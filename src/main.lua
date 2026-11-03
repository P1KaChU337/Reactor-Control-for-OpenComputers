-- Reactor Control v2: точка входа.
--   main.lua           обычный запуск с интерфейсом
--   main.lua --nogui   без интерфейса, журнал в терминал (для отладки)
local function scriptDir()
    local src = debug.getinfo(1, "S").source or ""
    local path = src:match("^[@=](.*)$")
    return path and path:match("^(.*)/[^/]*$") or "/home/reactorcontrol"
end
local ROOT = scriptDir()
package.path = ROOT .. "/?.lua;" .. package.path

local args = {...}
local nogui = false
for _, a in ipairs(args) do if a == "--nogui" then nogui = true end end

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

local buffer
if nogui then
    app.log:onEntry(function(e)
        io.write(string.format("[%7.1f] %-5s %s%s\n", e.time - app.state.startedAt, e.level:upper(), e.text,
            e.count > 1 and (" (x" .. e.count .. ")") or ""))
    end)
else
    buffer = require("doubleBuffering")
    buffer.setResolution(160, 50)
    buffer.clear(0x000000)
    local UI = require("ui.ui")
    local ui = UI.new(app, buffer, {imagesDir = ROOT .. "/images"})
    ui:attach()
    app.ui = ui
end

app:init()
if app.ui and app.cfg.firstStart then app.ui:openModal(require("ui.screens.settings")) end
app:run()

if buffer then
    buffer.clear(0x000000)
    buffer.drawChanges(true)
    pcall(function() require("term").clear() end)
end
if app.exitReason == "restart" then computer.shutdown(true) end
