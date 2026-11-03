package.preload.unicode = package.preload.unicode or function() return {char = utf8.char, len = utf8.len} end
local fmt = require("ui.format")
local T = T

T.test("format: compact не срезает нули у целых", function()
    T.eq(fmt.compact(290400), "290k"); T.eq(fmt.compact(100), "100"); T.eq(fmt.compact(1000), "1k")
    T.eq(fmt.compact(1500), "1.5k"); T.eq(fmt.compact(96768), "96.8k"); T.eq(fmt.compact(259352091430), "259g")
    T.eq(fmt.compact(10000000), "10m"); T.eq(fmt.compact(0), "0")
end)

T.test("format: si по метрике", function()
    local v, u = fmt.si(7793856, "auto"); T.eq(v, "7.8"); T.eq(u, "m")
    v, u = fmt.si(7793856, "k"); T.eq(v, "7793.9"); T.eq(u, "k")
    v, u = fmt.si(500, "auto"); T.eq(v, "500"); T.eq(u, "")
end)

T.test("format: время", function()
    T.eq(fmt.hms(3725), "01:02:05"); T.eq(fmt.hms(nil), "--:--:--"); T.eq(fmt.hms(-1), "--:--:--")
end)
