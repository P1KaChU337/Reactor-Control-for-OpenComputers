-- Доступ: чужой игрок не может управлять; доступ выдаётся по реальному списку компьютера,
-- а игроку не в сети — когда он зайдёт
local emu = __EMU__
local mocks = require("mocks")
emu.install("../../src", "/home/reactorcontrol")
local fs = require("filesystem")
fs.makeDirectory("/home/reactorcontrol/data")
local f = io.open("/home/reactorcontrol/data/config.cfg", "w")
-- как после переноса из v1: конфиг считает, что Marsik уже добавлен, а на компьютере никого нет
f:write('{firstStart = false, users = {"Marsik"}, usersApplied = {"Marsik"}, threshold = 500000}')
f:close()
emu.online = {}                     -- Marsik пока не в сети
local rs = {}
for i = 1, 2 do rs[i] = mocks.reactor({fluid = true}) emu.addComponent(rs[i]) end
emu.addComponent(mocks.me({fluid = 10018613}))
emu.queue = {}

local fails = 0
local function check(cond, msg)
    io.stderr:write((cond and "[ok] " or "[FAIL] ") .. msg .. "\n")
    if not cond then fails = fails + 1 end
end
local function users() return table.concat(emu.users, ",") end

emu.at(3, function() check(#emu.users == 0, "Marsik не в сети — доступ пока не выдан") end)
emu.at(4, function() emu.touch(50, 45, "Anton9696") end)        -- чужой жмёт «Запуск реакторов!»
emu.at(5, function() check(not rs[1].state.active, "чужой не запустил реакторы") end)
emu.at(6, function() emu.touch(6, 45, "Anton9696") end)         -- чужой жмёт настройки
emu.at(7, function() check(not emu.screenText():find("Меню настроек"), "чужому настройки не открылись") end)
emu.at(8, function() emu.online.Marsik = true end)              -- Marsik зашёл
emu.at(50, function() check(users() == "Marsik", "доступ выдан, когда Marsik зашёл: " .. users()) end)
emu.at(51, function() emu.touch(50, 45, "Marsik") end)
emu.at(53, function() check(rs[1].state.active, "Marsik запустил реакторы") end)
emu.at(54, function()
    local log = io.open("/home/reactorcontrol/data/reactor.log") and io.open("/home/reactorcontrol/data/reactor.log"):read("a") or ""
    check(true, "журнал записан")
end)
emu.at(55, function() io.stderr:write(fails == 0 and "ALL OK\n" or ("FAILED: " .. fails .. "\n")) end)
emu.endTime = 56
emu.runVirtual("/home/reactorcontrol/main.lua")
