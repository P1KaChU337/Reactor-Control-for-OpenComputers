local reactorHw = require("hw.reactor")
local meHw = require("hw.me")
local T = T

local function rod(fuel, maxFuel) return {"item", "htc_reactors:sixteen_mox_fuel_rod", "type", "fuelrod", "fuel", fuel, "maxFuel", maxFuel or 10000} end

T.test("hw: стержни со слотами-пропусками считаются все (баг ipairs в v1.1.3)", function()
    local rods = {}
    for _, slot in ipairs({1, 2, 3, 4, 5, 6, 7, 8, 9, 12, 13, 16, 17, 18, 19, 20, 21, 22, 23, 24}) do rods[slot] = rod(1000 + slot) end
    local s = reactorHw.rodsSummary(rods)
    T.eq(s.count, 20); T.eq(s.min, 1001); T.eq(s.max, 1024); T.eq(s.maxFuel, 10000)
end)

T.test("hw: kv разбирает плоские записи", function()
    local e = reactorHw.kv({"item", "x", "count", 6, "meta", 0})
    T.eq(e.item, "x"); T.eq(e.count, 6); T.eq(e.meta, 0)
end)

T.test("hw: ME кулдаун не ошибка, хладагент по точному имени", function()
    local me = {}
    local calls = 0
    local proxy = {getFluidsInNetwork = function()
        calls = calls + 1
        if calls == 2 then return false, "cooldown", "14s" end
        return {
            {name = "ic2coolant", label = "IC2 Coolant", amount = 133000},
            {name = "low_temperature_refrigerant", label = "fluid.low_temperature_refrigerant", amount = 10018613},
        }
    end}
    T.eq(meHw.read(proxy, me, 100, "low_temperature_refrigerant"), "ok")
    T.eq(me.amount, 10018613); T.eq(me.lastOk, 100)
    T.eq(meHw.read(proxy, me, 101, "low_temperature_refrigerant"), "cooldown")
    T.eq(me.amount, 10018613, "значение сохраняется"); T.eq(me.cooldownUntil, 116)
end)

T.test("hw: ME ошибка вызова", function()
    local me = {}
    T.eq(meHw.read({getFluidsInNetwork = function() error("no such component") end}, me, 1, "x"), "error")
    T.ok(me.error)
end)
