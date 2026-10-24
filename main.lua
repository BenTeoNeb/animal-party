-- Animal Party! (La Fête des Animaux !) Each pen wants a number of animals:
-- count them, add the missing ones, take the extra ones out. 1 or 2 players,
-- together. Made with the framework and the drawings of Lava Rescue!

local input = require("input")
local sfx = require("sfx")
local art = require("art")
local world = require("world")
local musique = require("musique")
-- the game log (journal.lua) is not shipped (see build.sh): without it, nothing is logged
local hasJournal, journal = pcall(require, "journal")
if not hasJournal then
    journal = setmetatable({}, { __index = function() return function() end end })
end
journal.enabled = true     -- real games are logged (see journal.lua)
local lang = require("lang")
local T = lang.t

-- Sound on/off (music and sound effects together): on by default,
-- Select on the controller (or M on the keyboard) switches it.
local soundOn = true
local function setSound(on)
    soundOn = on
    love.audio.setVolume(on and 1 or 0)
end

local W, H = 1280, 720
local g = love.graphics
local state = "games"      -- "games" (choose the game), "select" (choose the kids), "play"
local level = 1           -- 1 count, 2 add, 3 take away (chosen in the menu)
local mode = "fete"       -- "fete" (the pens), "train", "flash" or "path" (the games screen)
local MODES = { "fete", "train", "flash", "path" }
local function nextMode(dir)
    for i, m in ipairs(MODES) do
        if m == mode then mode = MODES[(i - 1 + dir) % #MODES + 1] return end
    end
end
local function levelName()
    return T(mode == "fete" and "level_" .. level or "level_" .. mode .. "_" .. level)
end
local fonts = {}

-- Character select: each player picks Rami, Zina or Lila.
local pick = {}
local stickWasOut = {}

local function resetSelect()
    pick[1] = { joined = true, choice = 1, ready = false }
    pick[2] = { joined = false, choice = 2, ready = false }
end

local function taken(p, choice)
    local other = pick[3 - p]
    return other.joined and other.choice == choice
end

local function moveChoice(p, dir)
    local c = pick[p].choice
    repeat c = (c - 1 + dir) % #art.KIDS + 1 until not taken(p, c)
    pick[p].choice = c
    sfx.play("select")
end

local function startIfReady()
    for p = 1, 2 do
        if pick[p].joined and not pick[p].ready then return end
    end
    local chosen = {}
    for p = 1, 2 do
        if pick[p].joined then table.insert(chosen, { player = p, kid = pick[p].choice }) end
    end
    world.start(chosen, level, mode)
    state = "play"
end

local function selectAction(p, action)
    local me = pick[p]
    if not me.joined then
        me.joined, me.ready = true, false
        if taken(p, me.choice) then moveChoice(p, 1) end
        sfx.play("ready")
        return
    end
    if action == "left" and not me.ready then
        moveChoice(p, -1)
    elseif action == "right" and not me.ready then
        moveChoice(p, 1)
    elseif action == "grab" then
        me.ready = true
        sfx.play("ready")
        startIfReady()
    elseif action == "drop" then
        if me.ready then me.ready = false
        elseif p == 2 then me.joined = false
        else state = "games" end                    -- player 1: back to the games
    end
end

-- The games screen: left / right picks a game, the bottom button chooses it.
local function gamesAction(p, action)
    if action == "left" or action == "right" then
        nextMode(action == "right" and 1 or -1)
        sfx.play("select")
    elseif action == "grab" then
        resetSelect()
        state = "select"
        sfx.play("ready")
    end
end

-- The menu (Start): pauses the game. Up/down to move, bottom button to choose,
-- Start or the right button to close it.
local menu = nil          -- { sel = n } while the menu is open
local drawMenu
local menuStickOut = {}

local function menuItems()
    local items = { "resume" }
    if state == "play" then table.insert(items, "to_title") end
    if state ~= "play" then table.insert(items, "level") end
    table.insert(items, "fullscreen")
    table.insert(items, "sound")
    table.insert(items, "language")
    table.insert(items, "quit")
    return items
end

local function menuLabel(item)
    if item == "level" then return T("level_item", levelName()) end
    if item == "fullscreen" then return T(love.window.getFullscreen() and "fullscreen_on" or "fullscreen_off") end
    if item == "sound" then return T(soundOn and "sound_on" or "sound_off") end
    if item == "language" then return T("language_item") end
    return T(item)
end

local function openMenu()
    menu = { sel = 1 }
    sfx.play("select")
end

local function menuChoose()
    local item = menuItems()[menu.sel]
    sfx.play("select")
    if item == "resume" then
        menu = nil
    elseif item == "to_title" then
        if world.phase ~= "results" then world.logEnd("accueil") end
        menu = nil
        resetSelect()
        state = "games"
    elseif item == "level" then
        level = level % 3 + 1
    elseif item == "fullscreen" then
        love.window.setFullscreen(not love.window.getFullscreen(), "desktop")
    elseif item == "sound" then
        setSound(not soundOn)
    elseif item == "language" then
        lang.toggle()
    elseif item == "quit" then
        if state == "play" and world.phase ~= "results" then world.logEnd("quitte") end
        love.event.quit()
    end
end

local function menuAction(action)
    local n = #menuItems()
    if action == "up" then
        menu.sel = (menu.sel - 2) % n + 1
        sfx.play("select")
    elseif action == "down" then
        menu.sel = menu.sel % n + 1
        sfx.play("select")
    elseif action == "grab" then
        menuChoose()
    elseif action == "start" or action == "drop" then
        menu = nil
    end
end

local makeFonts

-- Make the fonts for the real size of the screen: the 1280x720 picture is
-- scaled up (x3 in 4K), and on Retina screens there are 2 pixels per point.
local fontScale
makeFonts = function()
    local w, h = g.getDimensions()
    local s = math.min(w / W, h / H) * g.getDPIScale()
    if fontScale and math.abs(s - fontScale) < 0.01 then return end
    fontScale = s
    art.fontScale = s
    art.resetFonts()
    fonts.title = art.font(58, "titre")
    fonts.big = art.font(38, "titre")
    fonts.mid = art.font(24)
    fonts.small = art.font(20)
    world.makeFonts()
end

function love.resize()
    makeFonts()
end

function love.load()
    -- the window's icon (made by outils/icone)
    if love.filesystem.getInfo("icone.png") then
        pcall(love.window.setIcon, love.image.newImageData("icone.png"))
    end
    sfx.load()
    world.load()
    musique.load()
    art.preload()
    setSound(true)
    makeFonts()
    resetSelect()
    for _, js in ipairs(love.joystick.getJoysticks()) do
        input.joystickadded(js)
    end
end

function love.update(dt)
    dt = math.min(dt, 1 / 30)
    if menu then
        for p = 1, 2 do
            local y = input.stickY(p)
            local out = math.abs(y) > 0.6
            if out and not menuStickOut[p] then menuAction(y > 0 and "down" or "up") end
            menuStickOut[p] = out
        end
        return
    end
    if state == "games" then
        for p = 1, 2 do                  -- the stick moves the choice too, one step per push
            local x = input.stickX(p)
            local out = math.abs(x) > 0.6
            if out and not stickWasOut[p] then gamesAction(p, x > 0 and "right" or "left") end
            stickWasOut[p] = out
        end
        musique.update(dt, 0, 0, false)
    elseif state == "select" then
        -- let the stick move the choice too, one step per push
        for p = 1, 2 do
            local x = input.stickX(p)
            local out = math.abs(x) > 0.6
            if out and not stickWasOut[p] and pick[p].joined and not pick[p].ready then
                moveChoice(p, x > 0 and 1 or -1)
            end
            stickWasOut[p] = out
        end
        musique.update(dt, 0, 0, false)
    else
        world.update(dt)
        -- (big moments can lower the music for a moment with world.duck = seconds,
        -- and musique.update's tension adds drums: both unused for now)
        if (world.duck or 0) > 0 then musique.duck(world.duck); world.duck = 0 end
        musique.update(dt, 0, 0, true)
        if world.done then
            resetSelect()
            state = "games"
        end
    end
end

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

local PLAYER_COLORS = { { 1, 0.7, 0.2 }, { 0.4, 0.75, 1 } }

-- A little picture of each game, around (0, 0), about 110 x 70 at size 1.
local function drawModeIcon(m)
    if m == "fete" then                 -- a hen and a 3
        art.animal("poule", -20, 30, 1, 1.0, false)
        outlined("3", fonts.big, 4, -26, 40, { 1, 0.9, 0.4 })
    elseif m == "path" then             -- three stones, 1 2 3, and a squirrel hopping
        for i = 0, 2 do
            g.setColor(0.23, 0.14, 0.09)
            g.ellipse("fill", -36 + i * 34, 18, 17, 11)
            g.setColor(0.86, 0.84, 0.8)
            g.ellipse("fill", -36 + i * 34, 18, 14, 8)
            g.setFont(fonts.small)
            g.setColor(0.23, 0.14, 0.09)
            g.printf(tostring(i + 1), -46 + i * 34, 17 - fonts.small:getHeight() / 2, 20, "center")
        end
        art.animal("ecureuil", -2, -8, 1, 0.75, false)
    elseif m == "flash" then            -- a bush with two eyes peeking out
        art.prop("buisson", -10, 28, 1, 2.2)
        g.setColor(1, 1, 1)
        g.circle("fill", -20, -2, 7)
        g.circle("fill", 0, -2, 7)
        g.setColor(0.23, 0.14, 0.09)
        g.circle("fill", -18, -1, 3.5)
        g.circle("fill", 2, -1, 3.5)
    else                                -- a little train: two wagons and the engine
        for i = 0, 2 do
            local c = ({ { 0.4, 0.75, 0.35 }, { 1, 0.78, 0.2 }, { 0.3, 0.55, 0.9 } })[i + 1]
            local up = i == 2 and 12 or 0
            g.setColor(0.23, 0.14, 0.09)
            g.rectangle("fill", -42 + i * 28, -4 - up, 26, 24 + up, 4)
            g.setColor(c)
            g.rectangle("fill", -40 + i * 28, -2 - up, 22, 20 + up, 3)
            g.setColor(0.23, 0.14, 0.09)
            g.circle("fill", -34 + i * 28, 22, 5)
            g.circle("fill", -22 + i * 28, 22, 5)
        end
    end
end

-- The background of the home screens: grass, trees, animals, the title, a
-- subtitle, and the sound / language / level boxes at the top left.
local function drawBackdrop(subtitle)
    local t = love.timer.getTime()
    if not art.grass(W, H, world.GRASS_TILE) then
        g.setColor(0.5, 0.75, 0.35)
        g.rectangle("fill", 0, 0, W, H)
        g.setColor(0.56, 0.8, 0.4)
        for i = 0, 12 do g.ellipse("fill", (i * 173) % 1200 + 40, (i * 251) % 640 + 80, 90, 50) end
    end
    for i, x in ipairs({ 60, 170, 1230 }) do art.tree(x, 700, 1.1, false, ({ "chene", "sapin", "pommier" })[i]) end
    local kinds = { "poule", "ecureuil", "marcassin", "herisson", "renard" }
    for i, kind in ipairs(kinds) do
        art.animal(kind, 300 + i * 120, 714 - math.abs(math.sin(t * 4 + i)) * 6, 1, 1.0)
    end

    outlined(T("title"), fonts.title, 0, 30, W, { 1, 0.85, 0.3 })
    outlined(T(subtitle), fonts.mid, 0, 110, W)

    -- sound on/off (View / Select button) and language (shoulder buttons), top left
    art.panel(14, 12, 250, 38)
    art.panel(14, 56, 250, 38)
    art.glyph("view", 38, 31)
    outlined(T(soundOn and "sound_on" or "sound_off"), fonts.small, 56, 20, 200,
        soundOn and { 0.6, 1, 0.6 } or { 0.85, 0.85, 0.85 })
    g.setFont(fonts.small)
    art.glyph("lr", 56, 75, 0.75)
    outlined(T("language"), fonts.small, 82, 64, 180, { 1, 0.95, 0.6 })
    -- the level (changed in the menu)
    art.panel(14, 100, 250, 38)
    outlined(levelName(), fonts.small, 14, 108, 250, { 0.6, 0.9, 1 })
end

-- The games screen: four big cards with a picture, left / right to pick one.
local function drawGames()
    drawBackdrop("choose_game")
    local t = love.timer.getTime()
    for i, m in ipairs(MODES) do
        local cx = 640 + (i - 2.5) * 293
        local on = m == mode
        local bounce = on and math.abs(math.sin(t * 5)) * 8 or 0
        if on then                       -- the chosen one glows
            g.setColor(1, 0.85, 0.3, 0.55 + 0.25 * math.sin(t * 6))
            g.rectangle("fill", cx - 144, 156 - bounce, 288, 328, 34)
        end
        art.paper(cx - 130, 170 - bounce, 260, 300)
        g.push()
        g.translate(cx, 300 - bounce)
        g.scale(2.3)
        drawModeIcon(m)
        g.pop()
        g.setFont(fonts.big)
        g.setColor(art.OUTLINE)
        g.printf(T("mode_" .. m), cx - 130, 398 - bounce, 260, "center")
    end
    art.hint({ "@dpad", T("choose_short"), "   ", "@a", T("go"), "   ", "@menu", T("menu_hint") },
        W / 2, 624, fonts.small)
end

local function drawSelect()
    drawBackdrop("choose")
    local t = love.timer.getTime()

    for i, k in ipairs(art.KIDS) do
        local x = 220 + (i - 1) * 320 - 60
        for p = 1, 2 do
            local me = pick[p]
            if me.joined and me.choice == i then
                local c = PLAYER_COLORS[p]
                g.setColor(c[1], c[2], c[3], 0.3)
                g.rectangle("fill", x - 110, 160, 220, 360, 24)
                g.setColor(c)
                g.setLineWidth(me.ready and 8 or 4)
                g.rectangle("line", x - 110, 160, 220, 360, 24)
            end
        end
        local bounce = 0
        for p = 1, 2 do
            if pick[p].joined and pick[p].choice == i then bounce = math.abs(math.sin(t * 5)) * 10 end
        end
        art.kid(k, x, 460 - bounce, 1, 3.0, 0)
        outlined(k.name, fonts.big, x - 110, 470, 220)

        for p = 1, 2 do
            local me = pick[p]
            if me.joined and me.choice == i then
                outlined(T("player") .. p .. (me.ready and "  " .. T("ready") or ""), fonts.mid, x - 110, 170, 220,
                    PLAYER_COLORS[p])
            end
        end
    end

    -- the game chosen, top right (B goes back to the games)
    art.paper(1000, 12, 266, 82)
    g.push()
    g.translate(1060, 60)
    drawModeIcon(mode)
    g.pop()
    g.setFont(fonts.mid)
    g.setColor(art.OUTLINE)
    g.printf(T("mode_" .. mode), 1108, 36, 150, "center")
    -- how to play, with the buttons as icons
    art.hint({ "@dpad", T("choose_short"), "   ", "@a", T("go"), "   ", "@b", T("back_short"), "   ",
        "@menu", T("menu_hint") }, W / 2, 624, fonts.small)
    if not pick[2].joined then
        outlined(T("join"), fonts.small, 0, 648, W, PLAYER_COLORS[2])
    end
end

drawMenu = function()
    g.setColor(0, 0, 0, 0.55)
    g.rectangle("fill", 0, 0, W, H)
    local items = menuItems()
    local ph = 120 + #items * 62
    local py = (H - ph) / 2
    art.paper(390, py, 500, ph)
    outlined(T("menu"), fonts.big, 390, py + 20, 500, { 1, 0.8, 0.2 })
    for i, item in ipairs(items) do
        local y = py + 92 + (i - 1) * 62
        if i == menu.sel then
            g.setColor(art.OUTLINE)
            g.rectangle("fill", 417, y - 9, 446, 56, 18)
            g.setColor(art.COLORS.todo)
            g.rectangle("fill", 420, y - 6, 440, 50, 16)
        end
        g.setFont(fonts.mid)
        g.setColor(art.OUTLINE)
        g.printf(menuLabel(item), 390, y + 19 - fonts.mid:getHeight() / 2, 500, "center")
    end
end

function love.draw()
    makeFonts()   -- only rebuilt if the screen size changed
    -- Draw at 1280x720 and scale to fit the window.
    local w, h = g.getDimensions()
    local s = math.min(w / W, h / H)
    g.clear(0.1, 0.22, 0.1)   -- the bars around the picture (e.g. on the 16:10 Steam Deck)
    g.translate((w - W * s) / 2, (h - H * s) / 2)
    g.scale(s)
    g.setScissor((w - W * s) / 2, (h - H * s) / 2, W * s, H * s)
    if state == "games" then drawGames() elseif state == "select" then drawSelect() else world.draw() end
    if menu then drawMenu() end
    g.setScissor()
end

local function onAction(p, action)
    if action == "back" then setSound(not soundOn) return end   -- Select: sound on/off
    if menu then menuAction(action) return end
    if action == "lang" then                                     -- L1/R1: language
        if state ~= "play" then lang.toggle() end
        return
    end
    -- Start opens the menu (except on the end screen, where it plays again)
    if action == "start" and not (state == "play" and world.phase == "results") then
        openMenu()
        return
    end
    if state == "games" then gamesAction(p, action)
    elseif state == "select" then selectAction(p, action)
    else world.action(p, action) end
end

function love.joystickadded(joystick)
    input.joystickadded(joystick)
end

function love.joystickremoved(joystick)
    input.joystickremoved(joystick)
end

function love.quit()
    if state == "play" and world.phase ~= "results" then world.logEnd("quitte") end
end

function love.focus(focused)
    if not focused and state == "play" and world.phase == "play" and not menu then
        menu = { sel = 1 }
    end
end

function love.gamepadpressed(joystick, button)
    local p, action = input.gamepadpressed(joystick, button)
    if p then onAction(p, action) end
end

function love.keypressed(key)
    if key == "m" then setSound(not soundOn) return end
    if key == "l" and state ~= "play" then lang.toggle() return end
    local p, action = input.keypressed(key)
    if p then onAction(p, action) end
end
