-- Установщик v2: чистая установка поверх v1 (с вопросами и кнопками), потом обновление с --yes.
-- "Скачивание" берёт файлы из локального репозитория.
local emu = __EMU__
local mocks = require("mocks")
local OUT = os.getenv("EMU_OUT") or "/tmp/rc_emu_out"
io.popen("mkdir -p " .. OUT):close()
local BASE = "https://raw.githubusercontent.com/P1KaChU337/Reactor-Control-for-OpenComputers/claude/keen-volta-rnypyl/"
emu.http = setmetatable({}, {__index = function(_, url)
    if url:sub(1, #BASE) ~= BASE then return nil end
    local f = io.open("/__repo__/" .. url:sub(#BASE + 1), "rb")
    if not f then return "404: Not Found" end
    local d = f:read("a") f:close() return d
end})
emu.install("../../src", "/__repo__/src")
emu.install("../../lib", "/__repo__/lib")
emu.install("../../installer", "/__repo__/installer")
emu.install("../../installer", "/home")
emu.addComponent({type = "internet", address = "inet-1"})

-- старая версия v1, её конфиг и автозапуск
local fs = require("filesystem")
fs.makeDirectory("/home/data")
local f = io.open("/home/data/config.lua", "w")
f:write('porog = 300000\nusers = {"Player"}\nusersold = {"Player"}\ntheme = false\nupdateCheck = true\ndebugLog = false\nisFirstStart = false\n')
f:close()
f = io.open("/home/main.lua", "w") f:write("-- v1") f:close()
f = io.open("/home/.shrc", "w") f:write("main.lua\n") f:close()

local function shot(name) emu.dump(OUT .. "/inst_" .. name .. ".txt") end
emu.at(1, function() shot("01_confirm") end)
emu.at(2, function() emu.key(13, 28) end)        -- Enter: Установить
emu.at(4, function() shot("02_done") end)
emu.at(5, function() emu.key(string.byte("q"), 16) end) -- выход (без перезагрузки)
emu.endTime = 8
emu.runVirtual("/home/install_v2.lua")
local sh = io.open("/home/.shrc", "r"):read("a")
emu.trace("установлено файлов: " .. io.popen("find " .. emu.realPath("/home/reactorcontrol") .. " -type f | wc -l"):read("l")
    .. ", .shrc: " .. sh:gsub("\n", "\\n"))

-- обновление без вопросов
emu.endTime = 20
emu.at(10, function() shot("03_update") end)
emu.runVirtual("/home/install_v2.lua", "--yes")
emu.trace("после обновления .shrc: " .. io.open("/home/.shrc", "r"):read("a"):gsub("\n", "\\n"))

-- обновление из программы (--auto) при ВЫКЛЮЧЕННОМ автозапуске: одноразовый запуск после перезагрузки
local g = io.open("/home/.shrc", "w") g:write("echo hello\n") g:close()
emu.endTime = 40
local okAuto = emu.runVirtual("/home/install_v2.lua", "--auto")
emu.trace("после --auto .shrc: " .. io.open("/home/.shrc", "r"):read("a"):gsub("\n", "\\n"))
emu.trace("одноразовый скрипт есть: " .. tostring(io.open("/home/.rc_once.lua", "r") ~= nil))
emu.runVirtual("/home/.rc_once.lua")   -- "перезагрузка": .shrc выполняет одноразовый скрипт
emu.trace("после запуска .rc_once .shrc: " .. io.open("/home/.shrc", "r"):read("a"):gsub("\n", "\\n")
    .. ", скрипт удалён: " .. tostring(io.open("/home/.rc_once.lua", "r") == nil))

-- и программа запускается
for i = 1, 2 do emu.addComponent(mocks.reactor()) end
emu.addComponent(mocks.me())
emu.queue = {}
emu.at(43, function() emu.interrupt() end)
emu.endTime = 45
emu.runVirtual("/home/reactorcontrol/main.lua", "--nogui")
