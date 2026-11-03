-- v2 --nogui: управление с клавиатуры
local emu = __EMU__
local mocks = require("mocks")
emu.install("../../src", "/home/reactorcontrol")
local rs = {}
for i = 1, 2 do rs[i] = mocks.reactor() emu.addComponent(rs[i]) end
emu.addComponent(mocks.me())
emu.queue = {}
emu.at(2, function() emu.key(string.byte("s"), 31) end)
emu.at(4, function() emu.trace("после s: " .. tostring(rs[1].state.active) .. " " .. tostring(rs[2].state.active)) end)
emu.at(5, function() emu.key(string.byte("2"), 3) end)
emu.at(7, function() emu.trace("после 2: " .. tostring(rs[1].state.active) .. " " .. tostring(rs[2].state.active)) end)
emu.at(8, function() emu.key(string.byte("q"), 16) end)
emu.endTime = 12
emu.runVirtual("/home/reactorcontrol/main.lua", "--nogui")
