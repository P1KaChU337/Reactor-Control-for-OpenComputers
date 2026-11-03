-- v1.1.3: два пропущенных долива хладагента подряд (лаг) останавливают реактор навсегда,
-- и после восстановления подачи реактор сам не запускается.
local emu = __EMU__
local mocks = require("mocks")
local fs = require("filesystem")
fs.makeDirectory("/home/data")
local f = io.open("/home/data/config.lua", "w")
f:write('porog = 50000\nusers = {"Player"}\nusersold = {"Player"}\ntheme = false\nupdateCheck = false\ndebugLog = false\nisFirstStart = false\n')
f:close()
local r = mocks.reactor()
emu.addComponent(r)
emu.addComponent(mocks.me({fluid = 50000000}))
emu.queue = {}
emu.at(3, function() emu.touch(50, 45) end)               -- «Запуск реакторов!»
emu.at(20.5, function() r.state.supply = false end)        -- пропускаем два долива (21 и 24 с)
emu.at(25.5, function() r.state.supply = true end)
emu.at(40, function()
    emu.trace(string.format("через 15 с после сбоя: работает=%s, буфер=%.0f%%%s", tostring(r.state.active),
        r.state.coolant / r.state.maxCoolant * 100, r.state.active and "" or "  <-- остановлен после короткого перебоя подачи и не запущен снова"))
end)
emu.endTime = 41
emu.run(os.getenv("EMU_PROGRAM") or "../../home/nr_v1.1.lua")
