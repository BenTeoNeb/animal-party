-- progress.lua: the adaptive difficulty. Each game has a ladder of small
-- steps (its STEPS table); after every task the game says whether it went
-- well ("clean": right the first time, no mistake):
--   UP clean ones in a row (3 by default, a game may say less) -> one step up
--   2 not clean in a row                                       -> one step down
-- So a child who gets everything right climbs fast, and one who struggles
-- comes back to where it goes well (without being told).
-- Each kid's step in each game is saved (progres.lua in the save folder);
-- next time the game starts one step below, to warm up. Saving is safe
-- (a new file swapped in, the previous one kept as progres.lua.bak).

local progress = {}

local FILE = "progres.lua"
local VERSION = 1                            -- the file's format (bump it and migrate below)
local saved                                  -- saved[mode][kid id] = step

-- Read one save file as plain data: run in an empty sandbox (it cannot touch
-- the game), and only a table of numbers is accepted. Nil if missing or damaged.
local function read(file)
    if not love.filesystem.getInfo(file) then return nil end
    local ok, data = pcall(function()
        local chunk = assert(love.filesystem.load(file))
        setfenv(chunk, {})
        return chunk()
    end)
    if not ok or type(data) ~= "table" then return nil end
    local version = tonumber(data.version) or 0  -- (0: before the version number)
    data.version = nil
    if version > VERSION then return nil end   -- from a newer game: do not touch it
    for mode, kids in pairs(data) do
        if type(kids) ~= "table" then return nil end
        for id, step in pairs(kids) do
            if type(step) ~= "number" then return nil end
        end
    end
    return data
end

local function load()
    if saved then return end
    -- the backup (the save before the last one) if the save is damaged
    saved = read(FILE) or read(FILE .. ".bak") or {}
end

local function encode()
    local lines = { "return {", string.format("    version = %d,", VERSION) }
    for mode, kids in pairs(saved) do
        local parts = {}
        for id, step in pairs(kids) do parts[#parts + 1] = string.format("%s = %d", id, step) end
        lines[#lines + 1] = string.format("    %s = { %s },", mode, table.concat(parts, ", "))
    end
    lines[#lines + 1] = "}"
    return table.concat(lines, "\n") .. "\n"
end

-- Never write over the save in place (a crash or a power cut in the middle
-- would lose the kids' progress): write a new file, check it reads back,
-- keep the old one as .bak, then put the new one in its place.
local function save()
    local dir = love.filesystem.getSaveDirectory() .. "/"
    local tmp = FILE .. ".tmp"
    if not pcall(love.filesystem.write, tmp, encode()) or not read(tmp) then return end
    if love.filesystem.getInfo(FILE) then
        os.remove(dir .. FILE .. ".bak")
        os.rename(dir .. FILE, dir .. FILE .. ".bak")
    end
    if not os.rename(dir .. tmp, dir .. FILE) then
        pcall(love.filesystem.write, FILE, encode())   -- (no rename here: write it directly)
    end
end

-- Where to start: the menu's level gives a floor (1, a third, two thirds of
-- the ladder); the kids' saved step minus one (the lowest of the kids
-- playing; in the challenge, the saved step itself) may start higher.
function progress.start(mode, kidIds, menuLevel, steps, challenge)
    load()
    local floor = ({ 1, math.floor(steps / 3) + 1, math.floor(2 * steps / 3) + 1 })[menuLevel or 1] or 1
    local low
    for _, id in ipairs(kidIds) do
        local s = saved[mode] and saved[mode][id]
        if s then low = math.min(low or s, s) end
    end
    local start = math.max(floor, low and (challenge and low or low - 1) or 1)
    return math.max(1, math.min(steps, start))
end

-- A task is done: clean or not. Returns the new step, and +1 / -1 / 0.
function progress.answer(state, clean, steps, up)
    if clean then
        state.good, state.bad = (state.good or 0) + 1, 0
        if state.good >= (up or 3) and state.step < steps then
            state.step, state.good = state.step + 1, 0
            return state.step, 1
        end
    else
        state.bad, state.good = (state.bad or 0) + 1, 0
        if state.bad >= 2 and state.step > 1 then
            state.step, state.bad = state.step - 1, 0
            return state.step, -1
        end
    end
    return state.step, 0
end

-- Remember each kid's step in this game.
function progress.save(mode, kidIds, step)
    load()
    saved[mode] = saved[mode] or {}
    for _, id in ipairs(kidIds) do saved[mode][id] = step end
    save()
end

return progress
