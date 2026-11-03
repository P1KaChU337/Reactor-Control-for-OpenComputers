-- Reactor Control: зонд компонентов
-- Собирает, какие методы есть у реакторов, ME, Flux и чат-бокса, что они возвращают и сколько стоит вызов.
--
-- По умолчанию НИЧЕГО НЕ МЕНЯЕТ: вызываются только методы без аргументов, имена которых
-- начинаются с get/is/has/can. activate/deactivate и прочие команды не трогаются.
--
-- Использование:
--   probe                  отчёт по всем компонентам -> /home/probe_report.txt
--   probe --watch 60       плюс 60 секунд записи показаний реактора #1 раз в секунду
--   probe --watch 60 -r 2  то же для реактора #2
--   probe --toggle 1       ВКЛЮЧАЕТ/ВЫКЛЮЧАЕТ реактор #1, чтобы замерить реакцию (спросит подтверждение)
--   probe --all            опросить вообще все компоненты, а не только известные типы
--
-- Потом отчёт можно выгрузить:  pastebin put /home/probe_report.txt

local component = require("component")
local computer = require("computer")
local shell = require("shell")

local args, opts = shell.parse(...)
local OUT = "/home/probe_report.txt"
local WATCH = tonumber(opts.watch or (opts.w and args[1])) or 0
local REACTOR_N = tonumber(opts.r) or 1
local TOGGLE = tonumber(opts.toggle)

local TYPES = {
    htc_reactors = true,
    me_controller = true, me_interface = true,
    flux_controller = true,
    chat_box = true,
}
-- Методы, которые даже с безопасным именем лучше вызывать особым образом (большие списки)
local SPECIAL = {
    getItemsInNetwork = function(p) return p.getItemsInNetwork({name = "ae2fc:fluid_drop"}) end,
    getCraftables = false,          -- огромный список, пропускаем
    getItemsInNetworkById = false,
}
local SAFE_PREFIX = {"^get", "^is", "^has", "^can"}
-- У ME десятки методов, часть возвращает огромные списки. Для ME вызываем только эти
local ME_WHITELIST = {
    getItemsInNetwork = true, getFluidsInNetwork = true,
    getEnergyStored = true, getMaxEnergyStored = true, getStoredPower = true, getMaxStoredPower = true,
    getAvgPowerUsage = true, getAvgPowerInjection = true, getIdlePowerUsage = true,
}
-- Каким методом мерить стоимость вызова (первый найденный)
local CHEAP = {"hasWork", "getTemperature", "getEnergyInfo", "getEnergyStored", "getAvgPowerUsage"}

-------------------------------------------------------------------------------
local out = {}
local function w(...) local s = table.concat({...}) out[#out + 1] = s end
local function say(...) local s = table.concat({...}) io.write(s, "\n") end

local function ser(v, depth, seen)
    depth = depth or 0
    seen = seen or {}
    local t = type(v)
    if t == "string" then
        if #v > 200 then v = v:sub(1, 200) .. "...(" .. #v .. " байт)" end
        return string.format("%q", v)
    elseif t ~= "table" then
        return tostring(v)
    end
    if seen[v] then return "<цикл>" end
    if depth >= 4 then return "{...}" end
    seen[v] = true
    local parts, n, total = {}, 0, 0
    local keys = {}
    for k in pairs(v) do total = total + 1; keys[#keys + 1] = k end
    table.sort(keys, function(a, b)
        if type(a) == type(b) and (type(a) == "number" or type(a) == "string") then return a < b end
        return type(a) < type(b)
    end)
    for _, k in ipairs(keys) do
        n = n + 1
        if n > 30 then parts[#parts + 1] = "...(" .. total .. " всего)" break end
        local ks = type(k) == "string" and k:match("^[%a_][%w_]*$") and k or "[" .. ser(k, depth + 1, seen) .. "]"
        parts[#parts + 1] = ks .. "=" .. ser(v[k], depth + 1, seen)
    end
    seen[v] = nil
    return "{" .. table.concat(parts, ", ") .. "}"
end

local function isSafe(name)
    for _, p in ipairs(SAFE_PREFIX) do if name:match(p) then return true end end
    return false
end

-- Вызов с замером. uptime меняется по тикам, поэтому у одиночного вызова точность ~0.05 с
local function timed(f, ...)
    local t0 = computer.uptime()
    local r = table.pack(pcall(f, ...))
    return computer.uptime() - t0, r
end

local function fmtResult(r)
    if not r[1] then return "ОШИБКА: " .. tostring(r[2]) end
    local parts = {}
    for i = 2, r.n do parts[#parts + 1] = ser(r[i]) end
    if #parts == 0 then return "(ничего)" end
    return table.concat(parts, " | ")
end

-------------------------------------------------------------------------------
w("Reactor Control probe — ", os.date("%Y-%m-%d %H:%M:%S"))
w("Архитектура: ", computer.getArchitecture and computer.getArchitecture() or "?",
  ", память: ", math.floor(computer.totalMemory() / 1024), " КБ, свободно: ", math.floor(computer.freeMemory() / 1024), " КБ")
w("")
w("=== Все компоненты ===")
local byType = {}
for addr, ctype in component.list() do
    byType[ctype] = byType[ctype] or {}
    table.insert(byType[ctype], addr)
end
local typeNames = {}
for t in pairs(byType) do typeNames[#typeNames + 1] = t end
table.sort(typeNames)
for _, t in ipairs(typeNames) do
    table.sort(byType[t])
    w(string.format("%-24s x%d  %s", t, #byType[t], table.concat(byType[t], ", ")))
end
w("")

-------------------------------------------------------------------------------
local function probeType(ctype)
    local addrs = byType[ctype]
    if not addrs then return end
    say("Опрос ", ctype, " (", #addrs, " шт.)...")
    w("=== ", ctype, " (", #addrs, " шт.) ===")

    -- методы и документация — по первому экземпляру
    local addr = addrs[1]
    local methods = component.methods(addr)
    local names = {}
    for name in pairs(methods) do names[#names + 1] = name end
    table.sort(names)
    w("-- Методы (direct = вызов без ожидания тика):")
    for _, name in ipairs(names) do
        local doc = component.doc(addr, name)
        w(string.format("  %-32s direct=%-5s %s", name, tostring(methods[name]), doc and tostring(doc) or ""))
    end

    -- значения по каждому экземпляру
    for i, a in ipairs(addrs) do
        local p = component.proxy(a)
        w("-- #", i, " ", a)
        for _, name in ipairs(names) do
            local special = SPECIAL[name]
            if special == false then
                w(string.format("  %-32s (пропущен: большой список)", name))
            elseif ctype:match("^me_") and not ME_WHITELIST[name] then
                -- не вызываем, только список методов выше
            elseif special or isSafe(name) then
                local dt, r = timed(special and function() return special(p) end or p[name])
                w(string.format("  %-32s %5.2fс  %s", name, dt, fmtResult(r)))
            end
        end
        if ctype == "htc_reactors" and i >= 6 then
            w("  ...остальные реакторы не опрашиваются подробно")
            break
        end
    end

    -- стоимость вызова: 20 одинаковых вызовов подряд
    local p = component.proxy(addr)
    local cheap
    for _, name in ipairs(CHEAP) do
        if methods[name] and pcall(p[name]) then cheap = name break end
    end
    if cheap then
        local t0 = computer.uptime()
        for _ = 1, 20 do pcall(p[cheap]) end
        local dt = computer.uptime() - t0
        w(string.format("-- Стоимость: 20 вызовов %s = %.2fс (%.3fс на вызов, ~%.1f тика)", cheap, dt, dt / 20, dt / 20 / 0.05))
    end
    w("")
end

local probeTypes = {}
for _, t in ipairs(typeNames) do
    if opts.all or TYPES[t] then probeTypes[#probeTypes + 1] = t end
end
for _, t in ipairs(probeTypes) do
    local ok, err = pcall(probeType, t)
    if not ok then w("!!! ошибка при опросе ", t, ": ", tostring(err)) w("") end
end

-------------------------------------------------------------------------------
-- Наблюдение за реактором во времени: видно, как меняются стержни, буфер, температура
local reactors = byType.htc_reactors or {}
local function getters(p)
    local list = {}
    for name in pairs(component.methods(p.address)) do
        if isSafe(name) then list[#list + 1] = name end
    end
    table.sort(list)
    return list
end

if WATCH > 0 and reactors[REACTOR_N] then
    local p = component.proxy(reactors[REACTOR_N])
    local list = getters(p)
    say("Наблюдение за реактором #", REACTOR_N, " ", WATCH, " с...")
    w("=== Наблюдение: реактор #", REACTOR_N, " ", p.address, ", ", WATCH, " с ===")
    local t0 = computer.uptime()
    for s = 0, WATCH do
        local row = {}
        for _, name in ipairs(list) do
            local ok, v = pcall(p[name])
            if name == "getAllFuelRodsStatus" and ok and type(v) == "table" then
                local rods = {}
                for k, rod in ipairs(v) do rods[#rods + 1] = type(rod) == "table" and tostring(rod[6]) or ser(rod) end
                v = "rod[6]=" .. table.concat(rods, ",")
                row[#row + 1] = name .. "=" .. v
            else
                row[#row + 1] = name .. "=" .. (ok and ser(v) or "ERR")
            end
        end
        w(string.format("t=%6.2f  %s", computer.uptime() - t0, table.concat(row, "  ")))
        if s < WATCH then os.sleep(1) end
    end
    w("")
end

-------------------------------------------------------------------------------
-- Опасный режим: включение/выключение одного реактора
if TOGGLE then
    local addr = reactors[TOGGLE]
    if not addr then
        say("Реактор #", TOGGLE, " не найден")
    else
        io.write("ВНИМАНИЕ: реактор #", TOGGLE, " (", addr, ") будет включён и выключен.\n",
                 "Убедитесь, что схема и охлаждение в порядке. Напишите YES для продолжения: ")
        if io.read() == "YES" then
            local p = component.proxy(addr)
            local function snap(tag)
                local okW, hw = pcall(p.hasWork)
                local okT, tp = pcall(p.getTemperature)
                local okE, en = pcall(p.getEnergyGeneration)
                w(string.format("  %-14s t=%.2f hasWork=%s temp=%s gen=%s", tag, computer.uptime(), tostring(hw), tostring(tp), tostring(en)))
            end
            w("=== Тест включения реактора #", TOGGLE, " ===")
            local wasOn = select(2, pcall(p.hasWork))
            snap("до")
            local dt, r = timed(p.activate)
            w(string.format("  activate: %.2fс -> %s", dt, fmtResult(r)))
            snap("сразу")
            for i = 1, 5 do os.sleep(1) snap("через " .. i .. "с") end
            dt, r = timed(p.deactivate)
            w(string.format("  deactivate: %.2fс -> %s", dt, fmtResult(r)))
            snap("сразу")
            for i = 1, 3 do os.sleep(1) snap("через " .. i .. "с") end
            if wasOn == true then p.activate() w("  исходное состояние восстановлено: включён") end
            w("")
        else
            say("Отменено")
        end
    end
end

-------------------------------------------------------------------------------
local f, err = io.open(OUT, "w")
if not f then
    say("Не удалось записать ", OUT, ": ", tostring(err))
    for _, l in ipairs(out) do print(l) end
    return
end
f:write(table.concat(out, "\n"), "\n")
f:close()
say("")
say("Готово! Отчёт: ", OUT, " (", #out, " строк)")
say("Посмотреть:  edit ", OUT)
say("Выгрузить:   pastebin put ", OUT)
