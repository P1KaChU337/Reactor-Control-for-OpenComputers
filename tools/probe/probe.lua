-- Reactor Control: зонд компонентов (v2)
-- Собирает, какие методы есть у реакторов, ME, Flux и чат-бокса, что они возвращают и сколько стоит вызов.
--
-- По умолчанию НИЧЕГО НЕ МЕНЯЕТ: вызываются только методы без аргументов, имена которых
-- начинаются с get/is/has/can. activate/deactivate и прочие команды не трогаются.
--
-- Использование:
--   probe                  отчёт -> /home/probe_report.txt
--   probe --watch 120      плюс 120 секунд наблюдения за реактором #1 (лучше на РАБОТАЮЩЕМ реакторе)
--   probe --watch 120 -r 2 то же для реактора #2
--   probe --cooldown       замерить кулдаун ME getItemsInNetwork (ждёт до ~2 минут)
--   probe --toggle 1       ВКЛЮЧАЕТ/ВЫКЛЮЧАЕТ реактор #1, чтобы замерить реакцию (спросит подтверждение)
--   probe --all            опросить вообще все компоненты, а не только известные типы
--
-- Выгрузить отчёт:  pastebin put /home/probe_report.txt

local component = require("component")
local computer = require("computer")
local shell = require("shell")

local args, opts = shell.parse(...)
local OUT = "/home/probe_report.txt"
local WATCH = tonumber(opts.watch) or 0
local REACTOR_N = tonumber(opts.r) or 1
local TOGGLE = tonumber(opts.toggle)

local function isKnownType(t)
    return t:match("^htc_reactors") or t:match("^me_") or t == "flux_controller" or t == "chat_box"
end

local SAFE_PREFIX = {"^get", "^is", "^has", "^can"}
-- У ME десятки методов, часть возвращает огромные списки. Для ME вызываем только эти
local ME_CALL = {
    getAvgPowerUsage = true, getAvgPowerInjection = true, getIdlePowerUsage = true,
    getStoredPower = true, getMaxStoredPower = true, isNetworkPowered = true,
}
local CHEAP = {"hasWork", "getTemperature", "getEnergyInfo", "getAvgPowerUsage"}

-------------------------------------------------------------------------------
local out = {}
local function w(...) out[#out + 1] = table.concat({...}) end
local function say(...) io.write(table.concat({...}), "\n") end

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
    local parts, keys = {}, {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b)
        if type(a) == type(b) and (type(a) == "number" or type(a) == "string") then return a < b end
        return type(a) < type(b)
    end)
    for n, k in ipairs(keys) do
        if n > 30 then parts[#parts + 1] = "...(" .. #keys .. " всего)" break end
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

-- Реактор отдаёт записи "плоским" списком ключ/значение: {"item", "...", "fuel", 3652, ...}
local function kv(flat)
    local r = {}
    if type(flat) ~= "table" then return r end
    for i = 1, #flat - 1, 2 do
        if type(flat[i]) == "string" then r[flat[i]] = flat[i + 1] end
    end
    return r
end

local function slotsOf(t)
    local s = {}
    for k in pairs(t) do s[#s + 1] = k end
    table.sort(s, function(a, b) return tostring(a) < tostring(b) end)
    if #s > 0 and type(s[1]) == "number" then table.sort(s) end
    return s
end

local function rodsSummary(rods)
    if type(rods) ~= "table" then return "не таблица: " .. ser(rods) end
    local slots = slotsOf(rods)
    local n, sum, mn, mx, maxFuel, names = 0, 0, math.huge, -math.huge, nil, {}
    for _, slot in ipairs(slots) do
        local r = kv(rods[slot])
        local fuel = tonumber(r.fuel)
        if fuel then
            n = n + 1; sum = sum + fuel
            mn = math.min(mn, fuel); mx = math.max(mx, fuel)
        end
        maxFuel = maxFuel or r.maxFuel
        if r.item then names[r.item] = (names[r.item] or 0) + 1 end
    end
    local nm = {}
    for k, c in pairs(names) do nm[#nm + 1] = k .. " x" .. c end
    local slotStr = {}
    for _, s in ipairs(slots) do slotStr[#slotStr + 1] = tostring(s) end
    return string.format("стержней=%d, слоты=[%s], #rods=%d, fuel min=%s max=%s sum=%s, maxFuel=%s, %s",
        n, table.concat(slotStr, ","), #rods, tostring(mn), tostring(mx), tostring(sum), tostring(maxFuel), table.concat(nm, ", "))
end

local function componentsSummary(list)
    if type(list) ~= "table" then return ser(list) end
    local names, n = {}, 0
    for _, e in pairs(list) do
        local r = kv(e)
        n = n + 1
        if r.item then names[r.item] = (names[r.item] or 0) + 1 end
    end
    local nm = {}
    for k, c in pairs(names) do nm[#nm + 1] = k .. " x" .. c end
    table.sort(nm)
    local first = list[slotsOf(list)[1]]
    return "записей=" .. n .. ", пример=" .. ser(first) .. ", состав: " .. table.concat(nm, ", ")
end

local SUMMARY = {getAllFuelRodsStatus = rodsSummary, getReactorComponents = componentsSummary}

-------------------------------------------------------------------------------
w("Reactor Control probe v2 — ", os.date("%Y-%m-%d %H:%M:%S"))
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

local reactors = {}
for _, t in ipairs(typeNames) do
    if t:match("^htc_reactors") then for _, a in ipairs(byType[t]) do reactors[#reactors + 1] = a end end
end

-------------------------------------------------------------------------------
local function probeType(ctype)
    local addrs = byType[ctype]
    say("Опрос ", ctype, " (", #addrs, " шт.)...")
    w("=== ", ctype, " (", #addrs, " шт.) ===")

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

    local isME = ctype:match("^me_")
    for i, a in ipairs(addrs) do
        local p = component.proxy(a)
        w("-- #", i, " ", a)
        for _, name in ipairs(names) do
            if (isME and ME_CALL[name]) or (not isME and isSafe(name)) then
                local dt, r = timed(p[name])
                local text
                if r[1] and SUMMARY[name] then text = SUMMARY[name](r[2]) else text = fmtResult(r) end
                w(string.format("  %-32s %5.2fс  %s", name, dt, text))
            end
        end
    end

    local p = component.proxy(addr)
    for _, name in ipairs(CHEAP) do
        if methods[name] and pcall(p[name]) then
            local t0 = computer.uptime()
            for _ = 1, 20 do pcall(p[name]) end
            local dt = computer.uptime() - t0
            w(string.format("-- Стоимость: 20 вызовов %s = %.2fс (%.3fс на вызов, ~%.1f тика)", name, dt, dt / 20, dt / 20 / 0.05))
            break
        end
    end
    w("")
end

for _, t in ipairs(typeNames) do
    if opts.all or isKnownType(t) then
        local ok, err = pcall(probeType, t)
        if not ok then w("!!! ошибка при опросе ", t, ": ", tostring(err)) w("") end
    end
end

-------------------------------------------------------------------------------
-- ME: где искать хладагент и есть ли кулдауны
local meAddr = (byType.me_controller or byType.me_interface or {})[1]
if meAddr then
    local me = component.proxy(meAddr)
    say("ME: жидкости и кулдауны...")
    w("=== ME: хладагент и кулдауны ===")
    local function fluidsCall(tag)
        local dt, r = timed(me.getFluidsInNetwork)
        if not r[1] or type(r[2]) ~= "table" then
            w("  getFluidsInNetwork ", tag, ": ", string.format("%.2fс ", dt), fmtResult(r))
            return
        end
        local list = r[2]
        w(string.format("  getFluidsInNetwork %s: %.2fс, жидкостей: %d", tag, dt, #list))
        for _, f in ipairs(list) do
            local s = (tostring(f.name) .. " " .. tostring(f.label)):lower()
            if s:find("refriger") or s:find("coolant") or s:find("cool") or s:find("хлад") then
                w("    НАЙДЕНО: ", ser(f))
            end
        end
    end
    fluidsCall("вызов 1")
    fluidsCall("вызов 2 (сразу)")

    local function itemsCall(tag)
        local dt, r = timed(me.getItemsInNetwork, {name = "ae2fc:fluid_drop"})
        if r[1] and type(r[2]) == "table" then
            w(string.format("  getItemsInNetwork{ae2fc:fluid_drop} %s: %.2fс, записей: %d", tag, dt, #r[2]))
            for _, it in ipairs(r[2]) do
                local s = tostring(it.label):lower()
                if s:find("refriger") or s:find("coolant") or s:find("cool") then w("    НАЙДЕНО: ", ser(it)) end
            end
            return true
        end
        w(string.format("  getItemsInNetwork{ae2fc:fluid_drop} %s: %.2fс -> %s", tag, dt, fmtResult(r)))
        return false, r[1] and r[4]
    end
    local ok, left = itemsCall("вызов 1")
    if opts.cooldown then
        -- ждём окончания кулдауна, потом два вызова подряд, чтобы узнать полную длительность
        local wait = tonumber(tostring(left or ""):match("(%d+)")) or 0
        if not ok then
            say("  жду ", wait + 1, " с до конца кулдауна...")
            os.sleep(wait + 1)
            ok = itemsCall("после ожидания")
        end
        if ok then
            local t0 = computer.uptime()
            local ok2, left2 = itemsCall("сразу после успешного")
            if not ok2 then
                w("  => кулдаун после успешного вызова: ", tostring(left2))
                -- проверим, сбрасывается ли он раньше, чем сказано
                local deadline = t0 + 120
                while computer.uptime() < deadline do
                    os.sleep(1)
                    local dt, r = timed(me.getItemsInNetwork, {name = "ae2fc:fluid_drop"})
                    if r[1] and type(r[2]) == "table" then
                        w(string.format("  => снова доступен через %.1f с", computer.uptime() - t0))
                        break
                    end
                end
            else
                w("  => кулдауна нет (два вызова подряд успешны)")
            end
        end
    else
        w("  (длительность кулдауна не мерилась, запустите probe --cooldown)")
    end
    w("")
end

-------------------------------------------------------------------------------
-- Наблюдение за реактором во времени
local function rodsStats(rods)
    local n, sum, mn, mx = 0, 0, math.huge, -math.huge
    if type(rods) == "table" then
        for _, e in pairs(rods) do
            local fuel = tonumber(kv(e).fuel)
            if fuel then n = n + 1; sum = sum + fuel; mn = math.min(mn, fuel); mx = math.max(mx, fuel) end
        end
    end
    return n, sum, mn, mx
end

if WATCH > 0 and reactors[REACTOR_N] then
    local p = component.proxy(reactors[REACTOR_N])
    say("Наблюдение за реактором #", REACTOR_N, " ", WATCH, " с...")
    w("=== Наблюдение: реактор #", REACTOR_N, " ", p.address, ", ", WATCH, " с ===")
    w("  t       work  temp/max    gen          coolant/max        dCool/s  consume  rods  fuel(min..max)  sum      dSum/s")
    local t0 = computer.uptime()
    local prevT, prevCool, prevSum
    local nextAt = t0
    while computer.uptime() - t0 <= WATCH do
        local now = computer.uptime()
        local work = select(2, pcall(p.hasWork))
        local temp = select(2, pcall(p.getTemperature))
        local tmax = select(2, pcall(p.getMaxTemperature))
        local gen = select(2, pcall(p.getEnergyGeneration))
        local cool = select(2, pcall(p.getFluidCoolant))
        local cmax = select(2, pcall(p.getMaxFluidCoolant))
        local cons = select(2, pcall(p.getFluidCoolantConsume))
        local n, sum, mn, mx = rodsStats(select(2, pcall(p.getAllFuelRodsStatus)))
        local dCool, dSum = "", ""
        if prevT and now > prevT then
            if tonumber(cool) and tonumber(prevCool) then dCool = string.format("%.1f", (cool - prevCool) / (now - prevT)) end
            dSum = string.format("%.2f", (sum - prevSum) / (now - prevT))
        end
        w(string.format("  %-7.2f %-5s %5s/%-5s %-12s %8s/%-9s %8s  %-7s  %-4d  %s..%s  %-8s %s",
            now - t0, tostring(work), tostring(temp), tostring(tmax), tostring(gen), tostring(cool), tostring(cmax),
            dCool, tostring(cons), n, tostring(mn), tostring(mx), tostring(sum), dSum))
        prevT, prevCool, prevSum = now, cool, sum
        nextAt = nextAt + 1
        local s = nextAt - computer.uptime()
        if s > 0 then os.sleep(s) end
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
            local t0 = computer.uptime()
            local function snap(tag)
                local _, hw = pcall(p.hasWork)
                local _, tp = pcall(p.getTemperature)
                local _, en = pcall(p.getEnergyGeneration)
                local _, cl = pcall(p.getFluidCoolant)
                w(string.format("  %-10s t=%5.2f hasWork=%s temp=%s gen=%s coolant=%s", tag, computer.uptime() - t0, tostring(hw), tostring(tp), tostring(en), tostring(cl)))
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
