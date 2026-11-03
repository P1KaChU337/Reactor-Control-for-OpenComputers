-- HTTP через интернет-карту без блокировок: запрос продвигается маленькими шагами из общего цикла,
-- поэтому медленный или отсутствующий интернет не останавливает защиту реакторов.
local Http = {}
Http.__index = Http

Http.MAX_SIZE = 128 * 1024

function Http.new(component, clock)
    return setmetatable({component = component, clock = clock, pending = {}}, Http)
end

function Http:available()
    return self.component.isAvailable("internet")
end

-- get(url, cb(ok, dataOrErr) [, timeout])
function Http:get(url, cb, timeout)
    self.pending[#self.pending + 1] = {url = url, cb = cb, deadline = self.clock() + (timeout or 20), parts = {}, size = 0}
end

function Http:busy() return #self.pending > 0 end

local function finish(req, ok, data)
    if req.handle then pcall(req.handle.close) end
    local cbOk, err = pcall(req.cb, ok, data)
    if not cbOk then req.cbError = err end
end

-- Один шаг для всех запросов. Вызывается планировщиком каждые ~0.25 с.
function Http:step()
    local now = self.clock()
    for i = #self.pending, 1, -1 do
        local req = self.pending[i]
        local done, ok, data = false, false, nil
        if now > req.deadline then
            done, data = true, "таймаут"
        elseif not req.handle then
            if not self:available() then
                done, data = true, "нет интернет-карты"
            else
                local inet = self.component.internet
                local okReq, handle = pcall(inet.request, req.url)
                if okReq and handle then req.handle = handle else done, data = true, tostring(handle) end
            end
        elseif not req.connected then
            local okC, res, err = pcall(req.handle.finishConnect)
            if not okC then done, data = true, tostring(res)
            elseif res == nil and err then done, data = true, tostring(err)
            elseif res then
                req.connected = true
                local okR, code = pcall(req.handle.response)
                if okR and type(code) == "number" and code ~= 200 then done, data = true, "HTTP " .. code end
            end
        else
            -- читаем, сколько уже пришло; "" — данных пока нет, nil — конец
            for _ = 1, 8 do
                local okR, chunk = pcall(req.handle.read, 8192)
                if not okR then done, data = true, tostring(chunk) break end
                if chunk == nil then done, ok, data = true, true, table.concat(req.parts) break end
                if chunk == "" then break end
                req.parts[#req.parts + 1] = chunk
                req.size = req.size + #chunk
                if req.size > Http.MAX_SIZE then done, data = true, "слишком большой ответ" break end
            end
        end
        if done then
            table.remove(self.pending, i)
            finish(req, ok, data)
        end
    end
end

return Http
