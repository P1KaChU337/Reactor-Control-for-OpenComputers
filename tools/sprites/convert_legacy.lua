-- Переводит брайль-таблицы из home/nr_v1.1.lua в ASCII-арт для src/ui/sprites.lua.
-- Запуск из корня: lua5.3 tools/sprites/convert_legacy.lua > /tmp/sprites_ascii.lua
local src = io.open("home/nr_v1.1.lua"):read("a")
local a = src:find("local function brailleChar")
local b = src:find("local function saveCfg", 1, true)
local chunk = src:sub(a, b - 1)
local env = setmetatable({unicode = {char = utf8.char}}, {__index = _G})
local names = {}
for n in chunk:gmatch("local ([%w_]+) = {") do names[#names + 1] = n end
local code = chunk:gsub("local ([%w_]+) = {", "%1 = {"):gsub("local function brailleChar", "function brailleChar")
assert(load(code, "=legacy", "t", env))()

-- одна ячейка: dots[1..8] = (r1c1, r1c2, r2c1, r2c2, r3c1, r3c2, r4c1, r4c2)
local function cellRows(d)
    local rows = {}
    for r = 0, 3 do
        rows[r + 1] = ((d[r * 2 + 1] or 0) == 1 and "#" or ".") .. ((d[r * 2 + 2] or 0) == 1 and "#" or ".")
    end
    return rows
end

local out = {}
local function w(s) out[#out + 1] = s end
for _, n in ipairs(names) do
    local t = env[n]
    if n:match("^braill[%d_]") or n == "brail_fluid" or n == "brail_greenbtn" or n == "brail_redbtn"
        or n == "brail_thunderbolt" or n == "brail_time" then
        -- картинка 2x2 ячейки: [1] (0,0), [2] (1,0), [3] (0,1), [4] (1,1)
        local c = {cellRows(t[1]), cellRows(t[2]), cellRows(t[3]), cellRows(t[4])}
        w(string.format("    %s = img{", n))
        for r = 1, 4 do w(string.format('        "%s%s",', c[1][r], c[2][r])) end
        for r = 1, 4 do w(string.format('        "%s%s",', c[3][r], c[4][r])) end
        w("    },")
    else
        -- набор отдельных ячеек
        w(string.format("    %s = set{", n))
        for i, d in ipairs(t) do
            local rows = cellRows(d)
            w(string.format('        {"%s", "%s", "%s", "%s"}, -- %d %s', rows[1], rows[2], rows[3], rows[4], i, env.brailleChar(d)))
        end
        w("    },")
    end
end
print(table.concat(out, "\n"))
