-- Команды через чат-бокс (Computronics): @help, @status, @start [n], @stop [n] и т.д.
-- Выполняются только игроками из белого списка и идут через те же действия, что и кнопки.
local fmt = require("ui.format")
local protection = require("logic.protection")

local M = {}

M.NAME = "§6§lКомплекс§7§o"
M.MAX_SAY = 12   -- не больше строк за одну команду (каждая строка стоит тик)

local function say(app, text)
    local chat = app.proxies.chat
    if chat then pcall(chat.say, text) end
end

local function hasAccess(app, nick)
    for _, u in ipairs(app.cfg.users) do if u == nick then return true end end
    return false
end

local HELP = {
    "§e=== Команды Reactor Control ===",
    "§a@status §7— статус комплекса",
    "§a@start [n] §7— запустить все (или реактор n)",
    "§a@stop [n] §7— остановить все (или реактор n)",
    "§a@setporog <mB> §7— порог хладагента в МЭ",
    "§a@useradd <ник> §7/ §a@userdel <ник> §7— белый список",
    "§a@changelog [версия] §7— изменения",
    "§a@forget <n> [renum] §7— забыть пропавший реактор",
    "§a@info §7— о программе",
    "§a@restart §7— перезагрузить компьютер, §a@exit §7— выйти",
}

local commands = {}

commands["@help"] = function(app) for _, l in ipairs(HELP) do say(app, l) end end

commands["@status"] = function(app)
    local st, cfg = app.state, app.cfg
    local val, unit = fmt.si(st:totalRf(), cfg.metric)
    say(app, "§e=== Статус комплекса ===")
    say(app, "§aГенерация: §f" .. val .. " " .. unit .. "RF/t §aРасход: §f" .. fmt.compact((st:totalDrain())) .. " mB/s")
    local me = st.me
    say(app, "§aМЭ: §f" .. (me.present and (me.amount and (fmt.compact(me.amount) .. " mB") or "нет данных") or "§cне подключена")
        .. " §aпорог: §f" .. fmt.compact(cfg.threshold) .. " mB")
    for _, r in ipairs(st:list()) do
        local s
        if not r.online then s = "§cнет связи"
        elseif protection.hasFaults(r) then local _, t = protection.firstFault(r) s = "§c" .. t
        elseif r.running then s = "§2работает"
        else s = "§7остановлен" end
        local extra = ""
        if r.online and r.kind == "fluid" then
            local secs = protection.bufferSeconds(r, cfg)
            extra = " §7буфер " .. fmt.percent(r.coolant, r.coolantMax)
            if secs then extra = extra .. string.format(" (%.0f с)", secs) end
        end
        say(app, "§a#" .. r.slot .. " §f" .. (r.kind == "fluid" and "жидк." or "возд.") .. " " .. s .. extra)
    end
end

local function slotArg(app, args)
    local n = tonumber(args:match("^(%d+)"))
    if args:match("%S") and not n then return false end
    if n and not app.state.reactors[n] then return false end
    return true, n
end

-- Ответы о запуске/остановке берём из журнала, чтобы игрок видел ровно то же, что на экране
local function withLog(app, fn)
    local before = #app.log.entries
    local lastBefore = app.log.entries[before]
    local countBefore = lastBefore and lastBefore.count
    fn()
    local out, n = {}, 0
    for i = 1, #app.log.entries do
        local e = app.log.entries[i]
        if i > before or (e == lastBefore and e.count ~= countBefore) then
            local color = e.level == "error" and "§c" or e.level == "warn" and "§e" or (e.color == "ok" and "§2" or "§7")
            out[#out + 1] = color .. e.text
        end
    end
    for i = 1, math.min(#out, M.MAX_SAY) do say(app, out[i]) n = n + 1 end
    if #out > M.MAX_SAY then say(app, "§7...и ещё " .. (#out - M.MAX_SAY)) end
end

commands["@start"] = function(app, args, nick)
    local ok, n = slotArg(app, args)
    if not ok then say(app, "§cНеверный номер реактора!") return end
    withLog(app, function() app.actions:start(n, "чат: " .. nick) end)
end

commands["@stop"] = function(app, args, nick)
    local ok, n = slotArg(app, args)
    if not ok then say(app, "§cНеверный номер реактора!") return end
    withLog(app, function() app.actions:stop(n, "чат: " .. nick) end)
end

commands["@setporog"] = function(app, args)
    local v = tonumber(args:match("^(%d+)"))
    if not v then
        say(app, "§aИспользование: @setporog <значение в mB>, например @setporog 500000")
        return
    end
    app.actions:setThreshold(v)
    say(app, "§2Порог хладагента: " .. fmt.compact(app.cfg.threshold) .. " mB")
end

commands["@useradd"] = function(app, args)
    local name = args:match("^(%S+)")
    if not name then say(app, "§aИспользование: @useradd <ник>") return end
    local ok, err = app.actions:addUser(name)
    say(app, ok and ("§2Игрок §5" .. name .. " §2добавлен!") or ("§c" .. tostring(err)))
end

commands["@userdel"] = function(app, args)
    local name = args:match("^(%S+)")
    if not name then say(app, "§aИспользование: @userdel <ник>") return end
    local ok, err = app.actions:removeUser(name)
    say(app, ok and ("§2Игрок §5" .. name .. " §2удалён!") or ("§c" .. tostring(err)))
end

commands["@info"] = function(app)
    say(app, "§bReactor Control v" .. app.VERSION)
    say(app, "§aАвтор: §eP1KaChU337")
    say(app, "§aСайт: §1www.pzapps.uz")
    say(app, "§aGitHub: §1https://github.com/P1KaChU337/Reactor-Control-for-OpenComputers")
    say(app, "§aИгроки с доступом: §5" .. table.concat(app.cfg.users, ", "))
end

commands["@changelog"] = function(app, args)
    local list = app.remote and app.remote.changelog
    if not list then say(app, "§cИстория изменений ещё не загружена (нужна интернет-карта)") return end
    local want = args:match("^(%S+)")
    if want then
        for _, e in ipairs(list) do
            if e.version == want then
                say(app, "§eИзменения в версии " .. e.version .. ":")
                for i, c in ipairs(e.changes) do
                    if i > M.MAX_SAY then say(app, "§7...") break end
                    say(app, "§a- " .. c)
                end
                return
            end
        end
        say(app, "§cВерсия " .. want .. " не найдена")
    else
        local v = {}
        for _, e in ipairs(list) do v[#v + 1] = e.version end
        say(app, "§eВерсии: §a" .. table.concat(v, ", "))
        say(app, "§aИспользуйте: @changelog <версия>")
    end
end

commands["@forget"] = function(app, args)
    local n = tonumber(args:match("^(%d+)"))
    if not n then say(app, "§aИспользование: @forget <номер> [renum] — забыть пропавший реактор") return end
    local ok, err = app.actions:forget(n, args:find("renum", 1, true) ~= nil)
    say(app, ok and ("§2Реактор #" .. n .. " забыт") or ("§c" .. tostring(err)))
end

commands["@exit"] = function(app) say(app, "§cЗавершаю работу программы...") app:requestExit() end
commands["@restart"] = function(app) say(app, "§cПерезагрузка компьютера...") app:requestRestart() end

local function clean(s)
    return (tostring(s or ""):gsub("§.", ""):match("^%s*(.-)%s*$"))
end

-- Обработчик события chat_message(address, nick, message)
function M.handle(app, nick, message)
    local text = clean(message)
    local cmd = text:match("^(@%S+)")
    if not cmd then return false end
    cmd = cmd:lower()
    local fn = commands[cmd]
    if not fn then return false end
    if not hasAccess(app, nick) then
        say(app, "§cУ вас нет прав для управления реакторами!")
        app.log:warn("Чат: " .. tostring(nick) .. " без доступа пытался выполнить " .. cmd)
        return true
    end
    app.log:info("Чат: " .. nick .. ": " .. text)
    local args = text:match("^@%S+%s*(.*)$") or ""
    local ok, err = pcall(fn, app, args, nick)
    if not ok then
        say(app, "§cОшибка: " .. tostring(err))
        app.log:error("Чат-команда " .. cmd .. ": " .. tostring(err))
    end
    return true
end

function M.attach(app)
    app:on("chat_message", function(_, _, nick, message) M.handle(app, nick, message) end)
end

function M.greet(app)
    local chat = app.proxies.chat
    if not chat then return end
    pcall(chat.setName, M.NAME)
    say(app, "§2Reactor Control подключен! §aСписок команд: @help")
end

return M
