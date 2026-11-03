-- Установщик v2 на компьютере со старой версией: "скачивание" берёт файлы из локального репозитория,
-- после установки запускается установленная программа без интерфейса
local emu = __EMU__
local mocks = require("mocks")
local BASE = "https://raw.githubusercontent.com/P1KaChU337/Reactor-Control-for-OpenComputers/claude/keen-volta-rnypyl/"
emu.http = setmetatable({}, {__index = function(_, url)
    if url:sub(1, #BASE) ~= BASE then return nil end
    local f = io.open("/__repo__/" .. url:sub(#BASE + 1), "rb")
    if not f then return nil end
    local d = f:read("a") f:close() return d
end})
emu.install("../../src", "/__repo__/src")
emu.install("../../lib", "/__repo__/lib")
emu.install("../../installer", "/home")

-- старая версия и её конфиг
local fs = require("filesystem")
fs.makeDirectory("/home/data")
local f = io.open("/home/data/config.lua", "w")
f:write('porog = 300000\nusers = {"Player"}\nusersold = {"Player"}\ntheme = false\nupdateCheck = true\ndebugLog = false\nisFirstStart = false\n')
f:close()

emu.stdin = {"n"}
emu.runVirtual("/home/install_v2.lua")
emu.trace("установлено файлов: " .. (io.popen("find " .. emu.realPath("/home/reactorcontrol") .. " -type f | wc -l"):read("l")))

for i = 1, 2 do emu.addComponent(mocks.reactor()) end
emu.addComponent(mocks.me())
emu.queue = {}
emu.at(5, function() emu.interrupt() end)
emu.endTime = 8
emu.runVirtual("/home/reactorcontrol/main.lua", "--nogui")
