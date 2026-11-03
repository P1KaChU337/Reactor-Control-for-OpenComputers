-- Журнал: кольцевой буфер в памяти (его показывает консоль на экране) + файл с ротацией.
-- В файл пишется пачками (flush), чтобы не открывать файл на каждое сообщение.
local fsutil = require("core.fsutil")

local LEVELS = {debug = 1, info = 2, warn = 3, error = 4}

local Log = {}
Log.__index = Log

-- opts: path, clock (функция -> секунды), keep (строк в памяти), maxFileSize, fileLevel, flushInterval
function Log.new(opts)
    opts = opts or {}
    local self = setmetatable({}, Log)
    self.path = opts.path
    self.clock = opts.clock or os.clock
    self.date = opts.date or function() return os.date("%Y-%m-%d %H:%M:%S") end
    self.keep = opts.keep or 100
    self.maxFileSize = opts.maxFileSize or 64 * 1024
    self.fileLevel = LEVELS[opts.fileLevel or "info"]
    self.flushInterval = opts.flushInterval or 10
    self.entries = {}       -- {time, level, text, count}
    self.pending = {}       -- строки, ждущие записи в файл
    self.listeners = {}
    self.lastFlush = self.clock()
    self.version = 0        -- растёт при каждом изменении entries (для перерисовки консоли)
    return self
end

function Log:setFileLevel(level) self.fileLevel = LEVELS[level] or self.fileLevel end

function Log:onEntry(fn) self.listeners[#self.listeners + 1] = fn end

function Log:write(level, text, opts)
    text = tostring(text)
    local now = self.clock()
    local last = self.entries[#self.entries]
    -- одинаковые сообщения подряд склеиваются: "текст (x3)"
    if last and last.text == text and last.level == level and not (opts and opts.noStack) then
        last.count = last.count + 1
        last.time = now
    else
        last = {time = now, level = level, text = text, count = 1, color = opts and opts.color}
        self.entries[#self.entries + 1] = last
        if #self.entries > self.keep then table.remove(self.entries, 1) end
    end
    self.version = self.version + 1
    if self.path and LEVELS[level] >= self.fileLevel then
        self.pending[#self.pending + 1] = string.format("[%s] %-5s %s", self.date(), level:upper(), text)
        if LEVELS[level] >= LEVELS.error then self:flush() end
    end
    for _, fn in ipairs(self.listeners) do pcall(fn, last) end
    return last
end

function Log:debug(t, o) return self:write("debug", t, o) end
function Log:info(t, o) return self:write("info", t, o) end
function Log:warn(t, o) return self:write("warn", t, o) end
function Log:error(t, o) return self:write("error", t, o) end
-- Цветные сообщения уровня info: "ok" — зелёное (успех), "title" — голубое (заголовки)
function Log:ok(t) return self:write("info", t, {color = "ok"}) end
function Log:title(t) return self:write("info", t, {color = "title", noStack = true}) end

function Log:tick()
    if #self.pending > 0 and self.clock() - self.lastFlush >= self.flushInterval then self:flush() end
end

function Log:flush()
    self.lastFlush = self.clock()
    if not self.path or #self.pending == 0 then return true end
    local data = table.concat(self.pending, "\n") .. "\n"
    self.pending = {}
    if fsutil.exists(self.path) and fsutil.size(self.path) + #data > self.maxFileSize then
        local old = self.path .. ".1"
        if fsutil.exists(old) then fsutil.remove(old) end
        fsutil.rename(self.path, old)
    end
    local dir = fsutil.dirname(self.path)
    if not fsutil.exists(dir) then fsutil.makeDirectory(dir) end
    return fsutil.append(self.path, data)
end

Log.LEVELS = LEVELS
return Log
