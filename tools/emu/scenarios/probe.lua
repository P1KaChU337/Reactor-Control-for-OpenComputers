-- Прогон tools/probe/probe.lua на моках
local emu = __EMU__
local mocks = require("mocks")
for i = 1, 3 do emu.addComponent(mocks.reactor({fluid = i ~= 2, active = i == 1})) end
emu.addComponent(mocks.me())
emu.addComponent(mocks.flux())
emu.addComponent(mocks.chatbox())
emu.queue = {}
emu.stdin = {"YES"}
emu.run("../probe/probe.lua", "--watch", "5", "--cooldown", "--toggle", "2")
local f = io.open("/home/probe_report.txt", "r")
print(f and f:read("a") or "НЕТ ОТЧЁТА")
