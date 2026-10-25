-- world.lua: the Animal Party! Each pen has a sign with an animal and a
-- number: bring exactly that many of that animal into the pen.
--
-- The sign is a "ten-frame" (two rows of 5 boxes): a box fills in for each
-- animal inside, and the animals too many show in red. Three levels:
--   1 count:    the pens are empty, bring 1 to 5 animals
--   2 add:      some animals are already inside, bring the missing ones
--   3 take away: some pens have too many, lead the extra ones out
-- No timer, no losing: when all three pens are right, it's a party (a star),
-- and the next round starts. After 3 rounds the next level comes.

local input = require("input")
local sfx = require("sfx")
local art = require("art")
-- the game log (journal.lua) is not shipped (see build.sh): without it, nothing is logged
local hasJournal, journal = pcall(require, "journal")
if not hasJournal then
    journal = setmetatable({}, { __index = function() return function() end end })
end
local lang = require("lang")
local T = lang.t
-- The other games on the same meadow. Each is a module with the same hooks,
-- called below when there is one for the current game (world.rules); the
-- pens game is this file's own default rules.
--   START_X, START_Y, ZONES (optional)   where the kids start, the biome zones
--   newRound(level), grab(k, best, fresh), drop(k) (optional), arrive(k), updateAnimal(a, dt),
--   update(dt), done(), party(), hidden(a), things(list), drawGround(),
--   drawOnAnimal(a, shake), drawHud()
--   partyMove, busy(), partyAction(k, action) (optional): the kids may walk
--   during the party, which lasts while busy() (the train driving away)
local progress = require("progress")
local MODES = { train = require("train"), flash = require("flash"), path = require("path"),
    nid = require("nid"), oeufs = require("oeufs") }

local world = {}
local g = love.graphics

world.W, world.H = 1280, 720

-- Tweak these to make the game easier or harder.
local KID_SPEED = 230         -- running, arms free
local KID_WALK_SPEED = 185    -- walking, when animals are following you
-- The pens' ladder of steps (adaptive difficulty, see progress.lua): what the
-- pens ask for. count: empty pens, 1 to max; add: some already in, up to max;
-- take: too many in some pens; spare: animals more than needed, per pen.
local STEPS = {
    { kind = "count", max = 3, spare = 2 },
    { kind = "count", max = 5, spare = 2 },
    { kind = "add", max = 6, spare = 1 },
    { kind = "add", max = 8, spare = 1 },
    { kind = "add", max = 9, spare = 1 },
    { kind = "take", max = 6, spare = 1 },
    { kind = "mix", max = 8, spare = 1 },
    { kind = "mix", max = 9, spare = 1 },
}
local PENS_UP = 2             -- clean rounds in a row to go up a step (a round is 3 pens)
local DECOYS = 1              -- animals of each kind that no pen wants
local COUNT_GAP = 0.45        -- seconds between two animals going in (time to count out loud)

local KINDS = { "poule", "ecureuil", "marcassin", "herisson", "renard", "mouton", "biche" }

local GRASS_TILE = 380        -- width of one tile of the grass drawing, in pixels
world.GRASS_TILE = GRASS_TILE
local TOP = 20

-- The pens around the meadow, each one with its entrance (gate) facing the
-- middle: two at the top corners, one at the bottom in the middle. The sign
-- is on the far side from the gate, the animals stand near the gate.
local PENS = {
    { x = 14, y = 4, w = 320, h = 262, gate = "bottom", roof = { 0.9, 0.25, 0.2 }, name = "rouge" },
    { x = 946, y = 4, w = 320, h = 262, gate = "bottom", roof = { 0.25, 0.5, 0.95 }, name = "bleue" },
    { x = 480, y = 482, w = 320, h = 232, gate = "top", roof = { 1, 0.78, 0.15 }, name = "jaune" },
}
for _, r in ipairs(PENS) do
    r.hutX = r.x + r.w - 45
    r.hutY = r.gate == "top" and r.y + r.h - 24 or r.y + 75
end
world.pens = PENS        -- each one: kind, target (set by newRound)
local active = PENS      -- the pens of this game (none in the other games)

-- Where the kids start: the clearing in the middle.
local START_X, START_Y = 640, 380

-- The three parts of the meadow around the clearing (between the pens), and
-- the biomes that go in them (in a different place each game). Each kind of
-- animal lives in one biome: that's where to find it.
local ZONES = {
    { x1 = 360, y1 = 24, x2 = 920, y2 = 250 },      -- top, between the two pens
    { x1 = 16, y1 = 280, x2 = 450, y2 = 712 },      -- bottom left
    { x1 = 830, y1 = 280, x2 = 1264, y2 = 712 },    -- bottom right
}
local BIOMES = {
    { name = "pins", trees = { "sapin", "epicea", "bouleau" },
      props = { "pomme_de_pin", "pomme_de_pin", "fougere", "champignon", "rocher" },
      animals = { "ecureuil", "renard" } },
    { name = "verger", trees = { "pommier", "cerisier", "fruitier" },
      props = { "fleurs", "fleurs", "fleurs", "feuille", "buisson" },
      animals = { "poule", "mouton" } },
    { name = "chenes", trees = { "chene", "erable", "saule" },
      props = { "glands", "glands", "buche", "branche", "buisson", "champignon" },
      animals = { "marcassin", "herisson", "biche" }, pond = true },
}
local POND_W = 210         -- how wide the pond drawing is shown

-- The huts of the pens are picked at random among these drawings, three
-- different ones each round (the ones whose image exists).
local HUTS = {
    "cabane_souche", "cabane_coquillage", "cabane_pomme_de_pin", "cabane_rondins",
    "cabane_champignon", "maison_rouge", "maison_bleue", "maison_jaune",
}

local fonts = {}

local function dist(a, b)
    return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2)
end

local function clamp(v, lo, hi)
    return math.max(lo, math.min(hi, v))
end

local function rand(a, b)
    return a + love.math.random() * (b - a)
end

local function shuffle(t)
    for i = #t, 2, -1 do
        local j = love.math.random(i)
        t[i], t[j] = t[j], t[i]
    end
    return t
end

local function setAnim(o, name)
    if o.anim ~= name then o.anim, o.animT = name, 0 end
end

local function penAt(o)
    for i, r in ipairs(active) do
        if o.x > r.x + 8 and o.x < r.x + r.w - 8 and o.y > r.y + 8 and o.y < r.y + r.h - 4 then
            return i
        end
    end
end

-- The pen's sign: a small plaque in the corner away from the gate and the
-- hut, with the number it wants and its animal ("3 [fox]").
local SIGN_W, SIGN_H = 124, 66
local function signRect(pen)
    if pen.gate == "top" then return pen.x + 10, pen.y + pen.h - 14 - SIGN_H, SIGN_W, SIGN_H end
    return pen.x + 10, pen.y + 14, SIGN_W, SIGN_H
end

-- Where the animals of a pen stand: everywhere but the side with the sign
-- and the hut, never behind the sign (an animal is drawn up to ANIMAL_H
-- pixels above its feet).
local ANIMAL_H = 74
local function penArea(r)
    local _, sy, _, sh = signRect(r)
    if r.gate == "top" then return r.x + 40, r.x + r.w - 40, r.y + 62, sy - 8 end
    return r.x + 40, r.x + r.w - 60, sy + sh + 8 + ANIMAL_H, r.y + r.h - 20
end

-- Animals don't walk over one another (easier to count them): their feet
-- keep apart, GAP_X pixels side by side, less front to back (GAP_Y).
local GAP_X, GAP_Y = 46, 26

-- How close the nearest other animal is to (x, y), in GAP units (1 = touching).
local function crowd(x, y, me)
    local best = math.huge
    for _, b in ipairs(world.animals or {}) do
        if b ~= me and b.state ~= "follow" then
            local dx, dy = (b.x - x) / GAP_X, (b.y - y) / GAP_Y
            best = math.min(best, math.sqrt(dx * dx + dy * dy))
        end
    end
    return best
end

-- The freest spot in a pen: the one furthest from the other animals, out of
-- a few tries.
local function spotIn(r, me)
    local x1, x2, y1, y2 = penArea(r)
    local bx, by, bd = nil, nil, -1
    for _ = 1, 12 do
        local x, y = rand(x1, x2), rand(y1, y2)
        local d = crowd(x, y, me)
        if d > bd then bx, by, bd = x, y, d end
    end
    return bx, by
end

-- Trees are solid: push `o` out of every trunk. Each trunk is a flat ellipse at
-- the foot of the tree, so you can still walk behind the leaves.
local BODY = 10            -- half-width of a kid or an animal's feet
local function blockByTrees(o)
    for _, tr in ipairs(world.trees) do
        local r = (art.TRUNKS[tr.kind] or 15) * tr.s + BODY
        local dx, dy = o.x - tr.x, (o.y - tr.y) / 0.5
        local d = math.sqrt(dx * dx + dy * dy)
        if d < r then
            if d < 0.01 then dx, dy, d = 1, 0, 1 end
            o.x = tr.x + dx / d * r
            o.y = tr.y + dy / d * r * 0.5
        end
    end
end

-- Two kids can't walk through each other: if their feet overlap, push them
-- apart (half each), then make sure neither was pushed into a tree.
local KID_GAP = 26
local function separateKids()
    local a, b = world.kids[1], world.kids[2]
    if not (a and b) then return end
    local dx, dy = b.x - a.x, (b.y - a.y) / 0.5
    local d = math.sqrt(dx * dx + dy * dy)
    if d >= KID_GAP then return end
    if d < 0.01 then dx, dy, d = 1, 0, 1 end
    local push = (KID_GAP - d) / 2
    local nx, ny = dx / d, dy / d * 0.5
    a.x, a.y = a.x - nx * push, a.y - ny * push
    b.x, b.y = b.x + nx * push, b.y + ny * push
    blockByTrees(a)
    blockByTrees(b)
end

-- The pond is solid too (an ellipse, a little smaller than the drawing).
local function inPond(o, margin)
    local p = world.pond
    if not p then return false end
    local dx, dy = (o.x - p.x) / (p.rx + (margin or 0)), (o.y - p.y) / (p.ry + (margin or 0))
    return dx * dx + dy * dy < 1
end

local function blockByPond(o)
    local p = world.pond
    if not p or not inPond(o, BODY) then return end
    local dx, dy = (o.x - p.x) / (p.rx + BODY), (o.y - p.y) / (p.ry + BODY)
    local d = math.sqrt(dx * dx + dy * dy)
    if d < 0.01 then dx, dy, d = 1, 0, 1 end
    o.x = p.x + dx / d * (p.rx + BODY)
    o.y = p.y + dy / d * (p.ry + BODY)
end

-- The fences of the pens are solid for the kids: you can only get in through
-- the gate. (px, py) is where the kid was before moving, to know which side
-- of a fence they come from. Each pen's fences, with the gap of its gate:
-- rows { y, x1, x2 } and columns { x, y1, y2 }.
local WALL = 7             -- how thick a fence is, for the feet
for _, r in ipairs(PENS) do
    local top, bottom = r.y + 6, r.y + r.h - 2
    local gx1, gx2 = r.x + r.w * art.PEN_GAP_H[1], r.x + r.w * art.PEN_GAP_H[2]
    local gy1, gy2 = r.y + r.h * art.PEN_GAP[1], r.y + r.h * art.PEN_GAP[2]
    r.rows, r.cols = {}, { { r.x + r.w, top, bottom } }
    for _, y in ipairs({ top, bottom }) do
        if (r.gate == "top" and y == top) or (r.gate == "bottom" and y == bottom) then
            table.insert(r.rows, { y, r.x, gx1 })
            table.insert(r.rows, { y, gx2, r.x + r.w })
        else
            table.insert(r.rows, { y, r.x, r.x + r.w })
        end
    end
    if r.gate == "left" then
        table.insert(r.cols, { r.x, top, gy1 })
        table.insert(r.cols, { r.x, gy2, bottom })
    else
        table.insert(r.cols, { r.x, top, bottom })
    end
end

local function blockByFences(o, px, py)
    for _, r in ipairs(active) do
        for _, row in ipairs(r.rows) do
            local y, x1, x2 = row[1], row[2], row[3]
            if o.x > x1 - BODY and o.x < x2 + BODY and math.abs(o.y - y) < WALL then
                o.y = y + (py < y and -1 or 1) * WALL
            end
        end
        for _, col in ipairs(r.cols) do
            local x, y1, y2 = col[1], col[2], col[3]
            if o.y > y1 - WALL and o.y < y2 + WALL and math.abs(o.x - x) < BODY then
                o.x = x + (px < x and -1 or 1) * BODY
            end
        end
    end
end

local function popup(text, x, y, color)
    -- (several numbers at the same place: only the last one)
    for i = #world.popups, 1, -1 do
        if math.abs(world.popups[i].x - x) < 40 and math.abs(world.popups[i].y - y) < 40 then
            table.remove(world.popups, i)
        end
    end
    table.insert(world.popups, { text = text, x = x, y = y, age = 0, life = 1.2, color = color })
end

local function hearts(x, y, n)
    for _ = 1, n do
        table.insert(world.particles, { heart = true, x = x + rand(-15, 15), y = y,
            vx = rand(-20, 20), vy = rand(-70, -40), r = rand(0.6, 1), life = 1.2, max = 1.2 })
    end
end

local function stars(x, y, n)
    for _ = 1, n do
        local a = rand(0, math.pi * 2)
        local v = rand(120, 320)
        table.insert(world.particles, { star = true, x = x, y = y, vx = math.cos(a) * v,
            vy = math.sin(a) * v - 80, r = rand(8, 16), life = 1.4, max = 1.4 })
    end
end

-- How many animals are counted in pen i (the ones still walking in are not yet).
local function penCount(i)
    local n = 0
    for _, a in ipairs(world.animals) do
        if a.state == "home" and a.pen == i and a.counted then n = n + 1 end
    end
    return n
end

-- The pen's number just changed to n: say it (shown next to the sign), and
-- cheer if it's right.
local function counted(i, n, out)
    local pen = PENS[i]
    pen.countedAt = world.time
    local right = n == pen.target
    if n > pen.target and not out then world.clean = false end     -- one too many went in
    local x, y, w, h = signRect(pen)
    popup(tostring(n), x + w + 40, y + h / 2 - 26, right and { 0.6, 1, 0.5 } or n > pen.target and { 1, 0.55, 0.45 } or nil)
    sfx.count(n, lang.current)
    if right then
        hearts(pen.x + 90, pen.y + 60, 5)
        for _, k in ipairs(world.kids) do
            if penAt(k) == i then k.cheer = math.min(1.8, art.duration(k.look.id, "saut") or 1) end
        end
    end
end

-- Setup --------------------------------------------------------------------------

-- (Re)make the fonts, sharp for the current screen size.
function world.makeFonts()
    fonts.sign = art.font(60)
    fonts.big = art.font(44)
    fonts.small = art.font(20)
    fonts.badge = art.font(26)
    fonts.board = art.font(30)
    fonts.disk = art.font(36)
    fonts.plate = art.font(22)
end

function world.load()
    world.makeFonts()
end

-- What each pen asks for this round: { kind, target, start }.
local function roundFor(step)
    local st = STEPS[step]
    local kinds = shuffle({ unpack(KINDS) })
    local asks = {}
    for i = 1, #PENS do
        local ask = { kind = kinds[i] }
        local takeAway = st.kind == "take" and i <= 2 or st.kind == "mix" and (i == 1 or love.math.random() < 0.4)
        if st.kind == "count" then
            ask.start, ask.target = 0, love.math.random(1, st.max)
        elseif takeAway then
            ask.target = love.math.random(1, st.max - 3)
            ask.start = ask.target + love.math.random(1, 3)
        else
            ask.start = love.math.random(1, math.min(4, st.max - 2))
            ask.target = love.math.random(ask.start + 1, math.min(st.max, ask.start + 4))
        end
        asks[i] = ask
    end
    -- the pen asking to take away is not always the top one
    return shuffle(asks)
end

local function newAnimal(kind)
    return { kind = kind, state = "free", facing = love.math.random() < 0.5 and -1 or 1,
        walk = 0, wait = rand(0, 2), anim = "repos", animT = 0 }
end

-- A free spot in the animal's biome, not on another animal, a tree, the pond
-- or a kid, and not hidden behind a tree's leaves.
local function biomeSpot(a)
    local z = world.home[a.kind]
    for _ = 1, 100 do
        a.x, a.y = rand(z.x1 + 30, z.x2 - 30), rand(z.y1 + 50, z.y2 - 20)
        local ok = not inPond(a, 30)
        for _, b in ipairs(world.animals) do
            if b ~= a and dist(a, b) < 50 then ok = false end
        end
        for _, k in ipairs(world.kids) do
            if dist(a, k) < 90 then ok = false end
        end
        for _, tr in ipairs(world.trees) do
            if dist(a, tr) < 50 or (math.abs(a.x - tr.x) < 50 and a.y < tr.y and a.y > tr.y - 110) then
                ok = false
            end
        end
        if ok then break end
    end
    a.tx, a.ty = a.x, a.y
end

local function newRound()
    world.phase = "play"
    world.clean = true
    world.rightFor = 0
    world.animals = {}
    world.popups = {}
    for _, k in ipairs(world.kids) do k.followers = {} end
    if world.rules then
        world.rules.newRound(world.level)
        return
    end

    -- three different huts for the pens this time
    local huts = {}
    for _, name in ipairs(HUTS) do
        if art.image(name) then table.insert(huts, name) end
    end
    shuffle(huts)

    local asks = roundFor(world.level)
    local wanted = {}
    for i, pen in ipairs(PENS) do
        local ask = asks[i]
        pen.kind, pen.target, pen.hut, pen.nope = ask.kind, ask.target, huts[i], 0
        wanted[ask.kind] = true
        for _ = 1, ask.start do
            local a = newAnimal(ask.kind)
            a.state, a.pen, a.counted = "home", i, true
            a.x, a.y = spotIn(pen, a)
            a.tx, a.ty = a.x, a.y
            table.insert(world.animals, a)
        end
        for _ = 1, math.max(0, ask.target - ask.start) + STEPS[world.level].spare do
            local a = newAnimal(ask.kind)
            biomeSpot(a)
            table.insert(world.animals, a)
        end
    end
    for _, kind in ipairs(KINDS) do
        if not wanted[kind] then
            for _ = 1, DECOYS do
                local a = newAnimal(kind)
                biomeSpot(a)
                table.insert(world.animals, a)
            end
        end
    end

    local log = {}
    for i, pen in ipairs(PENS) do log[i] = { pen.kind, asks[i].start, pen.target } end
    journal.log("manche", { niveau = world.level, enclos = log })
end

-- A biome in zone z: its trees in a few little groves, its pond, its ground
-- things; its animals will live there.
function world.makeBiome(biome, z)
    for _, kind in ipairs(biome.animals) do world.home[kind] = z end
    local w, h = z.x2 - z.x1, z.y2 - z.y1
    if biome.pond and art.image("mare") then
        local im = art.image("mare")
        local ph = POND_W * im:getHeight() / im:getWidth()
        world.pond = { x = z.x1 + w / 2 + rand(-w, w) * 0.15, y = z.y1 + h * 0.55,
            rx = POND_W * 0.4, ry = ph * 0.3, h = ph }
    end
    -- trees: their feet low enough that the leaves stay in the zone, grouped
    -- around 2 or 3 grove centers, never on the pond
    local groves = {}
    for _ = 1, h > 300 and 3 or 2 do
        table.insert(groves, { x = rand(z.x1 + 60, z.x2 - 60), y = rand(z.y1 + 130, z.y2 - 10) })
    end
    local want = math.floor(w * h / 32000)
    for _ = 1, 300 do
        local c = groves[love.math.random(#groves)]
        local tree = { x = clamp(c.x + rand(-110, 110), z.x1 + 40, z.x2 - 40),
            y = clamp(c.y + rand(-70, 70), z.y1 + 125, z.y2 - 8), s = rand(0.85, 1.05),
            kind = biome.trees[love.math.random(#biome.trees)], f = love.math.random() < 0.5 and -1 or 1 }
        local ok = not inPond(tree, 45) and dist(tree, { x = world.startX, y = world.startY }) > 150
        for _, other in ipairs(world.trees) do
            if dist(tree, other) < 85 then ok = false end
        end
        if ok then table.insert(world.trees, tree) end
        if #world.trees >= want + (world.treeCount or 0) then break end
    end
    world.treeCount = #world.trees
    if art.image("fleurs") then
        for _ = 1, math.floor(w * h / 9000) do
            local prop = { name = biome.props[love.math.random(#biome.props)], x = rand(z.x1 + 10, z.x2 - 10),
                y = rand(z.y1 + 20, z.y2 - 5), f = love.math.random() < 0.5 and -1 or 1, s = rand(0.85, 1.15) }
            if not inPond(prop, 10) then table.insert(world.props, prop) end
        end
    end
end

-- mode: "fete" (the pens, default), "train", "flash" or "path".
-- playMode: "learn" (default) or "challenge" (faster steps, helps only after
-- a mistake, a streak counter; world.challenge, read by the games too).
function world.start(chosen, level, mode, playMode)
    world.challenge = playMode == "challenge"
    world.streak, world.streakFlash = 0, 0
    world.mode = MODES[mode] and mode or "fete"
    local R = MODES[world.mode]
    world.rules = R
    active = R and {} or PENS
    local zones = R and R.ZONES or ZONES
    world.startX = R and R.START_X or START_X
    world.startY = R and R.START_Y or START_Y
    world.treeCount = 0
    world.time = 0
    world.done = false
    world.roundsWon = 0
    world.particles, world.popups = {}, {}
    world.fade = 0

    world.kids = {}
    for i, c in ipairs(chosen) do
        table.insert(world.kids, {
            player = c.player, look = art.KIDS[c.kid],
            x = world.startX - 40 + (i - 1) * 80, y = world.startY, facing = 1,
            walk = 0, anim = "repos", animT = 0, cheer = 0, followers = {},
        })
    end

    world.trees, world.props, world.pond, world.home = {}, {}, nil, {}
    world.scene = R and R.SCENE                  -- a game may have its own place (the farm)
    if world.scene then
        -- no forest: its own ground, its decor (R.DECOR), and all the animals
        -- live in its yard (R.YARD)
        for _, kind in ipairs(KINDS) do world.home[kind] = R.YARD end
    else
        for i, biome in ipairs(shuffle({ unpack(BIOMES) })) do
            world.makeBiome(biome, zones[i])
        end
        -- a few flowers in the clearing
        for _ = 1, 10 do
            table.insert(world.props, { name = love.math.random() < 0.7 and "fleurs" or "feuille",
                x = world.startX + rand(-170, 170), y = world.startY + rand(-110, 90),
                f = love.math.random() < 0.5 and -1 or 1, s = rand(0.85, 1.1) })
        end
        table.sort(world.props, function(a, b) return a.y < b.y end)
    end

    local kidNames = {}
    for _, k in ipairs(world.kids) do kidNames[#kidNames + 1] = k.look.id end
    -- the step to start on: from the menu's level and the kids' saved steps
    world.kidIds = kidNames
    world.steps = R and #R.STEPS or #STEPS
    world.level = progress.start(world.mode, kidNames, level, world.steps, world.challenge)
    world.ladder = { step = world.level }
    -- turns (the games where one answer is for everybody: Peekaboo, the path):
    -- with two kids, they answer one after the other (R.TURNS)
    world.turn = (R and R.TURNS and #world.kids > 1) and world.kids[1].player or nil
    journal.start({ joueurs = #chosen, enfants = kidNames, mode = world.mode, niveau = world.level,
        langue = lang.current })
    newRound()
end

function world.logEnd(how)
    journal.finish(how, { manches = world.roundsWon, niveau = world.level })
end

-- Actions ------------------------------------------------------------------------

local function kidOf(p)
    for _, k in ipairs(world.kids) do
        if k.player == p then return k end
    end
end

-- Call the nearest free animal. Inside a pen, on a real press (not held, or
-- holding the button would empty the pen), take one of its animals back out.
local GRAB_REPEAT = 0.35   -- seconds between two calls while the button is held
local function tryGrab(k, fresh)
    k.grabWait = GRAB_REPEAT
    local best, bestD
    for _, a in ipairs(world.animals) do
        if a.state == "free" then
            local d = dist(k, a)
            if d < k.look.reach and (not bestD or d < bestD) then best, bestD = a, d end
        end
    end
    if world.rules then
        world.rules.grab(k, best, fresh)
        return
    end
    local here = penAt(k)
    if not best and fresh and here then
        for _, a in ipairs(world.animals) do
            if a.state == "home" and a.pen == here then
                local d = dist(k, a)
                if d < k.look.reach + 40 and (not bestD or d < bestD) then best, bestD = a, d end
            end
        end
    end
    if not best then return end
    if #k.followers >= k.look.carry then
        if fresh then sfx.play("full"); journal.log("plein", { joueur = k.player }) end   -- "bonk"
        return
    end
    local out = best.state == "home"
    journal.log(out and "ressorti" or "attrape", { joueur = k.player, animal = best.kind, enclos = best.pen })
    local wasCounted, pen = best.counted, best.pen
    best.pen, best.counted = nil, nil
    best.vx, best.vy = 0, 0
    best.state = "follow"
    table.insert(k.followers, best)
    hearts(best.x, best.y - 40, 1)
    sfx.play("grab_" .. best.kind)       -- each animal has its own voice
    if out and wasCounted then counted(pen, penCount(pen), true) end
end

-- An animal goes into pen i: it walks to a spot inside, and is counted
-- `delay` seconds later (one after the other, to count them out loud).
local function enter(a, i, delay)
    a.state, a.pen, a.counted, a.countIn = "home", i, false, delay
    a.tx, a.ty = spotIn(PENS[i], a)
    a.wait = rand(1, 2)
end

-- Not the animal this pen wants: it shakes its head and stays in line.
local function refuse(a, i)
    a.nope = 0.6
    PENS[i].nope = 0.6
    world.clean = false
end

-- Let go of one animal (the last in line); in its own pen, it goes in.
-- Holding the button lets go of the next ones too, one after the other.
local DROP_FIRST, DROP_REPEAT = 0.4, 0.2   -- seconds before the 2nd, then between the next ones
local function letGo(k)
    local a = table.remove(k.followers)
    journal.log("lache", { joueur = k.player, animal = a.kind })
    local here = penAt(k)
    if here and not world.rules and PENS[here].kind == a.kind then
        enter(a, here, 0.2)
    else
        a.state, a.tx, a.ty, a.wait = "free", a.x, a.y, rand(1, 2)
        sfx.play("drop")
    end
end

function world.action(p, action)
    if world.phase ~= "play" then
        local R = world.rules
        if world.phase == "party" and R and R.partyAction and kidOf(p) then R.partyAction(kidOf(p), action) end
        return
    end
    local k = kidOf(p)
    if not k then return end
    if action == "grab" then
        tryGrab(k, true)
    elseif action == "drop" and world.rules and world.rules.drop then
        world.rules.drop(k)
    elseif action == "drop" and #k.followers > 0 then
        letGo(k)
        k.dropWait = DROP_FIRST
    end
end

-- Update -------------------------------------------------------------------------

local function moveToward(o, x, y, speed, dt)
    local dx, dy = x - o.x, y - o.y
    local d = math.sqrt(dx * dx + dy * dy)
    if d < 2 then return false end
    local step = math.min(d, speed * dt)
    o.x, o.y = o.x + dx / d * step, o.y + dy / d * step
    if math.abs(dx) > 2 then o.facing = dx > 0 and 1 or -1 end
    o.walk = o.walk + dt * 12
    o.moving = speed
    return true
end

-- Where follower number i should be: FOLLOW_GAP pixels behind the one in front,
-- measured along the kid's footprints (so the line takes the same turns).
local FOLLOW_FIRST, FOLLOW_GAP = 42, 40
local function trailPoint(k, along)
    local px, py = k.x, k.y
    for _, p in ipairs(k.trail or {}) do
        local d = math.sqrt((p.x - px) ^ 2 + (p.y - py) ^ 2)
        if d >= along then
            local u = along / d
            return px + (p.x - px) * u, py + (p.y - py) * u
        end
        along = along - d
        px, py = p.x, p.y
    end
    return px, py
end

-- Smooth following: the animal's speed eases toward where it should be (no
-- stop-and-go), it only turns around when it really goes the other way, and
-- its walk / run animation changes with some margin (no flickering).
local function followTrail(a, k, i, dt)
    local tx, ty = trailPoint(k, FOLLOW_FIRST + (i - 1) * FOLLOW_GAP)
    local dx, dy = tx - a.x, ty - a.y
    local wantX, wantY = dx * 7, dy * 7                 -- faster when further behind
    local w = math.sqrt(wantX * wantX + wantY * wantY)
    if w > 380 then wantX, wantY = wantX / w * 380, wantY / w * 380 end
    local blend = 1 - math.exp(-10 * dt)
    a.vx = (a.vx or 0) + (wantX - (a.vx or 0)) * blend
    a.vy = (a.vy or 0) + (wantY - (a.vy or 0)) * blend
    a.x, a.y = a.x + a.vx * dt, a.y + a.vy * dt
    local v = math.sqrt(a.vx * a.vx + a.vy * a.vy)
    if math.abs(a.vx) > 30 then a.facing = a.vx > 0 and 1 or -1 end
    a.walk = a.walk + dt * v / 20
    local cur = a.anim
    if v > 190 or (cur == "course" and v > 140) then a.moving = 200
    elseif v > 22 or (cur ~= "repos" and v > 10) then a.moving = 100
    else a.moving = false; a.walk = 0 end
end

local function updateKid(k, dt)
    k.animT = k.animT + dt
    k.cheer = math.max(0, k.cheer - dt)
    k.grabWait = math.max(0, (k.grabWait or 0) - dt)
    -- holding the grab button keeps calling animals, one after the other
    if world.phase == "play" and k.grabWait == 0 and input.held(k.player, "grab") then
        tryGrab(k, false)
    end
    k.dropWait = math.max(0, (k.dropWait or 0) - dt)
    if world.phase == "play" and k.dropWait == 0 and #k.followers > 0 and input.held(k.player, "drop") then
        letGo(k)
        k.dropWait = DROP_REPEAT
    end
    local dx, dy = input.move(k.player)
    local partyMove = world.phase == "party" and world.rules and world.rules.partyMove
    if (world.phase ~= "play" and not partyMove) or k.driving then dx, dy = 0, 0 end
    -- sent somewhere by the game (k.autoTo = { x, y }): walk there by itself
    if k.autoTo then
        local ax, ay = k.autoTo[1] - k.x, k.autoTo[2] - k.y
        local d = math.sqrt(ax * ax + ay * ay)
        if d < 6 then k.autoTo, dx, dy = nil, 0, 0 else dx, dy = ax / d, ay / d end
    end
    local len = math.sqrt(dx * dx + dy * dy)
    if len > 1 then dx, dy = dx / len, dy / len end
    local leading = #k.followers > 0
    local px, py = k.x, k.y
    local speed = (leading and KID_WALK_SPEED or KID_SPEED) * k.look.speed
    k.x = clamp(k.x + dx * speed * dt, 20, world.W - 20)
    k.y = clamp(k.y + dy * speed * dt, TOP + 20, world.H - 8)
    -- footprints: the followers walk along this trail, in a neat line
    k.trail = k.trail or {}
    local last = k.trail[1]
    if not last or (k.x - last.x) ^ 2 + (k.y - last.y) ^ 2 > 16 then
        table.insert(k.trail, 1, { x = k.x, y = k.y })
        if #k.trail > 400 then table.remove(k.trail) end
    end
    blockByTrees(k)
    blockByPond(k)
    blockByFences(k, px, py)
    if len > 0.1 then
        k.walk = k.walk + dt * 12
        if math.abs(dx) > 0.1 then k.facing = dx > 0 and 1 or -1 end
    else
        k.walk = 0
    end
    if k.cheer > 0 then setAnim(k, "saut")
    elseif len > 0.1 then setAnim(k, leading and "marche" or "course")
    else setAnim(k, "repos") end

    if world.rules then
        world.rules.arrive(k)
        return
    end
    -- Walk into a pen: the animals it wants go inside, one after the other
    -- (only when you arrive, so an animal you take back out doesn't go straight
    -- back in). The others shake their heads and stay with you.
    local pen = penAt(k)
    local arriving = pen and pen ~= k.lastPen
    k.lastPen = pen
    if arriving and #k.followers > 0 then
        local stay, n = {}, 0
        for _, a in ipairs(k.followers) do
            if a.kind == PENS[pen].kind then
                enter(a, pen, n * COUNT_GAP)
                n = n + 1
                journal.log("dedans", { joueur = k.player, animal = a.kind, enclos = pen })
            else
                refuse(a, pen)
                table.insert(stay, a)
            end
        end
        k.followers = stay
        if #stay > 0 then
            sfx.play("full")
            journal.log("non", { joueur = k.player, enclos = pen, animaux = #stay })
        end
    end
end

local function wander(a, dt, minX, maxX, minY, maxY, speed)
    a.wait = a.wait - dt
    if a.wait <= 0 then
        a.tx = clamp(a.x + rand(-120, 120), minX, maxX)
        a.ty = clamp(a.y + rand(-120, 120), minY, maxY)
        a.wait = rand(2, 4)
    end
    if not moveToward(a, a.tx, a.ty, speed, dt) then a.walk = 0 end
end

-- Two animals too close (feet inside each other's flat ellipse): push them
-- apart, half each. Not the ones following a kid (they keep their line).
-- Then put them back out of trees and the pond, or back inside their pen.
local function separateAnimals()
    local list = world.animals
    for i = 1, #list do
        local a = list[i]
        if a.state == "free" or a.state == "home" then
            for j = i + 1, #list do
                local b = list[j]
                if b.state == "free" or b.state == "home" then
                    local dx, dy = (b.x - a.x) / GAP_X, (b.y - a.y) / GAP_Y
                    local d = math.sqrt(dx * dx + dy * dy)
                    if d < 1 then
                        if d < 0.01 then dx, dy, d = love.math.random() - 0.5, 0.3, 0.3 end
                        local push = (1 - d) / 2 / d
                        a.x, a.y = a.x - dx * push * GAP_X, a.y - dy * push * GAP_Y
                        b.x, b.y = b.x + dx * push * GAP_X, b.y + dy * push * GAP_Y
                    end
                end
            end
        end
    end
    for _, a in ipairs(list) do
        if a.state == "home" and a.counted then
            local x1, x2, y1, y2 = penArea(PENS[a.pen])
            a.x, a.y = clamp(a.x, x1, x2), clamp(a.y, y1, y2)
        elseif a.state == "free" then
            blockByTrees(a)
            blockByPond(a)
        end
    end
end

local function updateAnimal(a, dt)
    a.moving = false
    a.animT = a.animT + dt
    a.nope = math.max(0, (a.nope or 0) - dt)
    if a.state == "free" then
        local z = world.home[a.kind]
        if a.spotX then                   -- an animal with its own spot (the train's): stays near it
            wander(a, dt, a.spotX - 22, a.spotX + 22, a.spotY - 12, a.spotY + 12, 30)
        else
            wander(a, dt, z.x1 + 30, z.x2 - 30, z.y1 + 50, z.y2 - 20, 40)
        end
        blockByTrees(a)
        blockByPond(a)
    elseif a.state == "follow" then
        for _, k in ipairs(world.kids) do
            for i, b in ipairs(k.followers) do
                if b == a then followTrail(a, k, i, dt) end
            end
        end
        blockByTrees(a)
    elseif a.state == "home" then
        if not a.counted then
            a.countIn = a.countIn - dt
            if not moveToward(a, a.tx, a.ty, 120, dt) then a.walk = 0 end
            -- counted once inside, and not right after the one before (time
            -- to count out loud)
            local pen = PENS[a.pen]
            if a.countIn <= 0 and penAt(a) == a.pen and world.time - (pen.countedAt or -9) >= COUNT_GAP then
                a.counted = true
                counted(a.pen, penCount(a.pen))
            end
        else
            -- now and then, go to a free spot of the pen
            a.wait = a.wait - dt
            if a.wait <= 0 then
                a.tx, a.ty = spotIn(PENS[a.pen], a)
                a.wait = rand(4, 8)
            end
            if not moveToward(a, a.tx, a.ty, 30, dt) then a.walk = 0 end
        end
    elseif world.rules then
        world.rules.updateAnimal(a, dt)          -- the other games' own states
    end
    if a.moving and a.moving > 150 then setAnim(a, "course")
    elseif a.moving then setAnim(a, "marche")
    else setAnim(a, "repos") end
end

-- All three pens right (and nobody still walking in)?
local function allRight()
    if world.rules then return world.rules.done() end
    for _, a in ipairs(world.animals) do
        if a.state == "home" and not a.counted then return false end
    end
    for i, pen in ipairs(PENS) do
        if penCount(i) ~= pen.target then return false end
    end
    return true
end

local function updateEffects(dt)
    for i = #world.particles, 1, -1 do
        local p = world.particles[i]
        p.life = p.life - dt
        p.x, p.y = p.x + p.vx * dt, p.y + p.vy * dt
        if p.star then p.vy = p.vy + 300 * dt end
        if p.life <= 0 then table.remove(world.particles, i) end
    end
    for i = #world.popups, 1, -1 do
        local p = world.popups[i]
        p.age = p.age + dt
        if p.age >= p.life then table.remove(world.popups, i) end
    end
    -- a tree is see-through while a kid or an animal is behind its leaves
    for _, tr in ipairs(world.trees) do
        local top = tr.y - (art.TREES[tr.kind] or 125) * tr.s * 0.9
        local behind = false
        for _, list in ipairs({ world.kids, world.animals }) do
            for _, o in ipairs(list) do
                if o.y < tr.y - 4 and o.y > top + 30 and math.abs(o.x - tr.x) < 55 * tr.s then behind = true end
            end
        end
        tr.see = clamp((tr.see or 1) + (behind and -dt or dt) * 4, 0.45, 1)
    end
    for _, pen in ipairs(active) do
        pen.nope = math.max(0, (pen.nope or 0) - dt)
        -- the sign is see-through while a kid is behind it
        local x, y, w, h = signRect(pen)
        local behind = false
        for _, k in ipairs(world.kids) do
            if k.x > x - 20 and k.x < x + w + 20 and k.y > y and k.y < y + h + 110 then behind = true end
        end
        pen.see = clamp((pen.see or 1) + (behind and -dt or dt) * 4, 0.35, 1)
    end
end

-- A task is done (clean: right the first time). The difficulty adapts: a
-- step up after a few clean ones in a row (with a little sparkle on the
-- ladder), a step down after two not clean; it takes effect from the next
-- task, and is saved for the kids.
function world.answer(clean)
    local up = PENS_UP
    if world.rules then up = world.rules.UP or 3 end
    if world.challenge then up = math.max(1, up - 1) end        -- the challenge climbs faster
    local step, change = progress.answer(world.ladder, clean, world.steps, up)
    -- the challenge's streak: right the first time in a row; every 5, a burst
    world.streak = clean and world.streak + 1 or 0
    if world.challenge and clean and world.streak % 5 == 0 then
        world.streakFlash = 1.6
        sfx.play("win")
        stars(1180, 90, 18)
    end
    journal.log("etape", { propre = clean, etape = step, change = change })
    if change ~= 0 then
        world.level = step
        progress.save(world.mode, world.kidIds, step)
        if change > 0 then
            world.stepFlash = 1.2
            sfx.play("sparkle")
        end
    end
end

function world.update(dt)
    world.time = world.time + dt
    world.stepFlash = math.max(0, (world.stepFlash or 0) - dt)
    world.streakFlash = math.max(0, (world.streakFlash or 0) - dt)
    updateEffects(dt)

    if world.phase == "play" then
        -- right for a moment (not just passing through the right number)
        world.rightFor = allRight() and world.rightFor + dt or 0
        if world.rightFor > 0.8 then
            world.phase = "party"
            world.partyTime = 0
            world.roundsWon = world.roundsWon + 1
            if not world.rules then world.answer(world.clean ~= false) end   -- (the other games say it per task)
            world.duck = 3
            sfx.play("win")
            for _, k in ipairs(world.kids) do k.cheer = 3 end
            for _, pen in ipairs(active) do stars(pen.x + 120, pen.y + 140, 10) end
            if world.rules then world.rules.party() end
            journal.log("bravo", { niveau = world.level, manches = world.roundsWon })
        end
    elseif world.phase == "party" then
        world.partyTime = world.partyTime + dt
        for _, k in ipairs(world.kids) do
            if k.cheer <= 0.2 and not world.rules then k.cheer = 1.5 end   -- keep jumping for joy
        end
        local busy = world.rules and world.rules.busy and world.rules.busy()
        if world.partyTime > 3.5 and not busy then
            world.fade = math.min(1, world.fade + dt * 2.5)
            if world.fade >= 1 then
                for _, k in ipairs(world.kids) do k.cheer = 0 end
                newRound()
            end
        end
    end
    if world.phase == "play" and world.fade > 0 then world.fade = math.max(0, world.fade - dt * 2.5) end
    if world.rules then world.rules.update(dt) end

    for _, k in ipairs(world.kids) do updateKid(k, dt) end
    separateKids()
    for _, a in ipairs(world.animals) do updateAnimal(a, dt) end
    separateAnimals()
    if world.phase == "play" then journal.tick(world.kids) end
end

-- Drawing ------------------------------------------------------------------------

local function outlined(text, font, x, y, w, color)
    g.setFont(font)
    g.setColor(0.15, 0.08, 0.05, 0.85 * (color and color[4] or 1))
    for i = 0, 11 do   -- a round outline, smooth at any resolution
        local a = i / 12 * math.pi * 2
        g.printf(text, x + math.cos(a) * 2.2, y + math.sin(a) * 2.2, w, "center")
    end
    g.setColor(color or { 1, 1, 1 })
    g.printf(text, x, y, w, "center")
end

local function ground()
    local grass = art.grass(world.W, world.H, world.scene and world.rules.GROUND_TILE or GRASS_TILE,
        world.scene and world.rules.GROUND)
    if not grass then
        g.setColor(0.5, 0.75, 0.35)
        g.rectangle("fill", 0, 0, world.W, world.H)
    end
    local p = world.pond
    if p then
        local im = art.image("mare")
        local sc = POND_W / im:getWidth()
        g.setColor(1, 1, 1)
        g.draw(im, p.x, p.y, 0, sc, sc, im:getWidth() / 2, im:getHeight() * 0.49)
    end
    for _, p in ipairs(world.props) do art.prop(p.name, p.x, p.y, p.f, p.s) end
end

-- The pen's sign: the number it wants and its animal. It turns green with a
-- star when the pen is right, and the number turns red when there are too many.
local function drawSign(i)
    local pen = PENS[i]
    local n = penCount(i)
    local x, y, w, h = signRect(pen)
    local a = pen.see or 1
    local shake = math.sin(pen.nope * 40) * 6 * pen.nope / 0.6
    g.push()
    g.translate(shake, 0)
    local right = n == pen.target
    art.panel(x, y, w, h, a)
    art.disk(pen.target, x + 34, y + h / 2, 25, right and "ok" or n > pen.target and "over" or "todo", fonts.disk, a)
    art.tint = { 1, 1, 1, a }
    art.animal(pen.kind, x + 88, y + h - 8, 1, 1.05, false)
    art.tint = nil
    if right then
        g.setColor(1, 1, 1, a)
        art.star(x + w - 4, y + 4, 14, true)
    end
    g.pop()
end

-- With turns: is it kid k's turn? And the next kid's turn.
function world.myTurn(k)
    return not world.turn or world.turn == k.player
end

function world.nextTurn()
    if not world.turn then return end
    for i, k in ipairs(world.kids) do
        if k.player == world.turn then
            world.turn = world.kids[i % #world.kids + 1].player
            return
        end
    end
end

-- (a game may draw the kids bigger: world.rules.KID_SCALE, e.g. on the farm,
-- so they are in proportion with the market stall)
local function drawKid(k)
    local s = world.rules and world.rules.KID_SCALE or 1.25
    art.kid(k.look, k.x, k.y, k.facing, s, k.walk, k.anim, k.animT)
    if world.turn == k.player then          -- its turn: a big star over its head
        local hop = math.abs(math.sin(world.time * 5)) * 8
        art.star(k.x, k.y - 96 * s * k.look.size - 34 - hop, 16, true)
    end
    if #world.kids > 1 then
        outlined(T("player") .. k.player, fonts.small, k.x - 30, k.y - 96 * s * k.look.size, 60,
            k.player == 1 and { 1, 0.75, 0.3 } or { 0.5, 0.8, 1 })
    end
end

local function drawAnimal(a)
    local shake = math.sin((a.nope or 0) * 40) * 5 * (a.nope or 0) / 0.6
    local hop = (a.hop or 0) > 0 and math.sin(a.hop / 0.4 * math.pi) * 16 or 0   -- a little jump (a.hop seconds)
    art.animal(a.kind, a.x + shake, a.y - hop, a.facing, 1.2, true, a.anim, a.animT)
    if world.rules then world.rules.drawOnAnimal(a, shake) end
end

-- At the top: one star per round won.
-- The ladder of steps, at the top right: a dot per step, the ones reached
-- filled; it sparkles when the kids go up a step.
local function drawLadder()
    local n, cur = world.steps or 1, world.level or 1
    local gap = 16
    local w = (n - 1) * gap + 30
    local x0 = 1280 - 12 - w
    art.panel(x0, 10, w, 26)
    for i = 1, n do
        local x = x0 + 15 + (i - 1) * gap
        g.setColor(art.OUTLINE)
        g.circle("fill", x, 23, 6.5)
        if i <= cur then g.setColor(art.COLORS.todo) else g.setColor(0.55, 0.42, 0.3) end
        g.circle("fill", x, 23, 5)
    end
    if (world.stepFlash or 0) > 0 then
        local x = x0 + 15 + (cur - 1) * gap
        local s = math.sin(world.stepFlash / 1.2 * math.pi)
        art.star(x, 23 - s * 16, 9 + s * 8, true)
    end
end

-- The challenge's streak, under the ladder: a little flame and the number of
-- right answers in a row (it grows bigger every 5).
local function drawStreak()
    if not world.challenge then return end
    local n = world.streak or 0
    local pop = 1 + 0.6 * math.sin(math.min(1, (world.streakFlash or 0) / 1.6) * math.pi)
    local x, y = 1210, 70
    art.panel(1150, 44, 118, 52)
    g.push()
    g.translate(x - 30, y)
    g.scale(pop)
    local function drop(r, color)                               -- a round flame, its tip up
        g.setColor(color)
        g.circle("fill", 0, 5, r)
        g.polygon("fill", -r * 0.97, 3, 0, 5 - r * 2.3, r * 0.97, 3)
    end
    drop(13, art.OUTLINE)                                       -- the flame
    drop(10, n > 0 and { 1, 0.5, 0.15 } or { 0.6, 0.5, 0.4 })
    g.push()
    g.translate(0, 4)
    drop(5, n > 0 and { 1, 0.88, 0.35 } or { 0.75, 0.68, 0.6 })
    g.pop()
    g.pop()
    g.setFont(fonts.big)
    g.setColor(art.OUTLINE)
    g.printf(tostring(n), x - 14, y - fonts.big:getHeight() / 2, 60, "center")
end

local function hud()
    drawLadder()
    drawStreak()
    local n = world.roundsWon
    if n == 0 then return end
    local shown = math.min(n, 12)
    local x0 = START_X - (shown - 1) * 17
    if world.rules then x0 = 40 end          -- (the games' own counters are in the middle)
    art.panel(x0 - 24, 8, (shown - 1) * 34 + 48, 38)
    for s = 1, shown do art.star(x0 + (s - 1) * 34, 27, 14, true) end
end

function world.draw()
    ground()
    for _, r in ipairs(active) do art.pen(r) end
    if world.rules then world.rules.drawGround() end

    -- everything with feet, back to front
    local things = {}
    for _, tr in ipairs(world.trees) do table.insert(things, { y = tr.y, tree = tr }) end
    for _, a in ipairs(world.animals) do
        if not (world.rules and world.rules.hidden(a)) then table.insert(things, { y = a.y, animal = a }) end
    end
    for _, k in ipairs(world.kids) do
        if not k.driving then table.insert(things, { y = k.y, kid = k }) end
    end
    if world.rules then world.rules.things(things) end
    table.sort(things, function(a, b) return a.y < b.y end)
    for _, o in ipairs(things) do
        if o.draw then
            o.draw()
        elseif o.tree then
            if (o.tree.see or 1) < 1 then art.tint = { 1, 1, 1, o.tree.see } end
            art.tree(o.tree.x, o.tree.y, o.tree.s, false, o.tree.kind, o.tree.f)
            art.tint = nil
        elseif o.animal then
            drawAnimal(o.animal)
        else
            drawKid(o.kid)
        end
    end

    for i in ipairs(active) do drawSign(i) end
    for _, p in ipairs(world.particles) do
        local a = p.life / p.max
        if p.star then
            art.star(p.x, p.y, p.r * a, true)
        else
            art.heart(p.x, p.y, p.r, { 1, 0.35, 0.45, a })
        end
    end
    for _, p in ipairs(world.popups) do
        local u = p.age / p.life
        local c = p.color or { 1, 1, 1 }
        outlined(p.text, fonts.big, p.x - 60, p.y - u * 40, 120, { c[1], c[2], c[3], 1 - u * u })
    end
    if world.rules then world.rules.drawHud() end
    hud()
    if world.phase == "party" then
        local s = 1 + 0.15 * math.sin(world.partyTime * 6)
        g.push()
        g.translate(world.startX, world.startY - 60)
        g.scale(s * math.min(1, world.partyTime * 3))
        art.star(0, 0, 90, true)
        g.pop()
    end
    if world.fade > 0 then
        g.setColor(0.1, 0.22, 0.1, world.fade)
        g.rectangle("fill", 0, 0, world.W, world.H)
    end
end

-- The other games use the same meadow, animals and helpers.
for _, R in pairs(MODES) do
    R.setup(world, { newAnimal = newAnimal, biomeSpot = biomeSpot, moveToward = moveToward,
        popup = popup, hearts = hearts, stars = stars, outlined = outlined, fonts = fonts,
        journal = journal, KINDS = KINDS, shuffle = shuffle, dist = dist, rand = rand,
        answer = function(clean) world.answer(clean) end })
end

return world
