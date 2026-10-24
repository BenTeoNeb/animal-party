-- oeufs.lua: the Egg Boxes (les boîtes à œufs): tens and ones, up to 100. On
-- the farm, the hens have laid eggs all over the yard: walk on them to pick
-- them up. They go into an open box in the kid's basket (at the bottom); when
-- it holds 10 eggs it closes ("clac!"): a ten. The market stall asks for a
-- number (the sign at the top), say 34: bring it exactly 3 boxes and 4 eggs.
-- Right: it counts them, "10, 20, 30" then "31, 32, 33, 34" (on the sign, each
-- box and egg lights up), and shows "34 = 30 + 4". Not right: it wobbles; the
-- right button puts one egg down (with no loose egg, it opens a box: one egg
-- down, 9 loose ones carried; breaking a ten).
-- Grouping by ten, then reading a number as tens and ones (the Singapore
-- method's bundles of ten). Levels:
--   1  10 to 19; the sign shows the number and the boxes and eggs in pictures
--   2  20 to 59, pictures
--   3  20 to 99, the number only (the pictures come back after a wrong try)
-- Full boxes lie about at every level (one or two more than needed): walk on
-- one to pick it up, so a ten is one step, not ten. Loose eggs too (a few
-- more than the ones), to fill a box yourself if you like.
-- 3 deliveries make a round.
-- world.lua calls the hooks below at the right moments (see MODES there).

local art = require("art")
local sfx = require("sfx")
local lang = require("lang")
local ferme = require("ferme")

local oeufs = {}
local W, ctx
local g = love.graphics

-- The market stall, big, at the bottom right (images/etal.png): its feet,
-- its height, and where its table is in the drawing (parts of its width and
-- height): the delivered boxes stand on it, in two rows of five.
local CART_X, CART_Y, CART_H = 1070, 714, 300
local TABLE_X1, TABLE_X2 = 0.15, 0.85    -- (the stall seen from the front: a straight table
local TABLE_ROWS = { 0.675, 0.735 }      -- top from 0.62 to 0.735 of its height)
local TABLE_BOX = 50
local PICK = 34                          -- how close to an egg or a box picks it up
local PER_ROUND = 3
local COUNT_GAP = 0.4
local HENS = 6                           -- hens wandering about (they laid the eggs)
local EGG_H, BOX_W = 40, 92              -- an egg and a box on the ground

oeufs.START_X, oeufs.START_Y = 640, 430
oeufs.SCENE, oeufs.GROUND, oeufs.GROUND_TILE = "ferme", ferme.GROUND, ferme.GROUND_TILE
oeufs.KID_SCALE = ferme.KID_SCALE
oeufs.YARD = { x1 = 320, y1 = 170, x2 = 960, y2 = 330 }
local DECOR = {
    { "ferme_grange", 150, 300, 220 }, { "ferme_barriere", 1060, 140, 52 }, { "ferme_barriere", 1190, 140, 52 },
    { "ferme_foin", 1150, 250, 74 }, { "ferme_foin", 1060, 270, 66, -1 },
}

-- The ladder of steps (adaptive, see progress.lua): the numbers asked for,
-- and whether the sign shows them in boxes and eggs too.
oeufs.STEPS = {
    { from = 10, to = 14, pics = true },
    { from = 10, to = 19, pics = true },
    { from = 20, to = 39, pics = true },
    { from = 20, to = 59, pics = true },
    { from = 40, to = 79, pics = true },
    { from = 20, to = 99, pics = false },
    { from = 50, to = 99, pics = false },
}
oeufs.UP = 2                     -- clean deliveries in a row to go up a step

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
        x, y = ctx.rand(50, 1230), ctx.rand(190, 560)
        local ok = not (x < 290 and y < 330) and not (x > 990 and y < 300)          -- the barn, the hay
            and not (math.abs(x - oeufs.START_X) < 60 and math.abs(y - oeufs.START_Y) < 50)
            and not (x > 830 and y > 330)                                         -- the stall
        for _, it in ipairs(S.items) do
            if math.abs(it.x - x) < (it.kind == "box" and 90 or 52) and math.abs(it.y - y) < 46 then ok = false end
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
    local st = oeufs.STEPS[W.level]
    local target = love.math.random(st.from, st.to)
    local tens, ones = math.floor(target / 10), target % 10
    S.target, S.tens, S.ones = target, tens, ones
    -- (in the challenge, the boxes-and-eggs pictures only come after a mistake)
    S.items, S.phase, S.t, S.nope, S.help, S.counted, S.sum = {}, "play", 0, 0, st.pics and not W.challenge, 0, nil
    S.clean = true
    local boxes, eggs
    boxes = tens + (W.level == 1 and 1 or 2)
    eggs = ones + (W.level == 1 and 6 or 5)
    for _ = 1, boxes do
        local x, y = spot()
        table.insert(S.items, { kind = "box", x = x, y = y })
    end
    for _ = 1, eggs do
        local x, y = spot()
        table.insert(S.items, { kind = "egg", x = x, y = y })
    end
    for _, k in ipairs(W.kids) do k.eggs, k.boxes = 0, 0 end
    ctx.journal.log("commande", { niveau = W.level, nombre = target, boites = boxes, oeufs = eggs })
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
    table.insert(S.items, { kind = "egg", x = k.x + 30 * k.facing, y = k.y + 4, wait = 1, owner = k })
    sfx.play("drop")
end

local function deliver(k)
    local total = k.boxes * 10 + k.eggs
    ctx.journal.log("livre", { joueur = k.player, boites = k.boxes, oeufs = k.eggs, demande = S.target })
    if total == S.target then
        ctx.answer(S.clean)
        S.phase, S.t, S.counted, S.by = "count", 0.4, 0, k
        S.inBoxes, S.inEggs = k.boxes, k.eggs
        k.boxes, k.eggs = 0, 0
    else
        S.nope, S.help, S.clean = 0.6, true, false
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
        local reach = it.kind == "box" and PICK + 20 or PICK
        if not it.wait and math.abs(it.x - k.x) < reach and math.abs(it.y - k.y) < reach * 0.7 then
            table.remove(S.items, i)
            if it.kind == "box" then
                k.boxes = k.boxes + 1
                sfx.play("ready")
            else
                k.eggs = k.eggs + 1
                sfx.play("select")
                if k.eggs == 10 then              -- ten eggs: the box is full, a ten!
                    k.eggs, k.boxes = 0, k.boxes + 1
                    sfx.play("clac")
                    ctx.popup("10", k.x, k.y - 170, { 1, 0.9, 0.4 })
                    ctx.hearts(k.x, k.y - 150, 3)
                end
            end
        end
    end
    local atCart = math.abs(k.x - CART_X) < 210 and k.y > CART_Y - 150
    if atCart and not k.atCart and (k.boxes > 0 or k.eggs > 0) then deliver(k) end
    k.atCart = atCart
end

function oeufs.updateAnimal() end

function oeufs.update(dt)
    S.nope = math.max(0, S.nope - dt)
    -- an egg just put down waits until its kid has walked away from it
    for _, it in ipairs(S.items) do
        if it.wait then
            it.wait = math.max(0, it.wait - dt)
            local k = it.owner
            local away = not k or math.abs(k.x - it.x) > PICK * 2 or math.abs(k.y - it.y) > PICK * 2
            if it.wait == 0 and away then it.wait, it.owner = nil, nil end
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
            ctx.popup(tostring(n), CART_X, CART_Y - CART_H - 10, S.counted <= S.inBoxes and { 1, 0.9, 0.4 } or { 0.6, 1, 0.5 })
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

-- The eggs and boxes on the ground.
function oeufs.drawGround()
    for _, it in ipairs(S.items or {}) do
        if it.kind == "box" then ferme.box(it.x, it.y, BOX_W, 10) else ferme.egg(it.x, it.y, EGG_H) end
    end
end

-- Where box i stands on the stall's table (1-5 the back row, 6-10 the front).
local function onTable(i)
    local im = art.image("etal")
    local w = im and CART_H * im:getWidth() / im:getHeight() or CART_H
    local left, top = CART_X - w / 2, CART_Y - CART_H
    local col, row = (i - 1) % 5, math.floor((i - 1) / 5)
    local span = (TABLE_X2 - TABLE_X1) * w
    return left + TABLE_X1 * w + (col + 0.5) * span / 5, top + TABLE_ROWS[row + 1] * CART_H
end

-- The decor and the market stall, with what was delivered on its table: the
-- boxes, then the box of loose eggs filling up, as the stall counts them.
function oeufs.things(list)
    ferme.things(list, DECOR)
    table.insert(list, { y = CART_Y, draw = function()
        local shake = math.sin(S.nope * 40) * 6 * S.nope / 0.6
        ferme.image("etal", CART_X + shake, CART_Y, CART_H)
        if S.phase == "count" or S.phase == "done" then
            local nb = math.min(S.counted, S.inBoxes)
            for i = 1, nb do
                local x, y = onTable(i)
                ferme.box(x + shake, y, TABLE_BOX, 10)
            end
            if S.inEggs > 0 then
                local x, y = onTable(S.inBoxes + 1)
                ferme.box(x + shake, y, TABLE_BOX, math.max(0, S.counted - S.inBoxes))
            end
        end
    end })
end

-- The task, at the top in the middle: the number, and (levels 1-2, or after
-- a wrong try) the same in boxes: full boxes for the tens and an open box
-- with the ones. While the stall counts, they light up one by one.
local SIGN_BOX = 66
local function drawSign()
    local f = ctx.fonts.sign
    local text = S.sum or tostring(S.target)
    local pics = (S.help or S.phase ~= "play") and S.target
    local nb = S.tens + (S.ones > 0 and 1 or 0)
    local pw = pics and nb * (SIGN_BOX + 8) + 12 or 0
    local w = math.max(f:getWidth(text) + 60, pw + 20)
    local h = pics and 154 or 86
    local x = 640 - w / 2
    local shake = math.sin(S.nope * 40) * 6 * S.nope / 0.6
    g.push()
    g.translate(shake, 0)
    art.paper(x, 6, w, h)
    g.setFont(f)
    g.setColor(art.OUTLINE)
    g.printf(text, x, 48 - f:getHeight() / 2, w, "center")
    if pics then                         -- under the number: the same in boxes
        local lit = S.phase ~= "play" and S.counted or 0
        local bx = 640 - (nb * (SIGN_BOX + 8) - 8) / 2 + SIGN_BOX / 2
        for i = 1, S.tens do
            ferme.box(bx, 146, SIGN_BOX, 10, i <= lit and { 0.5, 1, 0.4 } or nil)
            bx = bx + SIGN_BOX + 8
        end
        if S.ones > 0 then
            local lone = S.phase ~= "play" and lit > S.inBoxes
            ferme.box(bx, 146, SIGN_BOX, S.ones, lone and { 0.5, 1, 0.4 } or nil)
        end
    end
    g.pop()
end

-- At the top left: the deliveries of the round (stars); at the top: the
-- task; at the bottom: each kid's basket.
function oeufs.drawHud()
    art.panel(12, 8, (PER_ROUND - 1) * 40 + 52, 44)
    for i = 1, PER_ROUND do art.star(38 + (i - 1) * 40, 30, 15, i <= S.good) end
    drawSign()
    for _, k in ipairs(W.kids) do ferme.basket(k, k.boxes or 0, k.eggs or 0) end
end

function oeufs.drawIcon(x, y, s)    -- (for the games screen) two boxes and 3 eggs
    ferme.box(x - 26 * s, y, 56 * s, 10)
    ferme.box(x + 34 * s, y, 56 * s, 3)
end

return oeufs
