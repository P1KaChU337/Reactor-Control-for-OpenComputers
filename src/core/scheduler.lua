-- Планировщик периодических задач по монотонным часам (computer.uptime).
-- Задачи разных групп сдвигаются (offset), чтобы вызовы компонентов не сваливались в один тик.
local Scheduler = {}
Scheduler.__index = Scheduler

-- onError(task, err) вызывается, если задача упала; планировщик при этом продолжает работу
function Scheduler.new(clock, onError)
    return setmetatable({clock = clock, tasks = {}, onError = onError}, Scheduler)
end

-- every(name, interval, fn [, offset]) — fn(now) каждые interval секунд, первый раз через offset (по умолчанию сразу)
function Scheduler:every(name, interval, fn, offset)
    assert(interval and interval > 0, "interval must be > 0")
    self.tasks[name] = {name = name, interval = interval, fn = fn, due = self.clock() + (offset or 0)}
    return name
end

-- after(name, delay, fn) — один раз
function Scheduler:after(name, delay, fn)
    self.tasks[name] = {name = name, fn = fn, due = self.clock() + delay, once = true}
    return name
end

function Scheduler:cancel(name) self.tasks[name] = nil end

function Scheduler:has(name) return self.tasks[name] ~= nil end

-- Перенести ближайший запуск задачи (например, "обновить ME сейчас")
function Scheduler:runSoon(name, delay)
    local t = self.tasks[name]
    if t then t.due = self.clock() + (delay or 0) end
end

function Scheduler:timeUntilNext()
    local now, best = self.clock(), math.huge
    for _, t in pairs(self.tasks) do
        local d = t.due - now
        if d < best then best = d end
    end
    if best < 0 then best = 0 end
    return best
end

-- Выполнить все наступившие задачи. Возвращает количество выполненных.
function Scheduler:run()
    local now = self.clock()
    local due = {}
    for _, t in pairs(self.tasks) do
        if t.due <= now + 1e-9 then due[#due + 1] = t end
    end
    table.sort(due, function(a, b) if a.due ~= b.due then return a.due < b.due end return a.name < b.name end)
    for _, t in ipairs(due) do
        if self.tasks[t.name] == t then
            if t.once then
                self.tasks[t.name] = nil
            else
                -- без накопления дрейфа: следующий срок от запланированного, но не в прошлом
                t.due = t.due + t.interval
                if t.due <= now then t.due = now + t.interval end
            end
            local ok, err = pcall(t.fn, now)
            if not ok and self.onError then self.onError(t, err) end
        end
    end
    return #due
end

return Scheduler
