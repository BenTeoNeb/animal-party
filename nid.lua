-- nid.lua: the Nest of 10 (le Nid de 10). In the middle of the meadow, a hen
-- house shaped like a ten-frame: 2 rows of 5 straw nests, some of them
-- already with a hen. Fill it: bring the missing hens. Each one sits in an
-- empty nest and is counted on from the ones already there ("7, 8, 9, 10");
-- when it's full, a golden egg. It trains the bonds of 10 (6 + 4 = 10), the
-- base of all the work on tens (the Singapore method's ten-frame). Levels,
-- from concrete to abstract:
--   1  bring the hens as you like; one too many is refused (only 10 nests)
--   2  bring them all at once: arrive with exactly the missing number (count
--      the empty nests first); not right, the nest wobbles and they stay
--   3  the nest has a straw roof and the sign says "6 + ? = 10"; not right,
--      the roof lifts a moment to show the nest (back to the concrete)
-- 5 full nests make a round.
-- world.lua calls the hooks below at the right moments (see MODES there).

local art = require("art")
local sfx = require("sfx")
local lang = require("lang")

local nid = {}
local W, ctx
local g = love.graphics

local CX = 640                           -- the frame's middle
local COL_GAP, ROWS_Y = 88, { 292, 378 } -- the nests: 5 columns, 2 rows (the hens' feet)
local FRAME = { x1 = 405, y1 = 212, x2 = 875, y2 = 412 }   -- the hen house (solid)
local GATE_Y = 470                       -- walking in front of it (above this) = arriving
local PER_ROUND = 5
local COUNT_GAP = 0.45                   -- seconds between two hens sitting down
local PRE = { { 2, 8 }, { 3, 9 }, { 1, 9 } }   -- hens already in the nest, per level
local SPARE = { 3, 4, 4 }                -- hens in the meadow more than needed

nid.START_X, nid.START_Y = 640, 570
nid.ZONES = {
    { x1 = 300, y1 = 10, x2 = 980, y2 = 190 },
    { x1 = 16, y1 = 220, x2 = 380, y2 = 712 },
    { x1 = 900, y1 = 220, x2 = 1264, y2 = 712 },
}

local S = {}      -- this nest: filled, nests, phase, timer, round...
nid.state = S     -- (read by the tests)

function nid.setup(world, c)
    W, ctx = world, c
end

local function slotAt(i)
    local col, row = (i - 1) % 5, math.floor((i - 1) / 5)
    return CX + (col - 2) * COL_GAP, ROWS_Y[row + 1]
end

local function newNest()
    local level = W.level
    local pre = love.math.random(PRE[level][1], PRE[level][2])
    S.pre, S.filled, S.taken = pre, pre, pre     -- taken: nests given (counted or walking in)
    S.phase, S.t, S.nope, S.peek, S.lastSit = "play", 0, 0, 0, -9
    W.animals = {}
    for i = 1, pre do
        local a = ctx.newAnimal("poule")
        a.state, a.slot, a.counted = "nest", i, true
        a.x, a.y = slotAt(i)
        a.tx, a.ty = a.x, a.y
        table.insert(W.animals, a)
    end
    for _ = 1, 10 - pre + SPARE[level] do
        local a = ctx.newAnimal("poule")
        ctx.biomeSpot(a)
        table.insert(W.animals, a)
    end
    for _, k in ipairs(W.kids) do k.followers = {} end
    ctx.journal.log("nid", { niveau = level, deja = pre })
end

function nid.newRound()
    S.good, S.finished = 0, false
    newNest()
end

-- The bottom button calls the nearest hen (as many as you like).
function nid.grab(k, a)
    if not a or a.kind ~= "poule" or #k.followers >= 10 then return end
    a.vx, a.vy, a.state = 0, 0, "follow"
    table.insert(k.followers, a)
    ctx.hearts(a.x, a.y - 40, 1)
    sfx.play("grab_poule")
end

-- A hen goes to the next empty nest; it is counted when it sits down.
local function enter(a)
    S.taken = S.taken + 1
    a.state, a.slot, a.counted = "nest", S.taken, false
    a.tx, a.ty = slotAt(S.taken)
end

local function refuse(list)
    for _, a in ipairs(list) do a.nope = 0.6 end
    S.nope = 0.6
    sfx.play("full")
end

-- The hen house is solid; walking up to its front with hens is arriving.
function nid.arrive(k)
    if k.x > FRAME.x1 - 10 and k.x < FRAME.x2 + 10 and k.y > FRAME.y1 and k.y < FRAME.y2 + 8 then
        k.y = FRAME.y2 + 8                      -- (pushed out, to the front)
    end
    local atGate = k.x > FRAME.x1 and k.x < FRAME.x2 and k.y < GATE_Y
    local arriving = atGate and not k.atNest
    k.atNest = atGate
    if not arriving or #k.followers == 0 or S.phase ~= "play" then return end
    local need = 10 - S.taken
    local level = W.level
    if level == 1 then
        -- as many as there is room for; the others shake their heads
        local stay = {}
        for i, a in ipairs(k.followers) do
            if i <= need then enter(a) else table.insert(stay, a) end
        end
        k.followers = stay
        if #stay > 0 then refuse(stay) end
    elseif #k.followers == need then
        for _, a in ipairs(k.followers) do enter(a) end
        k.followers = {}
    else
        refuse(k.followers)
        if level == 3 then S.peek = 2 end      -- the roof lifts: look at the nest
        ctx.journal.log("non", { joueur = k.player, amene = #k.followers, manque = need })
    end
end

function nid.updateAnimal(a, dt)
    if a.state ~= "nest" then return end
    if not ctx.moveToward(a, a.tx, a.ty, 140, dt) then
        a.walk = 0
        a.facing = 1
        if not a.counted and W.time - S.lastSit >= COUNT_GAP then
            -- sitting down: counted on from the hens already there
            a.counted, S.lastSit = true, W.time
            S.filled = S.filled + 1
            sfx.count(S.filled, lang.current)
            ctx.popup(tostring(S.filled), a.x, a.y - 80, S.filled == 10 and { 0.6, 1, 0.5 } or { 1, 0.9, 0.4 })
            ctx.hearts(a.x, a.y - 40, 1)
        end
    end
end

function nid.update(dt)
    S.nope = math.max(0, S.nope - dt)
    S.peek = math.max(0, S.peek - dt)
    if W.phase ~= "play" then return end
    S.t = S.t - dt
    if S.phase == "play" and S.filled == 10 then
        -- full: a golden egg
        S.phase, S.t = "full", 2.4
        S.good = S.good + 1
        sfx.play("home")
        ctx.hearts(CX, 300, 8)
        ctx.journal.log("plein", { manches = S.good })
    elseif S.phase == "full" and S.t <= 0 then
        if S.good >= PER_ROUND then S.finished = true else newNest() end
    end
end

function nid.done() return S.finished end

function nid.party()
    ctx.stars(CX, 300, 18)
end

function nid.hidden() return false end
function nid.drawOnAnimal() end

-- Drawing ------------------------------------------------------------------------

local OUTLINE = art.OUTLINE

-- The hen house: a wooden frame, a straw floor, and the 10 nests.
function nid.drawGround()
    local shake = math.sin(S.nope * 40) * 6 * S.nope / 0.6
    g.push()
    g.translate(shake, 0)
    local f = FRAME
    art.panel(f.x1, f.y1, f.x2 - f.x1, f.y2 - f.y1)
    g.setColor(0.93, 0.82, 0.5)
    g.rectangle("fill", f.x1 + 12, f.y1 + 12, f.x2 - f.x1 - 24, f.y2 - f.y1 - 24, 10)
    g.setColor(OUTLINE)                                        -- the dividers
    g.setLineWidth(4)
    for c = 1, 4 do
        local x = CX + (c - 2.5) * COL_GAP
        g.line(x, f.y1 + 14, x, f.y2 - 14)
    end
    g.line(f.x1 + 14, (f.y1 + f.y2) / 2, f.x2 - 14, (f.y1 + f.y2) / 2)
    for i = 1, 10 do                                           -- the straw nests
        local x, y = slotAt(i)
        g.setColor(0.6, 0.42, 0.2)
        g.ellipse("fill", x, y - 4, 32, 14)
        g.setColor(0.85, 0.66, 0.32)
        g.ellipse("fill", x, y - 6, 24, 9)
        g.setColor(0.6, 0.42, 0.2)
        g.setLineWidth(2)
        for s = -2, 2 do g.line(x + s * 8 - 6, y - 12, x + s * 8 + 6, y - 2) end
    end
    g.pop()
end

-- The straw roof (level 3, while the nest is not full and not peeking), and
-- the golden egg when it's full.
function nid.things(list)
    local covered = W.level == 3 and S.phase == "play" and S.peek <= 0
    if covered then
        table.insert(list, { y = FRAME.y2 + 1, draw = function()
            local f = FRAME
            local shake = math.sin(S.nope * 40) * 6 * S.nope / 0.6
            g.setColor(OUTLINE)
            g.rectangle("fill", f.x1 - 14 + shake, f.y1 - 34, f.x2 - f.x1 + 28, f.y2 - f.y1 + 36, 30)
            g.setColor(0.92, 0.75, 0.35)
            g.rectangle("fill", f.x1 - 10 + shake, f.y1 - 30, f.x2 - f.x1 + 20, f.y2 - f.y1 + 28, 26)
            g.setColor(0.75, 0.55, 0.22)
            g.setLineWidth(3)
            for y = f.y1 - 14, f.y2 - 14, 22 do
                for x = f.x1 + 6, f.x2 - 20, 26 do
                    g.line(x + shake, y, x + 14 + shake, y + 12)
                end
            end
        end })
    end
    if S.phase == "full" then
        table.insert(list, { y = FRAME.y2 + 2, draw = function()
            local s = math.min(1, (2.4 - S.t) * 3)
            local x, y = CX, FRAME.y1 - 10
            g.setColor(OUTLINE)
            g.ellipse("fill", x, y, 30 * s, 40 * s)
            g.setColor(1, 0.82, 0.2)
            g.ellipse("fill", x, y, 26 * s, 36 * s)
            g.setColor(1, 0.95, 0.6)
            g.ellipse("fill", x - 8 * s, y - 12 * s, 7 * s, 11 * s)
            art.star(x + 30, y - 30 + math.sin(W.time * 6) * 4, 9 * s, true)
            art.star(x - 32, y - 16 + math.cos(W.time * 6) * 4, 7 * s, true)
        end })
    end
end

-- At the top: the round's full nests (stars); at level 3, the sign "6 + ? = 10".
function nid.drawHud()
    local x0 = 640 - (PER_ROUND - 1) * 22
    art.panel(x0 - 30, 8, (PER_ROUND - 1) * 44 + 60, 44)
    for i = 1, PER_ROUND do art.star(x0 + (i - 1) * 44, 30, 15, i <= S.good) end
    if W.level == 3 then
        local f = ctx.fonts.sign
        local text = S.pre .. " + " .. (S.phase == "full" and tostring(10 - S.pre) or "?") .. " = 10"
        local w = f:getWidth(text) + 60
        art.paper(640 - w / 2, 60, w, 84)
        g.setFont(f)
        g.setColor(OUTLINE)
        g.printf(text, 640 - w / 2, 102 - f:getHeight() / 2, w, "center")
    end
end

return nid
