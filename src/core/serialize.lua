-- Сериализация таблиц в читаемый Lua-текст и обратно (без исполнения кода с доступом к окружению).
-- Поддерживает: nil, boolean, number, string, вложенные таблицы без циклов.
local M = {}

local function isIdent(k)
    return type(k) == "string" and k:match("^[%a_][%w_]*$") ~= nil
end

local function sortedKeys(t)
    local keys = {}
    for k in pairs(t) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b)
        local ta, tb = type(a), type(b)
        if ta ~= tb then return ta < tb end
        if ta == "number" or ta == "string" then return a < b end
        return tostring(a) < tostring(b)
    end)
    return keys
end

local function fmtNumber(n)
    if n ~= n then return "0/0" end
    if n == math.huge then return "math.huge" end
    if n == -math.huge then return "-math.huge" end
    if math.type and math.type(n) == "integer" then return tostring(n) end
    if n == math.floor(n) and math.abs(n) < 2^53 then return string.format("%d", n) end
    return string.format("%.17g", n)
end

local function ser(v, indent, level, seen, out)
    local t = type(v)
    if t == "nil" then out[#out + 1] = "nil"
    elseif t == "boolean" then out[#out + 1] = tostring(v)
    elseif t == "number" then out[#out + 1] = fmtNumber(v)
    elseif t == "string" then out[#out + 1] = string.format("%q", v)
    elseif t == "table" then
        if seen[v] then error("serialize: цикл в таблице", 0) end
        seen[v] = true
        local n = #v
        local keys = sortedKeys(v)
        if #keys == 0 then out[#out + 1] = "{}" seen[v] = nil return end
        local pad = indent and string.rep(indent, level + 1) or ""
        local nl = indent and "\n" or ""
        out[#out + 1] = "{" .. nl
        local first = true
        for _, k in ipairs(keys) do
            if not first then out[#out + 1] = "," .. nl end
            first = false
            out[#out + 1] = pad
            if type(k) == "number" and k >= 1 and k <= n and math.floor(k) == k then
                -- элемент массива: без ключа
            elseif isIdent(k) then
                out[#out + 1] = k .. " = "
            else
                out[#out + 1] = "["
                ser(k, nil, 0, seen, out)
                out[#out + 1] = "] = "
            end
            ser(v[k], indent, level + 1, seen, out)
        end
        out[#out + 1] = nl .. (indent and string.rep(indent, level) or "") .. "}"
        seen[v] = nil
    else
        error("serialize: тип " .. t .. " не поддерживается", 0)
    end
end

-- serialize(value [, pretty]) -> string
function M.serialize(v, pretty)
    local out = {}
    ser(v, pretty and "    " or nil, 0, {}, out)
    return table.concat(out)
end

-- unserialize(string) -> value | nil, err
-- Выполняется в пустом окружении: доступно только math.huge.
function M.unserialize(s)
    if type(s) ~= "string" then return nil, "ожидалась строка" end
    local env = {math = {huge = math.huge}}
    local chunk, err
    if setfenv then
        chunk, err = loadstring("return " .. s)
        if chunk then setfenv(chunk, env) end
    else
        chunk, err = load("return " .. s, "=data", "t", env)
    end
    if not chunk then return nil, err end
    local ok, res = pcall(chunk)
    if not ok then return nil, res end
    return res
end

return M
