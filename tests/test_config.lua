local config = require("core.config")
local T = T
local tmp = os.tmpname()
os.remove(tmp)
local dir = tmp .. "_cfg"
os.execute("mkdir -p " .. dir)

T.test("config: значения по умолчанию", function()
    local c, info = config.load(dir .. "/nope.cfg", dir .. "/nope_legacy.lua")
    T.eq(info.source, "default"); T.eq(c.threshold, 50000); T.eq(c.theme, "dark"); T.eq(c.autoRestart, true)
end)

T.test("config: перенос старого config.lua", function()
    local f = io.open(dir .. "/legacy.lua", "w")
    f:write('porog = 123456 -- коммент\nusers = {"P1KaChU337", "Ник2"}\nusersold = {"P1KaChU337"}\ntheme = true\nupdateCheck = false\ndebugLog = true\nisFirstStart = false\n')
    f:close()
    local c, info = config.load(dir .. "/new.cfg", dir .. "/legacy.lua")
    T.eq(info.source, "legacy"); T.eq(c.threshold, 123456); T.eq(#c.users, 2); T.eq(c.users[2], "Ник2")
    T.eq(c.usersApplied[1], "P1KaChU337"); T.eq(c.theme, "light"); T.eq(c.updateCheck, false); T.eq(c.firstStart, false)
end)

T.test("config: старый конфиг с ошибкой из-за бага usersold не роняет программу", function()
    local f = io.open(dir .. "/broken_legacy.lua", "w")
    f:write('porog = 1\nusers = {"a"}\nusersold = {"a", "b""c"}\n')
    f:close()
    local c, info = config.load(dir .. "/new2.cfg", dir .. "/broken_legacy.lua")
    T.eq(info.source, "default")
    T.ok(#info.warnings > 0)
end)

T.test("config: проверка значений", function()
    local c, w = config.normalize({threshold = -5, theme = "pink", users = {"ok_name", "", "a_very_long_name_over_16", "ok_name", 5}, bufferStopSec = 1000, unknown = 1})
    T.eq(c.threshold, 0); T.eq(c.theme, "dark"); T.eq(#c.users, 1); T.eq(c.bufferStopSec, 60)
    T.ok(#w >= 2)
end)

T.test("config: сохранение и чтение, повреждённый файл", function()
    local c = config.defaults()
    c.threshold = 777; c.users = {"X"}; c.reactorSlots = {["addr-1"] = 2}
    T.ok(config.save(c, dir .. "/save.cfg"))
    local back, info = config.load(dir .. "/save.cfg", dir .. "/nope.lua")
    T.eq(info.source, "file"); T.eq(back.threshold, 777); T.eq(back.users[1], "X"); T.eq(back.reactorSlots["addr-1"], 2)
    local f = io.open(dir .. "/save.cfg", "w") f:write("{ это не lua") f:close()
    local d, info2 = config.load(dir .. "/save.cfg", dir .. "/nope.lua")
    T.eq(info2.source, "default"); T.eq(d.threshold, 50000)
    local bf = io.open(dir .. "/save.cfg.broken", "r"); T.ok(bf, "битый файл сохранён рядом"); bf:close()
end)

T.test("config: все параметры, которые читают защита и интерфейс, есть в схеме", function()
    local used = {}
    for _, f in ipairs({"src/logic/protection.lua", "src/core/actions.lua", "src/core/app.lua",
        "src/ui/screens/main.lua", "src/ui/screens/settings.lua", "src/ui/textui.lua"}) do
        local code = io.open(f):read("a")
        for k in code:gmatch("cfg%.([%a_][%w_]*)") do used[k] = f end
    end
    for k, f in pairs(used) do T.ok(config.SCHEMA[k], "нет параметра '" .. k .. "' (используется в " .. f .. ")") end
end)
