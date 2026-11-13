-- Новая версия (src/) без интерфейса: старт, запуск реакторов, пропуск долива, авария ME, автозапуск
local emu = __EMU__
local mocks = require("mocks")
emu.install("../../src", "/home/reactorcontrol")

-- старый конфиг: проверяем перенос настроек
local fs = require("filesystem")
fs.makeDirectory("/home/data")
local f = io.open("/home/data/config.lua", "w")
f:write('porog = 1000000\nusers = {"Player"}\nusersold = {}\ntheme = true\nupdateCheck = false\ndebugLog = false\nisFirstStart = false\n')
f:close()

local reactors = {}
for i = 1, 3 do reactors[i] = mocks.reactor({fluid = i ~= 3}) emu.addComponent(reactors[i]) end
local me = mocks.me({fluid = 50000000})
emu.addComponent(me)
emu.addComponent(mocks.flux())
emu.queue = {}

local function report(tag)
    local parts = {}
    for i, r in ipairs(reactors) do
        parts[#parts + 1] = string.format("#%s %s %3.0f%%", r.address:sub(9, 12), r.state.active and "ON " or "off", r.state.coolant / r.state.maxCoolant * 100)
    end
    emu.trace("== " .. tag .. ": " .. table.concat(parts, " | "))
end

-- запуск через "действие" приложения (кнопок ещё нет): дергаем app из глобала, который выставит сценарий
emu.at(2, function() report("старт программы") end)
emu.at(3, function() _G.__RC_APP__.actions:start(nil, "сценарий") end)
emu.at(10, function() report("после запуска") end)
-- 1) один пропущенный долив у реактора 1: не должен останавливать
emu.at(20.5, function() reactors[1].state.supply = false end)
emu.at(22.5, function() reactors[1].state.supply = true end)
emu.at(30, function() report("после пропуска 1 долива") end)
-- 2) долив пропал надолго у реактора 2: остановка защитой, потом автозапуск
emu.at(40.5, function() reactors[2].state.supply = false end)
emu.at(60, function() report("реактор 2 без подачи") end)
emu.at(61, function() reactors[2].state.supply = true end)
emu.at(110, function() report("подача вернулась") end)
-- 3) хладагент в ME ниже порога: жидкостные стоят, воздушный работает
emu.at(120, function() me.state.fluid = 500000 end)
emu.at(200, function() report("МЭ ниже порога") end)
emu.at(201, function() me.state.fluid = 50000000 end)
emu.at(290, function() report("МЭ восстановилась") end)
-- 4) реактор выдернули из сети
emu.at(300, function() emu.removeComponent(reactors[1]) end)
emu.at(310, function() report("реактор 1 пропал") end)
emu.at(320, function() emu.addComponent(reactors[1]) end)
emu.at(330, function() report("реактор 1 вернулся") end)
emu.at(340, function() emu.key(0, 29, "Player") emu.interrupt() end)   -- Ctrl+C от игрока из белого списка
emu.endTime = 345

-- выставить __RC_APP__: оборачиваем App.new
local realRequire = require
_G.require = function(name)
    local m = realRequire(name)
    if name == "core.app" and not m.__wrapped then
        local new = m.new
        m.new = function(...) local a = new(...) _G.__RC_APP__ = a return a end
        m.__wrapped = true
    end
    return m
end

local c0 = os.clock()
emu.runVirtual("/home/reactorcontrol/main.lua")
emu.trace(string.format("готово: cpu=%.2fс, вызовов компонентов=%d (%.1f/с)", os.clock() - c0, emu.componentCalls, emu.componentCalls / emu.time))
local cfg = io.open("/home/reactorcontrol/data/config.cfg", "r")
emu.trace("config.cfg:\n" .. (cfg and cfg:read("a") or "НЕТ"))
