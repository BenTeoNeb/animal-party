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

local world = {}
local g = love.graphics

world.W, world.H = 1280, 720

-- Tweak these to make the game easier or harder.
local KID_SPEED = 230         -- running, arms free
local KID_WALK_SPEED = 185    -- walking, when animals are following you
local ROUNDS_PER_LEVEL = 3    -- rounds won before the next level
local SPARE = { 2, 1, 1 }     -- (per level) animals more than needed in the meadow, of each pen's kind
local DECOYS = 2              -- animals of each kind that no pen wants
local COUNT_GAP = 0.45        -- seconds between two animals going in (time to count out loud)

local KINDS = { "poule", "ecureuil", "marcassin", "herisson", "renard" }

local HILL_X = 920            -- the pens' side starts here
local GRASS_TILE = 380        -- width of one tile of the grass drawing, in pixels
world.GRASS_TILE = GRASS_TILE
local TOP = 20

local PENS = {
    { x = 960, y = 4, w = 310, h = 232, roof = { 0.9, 0.25, 0.2 }, name = "rouge" },
    { x = 960, y = 240, w = 310, h = 232, roof = { 0.25, 0.5, 0.95 }, name = "bleue", top = false },
    { x = 960, y = 476, w = 310, h = 232, roof = { 1, 0.78, 0.15 }, name = "jaune", top = false },
}
world.pens = PENS        -- each one: kind, target (set by newRound)

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
    for i, r in ipairs(PENS) do
        if o.x > r.x + 8 and o.x < r.x + r.w - 8 and o.y > r.y + 8 and o.y < r.y + r.h - 4 then
            return i
        end
    end
end

-- Where the animals of a pen stand: below the sign, left of the hut.
local function spotIn(r)
    return rand(r.x + 40, r.x + r.w - 100), rand(r.y + 165, r.y + r.h - 20)
end

-- The pen's sign (top left of the pen): the number, then a ten-frame of
-- boxes, 5 per row. slotAt(pen, s) is the middle of box s.
local SIGN_DIGIT, SLOT_W, SLOT_H = 62, 34, 46
local function signRect(pen)
    return pen.x + 10, pen.y + 14, SIGN_DIGIT + 5 * SLOT_W + 8, 2 * SLOT_H + 8
end
local function slotAt(pen, s)
    local x, y = signRect(pen)
    local col, row = (s - 1) % 5, math.floor((s - 1) / 5)
    return x + SIGN_DIGIT + col * SLOT_W + SLOT_W / 2, y + 4 + row * SLOT_H + SLOT_H / 2
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

-- The fences of the pens are solid for the kids: you can only get in through
-- the entrance on the meadow side. (px, py) is where the kid was before moving,
-- to know which side of a fence they come from.
local WALL = 7             -- how thick a fence is, for the feet
local function blockByFences(o, px, py)
    for _, r in ipairs(PENS) do
        local top, bottom = r.y + 6, r.y + r.h - 2
        local gapTop, gapBottom = r.y + r.h * art.PEN_GAP[1], r.y + r.h * art.PEN_GAP[2]
        for _, y in ipairs({ top, bottom }) do
            if o.x > r.x - BODY and o.x < r.x + r.w + BODY and math.abs(o.y - y) < WALL then
                local side = py < y and -1 or 1
                o.y = y + side * WALL
            end
        end
        local sides = { { r.x + r.w, top, bottom }, { r.x, top, gapTop }, { r.x, gapBottom, bottom } }
        for _, v in ipairs(sides) do
            local x, y1, y2 = v[1], v[2], v[3]
            if o.y > y1 - WALL and o.y < y2 + WALL and math.abs(o.x - x) < BODY then
                local side = px < x and -1 or 1
                o.x = x + side * BODY
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

-- The pen's number just changed to n: say it (shown over the box that just
-- filled, or emptied), and cheer if it's right.
local function counted(i, n, out)
    local pen = PENS[i]
    local right = n == pen.target
    local x, y = slotAt(pen, math.max(1, out and n + 1 or n))
    popup(tostring(n), x, y - 50, right and { 0.6, 1, 0.5 } or n > pen.target and { 1, 0.55, 0.45 } or nil)
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
end

function world.load()
    world.makeFonts()
end

-- What each pen asks for this round: { kind, target, start }.
local function roundFor(level)
    local kinds = shuffle({ unpack(KINDS) })
    local asks = {}
    for i = 1, #PENS do
        local ask = { kind = kinds[i] }
        local takeAway = level == 3 and (i == 1 or love.math.random() < 0.4)
        if level == 1 then
            ask.start, ask.target = 0, love.math.random(1, 5)
        elseif takeAway then
            ask.target = love.math.random(1, 6)
            ask.start = ask.target + love.math.random(1, 3)
        else
            local most = level == 3 and 6 or 8
            ask.start = love.math.random(1, 4)
            ask.target = love.math.random(ask.start + 1, math.min(most, ask.start + 4))
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

-- A free spot in the meadow, not on another animal, a tree or a kid.
local function meadowSpot(a)
    for _ = 1, 100 do
        a.x, a.y = rand(60, HILL_X - 90), rand(TOP + 70, world.H - 30)
        local ok = true
        for _, b in ipairs(world.animals) do
            if b ~= a and dist(a, b) < 55 then ok = false end
        end
        for _, k in ipairs(world.kids) do
            if dist(a, k) < 90 then ok = false end
        end
        for _, tr in ipairs(world.trees) do
            if dist(a, tr) < 50 then ok = false end
        end
        if ok then break end
    end
    a.tx, a.ty = a.x, a.y
end

local function newRound()
    world.phase = "play"
    world.rightFor = 0
    world.animals = {}
    world.popups = {}
    for _, k in ipairs(world.kids) do k.followers = {} end

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
            a.x, a.y = spotIn(pen)
            a.tx, a.ty = a.x, a.y
            table.insert(world.animals, a)
        end
        for _ = 1, math.max(0, ask.target - ask.start) + SPARE[world.level] do
            local a = newAnimal(ask.kind)
            meadowSpot(a)
            table.insert(world.animals, a)
        end
    end
    for _, kind in ipairs(KINDS) do
        if not wanted[kind] then
            for _ = 1, DECOYS do
                local a = newAnimal(kind)
                meadowSpot(a)
                table.insert(world.animals, a)
            end
        end
    end

    local log = {}
    for i, pen in ipairs(PENS) do log[i] = { pen.kind, asks[i].start, pen.target } end
    journal.log("manche", { niveau = world.level, enclos = log })
end

function world.start(chosen, level)
    world.time = 0
    world.done = false
    world.level = level or 1
    world.roundsWon, world.levelWins = 0, 0
    world.particles, world.popups = {}, {}
    world.fade = 0

    world.kids = {}
    for i, c in ipairs(chosen) do
        table.insert(world.kids, {
            player = c.player, look = art.KIDS[c.kid],
            x = HILL_X / 2 - 40 + (i - 1) * 80, y = world.H / 2 + 40, facing = 1,
            walk = 0, anim = "repos", animT = 0, cheer = 0, followers = {},
        })
    end

    world.trees = {}
    -- a few trees, spread out so they don't hide the kids too much,
    -- each one a different species as long as there are enough
    local kinds = {}
    for kind in pairs(art.TREES) do table.insert(kinds, kind) end
    table.sort(kinds)
    shuffle(kinds)
    for _ = 1, 200 do
        local tree = { x = rand(50, HILL_X - 110), y = rand(TOP + 120, world.H - 10), s = rand(0.8, 1),
            kind = kinds[#world.trees % #kinds + 1], f = love.math.random() < 0.5 and -1 or 1 }
        local ok = math.abs(tree.x - HILL_X / 2) > 140 or math.abs(tree.y - world.H / 2) > 120
        for _, other in ipairs(world.trees) do
            if dist(tree, other) < 200 then ok = false end
        end
        if ok then table.insert(world.trees, tree) end
        if #world.trees >= 8 then break end
    end

    -- the drawn forest things, if their images exist
    world.props = {}
    if art.image("fleurs") then
        for _ = 1, art.image("herbe") and 40 or 60 do
            table.insert(world.props, { name = art.randomProp(), x = rand(20, HILL_X - 30),
                y = rand(TOP + 15, world.H - 5), f = love.math.random() < 0.5 and -1 or 1, s = rand(0.85, 1.15) })
        end
        table.sort(world.props, function(a, b) return a.y < b.y end)
    end

    local kidNames = {}
    for _, k in ipairs(world.kids) do kidNames[#kidNames + 1] = k.look.id end
    journal.start({ joueurs = #chosen, enfants = kidNames, niveau = world.level, langue = lang.current })
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
    a.tx, a.ty = spotIn(PENS[i])
    a.wait = rand(1, 2)
end

-- Not the animal this pen wants: it shakes its head and stays in line.
local function refuse(a, i)
    a.nope = 0.6
    PENS[i].nope = 0.6
end

function world.action(p, action)
    if world.phase ~= "play" then return end
    local k = kidOf(p)
    if not k then return end
    if action == "grab" then
        tryGrab(k, true)
    elseif action == "drop" and #k.followers > 0 then
        -- let go of one animal only (the last in line); in its own pen, it goes in
        local a = table.remove(k.followers)
        journal.log("lache", { joueur = k.player, animal = a.kind })
        local here = penAt(k)
        if here and PENS[here].kind == a.kind then
            enter(a, here, 0.2)
        else
            a.state, a.tx, a.ty, a.wait = "free", a.x, a.y, rand(1, 2)
            sfx.play("drop")
        end
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
    local dx, dy = input.move(k.player)
    if world.phase ~= "play" then dx, dy = 0, 0 end
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

local function updateAnimal(a, dt)
    a.moving = false
    a.animT = a.animT + dt
    a.nope = math.max(0, (a.nope or 0) - dt)
    if a.state == "free" then
        wander(a, dt, 40, HILL_X - 60, TOP + 40, world.H - 20, 40)
        blockByTrees(a)
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
            if a.countIn <= 0 then
                a.counted = true
                counted(a.pen, penCount(a.pen))
            end
        else
            local r = PENS[a.pen]
            wander(a, dt, r.x + 40, r.x + r.w - 100, r.y + 165, r.y + r.h - 20, 30)
        end
    end
    if a.moving and a.moving > 150 then setAnim(a, "course")
    elseif a.moving then setAnim(a, "marche")
    else setAnim(a, "repos") end
end

-- All three pens right (and nobody still walking in)?
local function allRight()
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
    for _, pen in ipairs(PENS) do
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

function world.update(dt)
    world.time = world.time + dt
    updateEffects(dt)

    if world.phase == "play" then
        -- right for a moment (not just passing through the right number)
        world.rightFor = allRight() and world.rightFor + dt or 0
        if world.rightFor > 0.8 then
            world.phase = "party"
            world.partyTime = 0
            world.roundsWon = world.roundsWon + 1
            world.levelWins = world.levelWins + 1
            world.duck = 3
            sfx.play("win")
            for _, k in ipairs(world.kids) do k.cheer = 3 end
            for _, pen in ipairs(PENS) do stars(pen.x + 120, pen.y + 140, 10) end
            journal.log("bravo", { niveau = world.level, manches = world.roundsWon })
        end
    elseif world.phase == "party" then
        world.partyTime = world.partyTime + dt
        for _, k in ipairs(world.kids) do
            if k.cheer <= 0.2 then k.cheer = 1.5 end         -- keep jumping for joy
        end
        if world.partyTime > 3.5 then
            world.fade = math.min(1, world.fade + dt * 2.5)
            if world.fade >= 1 then
                if world.levelWins >= ROUNDS_PER_LEVEL and world.level < 3 then
                    world.level, world.levelWins = world.level + 1, 0
                end
                for _, k in ipairs(world.kids) do k.cheer = 0 end
                newRound()
            end
        end
    end
    if world.phase == "play" and world.fade > 0 then world.fade = math.max(0, world.fade - dt * 2.5) end

    for _, k in ipairs(world.kids) do updateKid(k, dt) end
    separateKids()
    for _, a in ipairs(world.animals) do updateAnimal(a, dt) end
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
    local grass = art.grass(world.W, world.H, GRASS_TILE)
    if not grass then
        g.setColor(0.5, 0.75, 0.35)
        g.rectangle("fill", 0, 0, world.W, world.H)
    end
    -- the pens' side: lighter
    if grass then g.setColor(1, 1, 0.75, 0.3) else g.setColor(0.62, 0.82, 0.45) end
    g.rectangle("fill", HILL_X, 0, world.W - HILL_X, world.H)
    for _, p in ipairs(world.props) do art.prop(p.name, p.x, p.y, p.f, p.s) end
end

-- The pen's sign: the number it wants, and a ten-frame of its animal. A box
-- fills in for each animal inside (an empty box shows the animal's shadow);
-- the animals too many are shown in red boxes.
local function drawSign(i)
    local pen = PENS[i]
    local n = penCount(i)
    local x, y, w, h = signRect(pen)
    local a = pen.see or 1
    local shake = math.sin(pen.nope * 40) * 6 * pen.nope / 0.6
    g.push()
    g.translate(shake, 0)
    local right = n == pen.target
    g.setColor(0.23, 0.14, 0.09, a)
    g.rectangle("fill", x - 4, y - 4, w + 8, h + 8, 14)
    if right then g.setColor(0.72, 0.9, 0.5, a) else g.setColor(0.93, 0.78, 0.55, a) end
    g.rectangle("fill", x, y, w, h, 11)
    outlined(tostring(pen.target), fonts.sign, x, y + h / 2 - 38, SIGN_DIGIT,
        right and { 0.75, 1, 0.6, a } or { 1, 0.9, 0.4, a })
    for s = 1, math.max(pen.target, n) do
        local cx, cy = slotAt(pen, s)
        local bx, by = cx - SLOT_W / 2 + 2, cy - SLOT_H / 2 + 2
        local extra = s > pen.target
        if extra then g.setColor(1, 0.72, 0.66, a) else g.setColor(1, 0.97, 0.88, a) end
        g.rectangle("fill", bx, by, SLOT_W - 4, SLOT_H - 4, 7)
        if extra then g.setColor(0.85, 0.25, 0.2, a) else g.setColor(0.6, 0.42, 0.25, a) end
        g.setLineWidth(2)
        g.rectangle("line", bx, by, SLOT_W - 4, SLOT_H - 4, 7)
        if s > n then
            art.tint = { 0.25, 0.15, 0.1, 0.35 * a }      -- empty: the animal's shadow
        elseif extra then
            art.tint = { 1, 0.5, 0.45, a }                -- one too many
        else
            art.tint = { 1, 1, 1, a }
        end
        art.animal(pen.kind, cx, by + SLOT_H - 9, 1, 0.82, false)
        art.tint = nil
    end
    if right then
        g.setColor(1, 1, 1, a)
        art.star(x + w - 6, y + 6, 15, true)
    end
    g.pop()
end

local function drawKid(k)
    art.kid(k.look, k.x, k.y, k.facing, 1.25, k.walk, k.anim, k.animT)
    if #world.kids > 1 then
        outlined(T("player") .. k.player, fonts.small, k.x - 30, k.y - 120 * k.look.size, 60,
            k.player == 1 and { 1, 0.75, 0.3 } or { 0.5, 0.8, 1 })
    end
end

local function drawAnimal(a)
    local shake = math.sin((a.nope or 0) * 40) * 5 * (a.nope or 0) / 0.6
    art.animal(a.kind, a.x + shake, a.y, a.facing, 1.2, true, a.anim, a.animT)
end

-- At the top: one star per round won.
local function hud()
    local n = world.roundsWon
    if n == 0 then return end
    local shown = math.min(n, 12)
    local x0 = HILL_X / 2 - (shown - 1) * 17
    g.setColor(0.2, 0.12, 0.08, 0.55)
    g.rectangle("fill", x0 - 24, 6, (shown - 1) * 34 + 48, 40, 16)
    for s = 1, shown do art.star(x0 + (s - 1) * 34, 26, 14, true) end
end

function world.draw()
    ground()
    for _, r in ipairs(PENS) do art.pen(r) end

    -- everything with feet, back to front
    local things = {}
    for _, tr in ipairs(world.trees) do table.insert(things, { y = tr.y, tree = tr }) end
    for _, a in ipairs(world.animals) do table.insert(things, { y = a.y, animal = a }) end
    for _, k in ipairs(world.kids) do table.insert(things, { y = k.y, kid = k }) end
    table.sort(things, function(a, b) return a.y < b.y end)
    for _, o in ipairs(things) do
        if o.tree then
            art.tree(o.tree.x, o.tree.y, o.tree.s, false, o.tree.kind, o.tree.f)
        elseif o.animal then
            drawAnimal(o.animal)
        else
            drawKid(o.kid)
        end
    end

    for i in ipairs(PENS) do drawSign(i) end
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
    hud()
    if world.phase == "party" then
        local s = 1 + 0.15 * math.sin(world.partyTime * 6)
        g.push()
        g.translate(HILL_X / 2, world.H / 2 - 40)
        g.scale(s * math.min(1, world.partyTime * 3))
        art.star(0, 0, 90, true)
        g.pop()
    end
    if world.fade > 0 then
        g.setColor(0.1, 0.22, 0.1, world.fade)
        g.rectangle("fill", 0, 0, world.W, world.H)
    end
end

return world
