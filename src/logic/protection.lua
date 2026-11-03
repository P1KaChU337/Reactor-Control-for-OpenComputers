-- Правила защиты реакторов. Чистая логика: читает состояние и конфиг, ставит/снимает аварии
-- (r.faults) и возвращает список команд. Сами команды выполняет core.actions через hw.
--
-- Аварии:
--   me_low     хладагента в ME не больше порога                       (жидкостные)
--   me_lost    нет данных из ME дольше meLostSec (или ME не подключена)  (жидкостные)
--   buffer_low буфер реактора кончится быстрее, чем через bufferStopSec  (жидкостные, работающие)
--   unstable   слишком много автозапусков подряд, нужен ручной запуск
--   offline    компонент реактора пропал (ставит discovery)
--
-- Реактор может работать, только если у него нет аварий.
-- Остановленный защитой реактор (r.halted) запускается обратно сам, когда аварии сняты (config.autoRestart).
local M = {}

M.TEXT = {
    me_low = "Мало хладагента в МЭ",
    me_lost = "Нет данных из МЭ",
    buffer_low = "Мало жидкости в буфере",
    unstable = "Частые аварии",
    offline = "Нет связи",
}

local function setFault(r, code, now, events)
    if not r.faults[code] then
        r.faults[code] = {since = now, text = M.TEXT[code]}
        events[#events + 1] = {level = "warn", slot = r.slot, text = "Реактор #" .. r.slot .. ": " .. M.TEXT[code]}
        return true
    end
end

local function clearFault(r, code, events)
    if r.faults[code] then
        r.faults[code] = nil
        events[#events + 1] = {level = "info", slot = r.slot, text = "Реактор #" .. r.slot .. ": авария снята (" .. M.TEXT[code] .. ")"}
        return true
    end
end

function M.firstFault(r)
    -- порядок важности для показа на экране
    for _, code in ipairs({"offline", "unstable", "me_lost", "me_low", "buffer_low"}) do
        if r.faults[code] then return code, r.faults[code].text end
    end
end

function M.hasFaults(r) return next(r.faults) ~= nil end

-- Реальный расход буфера, mB/с: замер, а пока его нет — номинал x drainFactor
function M.drainRate(r, cfg)
    local d = r.drain and r.drain:rate()
    if d and d > 0 then return d, true end
    if r.consumeNominal and r.consumeNominal > 0 then return r.consumeNominal * cfg.drainFactor, false end
end

-- Сколько секунд проработает реактор на текущем буфере (nil, если оценить нечем)
function M.bufferSeconds(r, cfg)
    local d = M.drainRate(r, cfg)
    if not d or not r.coolant then return nil end
    return r.coolant / d
end

-- evaluate(state, config, now) -> commands {{op="stop"|"start", slot=, reason=}}, events {{level, text, slot}}
function M.evaluate(state, cfg, now)
    local commands, events = {}, {}
    local me = state.me

    -- состояние ME одно на всех
    local meLost = (not me.present)
        or (me.lastOk == nil and now - state.startedAt > cfg.meLostSec)
        or (me.lastOk ~= nil and now - me.lastOk > cfg.meLostSec)
    local meLow = (not meLost) and me.amount ~= nil and me.amount <= cfg.threshold

    for _, r in ipairs(state:list()) do
        if r.online then
            local fluid = r.kind == "fluid"

            if fluid then
                if meLost then setFault(r, "me_lost", now, events) else clearFault(r, "me_lost", events) end
                if meLow then setFault(r, "me_low", now, events) else clearFault(r, "me_low", events) end

                -- буфер: в секундах работы
                local secs = M.bufferSeconds(r, cfg)
                if r.running and r.coolant then
                    local inGrace = r.startedAt and now - r.startedAt < cfg.startGraceSec
                    local limit = inGrace and cfg.bufferHardStopSec or cfg.bufferStopSec
                    local low
                    if secs then low = secs < limit
                    elseif r.coolantMax and r.coolantMax > 0 then low = r.coolant / r.coolantMax < cfg.bufferStopPct end
                    if low then setFault(r, "buffer_low", now, events) end
                end
                local bf = r.faults.buffer_low
                if bf and not r.running then
                    -- Остановленный реактор буфер не доливает. Снимаем аварию, если ME в порядке, прошло
                    -- bufferRetrySec и буфера хватит дождаться первого долива. Иначе — только ручной запуск.
                    local enough = secs and secs >= cfg.bufferRestartSec
                    local full = r.coolant and r.coolantMax and r.coolantMax > 0 and r.coolant / r.coolantMax >= cfg.bufferResumePct
                    local waited = now - bf.since >= cfg.bufferRetrySec and not meLost and not meLow
                    if full or (waited and enough) then
                        clearFault(r, "buffer_low", events)
                    elseif waited and not bf.manualHint then
                        bf.manualHint = true
                        events[#events + 1] = {level = "warn", slot = r.slot, text = string.format(
                            "Реактор #%d: буфера мало (%s), в простое он не доливается. Нужен ручной запуск",
                            r.slot, secs and string.format("%.1f с", secs) or "?")}
                    end
                end
            else
                -- воздушному реактору жидкость не нужна
                clearFault(r, "me_lost", events)
                clearFault(r, "me_low", events)
                clearFault(r, "buffer_low", events)
            end

            -- команды
            if M.hasFaults(r) then
                if r.running then
                    local code, text = M.firstFault(r)
                    commands[#commands + 1] = {op = "stop", slot = r.slot, reason = code}
                    if r.desired then r.halted = true end
                end
            elseif r.halted and r.desired and not r.running and cfg.autoRestart then
                -- ограничение частоты автозапусков
                local recent = {}
                for _, t in ipairs(r.restarts) do
                    if now - t <= cfg.autoRestartWindowSec then recent[#recent + 1] = t end
                end
                r.restarts = recent
                if #recent >= cfg.maxAutoRestarts then
                    setFault(r, "unstable", now, events)
                else
                    r.restarts[#r.restarts + 1] = now
                    commands[#commands + 1] = {op = "start", slot = r.slot, reason = "auto"}
                    events[#events + 1] = {level = "info", slot = r.slot, text = "Реактор #" .. r.slot .. ": автозапуск"}
                end
            end
        end
    end
    return commands, events
end

return M
