-- v2: бегущая строка спонсоров, changelog с GitHub, проверка обновлений, чат-команды
local emu = __EMU__
local mocks = require("mocks")
local OUT = os.getenv("EMU_OUT") or "/tmp/rc_emu_out"
io.popen("mkdir -p " .. OUT):close()
emu.install("../../src", "/home/reactorcontrol")
local REPO = "https://raw.githubusercontent.com/P1KaChU337/Reactor-Control-for-OpenComputers/"
local rf = function(p) local f = assert(rawget(_G, "__EMU_RAW_OPEN__") and nil or io.popen("cat ../../" .. p)) local d = f:read("a") f:close() return d end
emu.http = {
    [REPO .. "main/supporters.txt"] = rf("supporters.txt"),
    [REPO .. "main/changelog.lua"] = rf("changelog.lua"),
    [REPO .. "claude/keen-volta-rnypyl/version_v2.txt"] = "2.0.1\n",
}
local fs = require("filesystem")
fs.makeDirectory("/home/reactorcontrol/data")
local f = io.open("/home/reactorcontrol/data/config.cfg", "w")
f:write('{firstStart = false, users = {"Boss"}, usersApplied = {"Boss"}}') f:close()

for i = 1, 3 do emu.addComponent(mocks.reactor({fluid = i ~= 3})) end
emu.addComponent(mocks.me())
emu.addComponent(mocks.flux())
local cb = mocks.chatbox()
emu.addComponent(cb)
emu.addComponent(mocks.internet())
emu.queue = {}

local function shot(n) emu.dump(OUT .. "/net_" .. n .. ".txt") end
emu.at(10, function() shot("01_marquee") end)
emu.at(11, function() shot("02_marquee_moved") end)
emu.at(12, function() emu.chat("Boss", "@start") end)
emu.at(14, function() emu.chat("Stranger", "@stop") end)
emu.at(16, function() emu.chat("Boss", "@status") end)
emu.at(18, function() emu.touch(6, 48) end)       -- Инфо
emu.at(19, function() emu.touch(60, 9) end)       -- вкладка «Изменения в версиях»
emu.at(21, function() shot("03_info_changelog") end)
emu.at(22, function() emu.touch(5, 49) end)
emu.at(24, function() emu.chat("Boss", "@exit") end)
emu.endTime = 30
emu.runVirtual("/home/reactorcontrol/main.lua")
emu.trace("чат-бокс сказал " .. #cb.said .. " строк")
