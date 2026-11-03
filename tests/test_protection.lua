local protection = require("logic.protection")
local State = require("core.state")
local config = require("core.config")
local T = T

local MAX, D = 1080000, 96768

-- Модель: реакторы + ME, шаг = 1 секунда. Возвращает окружение для тестов.
local function world(opts)
    opts = opts or {}
    local c = T.clock(0)
    local st = State.new(c.fn)
    local cfg = config.defaults()
    for k, v in pairs(opts.cfg or {}) do cfg[k] = v end
    st.me.present = true
    st.me.amount = opts.me or 10000000
    st.me.lastOk = 0
    local w = {c = c, st = st, cfg = cfg, supply = {}, log = {}}
    for i = 1, (opts.n or 1) do
        local r = st:newReactor(i, "addr" .. i)
        r.kind = (opts.air and opts.air[i]) and "air" or "fluid"
        r.coolantMax = MAX
        r.coolant = MAX - D
        r.consumeNominal = 967
        r.desired = true
        r.running = true
        r.startedAt = -100
        w.supply[i] = true
    end
    -- один шаг: физика реактора, замер, защита, выполнение команд
    function w.step()
        c.t = c.t + 1
        local sec = c.t
        for _, r in ipairs(st:list()) do
            if r.running and r.kind == "fluid" then
                if w.supply[r.slot] and sec % 3 == 0 then r.coolant = MAX end
                r.coolant = math.max(0, r.coolant - D)
                r.drain:add(sec, r.coolant, true)
            end
        end
        st.me.lastOk = w.meOk == false and st.me.lastOk or sec
        local cmds, events = protection.evaluate(st, cfg, sec)
        for _, e in ipairs(events) do w.log[#w.log + 1] = e.text end
        for _, cmd in ipairs(cmds) do
            local r = st.reactors[cmd.slot]
            if cmd.op == "stop" then r.running = false
            elseif cmd.op == "start" then r.running = true r.halted = false r.startedAt = sec end
        end
    end
    function w.run(n) for _ = 1, n do w.step() end end
    function w.r(i) return st.reactors[i or 1] end
    return w
end

T.test("защита: нормальный цикл буфера не трогаем", function()
    local w = world()
    w.run(60)
    T.ok(w.r().running); T.no(next(w.r().faults))
end)

T.test("защита: один пропущенный долив не останавливает", function()
    local w = world()
    w.run(20)
    w.supply[1] = false; w.run(3); w.supply[1] = true
    w.run(20)
    T.ok(w.r().running, "реактор работает"); T.no(w.r().faults.buffer_low)
end)

T.test("защита: долгий перебой -> стоп, буфер не ниже жёсткого порога", function()
    local w = world()
    w.run(20)
    w.supply[1] = false
    local minSecs = math.huge
    for _ = 1, 20 do
        w.step()
        if w.r().running then minSecs = math.min(minSecs, w.r().coolant / D) end
    end
    T.no(w.r().running); T.ok(w.r().faults.buffer_low); T.ok(w.r().halted)
    T.ok(minSecs >= 2, "минимум буфера при работе: " .. minSecs .. " с")
end)

T.test("защита: после перебоя автозапуск, если буфера хватает", function()
    local w = world()
    w.run(21)
    w.supply[1] = false
    w.run(10)
    T.no(w.r().running)
    local left = w.r().coolant / D
    w.supply[1] = true
    w.run(40)
    if left >= w.cfg.bufferRestartSec then
        T.ok(w.r().running, "запустился сам")
    else
        T.no(w.r().running, "буфера мало — ждёт ручного запуска")
        local hint = false
        for _, l in ipairs(w.log) do if l:find("Нужен ручной запуск") then hint = true end end
        T.ok(hint, "подсказка про ручной запуск")
    end
end)

T.test("защита: нехватка в ME останавливает только жидкостные, потом автозапуск", function()
    local w = world({n = 2, air = {[2] = true}})
    w.run(5)
    w.st.me.amount = 1000
    w.step()
    T.no(w.r(1).running); T.ok(w.r(1).faults.me_low); T.ok(w.r(2).running, "воздушный работает")
    w.st.me.amount = 10000000
    w.step()
    T.ok(w.r(1).running, "автозапуск")
end)

T.test("защита: autoRestart выключен — остаётся стоять", function()
    local w = world({cfg = {autoRestart = false}})
    w.st.me.amount = 0; w.step()
    w.st.me.amount = 10000000; w.run(5)
    T.no(w.r().running); T.ok(w.r().halted)
end)

T.test("защита: пауза ME не авария, долгое отсутствие данных — авария", function()
    local w = world()
    w.meOk = false
    w.run(100)
    T.ok(w.r().running, "100 с без данных ME — ещё норма")
    w.run(100)
    T.no(w.r().running); T.ok(w.r().faults.me_lost)
end)

T.test("защита: ME не подключена -> жидкостные не работают", function()
    local w = world()
    w.st.me.present = false
    w.step()
    T.no(w.r().running); T.ok(w.r().faults.me_lost)
end)

T.test("защита: частые автозапуски -> 'Частые аварии', нужен ручной запуск", function()
    local w = world({cfg = {maxAutoRestarts = 2}})
    for _ = 1, 4 do
        w.st.me.amount = 0; w.step()
        w.st.me.amount = 10000000; w.step()
    end
    T.ok(w.r().faults.unstable); T.no(w.r().running)
end)

T.test("защита: сразу после запуска действует только жёсткий порог", function()
    local w = world()
    w.run(10)
    local r = w.r()
    r.coolant = 3.5 * D            -- 3.5 с: меньше мягкого порога (5), больше жёсткого (2)
    r.startedAt = w.c.t            -- только что запущен
    local cmds = protection.evaluate(w.st, w.cfg, w.c.t + 1)
    T.eq(#cmds, 0, "в льготный период не останавливаем")
    r.startedAt = -100
    cmds = protection.evaluate(w.st, w.cfg, w.c.t + 1)
    T.eq(#cmds, 1, "после льготного периода — стоп")
end)

T.test("защита: расход ещё не замерен -> номинал x drainFactor", function()
    local c = T.clock(0)
    local st = State.new(c.fn)
    local r = st:newReactor(1, "a")
    r.consumeNominal = 967
    local d, measured = protection.drainRate(r, config.defaults())
    T.eq(d, 96700); T.no(measured)
end)
