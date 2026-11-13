local Actions = require("core.actions")
local config = require("core.config")
local T = T

-- Компьютер как в OC: addUser — только для игроков в сети, users() — имена несколькими значениями
local function fakeComputer(online, users)
    local c = {list = users or {}}
    function c.addUser(n)
        if online and not online[n] then return nil, "player must be online" end
        for _, u in ipairs(c.list) do if u == n then return true end end
        c.list[#c.list + 1] = n
        return true
    end
    function c.removeUser(n)
        for i, u in ipairs(c.list) do if u == n then table.remove(c.list, i) return true end end
        return false
    end
    function c.users() return table.unpack(c.list) end
    return c
end

local function app(cfgPatch, computer)
    local cfg = config.defaults()
    for k, v in pairs(cfgPatch) do cfg[k] = v end
    local logs = {}
    local log = {}
    for _, lvl in ipairs({"info", "warn", "error", "ok", "debug"}) do
        log[lvl] = function(_, t) logs[#logs + 1] = lvl .. ": " .. t end
    end
    local a = {cfg = cfg, log = log, computer = computer, saves = 0, logs = logs}
    a.saveConfig = function() a.saves = a.saves + 1 end
    a.actions = Actions.new(a)
    return a
end

local function has(list, n) for _, u in ipairs(list) do if u == n then return true end end return false end

T.test("доступ: выдаётся по реальному списку компьютера, а не по записям конфига", function()
    -- конфиг (например, перенесённый из v1) считает, что доступ уже выдан, а на компьютере пусто
    local comp = fakeComputer()
    local a = app({users = {"Marsik"}, usersApplied = {"Marsik"}}, comp)
    T.ok(a.actions:syncUsers())
    T.ok(has(comp.list, "Marsik"), "доступ выдан")
end)

T.test("доступ: игрок не в сети — повтор позже, предупреждение один раз", function()
    local online = {}
    local comp = fakeComputer(online)
    local a = app({users = {"Marsik"}, usersApplied = {}}, comp)
    T.no(a.actions:syncUsers())
    T.no(a.actions:syncUsers())
    local warns = 0
    for _, l in ipairs(a.logs) do if l:find("^warn: Не удалось выдать") then warns = warns + 1 end end
    T.eq(warns, 1)
    online.Marsik = true
    T.ok(a.actions:syncUsers())
    T.ok(has(comp.list, "Marsik"))
    T.eq(a.cfg.usersApplied[1], "Marsik")
end)

T.test("доступ: лишние пользователи компьютера убираются, при пустом списке — никто", function()
    local comp = fakeComputer(nil, {"Anton9696", "Marsik"})
    local a = app({users = {"Marsik"}}, comp)
    a.actions:syncUsers()
    T.no(has(comp.list, "Anton9696"))
    T.ok(has(comp.list, "Marsik"))
    local comp2 = fakeComputer(nil, {"Someone"})
    local b = app({users = {}}, comp2)
    b.actions:syncUsers()
    T.ok(has(comp2.list, "Someone"), "пустой белый список ничего не трогает")
end)

T.test("доступ: управлять программой может только белый список; пустой — все", function()
    local a = app({users = {"Marsik"}}, fakeComputer())
    T.ok(a.actions:canUse("Marsik"))
    T.no(a.actions:canUse("Anton9696"))
    T.no(a.actions:canUse(nil))
    local b = app({users = {}}, fakeComputer())
    T.ok(b.actions:canUse("Anton9696"))
end)
