-- Список файлов в установщике должен совпадать с содержимым src/
local T = T
T.test("установщик: список файлов совпадает с src/", function()
    local code = io.open("installer/install_v2.lua"):read("a")
    local block = code:match("local FILES = {(.-)\n}")
    local listed = {}
    for f in block:gmatch('"([^"]+)"') do listed[f] = true end
    local p = io.popen("cd src && find . -type f \\( -name '*.lua' -o -name '*.pic' \\) | sed 's|^\\./||'")
    local missing = {}
    for f in p:lines() do
        if not listed[f] then missing[#missing + 1] = f end
        listed[f] = nil
    end
    p:close()
    local extra = {}
    for f in pairs(listed) do extra[#extra + 1] = f end
    T.eq(#missing, 0, "нет в установщике: " .. table.concat(missing, ", "))
    T.eq(#extra, 0, "лишние в установщике: " .. table.concat(extra, ", "))
end)
