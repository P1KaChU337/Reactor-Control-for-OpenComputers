-- Единое состояние программы. Логика пишет сюда, интерфейс только читает.
-- version растёт при любом изменении: интерфейс по нему понимает, что пора перерисоваться.
local rate = require("logic.rate")

local State = {}
State.__index = State

State.MAX_REACTORS = 6

function State.new(clock)
    local self = setmetatable({}, State)
    self.clock = clock
    self.startedAt = clock()
    self.version = 0
    self.reactors = {}   -- slot -> reactor
    self.me = {present = false, amount = nil, lastOk = nil, cooldownUntil = 0, error = nil}
    self.flux = {present = false, input = nil, output = nil, buffer = nil}
    self.chat = {present = false}
    return self
end

function State:touch() self.version = self.version + 1 end

function State:newReactor(slot, address)
    local r = {
        slot = slot,
        address = address,
        online = true,
        kind = nil,            -- "fluid" | "air"
        running = false,
        desired = false,       -- пользователь хочет, чтобы реактор работал
        halted = false,        -- остановлен защитой и ждёт автозапуска
        faults = {},           -- код -> {since=, text=}
        temp = nil, maxTemp = nil,
        rf = 0,
        coolant = nil, coolantMax = nil,
        consumeNominal = nil,
        level = nil,
        rods = nil,            -- {min, max, sum, count, maxFuel}
        drain = rate.drain(),
        burn = rate.burn(),
        restarts = {},         -- время автозапусков (для ограничения)
        lastSeen = self.clock(),
    }
    self.reactors[slot] = r
    self:touch()
    return r
end

function State:removeReactor(slot)
    self.reactors[slot] = nil
    self:touch()
end

-- Реакторы по порядку номеров
function State:list()
    local res = {}
    for slot = 1, State.MAX_REACTORS do
        if self.reactors[slot] then res[#res + 1] = self.reactors[slot] end
    end
    return res
end

function State:count()
    local n = 0
    for _ in pairs(self.reactors) do n = n + 1 end
    return n
end

function State:totalRf()
    local s = 0
    for _, r in pairs(self.reactors) do if r.running then s = s + (r.rf or 0) end end
    return s
end

-- Реальный расход хладагента всеми работающими жидкостными реакторами (mB/с, по замерам)
function State:totalDrain()
    local s, known = 0, true
    for _, r in pairs(self.reactors) do
        if r.running and r.kind == "fluid" then
            local d = r.drain:rate()
            if d then s = s + d else known = false end
        end
    end
    return s, known
end

function State:anyRunning()
    for _, r in pairs(self.reactors) do if r.running then return true end end
    return false
end

function State:uptime() return self.clock() - self.startedAt end

return State
