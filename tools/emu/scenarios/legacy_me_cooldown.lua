-- Баг v1.1.3: кулдаун ME getItemsInNetwork воспринимается как "Ошибка жидкости"
-- и аварийно останавливает все жидкостные реакторы.
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
for i = 1, 6 do reactors[i] = mocks.reactor() emu.addComponent(reactors[i]) end
emu.addComponent(mocks.me({fluid = 50000000, cooldown = 15}))
emu.queue = {}

emu.at(3, function() emu.touch(50, 45) end)   -- «Запуск реакторов!»
emu.at(8, function()
    local on = 0 for _, r in ipairs(reactors) do if r.state.active then on = on + 1 end end
    emu.trace("работает реакторов до нажатия: " .. on)
    emu.touch(75, 45)                            -- «Пр.Обновить МЭ» (кулдаун ещё идёт)
end)
emu.at(12, function()
    local on = 0 for _, r in ipairs(reactors) do if r.state.active then on = on + 1 end end
    emu.trace("работает реакторов после нажатия: " .. on .. (on == 0 and "  <-- БАГ: аварийная остановка из-за кулдауна ME" or ""))
    emu.dump(OUT .. "/legacy_me_cooldown.txt")
end)
emu.endTime = 13
emu.run(os.getenv("EMU_PROGRAM") or "../../home/nr_v1.1.lua")
