-- Reactor Control v2: точка входа.
-- Запуск: main.lua            (пока интерфейса нет — журнал в терминал)
local function scriptDir()
    local src = debug.getinfo(1, "S").source or ""
    local path = src:match("^[@=](.*)$")
    return path and path:match("^(.*)/[^/]*$") or "/home/reactorcontrol"
end
local ROOT = scriptDir()
package.path = ROOT .. "/?.lua;" .. ROOT .. "/lib/?.lua;" .. package.path

local component = require("component")
local computer = require("computer")
local event = require("event")
local App = require("core.app")

local app = App.new({
    component = component,
    computer = computer,
    event = event,
    configPath = ROOT .. "/data/config.cfg",
    legacyConfigPath = "/home/data/config.lua",
    logPath = ROOT .. "/data/reactor.log",
})

-- пока без интерфейса: всё, что пишется в журнал, выводим в терминал
app.log:onEntry(function(e)
    io.write(string.format("[%7.1f] %-5s %s%s\n", e.time - app.state.startedAt, e.level:upper(), e.text,
        e.count > 1 and (" (x" .. e.count .. ")") or ""))
end)

app:init()
app:run()
