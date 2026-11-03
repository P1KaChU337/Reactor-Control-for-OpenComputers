-- Главный экран. Раскладка и цвета повторяют v1.1.3; виджетов 6 (лимит сервера), поэтому они крупнее.
local G = require("ui.gfx")
local S = require("ui.sprites")
local T = require("ui.theme")
local fmt = require("ui.format")
local protection = require("logic.protection")

local M = {}

-- Сетка виджетов внутри серого поля 5..118 x 5..41
M.WIDGET_W, M.WIDGET_H = 34, 16
M.WIDGETS = {{8, 7}, {45, 7}, {82, 7}, {8, 24}, {45, 24}, {82, 24}}
M.CONSOLE_W = 34

local function metricLabel(cfg) return fmt.METRIC_LABEL[cfg.metric] or "Auto" end

-------------------------------------------------------------------------------
-- Виджет реактора

local function widgetStatus(r)
    if not r.online then return "offline" end
    if protection.hasFaults(r) then return "fault" end
    if r.running then return "run" end
    return "stop"
end

local function drawWidget(ui, slot, r)
    local th, app = ui:theme(), ui.app
    local cfg = app.cfg
    local now = app.clock()
    local x, y = M.WIDGETS[slot][1], M.WIDGETS[slot][2]
    local W, H = M.WIDGET_W, M.WIDGET_H
    local status = widgetStatus(r)
    local faulted = status == "fault" or status == "offline"
    local boxColor = faulted and th.warn or th.bg
    local tc = faulted and th.error or th.text
    G.box(x, y, W, H, boxColor)

    local fluid = r.kind == "fluid"
    local tx = x + 4
    G.center(x + 3, W - 4, tc, "Реактор #" .. slot, y + 1)

    if fluid then
        G.vbar(x + 1, y + 1, H - 2, r.coolant, r.coolantMax, T.coolantBottom, T.coolantTop, th.bg2)
    end

    if status == "offline" then
        G.text(tx, y + 4, tc, "Нет связи с реактором!")
        G.text(tx, y + 6, tc, "Проверьте адаптер и")
        G.text(tx, y + 7, tc, "загрузку чанка.")
        G.text(tx, y + 9, tc, "Пока связи нет, реактор")
        G.text(tx, y + 10, tc, "программа не контролирует.")
        local bw = 14
        ui:button("forget" .. slot, x + math.floor((W - bw) / 2), y + H - 4, bw, "Забыть", 0x666666, 0xffffff, function()
            local f = require("ui.screens.forget")
            f.slot = slot
            ui:openModal(f)
        end)
        return
    end

    local line = y + 3
    local function row(text, color) G.text(tx, line, color or tc, G.fit(text, W - 5)) line = line + 1 end

    row("Нагрев: " .. (r.temp and (r.temp .. "°C") or "-"))
    local val, unit = fmt.si(r.running and r.rf or 0, cfg.metric)
    row("Ген: " .. val .. " " .. unit .. "RF/t")
    row("Тип: " .. (r.kind == "fluid" and "Жидкостный" or r.kind == "air" and "Воздушный" or "-"))
    if status == "fault" then
        local _, text = protection.firstFault(r)
        row("Авария: " .. tostring(text), th.error)
    elseif status == "run" then
        row("Статус: Работает")
    else
        row("Статус: Остановлен")
    end

    if fluid then
        local secs = protection.bufferSeconds(r, cfg)
        row("Буфер: " .. fmt.percent(r.coolant, r.coolantMax) .. (secs and string.format(" (%.1f с)", secs) or ""))
        local drain, measured = protection.drainRate(r, cfg)
        if r.running and drain then
            row("Расход: " .. (measured and "" or "~") .. fmt.compact(drain) .. " mB/s")
        else
            row("Расход: 0 mB/s")
        end
    end

    local rods = r.rods
    if rods and rods.count > 0 then
        local maxFuel = rods.maxFuel or 10000
        row(string.format("Топливо: %d шт, %d-%d%%", rods.count,
            math.floor(rods.min / maxFuel * 100), math.floor(rods.max / maxFuel * 100)))
        local first, last = r.burn:remaining(now, r.running, r.stoppedAt)
        if first then
            row("Распад: " .. fmt.hms(first) .. " / " .. fmt.hms(last))
        else
            row("Распад: " .. (r.running and "замер..." or "--:--:--"))
        end
    else
        row("Топливо: нет стержней")
    end

    -- кнопка
    local label, color, onClick
    if r.faults.locked then
        label, color = "Заблокирован", 0x666666
        onClick = function() app.actions:start(slot, "кнопка") end   -- напишет в журнал, что делать
    elseif r.running then
        label, color = "Отключить", T.red
        onClick = function() app.actions:stop(slot, "кнопка") end
    elseif r.desired and r.halted and not r.faults.buffer_low and not r.faults.unstable then
        label, color = "Отменить", T.red      -- ждёт автозапуска: можно отказаться
        onClick = function() app.actions:stop(slot, "кнопка") end
    else
        label, color = "Включить", T.green
        onClick = function() app.actions:start(slot, "кнопка") end
    end
    local bw = 14
    ui:button("reactor" .. slot, x + math.floor((W - bw) / 2), y + H - 4, bw, label, color, th.textBtn, onClick)
end

local function drawWidgets(ui)
    local th, state = ui:theme(), ui.app.state
    G.rect(5, 5, 114, 37, th.bg4)
    if state:count() == 0 then
        G.rect(37, 19, 50, 3, th.bg2)
        G.box(36, 19, 52, 3, th.bg2)
        G.text(40, 20, 0xffd900, "⚠")
        G.text(43, 20, 0xcccccc, "Не подключено ни одного реактора!")
        return
    end
    for slot = 1, 6 do
        local r = state.reactors[slot]
        if r then drawWidget(ui, slot, r) end
    end
end

-------------------------------------------------------------------------------
-- Правая колонка: заголовок панели как в v1.1.3 (линия сверху, заголовок, линия снизу)

local function panel(th, y1, h, title, lineTop, lineBottom)
    G.rect(123, y1, 35, h, th.bg)
    if lineTop then G.hline(123, lineTop, 35, S.console[1], th.bg) end
    if lineBottom then G.hline(123, lineBottom, 35, S.console[2], th.bg2) end
    if title then G.text(124, y1, th.text, title) end
end

local LEVEL_COLOR = {debug = "version", info = "text", warn = "warn", error = "error"}

local function wrap(text, width)
    local lines = {}
    local unicode = require("unicode")
    while unicode.len(text) > width do
        local chunk = unicode.sub(text, 1, width)
        local cut = chunk:match(".*()%s")
        if cut and cut > 1 then
            lines[#lines + 1] = chunk:sub(1, cut - 1)
            text = text:sub(cut + 1)
        else
            lines[#lines + 1] = chunk
            text = unicode.sub(text, width + 1)
        end
    end
    if #text > 0 then lines[#lines + 1] = text end
    return lines
end

local function drawConsole(ui, flux)
    local th, log = ui:theme(), ui.app.log
    G.rect(123, 3, 35, flux and 22 or 24, th.bg)
    G.hline(123, 2, 35, S.console[1], th.bg)
    G.hline(123, 4, 35, S.console[2], th.bg2)
    G.text(124, 3, th.text, "Информационное окно отладки:")
    local height = flux and 19 or 22
    local top = 4
    local lines = {}
    for i = #log.entries, 1, -1 do
        local e = log.entries[i]
        if e.level ~= "debug" or ui.app.cfg.debugLog then
            local text = e.text .. (e.count > 1 and ("(x" .. e.count .. ")") or "")
            local wrapped = wrap(text, M.CONSOLE_W)
            local color = type(e.color) == "string" and th[e.color] or e.color or th[LEVEL_COLOR[e.level] or "text"]
            for j = #wrapped, 1, -1 do
                table.insert(lines, 1, {text = wrapped[j], color = color})
            end
            if #lines >= height then break end
        end
    end
    while #lines > height do table.remove(lines, 1) end
    -- старые строки тускнеют, как в v1.1.3
    for i, l in ipairs(lines) do
        local fade = (#lines - i) / math.max(height, 1) * 0.45
        G.text(124, top + i, G.lerp(l.color, th.bg, fade), l.text)
    end
end

local function drawFluid(ui, flux)
    local th, app = ui:theme(), ui.app
    local y = flux and 27 or 30
    panel(th, y - 1, 4, "Жидкости в МЭ сети:", y - 2, y)
    G.icon(125, y + 1, S.iconFluid, 0x0088ff)
    local me = app.state.me
    if not me.present then
        G.text(132, y + 1, th.error, "МЭ не подключена")
        return
    end
    local val, unit = fmt.si(me.amount or 0, app.cfg.metric)
    G.number(143, y + 1, me.amount and val or "-", th.text, unit .. "Mb", th.text)
end

local function thresholdStep(v)
    local step = 1000
    while v >= step * 100 do step = step * 10 end
    return step
end

local function drawThreshold(ui, flux)
    local th, app = ui:theme(), ui.app
    local y = flux and 32 or 35
    panel(th, y - 1, 4, "Настройка порога жидкости:", y - 2, y)
    local plus = ui:isPressed("thrPlus") and 0x5f9300 or 0xa6ff00
    local minus = ui:isPressed("thrMinus") and 0x9d0000 or 0xff2121
    G.icon(124, y + 1, S.iconPlus, plus)
    G.icon(126, y + 1, S.iconMinus, minus)
    ui:hit(124, y + 1, 125, y + 2, function()
        app.actions:setThreshold(app.cfg.threshold + thresholdStep(app.cfg.threshold))
    end, "thrPlus")
    ui:hit(126, y + 1, 127, y + 2, function()
        local v = app.cfg.threshold
        app.actions:setThreshold(math.max(0, v - thresholdStep(math.max(v - 1, 0))))
    end, "thrMinus")
    local val, unit = fmt.si(app.cfg.threshold, app.cfg.metric)
    G.number(144, y + 1, val, th.text, unit .. "Mb", th.text)
end

local function drawFlux(ui)
    local th, f = ui:theme(), ui.app.state.flux
    local y = 36
    panel(th, y, 4, "Общий вход/выход в Flux сети:", y - 1, y + 1)
    G.text(142, y + 1, th.bg2, S.divider[7])
    G.text(142, y + 2, th.bg2, S.divider[1])
    G.text(142, y + 3, th.bg2, S.divider[1])
    G.icon(125, y + 2, S.iconBolt, 0xff2200)
    local function num(v)
        local s = fmt.compact(v or 0)
        return (s:gsub("%a", "")), (s:match("%a") or "")
    end
    local iv, iu = num(f.input)
    local ov, ou = num(f.output)
    G.number(136, y + 2, iv, th.text, iu .. "RF/t", th.text)
    G.number(152, y + 2, ov, th.text, ou .. "RF/t", th.text)
end

local function drawGeneration(ui, flux)
    local th, app = ui:theme(), ui.app
    local y = flux and 41 or 40
    panel(th, y, 4, "Генерация всех реакторов:", y - 1, y + 1)
    G.icon(125, y + 2, S.iconBolt, 0xffc400)
    local val, unit = fmt.si(app.state:totalRf(), app.cfg.metric)
    G.number(144, y + 2, val, th.text, unit .. "Rf/t", th.text)
end

local function drawTime(ui, flux)
    local th, app = ui:theme(), ui.app
    local y = flux and 46 or 45
    panel(th, y, 4, nil, y - 1, y + 1)
    G.text(124, y, th.text, "МЭ: Обн. ч/з..")
    G.text(141, y, th.text, "Время работы:")
    G.text(139, y, th.bg2, S.divider[1])
    G.text(139, y + 1, th.bg2, S.divider[2])
    G.text(139, y + 2, th.bg2, S.divider[1])
    G.text(139, y + 3, th.bg2, S.divider[1])
    G.icon(125, y + 2, S.iconTime, 0xaa4b2e)
    local now = app.clock()
    local task = app.scheduler.tasks.me
    local left = 0
    if app.state.me.present and task then left = math.max(0, math.ceil(task.due - now)) end
    G.number(134, y + 2, left, th.text, "Sec", th.text)
    local up = math.floor(app.state:uptime())
    local h, m, s = math.floor(up / 3600), math.floor(up % 3600 / 60), up % 60
    if h > 0 then
        G.number(146, y + 2, h, th.text, "Hrs", th.text)
        G.number(154, y + 2, m, th.text, "Min", th.text)
    else
        G.number(146, y + 2, m, th.text, "Min", th.text)
        G.number(154, y + 2, s, th.text, "Sec", th.text)
    end
end

-------------------------------------------------------------------------------
-- Низ: кнопки и статус комплекса

local function drawStatus(ui)
    local th, state = ui:theme(), ui.app.state
    G.rect(89, 44, 31, 6, th.bg)
    G.hline(89, 43, 31, S.console[1], th.bg)
    G.hline(89, 45, 31, S.console[2], th.bg2)
    G.text(90, 44, th.text, "Статус комплекса:")
    G.text(110, 45, th.bg2, S.divider[5])
    for yy = 46, 49 do G.text(110, yy, th.bg2, S.divider[6]) end
    G.text(90, 46, th.text, "Кол-во реакторов: " .. state:count())
    G.text(90, 47, th.text, "Общий расход")
    local total = state:totalDrain()
    G.text(90, 48, th.text, "жидкости: " .. fmt.compact(total) .. " mB/s")
    local on = state:anyRunning()
    local c = on and 0x61ff52 or 0xfd3232
    G.box(112, 46, 6, 3, c)
    G.text(113, 47, on and 0x0d9f00 or 0x9d0000, on and "Work" or "Stop")
end

local function drawButtons(ui)
    local th, app = ui:theme(), ui.app
    ui:button("settings", 5, 44, 4, "🔧", T.purple, 0xffffff, function() ui:openModal(require("ui.screens.settings")) end)
    ui:button("info", 5, 47, 4, "ⓘ", T.purple, 0x05e2ff, function() ui:openModal(require("ui.screens.info")) end)
    ui:button("stopAll", 13, 44, 24, "Отключить реакторы!", T.red, th.textBtn, function() app.actions:stop(nil, "кнопка") end)
    ui:button("startAll", 41, 44, 23, "Запуск реакторов!", T.greenBig, th.textBtn, function() app.actions:start(nil, "кнопка") end)
    ui:button("refreshMe", 68, 44, 18, "Пр.Обновить МЭ", th.btn, th.textBtn, function() app.actions:refreshMe() end)
    ui:button("restart", 13, 47, 24, "Рестарт программы.", th.btn, th.textBtn, function() app:requestRestart() end)
    ui:button("exit", 41, 47, 23, "Выход из программы.", th.btn, th.textBtn, function() app:requestExit() end)
    ui:button("metric", 68, 47, 18, "Метрика: " .. metricLabel(app.cfg), th.btn, th.textBtn, function()
        local order, cur = fmt.METRIC_ORDER, 1
        for i, m in ipairs(order) do if m == app.cfg.metric then cur = i end end
        app.cfg.metric = order[cur % #order + 1]
        app.saveConfig()
        app.state:touch()
    end)
end

function M.draw(ui)
    local th, app = ui:theme(), ui.app
    local bg = ui:background()
    if bg then ui.buffer.drawImage(1, 1, bg) else G.rect(1, 1, 160, 50, th.bg3) end
    local flux = app.state.flux.present
    drawWidgets(ui)
    drawConsole(ui, flux)
    drawFluid(ui, flux)
    drawThreshold(ui, flux)
    if flux then drawFlux(ui) end
    drawGeneration(ui, flux)
    drawTime(ui, flux)
    drawStatus(ui)
    drawButtons(ui)
    local ver = "Reactor Control v" .. app.VERSION_SHORT .. " by P1KaChU337"
    G.text(161 - G.wlen(ver), 50, th.version, ver)
end

return M
