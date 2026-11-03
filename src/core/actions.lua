-- Все действия над комплексом. Один вход и для кнопок, и для чат-команд, и для защиты.
local reactorHw = require("hw.reactor")
local protection = require("logic.protection")

local Actions = {}
Actions.__index = Actions

-- app: {state, cfg, saveConfig(), log, proxies, scheduler, computer}
function Actions.new(app) return setmetatable({app = app}, Actions) end

local function targets(state, slot)
    if slot then
        local r = state.reactors[slot]
        return r and {r} or {}
    end
    return state:list()
end

local function doStart(self, r)
    local proxy = self.app.proxies.reactors[r.slot]
    local ok, err = reactorHw.activate(proxy)
    if ok then
        r.running = true
        r.halted = false
        r.startedAt = self.app.clock()
        self.app.state:touch()
        return true
    end
    self.app.log:error("Реактор #" .. r.slot .. ": не удалось запустить: " .. tostring(err))
    return false
end

local function doStop(self, r)
    local proxy = self.app.proxies.reactors[r.slot]
    local ok, err = reactorHw.deactivate(proxy)
    if ok then
        r.running = false
        r.stoppedAt = self.app.clock()
        self.app.state:touch()
        return true
    end
    self.app.log:error("Реактор #" .. r.slot .. ": не удалось остановить: " .. tostring(err))
    return false
end

local function kindName(r)
    return r.kind == "fluid" and "жидкостный" or r.kind == "air" and "воздушный" or "?"
end
Actions.kindName = kindName

-- Запуск по просьбе пользователя (slot = nil: все)
function Actions:start(slot, who)
    local state, log, cfg = self.app.state, self.app.log, self.app.cfg
    local list = targets(state, slot)
    if #list == 0 then log:warn(slot and ("Реактора #" .. slot .. " нет") or "Не подключено ни одного реактора!") return end
    if not slot then log:info("Запуск реакторов...") end
    local started, already, waiting, offline = 0, 0, 0, 0
    for _, r in ipairs(list) do
        if not r.online then
            offline = offline + 1
            log:warn("Реактор #" .. r.slot .. ": нет связи, запуск невозможен")
        else
            r.desired = true
            -- ручной запуск сбрасывает "частые аварии" и аварию буфера: пользователь берёт решение на себя,
            -- защита всё равно остановит реактор, если буфер начнёт пустеть
            r.faults.unstable = nil
            r.faults.buffer_low = nil
            r.restarts = {}
            if r.running then
                already = already + 1
                if slot then log:warn("Реактор #" .. r.slot .. " уже запущен") end
            elseif protection.hasFaults(r) then
                local _, text = protection.firstFault(r)
                r.halted = true
                waiting = waiting + 1
                log:warn("Реактор #" .. r.slot .. " не запущен: " .. text
                    .. (cfg.autoRestart and ". Запустится сам, когда авария пройдёт" or ""))
            elseif doStart(self, r) then
                started = started + 1
                log:ok("Реактор #" .. r.slot .. " (" .. kindName(r) .. ") запущен!")
            end
        end
    end
    if not slot then
        if started == 0 and waiting == 0 and offline == 0 then
            log:warn("Все реакторы уже запущены!")
        elseif started > 0 and started + already == #list then
            log:ok("Реакторы запущены! (" .. (started + already) .. "/" .. #list .. ")")
        elseif started > 0 then
            log:warn("Запущено " .. started .. ", работает " .. (started + already) .. " из " .. #list)
        end
    end
    state:touch()
end

function Actions:stop(slot, who)
    local state, log = self.app.state, self.app.log
    local list = targets(state, slot)
    if #list == 0 then log:warn(slot and ("Реактора #" .. slot .. " нет") or "Не подключено ни одного реактора!") return end
    if not slot then log:info("Отключение реакторов...") end
    local stopped, cancelled = 0, 0
    for _, r in ipairs(list) do
        local wasWaiting = r.halted and r.desired and not r.running
        r.desired = false
        r.halted = false
        if r.online and r.running then
            if doStop(self, r) then
                stopped = stopped + 1
                log:ok("Реактор #" .. r.slot .. " (" .. kindName(r) .. ") отключен!")
            end
        elseif wasWaiting then
            cancelled = cancelled + 1
            log:info("Реактор #" .. r.slot .. ": автозапуск отменён")
        elseif slot then
            log:warn("Реактор #" .. r.slot .. " уже отключен")
        end
    end
    if not slot then
        if stopped == 0 and cancelled == 0 then log:warn("Реакторы уже отключены!")
        else log:ok("Реакторы отключены!") end
    end
    state:touch()
end

function Actions:toggle(slot, who)
    local r = self.app.state.reactors[slot]
    if not r then return end
    if r.running or r.desired then self:stop(slot, who) else self:start(slot, who) end
end

-- Команды защиты
function Actions:apply(commands)
    for _, c in ipairs(commands) do
        local r = self.app.state.reactors[c.slot]
        if r and r.online then
            if c.op == "stop" and r.running then
                doStop(self, r)
                self.app.log:warn("Реактор #" .. r.slot .. " остановлен защитой: " .. tostring(protection.TEXT[c.reason] or c.reason))
            elseif c.op == "start" and not r.running and c.reason == "auto" then
                if doStart(self, r) then self.app.log:ok("Реактор #" .. r.slot .. " (" .. kindName(r) .. ") запущен автоматически") end
            elseif c.op == "start" and not r.running then
                if doStart(self, r) then self.app.log:ok("Реактор #" .. r.slot .. " запущен") end
            end
        end
    end
end

-- Наблюдаемое состояние разошлось с ожидаемым (реактор включили/выключили не мы, кончилось топливо)
function Actions:observeRunning(r, observed)
    if observed == nil or observed == r.running then return end
    local log = self.app.log
    if observed then
        r.running = true
        r.desired = true
        r.halted = false
        log:info("Реактор #" .. r.slot .. " запущен не программой")
    else
        r.running = false
        r.stoppedAt = self.app.clock()
        if not protection.hasFaults(r) then
            r.desired = false
            r.halted = false
            local noFuel = r.rods and r.rods.count > 0 and r.rods.max <= 0
            log:warn("Реактор #" .. r.slot .. (noFuel and " остановился: кончилось топливо" or " остановлен не программой"))
        end
    end
    self.app.state:touch()
end

function Actions:refreshMe()
    local me, sched = self.app.state.me, self.app.scheduler
    local wait = math.max(0, (me.cooldownUntil or 0) - self.app.clock())
    sched:runSoon("me", wait)
    if wait > 0 then
        self.app.log:info(string.format("МЭ обновится через %d с (ограничение сервера)", math.ceil(wait)))
    end
end

function Actions:setThreshold(v)
    v = tonumber(v)
    if not v or v < 0 then return false end
    self.app.cfg.threshold = math.floor(v)
    self.app.saveConfig()
    self.app.log:info("Порог жидкости: " .. self.app.cfg.threshold .. " mB")
    self.app.state:touch()
    return true
end

-- Белый список игроков -> computer.addUser/removeUser
function Actions:syncUsers()
    local cfg, log, computer = self.app.cfg, self.app.log, self.app.computer
    if not computer or not computer.addUser then return end
    local want, have = {}, {}
    for _, n in ipairs(cfg.users) do want[n] = true end
    for _, n in ipairs(cfg.usersApplied) do have[n] = true end
    local changed = false
    for _, n in ipairs(cfg.users) do
        if not have[n] then
            local ok, err = computer.addUser(n)
            if ok then
                cfg.usersApplied[#cfg.usersApplied + 1] = n
                log:ok("Добавлен пользователь: " .. n)
                changed = true
            else
                log:warn("Не удалось добавить " .. n .. ": " .. tostring(err))
            end
        end
    end
    for i = #cfg.usersApplied, 1, -1 do
        local n = cfg.usersApplied[i]
        if not want[n] then
            computer.removeUser(n)
            table.remove(cfg.usersApplied, i)
            log:info("Удалён пользователь: " .. n)
            changed = true
        end
    end
    if #cfg.users == 0 then log:warn("Компьютер не защищён: добавьте игроков в белый список") end
    if changed then self.app.saveConfig() end
end

function Actions:addUser(name)
    local cfg = self.app.cfg
    name = tostring(name or ""):match("^%s*(.-)%s*$")
    if #name < 3 or #name > 16 then return false, "Ник должен быть от 3 до 16 символов" end
    for _, n in ipairs(cfg.users) do if n == name then return false, "Уже в белом списке" end end
    cfg.users[#cfg.users + 1] = name
    self.app.saveConfig()
    self:syncUsers()
    return true
end

function Actions:removeUser(name)
    local cfg = self.app.cfg
    for i, n in ipairs(cfg.users) do
        if n == name then
            table.remove(cfg.users, i)
            self.app.saveConfig()
            self:syncUsers()
            return true
        end
    end
    return false, "Нет в белом списке"
end

return Actions
