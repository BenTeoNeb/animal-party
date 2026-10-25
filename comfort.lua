-- comfort.lua: "gentle motion", for kids who feel sick when the landscape
-- moves (the train). Chosen in the pause menu, remembered (comfort.txt in
-- the save folder). On: the far hills and the clouds stand still, the train
-- drives at half speed and its trip is half as long.

local comfort = { on = false }
local FILE = "comfort.txt"

function comfort.load()
    local ok, text = pcall(love.filesystem.read, FILE)
    comfort.on = ok and text ~= nil and text:sub(1, 1) == "1"
end

function comfort.set(on)
    comfort.on = on
    pcall(love.filesystem.write, FILE, on and "1\n" or "0\n")
end

return comfort
