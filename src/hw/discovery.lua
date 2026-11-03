-- Поиск компонентов и привязка реакторов к постоянным номерам.
-- Порядок component.list не гарантирован, поэтому номер хранится в конфиге: адрес -> номер (1..6).
local reactorHw = require("hw.reactor")
local meHw = require("hw.me")

local M = {}

-- scan(component, state, cfg, log) -> changed(bool), proxies {reactors = {slot -> proxy}, me, flux, chat}
function M.scan(component, state, cfg, log, proxies)
    proxies = proxies or {reactors = {}}
    local changed = false
    local max = state.MAX_REACTORS

    -- реакторы
    local found, foundList = {}, {}
    for addr, ctype in component.list() do
        if type(ctype) == "string" and ctype:sub(1, #reactorHw.TYPE_PREFIX) == reactorHw.TYPE_PREFIX then
            found[addr] = true
            foundList[#foundList + 1] = addr
        end
    end
    table.sort(foundList)

    local slots = cfg.reactorSlots
    local used = {}
    for addr, slot in pairs(slots) do used[slot] = addr end

    -- новые адреса получают свободный номер; если свободных нет — номер реактора, который пропал
    for _, addr in ipairs(foundList) do
        if not slots[addr] then
            local free
            for s = 1, max do if not used[s] then free = s break end end
            if not free then
                for s = 1, max do
                    local a = used[s]
                    if a and not found[a] then free = s slots[a] = nil break end
                end
            end
            if free then
                slots[addr] = free
                used[free] = addr
                changed = true
                log:info("Новый реактор -> #" .. free)
            else
                if not proxies.overflowWarned then
                    log:warn("Реакторов больше " .. max .. ", лишние не используются")
                    proxies.overflowWarned = true
                end
            end
        end
    end

    -- записи состояния
    for s = 1, max do
        local addr = used[s]
        local r = state.reactors[s]
        if addr and found[addr] then
            if not r or r.address ~= addr then
                r = state:newReactor(s, addr)
                changed = true
            end
            if not r.online then
                r.online = true
                r.faults.offline = nil
                log:info("Реактор #" .. s .. " снова на связи")
                changed = true
            end
            if not proxies.reactors[s] or proxies.reactors[s].address ~= addr then
                proxies.reactors[s] = component.proxy(addr)
                r.needStatic = true
            end
        elseif addr and r and r.online then
            -- был, но пропал: держим номер, ставим аварию
            r.online = false
            r.running = false
            r.faults.offline = {since = state.clock(), text = "Нет связи"}
            proxies.reactors[s] = nil
            log:warn("Реактор #" .. s .. " пропал из сети")
            changed = true
        elseif not addr and r then
            state:removeReactor(s)
            proxies.reactors[s] = nil
            changed = true
        end
    end

    -- ME
    local meAddr
    for _, t in ipairs(meHw.TYPES) do
        for addr in component.list(t, true) do meAddr = meAddr or addr end
        if meAddr then break end
    end
    if meAddr ~= (proxies.me and proxies.me.address) then
        proxies.me = meAddr and component.proxy(meAddr) or nil
        state.me.present = meAddr ~= nil
        log:info(meAddr and "МЭ-сеть подключена" or "МЭ-сеть не найдена")
        changed = true
    end

    -- Flux
    local fluxAddr
    for addr in component.list("flux_controller", true) do fluxAddr = fluxAddr or addr end
    if fluxAddr ~= (proxies.flux and proxies.flux.address) then
        proxies.flux = fluxAddr and component.proxy(fluxAddr) or nil
        state.flux.present = fluxAddr ~= nil
        changed = true
    end

    -- Чат-бокс
    local chatAddr
    for addr in component.list("chat_box", true) do chatAddr = chatAddr or addr end
    if chatAddr ~= (proxies.chat and proxies.chat.address) then
        proxies.chat = chatAddr and component.proxy(chatAddr) or nil
        state.chat.present = chatAddr ~= nil
        changed = true
    end

    if changed then state:touch() end
    return changed, proxies
end

return M
