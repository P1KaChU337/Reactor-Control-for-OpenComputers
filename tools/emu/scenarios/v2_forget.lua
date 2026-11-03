-- Реактор взорвался: после перезапуска его номер виден как "нет связи", его можно забыть с перенумерацией
local emu = __EMU__
local mocks = require("mocks")
local OUT = os.getenv("EMU_OUT") or "/tmp/rc_emu_out"
emu.install("../../src", "/home/reactorcontrol")
local rs = {}
for i = 1, 3 do rs[i] = mocks.reactor() emu.addComponent(rs[i]) end
emu.addComponent(mocks.me())
emu.queue = {}
local fs = require("filesystem")
fs.makeDirectory("/home/reactorcontrol/data")
local f = io.open("/home/reactorcontrol/data/config.cfg", "w")
f:write('{firstStart = false, users = {"Boss"}, usersApplied = {"Boss"}, reactorSlots = {["dead-reactor"] = 1, ["'
    .. rs[1].address .. '"] = 2, ["' .. rs[2].address .. '"] = 3, ["' .. rs[3].address .. '"] = 4}}')
f:close()
emu.at(3, function() emu.dump(OUT .. "/forget_01_offline.txt") end)
emu.at(4, function() emu.touch(24, 20) end)        -- «Забыть» на виджете #1
emu.at(5, function() emu.dump(OUT .. "/forget_02_modal.txt") end)
emu.at(6, function() emu.touch(80, 28) end)        -- «Забыть и перенумеровать»
emu.at(8, function() emu.dump(OUT .. "/forget_03_after.txt") end)
emu.at(9, function() emu.touch(50, 45) end)        -- запустить все: команды идут нужным реакторам
emu.at(12, function()
    emu.trace("после перенумерации и запуска: " .. tostring(rs[1].state.active) .. " " .. tostring(rs[2].state.active) .. " " .. tostring(rs[3].state.active))
end)
emu.endTime = 13
emu.runVirtual("/home/reactorcontrol/main.lua")
local cfg = io.open("/home/reactorcontrol/data/config.cfg"):read("a")
emu.trace("reactorSlots: " .. cfg:match("reactorSlots = (%b{})"):gsub("%s+", " "))
