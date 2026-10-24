-- flash.lua: Peekaboo! (Coucou !) A few animals hop out of the big bush, in a
-- dice pattern, for a moment, then hide again: how many were there? Walk onto
-- the stone with that number. Seeing a small number at a glance, without
-- counting one by one, makes counting much faster later.
--   right:     they come out again and are counted together, one by one
--   not right: the stone wobbles and greys, and they peek out again
-- 5 right answers make a round (the party and a star). Levels:
--   1  1 to 3 animals, out 3 s, 3 stones
--   2  2 to 5 animals, out 2.5 s, 3 stones
--   3  3 to 6 animals, out 2 s, 4 stones
-- world.lua calls the hooks below at the right moments (see MODES there).

local art = require("art")
local sfx = require("sfx")
local lang = require("lang")

local flash = {}
local W, ctx
local g = love.graphics

local BUSH_X, BUSH_Y = 640, 300          -- the bush's foot
local SHOW_X, SHOW_Y = 640, 380          -- the middle of the animals, when out
local STONE_Y, STONE_R = 645, 46
local PER_ROUND = 5                      -- right answers in a round
local SHOW_TIME = { 3, 2.5, 2 }          -- seconds out, per level
local RANGE = { { 1, 3 }, { 2, 5 }, { 3, 6 } }
local CHOICES = { 3, 3, 4 }
local STAND = 0.5                        -- seconds standing on a stone to choose it
local COUNT_GAP = 0.45                   -- seconds between two numbers when counting them

flash.START_X, flash.START_Y = 640, 540      -- below the animals: not in front of them
-- The biomes keep to the sides: the bush, the animals and the stones are in
-- the middle.
flash.ZONES = {
    { x1 = 360, y1 = 24, x2 = 920, y2 = 220 },
    { x1 = 16, y1 = 280, x2 = 390, y2 = 712 },
    { x1 = 890, y1 = 280, x2 = 1264, y2 = 712 },
}

-- Dice patterns: where each animal stands, in steps from the middle.
local PATTERNS = {
    { { 0, 0 } },
    { { -1, 0 }, { 1, 0 } },
    { { -1, 0.5 }, { 0, -0.5 }, { 1, 0.5 } },
    { { -1, -0.5 }, { 1, -0.5 }, { -1, 0.5 }, { 1, 0.5 } },
    { { -1, -0.5 }, { 1, -0.5 }, { 0, 0 }, { -1, 0.5 }, { 1, 0.5 } },
    { { -1, -0.5 }, { 0, -0.5 }, { 1, -0.5 }, { -1, 0.5 }, { 0, 0.5 }, { 1, 0.5 } },
}
local STEP_X, STEP_Y = 80, 76

local S = {}      -- this round: phase, timer, n, kind, stones, right answers...
flash.state = S   -- (read by the tests)

function flash.setup(world, c)
    W, ctx = world, c
end

local function hideSpot()
    return BUSH_X + ctx.rand(-50, 50), BUSH_Y - 12
end

-- Send the animals out of the bush (to their pattern), or back into it.
local function goOut()
    for _, a in ipairs(W.animals) do
        a.hidden, a.tx, a.ty = false, a.spotX, a.spotY
    end
    sfx.play("grab_" .. S.kind)
end

local function goIn()
    for _, a in ipairs(W.animals) do a.tx, a.ty = hideSpot() end
end

-- A new peekaboo: how many, which animal, which stones.
local function newFlash()
    local lo, hi = RANGE[W.level][1], RANGE[W.level][2]
    local n
    repeat n = love.math.random(lo, hi) until n ~= S.n or lo == hi
    S.n, S.kind = n, ctx.KINDS[love.math.random(#ctx.KINDS)]
    W.animals = {}
    for i, p in ipairs(PATTERNS[n]) do
        local a = ctx.newAnimal(S.kind)
        a.state, a.hidden = "show", true
        a.x, a.y = hideSpot()
        a.spotX = SHOW_X + p[1] * STEP_X + ctx.rand(-6, 6)
        a.spotY = SHOW_Y + p[2] * STEP_Y + ctx.rand(-4, 4)
        a.tx, a.ty, a.facing, a.order = a.x, a.y, 1, i
        table.insert(W.animals, a)
    end
    -- the stones: the right number and its neighbours, in a shuffled row
    local values, seen = { n }, { [n] = true }
    while #values < CHOICES[W.level] do
        local v = n + love.math.random(-2, 2)
        if v >= 1 and v <= 9 and not seen[v] then values[#values + 1], seen[v] = v, true end
    end
    ctx.shuffle(values)
    S.stones = {}
    local step = 150
    for i, v in ipairs(values) do
        table.insert(S.stones, { value = v, x = 640 + (i - (#values + 1) / 2) * step, y = STONE_Y,
            stand = 0, nope = 0, off = false })
    end
    S.phase, S.t, S.tries = "wait", 0.8, 0
end

function flash.newRound()
    S.good, S.finished, S.n = 0, false, nil
    newFlash()
    ctx.journal.log("manche", { niveau = W.level, coucou = true })
end

local function choose(stone, k)
    S.tries = S.tries + 1
    ctx.journal.log("choix", { joueur = k.player, montre = S.n, choisi = stone.value, essai = S.tries })
    if stone.value == S.n then
        S.phase, S.t, S.counted = "right", 0.3, 0
        stone.right = true
        goOut()
        sfx.play("home")
    else
        stone.nope, stone.off = 0.6, true
        sfx.play("drop")
        S.phase, S.t = "again", 0.5          -- they peek out again
    end
end

function flash.grab() end                    -- nothing to call here: just look

function flash.arrive() end                  -- (the stones are checked in flash.update)

-- The kids choose by standing on a stone for a moment (not one they were
-- already standing on when the stones appeared).
local function standOnStones(dt)
    for _, st in ipairs(S.stones) do
        local who
        for _, k in ipairs(W.kids) do
            if ctx.dist(k, st) < STONE_R then
                if st.lock ~= k then who = k end
            elseif st.lock == k then
                st.lock = nil                    -- stepped off: may choose it now
            end
        end
        if who and S.phase == "choose" and not st.off then
            st.stand = st.stand + dt
            if st.stand >= STAND then
                st.stand = 0
                choose(st, who)
                return
            end
        else
            st.stand = math.max(0, st.stand - dt * 2)
        end
    end
end

function flash.updateAnimal(a, dt)
    if a.hidden then return end
    if not ctx.moveToward(a, a.tx, a.ty, 260, dt) then a.walk = 0 end
    -- back in the bush: hidden (it went behind the bush to get there)
    if a.ty < BUSH_Y and math.abs(a.y - a.ty) < 3 then a.hidden = true end
end

local function allHidden()
    for _, a in ipairs(W.animals) do
        if not a.hidden then return false end
    end
    return true
end

local function allOut()
    for _, a in ipairs(W.animals) do
        if a.hidden or math.abs(a.x - a.spotX) > 3 or math.abs(a.y - a.spotY) > 3 then return false end
    end
    return true
end

function flash.update(dt)
    for _, st in ipairs(S.stones) do st.nope = math.max(0, st.nope - dt) end
    if W.phase ~= "play" then return end
    standOnStones(dt)
    S.t = S.t - dt
    if S.phase == "wait" and S.t <= 0 then
        S.phase, S.t = "out", SHOW_TIME[W.level]
        goOut()
    elseif S.phase == "out" and S.t <= 0 and allOut() then
        S.phase = "hide"
        goIn()
    elseif S.phase == "hide" and allHidden() then
        S.phase = "choose"
        for _, st in ipairs(S.stones) do      -- a kid already on a stone must step off first
            st.stand, st.lock = 0, nil
            for _, k in ipairs(W.kids) do
                if ctx.dist(k, st) < STONE_R then st.lock = k end
            end
        end
    elseif S.phase == "again" and S.t <= 0 then
        S.phase, S.t = "out", SHOW_TIME[W.level] * 0.8
        goOut()
    elseif S.phase == "right" and S.t <= 0 and allOut() then
        -- count them together, one by one
        if S.counted < S.n then
            S.counted = S.counted + 1
            local a = W.animals[S.counted]
            sfx.count(S.counted, lang.current)
            ctx.popup(tostring(S.counted), a.x, a.y - art.height(a.kind) * 1.2 - 40, { 0.6, 1, 0.5 })
            ctx.hearts(a.x, a.y - 40, 2)
            a.hop = 0.4
            S.t = COUNT_GAP
        else
            S.good = S.good + 1
            if S.good >= PER_ROUND then
                S.finished = true
            else
                S.phase, S.t = "next", 1.2
            end
        end
    elseif S.phase == "next" and S.t <= 0 then
        goIn()
        S.phase = "bye"
    elseif S.phase == "bye" and allHidden() then
        newFlash()
    end
    for _, a in ipairs(W.animals) do a.hop = math.max(0, (a.hop or 0) - dt) end
end

function flash.done()
    return S.finished
end

function flash.party()
    ctx.stars(BUSH_X, BUSH_Y - 60, 16)
end

function flash.hidden(a)
    return a.hidden
end

-- Drawing ------------------------------------------------------------------------

local OUTLINE = { 0.23, 0.14, 0.09 }

-- The bush, big, with the things drawn back to front. It rustles while the
-- animals wait inside.
function flash.things(list)
    table.insert(list, { y = BUSH_Y, draw = function()
        local wiggle = S.phase == "wait" and math.sin(W.time * 30) * 0.04 or 0
        g.push()
        g.translate(BUSH_X, BUSH_Y)
        g.scale(1 + wiggle, 1)
        art.prop("buisson", 0, 0, 1, 5)
        art.prop("buisson", -80, 6, -1, 3.2)
        art.prop("buisson", 84, 4, 1, 3.4)
        g.pop()
    end })
end

-- The stones, on the ground, once the animals have hidden: a flat round stone
-- with its number. Standing on one fills a ring around it.
function flash.drawGround()
    local show = S.phase == "choose" or S.phase == "right" or S.phase == "again" or S.phase == "next"
        or S.phase == "bye"
    if not show then return end
    for _, st in ipairs(S.stones) do
        local shake = math.sin(st.nope * 40) * 6 * st.nope / 0.6
        local x, y = st.x + shake, st.y
        g.setColor(0, 0, 0, 0.18)
        g.ellipse("fill", x, y + 10, STONE_R + 6, STONE_R * 0.5)
        g.setColor(OUTLINE)
        g.ellipse("fill", x, y, STONE_R + 4, STONE_R * 0.62 + 4)
        g.setColor(0.8, 0.78, 0.74)
        g.ellipse("fill", x, y, STONE_R, STONE_R * 0.62)
        if st.stand > 0 then
            g.setColor(1, 0.85, 0.3)
            g.setLineWidth(6)
            g.arc("line", "open", x, y - 4, STONE_R + 12, -math.pi / 2, -math.pi / 2 + math.pi * 2 * st.stand / STAND)
        end
        art.disk(st.value, x, y - 6, 26, st.right and "ok" or st.off and "off" or "plain", ctx.fonts.disk)
    end
end

function flash.drawOnAnimal() end

-- At the top: the right answers of this round, as little stars.
function flash.drawHud()
    local x0 = 640 - (PER_ROUND - 1) * 22
    art.panel(x0 - 30, 8, (PER_ROUND - 1) * 44 + 60, 44)
    for i = 1, PER_ROUND do art.star(x0 + (i - 1) * 44, 30, 15, i <= S.good) end
end

return flash
