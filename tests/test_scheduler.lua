local Scheduler = require("core.scheduler")
local T = T

T.test("scheduler: периодические задачи, сдвиг, без дрейфа", function()
    local c = T.clock(100)
    local s = Scheduler.new(c.fn)
    local a, b = 0, 0
    s:every("a", 1, function() a = a + 1 end)
    s:every("b", 5, function() b = b + 1 end, 0.5)
    for i = 1, 100 do c.t = 100 + i * 0.1 s:run() end -- 10 секунд
    T.eq(a, 11); T.eq(b, 2)
    T.near(s:timeUntilNext(), 0.0, 1.0)
end)

T.test("scheduler: ошибка задачи не ломает остальные", function()
    local c = T.clock(0)
    local errs = 0
    local s = Scheduler.new(c.fn, function() errs = errs + 1 end)
    local ok = 0
    s:every("bad", 1, function() error("boom") end)
    s:every("good", 1, function() ok = ok + 1 end)
    s:run()
    T.eq(errs, 1); T.eq(ok, 1)
end)

T.test("scheduler: runSoon и after", function()
    local c = T.clock(0)
    local s = Scheduler.new(c.fn)
    local n, once = 0, 0
    s:every("x", 60, function() n = n + 1 end, 60)
    s:after("o", 2, function() once = once + 1 end)
    s:runSoon("x", 1)
    c.t = 1 s:run()
    T.eq(n, 1)
    c.t = 3 s:run() c.t = 10 s:run()
    T.eq(once, 1); T.no(s:has("o"))
end)
