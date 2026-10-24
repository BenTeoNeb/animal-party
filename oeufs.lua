-- oeufs.lua: the Egg Boxes (les boîtes à œufs): tens and ones, up to 100. The
-- hens have laid eggs all over the meadow: walk on them to pick them up.
-- As soon as a kid carries 10 eggs, they snap into a box ("clac!"). The
-- market cart, at the bottom, asks for a number, say 34: bring it exactly 3
-- boxes and 4 eggs. Right: the cart counts them, "10, 20, 30" then "31, 32,
-- 33, 34", and shows "34 = 30 + 4". Too many or too few: it wobbles; the
-- right button puts one egg down (with no loose egg, it opens a box: one egg
-- down, 9 loose ones carried; breaking a ten).
-- Grouping by ten, then reading a number as tens and ones (the Singapore
-- method's bundles of ten). Levels:
--   1  10 to 19: make the box yourself; the sign shows the number and the
--      boxes and eggs in pictures
--   2  20 to 59: some full boxes lie about, but one must be made; pictures
--   3  20 to 99: the sign shows the number only (the pictures come back after
--      a wrong try)
-- 3 deliveries make a round.
-- world.lua calls the hooks below at the right moments (see MODES there).

local art = require("art")
local sfx = require("sfx")
local lang = require("lang")

local oeufs = {}
local W, ctx
local g = love.graphics

local CART_X, CART_Y = 640, 668          -- the cart's wheels
local PICK = 28                          -- how close to an egg or a box picks it up
local PER_ROUND = 3
local COUNT_GAP = 0.4
local HENS = 6                           -- hens wandering about (they laid the eggs)

oeufs.START_X, oeufs.START_Y = 640, 470
oeufs.ZONES = {
    { x1 = 300, y1 = 130, x2 = 980, y2 = 330 },
    { x1 = 16, y1 = 60, x2 = 420, y2 = 712 },
    { x1 = 860, y1 = 60, x2 = 1264, y2 = 712 },
}

local S = {}      -- this delivery: target, items on the ground, phase...
oeufs.state = S   -- (read by the tests)

function oeufs.setup(world, c)
    W, ctx = world, c
end

-- A free spot on the grass for an egg or a box (not on the cart, a tree, the
-- pond, another item).
local function spot()
    local x, y
    for _ = 1, 200 do
        x, y = ctx.rand(40, 1240), ctx.rand(150, 700)
        local ok = not (x > CART_X - 580 and x < CART_X + 170 and y > 470) and not (y < 210 and math.abs(x - 640) < 260)
        for _, it in ipairs(S.items) do
            if math.abs(it.x - x) < 44 and math.abs(it.y - y) < 32 then ok = false end
        end
        for _, tr in ipairs(W.trees) do
            if math.abs(tr.x - x) < 40 and y < tr.y + 14 and y > tr.y - 30 then ok = false end
        end
        local p = W.pond
        if p and ((x - p.x) / (p.rx + 30)) ^ 2 + ((y - p.y) / (p.ry + 30)) ^ 2 < 1 then ok = false end
        if ok then break end
    end
    return x, y
end

local function newDelivery()
    local level = W.level
    local target
    if level == 1 then target = love.math.random(10, 19)
    elseif level == 2 then target = love.math.random(20, 59)
    else target = love.math.random(20, 99) end
    local tens, ones = math.floor(target / 10), target % 10
    S.target, S.tens, S.ones = target, tens, ones
    S.items, S.phase, S.t, S.nope, S.help, S.counted, S.sum = {}, "play", 0, 0, level < 3, 0, nil
    local boxes, eggs
    if level == 1 then boxes, eggs = 0, target + 5
    elseif level == 2 then boxes, eggs = tens - 1, 10 + ones + 4
    else boxes, eggs = tens + 1, ones + 5 end
    for _ = 1, boxes do
        local x, y = spot()
        table.insert(S.items, { kind = "box", x = x, y = y })
    end
    for _ = 1, eggs do
        local x, y = spot()
        table.insert(S.items, { kind = "egg", x = x, y = y })
    end
    for _, k in ipairs(W.kids) do k.eggs, k.boxes = 0, 0 end
    ctx.journal.log("commande", { niveau = level, nombre = target, boites = boxes, oeufs = eggs })
end

function oeufs.newRound()
    S.good, S.finished = 0, false
    W.animals = {}
    for _ = 1, HENS do
        local a = ctx.newAnimal("poule")
        ctx.biomeSpot(a)
        table.insert(W.animals, a)
    end
    newDelivery()
end

function oeufs.grab() end                     -- (picking up is just walking on them)

-- The right button: put one egg down. With no loose egg, it opens a box
-- first (breaking a ten): one egg down, 9 loose ones carried.
function oeufs.drop(k)
    if S.phase ~= "play" then return end
    if (k.eggs or 0) == 0 then
        if (k.boxes or 0) == 0 then return end
        k.boxes, k.eggs = k.boxes - 1, 10
        sfx.play("clac")
    end
    k.eggs = k.eggs - 1
    table.insert(S.items, { kind = "egg", x = k.x + 30 * k.facing, y = k.y + 4, wait = 1 })
    sfx.play("drop")
end

local function deliver(k)
    local total = k.boxes * 10 + k.eggs
    ctx.journal.log("livre", { joueur = k.player, boites = k.boxes, oeufs = k.eggs, demande = S.target })
    if total == S.target then
        S.phase, S.t, S.counted, S.by = "count", 0.4, 0, k
        S.inBoxes, S.inEggs = k.boxes, k.eggs
        k.boxes, k.eggs = 0, 0
    else
        S.nope, S.help = 0.6, true
        sfx.play("full")
    end
end

-- Every frame, for each kid: pick up what they walk on, and deliver when they
-- reach the cart.
function oeufs.arrive(k)
    k.eggs, k.boxes = k.eggs or 0, k.boxes or 0
    if S.phase ~= "play" then return end
    for i = #S.items, 1, -1 do
        local it = S.items[i]
        if not it.wait and math.abs(it.x - k.x) < PICK and math.abs(it.y - k.y) < PICK * 0.7 then
            table.remove(S.items, i)
            if it.kind == "box" then
                k.boxes = k.boxes + 1
                sfx.play("ready")
            else
                k.eggs = k.eggs + 1
                sfx.play("select")
                if k.eggs == 10 then              -- ten eggs: a box!
                    k.eggs, k.boxes = 0, k.boxes + 1
                    sfx.play("clac")
                    ctx.popup("10", k.x, k.y - 150, { 1, 0.9, 0.4 })
                    ctx.hearts(k.x, k.y - 120, 3)
                end
            end
        end
    end
    local atCart = math.abs(k.x - CART_X) < 120 and k.y > CART_Y - 120
    if atCart and not k.atCart and (k.boxes > 0 or k.eggs > 0) then deliver(k) end
    k.atCart = atCart
end

function oeufs.updateAnimal() end

function oeufs.update(dt)
    S.nope = math.max(0, S.nope - dt)
    for _, it in ipairs(S.items) do
        if it.wait then
            it.wait = it.wait - dt
            if it.wait <= 0 then it.wait = nil end
        end
    end
    if W.phase ~= "play" then return end
    S.t = S.t - dt
    if S.phase == "count" and S.t <= 0 then
        -- the cart counts: the boxes by ten, then the eggs by one
        if S.counted < S.inBoxes + S.inEggs then
            S.counted = S.counted + 1
            local n = math.min(S.counted, S.inBoxes) * 10 + math.max(0, S.counted - S.inBoxes)
            sfx.count(n, lang.current)
            ctx.popup(tostring(n), CART_X + (S.counted <= S.inBoxes and -50 or 50), CART_Y - 170,
                S.counted <= S.inBoxes and { 1, 0.9, 0.4 } or { 0.6, 1, 0.5 })
            S.t = COUNT_GAP
        else
            S.sum = S.target .. " = " .. (S.tens * 10) .. " + " .. S.ones
            if S.ones == 0 then S.sum = S.target .. " = " .. (S.tens * 10) end
            S.good = S.good + 1
            sfx.play("home")
            ctx.hearts(CART_X, CART_Y - 120, 8)
            S.phase, S.t = "done", 2.6
        end
    elseif S.phase == "done" and S.t <= 0 then
        if S.good >= PER_ROUND then S.finished = true else newDelivery() end
    end
end

function oeufs.done() return S.finished end

function oeufs.party()
    ctx.stars(CART_X, CART_Y - 120, 16)
end

function oeufs.hidden() return false end
function oeufs.drawOnAnimal() end

-- Drawing ------------------------------------------------------------------------

local OUTLINE = art.OUTLINE

local function egg(x, y, s)
    s = s or 1
    g.setColor(0, 0, 0, 0.15)
    g.ellipse("fill", x + 2 * s, y + 1, 9 * s, 3.5 * s)
    g.setColor(OUTLINE)
    g.ellipse("fill", x, y - 9 * s, 9 * s, 11.5 * s)
    g.setColor(1, 0.97, 0.9)
    g.ellipse("fill", x, y - 9 * s, 7 * s, 9.5 * s)
    g.setColor(1, 1, 1)
    g.ellipse("fill", x - 2.5 * s, y - 13 * s, 2.2 * s, 3.2 * s)
end

-- A box of 10: a cardboard egg carton, 2 rows of 5 eggs showing.
local function box(x, y, s)
    s = s or 1
    local w, h = 58 * s, 24 * s
    g.setColor(0, 0, 0, 0.15)
    g.ellipse("fill", x + 3 * s, y + 1, w * 0.55, 5 * s)
    g.setColor(OUTLINE)
    g.rectangle("fill", x - w / 2 - 2 * s, y - h - 2 * s, w + 4 * s, h + 3 * s, 5 * s)
    g.setColor(0.78, 0.6, 0.4)
    g.rectangle("fill", x - w / 2, y - h, w, h, 4 * s)
    for r = 0, 1 do
        for c = 0, 4 do
            local ex, ey = x - w / 2 + 7 * s + c * 11 * s, y - h + 6.5 * s + r * 10 * s
            g.setColor(OUTLINE)
            g.circle("fill", ex, ey, 4.6 * s)
            g.setColor(1, 0.97, 0.9)
            g.circle("fill", ex, ey, 3.6 * s)
        end
    end
end
oeufs.drawEgg, oeufs.drawBox = egg, box

-- The eggs and boxes on the grass, and the market cart.
function oeufs.drawGround()
    for _, it in ipairs(S.items or {}) do
        if it.kind == "box" then box(it.x, it.y) else egg(it.x, it.y) end
    end
end

-- The cart (a wagon from the train, with a little awning) and its sign.
function oeufs.things(list)
    table.insert(list, { y = CART_Y, draw = function()
        local shake = math.sin(S.nope * 40) * 6 * S.nope / 0.6
        local x = CART_X + shake
        local im = art.image("train_wagon_jaune")
        if im then
            local sc = 170 / im:getWidth()
            g.setColor(1, 1, 1)
            g.draw(im, x, CART_Y, 0, sc, sc, im:getWidth() / 2, im:getHeight())
        end
        -- what's in it, while it counts
        if S.phase == "count" or S.phase == "done" then
            local n = math.min(S.counted, S.inBoxes)
            for i = 1, n do box(x - 60 + ((i - 1) % 5) * 20, CART_Y - 64 - math.floor((i - 1) / 5) * 8, 0.55) end
            for i = 1, math.max(0, S.counted - S.inBoxes) do egg(x + 22 + ((i - 1) % 5) * 11, CART_Y - 62, 0.7) end
        end
        g.setColor(OUTLINE)                                   -- the awning's poles
        g.setLineWidth(5)
        g.line(x - 78, CART_Y - 60, x - 78, CART_Y - 120)
        g.line(x + 78, CART_Y - 60, x + 78, CART_Y - 120)
        for i = 0, 5 do                                       -- the striped awning
            g.setColor(OUTLINE)
            g.rectangle("fill", x - 92 + i * 30.7, CART_Y - 136, 31.7, 22, 4)
            if i % 2 == 0 then g.setColor(0.9, 0.3, 0.25) else g.setColor(1, 0.97, 0.9) end
            g.rectangle("fill", x - 90 + i * 30.7, CART_Y - 134, 28.7, 18, 3)
        end
    end })
end

-- Boxes in a row, and loose eggs in a row under them, on a cream card whose
-- middle top is at (cx, y). Returns its height.
local BOX_S, BOX_STEP, EGG_S, EGG_STEP = 0.72, 46, 0.9, 19
local function rows(nb, ne, cx, y)
    local w = math.max(nb * BOX_STEP, ne * EGG_STEP) + 24
    local h = (nb > 0 and 30 or 0) + (ne > 0 and 26 or 0) + 16
    art.paper(cx - w / 2, y, w, h)
    local by = y + 8 + (nb > 0 and 22 or 0)
    for i = 1, nb do box(cx - nb * BOX_STEP / 2 + (i - 0.5) * BOX_STEP, by, BOX_S) end
    for i = 1, ne do egg(cx - ne * EGG_STEP / 2 + (i - 0.5) * EGG_STEP, by + 24, EGG_S) end
    return h
end

-- What a kid carries, above their head: boxes, and loose eggs under them.
local function drawCarried(k)
    local nb, ne = k.boxes or 0, k.eggs or 0
    if nb == 0 and ne == 0 then return end
    local h = (nb > 0 and 30 or 0) + (ne > 0 and 26 or 0) + 16
    rows(nb, ne, k.x, k.y - 130 * k.look.size - h)
end

-- At the top: the deliveries of the round (stars). On the cart: its sign,
-- the number asked for, and (levels 1-2, or after a wrong try) the same in
-- boxes and eggs; after a delivery, "34 = 30 + 4".
function oeufs.drawHud()
    local x0 = 640 - (PER_ROUND - 1) * 22
    art.panel(x0 - 30, 8, (PER_ROUND - 1) * 44 + 60, 44)
    for i = 1, PER_ROUND do art.star(x0 + (i - 1) * 44, 30, 15, i <= S.good) end
    for _, k in ipairs(W.kids) do drawCarried(k) end

    -- the sign, on the left of the cart
    local f = ctx.fonts.sign
    local text = S.sum or tostring(S.target)
    local pics = S.help and not S.sum
    local w = f:getWidth(text) + 50
    local right = CART_X - 112
    local shake = math.sin(S.nope * 40) * 6 * S.nope / 0.6
    local y = CART_Y - 78 - (pics and 74 or 0)
    g.push()
    g.translate(shake, 0)
    art.paper(right - w, y, w, 78)
    g.setFont(f)
    g.setColor(OUTLINE)
    g.printf(text, right - w, y + 39 - f:getHeight() / 2, w, "center")
    if pics then                         -- the same, in boxes and eggs, under it
        local pw = math.max(S.tens * BOX_STEP, S.ones * EGG_STEP) + 24
        rows(S.tens, S.ones, right - pw / 2, y + 84)
    end
    g.pop()
end

return oeufs
