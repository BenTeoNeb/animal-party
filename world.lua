-- world.lua: the playground. For now there are no rules: the kids walk in the
-- forest among the animals (taken from Lava Rescue!), and the bottom button
-- says hello to the nearest animal. The new game's rules go here.

local input = require("input")
local sfx = require("sfx")
local art = require("art")
-- the game log (journal.lua) is not shipped (see build.sh): without it, nothing is logged
local hasJournal, journal = pcall(require, "journal")
if not hasJournal then
    journal = setmetatable({}, { __index = function() return function() end end })
end
local T = require("lang").t

local world = {}
local g = love.graphics

world.W, world.H = 1280, 720

local KID_SPEED = 230         -- each kid changes it with their own speed (see art.KIDS)
local ANIMAL_COUNTS = { poule = 4, ecureuil = 3, marcassin = 3, herisson = 3, renard = 2 }
local GRASS_TILE = 380        -- width of one tile of the grass drawing, in pixels
world.GRASS_TILE = GRASS_TILE
local TOP = 20
local BODY = 10               -- half-width of a kid or an animal's feet

local FLOWER_COLORS = { { 1, 0.5, 0.6 }, { 0.7, 0.5, 1 }, { 1, 1, 1 }, { 1, 0.75, 0.3 } }

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

local function setAnim(o, name)
    if o.anim ~= name then o.anim, o.animT = name, 0 end
end

-- Nobody walks through a tree trunk.
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

local function hearts(x, y, n)
    for _ = 1, n do
        table.insert(world.particles, { heart = true, x = x + rand(-15, 15), y = y,
            vx = rand(-20, 20), vy = rand(-70, -40), r = rand(0.6, 1), life = 1.2, max = 1.2 })
    end
end

-- Setup --------------------------------------------------------------------------

-- (Re)make the fonts, sharp for the current screen size.
function world.makeFonts()
    fonts.big = art.font(40)
    fonts.small = art.font(20)
end

function world.load()
    world.makeFonts()
end

function world.start(chosen)
    world.time = 0
    world.phase = "play"
    world.done = false
    world.particles = {}

    world.kids = {}
    for i, c in ipairs(chosen) do
        table.insert(world.kids, {
            player = c.player, look = art.KIDS[c.kid],
            x = world.W / 2 - 40 + (i - 1) * 80, y = world.H / 2 + 40, facing = 1,
            walk = 0, anim = "repos", animT = 0, cheer = 0,
        })
    end

    world.trees = {}
    -- a few trees, spread out, each one a different species as long as there are enough
    local kinds = {}
    for kind in pairs(art.TREES) do table.insert(kinds, kind) end
    table.sort(kinds)
    for i = #kinds, 2, -1 do
        local j = love.math.random(i)
        kinds[i], kinds[j] = kinds[j], kinds[i]
    end
    for _ = 1, 200 do
        local tree = { x = rand(60, world.W - 60), y = rand(TOP + 120, world.H - 10), s = rand(0.8, 1),
            kind = kinds[#world.trees % #kinds + 1], f = love.math.random() < 0.5 and -1 or 1 }
        local ok = math.abs(tree.x - world.W / 2) > 140 or math.abs(tree.y - world.H / 2) > 120
        for _, other in ipairs(world.trees) do
            if dist(tree, other) < 190 then ok = false end
        end
        if ok then table.insert(world.trees, tree) end
        if #world.trees >= 12 then break end
    end

    world.animals = {}
    for kind, n in pairs(ANIMAL_COUNTS) do
        for _ = 1, n do
            local a = { kind = kind, facing = 1, walk = 0, wait = rand(0, 2), anim = "repos", animT = 0 }
            repeat
                a.x, a.y = rand(60, world.W - 60), rand(TOP + 60, world.H - 30)
                local ok = true
                for _, b in ipairs(world.animals) do
                    if dist(a, b) < 55 then ok = false end
                end
            until ok
            a.tx, a.ty = a.x, a.y
            table.insert(world.animals, a)
        end
    end

    -- the drawn forest things, if their images exist
    world.props, world.flowers = {}, {}
    if art.image("fleurs") then
        for _ = 1, art.image("herbe") and 50 or 75 do
            table.insert(world.props, { name = art.randomProp(), x = rand(20, world.W - 20),
                y = rand(TOP + 15, world.H - 5), f = love.math.random() < 0.5 and -1 or 1, s = rand(0.85, 1.15) })
        end
        table.sort(world.props, function(a, b) return a.y < b.y end)
    else
        for _ = 1, 110 do
            table.insert(world.flowers, { x = rand(0, world.W), y = rand(TOP, world.H),
                color = FLOWER_COLORS[love.math.random(#FLOWER_COLORS)] })
        end
    end

    local kidNames = {}
    for _, k in ipairs(world.kids) do kidNames[#kidNames + 1] = k.look.id end
    journal.start({ joueurs = #chosen, enfants = kidNames, langue = require("lang").current })
end

function world.logEnd(how)
    journal.finish(how)
end

-- Actions ------------------------------------------------------------------------

local function kidOf(p)
    for _, k in ipairs(world.kids) do
        if k.player == p then return k end
    end
end

-- The bottom button: the nearest animal in reach jumps and says hello.
function world.action(p, action)
    local k = kidOf(p)
    if not k then return end
    if action == "grab" then
        local best, bestD = nil, k.look.reach
        for _, a in ipairs(world.animals) do
            local d = dist(k, a)
            if d < bestD then best, bestD = a, d end
        end
        if best then
            best.hop = 0.5
            hearts(best.x, best.y - 30, 3)
            sfx.play("grab_" .. best.kind)
            journal.log("bonjour", { joueur = p, animal = best.kind })
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

local function updateKid(k, dt)
    k.animT = k.animT + dt
    k.cheer = math.max(0, k.cheer - dt)
    local dx, dy = input.move(k.player)
    local len = math.sqrt(dx * dx + dy * dy)
    if len > 1 then dx, dy = dx / len, dy / len end
    local speed = KID_SPEED * k.look.speed
    k.x = clamp(k.x + dx * speed * dt, 20, world.W - 20)
    k.y = clamp(k.y + dy * speed * dt, TOP + 20, world.H - 8)
    blockByTrees(k)
    if len > 0.1 then
        k.walk = k.walk + dt * 12
        if math.abs(dx) > 0.1 then k.facing = dx > 0 and 1 or -1 end
    else
        k.walk = 0
    end
    if k.cheer > 0 then setAnim(k, "saut")
    elseif len > 0.1 then setAnim(k, "course")
    else setAnim(k, "repos") end
end

local function updateAnimal(a, dt)
    a.moving = false
    a.animT = a.animT + dt
    a.hop = math.max(0, (a.hop or 0) - dt)
    a.wait = a.wait - dt
    if a.wait <= 0 then
        a.tx = clamp(a.x + rand(-120, 120), 40, world.W - 40)
        a.ty = clamp(a.y + rand(-120, 120), TOP + 30, world.H - 20)
        a.wait = rand(2, 4)
    end
    if not moveToward(a, a.tx, a.ty, 40, dt) then a.walk = 0 end
    blockByTrees(a)
    if a.moving then setAnim(a, "marche") else setAnim(a, "repos") end
end

function world.update(dt)
    world.time = world.time + dt
    for i = #world.particles, 1, -1 do
        local p = world.particles[i]
        p.life = p.life - dt
        p.x, p.y = p.x + p.vx * dt, p.y + p.vy * dt
        if p.life <= 0 then table.remove(world.particles, i) end
    end
    for _, k in ipairs(world.kids) do updateKid(k, dt) end
    separateKids()
    for _, a in ipairs(world.animals) do updateAnimal(a, dt) end
    journal.tick(world.kids)
end

-- Drawing ------------------------------------------------------------------------

local function outlined(text, font, x, y, w, color)
    g.setFont(font)
    g.setColor(0.15, 0.08, 0.05, 0.85)
    for i = 0, 11 do   -- a round outline, smooth at any resolution
        local a = i / 12 * math.pi * 2
        g.printf(text, x + math.cos(a) * 2.2, y + math.sin(a) * 2.2, w, "center")
    end
    g.setColor(color or { 1, 1, 1 })
    g.printf(text, x, y, w, "center")
end

local function ground()
    if not art.grass(world.W, world.H, GRASS_TILE) then
        g.setColor(0.5, 0.75, 0.35)
        g.rectangle("fill", 0, 0, world.W, world.H)
    end
    for _, p in ipairs(world.props) do art.prop(p.name, p.x, p.y, p.f, p.s) end
    for _, f in ipairs(world.flowers) do art.flower(f.x, f.y, f.color) end
end

local function drawKid(k)
    art.kid(k.look, k.x, k.y, k.facing, 1.25, k.walk, k.anim, k.animT)
    if #world.kids > 1 then
        outlined(T("player") .. k.player, fonts.small, k.x - 30, k.y - 120 * k.look.size, 60,
            k.player == 1 and { 1, 0.75, 0.3 } or { 0.5, 0.8, 1 })
    end
end

local function drawAnimal(a)
    local hop = math.sin(math.min(1, (a.hop or 0) / 0.5) * math.pi) * 18
    art.animal(a.kind, a.x, a.y - hop, a.facing, 1.2, true, a.anim, a.animT)
end

function world.draw()
    ground()
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
    for _, p in ipairs(world.particles) do
        art.heart(p.x, p.y, p.r, { 1, 0.35, 0.45, p.life / p.max })
    end
end

return world
