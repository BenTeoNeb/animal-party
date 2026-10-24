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
local ferme = require("ferme")

local nid = {}
local W, ctx
local g = love.graphics

-- The hen house: 2 rows of 5 drawn nest boxes (images/nichoir.png, 118 px
-- wide), under a roof (images/nichoir_toit.png, one piece per column).
local CX, NEST_W = 640, 118
local ROOF_Y = 222                        -- the roof's bottom
local ROWS_Y = { 340, 460 }               -- the bottom of each row of nest boxes
local FRAME = { x1 = CX - 2.5 * NEST_W, y1 = 150, x2 = CX + 2.5 * NEST_W, y2 = 460 }   -- (solid)
local GATE_Y = 560                        -- walking up to its front (above this) = arriving
local PER_ROUND = 5
local COUNT_GAP = 0.45                   -- seconds between two hens sitting down
-- The ladder of steps (adaptive, see progress.lua): how the hens go in
-- (free: as many as there is room for; once: exactly the missing number at
-- once; covered: the same with the nest boxes shut and "6 + ? = 10"), the
-- hens already in, the spare hens in the yard.
nid.STEPS = {
    { way = "free", pre = { 6, 9 }, spare = 3 },
    { way = "free", pre = { 2, 8 }, spare = 3 },
    { way = "once", pre = { 6, 9 }, spare = 4 },
    { way = "once", pre = { 1, 9 }, spare = 4 },
    { way = "covered", pre = { 6, 9 }, spare = 4 },
    { way = "covered", pre = { 1, 9 }, spare = 5 },
}
nid.UP = 2                               -- clean nests in a row to go up a step

nid.START_X, nid.START_Y = 640, 620
-- The farm: its ground, the yard where the hens wander, and its decor
-- ({ image, x, feet y, height, flip }).
nid.SCENE, nid.GROUND, nid.GROUND_TILE = "ferme", ferme.GROUND, ferme.GROUND_TILE
nid.KID_SCALE = ferme.KID_SCALE
nid.YARD = { x1 = 20, y1 = 470, x2 = 1260, y2 = 720 }
local DECOR = {
    { "ferme_grange", 165, 340, 230 },
    { "ferme_barriere", 1035, 170, 56 }, { "ferme_barriere", 1180, 170, 56 },
    { "ferme_foin", 1110, 250, 78 }, { "ferme_foin", 1200, 300, 78, -1 }, { "ferme_foin", 1030, 310, 70 },
    { "ferme_abreuvoir", 1160, 440, 54 }, { "ferme_brouette", 180, 450, 58 },
}

local S = {}      -- this nest: filled, nests, phase, timer, round...
nid.state = S     -- (read by the tests)

function nid.setup(world, c)
    W, ctx = world, c
end

-- Where the hen of nest i stands (on its straw).
local function slotAt(i)
    local col, row = (i - 1) % 5, math.floor((i - 1) / 5)
    return CX + (col - 2) * NEST_W, ROWS_Y[row + 1] - 14
end

local function newNest()
    local st = nid.STEPS[W.level]
    S.way = st.way
    local pre = love.math.random(st.pre[1], st.pre[2])
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
    S.clean = true
    for _ = 1, 10 - pre + st.spare do
        local a = ctx.newAnimal("poule")
        ctx.biomeSpot(a)
        table.insert(W.animals, a)
    end
    for _, k in ipairs(W.kids) do k.followers = {} end
    ctx.journal.log("nid", { niveau = W.level, deja = pre })
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
    S.clean = false
    for _, a in ipairs(list) do a.nope = 0.6 end
    S.nope = 0.6
    sfx.play("full")
end

-- The hen house is solid; walking up to its front with hens is arriving.
function nid.arrive(k)
    if k.x > FRAME.x1 - 10 and k.x < FRAME.x2 + 10 and k.y > FRAME.y1 and k.y < FRAME.y2 + 14 then
        k.y = FRAME.y2 + 14                     -- (pushed out, to the front)
    end
    local atGate = k.x > FRAME.x1 and k.x < FRAME.x2 and k.y < GATE_Y
    local arriving = atGate and not k.atNest
    k.atNest = atGate
    if not arriving or #k.followers == 0 or S.phase ~= "play" then return end
    local need = 10 - S.taken
    if S.way == "free" then
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
        if S.way == "covered" then S.peek = 2 end   -- the doors open: look at the nest
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
        ctx.answer(S.clean)
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

-- The hen house: the roof and the 10 nest boxes.
function nid.drawGround()
    local shake = math.sin(S.nope * 40) * 6 * S.nope / 0.6
    g.push()
    g.translate(shake, 0)
    g.setColor(0, 0, 0, 0.18)
    g.ellipse("fill", CX, FRAME.y2 + 2, 2.7 * NEST_W, 18)
    for col = 0, 4 do
        local x = CX + (col - 2) * NEST_W
        for _, y in ipairs(ROWS_Y) do ferme.image("nichoir", x, y, NEST_W * 360 / 354) end
        ferme.image("nichoir_toit", x, ROOF_Y, NEST_W * 199 / 354 + 4)
    end
    g.pop()
end

-- The decor; the closed doors over the nest boxes (level 3, while it is not
-- full and not peeking); the golden egg when it's full.
function nid.things(list)
    ferme.things(list, DECOR)
    local covered = S.way == "covered" and S.phase == "play" and S.peek <= 0
    if covered then
        table.insert(list, { y = FRAME.y2 + 1, draw = function()
            local shake = math.sin(S.nope * 40) * 6 * S.nope / 0.6
            for i = 1, 10 do
                local col, row = (i - 1) % 5, math.floor((i - 1) / 5)
                local x, y = CX + (col - 2) * NEST_W + shake, ROWS_Y[row + 1]
                art.panel(x - NEST_W / 2 + 12, y - 104, NEST_W - 24, 92)
                g.setColor(1, 0.85, 0.3)
                g.circle("fill", x + 26, y - 58, 5)
            end
        end })
    end
    if S.phase == "full" then
        table.insert(list, { y = FRAME.y2 + 2, draw = function()
            local s = math.min(1, (2.4 - S.t) * 3)
            ferme.image("oeuf_dore", CX, FRAME.y1 + 10 - 30 * s, 96 * s)
            art.star(CX + 60, FRAME.y1 - 70 + math.sin(W.time * 6) * 4, 11 * s, true)
            art.star(CX - 62, FRAME.y1 - 40 + math.cos(W.time * 6) * 4, 9 * s, true)
        end })
    end
end

-- At the top left: the round's full nests (stars); at the top in the middle,
-- level 3: the sign "6 + ? = 10".
function nid.drawHud()
    art.panel(12, 8, (PER_ROUND - 1) * 40 + 52, 44)
    for i = 1, PER_ROUND do art.star(38 + (i - 1) * 40, 30, 15, i <= S.good) end
    if S.way == "covered" then
        local f = ctx.fonts.sign
        local text = S.pre .. " + " .. (S.phase == "full" and tostring(10 - S.pre) or "?") .. " = 10"
        local w = f:getWidth(text) + 60
        art.paper(640 - w / 2, 10, w, 84)
        g.setFont(f)
        g.setColor(OUTLINE)
        g.printf(text, 640 - w / 2, 52 - f:getHeight() / 2, w, "center")
    end
end

return nid
