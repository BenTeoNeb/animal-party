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

local RAIL_Y = 690             -- the rails (the wagons' wheels)
local PLATFORM_Y = 612         -- walk onto the platform (below this) to board the train
local PLATFORM_X = 470
local LOCO_X = 540             -- the engine, at the left end, facing left: the wagons
                               -- behind it read in order, left to right (1 2 3 4 5)
local WAGON_GAP = 70
local SEAT_Y = RAIL_Y - 22     -- where the animals stand in their wagon
local HINT_AFTER = 10          -- seconds without finding the next one: it sparkles
local BOARD_GAP = 0.45         -- seconds between two animals sitting down (time to count)

train.START_X, train.START_Y = 640, 430
-- The three parts of the meadow (the rails take the bottom).
train.ZONES = {
    { x1 = 470, y1 = 96, x2 = 810, y2 = 280 },       -- top, below the number board
    { x1 = 16, y1 = 24, x2 = 450, y2 = 590 },        -- left
    { x1 = 830, y1 = 24, x2 = 1264, y2 = 580 },      -- right
}

-- ctx: helpers from world.lua (newAnimal, biomeSpot, moveToward, popup,
-- hearts, stars, outlined, fonts, journal, KINDS, shuffle, rand).
function train.setup(world, c)
    W, ctx = world, c
end

local function wagonX(i)
    return LOCO_X + 100 + (i - 1) * WAGON_GAP + (W.trainShift or 0)
end

-- The numbers of this round's train, in order.
local function sequenceFor(level)
    local seq = {}
    if level == 1 then
        for n = 1, love.math.random(3, 5) do seq[#seq + 1] = n end
    elseif level == 2 then
        local s = love.math.random(2, 5)
        for n = s, s + 4 do seq[#seq + 1] = n end
    else
        for n = love.math.random(5, 8), 1, -1 do seq[#seq + 1] = n end
    end
    return seq
end

function train.newRound(level)
    local seq = sequenceFor(level)
    W.seq, W.trainShift, W.hintT, W.boardNope, W.seatedAt = seq, 0, 0, 0, -9
    local numbers = { unpack(seq) }
    -- decoys: numbers just around the train's, that are not in it
    if level == 2 then
        table.insert(numbers, seq[1] - 1)
        table.insert(numbers, seq[#seq] + 1)
    elseif level == 3 then
        table.insert(numbers, seq[1] + 1)
        table.insert(numbers, seq[1] + 2)
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
    if k.y < PLATFORM_Y or k.x < PLATFORM_X or #k.followers == 0 then return end
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
    sfx.play("toot")
    ctx.stars(wagonX(1), RAIL_Y - 60, 14)
end

local smoke = {}
function train.update(dt)
    W.boardNope = math.max(0, W.boardNope - dt)
    if W.phase == "play" then
        local before = W.hintT
        W.hintT = W.hintT + dt
        if before < HINT_AFTER and W.hintT >= HINT_AFTER then
            ctx.journal.log("aide", { numero = train.nextNumber() })
        end
    elseif W.phase == "party" and W.partyTime > 1 then
        -- the train leaves (to the left), puffing
        W.trainShift = W.trainShift - dt * math.min(320, (W.partyTime - 1) * 260)
        if love.math.random() < dt * 12 then
            table.insert(smoke, { x = LOCO_X - 21 + W.trainShift, y = RAIL_Y - 84, r = 8, life = 1 })
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
local WAGON_COLORS = { { 0.9, 0.3, 0.25 }, { 0.3, 0.55, 0.9 }, { 1, 0.78, 0.2 }, { 0.4, 0.75, 0.35 } }

-- A filled shape with the thick dark-brown outline of the drawings.
local function shape(kind, color, ...)
    g.setColor(OUTLINE)
    g.setLineWidth(5)
    g[kind]("line", ...)
    g.setColor(color)
    g[kind]("fill", ...)
end

local function wheel(x, y, r)
    shape("circle", { 0.35, 0.3, 0.3 }, x, y, r)
    g.setColor(0.75, 0.7, 0.65)
    g.circle("fill", x, y, r * 0.35)
end

-- The platform and the rails, on the ground.
function train.drawGround()
    shape("rectangle", { 0.86, 0.72, 0.5 }, PLATFORM_X, PLATFORM_Y, 1290 - PLATFORM_X, 40, 6)
    g.setColor(0.7, 0.55, 0.35)
    g.setLineWidth(2)
    for x = PLATFORM_X + 40, 1280, 40 do g.line(x, PLATFORM_Y + 4, x, PLATFORM_Y + 36) end
    for x = 0, 1280, 28 do      -- the sleepers, then the two rails
        g.setColor(0.5, 0.36, 0.22)
        g.rectangle("fill", x, RAIL_Y - 4, 14, 20, 2)
    end
    g.setColor(0.55, 0.55, 0.6)
    g.rectangle("fill", 0, RAIL_Y - 2, 1280, 5)
    g.rectangle("fill", 0, RAIL_Y + 9, 1280, 5)
end

-- The engine, drawn facing right around x = 0, then turned to face left.
local function drawLoco()
    g.push()
    g.translate(LOCO_X + W.trainShift, 0)
    g.scale(-1, 1)
    local x, y = 0, RAIL_Y
    shape("rectangle", { 0.85, 0.25, 0.2 }, x - 44, y - 62, 34, 52, 6)          -- cabin
    shape("rectangle", { 0.55, 0.3, 0.2 }, x - 50, y - 70, 46, 10, 4)           -- its roof
    shape("rectangle", { 0.3, 0.55, 0.9 }, x - 12, y - 46, 56, 36, 10)          -- boiler
    shape("rectangle", { 0.3, 0.25, 0.25 }, x + 14, y - 74, 14, 28, 3)          -- chimney
    g.setColor(1, 0.95, 0.7)
    g.rectangle("fill", x - 38, y - 54, 22, 16, 3)                              -- window
    shape("polygon", { 0.85, 0.25, 0.2 }, x + 44, y - 20, x + 58, y - 4, x + 44, y - 4)
    wheel(x - 28, y - 4, 12)
    wheel(x + 4, y - 2, 9)
    wheel(x + 30, y - 2, 9)
    g.pop()
    for _, p in ipairs(smoke) do
        g.setColor(0.95, 0.95, 0.95, p.life * 0.8)
        g.circle("fill", p.x, p.y, p.r)
    end
end

local function drawWagon(i)
    local x, y = wagonX(i), RAIL_Y
    for _, a in ipairs(W.animals) do
        if a.slot == i and train.hidden(a) then
            art.animal(a.kind, x, SEAT_Y, -1, 1.1, false)
        end
    end
    local c = WAGON_COLORS[(i - 1) % #WAGON_COLORS + 1]
    shape("rectangle", c, x - 30, y - 34, 60, 26, 5)
    ctx.outlined(tostring(W.seq[i]), ctx.fonts.badge, x - 30, y - 35, 60, { 1, 1, 1 })
    wheel(x - 16, y - 4, 8)
    wheel(x + 16, y - 4, 8)
    g.setColor(OUTLINE)
    g.setLineWidth(4)
    g.line(x - 30, y - 16, x - WAGON_GAP + 30, y - 16)       -- the hitch to the one in front
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
    if W.hintT > HINT_AFTER and a.number == train.nextNumber() and a.state == "free" then
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
