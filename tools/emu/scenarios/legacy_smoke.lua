-- Прогон старой версии (home/nr_v1.1.lua) для эталонных скриншотов
local emu = __EMU__
local mocks = require("mocks")
local fs = require("filesystem")
local OUT = os.getenv("EMU_OUT") or "/tmp/rc_emu_out"
io.popen("mkdir -p " .. OUT):close()

fs.makeDirectory("/home/data")
local f = io.open("/home/data/config.lua", "w")
f:write('porog = 50000\nusers = {"Player"}\nusersold = {"Player"}\ntheme = false\nupdateCheck = false\ndebugLog = false\nisFirstStart = false\n')
f:close()

local reactors = {}
for i = 1, 6 do
    local r = mocks.reactor({fluid = i ~= 3, active = false})
    reactors[i] = r
    emu.addComponent(r)
end
local me = mocks.me({fluid = 2500000})
emu.addComponent(me)
emu.addComponent(mocks.flux())
emu.addComponent(mocks.chatbox())
emu.queue = {}  -- стартовые component_added не нужны

emu.http = {["https://github.com/P1KaChU337/Reactor-Control-for-OpenComputers/raw/refs/heads/main/supporters.txt"] = "Спасибо всем: Test1, Test2, Test3, Test4"}

emu.at(5, function() emu.dump(OUT .. "/legacy_01_idle.txt") end)
emu.at(6, function() emu.touch(50, 45) end)          -- «Запуск реакторов!»
emu.at(20, function() emu.dump(OUT .. "/legacy_02_running.txt") end)
emu.at(21, function() me.state.fluid = 10000 end)   -- жидкость кончилась
emu.at(90, function() emu.dump(OUT .. "/legacy_03_nofluid.txt") end)
emu.at(91, function() emu.touch(6, 45) end)          -- настройки
emu.at(95, function() emu.dump(OUT .. "/legacy_04_settings.txt") end)
emu.endTime = 96

local c0, t0 = os.clock(), emu.time
local ok = emu.run(os.getenv("EMU_PROGRAM") or "../../home/nr_v1.1.lua")
__EMU__.trace(string.format("done ok=%s virtual=%.1fs cpu=%.2fs gpuCalls=%d componentCalls=%d\n", tostring(ok), emu.time - t0, os.clock() - c0, emu.gpuCalls, emu.componentCalls))
