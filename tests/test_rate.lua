local rate = require("logic.rate")
local T = T

T.test("drain: медиана по пиле с доливом до полного", function()
    local d = rate.drain()
    local max, D = 1080000, 96768
    local v = max - D
    for sec = 1, 30 do
        if sec % 3 == 0 then v = max end
        v = v - D
        d:add(sec, v, true)
    end
    T.near(d:rate(), D, 1)
end)

T.test("drain: без работы реактора не меряется", function()
    local d = rate.drain()
    for sec = 1, 10 do d:add(sec, 1000 - sec * 10, false) end
    T.no(d:rate())
end)

T.test("burn: средняя скорость, наниты меняют скорость", function()
    local b = rate.burn(600)
    local fuel = 9000
    for t = 0, 300, 30 do
        b:add(t, {min = fuel - 3000, max = fuel, sum = fuel * 20, count = 20}, true)
        fuel = fuel - 30 * 3   -- 3 ед./с
    end
    T.near(b:rate(), 3, 1e-6)
    local first, last = b:remaining(300)
    T.near(last, (9000 - 300 * 3) / 3, 1)
    -- ускорение: 6 ед./с следующие 300 с
    for t = 330, 600, 30 do
        b:add(t, {min = fuel - 3000, max = fuel, sum = fuel * 20, count = 20}, true)
        fuel = fuel - 30 * 6
    end
    local r = b:rate()
    T.ok(r > 3 and r < 6, "среднее за окно между 3 и 6: " .. tostring(r))
end)

T.test("burn: замена стержня и простой", function()
    local b = rate.burn(600)
    b:add(0, {min = 100, max = 100, sum = 2000, count = 20}, true)
    b:add(30, {min = 40, max = 40, sum = 800, count = 20}, true)
    T.near(b:rate(), 2)
    b:add(60, {min = 10000, max = 10000, sum = 200000, count = 20}, true)
    T.no(b:rate(), "после замены отсчёт заново")
    b:add(90, {min = 9940, max = 9940, sum = 198800, count = 20}, false)
    b:add(120, {min = 9940, max = 9940, sum = 198800, count = 20}, false)
    T.no(b:rate(), "простой не считается")
end)

T.test("burn: оценка между замерами", function()
    local b = rate.burn(600)
    b:add(0, {min = 1000, max = 2000, sum = 30000, count = 20}, true)
    b:add(30, {min = 940, max = 1940, sum = 28800, count = 20}, true) -- 2 ед./с
    local first, last = b:remaining(40)
    T.near(first, (940 - 20) / 2); T.near(last, (1940 - 20) / 2)
end)
