-- Данные с GitHub: текст «Общая информация», история изменений, проверка обновлений.
-- Ничего из скачанного не исполняется с доступом к окружению.
local serialize = require("core.serialize")

local M = {}

M.REPO = "https://raw.githubusercontent.com/P1KaChU337/Reactor-Control-for-OpenComputers/"
M.MAIN = "main"

-- changelog.lua в репозитории — таблица данных вида "return { {version=, changes={...}}, ... }"
function M.parseChangelog(text)
    if type(text) ~= "string" then return nil end
    text = text:gsub("^\239\187\191", "")
    -- комментарии в начале файла (-- ... и --[[ ... ]]) пропускаем
    while true do
        local rest = text:match("^%s*%-%-%[%[.-%]%](.*)$") or text:match("^%s*%-%-[^\n]*\n(.*)$")
        if not rest then break end
        text = rest
    end
    text = text:gsub("^%s*return%s+", "")
    local data = serialize.unserialize(text)
    if type(data) ~= "table" then return nil end
    local out = {}
    for _, e in ipairs(data) do
        if type(e) == "table" and type(e.version) == "string" and type(e.changes) == "table" then
            local changes = {}
            for _, c in ipairs(e.changes) do if type(c) == "string" then changes[#changes + 1] = c end end
            out[#out + 1] = {version = e.version, changes = changes}
        end
    end
    return #out > 0 and out or nil
end

-- about_v2.txt — обычный текст для вкладки «Общая информация». Строки, начинающиеся с "#", — комментарии.
-- Пустая строка — отступ между абзацами.
function M.parseAbout(text)
    if type(text) ~= "string" or #text == 0 then return nil end
    text = text:gsub("^\239\187\191", ""):gsub("\r", "")
    local out = {}
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
        if not line:match("^#") then out[#out + 1] = line end
    end
    while out[1] == "" do table.remove(out, 1) end
    while out[#out] == "" do table.remove(out) end
    return #out > 0 and out or nil
end

-- "2.0.1" > "2.0.0-dev"? Числа сравниваются по порядку, версия с суффиксом (-dev) младше такой же без него.
local function parseVersion(v)
    local nums = {}
    for n in tostring(v):gmatch("%d+") do nums[#nums + 1] = tonumber(n) if #nums >= 4 then break end end
    local pre = tostring(v):find("%-") ~= nil
    return nums, pre
end

-- Записи changelog, которые новее текущей версии (и не новее найденной), сверху самые новые
function M.notesBetween(list, cur, latest)
    local out = {}
    for _, e in ipairs(list or {}) do
        if M.isNewer(e.version, cur) and not M.isNewer(e.version, latest) then out[#out + 1] = e end
    end
    table.sort(out, function(a, b) return M.isNewer(a.version, b.version) end)
    return out
end

function M.isNewer(remote, cur)
    local a, ap = parseVersion(remote)
    local b, bp = parseVersion(cur)
    for i = 1, math.max(#a, #b) do
        local x, y = a[i] or 0, b[i] or 0
        if x ~= y then return x > y end
    end
    return bp and not ap
end

return M
