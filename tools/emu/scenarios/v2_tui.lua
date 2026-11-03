-- v2 --nogui: текстовая панель + блокировка после 3 ручных запусков при пустом буфере
local emu = __EMU__
local mocks = require("mocks")
local OUT = os.getenv("EMU_OUT") or "/tmp/rc_emu_out"
emu.install("../../src", "/home/reactorcontrol")
local rs = {}
for i = 1, 4 do rs[i] = mocks.reactor({fluid = i ~= 4, rodFuel = 3000 + i * 1000}) emu.addComponent(rs[i]) end
emu.addComponent(mocks.me())
emu.addComponent(mocks.flux())
emu.queue = {}
emu.at(2, function() emu.key(string.byte("s"), 31) end)
emu.at(40, function() emu.dump(OUT .. "/tui_01.txt") end)
emu.at(40.5, function() rs[1].state.supply = false end)
-- игрок упорно жмёт "1"
for i, t in ipairs({60, 65, 70, 75, 80}) do
    emu.at(t, function() emu.key(string.byte("1"), 2) end)
end
emu.at(90, function() emu.dump(OUT .. "/tui_02_locked.txt") end)
emu.at(92, function() emu.key(string.byte("q"), 16) end)
emu.endTime = 95
emu.runVirtual("/home/reactorcontrol/main.lua", "--nogui")
emu.trace("реактор 1 после 5 нажатий: active=" .. tostring(rs[1].state.active))
