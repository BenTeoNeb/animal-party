-- train.lua: the Animal Train. Animals wearing a number wait in the meadow:
-- call them in order (1, 2, 3...) and lead them onto the platform, where each
-- one climbs into its wagon (the wagons have the numbers painted on). Only
-- the next number follows you: another one shakes its head. Levels:
--   1  count up from 1 (to 3, 4 or 5)
--   2  count up from another number (five numbers from 2 to 5), with a
--      couple of numbers around them that are not in the train
--   3  count down to 1 (from 5 to 8), and the train leaves: "3, 2, 1, go!"
-- When the train is full it waits and its engine sparkles: a kid who walks
-- up to it climbs into the cab and drives it away (left on the stick goes,
-- right slows down, the bottom button whistles). If nobody comes, it leaves
-- by itself after a moment.
-- world.lua calls the hooks below at the right moments (see MODES there).

local art = require("art")
local sfx = require("sfx")
local lang = require("lang")
local input = require("input")

local train = {}
local W, ctx
local g = love.graphics

-- The train (images/train_*.png): the engine at the left end, facing left,
-- and the wagons behind it, read in order left to right (1 2 3 4 5), the
-- whole train in the middle of the screen. The platform is behind the rails:
-- walk onto it to board the train.
local RAIL_Y = 702             -- the bottom of the wheels
local PLATFORM_Y = 586         -- walk onto the platform (below this, along the train) to board it
local PLATFORM_EDGE = 672      -- where its top ends and its front face starts, above the rails
local LOCO_W, WAGON_W = 180, 112
local WAGON_GAP = 120          -- from one wagon to the next
local SEAT_Y = RAIL_Y - 58     -- where the animals stand in their wagon (just above its
                               -- side: the whole animal shows)
local WAGONS = { "train_wagon_rouge", "train_wagon_bleu", "train_wagon_jaune", "train_wagon_vert" }
local LOCO_X = 640             -- the engine's middle (set for each train, see newRound)
local HINT_AFTER = 10          -- seconds without finding the next one: it sparkles
local BOARD_GAP = 0.45         -- seconds between two animals sitting down (time to count)

train.START_X, train.START_Y = 640, 450
-- The scene is in 2.5D, like a painted picture-book page: a sky, far hills
-- with a village (images/train_loin.png), a row of trees (train_milieu.png),
-- then the meadow in perspective down to the platform. Things further up the
-- screen (further away) are drawn smaller (train.depth). When the train
-- drives off, the landscape scrolls by, the far layers slower (parallax).
-- One camera for everything: the ground, the animals, the kids and the
-- trees all follow train.depth (80 % at the horizon, full size at the
-- bottom: a gentle perspective); the ground is also squashed from top to
-- bottom (FORESHORTEN: it lies flat, seen at an angle), and moving up the
-- screen (away) is slower than moving across (Y_SPEED).
local HORIZON = 230            -- where the meadow meets the trees
local FAR_SCALE = 0.8          -- how big things are at the horizon
local FORESHORTEN = 0.55       -- the ground seen at an angle: squashed from top to bottom
train.Y_SPEED = FORESHORTEN    -- walking up or down the screen, compared with across (the
                               -- ground's squash; and further away, slower: world.lua)
train.MIN_Y = HORIZON + 40     -- the kids' feet stay on the meadow (not in the trees or the sky)
train.NO_POND = true           -- (the pond is drawn from above: not in this side view)
-- The three parts of the meadow (the rails take the bottom); their feet stay
-- below the trees on the horizon.
train.ZONES = {
    { x1 = 470, y1 = 268, x2 = 810, y2 = 340 },      -- top, below the trees
    { x1 = 16, y1 = 268, x2 = 450, y2 = 520 },       -- left
    { x1 = 830, y1 = 268, x2 = 1264, y2 = 520 },     -- right
}

-- How big things are drawn at height y on the screen (1: near, smaller far).
function train.depth(y)
    local u = math.max(0, math.min(1, (y - HORIZON) / (720 - HORIZON)))
    return FAR_SCALE + (1 - FAR_SCALE) * u
end

-- How far things at height y have moved to the right while the train drives
-- away (the camera follows the train: near things go by faster).
function train.offset(y)
    return (W.scroll or 0) * train.depth(y)
end
local SPREAD = 150             -- the numbered animals stand at least this far apart

-- ctx: helpers from world.lua (newAnimal, biomeSpot, moveToward, popup,
-- hearts, stars, outlined, fonts, journal, KINDS, shuffle, rand).
function train.setup(world, c)
    W, ctx = world, c
end

local function wagonX(i)
    return LOCO_X + LOCO_W / 2 + WAGON_GAP / 2 + (i - 1) * WAGON_GAP + (W.trainShift or 0)
end

-- The ladder of steps (adaptive, see progress.lua): the train's numbers.
-- from: the first number (a range); len: how many wagons; by: the step
-- between two numbers (-1 counts down, 10 counts by tens); decoys: numbers
-- around it that are not in the train.
train.STEPS = {
    { from = { 1, 1 }, len = { 3, 3 }, by = 1 },
    { from = { 1, 1 }, len = { 4, 5 }, by = 1 },
    { from = { 1, 1 }, len = { 6, 7 }, by = 1 },
    { from = { 2, 5 }, len = { 5, 5 }, by = 1, decoys = true },
    { from = { 6, 14 }, len = { 5, 5 }, by = 1, decoys = true },
    { from = { 5, 5 }, len = { 5, 5 }, by = -1, decoys = true },
    { from = { 7, 9 }, len = { 7, 9 }, by = -1, decoys = true },
    { from = { 10, 10 }, len = { 5, 6 }, by = 10, decoys = true },
}
train.UP = 2                   -- clean trains in a row to go up a step

local function sequenceFor(step)
    local st = train.STEPS[step]
    local first = love.math.random(st.from[1], st.from[2])
    local len = love.math.random(st.len[1], st.len[2])
    if st.by < 0 then len = math.min(len, first) end       -- (down to 1, not below)
    local seq = {}
    for i = 0, len - 1 do seq[#seq + 1] = first + i * st.by end
    return seq, st
end

function train.newRound(level)
    local seq, st = sequenceFor(level)
    W.trainClean = true
    W.seq, W.trainShift, W.hintT, W.boardNope, W.seatedAt = seq, 0, 0, 0, -9
    W.scroll = 0
    W.drive = nil
    for _, k in ipairs(W.kids) do k.driving = nil end
    LOCO_X = 640 - (LOCO_W + #seq * WAGON_GAP) / 2 + LOCO_W / 2      -- the train in the middle
    local numbers = { unpack(seq) }
    -- decoys: numbers just around the train's, that are not in it
    if st.decoys then
        local by = st.by
        local before, after = seq[1] - by, seq[#seq] + by
        if before >= 1 then table.insert(numbers, before) end
        if after >= 1 then table.insert(numbers, after) end
        if #numbers == #seq + 1 then table.insert(numbers, seq[#seq] + 2 * by > 0 and seq[#seq] + 2 * by or seq[1] - 2 * by) end
    end
    local kinds = ctx.shuffle({ unpack(ctx.KINDS) })
    -- each one on its own spot, as far as possible from the others (so only
    -- one is in reach at a time); it only moves a little around it
    for i, n in ipairs(numbers) do
        local a = ctx.newAnimal(kinds[(i - 1) % #kinds + 1])
        a.number = n
        local bx, by, bd = nil, nil, -1
        for _ = 1, 30 do
            ctx.biomeSpot(a)
            local d = math.huge
            for _, b in ipairs(W.animals) do d = math.min(d, ctx.dist(a, b)) end
            if d > bd then bx, by, bd = a.x, a.y, d end
            if d >= SPREAD then break end
        end
        a.x, a.y, a.tx, a.ty = bx, by, bx, by
        a.spotX, a.spotY = bx, by
        table.insert(W.animals, a)
    end
    ctx.journal.log("manche", { niveau = level, train = seq })
end

-- The place in the train of the next number to find (nil: all found).
local function nextIndex()
    for i, n in ipairs(W.seq) do
        for _, a in ipairs(W.animals) do
            if a.number == n and a.state == "free" then return i end
        end
    end
end

function train.nextNumber()
    local i = nextIndex()
    return i and W.seq[i]
end

local function slotOf(n)
    for i, m in ipairs(W.seq) do
        if m == n then return i end
    end
end

-- A kid calls the nearest animal (best): only the next number follows, and
-- says its number; another one shakes its head, and the next number on the
-- board too. The train takes them all (no limit to how many follow).
function train.grab(k, a, fresh)
    if not a then return end
    if a.number == nil or a.number ~= train.nextNumber() then
        if fresh then
            a.nope, W.boardNope = 0.6, 0.6
            sfx.play("full")
            W.trainClean = false
        end
        return
    end
    a.vx, a.vy, a.state = 0, 0, "follow"
    table.insert(k.followers, a)
    ctx.hearts(a.x, a.y - 40, 1)
    W.hintT = 0
    sfx.count(a.number, lang.current)
    ctx.popup(tostring(a.number), a.x, a.y - art.height(a.kind) * 1.2 - 50, { 1, 0.9, 0.4 })
    ctx.journal.log("attrape", { joueur = k.player, numero = a.number })
end

-- A kid on the platform: the animals following them go to their wagons.
function train.arrive(k)
    local x1, x2 = train.platformX()
    if k.y < PLATFORM_Y or k.x < x1 or k.x > x2 or #k.followers == 0 then return end
    for _, a in ipairs(k.followers) do
        a.state, a.slot, a.seated = "board", slotOf(a.number), false
        ctx.journal.log("monte", { joueur = k.player, numero = a.number })
    end
    k.followers = {}
end

-- An animal going to its wagon (state "board"), then sitting in it.
function train.updateAnimal(a, dt)
    local x, y = wagonX(a.slot), SEAT_Y
    if a.seated then
        a.x, a.y, a.facing, a.moving = x, y, -1, false
        return
    end
    if not ctx.moveToward(a, x, y, 170, dt) then
        a.walk = 0
        -- sitting down, one after the other: say its number
        if W.time - W.seatedAt >= BOARD_GAP then
            a.seated, W.seatedAt = true, W.time
            sfx.count(a.number, lang.current)
            ctx.popup(tostring(a.number), x, y - 110, { 0.6, 1, 0.5 })
            ctx.hearts(x, y - 50, 2)
        end
    end
end

-- Everybody in the train?
function train.done()
    for _, n in ipairs(W.seq) do
        local ok = false
        for _, a in ipairs(W.animals) do
            if a.number == n and a.state == "board" and a.seated then ok = true end
        end
        if not ok then return false end
    end
    return true
end

local smoke = {}               -- the engine's puffs of smoke
local DRIVE_WAIT = 6           -- seconds the full train waits for a driver
-- Driving, gently (6-9 year olds are the most prone to motion sickness): the
-- speed changes by at most DRIVE_ACCEL a second (no jolt), up to DRIVE_SPEED.
-- At the end of the trip the landscape stops and the train rolls on, off the
-- left of the screen, before the fade.
local DRIVE_SPEED = 280        -- the train's top speed, pixels a second
local DRIVE_ACCEL = 150        -- pixels a second, per second (about 2 s to full speed)
local CAMERA_LOCO_X = 250      -- where the engine stays while the landscape goes by
local TRIP = 1700              -- how far it goes before the next train
local CAB_NEAR = 120           -- how close to the engine a kid climbs in

function train.party()
    ctx.answer(W.trainClean)
    sfx.play("toot")
    ctx.stars(wagonX(1), RAIL_Y - 90, 14)
    W.drive = { wait = 0, speed = 0, near = {} }
    for _, k in ipairs(W.kids) do                  -- (already next to it: not by accident)
        W.drive.near[k] = math.abs(k.x - LOCO_X) < CAB_NEAR * 0.7 and k.y > PLATFORM_Y - 40
    end
end

train.partyMove = true         -- the kids may walk up to the engine
function train.busy()          -- the party lasts until the train has left
    return W.drive and not W.drive.gone
end

local function climbIn(k)
    local d = W.drive
    d.by, k.driving = k, true
    k.followers = {}
    sfx.play("toot")
    ctx.journal.log("conduit", { joueur = k.player })
end

-- The bottom button: in the cab, the whistle; next to the engine, climb in.
function train.partyAction(k, action)
    local d = W.drive
    if not d or d.gone or action ~= "grab" then return end
    if d.by == k then
        sfx.play("toot")
    elseif not d.by and math.abs(k.x - LOCO_X) < CAB_NEAR and k.y > PLATFORM_Y - 60 then
        climbIn(k)
    end
end

-- The full train: waiting for a driver, driven, or leaving by itself; when
-- the whole train is off the screen, the driver gets off at the start.
local function updateDrive(dt)
    local d = W.drive
    if not d or d.gone then return end
    if not d.by and not d.auto then
        d.wait = d.wait + dt
        for _, k in ipairs(W.kids) do              -- walking up to the engine: climb in
            local near = math.abs(k.x - LOCO_X - W.trainShift) < CAB_NEAR * 0.7 and k.y > PLATFORM_Y - 40
            if near and not d.near[k] and not d.by then climbIn(k) end
            d.near[k] = near
        end
        if not d.by and d.wait > DRIVE_WAIT then d.auto = true end
    end
    local want = 0
    if d.by then
        local dx = input.move(d.by.player)
        want = dx < -0.2 and -DRIVE_SPEED or dx > 0.2 and 0 or d.speed       -- left goes, right brakes
    elseif d.auto then
        want = -DRIVE_SPEED
    end
    if (W.scroll or 0) >= TRIP then want = -DRIVE_SPEED end   -- the end: it goes, whatever the stick
    local step = DRIVE_ACCEL * dt
    d.speed = d.speed + math.max(-step, math.min(step, want - d.speed))
    -- the train rolls to the left of the screen, then stays there and the
    -- landscape goes by instead (the camera follows it); at the end of the
    -- trip, the landscape stops and the train rolls on, off the screen
    local move = d.speed * dt
    local room = (CAMERA_LOCO_X - LOCO_X) - W.trainShift       -- (negative: how far it can still go)
    local roll = math.max(move, math.min(0, room))
    if (W.scroll or 0) >= TRIP then roll = move end
    W.trainShift = math.min(0, W.trainShift + roll)
    W.scroll = (W.scroll or 0) - (move - roll)
    if d.speed < -20 and love.math.random() < dt * 12 then
        table.insert(smoke, { x = LOCO_X - 36 + W.trainShift, y = RAIL_Y - 128, r = 10, life = 1.2 })
    end
    if wagonX(#W.seq) + WAGON_W < 0 then                     -- off the screen: the driver gets off
        d.gone = true
        if d.by then
            d.by.driving = nil
            d.by.x, d.by.y = train.START_X, train.START_Y
        end
    end
end

function train.update(dt)
    W.boardNope = math.max(0, W.boardNope - dt)
    if W.phase == "play" then
        local before = W.hintT
        W.hintT = W.hintT + dt
        if before < HINT_AFTER and W.hintT >= HINT_AFTER and not W.challenge then
            ctx.journal.log("aide", { numero = train.nextNumber() })
        end
    elseif W.phase == "party" then
        updateDrive(dt)
    end
    for i = #smoke, 1, -1 do
        local p = smoke[i]
        p.life, p.y, p.r = p.life - dt, p.y - 40 * dt, p.r + 14 * dt
        if p.life <= 0 then table.remove(smoke, i) end
    end
end

-- The seated animals are drawn with their wagon.
function train.hidden(a)
    return a.state == "board" and a.seated
end

-- Drawing ------------------------------------------------------------------------

-- A landscape layer, repeated (every other copy mirrored, so the joins are
-- seamless), its bottom at y, h tall, scrolled by dx.
local function band(name, y, h, dx)
    local im = art.image(name)
    if not im then return end
    local sc = h / im:getHeight()
    local w = im:getWidth() * sc
    local x = (dx % (2 * w)) - 2 * w
    g.setColor(1, 1, 1)
    local i = 0
    while x < 1280 do
        if i % 2 == 0 then g.draw(im, x, y - h, 0, sc, sc)
        else g.draw(im, x + w, y - h, 0, -sc, sc) end
        x, i = x + w, i + 1
    end
end

-- The meadow's grass in perspective: thin strips, smaller further up, which
-- go by at their own speed when the landscape scrolls.
local quad
local function perspectiveGrass()
    local im = art.image("herbe")
    if not im then
        g.setColor(0.5, 0.75, 0.35)
        g.rectangle("fill", 0, HORIZON, 1280, 720 - HORIZON)
        return
    end
    im:setWrap("repeat", "repeat")
    quad = quad or g.newQuad(0, 0, 1, 1, im:getDimensions())
    local k = im:getWidth() / 380                  -- texture pixels per meadow pixel (at full size)
    local v, STRIP = 0, 3
    g.setColor(1, 1, 1)
    for y = HORIZON - 4, 720, STRIP do
        local s = train.depth(y)                   -- across: the same scale as the sprites
        local sy = s * FORESHORTEN                 -- from top to bottom: squashed (lying flat)
        local u0 = ((-640) / s + 640 - (W.scroll or 0)) * k
        quad:setViewport(u0, v, 1280 / s * k, STRIP / sy * k)
        g.draw(im, quad, 0, y, 0, s / k, sy / k)
        v = v + STRIP / sy * k
    end
    -- a light haze far away, just before the trees (it helps the eye read
    -- the meadow as going away, not up)
    for i = 0, 19 do
        g.setColor(0.86, 0.93, 0.98, 0.42 * (1 - i / 20))
        g.rectangle("fill", 0, HORIZON - 4 + i * 6, 1280, 6)
    end
end

-- Before everything: the sky, the far hills, the meadow, the trees.
function train.drawBack()
    local sc = W.scroll or 0
    for i = 0, 23 do                                          -- the sky
        local u = i / 23
        g.setColor(0.55 + 0.33 * u, 0.78 + 0.16 * u, 0.96 + 0.02 * u)
        g.rectangle("fill", 0, i * HORIZON / 24, 1280, HORIZON / 24 + 1)
    end
    g.setColor(1, 1, 1, 0.85)                                 -- two soft clouds
    for i, c in ipairs({ { 230, 70, 60 }, { 900, 50, 75 } }) do
        local x = (c[1] + sc * 0.05) % 1500 - 110
        g.ellipse("fill", x, c[2], c[3], c[3] * 0.35)
        g.ellipse("fill", x + c[3] * 0.5, c[2] - 10, c[3] * 0.6, c[3] * 0.3)
    end
    band("train_loin", HORIZON + 8, 150, sc * 0.12)
    perspectiveGrass()
    -- the trees stand on the meadow's far edge: they go by with the grass
    -- there (not slower: they would slide over their own ground)
    band("train_milieu", HORIZON + 16, 92, sc * train.depth(HORIZON + 16))
    return true
end

local OUTLINE = { 0.23, 0.14, 0.09 }

-- A filled shape with the thick dark-brown outline of the drawings.
local function shape(kind, color, ...)
    g.setColor(OUTLINE)
    g.setLineWidth(5)
    g[kind]("line", ...)
    g.setColor(color)
    g[kind]("fill", ...)
end

-- The platform: along the train, from a bit before the engine to a bit after
-- the last wagon.
function train.platformX()
    return LOCO_X - LOCO_W / 2 - 40, wagonX(#W.seq) - (W.trainShift or 0) + WAGON_W / 2 + 40
end

-- A lamp post at the end of the platform.
local function lamp(x, y)
    g.setColor(0, 0, 0, 0.2)
    g.ellipse("fill", x + 3, y + 1, 12, 4)
    shape("rectangle", { 0.3, 0.27, 0.27 }, x - 9, y - 6, 18, 8, 3)       -- its foot
    shape("rectangle", { 0.3, 0.27, 0.27 }, x - 4, y - 92, 8, 92, 3)
    shape("rectangle", { 0.3, 0.27, 0.27 }, x - 14, y - 104, 28, 14, 4)
    shape("rectangle", { 1, 0.9, 0.55 }, x - 10, y - 122, 20, 20, 5)
    shape("polygon", { 0.3, 0.27, 0.27 }, x - 16, y - 120, x + 16, y - 120, x, y - 134)
end

-- The platform: a wooden floor lying on the ground, seen at an angle (its
-- far edge a little narrower, boards running across, like the meadow), with
-- a thick front curb above the rails, and two lamp posts standing on it.
-- Then the sleepers (going by when the train drives) and the two rails.
local CURB = 18                -- the front curb's height
function train.drawGround()
    local x1, x2 = train.platformX()
    local sc = W.scroll or 0
    x1, x2 = x1 + sc, x2 + sc                                  -- (left behind when the train goes)
    local top, front = PLATFORM_Y, PLATFORM_EDGE               -- far edge, near edge of the floor
    local inset = (x2 - x1) * (1 - train.depth(top) / train.depth(front)) / 2
    local fx1, fx2 = x1 + inset, x2 - inset                    -- the far edge, a little narrower
    g.setColor(0, 0, 0, 0.18)                                  -- its shadow on the grass
    g.polygon("fill", fx1 - 6, top + 6, fx2 + 6, top + 6, x2 + 8, front + CURB + 4, x1 - 8, front + CURB + 4)
    shape("polygon", { 0.88, 0.74, 0.52 }, fx1, top, fx2, top, x2, front, x1, front)   -- the floor
    g.setColor(0.74, 0.58, 0.38)                               -- boards across, closer together far away
    g.setLineWidth(2)
    for i = 1, 5 do
        local u = (i / 6) ^ 1.25
        local y = top + (front - top) * u
        local a, b = fx1 + (x1 - fx1) * u, fx2 + (x2 - fx2) * u
        g.line(a + 4, y, b - 4, y)
    end
    g.setColor(1, 0.86, 0.35)                                  -- the yellow safety line, near the edge
    g.rectangle("fill", x1 + 8, front - 9, x2 - x1 - 16, 5, 2)
    shape("rectangle", { 0.6, 0.42, 0.25 }, x1, front, x2 - x1, CURB, 4)                -- the front curb
    g.setColor(0.48, 0.32, 0.18)
    for x = x1 + 24, x2 - 24, 48 do g.rectangle("fill", x, front + 4, 4, CURB - 8, 1) end
    for x = -30, 1280, 30 do    -- the sleepers (going by), then the two rails
        g.setColor(0.5, 0.36, 0.22)
        g.rectangle("fill", x + sc % 30, RAIL_Y - 12, 16, 24, 2)
    end
    g.setColor(0.55, 0.55, 0.6)
    g.rectangle("fill", 0, RAIL_Y - 9, 1280, 6)
    g.rectangle("fill", 0, RAIL_Y + 4, 1280, 6)
    lamp(fx1 + 24, top + 10)                                   -- the lamps, on the floor's far corners
    lamp(fx2 - 24, top + 10)
end

-- Draw an image w wide, the bottom of its wheels at (x, RAIL_Y); flip = -1 to
-- face left.
local function onRails(name, x, w, flip)
    local im = art.image(name)
    if not im then
        shape("rectangle", { 0.85, 0.3, 0.25 }, x - w / 2, RAIL_Y - w * 0.55, w, w * 0.5, 8)
        return w * 0.55
    end
    local sc = w / im:getWidth()
    g.setColor(1, 1, 1)
    g.draw(im, x, RAIL_Y + 4, 0, sc * (flip or 1), sc, im:getWidth() / 2, im:getHeight())
    return im:getHeight() * sc
end

local function drawLoco()
    local d = W.drive
    local x = LOCO_X + W.trainShift
    if d and d.by and not d.gone then                          -- the driver, in the cab
        art.kid(d.by.look, x + 38, RAIL_Y - 92, -1, 0.95, 0, "repos", W.time)
    end
    onRails("train_loco", x, LOCO_W, -1)
    if d and not d.by and not d.auto and not d.gone then       -- come and drive!
        local t = W.time * 5
        art.star(x + 30, RAIL_Y - 150 - math.abs(math.sin(t)) * 10, 12, true)
        art.star(x - 10, RAIL_Y - 140 - math.abs(math.cos(t)) * 10, 9, true)
    end
    for _, p in ipairs(smoke) do
        g.setColor(0.95, 0.95, 0.95, p.life * 0.7)
        g.circle("fill", p.x, p.y, p.r)
    end
end

-- A wagon: the animal sitting in it (drawn first: the wagon's side hides its
-- legs), the wagon, the hitch to the one in front, and its number on the plate.
local function drawWagon(i)
    local x = wagonX(i)
    for _, a in ipairs(W.animals) do
        if a.slot == i and train.hidden(a) then
            art.animal(a.kind, x, SEAT_Y, -1, 1.15, false)
        end
    end
    g.setColor(OUTLINE)
    g.setLineWidth(5)
    g.line(x - WAGON_W / 2 + 2, RAIL_Y - 20, x - WAGON_GAP + WAGON_W / 2 - 2, RAIL_Y - 20)
    local h = onRails(WAGONS[(i - 1) % #WAGONS + 1], x, WAGON_W)
    -- its number, big, in a round tag on the plate (green once its animal is in)
    local seated = false
    for _, a in ipairs(W.animals) do
        if a.slot == i and train.hidden(a) then seated = true end
    end
    art.disk(W.seq[i], x, RAIL_Y + 4 - h + h * 0.4, 23, seated and "ok" or "plain", ctx.fonts.board)
end

-- Add the train to the things drawn back to front (by their feet).
function train.things(list)
    table.insert(list, { y = RAIL_Y, draw = drawLoco })
    for i = 1, #W.seq do
        table.insert(list, { y = RAIL_Y + 0.1, draw = function() drawWagon(i) end })
    end
end

-- The number on an animal's back: a little round badge above its head. The
-- next number to find sparkles when the kids have been looking for a while.
function train.drawOnAnimal(a, shake)
    if not a.number or a.state == "board" then return end
    local d = train.depth(a.y)
    local x, y = a.x + (shake or 0) + train.offset(a.y), a.y - art.height(a.kind) * 1.2 * d - 22 * d
    art.disk(a.number, x, y, 19, "plain", ctx.fonts.badge)
    -- (in the challenge: only after a mistake)
    if W.hintT > HINT_AFTER and (not W.challenge or not W.trainClean) and a.number == train.nextNumber()
        and a.state == "free" then
        local t = W.time * 5
        art.star(x + 22, y - 16 - math.abs(math.sin(t)) * 8, 9, true)
        art.star(x - 22, y - 10 - math.abs(math.cos(t)) * 8, 7, true)
    end
end

-- At the top: the train's numbers in order. Green: in the train; yellow:
-- following a kid; the next one to find is bigger and pulses.
function train.drawHud()
    local n = #W.seq
    local step = 56
    local x0 = 640 - (n - 1) * step / 2
    art.panel(x0 - 40, 8, (n - 1) * step + 80, 64)
    local nextN = train.nextNumber()
    for i, num in ipairs(W.seq) do
        local x, y = x0 + (i - 1) * step, 40
        local state = "wait"
        for _, a in ipairs(W.animals) do
            if a.number == num then
                if a.state == "board" then state = "in"
                elseif a.state == "follow" then state = "follow" end
            end
        end
        local r, kind = 20, "off"
        if state == "in" then kind = "ok"
        elseif state == "follow" then kind = "todo"
        elseif num == nextN and W.phase == "play" then
            local shake = math.sin(W.boardNope * 40) * 5 * W.boardNope / 0.6
            x = x + shake
            r, kind = 24 + math.sin(W.time * 6) * 2, "plain"
        end
        art.disk(num, x, y, r, kind, ctx.fonts.board)
    end
end

return train
