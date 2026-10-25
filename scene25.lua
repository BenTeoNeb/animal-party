-- A 2.5D scene for LÖVE: a painted picture-book page seen at an angle, with
-- one camera for everything (see the scene-2-5d skill, SKILL.md).
--
--   local scene25 = require("scene25")
--   local S = scene25.new({ horizon = 230, far = 0.8, squash = 0.55 })
--   S:depth(y)                 how big things are drawn at height y (far .. 1)
--   S:offset(y)                how far they have scrolled (S.scroll * depth)
--   S:walk(x, y, dx, dy, speed, dt)   a step on the ground (slower away and far)
--   S:ground(image, tile)      the ground texture in perspective (one mesh)
--   S:band(image, y, h, f)     a far landscape strip, repeated, parallax f
--   S:shadow(x, y, w)          a soft shadow lying on the ground
--   S:floor(x1, x2, yFar, yNear)   the far corners of a flat thing on the ground
--   S:sort(list)               draw order: by the feet's y, stable
--   S:approach(v, target, dt)  a speed that changes gently (no jolt)
--
-- Coordinates are the game's own (e.g. 1280x720). The camera never moves up or
-- down and never zooms: only S.scroll changes, when the landscape goes by.

local scene25 = {}
scene25.__index = scene25

-- horizon: where the ground meets the backdrop (the far edge of the scene).
-- far: how big things are at the horizon (0.8: gentle; 0.6 made a kid sick).
-- squash: the ground seen at an angle, squashed from top to bottom (0.55 is a
-- camera looking down at about 33 degrees). exact: the ground is squashed a
-- little more far away (squash * depth), as a real camera would do.
function scene25.new(o)
    o = o or {}
    local S = setmetatable({}, scene25)
    S.W, S.H = o.width or 1280, o.height or 720
    S.horizon = o.horizon or 230
    S.far = o.far or 0.8
    S.squash = o.squash or 0.55
    S.exact = o.exact or false
    S.scroll = 0
    S.comfort = o.comfort or false     -- reduced motion: no far parallax, slower
    S.maxSpeed = o.maxSpeed or 280     -- landscape speed cap (px/s), for 5-7 year olds
    S.accel = o.accel or 150           -- px/s per second: about 2 s to full speed
    return S
end

function scene25:depth(y)
    local u = math.max(0, math.min(1, (y - self.horizon) / (self.H - self.horizon)))
    return self.far + (1 - self.far) * u
end

-- Things standing on the ground at height y go by at their own depth: that is
-- the exact parallax (a layer scrolling slower than its ground "slides").
function scene25:offset(y)
    return self.scroll * self:depth(y)
end

-- How much the ground is squashed from top to bottom at height y, compared
-- with across.
function scene25:squashAt(y)
    return self.exact and self.squash * self:depth(y) or self.squash
end

-- A step of something walking on the ground. dx, dy: the stick (-1..1).
-- Going up the screen is going away: slower by the ground's squash; and far
-- away everything is a little slower on the screen, like it is smaller.
function scene25:walk(x, y, dx, dy, speed, dt)
    local d = self:depth(y)
    return x + dx * speed * d * dt, y + dy * speed * self:squashAt(y) * d * dt
end

-- The ground's texture (a seamless tile), lying flat from the horizon to the
-- bottom of the screen, scrolled with the scene. tile: how wide one copy of
-- the texture is on the ground, at full size (front of the scene). One mesh,
-- rebuilt when the scroll changes: no strips, no stair steps at 4K.
local ROW = 4                          -- screen px between two rows of the mesh
function scene25:ground(image, tile)
    image:setWrap("repeat", "repeat")
    local rows = math.ceil((self.H - self.horizon) / ROW) + 1
    if not self.mesh or self.meshImage ~= image or self.meshTile ~= tile or self.meshScroll ~= self.scroll then
        local verts, v = {}, 0
        local cx = self.W / 2
        for i = 0, rows - 1 do
            local y = math.min(self.H, self.horizon + i * ROW)
            local d = self:depth(y)
            -- across: the screen x of the edges, back on the ground (in tiles)
            local u0 = ((0 - cx) / d + cx - self.scroll) / tile
            local u1 = ((self.W - cx) / d + cx - self.scroll) / tile
            verts[#verts + 1] = { 0, y, u0, v }
            verts[#verts + 1] = { self.W, y, u1, v }
            -- down: one screen px is 1 / (depth * squash) ground px
            v = v + ROW / (d * self:squashAt(y)) / tile
        end
        if self.mesh and self.meshRows == rows then
            self.mesh:setVertices(verts)
        else
            self.mesh = love.graphics.newMesh(verts, "strip", "dynamic")
            self.meshRows = rows
        end
        self.mesh:setTexture(image)
        self.meshImage, self.meshTile, self.meshScroll = image, tile, self.scroll
    end
    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(self.mesh)
end

-- A landscape strip far away (hills, a village), its bottom at y, h tall,
-- repeated with every other copy mirrored (so the joins match). f: its
-- parallax, the speed compared with the front (smaller than the ground's at
-- the horizon: it must stand behind something, never on the scrolling grass).
-- In comfort mode the far layers stand still.
function scene25:band(image, y, h, f)
    local sc = h / image:getHeight()
    local w = image:getWidth() * sc
    local dx = self.comfort and f < self:depth(self.horizon) and 0 or self.scroll * f
    local x = (dx % (2 * w)) - 2 * w
    local i = 0
    love.graphics.setColor(1, 1, 1)
    while x < self.W do
        if i % 2 == 0 then love.graphics.draw(image, x, y - h, 0, sc, sc)
        else love.graphics.draw(image, x + w, y - h, 0, -sc, sc) end
        x, i = x + w, i + 1
    end
end

-- A light haze just in front of the backdrop: it reads as distance (not as a
-- wall) and hides where the ground meets the backdrop.
-- One smooth gradient (a mesh), not bands: bands show as stripes.
function scene25:haze(h, color, alpha)
    local c = color or { 0.86, 0.93, 0.98 }
    local a = alpha or 0.42
    h = h or 120
    local key = table.concat({ h, c[1], c[2], c[3], a }, " ")
    if self.hazeKey ~= key then                    -- (made once, until it changes)
        local top, bottom = self.horizon - 4, self.horizon - 4 + h
        self.hazeMesh = love.graphics.newMesh({
            { 0, top, 0, 0, c[1], c[2], c[3], a }, { self.W, top, 0, 0, c[1], c[2], c[3], a },
            { self.W, bottom, 0, 0, c[1], c[2], c[3], 0 }, { 0, bottom, 0, 0, c[1], c[2], c[3], 0 },
        }, "fan", "static")
        self.hazeKey = key
    end
    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(self.hazeMesh)
end

-- A soft shadow lying on the ground under something w wide (at full size),
-- centered under its feet at (x, y): flattened like the ground.
function scene25:shadow(x, y, w, alpha)
    local d = self:depth(y)
    love.graphics.setColor(0, 0, 0, alpha or 0.2)
    love.graphics.ellipse("fill", x + self:offset(y), y, w * d / 2, w * d * self:squashAt(y) / 2)
end

-- A flat thing lying on the ground (a platform, a rug), from x1 to x2 at its
-- near edge yNear: its far edge at yFar is narrower, by the depth.
-- Returns the far edge's x1, x2.
function scene25:floor(x1, x2, yFar, yNear)
    local inset = (x2 - x1) * (1 - self:depth(yFar) / self:depth(yNear)) / 2
    return x1 + inset, x2 - inset
end

-- Draw order: further first (smaller y of the feet); equal y kept stable by
-- id (or x), so two sprites side by side never flicker.
function scene25:sort(list)
    table.sort(list, function(a, b)
        if a.y ~= b.y then return a.y < b.y end
        return (a.id or a.x or 0) < (b.id or b.x or 0)
    end)
end

-- A speed that goes toward target gently (at most accel px/s per second),
-- capped by maxSpeed (half in comfort mode). Use it for the scrolling.
function scene25:approach(v, target, dt)
    local cap = self.comfort and self.maxSpeed / 2 or self.maxSpeed
    target = math.max(-cap, math.min(cap, target))
    local step = self.accel * dt
    if v < target then return math.min(target, v + step) end
    return math.max(target, v - step)
end

return scene25
