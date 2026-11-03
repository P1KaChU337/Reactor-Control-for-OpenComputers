-- Обёртка над компонентом реактора HiTech (htc_reactors_nuclear_reactor).
-- Каждый вызов метода стоит 1 тик, поэтому опрос разбит на группы с разной частотой.
local M = {}

M.TYPE_PREFIX = "htc_reactors"

-- Безопасный вызов: -> ok, value. Ошибки и nil не роняют программу.
-- В OpenComputers методы прокси — НЕ функции, а вызываемые таблицы (с __call), поэтому проверяем только на nil.
function M.call(proxy, method, ...)
    local f = proxy and proxy[method]
    if f == nil then return false, "нет метода " .. tostring(method) end
    local ok, v = pcall(f, ...)
    if not ok then return false, v end
    return true, v
end

-- Записи реактора приходят плоским списком {"item", name, "fuel", 3652, ...} -> {item=name, fuel=3652}
function M.kv(flat)
    local r = {}
    if type(flat) ~= "table" then return r end
    for i = 1, #flat - 1, 2 do
        if type(flat[i]) == "string" then r[flat[i]] = flat[i + 1] end
    end
    return r
end

-- Сводка по стержням. Слоты идут с пропусками, поэтому только pairs (ipairs обрывается на первой дыре).
function M.rodsSummary(rods)
    if type(rods) ~= "table" then return nil end
    local s = {min = math.huge, max = 0, sum = 0, count = 0, maxFuel = nil}
    for _, entry in pairs(rods) do
        local e = M.kv(entry)
        local fuel = tonumber(e.fuel)
        if fuel then
            s.count = s.count + 1
            s.sum = s.sum + fuel
            if fuel < s.min then s.min = fuel end
            if fuel > s.max then s.max = fuel end
            s.maxFuel = s.maxFuel or tonumber(e.maxFuel)
        end
    end
    if s.count == 0 then s.min = 0 end
    return s
end

-- Группы опроса. Все функции обновляют запись реактора r (см. core.state) и возвращают true, если что-то изменилось.

-- Редко меняющееся: тип охлаждения, размер буфера, номинальный расход, уровень
function M.pollStatic(r, proxy)
    local ok, v
    ok, v = M.call(proxy, "isActiveCooling")
    if ok then r.kind = v and "fluid" or "air" end
    ok, v = M.call(proxy, "getMaxFluidCoolant"); if ok then r.coolantMax = tonumber(v) end
    ok, v = M.call(proxy, "getFluidCoolantConsume"); if ok then r.consumeNominal = tonumber(v) end
    ok, v = M.call(proxy, "getMaxTemperature"); if ok then r.maxTemp = tonumber(v) end
    ok, v = M.call(proxy, "getReactorLevel"); if ok then r.level = tonumber(v) end
    return true
end

-- Работает ли реактор. -> observed (true/false/nil при ошибке)
function M.pollRunning(proxy)
    local ok, v = M.call(proxy, "hasWork")
    if not ok then return nil end
    return v == true
end

function M.pollCoolant(r, proxy, now)
    local ok, v = M.call(proxy, "getFluidCoolant")
    if not ok then return false end
    r.coolant = tonumber(v)
    r.drain:add(now, r.coolant, r.running)
    return true
end

function M.pollStats(r, proxy)
    local ok, v
    ok, v = M.call(proxy, "getEnergyGeneration"); if ok then r.rf = tonumber(v) or 0 end
    ok, v = M.call(proxy, "getTemperature"); if ok then r.temp = tonumber(v) end
    return true
end

function M.pollRods(r, proxy, now)
    local ok, v = M.call(proxy, "getAllFuelRodsStatus")
    if not ok then return false end
    r.rods = M.rodsSummary(v)
    r.burn:add(now, r.rods, r.running, r.stoppedAt)
    return true
end

function M.activate(proxy) return M.call(proxy, "activate") end
function M.deactivate(proxy) return M.call(proxy, "deactivate") end

return M
