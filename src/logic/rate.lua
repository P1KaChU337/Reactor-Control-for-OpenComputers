-- Измерители скорости по наблюдениям, без знания внутренностей мода.
local M = {}

-------------------------------------------------------------------------------
-- DrainMeter: реальный расход буфера хладагента (mB/с).
-- Буфер ходит пилой: каждую секунду -D, раз в несколько секунд долив +kD. Средняя разность тут
-- бесполезна (долив её обнуляет), поэтому берём МЕДИАНУ отрицательных скоростей за последние N замеров.
local Drain = {}
Drain.__index = Drain

function M.drain(size)
    return setmetatable({size = size or 15, samples = {}, lastT = nil, lastV = nil}, Drain)
end

function Drain:reset() self.samples = {}; self.lastT = nil; self.lastV = nil end

-- running: учитывать только пока реактор работает
function Drain:add(t, value, running)
    if not running or type(value) ~= "number" then self.lastT, self.lastV = nil, nil return end
    if self.lastT then
        local dt = t - self.lastT
        if dt >= 0.5 and dt <= 5 then
            local r = (self.lastV - value) / dt
            if r > 0 then
                local s = self.samples
                s[#s + 1] = r
                if #s > self.size then table.remove(s, 1) end
            end
        end
    end
    self.lastT, self.lastV = t, value
end

-- -> mB/с или nil, пока замеров мало
function Drain:rate()
    local n = #self.samples
    if n < 3 then return nil end
    local s = {}
    for i = 1, n do s[i] = self.samples[i] end
    table.sort(s)
    if n % 2 == 1 then return s[(n + 1) / 2] end
    return (s[n / 2] + s[n / 2 + 1]) / 2
end

-------------------------------------------------------------------------------
-- BurnMeter: скорость выгорания топлива на один стержень (ед./с).
-- Наниты и прочие ускорители меняют скорость, поэтому она не зашивается, а усредняется
-- по последним windowSec секундам РАБОТЫ реактора. Замена стержня (топливо выросло) или
-- изменение числа стержней начинают отсчёт заново.
local Burn = {}
Burn.__index = Burn

function M.burn(windowSec)
    return setmetatable({window = windowSec or 600, pieces = {}, last = nil, sample = nil}, Burn)
end

-- sample = {min=, max=, sum=, count=} — сводка по стержням (см. hw.reactor.rodsSummary)
function Burn:add(t, sample, running)
    local last = self.last
    if running and last and last.running and sample and last.sample
        and sample.count == last.sample.count and sample.count > 0 then
        local dt = t - last.t
        local burned = (last.sample.sum - sample.sum) / sample.count
        if dt > 0 and burned >= 0 then
            local p = self.pieces
            p[#p + 1] = {dt = dt, burned = burned}
            local total = 0
            for i = #p, 1, -1 do
                total = total + p[i].dt
                if total > self.window and i > 1 then
                    for _ = 1, i - 1 do table.remove(p, 1) end
                    break
                end
            end
        elseif burned < 0 then
            self.pieces = {} -- стержень заменили
        end
    elseif sample and last and last.sample and sample.count ~= last.sample.count then
        self.pieces = {}
    end
    self.last = {t = t, sample = sample, running = running}
end

-- -> ед./с на стержень или nil
function Burn:rate()
    local dt, burned = 0, 0
    for _, p in ipairs(self.pieces) do dt = dt + p.dt; burned = burned + p.burned end
    if dt < 1 or burned <= 0 then return nil end
    return burned / dt
end

-- Оценка на момент now (между редкими замерами топливо "догорает" по измеренной скорости).
-- running/stoppedAt — ТЕКУЩЕЕ состояние реактора: после остановки отсчёт замирает на моменте остановки,
-- даже если последний замер стержней был сделан, пока реактор ещё работал.
-- -> secondsFirst (до пустого первого стержня), secondsLast (до пустого последнего) или nil
function Burn:remaining(now, running, stoppedAt)
    local r = self:rate()
    local last = self.last
    if not r or not last or not last.sample or last.sample.count == 0 then return nil end
    local untilT = now
    if running == false then untilT = math.max(last.t, math.min(now, stoppedAt or last.t)) end
    local spent = last.running and r * math.max(0, untilT - last.t) or 0
    local first = math.max(0, last.sample.min - spent) / r
    local lastRod = math.max(0, last.sample.max - spent) / r
    return first, lastRod
end

return M
