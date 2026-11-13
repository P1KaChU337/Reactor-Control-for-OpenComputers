-- Минимальный headless-эмулятор OpenComputers для разработки и тестов.
-- Запуск: lua5.3 tools/emu/emu.lua <scenario.lua>
-- Время виртуальное: os.sleep / event.pull двигают часы, а не ждут реально.

local EMU_DIR = arg[0]:match("^(.*)/[^/]*$") or "."
local REPO = EMU_DIR .. "/../.."

local rawExecute = os.execute
local rawStderr = io.stderr
local emu = {
    time = 0,
    queue = {},       -- {t, name, ...}
    screen = nil,
    log = {},
    endTime = math.huge,
    root = os.getenv("EMU_ROOT") or "/tmp/rc_emu_root",
    actions = {},     -- {t, fn}
}
_G.__EMU__ = emu

local function trace(...) rawStderr:write("[emu " .. string.format("%7.2f", emu.time) .. "] " .. table.concat({...}, " ") .. "\n") end
emu.trace = trace

---------------------------------------------------------------------------
-- bit32 (в Lua 5.3 его нет, а OC даёт)
---------------------------------------------------------------------------
_G.bit32 = load([[
local b = {}
local M = 0xFFFFFFFF
function b.band(...) local r = M for _, v in ipairs({...}) do r = r & v end return r & M end
function b.bor(...) local r = 0 for _, v in ipairs({...}) do r = r | v end return r & M end
function b.bxor(...) local r = 0 for _, v in ipairs({...}) do r = r ~ v end return r & M end
function b.bnot(x) return (~x) & M end
function b.lshift(x, n) if n >= 32 then return 0 end return (x << n) & M end
function b.rshift(x, n) if n >= 32 then return 0 end return (x & M) >> n end
function b.arshift(x, n) x = x & M if x & 0x80000000 ~= 0 then return ((x >> n) | ~(M >> n)) & M end return x >> n end
function b.extract(x, f, w) w = w or 1 return (x >> f) & ((1 << w) - 1) end
function b.replace(x, v, f, w) w = w or 1 local m = ((1 << w) - 1) << f return (x & ~m | ((v << f) & m)) & M end
function b.btest(...) return b.band(...) ~= 0 end
return b]])()

---------------------------------------------------------------------------
-- Песочница ФС: все абсолютные пути уходят в emu.root
---------------------------------------------------------------------------
rawExecute("mkdir -p " .. emu.root .. "/home " .. emu.root .. "/tmp")
local function realPath(p)
    p = tostring(p)
    if p:sub(1, 1) ~= "/" then p = "/home/" .. p end
    return emu.root .. p
end
emu.realPath = realPath
local rawOpen = io.open
io.open = function(p, m) return rawOpen(realPath(p), m) end
local rawDofile = dofile
dofile = function(p) return rawDofile(realPath(p)) end
local rawLoadfile = loadfile
loadfile = function(p, ...) return rawLoadfile(realPath(p), ...) end

---------------------------------------------------------------------------
-- Модули OpenOS
---------------------------------------------------------------------------
local preload = package.preload

local computer = {}
function computer.uptime() return emu.time end
-- Пользователи компьютера как в OC: addUser работает только для игрока в сети (emu.online; nil — все в сети),
-- users() возвращает имена несколькими значениями
emu.users = {}
emu.online = nil
function computer.addUser(n)
    if emu.online and not emu.online[n] then trace("addUser", n, "offline") return nil, "player must be online" end
    for _, u in ipairs(emu.users) do if u == n then return true end end
    emu.users[#emu.users + 1] = n
    trace("addUser", n)
    return true
end
function computer.removeUser(n)
    for i, u in ipairs(emu.users) do if u == n then table.remove(emu.users, i) trace("removeUser", n) return true end end
    return false
end
function computer.users() return table.unpack(emu.users) end
function computer.getArchitecture() return "Lua 5.3" end
function computer.totalMemory() return 4 * 1024 * 1024 end
function computer.freeMemory() return 2 * 1024 * 1024 end
function computer.beep() end
function computer.shutdown(r) error("EMU_SHUTDOWN", 0) end
function computer.pullSignal(t) return require("event").pull(t) end
function computer.pushSignal(...) table.insert(emu.queue, {emu.time, ...}) end
preload.computer = function() return computer end

-- unicode через utf8
local unicode = {}
function unicode.char(...) return utf8.char(...) end
function unicode.len(s) return utf8.len(s) or #s end
function unicode.sub(s, i, j)
    local len = unicode.len(s)
    i = i or 1; j = j or -1
    if i < 0 then i = len + i + 1 end
    if j < 0 then j = len + j + 1 end
    if i < 1 then i = 1 end
    if j > len then j = len end
    if i > j then return "" end
    local bi = utf8.offset(s, i)
    local bj = utf8.offset(s, j + 1)
    return s:sub(bi, (bj or #s + 1) - 1)
end
function unicode.upper(s) return s:upper() end
function unicode.lower(s) return s:lower() end
-- Ширина символов берётся из настоящего шрифта OC (font.hex): 32 hex = 8x16 (1 ячейка), 64 hex = 16x16 (2 ячейки)
local FONT_URL = "https://raw.githubusercontent.com/MightyPirates/OpenComputers/master-MC1.12/src/main/resources/assets/opencomputers/font.hex"
local fontPath = EMU_DIR .. "/.cache/font.hex"
local wide = {}
do
    local f = rawOpen(fontPath, "r")
    if not f then
        rawExecute("mkdir -p '" .. EMU_DIR .. "/.cache' && curl -sSfL -o '" .. fontPath .. "' " .. FONT_URL)
        f = rawOpen(fontPath, "r")
    end
    if f then
        for line in f:lines() do
            local cp, bits = line:match("^(%x+):(%x+)")
            if cp and #bits == 64 then wide[tonumber(cp, 16)] = true end
        end
        f:close()
    else
        rawStderr:write("[emu] WARNING: font.hex не найден, ширина всех символов = 1\n")
    end
end
emu.wide = wide
local function cpWidth(cp) return wide[cp] and 2 or 1 end
function unicode.isWide(ch) return cpWidth(utf8.codepoint(ch)) > 1 end
function unicode.charWidth(ch) return cpWidth(utf8.codepoint(ch)) end
function unicode.wlen(s) local n = 0 for _, cp in utf8.codes(s) do n = n + cpWidth(cp) end return n end
function unicode.wtrunc(s, n)
    local w, out = 0, {}
    for _, cp in utf8.codes(s) do
        w = w + cpWidth(cp)
        if w >= n then break end
        out[#out + 1] = utf8.char(cp)
    end
    return table.concat(out)
end
preload.unicode = function() return unicode end

-- GPU + экран
local W, H = 160, 50
local scr = {bg = {}, fg = {}, ch = {}}
emu.screen = scr
local function scrReset(w, h)
    W, H = w, h
    for i = 1, W * H do scr.bg[i], scr.fg[i], scr.ch[i] = 0, 0xFFFFFF, " " end
end
scrReset(W, H)
local gpuState = {bg = 0, fg = 0xFFFFFF}
emu.gpuCalls = 0
local gpu = {type = "gpu", address = "gpu-0"}
function gpu.getResolution() return W, H end
function gpu.setResolution(w, h) scrReset(w, h) return true end
function gpu.maxResolution() return 160, 50 end
function gpu.bind() return true end
function gpu.getScreen() return "screen-0" end
function gpu.setBackground(c) emu.gpuCalls = emu.gpuCalls + 1 local o = gpuState.bg gpuState.bg = c return o end
function gpu.setForeground(c) emu.gpuCalls = emu.gpuCalls + 1 local o = gpuState.fg gpuState.fg = c return o end
function gpu.getBackground() return gpuState.bg end
function gpu.getForeground() return gpuState.fg end
function gpu.getDepth() return 8 end
function gpu.set(x, y, s, vertical)
    emu.gpuCalls = emu.gpuCalls + 1
    -- Как в OC: широкий символ занимает 2 колонки, следующая колонка становится пробелом,
    -- и всё, что идёт дальше в строке, сдвигается вправо
    for _, cp in utf8.codes(s) do
        local w = cpWidth(cp)
        if x >= 1 and x <= W and y >= 1 and y <= H then
            local i = (y - 1) * W + x
            scr.bg[i], scr.fg[i], scr.ch[i] = gpuState.bg, gpuState.fg, utf8.char(cp)
            if w > 1 and x + 1 <= W then
                scr.bg[i + 1], scr.fg[i + 1], scr.ch[i + 1] = gpuState.bg, gpuState.fg, " "
            end
        end
        if vertical then y = y + 1 else x = x + w end
    end
    return true
end
function gpu.get(x, y)
    local i = (y - 1) * W + x
    return scr.ch[i], scr.fg[i], scr.bg[i]
end
function gpu.fill(x, y, w, h, c)
    emu.gpuCalls = emu.gpuCalls + 1
    for yy = y, y + h - 1 do for xx = x, x + w - 1 do
        if xx >= 1 and xx <= W and yy >= 1 and yy <= H then
            local i = (yy - 1) * W + xx
            scr.bg[i], scr.fg[i], scr.ch[i] = gpuState.bg, gpuState.fg, c
        end
    end end
    return true
end
function gpu.copy() return true end

-- Компоненты
local components = {gpu = {gpu}}  -- type -> list of proxies
emu.components = components
function emu.addComponent(proxy)
    components[proxy.type] = components[proxy.type] or {}
    table.insert(components[proxy.type], proxy)
    computer.pushSignal("component_added", proxy.address, proxy.type)
end
function emu.removeComponent(proxy)
    local l = components[proxy.type] or {}
    for i = #l, 1, -1 do if l[i] == proxy then table.remove(l, i) end end
    computer.pushSignal("component_removed", proxy.address, proxy.type)
end
emu.componentCalls = 0

local component = {}
local function findByAddress(a)
    for _, l in pairs(components) do for _, p in ipairs(l) do if p.address == a then return p end end end
end
function component.list(filter, exact)
    local res = {}
    for t, l in pairs(components) do
        local ok = (not filter) or (exact and t == filter) or (not exact and t:find(filter, 1, true))
        if ok then for _, p in ipairs(l) do res[p.address] = t end end
    end
    local k
    return setmetatable(res, {__call = function() k = next(res, k) return k, k and res[k] end})
end
function component.isAvailable(t) return components[t] ~= nil and #components[t] > 0 end
function component.getPrimary(t)
    if not component.isAvailable(t) then error("no primary '" .. t .. "' available") end
    return components[t][1]
end
function component.proxy(a)
    local p = findByAddress(a)
    if not p then return nil, "no such component" end
    if p.type == "gpu" then return p end
    -- оборачиваем, чтобы считать вызовы и иметь возможность "отключить" компонент
    local w = {type = p.type, address = p.address, slot = -1}
    -- Как в OC: методы прокси — вызываемые таблицы (type() == "table"), а не функции
    for k, v in pairs(p) do
        if type(v) == "function" then
            w[k] = setmetatable({name = k, address = p.address}, {
                __call = function(_, ...)
                    emu.componentCalls = emu.componentCalls + 1
                    if p.__removed then error("no such component", 0) end
                    return v(...)
                end,
                __tostring = function() return "function" end,
            })
        end
    end
    return w
end
function component.methods(a) local p = findByAddress(a) local r = {} for k, v in pairs(p) do if type(v) == "function" then r[k] = false end end return r end
function component.doc(a, m) local p = findByAddress(a) return p and p.__doc and p.__doc[m] or nil end
function component.type(a) local p = findByAddress(a) return p and p.type end
setmetatable(component, {__index = function(_, t)
    if components[t] and components[t][1] then return component.proxy(components[t][1].address) end
    error("no primary '" .. tostring(t) .. "' available", 2)
end})
preload.component = function() return component end

-- event: виртуальное время + очередь сценария
local event = {}
local listeners = {}
local timers, timerId = {}, 0
local function runTimers()
    for id, t in pairs(timers) do
        if emu.time >= t.at then
            t.times = t.times - 1
            t.at = emu.time + t.interval
            if t.times <= 0 then timers[id] = nil end
            t.cb()
        end
    end
end
local function runActions()
    local i = 1
    while i <= #emu.actions do
        local a = emu.actions[i]
        if emu.time >= a[1] then table.remove(emu.actions, i) a[2]() else i = i + 1 end
    end
end
local function advance(dt)
    local target = emu.time + dt
    -- двигаемся шагами по 0.05 (тик), чтобы срабатывали действия сценария
    while emu.time < target - 1e-9 do
        emu.time = math.min(target, emu.time + 0.05)
        runActions()
        runTimers()
        if emu.time >= emu.endTime then
            -- конец сценария: программа просто замирает (её корутину больше не продолжают)
            if emu.programCo and coroutine.running() == emu.programCo then
                coroutine.yield("EMU_END")
            end
            error("EMU_END", 0)
        end
    end
end
emu.advance = advance
local function match(ev, name, ...)
    if name and not tostring(ev[2]):match(name) then return false end
    local f = {...}
    for i = 1, select("#", ...) do if f[i] ~= nil and ev[2 + i] ~= f[i] then return false end end
    return true
end
local function popEvent(filter)
    for i, ev in ipairs(emu.queue) do
        if ev[1] <= emu.time + 1e-9 and filter(ev) then
            table.remove(emu.queue, i)
            for _, l in ipairs(listeners) do if l.name == ev[2] then l.cb(table.unpack(ev, 2)) end end
            return ev
        end
    end
end
local function pullWith(timeout, filter)
    -- как в OC: даже pull(0) отдаёт управление до следующего тика
    if timeout and timeout < 0.05 then timeout = 0.05 end
    local deadline = emu.time + (timeout or math.huge)
    while true do
        local ev = popEvent(filter)
        if ev then return table.unpack(ev, 2) end
        if emu.time >= deadline - 1e-9 then return nil end
        advance(math.min(0.05, deadline - emu.time))
        -- корутины thread: даём им поработать
        if emu.threadsTick then emu.threadsTick() end
    end
end
function event.pull(...)
    local args = {...}
    local timeout
    if type(args[1]) == "number" then timeout = table.remove(args, 1) end
    local name = args[1]
    local rest = {table.unpack(args, 2)}
    return pullWith(timeout, function(ev) return match(ev, name, table.unpack(rest)) end)
end
function event.pullFiltered(timeout, filter)
    if type(timeout) == "function" then filter, timeout = timeout, nil end
    return pullWith(timeout, function(ev) return filter(table.unpack(ev, 2)) end)
end
function event.pullMultiple(...)
    local names = {...}
    local timeout
    if type(names[1]) == "number" then timeout = table.remove(names, 1) end
    return pullWith(timeout, function(ev) for _, n in ipairs(names) do if tostring(ev[2]):match(n) then return true end end return false end)
end
function event.listen(name, cb) table.insert(listeners, {name = name, cb = cb}) return true end
function event.ignore(name, cb) for i, l in ipairs(listeners) do if l.name == name and l.cb == cb then table.remove(listeners, i) return true end end return false end
function event.timer(interval, cb, times) timerId = timerId + 1 timers[timerId] = {interval = interval, cb = cb, times = times or 1, at = emu.time + interval} return timerId end
function event.cancel(id) local ok = timers[id] ~= nil timers[id] = nil return ok end
function event.push(...) computer.pushSignal(...) end
event.onError = function(e) trace("event error", tostring(e)) end
preload.event = function() return event end

function os.sleep(t) pullWith(t or 0, function() return false end) end

-- thread: кооперативные корутины, крутятся внутри pull
local threads = {}
emu.threadsTick = function()
    for i = #threads, 1, -1 do
        local th = threads[i]
        if th.dead then table.remove(threads, i)
        elseif not th.running then
            th.running = true
            local ok, err = coroutine.resume(th.co)
            th.running = false
            if not ok then trace("thread error", tostring(err)) th.dead = true end
            if coroutine.status(th.co) == "dead" then th.dead = true end
        end
    end
end
preload.thread = function()
    return {create = function(f, ...)
        local args = {...}
        local th = {}
        th.co = coroutine.create(function() return f(table.unpack(args)) end)
        function th:kill() self.dead = true end
        function th:status() return self.dead and "dead" or "running" end
        table.insert(threads, th)
        return th
    end}
end
-- внутри корутины pull должен уступать управление, а не крутить время
local rawPullWith = pullWith
pullWith = function(timeout, filter)
    local co, main = coroutine.running()
    if not main and co ~= emu.programCo then
        local deadline = emu.time + (timeout or math.huge)
        while true do
            local ev = popEvent(filter)
            if ev then return table.unpack(ev, 2) end
            if emu.time >= deadline - 1e-9 then return nil end
            coroutine.yield()
        end
    end
    return rawPullWith(timeout, filter)
end

-- filesystem
local fs = {}
local function sh(cmd) return rawExecute(cmd) end
function fs.exists(p) local f = rawOpen(realPath(p), "r") if f then f:close() return true end return sh("test -e '" .. realPath(p) .. "'") == true end
function fs.isDirectory(p) return sh("test -d '" .. realPath(p) .. "'") == true end
function fs.makeDirectory(p) return sh("mkdir -p '" .. realPath(p) .. "'") == true end
function fs.remove(p) return sh("rm -rf '" .. realPath(p) .. "'") == true end
function fs.rename(a, b) return sh("mv '" .. realPath(a) .. "' '" .. realPath(b) .. "'") == true end
function fs.size(p) local f = rawOpen(realPath(p), "rb") if not f then return 0 end local s = f:seek("end") f:close() return s end
function fs.list(p) local r = {} local h = io.popen("ls -1 '" .. realPath(p) .. "' 2>/dev/null") for l in h:lines() do table.insert(r, l) end h:close() local i = 0 return function() i = i + 1 return r[i] end end
function fs.concat(...) return (table.concat({...}, "/"):gsub("/+", "/")) end
function fs.path(p) return p:match("^(.*/)[^/]*$") or "" end
function fs.name(p) return p:match("([^/]*)/?$") end
function fs.lastModified() return 0 end
preload.filesystem = function() return fs end

-- shell / os.execute: перехватываем wget, rm, clear
local function fakeExec(cmd)
    cmd = tostring(cmd)
    trace("exec", cmd)
    local url, out = cmd:match("wget%s+%-%a+%s+(%S+)%s+(%S+)")
    if url then
        local data = emu.http and emu.http[url]
        if not data then return false end
        local f = io.open(out, "w") f:write(data) f:close()
        return true
    end
    return true
end
os.execute = fakeExec
-- Точная копия логики shell.parse из OpenOS: "--key=value" даёт значение, "--key" и "-abc" дают true,
-- всё остальное (в том числе число после "--key ") уходит в позиционные аргументы
local function shellParse(...)
    local params = table.pack(...)
    local args, options, doneWithOptions = {}, {}, false
    for i = 1, params.n do
        local param = params[i]
        if not doneWithOptions and type(param) == "string" then
            if param == "--" then
                doneWithOptions = true
            elseif param:sub(1, 2) == "--" then
                local key, value = param:match("%-%-(.-)=(.*)")
                if not key then key, value = param:sub(3), true end
                options[key] = value
            elseif param:sub(1, 1) == "-" and param ~= "-" then
                for j = 2, unicode.len(param) do options[unicode.sub(param, j, j)] = true end
            else
                table.insert(args, param)
            end
        else
            table.insert(args, param)
        end
    end
    return args, options
end
preload.shell = function() return {execute = fakeExec, parse = shellParse, getWorkingDirectory = function() return "/home" end, resolve = function(p) return p end} end
-- internet (OpenOS): request(url) -> итератор кусков; данные берутся из emu.http[url]
preload.internet = function()
    return {request = function(url)
        local data = emu.http and emu.http[url]
        if not data then error("404 " .. tostring(url), 0) end
        local sent = false
        return function()
            if sent then return nil end
            sent = true
            return data
        end
    end}
end
preload.term = function() return {clear = function() end, setCursor = function() end, write = function() end, read = function() return "" end, isAvailable = function() return true end} end
preload.keyboard = function() return {keys = {c = 46}, isControlDown = function() return false end, isKeyDown = function() return false end, isAltDown = function() return false end} end
preload.process = function() return {info = function() return {data = {signal = function() end}} end} end
preload.serialization = function()
    local s = {}
    function s.serialize(v, pretty)
        local t = type(v)
        if t == "table" then
            local parts = {}
            for k, x in pairs(v) do
                local key = type(k) == "string" and k:match("^[%a_][%w_]*$") and k or ("[" .. s.serialize(k) .. "]")
                table.insert(parts, key .. "=" .. s.serialize(x))
            end
            table.sort(parts)
            return "{" .. table.concat(parts, ",") .. "}"
        elseif t == "string" then return string.format("%q", v)
        else return tostring(v) end
    end
    function s.unserialize(str) local f = load("return " .. str, "=unserialize", "t", {math = {huge = math.huge}}) if not f then return nil end local ok, r = pcall(f) return ok and r or nil end
    return s
end
os.exit = function() error("EMU_EXIT", 0) end
local rawDate = os.date
os.date = function(fmt, t) return rawDate(fmt, t or 1700000000 + math.floor(emu.time)) end
emu.stdin = {}
io.read = function() local l = table.remove(emu.stdin, 1) trace("io.read ->", tostring(l)) return l end
io.write = function(...) for _, v in ipairs({...}) do rawStderr:write(tostring(v)) end end
io.stderr = setmetatable({write = function(_, ...) trace("stderr:", ...) end}, {})

table.insert(package.searchers, 2, function(name)
    local rel = name:gsub("%.", "/")
    local tried = {}
    for template in package.path:gmatch("[^;]+") do
        if template:sub(1, 1) == "/" and not template:find("^" .. emu.root:gsub("%p", "%%%0")) then
            local vpath = template:gsub("%?", rel)
            local f = rawOpen(realPath(vpath), "r")
            if f then
                local code = f:read("a") f:close()
                local chunk, err = load(code, "@" .. vpath)
                if not chunk then error(err, 0) end
                return chunk, vpath
            end
            tried[#tried + 1] = "\n\tno file '" .. vpath .. "' (emu)"
        end
    end
    return table.concat(tried)
end)
package.path = REPO .. "/lib/?.lua;" .. REPO .. "/lib/FormatModules/?.lua;" .. EMU_DIR .. "/?.lua;" .. package.path

-- image.lua грузит форматы через loadfile("/lib/FormatModules/OCIF.lua") — подкладываем в песочницу
sh("mkdir -p " .. emu.root .. "/lib/FormatModules && cp " .. REPO .. "/lib/OCIF.lua " .. emu.root .. "/lib/FormatModules/OCIF.lua")
sh("mkdir -p " .. emu.root .. "/home/images && cp " .. REPO .. "/home/images/*.pic " .. emu.root .. "/home/images/")

---------------------------------------------------------------------------
-- API сценария
---------------------------------------------------------------------------
function emu.at(t, fn) table.insert(emu.actions, {t, fn}) end
emu.nick = "Player"   -- кто нажимает по умолчанию (сценарий может поменять)
function emu.touch(x, y, nick) computer.pushSignal("touch", "screen-0", x, y, 0, nick or emu.nick) end
function emu.chat(nick, msg) computer.pushSignal("chat_message", "chatbox-0", nick, msg) end
function emu.key(char, code, nick) computer.pushSignal("key_down", "keyboard-0", char, code, nick or emu.nick) end
function emu.dump(path)
    local f = rawOpen(path, "w")
    f:write(W, " ", H, "\n")
    for i = 1, W * H do f:write(string.format("%06x %06x %s\n", scr.bg[i], scr.fg[i], scr.ch[i])) end
    f:close()
    trace("screenshot ->", path, "gpuCalls=" .. emu.gpuCalls, "componentCalls=" .. emu.componentCalls)
end
function emu.screenText()
    local lines = {}
    for y = 1, H do local r = {} for x = 1, W do r[x] = scr.ch[(y - 1) * W + x] end lines[y] = table.concat(r) end
    return table.concat(lines, "\n")
end
function emu.run(path, ...)
    local chunk = assert(rawLoadfile(path))
    local co = coroutine.create(chunk)
    emu.programCo = co
    local ok, res = coroutine.resume(co, ...)
    emu.programCo = nil
    if not ok then
        if tostring(res):find("EMU_EXIT") or tostring(res):find("EMU_END") then return true end
        local tb = debug.traceback(co, tostring(res))
        trace("program error:", tb)
        return false, tb
    end
    return true
end
-- Скопировать каталог репозитория в песочницу (как установщик кладёт программу в игре)
function emu.install(srcDir, virtualDir)
    sh("mkdir -p '" .. realPath(virtualDir) .. "' && cp -r '" .. srcDir .. "/.' '" .. realPath(virtualDir) .. "/'")
end
-- Запустить программу по ВИРТУАЛЬНОМУ пути (внутри песочницы), как её запустил бы OpenOS
function emu.runVirtual(vpath, ...)
    local f = assert(rawOpen(realPath(vpath), "r"))
    local code = f:read("a") f:close()
    local chunk = assert(load(code, "@" .. vpath))
    local tmp = os.tmpname()
    local tf = rawOpen(tmp, "w") tf:write("") tf:close()
    local co = coroutine.create(chunk)
    emu.programCo = co
    local ok, res = coroutine.resume(co, ...)
    emu.programCo = nil
    os.remove(tmp)
    if not ok then
        if tostring(res):find("EMU_EXIT") or tostring(res):find("EMU_END") then return true end
        local tb = debug.traceback(co, tostring(res))
        trace("program error:", tb)
        return false, tb
    end
    return true
end
function emu.interrupt() computer.pushSignal("interrupted", emu.time) end

local scenario = assert(arg[1], "usage: emu.lua <scenario.lua>")
return rawDofile(scenario)
