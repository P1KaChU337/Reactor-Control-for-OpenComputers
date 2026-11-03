-- Текстовый режим (main.lua --nogui): без doubleBuffering и картинок, только GPU.
-- Слева журнал, справа сводка по реакторам и комплексу. Экран не прокручивается:
-- каждая строка рисуется на своём месте и перерисовывается, только если изменилась.
local unicode = require("unicode")
local fmt = require("ui.format")
local protection = require("logic.protection")

local TUI = {}
TUI.__index = TUI

local C = {
    bg = 0x000000, text = 0xcccccc, dim = 0x777777, title = 0x72f8ff, ok = 0x61ff52,
    warn = 0xfff700, error = 0xff4040, accent = 0xffb000, sep = 0x444444, run = 0x61ff52, stop = 0xfd3232,
}
local LEVEL = {debug = C.dim, info = C.text, warn = C.warn, error = C.error}
local NAMED = {ok = C.ok, title = C.title}

function TUI.new(app, gpu)
    local self = setmetatable({app = app, gpu = gpu, cache = {}, lastFrame = -math.huge, drawnVersion = -1}, TUI)
    self.W, self.H = gpu.getResolution()
    self.split = math.floor(self.W * 0.45)
    gpu.setBackground(C.bg)
    gpu.fill(1, 1, self.W, self.H, " ")
    return self
end

local function fit(s, n)
    if unicode.len(s) > n then return unicode.sub(s, 1, n - 1) .. "…" end
    return s .. string.rep(" ", n - unicode.len(s))
end

-- Строка = список {текст, цвет}. Рисуется, только если отличается от прошлого кадра.
function TUI:row(x, y, w, segments)
    local key = {}
    for _, s in ipairs(segments) do key[#key + 1] = s[2] .. ":" .. s[1] end
    local k = table.concat(key, "|")
    local ck = x .. ":" .. y
    if self.cache[ck] == k then return end
    self.cache[ck] = k
    local gpu = self.gpu
    gpu.setBackground(C.bg)
    local cx, left = x, w
    for _, s in ipairs(segments) do
        if left <= 0 then break end
        local t = s[1]
        if unicode.len(t) > left then t = unicode.sub(t, 1, left) end
        gpu.setForeground(s[2])
        gpu.set(cx, y, t)
        cx = cx + unicode.len(t)
        left = left - unicode.len(t)
    end
    if left > 0 then gpu.set(cx, y, string.rep(" ", left)) end
end

local function wrap(text, width)
    local lines = {}
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

function TUI:drawLog(x, y, w, h)
    local log = self.app.log
    local lines = {}
    for i = #log.entries, 1, -1 do
        local e = log.entries[i]
        if e.level ~= "debug" or self.app.cfg.debugLog then
            local t = e.text .. (e.count > 1 and (" (x" .. e.count .. ")") or "")
            local color = (type(e.color) == "string" and NAMED[e.color]) or LEVEL[e.level] or C.text
            local wrapped = wrap(t, w)
            for j = #wrapped, 1, -1 do table.insert(lines, 1, {wrapped[j], color}) end
            if #lines >= h then break end
        end
    end
    while #lines > h do table.remove(lines, 1) end
    for i = 1, h do
        local l = lines[i]
        self:row(x, y + i - 1, w, l and {{l[1], l[2]}} or {})
    end
end

local function reactorLines(app, r, now)
    local cfg = app.cfg
    local lines = {}
    local kind = r.kind == "fluid" and "жидк." or r.kind == "air" and "возд." or "?"
    local status, sc
    if not r.online then status, sc = "НЕТ СВЯЗИ", C.error
    elseif protection.hasFaults(r) then
        local _, text = protection.firstFault(r)
        status, sc = "АВАРИЯ: " .. text, C.error
    elseif r.running then status, sc = "РАБОТАЕТ", C.run
    else status, sc = "остановлен", C.dim end
    lines[1] = {{string.format("#%d ", r.slot), C.accent}, {kind .. "  ", C.dim}, {status, sc}}
    if not r.online then return lines end
    local val, unit = fmt.si(r.running and r.rf or 0, cfg.metric)
    lines[2] = {{"   Ген: ", C.dim}, {val .. " " .. unit .. "RF/t", C.text},
        {"   Нагрев: ", C.dim}, {(r.temp and (r.temp .. "°C") or "-"), C.text}}
    if r.kind == "fluid" then
        local secs = protection.bufferSeconds(r, cfg)
        local drain, measured = protection.drainRate(r, cfg)
        local bc = (secs and secs < cfg.bufferStopSec) and C.warn or C.text
        lines[3] = {{"   Буфер: ", C.dim}, {fmt.percent(r.coolant, r.coolantMax) .. (secs and string.format(" (%.1f с)", secs) or ""), bc},
            {"   Расход: ", C.dim}, {(r.running and drain) and ((measured and "" or "~") .. fmt.compact(drain) .. " mB/s") or "0 mB/s", C.text}}
    end
    local rods = r.rods
    if rods and rods.count > 0 then
        local maxFuel = rods.maxFuel or 10000
        local first, last = r.burn:remaining(now, r.running, r.stoppedAt)
        lines[#lines + 1] = {{"   Топливо: ", C.dim},
            {string.format("%d шт, %d-%d%%", rods.count, math.floor(rods.min / maxFuel * 100), math.floor(rods.max / maxFuel * 100)), C.text},
            {"   Распад: ", C.dim}, {first and (fmt.hms(first) .. " / " .. fmt.hms(last)) or (r.running and "замер..." or "--:--:--"), C.text}}
    else
        lines[#lines + 1] = {{"   Топливо: ", C.dim}, {"нет стержней", C.text}}
    end
    if (r.manualTries or 0) > 0 and not r.faults.locked then
        lines[#lines + 1] = {{"   Ручных запусков при пустом буфере: ", C.dim}, {r.manualTries .. "/" .. cfg.maxManualStarts, C.warn}}
    end
    return lines
end

function TUI:drawStatus(x, y, w, h)
    local app, st = self.app, self.app.state
    local now = app.clock()
    local out = {}
    local function add(segs) out[#out + 1] = segs end
    add({{"КОМПЛЕКС", C.title}})
    local me = st.me
    local meText = not me.present and "не подключена"
        or (me.amount and (fmt.compact(me.amount) .. " mB") or "нет данных")
    local task = app.scheduler.tasks.me
    local left = (me.present and task) and math.max(0, math.ceil(task.due - now)) or 0
    add({{" МЭ: ", C.dim}, {meText, me.present and C.text or C.error},
        {"  порог ", C.dim}, {fmt.compact(app.cfg.threshold) .. " mB", C.text}, {"  обн. через " .. left .. " с", C.dim}})
    if st.flux.present then
        add({{" Flux: ", C.dim}, {"вход " .. fmt.compact(st.flux.input or 0) .. " / выход " .. fmt.compact(st.flux.output or 0) .. " RF/t", C.text}})
    end
    local val, unit = fmt.si(st:totalRf(), app.cfg.metric)
    add({{" Генерация: ", C.dim}, {val .. " " .. unit .. "RF/t", C.text},
        {"   Расход: ", C.dim}, {fmt.compact((st:totalDrain())) .. " mB/s", C.text}})
    local up = math.floor(st:uptime())
    add({{" Работает: ", C.dim}, {string.format("%02d:%02d:%02d", math.floor(up / 3600), math.floor(up % 3600 / 60), up % 60), C.text},
        {"   Реакторов: ", C.dim}, {tostring(st:count()), C.text}})
    add({})
    add({{"РЕАКТОРЫ", C.title}})
    for _, r in ipairs(st:list()) do
        for _, l in ipairs(reactorLines(app, r, now)) do add(l) end
        add({})
    end
    for i = 1, h do self:row(x, y + i - 1, w, out[i] or {}) end
end

function TUI:frame(force)
    local now = self.app.clock()
    if not force and self.app.state.version == self.drawnVersion and now - self.lastFrame < 1 then return end
    if not force and now - self.lastFrame < 0.25 then return end
    self.lastFrame, self.drawnVersion = now, self.app.state.version
    local W, H, sx = self.W, self.H, self.split
    self:row(1, 1, W, {{"Reactor Control v" .. self.app.VERSION_SHORT, C.accent}, {"  —  текстовый режим", C.dim}})
    self:row(1, 2, W, {{string.rep("─", sx - 1), C.sep}, {"┬", C.sep}, {string.rep("─", W - sx), C.sep}})
    for y = 3, H - 2 do self:row(sx, y, 1, {{"│", C.sep}}) end
    self:drawLog(1, 3, sx - 2, H - 4)
    self:drawStatus(sx + 2, 3, W - sx - 1, H - 4)
    self:row(1, H - 1, W, {{string.rep("─", sx - 1), C.sep}, {"┴", C.sep}, {string.rep("─", W - sx), C.sep}})
    self:row(1, H, W, {{"s", C.accent}, {" запустить все  ", C.dim}, {"x", C.accent}, {" остановить все  ", C.dim},
        {"1-6", C.accent}, {" вкл/выкл реактор  ", C.dim}, {"m", C.accent}, {" обновить МЭ  ", C.dim}, {"q", C.accent}, {" выход", C.dim}})
end

function TUI:timeUntilNext() return math.max(0, self.lastFrame + 1 - self.app.clock()) end

return TUI
