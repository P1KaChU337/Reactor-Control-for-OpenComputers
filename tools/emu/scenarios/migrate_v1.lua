-- Переход игрока с v1 на v2 через старый апдейтер:
-- v1 видит versions.txt = 2.0.0 -> своё окно обновления -> "Установить" -> installer/updater.lua (переходник)
-- -> install_v2.lua --auto -> перезагрузка -> v2 стартует с настройками v1
local emu = __EMU__
local mocks = require("mocks")
local OUT = os.getenv("EMU_OUT") or "/tmp/rc_emu_out"
io.popen("mkdir -p " .. OUT):close()
emu.install("../..", "/__repo__")
local PREFIXES = {
    "https://raw.githubusercontent.com/P1KaChU337/Reactor-Control-for-OpenComputers/main/",
    "https://github.com/P1KaChU337/Reactor-Control-for-OpenComputers/raw/refs/heads/main/",
}
emu.http = setmetatable({}, {__index = function(_, url)
    for _, p in ipairs(PREFIXES) do
        if url:sub(1, #p) == p then
            local f = io.open("/__repo__/" .. url:sub(#p + 1), "rb")
            if not f then return nil end
            local d = f:read("a") f:close() return d
        end
    end
end})

-- компьютер игрока с v1
local fs = require("filesystem")
fs.makeDirectory("/home/data")
local f = io.open("/home/data/config.lua", "w")
f:write('porog = 777000\nusers = {"Player"}\nusersold = {"Player"}\ntheme = false\nupdateCheck = true\ndebugLog = false\nisFirstStart = false\n')
f:close()
f = io.open("/home/.shrc", "w") f:write("main.lua\n") f:close()
emu.install("../../home", "/home")            -- nr_v1.1.lua и картинки v1
for i = 1, 2 do emu.addComponent(mocks.reactor()) end
emu.addComponent(mocks.me())
emu.addComponent(mocks.internet())
emu.queue = {}

emu.at(4, function() emu.dump(OUT .. "/migrate_01_v1_modal.txt") end)
emu.at(5, function() emu.touch(84, 26) end)  -- "Установить" в окне обновления v1
emu.endTime = 8
emu.runVirtual("/home/nr_v1.1.lua")
local hasUpdater = io.open("/home/updater", "r") ~= nil
emu.trace("v1 скачала переходник: " .. tostring(hasUpdater))

emu.endTime = 10
emu.runVirtual("/home/updater")                        -- его запускает v1 через os.execute("updater")
emu.trace("переходник скачал установщик: " .. tostring(io.open("/home/rc_install.lua", "r") ~= nil))

emu.endTime = 30
emu.runVirtual("/home/rc_install.lua", "--auto")      -- его запускает переходник; в конце перезагрузка
emu.trace(".shrc после установки: " .. io.open("/home/.shrc", "r"):read("a"):gsub("\n", "\\n"))

-- "перезагрузка": автозапуск из .shrc
emu.queue = {}
emu.at(33, function() emu.interrupt() end)
emu.endTime = 35
emu.runVirtual("/home/reactorcontrol/main.lua", "--plain")
local cfg = io.open("/home/reactorcontrol/data/config.cfg", "r"):read("a")
emu.trace("v2: порог из v1 = " .. tostring(cfg:match("threshold = (%d+)")) .. ", игроки: " .. tostring(cfg:match("users = (%b{})")):gsub("%s+", " "))
