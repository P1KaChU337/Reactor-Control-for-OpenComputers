-- v2: бегущая строка спонсоров, changelog с GitHub, проверка обновлений, чат-команды
local emu = __EMU__
local mocks = require("mocks")
local OUT = os.getenv("EMU_OUT") or "/tmp/rc_emu_out"
io.popen("mkdir -p " .. OUT):close()
emu.install("../../src", "/home/reactorcontrol")
local REPO = "https://raw.githubusercontent.com/P1KaChU337/Reactor-Control-for-OpenComputers/"
local rf = function(p) local f = assert(rawget(_G, "__EMU_RAW_OPEN__") and nil or io.popen("cat ../../" .. p)) local d = f:read("a") f:close() return d end
emu.http = {
    [REPO .. "claude/keen-volta-rnypyl/about_v2.txt"] = rf("about_v2.txt"):gsub("Спасибо за поддержку:", "Спасибо за поддержку (с GitHub):"),
    [REPO .. "main/changelog.lua"] = rf("changelog.lua"),
    [REPO .. "claude/keen-volta-rnypyl/version_v2.txt"] = "2.0.1\n",
    [REPO .. "claude/keen-volta-rnypyl/changelog_v2.lua"] = rf("changelog_v2.lua"):gsub("}%s*$", "") ..
        '  {version = "2.0.1", changes = {"Новая кнопка, которой раньше не было", "Исправлена ошибка, из-за которой что-то ломалось при определённых условиях на сервере"}},\n}\n',
    [REPO .. "claude/keen-volta-rnypyl/installer/install_v2.lua"] = rf("installer/install_v2.lua"),
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
emu.at(11, function() shot("00_update_modal") end)
emu.at(11.5, function() emu.touch(75, 38) end)  -- «Позже»
emu.at(12, function() emu.touch(6, 48) end)       -- Инфо, вкладка «Общая информация»
emu.at(12.5, function() shot("01_about") end)
emu.at(13, function() emu.touch(5, 49) end)
emu.at(13.5, function() emu.chat("Boss", "@start") end)
emu.at(14, function() emu.chat("Stranger", "@stop") end)
emu.at(16, function() emu.chat("Boss", "@status") end)
emu.at(18, function() emu.touch(6, 48) end)       -- Инфо
emu.at(19, function() emu.touch(60, 9) end)       -- вкладка «Изменения в версиях»
emu.at(21, function() shot("03_info_changelog") end)
emu.at(22, function() emu.touch(5, 49) end)
emu.at(24, function() emu.touch(6, 48) end)       -- Инфо -> «Подробнее об обновлении»
emu.at(25, function() emu.touch(80, 38) end)
emu.at(26, function() shot("04_update_from_info") end)
emu.at(27, function() emu.touch(45, 38) end)     -- «Обновить»
emu.endTime = 30
emu.runVirtual("/home/reactorcontrol/main.lua")
emu.trace("чат-бокс сказал " .. #cb.said .. " строк")
