-- Новая версия с интерфейсом: скриншоты главного экрана, аварий, настроек и инфо
local emu = __EMU__
local mocks = require("mocks")
local OUT = os.getenv("EMU_OUT") or "/tmp/rc_emu_out"
io.popen("mkdir -p " .. OUT):close()
emu.install("../../src", "/home/reactorcontrol")

-- конфиг без первого запуска
local fs = require("filesystem")
fs.makeDirectory("/home/reactorcontrol/data")
local f = io.open("/home/reactorcontrol/data/config.cfg", "w")
f:write('{firstStart = false, users = {"Player"}, usersApplied = {"Player"}, threshold = 1000000, theme = "dark"}')
f:close()

local reactors = {}
for i = 1, 6 do
    reactors[i] = mocks.reactor({fluid = i ~= 5, rodFuel = 3000 + i * 900})
    emu.addComponent(reactors[i])
end
local me = mocks.me({fluid = 10018613})
emu.addComponent(me)
emu.addComponent(mocks.flux())
emu.addComponent(mocks.chatbox())
emu.queue = {}

local function shot(name) emu.dump(OUT .. "/v2_" .. name .. ".txt") end
emu.at(3, function() shot("01_idle") end)
emu.at(4, function() emu.touch(50, 45) end)                    -- «Запуск реакторов!»
emu.at(4.1, function() shot("02_pressed") end)
emu.at(6, function() emu.touch(50, 45) end)                    -- повторно: «уже запущены»
emu.at(75, function() shot("03_running") end)
emu.at(80.5, function() reactors[2].state.supply = false end) -- перебой подачи у №2
emu.at(100, function() shot("04_buffer_fault") end)
emu.at(101, function() me.state.fluid = 500000 end)          -- мало хладагента в МЭ
emu.at(150, function() shot("05_me_low") end)
emu.at(151, function() emu.touch(6, 45) end)                  -- настройки
emu.at(153, function() emu.touch(45, 15) end)                 -- поле порога
emu.at(154, function() emu.key(string.byte("5"), 6) end)
emu.at(155, function() shot("06_settings") end)
emu.at(156, function() emu.touch(5, 5) end)                   -- мимо окна: выйти без сохранения
emu.at(157, function() emu.touch(6, 48) end)                  -- инфо
emu.at(159, function() shot("07_info") end)
emu.at(160, function() emu.touch(5, 5) end)
emu.at(161, function() me.state.fluid = 10018613 end)
emu.at(200, function() shot("08_recovered") end)
emu.at(201, function() emu.removeComponent(reactors[4]) end)
emu.at(210, function() shot("09_offline") end)
emu.at(211, function() reactors[2].state.supply = true end)
emu.at(212, function() emu.touch(60, 20) end)                 -- «Включить» на виджете №2 (после аварии буфера)
emu.at(220, function() shot("10_manual_start") end)
emu.at(221, function() emu.touch(6, 45) end)                  -- настройки
emu.at(222, function() emu.touch(45, 19) end)                 -- тема: светлая
emu.at(223, function() emu.touch(50, 34) end)                 -- «Сохранить и выйти»
emu.at(226, function() shot("11_light") end)
emu.at(228, function() emu.touch(45, 48) end)                 -- «Выход из программы.»
emu.endTime = tonumber(os.getenv("EMU_END")) or 232

local c0 = os.clock()
emu.runVirtual("/home/reactorcontrol/main.lua")
emu.trace(string.format("готово: cpu=%.2fс за %.0f с игрового времени, вызовов компонентов=%d (%.1f/с), GPU=%d",
    os.clock() - c0, emu.time, emu.componentCalls, emu.componentCalls / emu.time, emu.gpuCalls))
