-- Reactor Control v2: точка входа.
--   main.lua           обычный запуск с интерфейсом
--   main.lua --nogui   текстовый режим: журнал слева, реакторы справа, управление с клавиатуры
--   main.lua --plain   только строки журнала в терминал
local function scriptDir()
    local src = debug.getinfo(1, "S").source or ""
    local path = src:match("^[@=](.*)$")
    return path and path:match("^(.*)/[^/]*$") or "/home/reactorcontrol"
end
local ROOT = scriptDir()
if not package.path:find(ROOT .. "/?.lua", 1, true) then package.path = ROOT .. "/?.lua;" .. package.path end

-- OpenOS держит модули из require в памяти до перезагрузки. Выгружаем свои, чтобы после обновления
-- файлов (или повторного запуска) работала новая версия, а не старая из памяти.
for name in pairs(package.loaded) do
    if name:match("^core%.") or name:match("^hw%.") or name:match("^logic%.") or name:match("^ui%.") then
        package.loaded[name] = nil
    end
end

local args = {...}
local nogui, plain = false, false
for _, a in ipairs(args) do
    if a == "--nogui" then nogui = true end
    if a == "--plain" then nogui, plain = true, true end
end

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
    if plain then
        -- --plain: просто строки журнала в терминал (для логов и отладки)
        app.log:onEntry(function(e)
            io.write(string.format("[%7.1f] %-5s %s%s\n", e.time - app.state.startedAt, e.level:upper(), e.text,
                e.count > 1 and (" (x" .. e.count .. ")") or ""))
        end)
    else
        -- --nogui: текстовая панель (журнал слева, реакторы справа), без прокрутки
        local TUI = require("ui.textui")
        local tui = TUI.new(app, component.gpu)
        app.onFrame = function() tui:frame() end
        app.waitHint = function() return tui:timeUntilNext() end
        app.tui = tui
    end
    -- управление с клавиатуры
    app:on("key_down", function(_, _, char)
        local c = char and char > 0 and string.char(char):lower() or ""
        if c == "s" then app.actions:start(nil, "клавиатура")
        elseif c == "x" then app.actions:stop(nil, "клавиатура")
        elseif c == "m" then app.actions:refreshMe()
        elseif c == "q" then app:requestExit()
        elseif c:match("^[1-6]$") then app.actions:toggle(tonumber(c), "клавиатура") end
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
end
if buffer or app.tui then pcall(function() require("term").clear() end) end
if app.exitReason == "restart" then computer.shutdown(true) end
