local S = require("core.serialize")
local T = T

T.test("serialize: туда и обратно", function()
    local v = {a = 1, b = "x\"y\n", c = {1, 2, 3}, d = {["key with space"] = true, [10] = false}, e = 1.5, f = math.huge}
    local back = S.unserialize(S.serialize(v, true))
    T.eq(back.a, 1); T.eq(back.b, "x\"y\n"); T.eq(#back.c, 3); T.eq(back.c[3], 3)
    T.eq(back.d["key with space"], true); T.eq(back.d[10], false); T.eq(back.e, 1.5); T.eq(back.f, math.huge)
end)

T.test("serialize: порядок ключей стабильный", function()
    T.eq(S.serialize({b = 1, a = 2}), S.serialize({a = 2, b = 1}))
end)

T.test("unserialize: код не исполняется с доступом к окружению", function()
    local v, err = S.unserialize("os.exit()")
    T.no(v)
    local v2 = S.unserialize("(function() return io end)()")
    T.no(v2)
end)

T.test("unserialize: комментарий в начале файла", function()
    local v = S.unserialize("-- коммент\n{x = 5}")
    T.eq(v.x, 5)
end)

T.test("serialize: цикл -> ошибка", function()
    local t = {}; t.self = t
    T.no(pcall(S.serialize, t))
end)
