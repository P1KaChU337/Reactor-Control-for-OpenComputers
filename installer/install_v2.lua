-- Reactor Control v2 — тестовый установщик (только стандартные библиотеки OpenOS).
-- Ставит программу в /home/reactorcontrol, библиотеки интерфейса — в /lib (как v1).
-- Старую версию (/home/main.lua) и её настройки (/home/data/config.lua) НЕ трогает:
-- при первом запуске v2 сама перенесёт настройки.
--
-- Установка:
--   wget -f https://raw.githubusercontent.com/P1KaChU337/Reactor-Control-for-OpenComputers/claude/keen-volta-rnypyl/installer/install_v2.lua /home/install_v2.lua
--   install_v2
-- Другая ветка: install_v2 --branch=main
local shell = require("shell")
local fs = require("filesystem")

local args, opts = shell.parse(...)
local BRANCH = type(opts.branch) == "string" and opts.branch or "claude/keen-volta-rnypyl"
local BASE = "https://raw.githubusercontent.com/P1KaChU337/Reactor-Control-for-OpenComputers/" .. BRANCH .. "/"
local DEST = "/home/reactorcontrol/"

-- Файлы программы (src/ -> /home/reactorcontrol/). Список проверяется тестом tests/test_installer.lua
local FILES = {
    "core/actions.lua",
    "core/app.lua",
    "core/config.lua",
    "core/fsutil.lua",
    "core/log.lua",
    "core/scheduler.lua",
    "core/serialize.lua",
    "core/state.lua",
    "hw/discovery.lua",
    "hw/flux.lua",
    "hw/me.lua",
    "hw/reactor.lua",
    "images/dark.pic",
    "images/light.pic",
    "logic/protection.lua",
    "logic/rate.lua",
    "main.lua",
    "ui/braille.lua",
    "ui/format.lua",
    "ui/gfx.lua",
    "ui/screens/info.lua",
    "ui/screens/main.lua",
    "ui/screens/settings.lua",
    "ui/sprites.lua",
    "ui/theme.lua",
    "ui/ui.lua",
}

-- Библиотеки интерфейса (MineOS legacy). event.lua не трогаем: на компьютере уже стоит нужный.
local LIBS = {
    {"lib/advancedLua.lua", "/lib/advancedLua.lua"},
    {"lib/color.lua", "/lib/color.lua"},
    {"lib/image.lua", "/lib/image.lua"},
    {"lib/doubleBuffering.lua", "/lib/doubleBuffering.lua"},
    {"lib/OCIF.lua", "/lib/FormatModules/OCIF.lua"},
}

local function download(url, path)
    local dir = fs.path(path)
    if dir and not fs.exists(dir) then fs.makeDirectory(dir) end
    local ok = shell.execute("wget -fq " .. url .. " " .. path)
    return ok and fs.exists(path) and fs.size(path) > 0
end

print("Reactor Control v2 — установка из ветки " .. BRANCH)
local total = #FILES + #LIBS
local n, failed = 0, {}
for _, f in ipairs(FILES) do
    n = n + 1
    io.write(string.format("[%2d/%d] %s ", n, total, f))
    if download(BASE .. "src/" .. f, DEST .. f) then print("ok") else print("ОШИБКА") failed[#failed + 1] = f end
end
for _, l in ipairs(LIBS) do
    n = n + 1
    io.write(string.format("[%2d/%d] %s ", n, total, l[2]))
    if download(BASE .. l[1], l[2]) then print("ok") else print("ОШИБКА") failed[#failed + 1] = l[1] end
end

if #failed > 0 then
    print("")
    print("Не скачались файлы (" .. #failed .. "). Проверьте интернет-карту и запустите установщик ещё раз.")
    return
end

print("")
print("Готово! Запуск:  /home/reactorcontrol/main.lua")
print("Без интерфейса (журнал в терминал):  /home/reactorcontrol/main.lua --nogui")
io.write("Запускать v2 автоматически при включении компьютера вместо старой версии? [y/N] ")
local answer = io.read()
if answer and answer:lower():match("^y") then
    local f = io.open("/home/.shrc", "w")
    if f then f:write("/home/reactorcontrol/main.lua\n") f:close() print("Автозапуск: /home/.shrc -> /home/reactorcontrol/main.lua") end
else
    print("Автозапуск не менялся.")
end
