-- Спрайты из ASCII-арта должны давать ровно те же символы, что старые таблицы v1.1.3
package.preload.unicode = package.preload.unicode or function() return {char = utf8.char, len = utf8.len} end
local T = T
local braille = require("ui.braille")
local S = require("ui.sprites")

local src = io.open("home/nr_v1.1.lua"):read("a")
local a = src:find("local function brailleChar", 1, true)
local b = src:find("local function saveCfg", 1, true)
local env = setmetatable({unicode = {char = utf8.char}}, {__index = _G})
local code = src:sub(a, b - 1):gsub("local ([%w_]+) = {", "%1 = {"):gsub("local function brailleChar", "function brailleChar")
assert(load(code, "=legacy", "t", env))()

local IMG = {braill0 = "digit0", braill1 = "digit1", braill2 = "digit2", braill3 = "digit3", braill4 = "digit4",
    braill5 = "digit5", braill6 = "digit6", braill7 = "digit7", braill8 = "digit8", braill9 = "digit9",
    braill_minus = "digitMinus", braill_dot = "digitDot", brail_fluid = "iconFluid", brail_greenbtn = "iconPlus",
    brail_redbtn = "iconMinus", brail_thunderbolt = "iconBolt", brail_time = "iconTime"}
local SET = {brail_console = "console", brail_cherta = "divider", button1 = "button", button1_push = "buttonPushed",
    brail_status = "corner", brail_fields = "field", brail_verticalbar = "vbar"}

T.test("брайль: картинки совпадают со старыми таблицами", function()
    for old, new in pairs(IMG) do
        local t, im = env[old], S[new]
        T.eq(im[1][1], env.brailleChar(t[1]), new .. "[1]"); T.eq(im[1][2], env.brailleChar(t[2]), new .. "[2]")
        T.eq(im[2][1], env.brailleChar(t[3]), new .. "[3]"); T.eq(im[2][2], env.brailleChar(t[4]), new .. "[4]")
    end
end)

T.test("брайль: наборы ячеек совпадают со старыми таблицами", function()
    for old, new in pairs(SET) do
        for i, d in ipairs(env[old]) do T.eq(S[new][i], env.brailleChar(d), new .. "[" .. i .. "]") end
    end
end)

T.test("брайль: fromDots == старый brailleChar", function()
    for m = 0, 255 do
        local d = {}
        for i = 1, 8 do d[i] = math.random(0, 1) end
        T.eq(braille.fromDots(d), env.brailleChar(d))
    end
end)
