-- art.lua: all the drawings, made with shapes in code. Every function draws
-- with the FEET at (x, y). f = facing (1 = right, -1 = left), s = size.

local art = {}
local g = love.graphics

-- Images from the images/ folder replace the drawings below when they exist
-- (e.g. images/renard.png). They must face RIGHT, with the feet at the bottom.
local images = {}

function art.image(name)
    if images[name] == nil then
        local path = "images/" .. name .. ".png"
        images[name] = love.filesystem.getInfo(path) and g.newImage(path, { mipmaps = true }) or false
        if images[name] then images[name]:setMipmapFilter("linear") end
    end
    return images[name]
end

-- Load every image and animation now (at launch), so the game never stops to
-- load one in the middle of a game (that made it stutter).
function art.preload()
    for _, file in ipairs(love.filesystem.getDirectoryItems("images")) do
        local name = file:match("^(.+)%.png$")
        if name and name:sub(1, 1) ~= "_" then art.image(name) end
        local anim = file:match("^(.+)%.lua$")
        if anim then art.anims(anim) end
    end
end

-- Draw an image with its feet at (x, y), `height` pixels tall, flipped if f = -1.
local function sprite(im, x, y, f, height, rot, tint)
    local sc = height / im:getHeight()
    g.setColor(tint or art.tint or { 1, 1, 1 })
    g.draw(im, x, y, rot or 0, sc * f, sc, im:getWidth() / 2, im:getHeight())
end

-- Animations made by outils/video.py: images/<name>.lua describes the strips
-- images/<name>_marche.png, <name>_course.png, ... (one row of frames each).
local anims = {}

function art.anims(name)
    if anims[name] == nil then
        anims[name] = false
        local path = "images/" .. name .. ".lua"
        if love.filesystem.getInfo(path) then
            local meta = love.filesystem.load(path)()
            for anim, a in pairs(meta.anims) do
                a.image = art.image(name .. "_" .. anim)
                if a.image then
                    a.quads = {}
                    local cols = a.cols or a.frames      -- frames laid out in rows of `cols`
                    for i = 0, a.frames - 1 do
                        a.quads[i + 1] = g.newQuad((i % cols) * meta.frameW, math.floor(i / cols) * meta.frameH,
                            meta.frameW, meta.frameH, a.image:getDimensions())
                    end
                end
            end
            anims[name] = meta
        end
    end
    return anims[name]
end

-- How long a one-shot animation lasts, in seconds (nil if there is none).
function art.duration(name, anim)
    local m = art.anims(name)
    local a = m and m.anims[anim]
    if a and a.image then return a.frames / m.fps end
end

-- Draw frame `t` seconds into an animation, feet at (x, y). Returns false if
-- this character has no animations, so the caller can draw something else.
local function animated(name, anim, t, x, y, f, height)
    local m = art.anims(name)
    if not m then return false end
    local a = m.anims[anim]
    if not (a and a.image) then a = m.anims.repos end
    if not (a and a.image) then return false end
    local i = math.floor((t or 0) * m.fps)
    if a.loop then i = i % a.frames else i = math.min(i, a.frames - 1) end
    local sc = height / m.height
    g.setColor(art.tint or { 1, 1, 1 })
    g.draw(a.image, a.quads[i + 1], x, y, 0, sc * f, sc, m.frameW / 2, m.baseline)
    return true
end

-- How tall each image is drawn (at size 1).
local HEIGHTS = {
    kid = 92, renard = 46, poule = 42, ecureuil = 46, marcassin = 38, herisson = 34,
    mouton = 43, biche = 60,
    -- the big mamas (event "big animal"): about as tall as Rami
    maman_renard = 92, maman_poule = 84, maman_ecureuil = 92, maman_marcassin = 96, maman_herisson = 76,
    arbre = 125, maison = 80, volcan = 230,
}

-- How tall an animal is drawn at size 1.
function art.height(kind)
    return HEIGHTS[kind] or 46
end

-- The tree species (images/<name>.png, and <name>_brule.png once the lava got
-- them), with how tall each one is drawn.
art.TREES = {
    baobab = 130, erable = 125, fruitier = 120, palmier = 140, cerisier = 115, sapin = 140,
    saule = 130, bouleau = 145, epicea = 150, chene = 135, peuplier = 155, pommier = 110,
}

-- Half-width of each trunk at its base, in pixels (for collisions).
art.TRUNKS = {
    baobab = 34, erable = 15, fruitier = 18, palmier = 9, cerisier = 14, sapin = 15,
    saule = 18, bouleau = 8, epicea = 14, chene = 22, peuplier = 12, pommier = 13,
}

-- The three kids. Here they all play the same (the game is about counting,
-- not about who is fastest):
--   speed: how fast they move (1 = normal), carry: how many animals can follow
--   them, reach: from how far they can call an animal (pixels).
-- The colors are only used if there are no drawings for them in images/.
local SPEED, CARRY, REACH = 1.1, 5, 110
art.KIDS = {
    { id = "rami", name = "Rami", size = 0.82, style = "short",
      speed = SPEED, carry = CARRY, reach = REACH,
      skin = { 0.96, 0.8, 0.65 }, hair = { 0.22, 0.14, 0.08 },
      top = { 0.25, 0.55, 0.95 }, bottom = { 0.15, 0.25, 0.5 } },
    { id = "zina", name = "Zina", size = 1.0, style = "puffs", dress = true,
      speed = SPEED, carry = CARRY, reach = REACH,
      skin = { 0.96, 0.8, 0.65 }, hair = { 0.14, 0.09, 0.06 },
      top = { 0.93, 0.42, 0.7 }, bow = { 1, 0.85, 0.2 } },
    { id = "lila", name = "Lila", size = 1.0, style = "long", dress = true,
      speed = SPEED, carry = CARRY, reach = REACH,
      skin = { 0.96, 0.8, 0.65 }, hair = { 0.5, 0.28, 0.12 },
      top = { 0.2, 0.75, 0.65 }, bow = { 0.95, 0.3, 0.4 } },
}

art.ANIMALS = {
    renard = "Renard", poule = "Poule", ecureuil = "Écureuil",
    marcassin = "Marcassin", herisson = "Hérisson", mouton = "Mouton", biche = "Biche",
}

local function shadow(x, y, w)
    g.setColor(0, 0, 0, 0.18)
    g.ellipse("fill", x, y, w, w * 0.3)
end

-- Kids -------------------------------------------------------------------------

-- anim: "repos", "marche", "course", "saut" or "aie"; t: seconds into it.
function art.kid(k, x, y, f, s, walk, anim, t)
    s = (s or 1) * k.size
    local swing = math.sin(walk or 0) * 6 * s
    shadow(x, y, 16 * s)
    if animated(k.id, anim or "repos", t, x, y, f, HEIGHTS.kid * s) then return end
    local im = art.image(k.id)
    if im then
        local bob = math.abs(math.sin(walk or 0)) * 4 * s
        sprite(im, x, y - bob, f, HEIGHTS.kid * s, math.sin(walk or 0) * 0.06)
        return
    end

    -- legs and shoes
    g.setColor(k.skin)
    g.setLineWidth(6 * s)
    g.line(x - 6 * s, y - 24 * s, x - 6 * s + swing, y - 4 * s)
    g.line(x + 6 * s, y - 24 * s, x + 6 * s - swing, y - 4 * s)
    g.setColor(0.35, 0.22, 0.15)
    g.ellipse("fill", x - 6 * s + swing + f * 2 * s, y - 3 * s, 6 * s, 3.5 * s)
    g.ellipse("fill", x + 6 * s - swing + f * 2 * s, y - 3 * s, 6 * s, 3.5 * s)

    local hx, hy = x, y - 64 * s
    if k.style == "long" then
        g.setColor(k.hair)
        g.ellipse("fill", hx - f * 2 * s, hy + 10 * s, 17 * s, 24 * s)
    end

    -- body
    if k.dress then
        g.setColor(k.top)
        g.polygon("fill", x - 9 * s, y - 48 * s, x + 9 * s, y - 48 * s,
            x + 17 * s, y - 20 * s, x - 17 * s, y - 20 * s)
        g.setColor(1, 1, 1, 0.35)
        g.rectangle("fill", x - 15 * s, y - 25 * s, 30 * s, 3 * s)
    else
        g.setColor(k.bottom)
        g.rectangle("fill", x - 11 * s, y - 32 * s, 22 * s, 11 * s, 3 * s)
        g.setColor(k.top)
        g.rectangle("fill", x - 12 * s, y - 50 * s, 24 * s, 22 * s, 6 * s)
        g.setColor(1, 1, 1, 0.8)
        g.circle("fill", x, y - 40 * s, 4 * s)
    end

    -- arms
    g.setColor(k.skin)
    g.setLineWidth(5 * s)
    g.line(x - 11 * s, y - 46 * s, x - 17 * s - swing * 0.6, y - 30 * s)
    g.line(x + 11 * s, y - 46 * s, x + 17 * s + swing * 0.6, y - 30 * s)

    -- head and hair
    g.setColor(k.skin)
    g.circle("fill", hx, hy, 15 * s)
    g.setColor(k.hair)
    g.arc("fill", hx, hy - 1 * s, 16 * s, math.pi, 2 * math.pi)
    if k.style == "short" then
        for i = -2, 2 do g.circle("fill", hx + i * 6 * s, hy - 13 * s, 5 * s) end
    elseif k.style == "puffs" then
        g.circle("fill", hx - 15 * s, hy - 14 * s, 9 * s)
        g.circle("fill", hx + 15 * s, hy - 14 * s, 9 * s)
    else
        g.ellipse("fill", hx - f * 9 * s, hy - 3 * s, 8 * s, 10 * s)
    end
    if k.bow then
        g.setColor(k.bow)
        local bx, by = hx - f * 6 * s, hy - 15 * s
        g.polygon("fill", bx, by, bx - 7 * s, by - 5 * s, bx - 7 * s, by + 5 * s)
        g.polygon("fill", bx, by, bx + 7 * s, by - 5 * s, bx + 7 * s, by + 5 * s)
        g.circle("fill", bx, by, 2.5 * s)
    end

    -- face
    local ex = hx + f * 3 * s
    g.setColor(0.15, 0.1, 0.08)
    g.circle("fill", ex - 5 * s, hy + 1 * s, 2.2 * s)
    g.circle("fill", ex + 5 * s, hy + 1 * s, 2.2 * s)
    g.setLineWidth(1.8 * s)
    g.arc("line", "open", ex, hy + 4 * s, 4.5 * s, 0.35, math.pi - 0.35)
    g.setColor(1, 0.5, 0.5, 0.55)
    g.circle("fill", ex - 9 * s, hy + 5 * s, 3 * s)
    g.circle("fill", ex + 9 * s, hy + 5 * s, 3 * s)
end

-- Animals ----------------------------------------------------------------------

local function legs(x, y, s, xs, color)
    g.setColor(color or { 0.3, 0.2, 0.12 })
    g.setLineWidth(3 * s)
    for _, lx in ipairs(xs) do g.line(x + lx * s, y - 7 * s, x + lx * s, y) end
end

local function eye(x, y, s)
    g.setColor(0.05, 0.05, 0.05)
    g.circle("fill", x, y, 2 * s)
    g.setColor(1, 1, 1)
    g.circle("fill", x + 0.7 * s, y - 0.7 * s, 0.7 * s)
end

local function fox(x, y, f, s)
    local orange = { 0.95, 0.5, 0.15 }
    g.setColor(orange)
    g.ellipse("fill", x - f * 20 * s, y - 15 * s, 13 * s, 7 * s)
    g.setColor(1, 1, 1)
    g.circle("fill", x - f * 30 * s, y - 16 * s, 5 * s)
    legs(x, y, s, { -8, 8 })
    g.setColor(orange)
    g.ellipse("fill", x, y - 13 * s, 15 * s, 10 * s)
    g.setColor(1, 1, 1)
    g.ellipse("fill", x + f * 9 * s, y - 11 * s, 6 * s, 6 * s)
    local hx, hy = x + f * 14 * s, y - 23 * s
    g.setColor(orange)
    g.polygon("fill", hx - 9 * s, hy - 3 * s, hx - 5 * s, hy - 16 * s, hx - 1 * s, hy - 4 * s)
    g.polygon("fill", hx + 1 * s, hy - 4 * s, hx + 5 * s, hy - 16 * s, hx + 9 * s, hy - 3 * s)
    g.circle("fill", hx, hy, 9 * s)
    g.setColor(1, 1, 1)
    g.polygon("fill", hx + f * 2 * s, hy - 1 * s, hx + f * 15 * s, hy + 3 * s, hx + f * 2 * s, hy + 7 * s)
    g.setColor(0, 0, 0)
    g.circle("fill", hx + f * 15 * s, hy + 3 * s, 2 * s)
    eye(hx + f * 3 * s, hy - 3 * s, s)
end

local function hen(x, y, f, s)
    legs(x, y, s, { -4, 4 }, { 1, 0.6, 0.1 })
    g.setColor(0.95, 0.95, 0.92)
    g.polygon("fill", x - f * 8 * s, y - 16 * s, x - f * 20 * s, y - 28 * s, x - f * 16 * s, y - 12 * s)
    g.circle("fill", x, y - 14 * s, 11 * s)
    g.setColor(0.85, 0.85, 0.82)
    g.ellipse("fill", x - f * 2 * s, y - 14 * s, 7 * s, 5 * s)
    local hx, hy = x + f * 8 * s, y - 26 * s
    g.setColor(0.95, 0.15, 0.15)
    g.circle("fill", hx - 3 * s, hy - 7 * s, 3 * s)
    g.circle("fill", hx + 1 * s, hy - 8 * s, 3 * s)
    g.circle("fill", hx + f * 6 * s, hy + 5 * s, 2.5 * s)
    g.setColor(0.95, 0.95, 0.92)
    g.circle("fill", hx, hy, 7 * s)
    g.setColor(1, 0.75, 0.1)
    g.polygon("fill", hx + f * 6 * s, hy - 2 * s, hx + f * 12 * s, hy + 1 * s, hx + f * 6 * s, hy + 3 * s)
    eye(hx + f * 2 * s, hy - 1 * s, s)
end

local function squirrel(x, y, f, s)
    g.setColor(0.88, 0.52, 0.22)
    g.circle("fill", x - f * 13 * s, y - 19 * s, 10 * s)
    g.circle("fill", x - f * 9 * s, y - 31 * s, 8 * s)
    g.circle("fill", x - f * 3 * s, y - 37 * s, 5 * s)
    legs(x, y, s, { -4, 5 })
    g.setColor(0.75, 0.4, 0.17)
    g.ellipse("fill", x, y - 11 * s, 10 * s, 9 * s)
    g.setColor(1, 0.85, 0.65)
    g.ellipse("fill", x + f * 4 * s, y - 10 * s, 5 * s, 6 * s)
    local hx, hy = x + f * 8 * s, y - 22 * s
    g.setColor(0.75, 0.4, 0.17)
    g.polygon("fill", hx - 4 * s, hy - 4 * s, hx - 2 * s, hy - 13 * s, hx + 2 * s, hy - 5 * s)
    g.circle("fill", hx, hy, 7 * s)
    g.setColor(0.2, 0.1, 0.05)
    g.circle("fill", hx + f * 7 * s, hy + 1 * s, 1.5 * s)
    eye(hx + f * 2 * s, hy - 2 * s, s)
end

local function piglet(x, y, f, s)
    legs(x, y, s, { -10, -4, 5, 11 }, { 0.35, 0.22, 0.14 })
    g.setColor(0.62, 0.42, 0.26)
    g.ellipse("fill", x, y - 13 * s, 17 * s, 11 * s)
    g.setColor(0.95, 0.85, 0.6)
    g.setLineWidth(2.5 * s)
    for i = -1, 1 do g.line(x - 12 * s, y - 13 * s + i * 5 * s, x + 9 * s, y - 13 * s + i * 5 * s) end
    g.setColor(0.62, 0.42, 0.26)
    g.setLineWidth(2 * s)
    g.line(x - f * 17 * s, y - 15 * s, x - f * 21 * s, y - 19 * s)
    local hx, hy = x + f * 16 * s, y - 15 * s
    g.polygon("fill", hx - 5 * s, hy - 5 * s, hx - 2 * s, hy - 13 * s, hx + 2 * s, hy - 6 * s)
    g.ellipse("fill", hx, hy, 9 * s, 8 * s)
    g.setColor(0.85, 0.6, 0.55)
    g.ellipse("fill", hx + f * 8 * s, hy + 2 * s, 4 * s, 4 * s)
    g.setColor(0.4, 0.2, 0.2)
    g.circle("fill", hx + f * 8 * s - 1.3 * s, hy + 2 * s, 0.9 * s)
    g.circle("fill", hx + f * 8 * s + 1.3 * s, hy + 2 * s, 0.9 * s)
    eye(hx + f * 2 * s, hy - 3 * s, s)
end

local function hedgehog(x, y, f, s)
    legs(x, y, s, { -6, 6 }, { 0.4, 0.3, 0.2 })
    g.setColor(0.35, 0.25, 0.18)
    local cx, cy = x - f * 3 * s, y - 10 * s
    for i = 0, 10 do
        local ang = math.pi * (1 + i / 10)
        local tx, ty = cx + math.cos(ang) * 22 * s, cy + math.sin(ang) * 18 * s
        local a1, a2 = ang - 0.18, ang + 0.18
        g.polygon("fill", tx, ty, cx + math.cos(a1) * 13 * s, cy + math.sin(a1) * 10 * s,
            cx + math.cos(a2) * 13 * s, cy + math.sin(a2) * 10 * s)
    end
    g.ellipse("fill", cx, cy, 16 * s, 11 * s)
    g.setColor(0.95, 0.85, 0.65)
    g.ellipse("fill", x + f * 12 * s, y - 8 * s, 8 * s, 6 * s)
    g.setColor(0, 0, 0)
    g.circle("fill", x + f * 20 * s, y - 8 * s, 2.5 * s)
    eye(x + f * 12 * s, y - 11 * s, s)
end

local DRAW = { renard = fox, poule = hen, ecureuil = squirrel, marcassin = piglet, herisson = hedgehog }

function art.animal(kind, x, y, f, s, withShadow, anim, t)
    s = s or 1
    if withShadow ~= false then shadow(x, y, (HEIGHTS[kind] or 46) * 0.35 * s) end
    if animated(kind, anim or "repos", t, x, y, f, HEIGHTS[kind] * s) then return end
    local im = art.image(kind)
    if im then
        -- no animation yet: waddle the still image while it moves
        local rot, hop = 0, 0
        if anim == "marche" then
            rot = math.sin((t or 0) * 12) * 0.08
            hop = math.abs(math.sin((t or 0) * 12)) * 3 * s
        elseif anim == "course" then
            rot = math.sin((t or 0) * 22) * 0.14
            hop = math.abs(math.sin((t or 0) * 22)) * 8 * s
        end
        sprite(im, x, y - hop, f, HEIGHTS[kind] * s, rot)
        return
    end
    (DRAW[kind] or DRAW.poule)(x, y, f, s)     -- (no drawing in code for the newer animals)
end

function art.heart(x, y, s, color)
    g.setColor(color or { 1, 0.3, 0.4 })
    g.circle("fill", x - 5 * s, y - 3 * s, 6 * s)
    g.circle("fill", x + 5 * s, y - 3 * s, 6 * s)
    g.polygon("fill", x - 10.5 * s, y - 1 * s, x + 10.5 * s, y - 1 * s, x, y + 11 * s)
end

function art.bolt(x, y, s)
    g.setColor(1, 0.85, 0.15)
    g.polygon("fill", x + 2 * s, y - 10 * s, x - 6 * s, y + 2 * s, x + 2 * s, y + 1 * s)
    g.polygon("fill", x - 2 * s, y + 10 * s, x + 6 * s, y - 2 * s, x - 2 * s, y - 1 * s)
    g.setColor(0.23, 0.14, 0.09)
    g.setLineWidth(1.5)
    g.polygon("line", x + 2 * s, y - 10 * s, x - 6 * s, y + 2 * s, x - 1 * s, y + 1 * s,
        x - 2 * s, y + 10 * s, x + 6 * s, y - 2 * s, x + 1 * s, y - 1 * s)
end

-- Controller button icons, as on the Steam Deck / Xbox-style pads (the 8BitDo
-- pads in X-input mode have the same layout). name: "a" (bottom button), "b"
-- (right button), "view" (Select), "menu" (Start), "lr" (shoulder buttons),
-- "dpad" (left / right). (x, y) is the center; returns the icon's width.
-- Fonts are made for the real size of the screen (the game is drawn at 1280x720
-- and scaled up), so text stays sharp up to 4K. art.fontScale is set by main.lua.
art.fontScale = 1
-- Two fonts (fonts/, SIL Open Font License): Andika, made for children who
-- learn to read (school-shaped letters and numbers), for every text and
-- number; Fredoka, round and chunky like the drawings, for titles and names
-- (face = "titre"). Without them, LÖVE's own font.
local FACES = { texte = "fonts/Andika-Bold.ttf", titre = "fonts/Fredoka-Bold.ttf" }
function art.font(size, face)
    local file = FACES[face or "texte"]
    if file and love.filesystem.getInfo(file) then
        return g.newFont(file, size, "normal", art.fontScale)
    end
    return g.newFont(size, "normal", art.fontScale)
end

-- The UI, drawn like the rest of the game: the same dark-brown outline, warm
-- wood and cream. art.panel: a wooden plank (for boxes, counters, signs);
-- art.paper: a cream face in a wooden frame (for the menu); art.disk: the one
-- look of the numbers on things (a round tag with the number), coloured:
art.OUTLINE = { 0.23, 0.14, 0.09 }
art.COLORS = {
    todo = { 1, 0.86, 0.4 },        -- yellow: still to do
    ok = { 0.62, 0.88, 0.5 },       -- green: right
    over = { 1, 0.55, 0.45 },       -- red: too many / not right
    plain = { 1, 0.97, 0.88 },      -- cream: just a number
    off = { 0.75, 0.73, 0.7 },      -- grey: not this one
}

local function roundBox(x, y, w, h, r, color, a)
    g.setColor(color[1], color[2], color[3], (color[4] or 1) * (a or 1))
    g.rectangle("fill", x, y, w, h, r)
end

function art.panel(x, y, w, h, a)
    a = a or 1
    local r = math.min(16, h / 2)
    roundBox(x + 2, y + 5, w, h, r, { 0, 0, 0, 0.22 }, a)                  -- shadow
    roundBox(x - 3, y - 3, w + 6, h + 6, r + 3, art.OUTLINE, a)
    roundBox(x, y, w, h, r, { 0.7, 0.46, 0.26 }, a)                         -- wood
    roundBox(x + 3, y + 3, w - 6, h * 0.42, r - 2, { 0.8, 0.57, 0.34 }, a)  -- light from the top
    g.setColor(0.55, 0.34, 0.18, 0.55 * a)                                  -- grain
    g.setLineWidth(2)
    for i = 1, math.floor(h / 14) do
        local ly = y + i * h / (math.floor(h / 14) + 1)
        local x1 = x + 12 + ((i * 37 + x) % 40)
        local x2 = x + w - 12 - ((i * 53 + y) % 50)
        if x2 > x1 + 20 then g.line(x1, ly, x2, ly) end
    end
end

function art.paper(x, y, w, h, a)
    art.panel(x, y, w, h, a)
    roundBox(x + 10, y + 10, w - 20, h - 20, 12, { 0.99, 0.95, 0.85 }, a)
end

-- A stepping stone with a number painted on it (images/gue1-3.png), its
-- middle at (x, y), w wide. kind: a glow under it for its state ("ok" green,
-- "todo" yellow, "start" blue, "over" red), or "off" (darker: not this one).
local GLOWS = { ok = { 0.5, 1, 0.4 }, todo = { 1, 0.85, 0.3 }, start = { 0.35, 0.65, 1 }, over = { 1, 0.45, 0.35 } }
function art.stone(n, x, y, w, kind, font, variant)
    local im = art.image("gue" .. ((variant or n) % 3 + 1))
    local h = im and w * im:getHeight() / im:getWidth() or w * 0.62
    local glow = GLOWS[kind]
    if glow then
        for i = 3, 1, -1 do
            g.setColor(glow[1], glow[2], glow[3], 0.22)
            g.ellipse("fill", x, y + h * 0.08, w * 0.5 + i * 7, h * 0.42 + i * 5)
        end
    end
    if im then
        local sc = w / im:getWidth()
        if kind == "off" then g.setColor(0.55, 0.55, 0.55) else g.setColor(1, 1, 1) end
        g.draw(im, x, y, 0, sc, sc, im:getWidth() / 2, im:getHeight() / 2)
    else
        g.setColor(art.OUTLINE)
        g.ellipse("fill", x, y, w / 2 + 3, h / 2 + 3)
        g.setColor(kind == "off" and { 0.55, 0.53, 0.5 } or { 0.8, 0.78, 0.74 })
        g.ellipse("fill", x, y, w / 2, h / 2)
    end
    -- the number, painted on the flat top (cream, with a dark outline)
    local text, ty = tostring(n), y - h * 0.12 - font:getHeight() / 2
    g.setFont(font)
    g.setColor(art.OUTLINE)
    for i = 0, 11 do
        local a = i / 12 * math.pi * 2
        g.printf(text, x - w / 2 + math.cos(a) * 2.5, ty + math.sin(a) * 2.5, w, "center")
    end
    if kind == "off" then g.setColor(0.75, 0.73, 0.7) else g.setColor(1, 0.96, 0.85) end
    g.printf(text, x - w / 2, ty, w, "center")
end

-- A number tag: a disk of colour `kind` (art.COLORS) with the number in dark
-- brown. font: the font for the number (its size goes with r).
function art.disk(text, x, y, r, kind, font, a)
    a = a or 1
    local c = art.COLORS[kind] or kind
    g.setColor(0, 0, 0, 0.2 * a)
    g.circle("fill", x + 1, y + 3, r + 3)
    g.setColor(art.OUTLINE[1], art.OUTLINE[2], art.OUTLINE[3], a)
    g.circle("fill", x, y, r + 3)
    g.setColor(c[1], c[2], c[3], a)
    g.circle("fill", x, y, r)
    g.setColor(1, 1, 1, 0.35 * a)
    g.arc("fill", x, y, r * 0.8, math.pi * 1.1, math.pi * 1.6)             -- a little shine
    g.setFont(font)
    g.setColor(art.OUTLINE[1], art.OUTLINE[2], art.OUTLINE[3], a)
    g.printf(tostring(text), x - r * 2, y - font:getHeight() / 2, r * 4, "center")
end

local glyphFont
function art.resetFonts() glyphFont = nil end

function art.glyph(name, x, y, s)
    s = s or 1
    local previous = g.getFont()
    glyphFont = glyphFont or art.font(15)
    g.setFont(glyphFont)
    local w = art.drawGlyph(name, x, y, s)
    g.setFont(previous)
    return w
end

function art.drawGlyph(name, x, y, s)
    local dark = { 0.15, 0.12, 0.1 }
    g.setLineWidth(2 * s)
    if name == "a" or name == "b" then
        g.setColor(name == "a" and { 0.35, 0.75, 0.3 } or { 0.85, 0.3, 0.25 })
        g.circle("fill", x, y, 13 * s)
        g.setColor(dark)
        g.circle("line", x, y, 13 * s)
        g.setColor(1, 1, 1)
        local f = g.getFont()
        local label = name == "a" and "A" or "B"
        g.print(label, x - f:getWidth(label) / 2, y - f:getHeight() / 2)
        return 28 * s
    elseif name == "view" or name == "menu" then
        g.setColor(0.95, 0.95, 0.95)
        g.circle("fill", x, y, 13 * s)
        g.setColor(dark)
        g.circle("line", x, y, 13 * s)
        if name == "view" then
            g.rectangle("line", x - 6 * s, y - 5 * s, 8 * s, 7 * s, 1.5 * s)
            g.rectangle("fill", x - 2 * s, y - 2 * s, 8 * s, 7 * s, 1.5 * s)
        else
            for i = -1, 1 do g.rectangle("fill", x - 6 * s, y + i * 4 * s - 1 * s, 12 * s, 2.2 * s) end
        end
        return 28 * s
    elseif name == "lr" then
        for i, dx in ipairs({ -15, 15 }) do
            g.setColor(0.95, 0.95, 0.95)
            g.rectangle("fill", x + dx * s - 13 * s, y - 8 * s, 26 * s, 16 * s, 7 * s)
            g.setColor(dark)
            g.rectangle("line", x + dx * s - 13 * s, y - 8 * s, 26 * s, 16 * s, 7 * s)
            local f = g.getFont()
            local label = i == 1 and "L" or "R"
            g.print(label, x + dx * s - f:getWidth(label) / 2, y - f:getHeight() / 2)
        end
        return 60 * s
    elseif name == "dpad" then
        g.setColor(0.95, 0.95, 0.95)
        g.rectangle("fill", x - 16 * s, y - 6 * s, 32 * s, 12 * s, 3 * s)
        g.rectangle("fill", x - 6 * s, y - 16 * s, 12 * s, 32 * s, 3 * s)
        g.setColor(dark)
        g.polygon("fill", x - 14 * s, y, x - 9 * s, y - 4 * s, x - 9 * s, y + 4 * s)
        g.polygon("fill", x + 14 * s, y, x + 9 * s, y - 4 * s, x + 9 * s, y + 4 * s)
        return 34 * s
    end
    return 0
end

-- Draw a line of icons and words, centered on cx: parts = { "@a", "text", ... }
-- (a part starting with @ is an icon, see art.glyph). font: for the words.
function art.hint(parts, cx, y, font, color)
    g.setFont(font)
    local widths, total = {}, 0
    for i, p in ipairs(parts) do
        local icon = p:sub(1, 1) == "@" and p:sub(2)
        widths[i] = icon and (icon == "lr" and 62 or icon == "dpad" and 36 or 30) or font:getWidth(p) + 10
        total = total + widths[i]
    end
    local x = cx - total / 2
    art.panel(x - 14, y - 21, total + 28, 42)          -- on a little plank
    for i, p in ipairs(parts) do
        if p:sub(1, 1) == "@" then
            art.glyph(p:sub(2), x + widths[i] / 2, y)
        else
            g.setColor(0.15, 0.08, 0.05, 0.85)
            for i = 0, 11 do
                local a = i / 12 * math.pi * 2
                g.print(p, x + 5 + math.cos(a) * 2.2, y - font:getHeight() / 2 + math.sin(a) * 2.2)
            end
            g.setColor(color or { 1, 1, 1 })
            g.print(p, x + 5, y - font:getHeight() / 2)
        end
        x = x + widths[i]
    end
end

function art.star(x, y, r, filled)
    local pts = {}
    for i = 0, 9 do
        local ang = -math.pi / 2 + i * math.pi / 5
        local rr = i % 2 == 0 and r or r * 0.45
        table.insert(pts, x + math.cos(ang) * rr)
        table.insert(pts, y + math.sin(ang) * rr)
    end
    if filled then g.setColor(1, 0.85, 0.15) else g.setColor(0.45, 0.3, 0.18, 0.45) end
    -- a star is concave: draw it as triangles from the middle
    for i = 0, 9 do
        local j = (i + 1) % 10
        g.polygon("fill", x, y, pts[i * 2 + 1], pts[i * 2 + 2], pts[j * 2 + 1], pts[j * 2 + 2])
    end
end

-- Scenery ----------------------------------------------------------------------

-- The grass drawing (images/herbe.png), repeated as tiles `tile` pixels wide
-- over a w x h area. Returns false if there is no grass drawing.
local grassQuads = {}
function art.grass(w, h, tile)
    local im = art.image("herbe")
    if not im then return false end
    local key = w .. "x" .. h .. "@" .. tile
    if not grassQuads[key] then
        im:setWrap("repeat", "repeat")
        local sc = tile / im:getWidth()
        grassQuads[key] = { g.newQuad(0, 0, w / sc, h / sc, im:getWidth(), im:getHeight()), sc }
    end
    local q = grassQuads[key]
    g.setColor(1, 1, 1)
    g.draw(im, q[1], 0, 0, 0, q[2], q[2])
    return true
end

-- Little forest things scattered on the ground (images/<name>.png), with how
-- tall each is drawn and how often it appears.
art.PROPS = {
    fleurs = { 26, 18 }, feuille = { 13, 10 }, champignon = { 22, 8 }, fougere = { 32, 8 },
    rocher = { 22, 6 }, buisson = { 32, 6 }, glands = { 18, 6 }, pomme_de_pin = { 16, 6 },
    branche = { 16, 6 }, buche = { 24, 3 },
}

-- A random prop name, the common ones more often.
function art.randomProp()
    local total = 0
    for _, p in pairs(art.PROPS) do total = total + p[2] end
    local r = love.math.random() * total
    local names = {}
    for name in pairs(art.PROPS) do table.insert(names, name) end
    table.sort(names)
    for _, name in ipairs(names) do
        r = r - art.PROPS[name][2]
        if r <= 0 then return name end
    end
    return names[1]
end

function art.prop(name, x, y, f, s)
    local im = art.image(name)
    if not im then return end
    s = s or 1
    if art.PROPS[name][1] > 20 then shadow(x, y, art.PROPS[name][1] * 0.5 * s) end
    sprite(im, x, y, f or 1, art.PROPS[name][1] * s)
end

-- kind: one of art.TREES; f: 1 or -1 to mirror it for variety.
function art.tree(x, y, s, burnt, kind, f)
    shadow(x, y, 30 * s)
    local im = kind and art.image(kind)
    if im then
        local height = (art.TREES[kind] or HEIGHTS.arbre) * s
        local charred = burnt and art.image(kind .. "_brule")
        if charred then
            sprite(charred, x, y, f or 1, height)
        else
            sprite(im, x, y, f or 1, height, 0, burnt and { 0.25, 0.2, 0.2 } or nil)
        end
        return
    end
    if burnt then
        g.setColor(0.2, 0.15, 0.13)
        g.rectangle("fill", x - 7 * s, y - 30 * s, 14 * s, 30 * s, 3 * s)
        return
    end
    g.setColor(0.5, 0.33, 0.2)
    g.rectangle("fill", x - 7 * s, y - 40 * s, 14 * s, 40 * s, 3 * s)
    g.setColor(0.18, 0.5, 0.22)
    g.circle("fill", x - 18 * s, y - 55 * s, 22 * s)
    g.circle("fill", x + 18 * s, y - 55 * s, 22 * s)
    g.circle("fill", x, y - 75 * s, 26 * s)
    g.setColor(0.28, 0.65, 0.3)
    g.circle("fill", x - 8 * s, y - 80 * s, 13 * s)
    g.circle("fill", x - 22 * s, y - 60 * s, 9 * s)
end

function art.flower(x, y, color)
    g.setColor(color)
    for i = 0, 4 do
        local ang = i / 5 * math.pi * 2
        g.circle("fill", x + math.cos(ang) * 4, y + math.sin(ang) * 4, 3.2)
    end
    g.setColor(1, 0.9, 0.3)
    g.circle("fill", x, y, 2.5)
end

function art.mushroom(x, y)
    g.setColor(0.95, 0.92, 0.85)
    g.rectangle("fill", x - 3, y - 10, 6, 10, 2)
    g.setColor(0.9, 0.2, 0.2)
    g.arc("fill", x, y - 9, 10, math.pi, 2 * math.pi)
    g.setColor(1, 1, 1)
    g.circle("fill", x - 4, y - 14, 2)
    g.circle("fill", x + 4, y - 13, 1.6)
end

-- mood: "calme", "surpris", "fume" or "erupt" (images/volcan_<mood>.png).
-- The four drawings have the same base width but not the same height (smoke,
-- lava fountain), so they are scaled by width to keep the same mountain.
-- width: how wide it is drawn (260 by default).
function art.volcano(x, y, t, glow, mood, width)
    local im = art.image("volcan_" .. (mood or "calme")) or art.image("volcan_calme")
    if im then
        local sc = (width or 260) / im:getWidth()
        local wobble = mood == "erupt" and math.sin(t * 40) * 0.015 or 0
        g.setColor(1, 1, 1)
        g.draw(im, x, y, wobble, sc, sc * (mood == "fume" and 1 + math.sin(t * 6) * 0.02 or 1),
            im:getWidth() / 2, im:getHeight())
        return
    end
    g.setColor(0.4, 0.3, 0.27)
    g.polygon("fill", x - 150, y, x + 150, y, x + 45, y - 175, x - 45, y - 175)
    g.setColor(0.33, 0.24, 0.22)
    g.polygon("fill", x - 150, y, x - 60, y, x - 18, y - 175, x - 45, y - 175)
    g.setColor(0.48, 0.37, 0.32)
    g.polygon("fill", x + 60, y, x + 150, y, x + 45, y - 175, x + 25, y - 175)
    -- lava running down
    local pulse = 0.5 + 0.5 * math.sin(t * 4)
    g.setColor(1, 0.4 + pulse * 0.15, 0.05)
    g.polygon("fill", x - 25, y - 175, x - 5, y - 175, x - 30, y - 60, x - 55, y)
    g.polygon("fill", x + 10, y - 175, x + 28, y - 175, x + 50, y - 80, x + 35, y)
    g.ellipse("fill", x, y - 175, 46, 12)
    g.setColor(1, 0.85, 0.3, 0.6 + 0.4 * glow)
    g.ellipse("fill", x, y - 176, 34, 7)
end

-- img: the drawing to use (an image name); otherwise images/maison_<name>.png.
function art.hut(x, y, roof, name, img)
    local im = (img and art.image(img)) or (name and art.image("maison_" .. name))
    if im then
        sprite(im, x - 10, y + 10, 1, HEIGHTS.maison)
        return
    end
    g.setColor(0.72, 0.5, 0.3)
    g.rectangle("fill", x - 30, y - 34, 60, 34)
    g.setColor(0.6, 0.4, 0.22)
    g.setLineWidth(2)
    for i = 1, 3 do g.line(x - 30, y - 34 + i * 9, x + 30, y - 34 + i * 9) end
    g.setColor(roof)
    g.polygon("fill", x - 40, y - 32, x + 40, y - 32, x, y - 70)
    g.setColor(0.35, 0.22, 0.12)
    g.rectangle("fill", x - 9, y - 22, 18, 22, 6)
end

-- The entrance of the pens, on the side facing the meadow (r.gate): on the
-- left side from 20% to 85% of the height, on the top or bottom side from
-- 32% to 68% of the width.
art.PEN_GAP = { 0.2, 0.85 }
art.PEN_GAP_H = { 0.32, 0.68 }

-- The fence drawings: a front section, a lone post and an open gate.
local FENCE_H = 30         -- height of the fence, in pixels

-- A row of front fence sections between x1 and x2, feet at y.
local function fenceRow(x1, x2, y)
    local im = art.image("barriere_face")
    local n = math.max(1, math.floor((x2 - x1) / 52 + 0.5))
    local w = (x2 - x1) / n
    local sy = FENCE_H / im:getHeight()
    local sx = (w + 6) / im:getWidth()
    g.setColor(1, 1, 1)
    for i = 0, n - 1 do
        g.draw(im, x1 + (i + 0.5) * w, y, 0, sx, sy, im:getWidth() / 2, im:getHeight())
    end
end

local function post(x, y)
    local im = art.image("poteau")
    local sc = (FENCE_H + 2) / im:getHeight()
    g.setColor(1, 1, 1)
    g.draw(im, x, y, 0, sc, sc, im:getWidth() / 2, im:getHeight())
end

-- A row with the entrance in the middle (a post on each side of it).
local function gateRow(r, y)
    local x1, x2 = r.x + r.w * art.PEN_GAP_H[1], r.x + r.w * art.PEN_GAP_H[2]
    fenceRow(r.x, x1, y)
    fenceRow(x2, r.x + r.w, y)
    post(x1, y)
    post(x2, y)
end

-- A column of posts with a rail between them, from y1 to y2, at x.
local function fenceColumn(x, y1, y2)
    local n = math.max(1, math.floor((y2 - y1) / 26 + 0.5))
    local step = (y2 - y1) / n
    for i = 0, n - 1 do        -- the rails, behind the posts
        local a, b = y1 + i * step - FENCE_H * 0.7, y1 + (i + 1) * step - FENCE_H * 0.35
        g.setColor(0.23, 0.14, 0.09)
        g.rectangle("fill", x - 3.5, a, 7, b - a, 3)
        g.setColor(0.9, 0.66, 0.45)
        g.rectangle("fill", x - 2, a + 1, 4, b - a - 2, 2)
    end
    for i = 0, n do post(x, y1 + i * step) end
end

-- A fenced pen. r.gate: the side of the entrance, "left" (default), "top" or
-- "bottom". r.top = false: no fence on top (the pen above already has one).
-- r.hutX, r.hutY: where the hut stands (top right by default).
function art.pen(r)
    g.setColor(0.9, 0.82, 0.5, 0.55)
    g.rectangle("fill", r.x, r.y, r.w, r.h, 10)
    local hx, hy = r.hutX or r.x + r.w - 45, r.hutY or r.y + 75
    local gate = r.gate or "left"
    if art.image("barriere_face") and art.image("poteau") then
        local top, bottom = r.y + 6, r.y + r.h - 2
        local gapTop, gapBottom = r.y + r.h * art.PEN_GAP[1], r.y + r.h * art.PEN_GAP[2]
        if gate == "top" then gateRow(r, top)
        elseif r.top ~= false then fenceRow(r.x, r.x + r.w, top) end
        fenceColumn(r.x + r.w, top, bottom)
        if gate == "left" then
            fenceColumn(r.x, top, gapTop)
            art.hut(hx, hy, r.roof, r.name, r.hut)
            fenceColumn(r.x, gapBottom, bottom)
            local im = art.image("portillon")
            if im then   -- the open gate at the entrance
                local sc = (FENCE_H + 14) / im:getHeight()
                g.setColor(1, 1, 1)
                g.draw(im, r.x - 4, gapBottom, 0, sc, sc, im:getWidth() * 0.2, im:getHeight())
            end
        else
            fenceColumn(r.x, top, bottom)
            art.hut(hx, hy, r.roof, r.name, r.hut)
        end
        if gate == "bottom" then gateRow(r, bottom) else fenceRow(r.x, r.x + r.w, bottom) end
        return
    end
    art.hut(hx, hy, r.roof, r.name, r.hut)
    g.setColor(0.55, 0.36, 0.2)
    g.setLineWidth(4)
    g.rectangle("line", r.x, r.y, r.w, r.h, 6)
end

return art
