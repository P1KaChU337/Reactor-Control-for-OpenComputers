-- OpenOS не выгружает модули require до перезагрузки: второй запуск main.lua должен взять новые файлы
local emu = __EMU__
local mocks = require("mocks")
emu.install("../../src", "/home/reactorcontrol")
emu.addComponent(mocks.reactor())
emu.addComponent(mocks.me())
emu.queue = {}
emu.at(1, function() emu.key(string.byte("q"), 16) end)
emu.endTime = 3
emu.runVirtual("/home/reactorcontrol/main.lua", "--nogui")
-- "обновление": подменяем модуль на диске
local f = io.open("/home/reactorcontrol/hw/flux.lua", "w")
f:write('__EMU_RELOADED__ = true\nreturn {read = function() return false end}\n')
f:close()
emu.endTime = 6
emu.at(4, function() emu.key(string.byte("q"), 16) end)
emu.runVirtual("/home/reactorcontrol/main.lua", "--nogui")
emu.trace("новый модуль загружен при втором запуске: " .. tostring(_G.__EMU_RELOADED__ == true))
