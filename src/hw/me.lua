-- ME-контроллер / интерфейс. getFluidsInNetwork и getItemsInNetwork делят общий кулдаун ~15 с:
-- во время него метод возвращает false, "cooldown", "14s". Это НЕ авария — просто ждём.
local M = {}

M.TYPES = {"me_controller", "me_interface"}
M.MIN_INTERVAL = 16

-- read(proxy, state.me, now, coolantName) -> "ok" | "cooldown" | "error"
function M.read(proxy, me, now, coolantName)
    if not proxy then return "error" end
    local ok, list, reason, left = pcall(proxy.getFluidsInNetwork)
    if not ok then
        me.error = tostring(list)
        return "error"
    end
    if list == false and reason == "cooldown" then
        local secs = tonumber(tostring(left or ""):match("(%d+)")) or M.MIN_INTERVAL
        me.cooldownUntil = now + secs + 1
        return "cooldown"
    end
    if type(list) ~= "table" then
        me.error = "getFluidsInNetwork: " .. tostring(reason or list)
        return "error"
    end
    local amount = 0
    for _, f in ipairs(list) do
        if f.name == coolantName then amount = amount + (tonumber(f.amount) or 0) end
    end
    me.amount = amount
    me.lastOk = now
    me.error = nil
    me.cooldownUntil = now + M.MIN_INTERVAL
    return "ok"
end

return M
