-- flash.lua: Peekaboo! (Coucou !) Animals hop out of their hiding places (a
-- bush, a flowery bush, a hollow log), in a dice pattern, for a moment, then
-- hide again: how many were there? Walk onto the stone with that number.
-- Seeing a small number at a glance, without counting one by one, makes
-- counting much faster later; with two or three hiding places, the kids add
-- the groups together.
--   right:     they come out again and are counted together, one by one,
--              then the sum is shown ("2 + 3 = 5")
--   not right: the stone wobbles and greys, and they peek out again
-- After answering, the kid walks back to the start by itself. 5 right answers
-- make a round (the party and a star). Levels:
--   1  one hiding place, 1 to 4 animals, 3 stones
--   2  two hiding places, 1 to 3 animals each (add them), 3 stones
--   3  three hiding places, 1 to 3 animals each, 4 stones
-- world.lua calls the hooks below at the right moments (see MODES there).

local art = require("art")
local sfx = require("sfx")
local lang = require("lang")

local flash = {}
local W, ctx
local g = love.graphics

local SHOW_Y = 385                       -- where the animals stand when out
local STONE_Y, STONE_R, STONE_W = 645, 50, 112
local PER_ROUND = 5                      -- right answers in a round
-- The ladder of steps (adaptive, see progress.lua): how many hiding places,
-- animals behind each, seconds out, stones to choose from.
flash.STEPS = {
    { places = 1, group = { 1, 3 }, show = 3, choices = 3 },
    { places = 1, group = { 1, 4 }, show = 3, choices = 3 },
    { places = 1, group = { 2, 4 }, show = 2.2, choices = 3 },
    { places = 2, group = { 1, 2 }, show = 3.5, choices = 3 },
    { places = 2, group = { 1, 3 }, show = 3.5, choices = 3 },
    { places = 2, group = { 1, 4 }, show = 3, choices = 4 },
    { places = 3, group = { 1, 3 }, show = 4, choices = 4 },
    { places = 3, group = { 1, 4 }, show = 3.5, choices = 4 },
}
local STAND = 1.5                        -- seconds standing on a stone to choose it (or press A on it)
local COUNT_GAP = 0.45                   -- seconds between two numbers when counting them

-- The hiding places: the drawing, how tall it is shown, and where they stand
-- when there are one, two or three of them (their feet).
local HIDES = { cachette_buisson = 165, cachette_feuillu = 165, cachette_tronc = 120 }
local PLACES = {
    { { 640, 300 } },
    { { 430, 300 }, { 850, 300 } },
    { { 320, 305 }, { 640, 285 }, { 960, 305 } },
}

flash.TURNS = true               -- with two kids, they answer in turns
flash.START_X, flash.START_Y = 640, 540      -- below the animals: not in front of them
-- The biomes keep to the edges: the hiding places, the animals and the
-- stones are in the middle.
flash.ZONES = {
    { x1 = 300, y1 = 10, x2 = 980, y2 = 172 },
    { x1 = 16, y1 = 400, x2 = 330, y2 = 712 },
    { x1 = 950, y1 = 400, x2 = 1264, y2 = 712 },
}

-- Dice patterns: where each animal stands, in steps from the middle.
local PATTERNS = {
    { { 0, 0 } },
    { { -1, 0 }, { 1, 0 } },
    { { -1, 0.5 }, { 0, -0.5 }, { 1, 0.5 } },
    { { -1, -0.5 }, { 1, -0.5 }, { -1, 0.5 }, { 1, 0.5 } },
}
local STEP_X, STEP_Y = 62, 70

local S = {}      -- this round: phase, timer, groups, n, stones, right answers...
flash.state = S   -- (read by the tests)

function flash.setup(world, c)
    W, ctx = world, c
end

local function hideSpot(h)
    return h.x + ctx.rand(-40, 40), h.y - 12
end

-- Send the animals out of their hiding places (to their pattern), or back in.
local function goOut()
    for _, a in ipairs(W.animals) do
        a.hidden, a.tx, a.ty = false, a.spotX, a.spotY
    end
    for _, h in ipairs(S.hides) do sfx.play("grab_" .. h.kind) end
end

local function goIn()
    for _, a in ipairs(W.animals) do a.tx, a.ty = hideSpot(a.hide) end
end

-- A new peekaboo: the hiding places, how many animals behind each one, the stones.
local function newFlash()
    local st = flash.STEPS[W.level]
    S.st = st
    local places = PLACES[st.places]
    local names = ctx.shuffle({ "cachette_buisson", "cachette_feuillu", "cachette_tronc" })
    local kinds = ctx.shuffle({ unpack(ctx.KINDS) })
    local n
    repeat
        S.hides, n = {}, 0
        for i, p in ipairs(places) do
            local c = love.math.random(st.group[1], st.group[2])
            S.hides[i] = { x = p[1], y = p[2], image = names[i], kind = kinds[i], count = c }
            n = n + c
        end
    until n ~= S.n or st.places == 3
    S.n = n
    W.animals = {}
    for _, h in ipairs(S.hides) do
        for _, p in ipairs(PATTERNS[h.count]) do
            local a = ctx.newAnimal(h.kind)
            a.state, a.hidden, a.hide = "show", true, h
            a.x, a.y = hideSpot(h)
            a.spotX = h.x + p[1] * STEP_X + ctx.rand(-5, 5)
            a.spotY = SHOW_Y + p[2] * STEP_Y + ctx.rand(-4, 4)
            a.tx, a.ty, a.facing = a.x, a.y, 1
            table.insert(W.animals, a)
        end
    end
    -- the stones: the right number and its neighbours, in a shuffled row
    local values, seen = { n }, { [n] = true }
    while #values < st.choices do
        local v = n + love.math.random(-2, 2)
        if v >= 1 and v <= 15 and not seen[v] then values[#values + 1], seen[v] = v, true end
    end
    ctx.shuffle(values)
    S.stones = {}
    for i, v in ipairs(values) do
        table.insert(S.stones, { value = v, x = 640 + (i - (#values + 1) / 2) * 160, y = STONE_Y,
            stand = 0, nope = 0, off = false })
    end
    S.phase, S.t, S.tries, S.sum = "wait", 0.8, 0, nil
end

function flash.newRound()
    S.good, S.finished, S.n = 0, false, nil
    newFlash()
    ctx.journal.log("manche", { niveau = W.level, coucou = true })
end

-- After answering, the kids walk back to where they started (not left
-- standing on the stones).
local function sendKidsBack()
    for i, k in ipairs(W.kids) do
        k.autoTo = { flash.START_X - 40 * (#W.kids - 1) + (i - 1) * 80, flash.START_Y }
    end
end

local function choose(stone, k)
    S.tries = S.tries + 1
    local groups = {}
    for i, h in ipairs(S.hides) do groups[i] = h.count end
    ctx.journal.log("choix", { joueur = k.player, montre = S.n, groupes = groups, choisi = stone.value,
        essai = S.tries })
    sendKidsBack()
    if stone.value == S.n then
        ctx.answer(S.tries == 1)              -- (adapts the difficulty from the next one)
        W.nextTurn()                          -- (two kids: the other one answers the next)
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

-- A on a stone chooses it right away (no waiting).
function flash.grab(k, _, fresh)
    if not fresh or S.phase ~= "choose" or k.autoTo or not W.myTurn(k) then return end
    for _, st in ipairs(S.stones) do
        if not st.off and ctx.dist(k, st) < STONE_R then
            st.stand = 0
            choose(st, k)
            return
        end
    end
end

function flash.arrive() end                  -- (the stones are checked in flash.update)

-- The kids choose by standing on a stone for a moment (not one they were
-- already standing on when the stones appeared, nor while walking back).
local function standOnStones(dt)
    for _, st in ipairs(S.stones) do
        local who
        for _, k in ipairs(W.kids) do
            if ctx.dist(k, st) < STONE_R then
                if st.lock ~= k and not k.autoTo and W.myTurn(k) then who = k end
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
    -- back behind its hiding place: hidden (it went behind it to get there)
    if a.ty < a.hide.y and math.abs(a.y - a.ty) < 3 then a.hidden = true end
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
        S.phase, S.t = "out", S.st.show
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
        S.phase, S.t = "out", S.st.show * 0.8
        goOut()
    elseif S.phase == "right" and S.t <= 0 and allOut() then
        -- count them together, one by one (hiding place after hiding place)
        if S.counted < S.n then
            S.counted = S.counted + 1
            local a = W.animals[S.counted]
            sfx.count(S.counted, lang.current)
            ctx.popup(tostring(S.counted), a.x, a.y - art.height(a.kind) * 1.2 - 40, { 0.6, 1, 0.5 })
            ctx.hearts(a.x, a.y - 40, 2)
            a.hop = 0.4
            S.t = COUNT_GAP
        else
            -- then the sum, when there were several groups: "2 + 3 = 5"
            if #S.hides > 1 then
                local parts = {}
                for i, h in ipairs(S.hides) do parts[i] = tostring(h.count) end
                S.sum = table.concat(parts, " + ") .. " = " .. S.n
            end
            S.good = S.good + 1
            if S.good >= PER_ROUND then
                S.finished = true
            else
                S.phase, S.t = "next", #S.hides > 1 and 2.2 or 1.2
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
    for _, h in ipairs(S.hides) do ctx.stars(h.x, h.y - 60, 10) end
end

function flash.hidden(a)
    return a.hidden
end

-- Drawing ------------------------------------------------------------------------

-- The hiding places, with the things drawn back to front (their feet). They
-- rustle while the animals wait inside.
function flash.things(list)
    for i, h in ipairs(S.hides) do
        table.insert(list, { y = h.y, draw = function()
            local im = art.image(h.image)
            local wiggle = S.phase == "wait" and math.sin(W.time * 30 + i) * 0.04 or 0
            g.push()
            g.translate(h.x, h.y)
            g.scale(1 + wiggle, 1)
            g.setColor(0, 0, 0, 0.18)
            g.ellipse("fill", 0, 0, HIDES[h.image] * 0.55, HIDES[h.image] * 0.14)
            if im then
                local sc = HIDES[h.image] / im:getHeight()
                g.setColor(1, 1, 1)
                g.draw(im, 0, 8, 0, sc, sc, im:getWidth() / 2, im:getHeight())
            else
                art.prop("buisson", 0, 0, 1, 5)
            end
            g.pop()
        end })
    end
end

-- The stones, on the ground, once the animals have hidden: a stepping stone
-- with its number painted on. Standing on one fills a ring around it.
function flash.drawGround()
    local show = S.phase == "choose" or S.phase == "right" or S.phase == "again" or S.phase == "next"
        or S.phase == "bye"
    if not show then return end
    for i, st in ipairs(S.stones) do
        local shake = math.sin(st.nope * 40) * 6 * st.nope / 0.6
        local x, y = st.x + shake, st.y
        art.stone(st.value, x, y, STONE_W, st.right and "ok" or st.off and "off" or nil, ctx.fonts.disk, i)
        if st.stand > 0 then
            g.setColor(1, 0.85, 0.3)
            g.setLineWidth(6)
            g.arc("line", "open", x, y, STONE_R + 14, -math.pi / 2, -math.pi / 2 + math.pi * 2 * st.stand / STAND)
        end
    end
end

function flash.drawOnAnimal() end

-- At the top: the right answers of this round, as little stars; under them,
-- after a right answer with several groups, the sum.
function flash.drawHud()
    local x0 = 640 - (PER_ROUND - 1) * 22
    art.panel(x0 - 30, 8, (PER_ROUND - 1) * 44 + 60, 44)
    for i = 1, PER_ROUND do art.star(x0 + (i - 1) * 44, 30, 15, i <= S.good) end
    if S.sum and (S.phase == "next" or S.phase == "bye" or S.finished) then
        local f = ctx.fonts.sign
        local w = f:getWidth(S.sum) + 60
        art.paper(640 - w / 2, 62, w, 84)
        g.setFont(f)
        g.setColor(art.OUTLINE)
        g.printf(S.sum, 640 - w / 2, 104 - f:getHeight() / 2, w, "center")
    end
end

return flash
