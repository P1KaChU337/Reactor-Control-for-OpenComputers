-- Форматирование чисел и времени для экрана
local M = {}

local SUFFIX = {"", "k", "m", "g", "t", "p"}
local METRIC = {[""] = 1, k = 2, m = 3, g = 4}

local function round(v, digits)
    local mult = 10 ^ (digits or 0)
    local r = math.floor(v * mult + 0.5) / mult
    if r == math.floor(r) then return string.format("%d", r) end
    return tostring(r)
end
M.round = round

-- si(value, metric) -> "7.8", "m". metric: "auto" | "" | "k" | "m" | "g"
function M.si(value, metric)
    value = tonumber(value) or 0
    local idx = METRIC[metric or "auto"]
    if not idx then
        idx = 1
        local v = math.abs(value)
        while v >= 1000 and idx < #SUFFIX do v = v / 1000 idx = idx + 1 end
    end
    return round(value / 1000 ^ (idx - 1), 1), SUFFIX[idx]
end

-- compact(value) -> "7.79m" (всегда авто, 3 значащих цифры) — для узких мест
function M.compact(value)
    value = tonumber(value) or 0
    local idx, v = 1, value
    while math.abs(v) >= 1000 and idx < #SUFFIX do v = v / 1000 idx = idx + 1 end
    local s
    if math.abs(v) < 10 and idx > 1 then s = string.format("%.2f", v)
    elseif math.abs(v) < 100 and idx > 1 then s = string.format("%.1f", v)
    else s = string.format("%.0f", v) end
    if s:find("%.") then s = s:gsub("0+$", ""):gsub("%.$", "") end
    if s == "" or s == "-" then s = "0" end
    return s .. SUFFIX[idx]
end

function M.hms(seconds)
    if type(seconds) ~= "number" or seconds ~= seconds or seconds < 0 then return "--:--:--" end
    if seconds > 359999 then return ">99ч" end
    local h = math.floor(seconds / 3600)
    local m = math.floor(seconds % 3600 / 60)
    local s = math.floor(seconds % 60)
    return string.format("%02d:%02d:%02d", h, m, s)
end

function M.percent(v, max)
    if not v or not max or max <= 0 then return "--" end
    return string.format("%d%%", math.floor(v / max * 100 + 0.5))
end

M.METRIC_ORDER = {"auto", "", "k", "m", "g"}
M.METRIC_LABEL = {auto = "Auto", [""] = "Rf, Mb", k = "kRf, kMb", m = "mRf, mMb", g = "gRf, gMb"}

return M
