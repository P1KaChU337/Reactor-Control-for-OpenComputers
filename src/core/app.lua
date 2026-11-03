-- Приложение: собирает модули, расписывает опрос железа и крутит единый цикл событий.
-- Защита работает в этом же цикле всегда, что бы ни было открыто на экране.
local Log = require("core.log")
local config = require("core.config")
local State = require("core.state")
local Scheduler = require("core.scheduler")
local Actions = require("core.actions")
local protection = require("logic.protection")
local discovery = require("hw.discovery")
local reactorHw = require("hw.reactor")
local meHw = require("hw.me")
local fluxHw = require("hw.flux")

local App = {}
App.__index = App

App.VERSION = "2.0.0-dev"
App.VERSION_SHORT = "2.0-dev"

-- Интервалы опроса (секунды) и сдвиги, чтобы группы не попадали в один тик
App.POLL = {
    coolant = {1, 0},     -- буфер работающих жидкостных: защита
    protect = {1, 0.05},
    running = {5, 0.3},   -- hasWork: реактор могли включить/выключить руками
    stats   = {10, 0.55}, -- генерация, температура
    rods    = {30, 0.8},  -- стержни: время до распада
    static  = {60, 0.9},  -- тип, буфер, номинал
    me      = {60, 0.15},
    flux    = {5, 0.4},   -- direct, бесплатно
    scan    = {30, 0.95}, -- на случай пропущенных component_added/removed
    logflush = {10, 0.6},
}

-- deps: component, computer, event, clock (по умолчанию computer.uptime),
--       configPath, legacyConfigPath, logPath, onStartPolicy
function App.new(deps)
    local self = setmetatable({}, App)
    self.component = deps.component
    self.computer = deps.computer
    self.event = deps.event
    self.clock = deps.clock or deps.computer.uptime
    self.configPath = deps.configPath
    self.log = Log.new({path = deps.logPath, clock = self.clock, keep = 200})
    local cfg, info = config.load(deps.configPath, deps.legacyConfigPath)
    self.cfg = cfg
    self.cfgInfo = info
    self.state = State.new(self.clock)
    self.proxies = {reactors = {}}
    self.scheduler = Scheduler.new(self.clock, function(task, err)
        self.log:error("Задача " .. task.name .. ": " .. tostring(err))
    end)
    self.saveConfig = function()
        local ok, err = config.save(self.cfg, self.configPath)
        if not ok then self.log:error("Не удалось сохранить настройки: " .. tostring(err)) end
    end
    self.actions = Actions.new(self)
    self.handlers = {}   -- имя события -> функция (интерфейс и чат добавляют свои)
    self.running = false
    return self
end

function App:on(name, fn) self.handlers[name] = fn end

-- Один шаг защиты: оценить и выполнить команды
function App:protect()
    local cmds, events = protection.evaluate(self.state, self.cfg, self.clock())
    for _, e in ipairs(events) do self.log:write(e.level, e.text, e.color and {color = e.color}) end
    if #cmds > 0 then self.actions:apply(cmds) end
    if #events > 0 or #cmds > 0 then self.state:touch() end
end

function App:pollMe()
    local now = self.clock()
    local me = self.state.me
    if not self.proxies.me then return end
    if now < (me.cooldownUntil or 0) then
        self.scheduler:runSoon("me", me.cooldownUntil - now)
        return
    end
    local res = meHw.read(self.proxies.me, me, now, self.cfg.coolantName)
    if res == "cooldown" then
        self.scheduler:runSoon("me", me.cooldownUntil - now)
    elseif res == "ok" and me.amount and me.amount <= self.cfg.threshold then
        -- пока хладагента мало, проверяем чаще, чтобы быстрее запустить реакторы обратно
        self.scheduler:runSoon("me", 20)
    elseif res == "error" then
        self.log:warn("МЭ: " .. tostring(me.error))
    end
    self.state:touch()
end

function App:forEachOnline(fn)
    for slot, r in pairs(self.state.reactors) do
        local p = self.proxies.reactors[slot]
        if r.online and p then fn(r, p) end
    end
end

function App:scan()
    local changed = discovery.scan(self.component, self.state, self.cfg, self.log, self.proxies)
    -- новые реакторы: сразу статику и состояние
    self:forEachOnline(function(r, p)
        if r.needStatic then
            r.needStatic = false
            reactorHw.pollStatic(r, p)
            local obs = reactorHw.pollRunning(p)
            if obs ~= nil then r.running = obs end
            reactorHw.pollStats(r, p)
            reactorHw.pollRods(r, p, self.clock())
        end
    end)
    if changed then self.saveConfig() end
    return changed
end

function App:schedule()
    local P, s = App.POLL, self.scheduler
    s:every("coolant", P.coolant[1], function(now)
        self:forEachOnline(function(r, p)
            -- работающие жидкостные — для защиты; остановленные защитой — чтобы решать об автозапуске по свежим данным
            if r.kind == "fluid" and (r.running or r.halted or r.faults.buffer_low or r.faults.locked) then
                reactorHw.pollCoolant(r, p, now)
            end
        end)
        self.state:touch()
    end, P.coolant[2])
    s:every("protect", P.protect[1], function() self:protect() end, P.protect[2])
    s:every("running", P.running[1], function()
        self:forEachOnline(function(r, p) self.actions:observeRunning(r, reactorHw.pollRunning(p)) end)
    end, P.running[2])
    s:every("stats", P.stats[1], function()
        self:forEachOnline(function(r, p) reactorHw.pollStats(r, p) end)
        self.state:touch()
    end, P.stats[2])
    s:every("rods", P.rods[1], function(now)
        self:forEachOnline(function(r, p) reactorHw.pollRods(r, p, now) end)
        self.state:touch()
    end, P.rods[2])
    s:every("static", P.static[1], function()
        self:forEachOnline(function(r, p) reactorHw.pollStatic(r, p) end)
    end, P.static[2])
    s:every("me", P.me[1], function() self:pollMe() end, P.me[2])
    s:every("flux", P.flux[1], function()
        if fluxHw.read(self.proxies.flux, self.state.flux) then self.state:touch() end
    end, P.flux[2])
    s:every("scan", P.scan[1], function() self:scan() end, P.scan[2])
    s:every("logflush", P.logflush[1], function() self.log:flush() end, P.logflush[2])
end

function App:init()
    local log = self.log
    log:title("------Reactor Control v" .. App.VERSION_SHORT .. "------")
    log:title("Автор приложения: P1KaChU337")
    log:title("Версия приложения: " .. App.VERSION)
    for _, w in ipairs(self.cfgInfo.warnings) do log:warn(w) end
    if self.cfgInfo.source == "legacy" then
        log:ok("Настройки перенесены из старой версии")
        self.saveConfig()
    end
    log:setFileLevel(self.cfg.debugLog and "debug" or "info")
    self:scan()
    local st = self.state
    log:title("Реакторов найдено: " .. st:count())
    log:title("МЭ-сеть: " .. (st.me.present and "Подключена" or "Не подключена"))
    log:title("Flux-сеть: " .. (st.flux.present and "Подключена" or "Не подключена"))
    log:title("ChatBox: " .. (st.chat.present and "Подключен" or "Не подключен"))
    log:title("----------------------------------")
    -- Как в старой версии: при старте программы всё останавливается, запуск — кнопкой
    if self.cfg.onStart ~= "adopt" then
        self:forEachOnline(function(r, p)
            if r.running then reactorHw.deactivate(p) r.running = false end
        end)
    else
        self:forEachOnline(function(r) if r.running then r.desired = true end end)
    end
    self.actions:syncUsers()
    self:schedule()
    self.state:touch()
end

-- Один проход цикла: ждать событие не дольше, чем до ближайшей задачи
function App:step(maxWait)
    local wait = self.scheduler:timeUntilNext()
    if self.waitHint then wait = math.min(wait, self.waitHint()) end
    if maxWait and wait > maxWait then wait = maxWait end
    local ev = table.pack(self.event.pull(wait))
    local name = ev[1]
    if name then
        if name == "component_added" or name == "component_removed" then
            self.scheduler:runSoon("scan", 0.5)
        elseif name == "interrupted" then
            self.running = false
        end
        local h = self.handlers[name]
        if h then
            local ok, err = pcall(h, table.unpack(ev, 1, ev.n))
            if not ok then self.log:error("Обработчик " .. name .. ": " .. tostring(err)) end
        end
    end
    self.scheduler:run()
    if self.onFrame then
        local ok, err = pcall(self.onFrame)
        if not ok then self.log:error("Отрисовка: " .. tostring(err)) end
    end
end

function App:requestExit() self.exitReason = "exit" self.running = false end
function App:requestRestart() self.exitReason = "restart" self.running = false end

function App:shutdown()
    self.log:warn("Завершаю работу программы...")
    self.actions:stop(nil, "выход")
    self.log:flush()
end

function App:run()
    self.running = true
    while self.running do
        local ok, err = xpcall(function() self:step() end, debug.traceback)
        if not ok then
            if tostring(err):find("interrupted") then break end
            -- ошибка одного шага не роняет программу и не перезапускает её
            self.log:error("Ошибка цикла: " .. tostring(err):sub(1, 300))
        end
    end
    self:shutdown()
end

return App
