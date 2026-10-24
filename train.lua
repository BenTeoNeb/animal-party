-- train.lua: the Animal Train. Animals wearing a number wait in the meadow:
-- call them in order (1, 2, 3...) and lead them onto the platform, where each
-- one climbs into its wagon (the wagons have the numbers painted on). Only
-- the next number follows you: another one shakes its head. Levels:
--   1  count up from 1 (to 3, 4 or 5)
--   2  count up from another number (five numbers from 2 to 5), with a
--      couple of numbers around them that are not in the train
--   3  count down to 1 (from 5 to 8), and the train leaves: "3, 2, 1, go!"
-- world.lua calls the hooks below at the right moments (see MODES there).

local art = require("art")
local sfx = require("sfx")
local lang = require("lang")

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

train.START_X, train.START_Y = 640, 430
-- The three parts of the meadow (the rails take the bottom).
train.ZONES = {
    { x1 = 470, y1 = 96, x2 = 810, y2 = 280 },       -- top, below the number board
    { x1 = 16, y1 = 24, x2 = 450, y2 = 520 },        -- left
    { x1 = 830, y1 = 24, x2 = 1264, y2 = 520 },      -- right
}

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
    for i, n in ipairs(numbers) do
        local a = ctx.newAnimal(kinds[(i - 1) % #kinds + 1])
        a.number = n
        ctx.biomeSpot(a)
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

function train.party()
    ctx.answer(W.trainClean)
    sfx.play("toot")
    ctx.stars(wagonX(1), RAIL_Y - 90, 14)
end

local smoke = {}
function train.update(dt)
    W.boardNope = math.max(0, W.boardNope - dt)
    if W.phase == "play" then
        local before = W.hintT
        W.hintT = W.hintT + dt
        if before < HINT_AFTER and W.hintT >= HINT_AFTER and not W.challenge then
            ctx.journal.log("aide", { numero = train.nextNumber() })
        end
    elseif W.phase == "party" and W.partyTime > 1 then
        -- the train leaves (to the left), puffing
        W.trainShift = W.trainShift - dt * math.min(320, (W.partyTime - 1) * 260)
        if love.math.random() < dt * 12 then
            table.insert(smoke, { x = LOCO_X - 36 + W.trainShift, y = RAIL_Y - 128, r = 10, life = 1.2 })
        end
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
    shape("rectangle", { 0.3, 0.27, 0.27 }, x - 4, y - 92, 8, 92, 3)
    shape("rectangle", { 0.3, 0.27, 0.27 }, x - 14, y - 104, 28, 14, 4)
    shape("rectangle", { 1, 0.9, 0.55 }, x - 10, y - 122, 20, 20, 5)
    shape("polygon", { 0.3, 0.27, 0.27 }, x - 16, y - 120, x + 16, y - 120, x, y - 134)
end

-- The platform (a raised wooden floor with a light edge and a darker front,
-- right above the rails) and the rails.
function train.drawGround()
    local x1, x2 = train.platformX()
    local w = x2 - x1
    g.setColor(0, 0, 0, 0.2)
    g.rectangle("fill", x1 + 4, PLATFORM_Y + 8, w, RAIL_Y - PLATFORM_Y - 4, 10)
    shape("rectangle", { 0.6, 0.42, 0.25 }, x1, PLATFORM_EDGE - 6, w, RAIL_Y - 12 - PLATFORM_EDGE + 6, 6)   -- front
    shape("rectangle", { 0.88, 0.74, 0.52 }, x1, PLATFORM_Y, w, PLATFORM_EDGE - PLATFORM_Y, 10)            -- top
    g.setColor(0.72, 0.56, 0.36)
    g.setLineWidth(2)
    for x = x1 + 44, x2 - 10, 44 do g.line(x, PLATFORM_Y + 6, x, PLATFORM_EDGE - 14) end
    g.setColor(1, 0.86, 0.35)                                     -- the edge
    g.rectangle("fill", x1 + 6, PLATFORM_EDGE - 12, w - 12, 7, 3)
    g.setColor(0.5, 0.33, 0.18)
    for x = x1 + 18, x2 - 18, 36 do g.rectangle("fill", x, PLATFORM_EDGE + 2, 18, 4, 2) end
    for x = 0, 1280, 30 do      -- the sleepers, then the two rails
        g.setColor(0.5, 0.36, 0.22)
        g.rectangle("fill", x, RAIL_Y - 12, 16, 24, 2)
    end
    g.setColor(0.55, 0.55, 0.6)
    g.rectangle("fill", 0, RAIL_Y - 9, 1280, 6)
    g.rectangle("fill", 0, RAIL_Y + 4, 1280, 6)
    lamp(x1 + 16, PLATFORM_Y + 20)
    lamp(x2 - 16, PLATFORM_Y + 20)
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
    onRails("train_loco", LOCO_X + W.trainShift, LOCO_W, -1)
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
    local x, y = a.x + (shake or 0), a.y - art.height(a.kind) * 1.2 - 22
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
