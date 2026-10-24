-- ferme.lua: the farm, the place of the Nest of 10 and the Egg Boxes: the
-- farmyard ground, its decor (a barn, hay bales, fences, a trough, a
-- wheelbarrow) and the drawings the two games share (an egg, an egg box
-- holding 0 to 10 eggs, the basket of what a kid carries).
-- UI rules for these games: what is counted is a drawing at least 60 px; the
-- task is at the top in the middle, the progress (stars) at the top left,
-- what a kid carries at the bottom left (player 2: bottom right).

local art = require("art")

local ferme = {}
local g = love.graphics

ferme.GROUND = "cour"                        -- images/cour.png, the farmyard tile (made
ferme.GROUND_TILE = 560                      -- from planches/cour.png, which repeats as is)
ferme.KID_SCALE = 1.6                        -- the kids, bigger on the farm (the stall's table
                                             -- comes up to their chest)

-- An image h tall, its feet at (x, y), flipped if f = -1; tint (optional).
function ferme.image(name, x, y, h, f, tint)
    local im = art.image(name)
    if not im then return end
    local sc = h / im:getHeight()
    g.setColor(tint or { 1, 1, 1 })
    g.draw(im, x, y, 0, sc * (f or 1), sc, im:getWidth() / 2, im:getHeight())
end

-- Add decor pieces ({ name, x, y, h, f }) to the things drawn back to front.
-- Each one stands on a soft shadow (like the animals), so it sits on the
-- ground instead of floating.
function ferme.things(list, decor)
    for _, d in ipairs(decor) do
        table.insert(list, { y = d[3], draw = function()
            local im = art.image(d[1])
            if im then
                local w = d[4] * im:getWidth() / im:getHeight()
                g.setColor(0, 0, 0, 0.2)
                g.ellipse("fill", d[2] + w * 0.04, d[3] - 2, w * 0.54, math.max(6, w * 0.07))
            end
            ferme.image(d[1], d[2], d[3], d[4], d[5])
        end })
    end
end

-- An egg, its bottom at (x, y), h tall.
function ferme.egg(x, y, h)
    if art.image("oeuf") then
        g.setColor(0, 0, 0, 0.16)
        g.ellipse("fill", x + h * 0.08, y - h * 0.02, h * 0.34, h * 0.1)
        ferme.image("oeuf", x, y, h)
        return
    end
    g.setColor(art.OUTLINE)
    g.ellipse("fill", x, y - h / 2, h * 0.4, h * 0.5)
    g.setColor(1, 0.97, 0.9)
    g.ellipse("fill", x, y - h / 2, h * 0.34, h * 0.44)
end

-- The egg cups of the box drawing (images/boite_vide.png), as parts of its
-- width and height: two rows of five.
local CUPS = {
    { 0.148, 0.6 }, { 0.323, 0.6 }, { 0.499, 0.6 }, { 0.674, 0.6 }, { 0.849, 0.6 },
    { 0.129, 0.78 }, { 0.314, 0.78 }, { 0.499, 0.78 }, { 0.683, 0.78 }, { 0.868, 0.78 },
}

-- An egg box w wide, its middle bottom at (x, y), with n eggs in its cups
-- (10: a full box, a ten). glow: a soft light around it (counted, chosen...).
function ferme.box(x, y, w, n, glow)
    local im = art.image("boite_vide")
    if not im then return end
    local sc = w / im:getWidth()
    local h = im:getHeight() * sc
    if glow then
        g.setColor(glow[1], glow[2], glow[3], 0.45)
        g.rectangle("fill", x - w / 2 - 8, y - h - 8, w + 16, h + 16, 18)
    end
    g.setColor(0, 0, 0, 0.16)
    g.ellipse("fill", x + 4, y - 2, w * 0.5, h * 0.12)
    g.setColor(1, 1, 1)
    g.draw(im, x, y, 0, sc, sc, im:getWidth() / 2, im:getHeight())
    for i = 1, math.min(n or 0, 10) do
        local c = CUPS[i]
        local ex, ey = x - w / 2 + c[1] * w, y - h + c[2] * h
        ferme.image("oeuf", ex, ey + w * 0.05, w * 0.15)
    end
    return h
end

-- How tall a box w wide is.
function ferme.boxHeight(w)
    local im = art.image("boite_vide")
    return im and w * im:getHeight() / im:getWidth() or w * 0.8
end

-- What a kid carries, at the bottom (player 1 on the left, player 2 next to
-- it): the basket, the full boxes, and an open box filling with the loose
-- eggs (so you can see how many more make a ten).
function ferme.basket(k, boxes, eggs)
    local BW, OPEN = 54, 96                       -- a full box, the open one
    local cols = math.min(4, math.max(1, boxes))
    local rowsN = math.max(1, math.ceil(boxes / 4))
    local w = 92 + (boxes > 0 and cols * (BW + 6) + 6 or 0) + OPEN + 24
    local h = math.max(112, rowsN * 46 + 50)
    local x0 = k.player == 2 and 470 or 12        -- (the bottom right is the stall's)
    local y0 = 720 - 8 - h
    art.paper(x0, y0, w, h)
    ferme.image("panier", x0 + 48, y0 + h - 12, 78)
    local x = x0 + 92
    for i = 1, boxes do                           -- the full boxes, 4 a row
        local c, r = (i - 1) % 4, math.floor((i - 1) / 4)
        ferme.box(x + 6 + c * (BW + 6) + BW / 2, y0 + 56 + r * 46, BW, 10)
    end
    if boxes > 0 then x = x + cols * (BW + 6) + 6 end
    ferme.box(x + 6 + OPEN / 2, y0 + h - 14, OPEN, eggs, eggs > 0 and { 1, 0.86, 0.35 } or nil)
end

return ferme
