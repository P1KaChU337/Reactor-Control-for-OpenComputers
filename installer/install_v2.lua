-- Reactor Control v2 — установщик и обновление (только стандартные библиотеки OpenOS).
-- Сам определяет, что делать:
--   * чистый компьютер           -> установка
--   * стоит v1 (/home/main.lua)  -> установка v2 рядом, настройки v1 переносятся при первом запуске
--   * стоит v2                   -> обновление, настройки и журнал (/home/reactorcontrol/data) не трогаются
-- Файлы пишутся атомарно: сначала во временный файл, потом замена. Обрыв связи не портит установленную версию.
--
--   rc_install            обычный запуск
--   rc_install --yes      без вопросов (для скриптов)
--   rc_install --branch=main
local component = require("component")
local computer = require("computer")
local event = require("event")
local fs = require("filesystem")
local shell = require("shell")
local unicode = require("unicode")

local args, opts = shell.parse(...)
local BRANCH = type(opts.branch) == "string" and opts.branch or "claude/keen-volta-rnypyl"
local REPO = "https://raw.githubusercontent.com/P1KaChU337/Reactor-Control-for-OpenComputers/"
local BASE = REPO .. BRANCH .. "/"
local DEST = "/home/reactorcontrol/"
local AUTOSTART_CMD = "/home/reactorcontrol/main.lua"

-- Файлы программы (src/ -> /home/reactorcontrol/). Список проверяется тестом tests/test_installer.lua
local FILES = {
    "commands/chat.lua",
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
    "net/http.lua",
    "net/remote.lua",
    "ui/braille.lua",
    "ui/format.lua",
    "ui/gfx.lua",
    "ui/screens/info.lua",
    "ui/screens/main.lua",
    "ui/screens/settings.lua",
    "ui/sprites.lua",
    "ui/textui.lua",
    "ui/theme.lua",
    "ui/ui.lua",
    "update.lua",
}
-- Библиотеки интерфейса (MineOS legacy) — в /lib, как в v1. /lib/event.lua не трогаем.
local LIBS = {
    {"lib/advancedLua.lua", "/lib/advancedLua.lua"},
    {"lib/color.lua", "/lib/color.lua"},
    {"lib/image.lua", "/lib/image.lua"},
    {"lib/doubleBuffering.lua", "/lib/doubleBuffering.lua"},
    {"lib/OCIF.lua", "/lib/FormatModules/OCIF.lua"},
}

-------------------------------------------------------------------------------
-- Экран

local gpu = component.gpu
local oldW, oldH = gpu.getResolution()
local maxW, maxH = gpu.maxResolution()
local W, H = math.min(maxW, 100), math.min(maxH, 32)
gpu.setResolution(W, H)
local depth = gpu.getDepth()

local C = {
    bg = 0x161616, panel = 0x262626, panel2 = 0x1e1e1e, text = 0xd8d8d8, dim = 0x8a8a8a,
    accent = 0xffb000, ok = 0x61ff52, warn = 0xfff700, err = 0xff4040, title = 0x72f8ff,
    bar = 0x2beb1a, barBg = 0x3a3a3a, btn = 0x059bff, btnText = 0xffffff, btnAlt = 0x4a4a4a,
}
if depth < 4 then for k in pairs(C) do C[k] = (k == "bg" or k == "panel" or k == "panel2" or k == "barBg" or k == "btnAlt") and 0x000000 or 0xffffff end end

local function fill(x, y, w, h, bg, ch) gpu.setBackground(bg) gpu.fill(x, y, w, h, ch or " ") end
local function text(x, y, s, fg, bg) if bg then gpu.setBackground(bg) end gpu.setForeground(fg) gpu.set(x, y, s) end
local function center(y, s, fg, bg, x, w)
    x, w = x or 1, w or W
    text(x + math.floor((w - unicode.len(s)) / 2), y, s, fg, bg)
end
local function fit(s, n) if unicode.len(s) > n then return unicode.sub(s, 1, n - 1) .. "…" end return s end

-- Панель: полублоки сверху/снизу дают аккуратные края
local PX, PY, PW, PH = 6, 3, W - 10, H - 4
local function panel()
    fill(1, 1, W, H, C.bg)
    fill(PX, PY + 1, PW, PH - 2, C.panel)
    gpu.setBackground(C.bg) gpu.setForeground(C.panel)
    gpu.set(PX, PY, string.rep("▄", PW))
    gpu.set(PX, PY + PH - 1, string.rep("▀", PW))
    -- заголовок
    center(PY + 1, "REACTOR CONTROL", C.accent, C.panel, PX, PW)
    center(PY + 2, "v2 · установка и обновление · by P1KaChU337", C.dim, C.panel, PX, PW)
    gpu.setForeground(0x3a3a3a)
    gpu.setBackground(C.panel)
    gpu.set(PX + 2, PY + 3, string.rep("─", PW - 4))
end

local buttons = {}
local function button(id, x, y, w, label, color, fg)
    fill(x, y, w, 1, color)
    gpu.setBackground(C.panel) gpu.setForeground(color)
    gpu.set(x, y - 1, string.rep("▄", w))
    gpu.set(x, y + 1, string.rep("▀", w))
    text(x + math.floor((w - unicode.len(label)) / 2), y, label, fg or C.btnText, color)
    buttons[#buttons + 1] = {id = id, x1 = x, y1 = y - 1, x2 = x + w - 1, y2 = y + 1}
end

-- Ждать нажатия на одну из кнопок (или клавиши: Enter — первая, Esc/Q — последняя)
local function waitButton(keys)
    while true do
        local ev = table.pack(event.pull())
        if ev[1] == "touch" then
            local x, y = ev[3], ev[4]
            for _, b in ipairs(buttons) do
                if x >= b.x1 and x <= b.x2 and y >= b.y1 and y <= b.y2 then return b.id end
            end
        elseif ev[1] == "key_down" then
            local ch, code = ev[3], ev[4]
            if keys and keys[code] then return keys[code] end
            if keys and ch and ch > 0 and keys[string.char(ch):lower()] then return keys[string.char(ch):lower()] end
        elseif ev[1] == "interrupted" then
            return "cancel"
        end
    end
end

-- Строки состояния (галочки)
local function statusLine(y, ok, label, value)
    local mark, color = "✓", C.ok
    if ok == false then mark, color = "✗", C.err elseif ok == nil then mark, color = "•", C.warn end
    text(PX + 4, y, mark, color, C.panel)
    text(PX + 6, y, label, C.text, C.panel)
    text(PX + 30, y, fit(value or "", PW - 34), ok == false and C.err or C.dim, C.panel)
end

-- Журнал внизу панели
local LOG_Y, LOG_H = PY + 15, PH - 21
local logLines = {}
local function log(s, color)
    logLines[#logLines + 1] = {s = s, c = color or C.dim}
    if #logLines > LOG_H then table.remove(logLines, 1) end
    fill(PX + 3, LOG_Y, PW - 6, LOG_H, C.panel2)
    for i, l in ipairs(logLines) do text(PX + 4, LOG_Y + i - 1, fit(l.s, PW - 8), l.c, C.panel2) end
end

local function progress(y, ratio, label)
    local bw = PW - 8
    local filled = math.floor(bw * ratio + 0.5)
    fill(PX + 4, y, bw, 1, C.barBg)
    if filled > 0 then fill(PX + 4, y, filled, 1, C.bar) end
    fill(PX + 4, y + 1, bw, 1, C.panel)
    text(PX + 4, y + 1, fit(label, bw - 6), C.text, C.panel)
    local pct = string.format("%3d%%", math.floor(ratio * 100))
    text(PX + 4 + bw - #pct, y + 1, pct, C.accent, C.panel)
end

local function restoreScreen()
    gpu.setResolution(oldW, oldH)
    gpu.setBackground(0x000000) gpu.setForeground(0xffffff)
    gpu.fill(1, 1, oldW, oldH, " ")
    pcall(function() require("term").setCursor(1, 1) end)
end

-------------------------------------------------------------------------------
-- Загрузка

local internetOk, internet = pcall(require, "internet")
if not internetOk then internet = nil end

local function fetch(url)
    if internet and component.isAvailable("internet") then
        local ok, res = pcall(function()
            local parts = {}
            for chunk in internet.request(url) do parts[#parts + 1] = chunk end
            return table.concat(parts)
        end)
        if ok and res and #res > 0 then return res end
        return nil, tostring(res)
    end
    -- запасной путь через wget
    local tmp = "/tmp/rc_dl.tmp"
    if fs.exists(tmp) then fs.remove(tmp) end
    shell.execute("wget -fq " .. url .. " " .. tmp)
    local f = io.open(tmp, "rb")
    if not f then return nil, "wget не скачал файл" end
    local d = f:read("*a") f:close() fs.remove(tmp)
    if not d or #d == 0 then return nil, "пустой ответ" end
    return d
end

local function writeAtomic(path, data)
    local dir = fs.path(path)
    if dir and not fs.exists(dir) then fs.makeDirectory(dir) end
    local tmp = path .. ".new"
    local f, err = io.open(tmp, "wb")
    if not f then return nil, err end
    f:write(data) f:close()
    if fs.exists(path) then fs.remove(path) end
    return fs.rename(tmp, path)
end

local function download(url, path)
    local lastErr
    for attempt = 1, 3 do
        local data, err = fetch(url)
        if data then
            -- GitHub на неверный путь отдаёт текст "404: Not Found"
            if data:sub(1, 4) == "404:" then return nil, "нет файла (404)" end
            local ok, werr = writeAtomic(path, data)
            if ok then return true, #data end
            return nil, "запись: " .. tostring(werr)
        end
        lastErr = err
        os.sleep(attempt)
    end
    return nil, lastErr
end

-------------------------------------------------------------------------------
-- Шаг 1: проверка компьютера

local function readShrc()
    local f = io.open("/home/.shrc", "r")
    if not f then return "" end
    local d = f:read("*a") or "" f:close()
    return d
end

local mode = fs.exists(DEST .. "main.lua") and "update" or "install"
local hasV1 = fs.exists("/home/main.lua") and fs.exists("/home/data/config.lua")
local shrc = readShrc()
local autostartNow = shrc:find(AUTOSTART_CMD, 1, true) ~= nil
local autostart = (mode == "install") and true or autostartNow

local function check()
    buttons = {}
    panel()
    center(PY + 5, mode == "update" and "Обновление Reactor Control v2" or "Установка Reactor Control v2", C.title, C.panel, PX, PW)
    local hasNet = component.isAvailable("internet")
    local mem = math.floor(computer.totalMemory() / 1024)
    statusLine(PY + 7, hasNet, "Интернет-карта", hasNet and "есть" or "нужна для загрузки файлов")
    statusLine(PY + 8, maxW >= 160 and maxH >= 50, "Видеокарта и монитор", maxW .. "x" .. maxH .. (maxW >= 160 and "" or " — нужен 3 уровень (160x50)"))
    statusLine(PY + 9, mem >= 1024 or nil, "Память", mem .. " КБ" .. (mem >= 1024 and "" or " — лучше больше"))
    if mode == "update" then
        statusLine(PY + 10, true, "Установлена v2", "обновление, настройки сохранятся")
    elseif hasV1 then
        statusLine(PY + 10, true, "Найдена v1", "останется на месте, настройки перенесутся")
    else
        statusLine(PY + 10, true, "Чистая установка", DEST)
    end
    statusLine(PY + 11, true, "Ветка", BRANCH)
    return hasNet
end

local function autostartLine()
    local y = PY + 13
    fill(PX + 4, y, PW - 8, 1, C.panel)
    text(PX + 4, y, autostart and "[x]" or "[ ]", autostart and C.ok or C.dim, C.panel)
    text(PX + 8, y, "Запускать при включении компьютера", C.text, C.panel)
    text(PX + 44, y, "(пробел — переключить)", C.dim, C.panel)
    buttons[#buttons + 1] = {id = "autostart", x1 = PX + 4, y1 = y, x2 = PX + 66, y2 = y}
end

-------------------------------------------------------------------------------

local function main()
    local hasNet = check()
    local by = PY + PH - 3
    if not hasNet then
        log("Вставьте интернет-карту в компьютер и запустите установщик снова.", C.err)
        button("exit", PX + math.floor(PW / 2) - 8, by, 16, "Выход", C.btnAlt)
        waitButton({[28] = "exit", q = "exit"})
        return
    end
    autostartLine()
    log("Файлов к загрузке: " .. (#FILES + #LIBS), C.dim)
    if mode == "update" then log("Папка data/ (настройки и журнал) не изменяется.", C.dim) end
    local main = mode == "update" and "Обновить" or "Установить"
    button("go", PX + math.floor(PW / 2) - 20, by, 18, main, C.btn)
    button("cancel", PX + math.floor(PW / 2) + 2, by, 18, "Отмена", C.btnAlt)
    if not opts.yes then
        while true do
            local id = waitButton({[28] = "go", q = "cancel", [1] = "cancel", [57] = "autostart"})
            if id == "autostart" then autostart = not autostart autostartLine()
            elseif id == "cancel" then return
            elseif id == "go" then break end
        end
    end

    -- Шаг 2: загрузка
    buttons = {}
    fill(PX + 1, PY + 13, PW - 2, 1, C.panel)
    fill(PX + 1, by - 1, PW - 2, 3, C.panel)
    local list = {}
    for _, f in ipairs(FILES) do list[#list + 1] = {BASE .. "src/" .. f, DEST .. f, f} end
    for _, l in ipairs(LIBS) do list[#list + 1] = {BASE .. l[1], l[2], l[2]} end
    local failed, bytes = {}, 0
    local t0 = computer.uptime()
    for i, item in ipairs(list) do
        progress(PY + 13, (i - 1) / #list, "Загрузка: " .. item[3])
        local ok, res = download(item[1], item[2])
        if ok then
            bytes = bytes + res
            log("✓ " .. item[3], C.ok)
        else
            failed[#failed + 1] = item[3]
            log("✗ " .. item[3] .. ": " .. tostring(res), C.err)
        end
    end
    progress(PY + 13, 1, string.format("Загружено %d КБ за %.0f с", math.floor(bytes / 1024), computer.uptime() - t0))

    if #failed > 0 then
        log("Не загрузилось файлов: " .. #failed .. ". Уже установленная версия не пострадала.", C.err)
        log("Проверьте интернет и запустите установщик ещё раз.", C.warn)
        button("exit", PX + math.floor(PW / 2) - 8, by, 16, "Выход", C.btnAlt)
        waitButton({[28] = "exit", q = "exit"})
        return
    end

    -- Шаг 3: автозапуск
    shrc = readShrc()
    local cleaned = {}
    for line in (shrc .. "\n"):gmatch("([^\n]*)\n") do
        local isOld = line:match("^%s*main%.lua%s*$") or line:match("^%s*/home/main%.lua%s*$") or line:find(AUTOSTART_CMD, 1, true)
        if not isOld and line:match("%S") then cleaned[#cleaned + 1] = line end
    end
    if autostart then cleaned[#cleaned + 1] = AUTOSTART_CMD end
    if autostart ~= autostartNow or (autostart and shrc:match("main%.lua") and not autostartNow) then
        local f = io.open("/home/.shrc", "w")
        if f then f:write(table.concat(cleaned, "\n") .. (#cleaned > 0 and "\n" or "")) f:close() end
        log(autostart and "Автозапуск: включён (вместо старой версии)" or "Автозапуск: выключен", C.title)
    end

    log(mode == "update" and "Обновление завершено!" or "Установка завершена!", C.ok)
    button("run", PX + math.floor(PW / 2) - 29, by, 18, "Запустить", C.btn)
    button("reboot", PX + math.floor(PW / 2) - 9, by, 18, "Перезагрузить", C.btnAlt)
    button("exit", PX + math.floor(PW / 2) + 11, by, 18, "Выход", C.btnAlt)
    if opts.yes then return "exit" end
    return waitButton({[28] = "run", q = "exit", [1] = "exit"})
end

local ok, res = pcall(main)
restoreScreen()
if not ok then
    io.stderr:write("Установщик упал: " .. tostring(res) .. "\n")
elseif res == "run" then
    shell.execute(AUTOSTART_CMD)
elseif res == "reboot" then
    computer.shutdown(true)
end
