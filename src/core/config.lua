-- Конфигурация: значения по умолчанию, проверка типов и диапазонов, сохранение, перенос старого config.lua.
local serialize = require("core.serialize")
local fsutil = require("core.fsutil")

local M = {}

M.PATH = "/home/reactorcontrol/data/config.cfg"
M.LEGACY_PATH = "/home/data/config.lua"
M.VERSION = 1

-- Описание полей: значение по умолчанию + проверка.
-- check(v) -> нормализованное значение или nil (тогда берётся default).
local function bool(v) if type(v) == "boolean" then return v end end
local function numRange(lo, hi)
    return function(v)
        v = tonumber(v)
        if not v or v ~= v then return nil end
        if lo and v < lo then v = lo end
        if hi and v > hi then v = hi end
        return v
    end
end
local function oneOf(...)
    local allowed = {}
    for _, x in ipairs({...}) do allowed[x] = true end
    return function(v) if allowed[v] then return v end end
end
local function stringList(maxLen)
    return function(v)
        if type(v) ~= "table" then return nil end
        local res, seen = {}, {}
        for _, s in ipairs(v) do
            if type(s) == "string" then
                s = s:match("^%s*(.-)%s*$")
                if #s > 0 and #s <= maxLen and not seen[s] then
                    seen[s] = true
                    res[#res + 1] = s
                end
            end
        end
        return res
    end
end
local function addressMap(v)
    -- адрес компонента -> постоянный номер реактора на экране
    if type(v) ~= "table" then return nil end
    local res, used = {}, {}
    for addr, slot in pairs(v) do
        slot = tonumber(slot)
        if type(addr) == "string" and slot and slot >= 1 and slot <= 6 and slot == math.floor(slot) and not used[slot] then
            used[slot] = true
            res[addr] = slot
        end
    end
    return res
end

M.SCHEMA = {
    version          = {default = M.VERSION, check = numRange(1)},
    threshold        = {default = 50000, check = numRange(0, 1e15)},   -- порог хладагента в ME, mB
    users            = {default = {}, check = stringList(16)},          -- белый список игроков
    usersApplied     = {default = {}, check = stringList(16)},          -- кому уже выдан computer.addUser
    theme            = {default = "dark", check = oneOf("dark", "light")},
    updateCheck      = {default = true, check = bool},
    debugLog         = {default = false, check = bool},
    firstStart       = {default = true, check = bool},
    metric           = {default = "auto", check = oneOf("auto", "", "k", "m", "g")},
    reactorSlots     = {default = {}, check = addressMap},
    -- защита
    autoRestart      = {default = true, check = bool},    -- запускать реактор обратно, когда авария прошла
    -- Буфер считается в СЕКУНДАХ работы: буфер / реальный расход. В норме он не опускается ниже ~8 с
    -- (долив до полного раз в 3 с). Остановленный реактор буфер не доливает, поэтому останавливаемся
    -- заранее, чтобы хватило на перезапуск.
    bufferStopSec    = {default = 5, check = numRange(2, 60)},  -- мягкий порог: стоп
    bufferHardStopSec = {default = 2, check = numRange(1, 30)}, -- жёсткий порог: стоп всегда, даже сразу после запуска
    startGraceSec    = {default = 4, check = numRange(0, 60)},  -- после запуска до первого долива: только жёсткий порог
    bufferRestartSec = {default = 4, check = numRange(1, 60)},  -- автозапуск, только если буфера хватит хотя бы на N с
    bufferResumePct  = {default = 0.8, check = numRange(0.1, 1)},  -- или если буфер заполнен хотя бы на N
    bufferRetrySec   = {default = 30, check = numRange(5, 3600)}, -- автозапуск после аварии буфера не раньше, чем через N с
    bufferStopPct    = {default = 0.5, check = numRange(0.05, 0.95)}, -- запасной порог, если расход неизвестен совсем
    drainFactor      = {default = 100, check = numRange(1, 10000)}, -- пока расход не замерен: номинал x N (замер с сервера)
    coolantName      = {default = "low_temperature_refrigerant", check = function(v) if type(v) == "string" and #v > 0 then return v end end},
    meLostSec        = {default = 180, check = numRange(30, 3600)}, -- нет данных ME дольше N с => авария
    onStart          = {default = "stop", check = oneOf("stop", "adopt")}, -- при старте программы: остановить всё / подхватить работающие
    maxAutoRestarts  = {default = 3, check = numRange(0, 100)},   -- автозапусков за окно, потом нужен ручной
    autoRestartWindowSec = {default = 600, check = numRange(60, 86400)},
}

local function copy(v)
    if type(v) ~= "table" then return v end
    local r = {}
    for k, x in pairs(v) do r[k] = copy(x) end
    return r
end

function M.defaults()
    local c = {}
    for k, f in pairs(M.SCHEMA) do c[k] = copy(f.default) end
    return c
end

-- Привести произвольную таблицу к схеме. Возвращает конфиг и список предупреждений.
function M.normalize(raw)
    local c, warnings = {}, {}
    raw = type(raw) == "table" and raw or {}
    for k, f in pairs(M.SCHEMA) do
        local v = raw[k]
        if v == nil then
            c[k] = copy(f.default)
        else
            local nv = f.check(v)
            if nv == nil then
                warnings[#warnings + 1] = "config: неверное значение " .. k .. ", взято по умолчанию"
                c[k] = copy(f.default)
            else
                c[k] = nv
            end
        end
    end
    for k in pairs(raw) do
        if not M.SCHEMA[k] then warnings[#warnings + 1] = "config: неизвестный ключ " .. tostring(k) .. " пропущен" end
    end
    return c, warnings
end

-- Старый config.lua — это Lua-присваивания (porog = ..., users = {...}).
-- Выполняем его в пустом окружении и переносим значения.
function M.fromLegacy(text)
    local env = {}
    local chunk
    if setfenv then
        chunk = loadstring(text)
        if chunk then setfenv(chunk, env) end
    else
        chunk = load(text, "=legacy_config", "t", env)
    end
    if not chunk then return nil, "не удалось разобрать старый конфиг" end
    local ok, err = pcall(chunk)
    if not ok then return nil, tostring(err) end
    return {
        threshold = env.porog,
        users = env.users,
        usersApplied = env.usersold,
        theme = env.theme == true and "light" or "dark",
        updateCheck = env.updateCheck,
        debugLog = env.debugLog,
        firstStart = env.isFirstStart,
    }
end

-- load([path, legacyPath]) -> config, info{source = "file"|"legacy"|"default", warnings = {...}}
function M.load(path, legacyPath)
    path = path or M.PATH
    legacyPath = legacyPath or M.LEGACY_PATH
    local info = {warnings = {}}
    local text = fsutil.read(path)
    if text then
        local raw, err = serialize.unserialize(text)
        if type(raw) == "table" then
            local c, w = M.normalize(raw)
            info.source, info.warnings = "file", w
            return c, info
        end
        info.warnings[#info.warnings + 1] = "config: файл повреждён (" .. tostring(err) .. "), загружены значения по умолчанию"
        fsutil.rename(path, path .. ".broken")
    end
    local legacy = fsutil.read(legacyPath)
    if legacy then
        local raw, err = M.fromLegacy(legacy)
        if raw then
            local c, w = M.normalize(raw)
            for _, x in ipairs(w) do info.warnings[#info.warnings + 1] = x end
            info.source = "legacy"
            return c, info
        end
        info.warnings[#info.warnings + 1] = "config: старый конфиг не перенесён: " .. tostring(err)
    end
    info.source = "default"
    return M.defaults(), info
end

function M.save(c, path)
    path = path or M.PATH
    local normalized = M.normalize(c)
    local text = "-- Reactor Control: настройки. Удобнее менять в меню настроек программы.\n"
        .. serialize.serialize(normalized, true) .. "\n"
    -- комментарий в начале файла: unserialize ждёт выражение, поэтому комментарий срезаем при чтении
    return fsutil.writeAtomic(path, text)
end

-- serialize.unserialize("-- коммент\n{...}") работает: "return -- коммент\n{...}" — валидный Lua.

return M
