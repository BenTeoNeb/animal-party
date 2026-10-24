-- progress.lua: the adaptive difficulty. Each game has a ladder of small
-- steps (its STEPS table); after every task the game says whether it went
-- well ("clean": right the first time, no mistake):
--   UP clean ones in a row (3 by default, a game may say less) -> one step up
--   2 not clean in a row                                       -> one step down
-- So a child who gets everything right climbs fast, and one who struggles
-- comes back to where it goes well (without being told).
-- Each kid's step in each game is saved (progres.lua in the save folder);
-- next time the game starts one step below, to warm up.

local progress = {}

local FILE = "progres.lua"
local saved                                  -- saved[mode][kid id] = step

local function load()
    if saved then return end
    saved = {}
    local ok, data = pcall(function()
        if love.filesystem.getInfo(FILE) then return love.filesystem.load(FILE)() end
    end)
    if ok and type(data) == "table" then saved = data end
end

local function save()
    local lines = { "return {" }
    for mode, kids in pairs(saved) do
        local parts = {}
        for id, step in pairs(kids) do parts[#parts + 1] = string.format("%s = %d", id, step) end
        lines[#lines + 1] = string.format("    %s = { %s },", mode, table.concat(parts, ", "))
    end
    lines[#lines + 1] = "}"
    pcall(love.filesystem.write, FILE, table.concat(lines, "\n") .. "\n")
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
