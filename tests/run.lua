-- Мини-раннер тестов на чистом Lua 5.3 (без OpenComputers).
-- Запуск из корня репозитория: lua5.3 tests/run.lua [фильтр]
package.path = "./src/?.lua;./tests/?.lua;" .. package.path

local T = {passed = 0, failed = 0, current = nil}
_G.T = T

function T.eq(a, b, msg)
    if a ~= b then error((msg or "eq") .. ": ожидалось " .. tostring(b) .. ", получено " .. tostring(a), 2) end
end
function T.near(a, b, eps, msg)
    if type(a) ~= "number" or math.abs(a - b) > (eps or 1e-6) then
        error((msg or "near") .. ": ожидалось ~" .. tostring(b) .. ", получено " .. tostring(a), 2)
    end
end
function T.ok(v, msg) if not v then error(msg or "ожидалось true", 2) end end
function T.no(v, msg) if v then error(msg or "ожидалось false/nil", 2) end end

function T.test(name, fn)
    if T.filter and not name:find(T.filter, 1, true) then return end
    local ok, err = xpcall(fn, debug.traceback)
    if ok then
        T.passed = T.passed + 1
    else
        T.failed = T.failed + 1
        io.write("FAIL ", name, "\n  ", tostring(err):gsub("\n", "\n  "), "\n")
    end
end

-- часы, которыми управляет тест
function T.clock(start)
    local c = {t = start or 0}
    c.fn = function() return c.t end
    return c
end

T.filter = arg[1]
local files = {"test_serialize", "test_config", "test_scheduler", "test_rate", "test_protection", "test_hw", "test_braille", "test_format", "test_installer"}
for _, f in ipairs(files) do
    package.loaded[f] = nil
    require(f)
end
io.write(string.format("\n%d passed, %d failed\n", T.passed, T.failed))
os.exit(T.failed == 0 and 0 or 1)
