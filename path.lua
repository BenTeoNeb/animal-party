-- path.lua: the Number Path (le chemin des nombres). Stones numbered 0 to 10
-- wind across the meadow. An animal sits on one of them, and the sign at the
-- top says where it goes: "2 + 3 = ?" ("-" means going back). The kid
-- answers by standing on the stone of the result (in their head):
--   right:     the animal hops there stone by stone, saying the numbers and
--              filling one dot under the 3 per hop (the proof), and its
--              friend pops out by that stone
--   not right: the stone wobbles and darkens, and the animal sparkles: now
--              the kid may make it hop, one press of the bottom button next to
--              it = one hop (the right button hops back), to count it out
-- After answering the kid walks back to the start by itself. 5 trips make a
-- round.
-- Levels:
--   1  adding 1 to 3, up to 8
--   2  taking away 1 to 3
--   3  both, 1 to 5 hops, from 0 to 10
-- world.lua calls the hooks below at the right moments (see MODES there).

local art = require("art")
local sfx = require("sfx")
local lang = require("lang")

local path = {}
local W, ctx
local g = love.graphics

local STONES = 11                -- 0 to 10
local HOP_TIME = 0.4             -- seconds in the air
local NEAR = 150                 -- how close to the animal a kid must be to make it hop
local PER_ROUND = 5              -- trips in a round
local STAND = 0.6                -- seconds standing on a stone to answer with it
local ON_STONE = 40              -- how close to a stone's middle is standing on it
local AUTO_GAP = 0.15            -- seconds between the hops of the proof

path.START_X, path.START_Y = 640, 520
-- The biomes above and below the path.
path.ZONES = {
    { x1 = 16, y1 = 130, x2 = 600, y2 = 320 },
    { x1 = 680, y1 = 130, x2 = 1264, y2 = 320 },
    { x1 = 16, y1 = 560, x2 = 1264, y2 = 712 },
}

-- Where stone n is: a gentle wave from left to right.
local function stoneAt(n)
    return 140 + n * 100, 430 + math.sin(n * 0.9) * 24
end

local S = {}      -- this trip: start, hops (+1 or -1), done, animal, friend...
path.state = S    -- (read by the tests)

function path.setup(world, c)
    W, ctx = world, c
end

-- A new trip: where the animal starts, how many hops, which way.
local function newTrip()
    local level = W.level
    local dir = level == 1 and 1 or level == 2 and -1 or (love.math.random() < 0.5 and 1 or -1)
    local most = level == 3 and 5 or 3
    local n, s
    repeat
        n = love.math.random(1, most)
        if dir > 0 then
            s = love.math.random(0, (level == 1 and 8 or 10) - n)
        else
            s = love.math.random(n, level == 2 and 8 or 10)
        end
    until not (s == S.start and n == S.n)
    S.start, S.n, S.dir, S.hops, S.at = s, n, dir, 0, s
    S.phase, S.t = "play", 0
    S.answer = s + n * dir
    S.off, S.stand, S.nope, S.lock = {}, {}, {}, {}     -- stones ruled out, being stood on...
    S.help, S.auto = false, false
    for _, k in ipairs(W.kids) do              -- a kid already on a stone must step off first
        for m = 0, STONES - 1 do
            local x, y = stoneAt(m)
            if ctx.dist(k, { x = x, y = y }) < ON_STONE then S.lock[m] = k end
        end
    end
    local kind = ctx.KINDS[love.math.random(#ctx.KINDS)]
    local a = ctx.newAnimal(kind)
    a.state = "path"
    a.x, a.y = stoneAt(s)
    a.tx, a.ty, a.facing = a.x, a.y, dir
    S.animal, S.friend = a, nil
    W.animals = { a }
    ctx.journal.log("trajet", { depart = s, sauts = n * dir })
end

function path.newRound()
    S.good, S.finished = 0, false
    newTrip()
end

local function hop(dir)
    local a = S.animal
    S.at = S.at + dir
    S.hops = S.hops + dir * S.dir
    a.fromX, a.fromY = a.x, a.y
    a.tx, a.ty = stoneAt(S.at)
    a.hopT, a.facing = 0, dir
    S.phase = "hop"
end

local function near(k)
    return ctx.dist(k, S.animal) < NEAR
end

-- The bottom button, next to the animal, once the kid has tried an answer:
-- one hop the sign's way (one press, one hop: holding the button does nothing
-- more, so each hop is counted).
function path.grab(k, _, fresh)
    if not fresh or not S.help or S.auto or S.phase ~= "play" or not near(k) then return end
    if S.hops < S.n then
        hop(S.dir)
    else
        S.animal.nope = 0.6          -- already there: it shakes its head
        sfx.play("full")
    end
end

-- The right button: hop back one, to fix a mistake.
function path.drop(k)
    if not S.help or S.auto or S.phase ~= "play" or not near(k) or S.hops <= 0 then return end
    hop(-S.dir)
end

function path.arrive() end

-- A kid answered with stone m (and walks back to the start).
local function answer(m, k)
    k.autoTo = { path.START_X, path.START_Y }
    ctx.journal.log("reponse", { joueur = k.player, depart = S.start, sauts = S.n * S.dir, choisi = m,
        juste = m == S.answer, aide = S.help })
    if m == S.answer then
        S.auto, S.t = true, 0.3                 -- the animal hops there, to show it
    else
        S.off[m], S.nope[m], S.help = true, 0.6, true
        sfx.play("drop")
    end
end

-- Standing on a stone for a moment answers with it (not the animal's own
-- stone, nor one ruled out, nor one the kid was already on).
local function standOnStones(dt)
    for m = 0, STONES - 1 do
        local x, y = stoneAt(m)
        local who
        for _, k in ipairs(W.kids) do
            if ctx.dist(k, { x = x, y = y }) < ON_STONE then
                if S.lock[m] ~= k and not k.autoTo then who = k end
            elseif S.lock[m] == k then
                S.lock[m] = nil
            end
        end
        if who and not S.off[m] and m ~= S.at and S.phase == "play" and not S.auto then
            S.stand[m] = (S.stand[m] or 0) + dt
            if S.stand[m] >= STAND then
                S.stand[m] = 0
                answer(m, who)
                return
            end
        else
            S.stand[m] = math.max(0, (S.stand[m] or 0) - dt * 2)
        end
    end
end

function path.updateAnimal(a, dt)
    if a ~= S.animal or not a.hopT then return end
    a.hopT = a.hopT + dt
    local u = math.min(1, a.hopT / HOP_TIME)
    a.x = a.fromX + (a.tx - a.fromX) * u
    a.y = a.fromY + (a.ty - a.fromY) * u
    a.hop = (1 - u) * 0.4            -- world.lua draws it higher in the middle of the hop
    a.moving = 100
    if u >= 1 then
        a.hopT, a.hop, a.moving = nil, 0, false
        -- landed: say the number of the stone
        local x, y = stoneAt(S.at)
        sfx.count(S.at, lang.current)
        ctx.popup(tostring(S.at), x, y - 110, { 1, 0.9, 0.4 })
        S.phase = "play"
        if S.hops == S.n then S.phase, S.t = "landed", 0.5 end
    end
end

function path.update(dt)
    for m in pairs(S.nope) do S.nope[m] = math.max(0, S.nope[m] - dt) end
    if W.phase ~= "play" then return end
    standOnStones(dt)
    S.t = S.t - dt
    if S.auto and S.phase == "play" and S.t <= 0 then
        -- the proof: hop by hop to the answer (from wherever it is now)
        if S.hops < S.n then hop(S.dir) else hop(-S.dir) end
        S.t = AUTO_GAP
    elseif S.phase == "landed" and S.t <= 0 then
        -- its friend pops out by the stone
        local x, y = stoneAt(S.at)
        local f = ctx.newAnimal(S.animal.kind)
        f.state, f.x, f.y, f.facing = "friend", x + 46 * -S.dir, y + 60, S.dir
        f.hop = 0.4
        S.friend = f
        table.insert(W.animals, f)
        ctx.hearts(x, y - 40, 6)
        sfx.play("home")
        S.phase, S.t = "together", 1.8
        S.good = S.good + 1
        ctx.journal.log("arrive", { numero = S.at })
    elseif S.phase == "together" and S.t <= 0 then
        if S.good >= PER_ROUND then S.finished = true else newTrip() end
    end
    for _, a in ipairs(W.animals) do
        if a.state == "friend" then a.hop = math.max(0, (a.hop or 0) - dt) end
    end
end

function path.done()
    return S.finished
end

function path.party()
    local x, y = stoneAt(S.at)
    ctx.stars(x, y - 60, 16)
end

function path.hidden() return false end
function path.things() end
-- Once the kid has tried an answer, the animal sparkles: it can be made to hop.
function path.drawOnAnimal(a)
    if a ~= S.animal or not S.help or S.auto or S.phase ~= "play" then return end
    local t = W.time * 5
    local top = a.y - art.height(a.kind) * 1.2
    art.star(a.x + 24, top - 6 - math.abs(math.sin(t)) * 8, 9, true)
    art.star(a.x - 22, top + 2 - math.abs(math.cos(t)) * 8, 7, true)
end

-- Drawing ------------------------------------------------------------------------

local OUTLINE = { 0.23, 0.14, 0.09 }

-- The path: a soft dirt trail, and the stepping stones on it. The start stone
-- glows blue, the ones the animal hopped on yellow, the landing one green.
function path.drawGround()
    g.setColor(0.78, 0.66, 0.45, 0.6)
    g.setLineWidth(46)
    local pts = {}
    for n = 0, STONES - 1 do
        local x, y = stoneAt(n)
        pts[#pts + 1], pts[#pts + 2] = x, y
    end
    g.setLineJoin("bevel")
    g.line(pts)
    for n = 0, STONES - 1 do
        local x, y = stoneAt(n)
        local lo, hi = math.min(S.start, S.at), math.max(S.start, S.at)
        local kind
        if S.phase == "together" and n == S.at then kind = "ok"
        elseif n == S.start then kind = "start"
        elseif S.off[n] then kind = "off"
        elseif n >= lo and n <= hi and (S.hops > 0) then kind = "todo" end
        local shake = math.sin((S.nope[n] or 0) * 40) * 6 * (S.nope[n] or 0) / 0.6
        art.stone(n, x + shake, y, 84, kind, ctx.fonts.board)
        if (S.stand[n] or 0) > 0 then          -- standing on it: a ring fills
            g.setColor(1, 0.85, 0.3)
            g.setLineWidth(6)
            g.arc("line", "open", x, y, 52, -math.pi / 2, -math.pi / 2 + math.pi * 2 * S.stand[n] / STAND)
        end
    end
end

-- The sign at the top: "2 + 3 = ?", with one dot per hop under the 3 (they
-- fill as the animal hops), and the stars of the round's trips.
function path.drawHud()
    local x0, y0, w, h = 640 - 230, 6, 460, 120
    art.panel(x0, y0, w, h)
    local f = ctx.fonts.sign
    local function at(text, cx, color)
        ctx.outlined(text, f, cx - 60, y0 + 46 - f:getHeight() / 2, 120, color)
    end
    at(tostring(S.start), x0 + 60, { 0.6, 0.8, 1 })
    at(S.dir > 0 and "+" or "-", x0 + 135, { 1, 1, 1 })
    at(tostring(S.n), x0 + 210, { 1, 0.9, 0.4 })
    at("=", x0 + 285, { 1, 1, 1 })
    local landed = S.phase == "together"
    at(landed and tostring(S.at) or "?", x0 + 370, landed and { 0.6, 1, 0.5 } or { 1, 1, 1 })
    -- one dot per hop
    local dx = 18
    local d0 = x0 + 210 - (S.n - 1) * dx / 2
    for i = 1, S.n do
        local full = i <= S.hops
        g.setColor(OUTLINE)
        g.circle("fill", d0 + (i - 1) * dx, y0 + 100, 8)
        if full then g.setColor(1, 0.85, 0.3) else g.setColor(0.95, 0.92, 0.85) end
        g.circle("fill", d0 + (i - 1) * dx, y0 + 100, 6)
    end
    -- the trips of this round
    art.panel(x0 + w + 12, y0, 38, h)
    for i = 1, PER_ROUND do art.star(x0 + w + 31, y0 + 16 + (i - 1) * 22, 9, i <= S.good) end
end

return path
