-- Работа с файлами поверх io.open/filesystem. Запись атомарная: сначала во временный файл, потом rename,
-- чтобы при выключении сервера посреди записи конфиг не превратился в мусор.
local M = {}

local okFs, filesystem = pcall(require, "filesystem")
if not okFs then filesystem = nil end

function M.read(path)
    local f, err = io.open(path, "r")
    if not f then return nil, err end
    local data = f:read("*a")
    f:close()
    return data
end

function M.exists(path)
    if filesystem then return filesystem.exists(path) end
    local f = io.open(path, "r")
    if f then f:close() return true end
    return false
end

function M.makeDirectory(path)
    if filesystem then return filesystem.makeDirectory(path) end
    return os.execute("mkdir -p '" .. path .. "'")
end

function M.dirname(path)
    return path:match("^(.*)/[^/]*$") or "."
end

function M.remove(path)
    if filesystem then return filesystem.remove(path) end
    return os.remove(path)
end

function M.rename(from, to)
    if filesystem then return filesystem.rename(from, to) end
    return os.rename(from, to)
end

function M.size(path)
    if filesystem then return filesystem.size(path) end
    local f = io.open(path, "r")
    if not f then return 0 end
    local s = f:seek("end")
    f:close()
    return s or 0
end

function M.writeAtomic(path, data)
    local dir = M.dirname(path)
    if not M.exists(dir) then M.makeDirectory(dir) end
    local tmp = path .. ".tmp"
    local f, err = io.open(tmp, "w")
    if not f then return nil, err end
    local ok, werr = f:write(data)
    f:close()
    if not ok then M.remove(tmp) return nil, werr end
    if M.exists(path) then M.remove(path) end
    local rok, rerr = M.rename(tmp, path)
    if not rok then return nil, rerr end
    return true
end

function M.append(path, data)
    local f, err = io.open(path, "a")
    if not f then return nil, err end
    f:write(data)
    f:close()
    return true
end

return M
