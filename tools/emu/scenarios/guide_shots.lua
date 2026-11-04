-- Скриншоты для гайда на форуме: всё снимается настоящей программой v2 в эмуляторе
local emu = __EMU__
local mocks = require("mocks")
local OUT = os.getenv("EMU_OUT") or "/tmp/rc_emu_out"
io.popen("mkdir -p " .. OUT):close()
emu.install("../../src", "/home/reactorcontrol")
local REPO = "https://raw.githubusercontent.com/P1KaChU337/Reactor-Control-for-OpenComputers/main/"
local function rf(p) local f = io.popen("cat ../../" .. p) local d = f:read("a") f:close() return d end
emu.http = {
    [REPO .. "about_v2.txt"] = rf("about_v2.txt"),
    [REPO .. "changelog.lua"] = rf("changelog.lua"),
    [REPO .. "changelog_v2.lua"] = rf("changelog_v2.lua"):gsub("}%s*$", "") .. [[
  {
    version = "2.0.1",
    changes = {
      "# Виджеты",
      "Пример: здесь будет описание того, что изменилось в новой версии",
      "# Исправления",
      "Пример: что было исправлено",
    }
  },
}
]],
    [REPO .. "version_v2.txt"] = "2.0.0\n",
}
local fs = require("filesystem")
fs.makeDirectory("/home/reactorcontrol/data")
local f = io.open("/home/reactorcontrol/data/config.cfg", "w")
f:write('{firstStart = false, users = {"P1KaChU337", "oGoOgO"}, usersApplied = {"P1KaChU337", "oGoOgO"}, threshold = 500000}')
f:close()

-- 6 реакторов: 5 жидкостных (MOX), 1 воздушный; у стержней разный остаток топлива
local rs = {}
local fuelBase = {3900, 6200, 2500, 7400, 5100, 8300}
for i = 1, 6 do
    local r = mocks.reactor({fluid = i ~= 5, gen = i == 5 and 651800 or 7793856, temp = i == 5 and 0 or 9998})
    local k = 0
    for slot, rod in pairs(r.state.rods) do
        k = k + 1
        rod.fuel = math.min(10000, fuelBase[i] + (k * 337) % 4500)
    end
    rs[i] = r
    emu.addComponent(r)
end
emu.addComponent(mocks.me({fluid = 10018613}))
emu.addComponent(mocks.flux())
emu.addComponent(mocks.chatbox())
emu.addComponent(mocks.internet())
emu.queue = {}

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

local function shot(n) emu.dump(OUT .. "/guide_" .. n .. ".txt") end
emu.at(2, function() emu.touch(50, 45) end)                       -- «Запуск реакторов!»
emu.at(150, function() shot("main") end)
emu.at(151, function() emu.touch(6, 45) end)                      -- настройки
emu.at(152, function() shot("settings") end)
emu.at(153, function() emu.touch(5, 5) end)
emu.at(154, function() emu.touch(6, 48) end)                      -- информация
emu.at(156, function() shot("info") end)
emu.at(157, function() emu.touch(60, 9) end)                      -- вкладка «Изменения в версиях»
emu.at(158, function() shot("changelog") end)
emu.at(159, function() emu.touch(5, 5) end)
emu.at(160, function()                                            -- вышла «новая версия»
    emu.http[REPO .. "version_v2.txt"] = "2.0.1\n"
    _G.__RC_APP__:checkUpdates()
end)
emu.at(164, function() shot("update") end)
emu.at(165, function() emu.touch(75, 38) end)                     -- «Позже»
-- аварии
emu.at(170.5, function() rs[2].state.supply = false rs[3].state.supply = false end)
for i, t in ipairs({185, 195, 205, 215}) do emu.at(t, function() emu.touch(98, 20) end) end -- игрок жмёт «Включить» у №3
emu.at(225, function() rs[2].state.supply = true rs[3].state.supply = true end)
emu.at(226, function() for _, r in ipairs(rs) do end end)
emu.at(230, function() rs[1].state.supply = true end)
emu.at(231, function() _G.__RC_APP__.cfg.threshold = 20000000 _G.__RC_APP__.actions:refreshMe() end) -- в МЭ меньше порога
emu.at(270, function() shot("faults") end)
emu.at(271, function() _G.__RC_APP__.cfg.threshold = 500000 _G.__RC_APP__.actions:refreshMe() end)
emu.at(300, function() emu.removeComponent(rs[6]) end)            -- реактор №6 «взорвался»
emu.at(305, function() shot("offline") end)
emu.at(306, function() emu.touch(98, 37) end)                     -- «Забыть»
emu.at(307, function() shot("forget") end)
emu.at(308, function() emu.touch(5, 5) end)
-- светлая тема
emu.at(310, function() emu.touch(6, 45) end)
emu.at(311, function() emu.touch(45, 19) end)
emu.at(312, function() emu.touch(50, 34) end)
emu.at(315, function() shot("light") end)
emu.endTime = 316
emu.runVirtual("/home/reactorcontrol/main.lua")
