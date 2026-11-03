-- Моки игровых компонентов (htc_reactors, ME, Flux, ChatBox)
local M = {}
local n = 0
local function addr(prefix) n = n + 1 return string.format("%s-%04d-0000-0000-000000000000", prefix, n) end

-- Жидкостный/воздушный реактор HiTech (API восстановлено по вызовам в коде)
function M.reactor(opts)
    opts = opts or {}
    local s = {
        active = opts.active or false,
        fluid = opts.fluid ~= false,
        temp = opts.temp or 0,
        gen = opts.gen or 25000,
        coolant = opts.coolant or 16000,
        maxCoolant = opts.maxCoolant or 16000,
        consume = opts.consume or 40,
        rods = opts.rods or {{0,0,0,0,0, 7200}, {0,0,0,0,0, 7100}},
    }
    local p = {type = "htc_reactors", address = addr("reactor"), state = s}
    function p.hasWork() return s.active end
    function p.activate() s.active = true return true end
    function p.deactivate() s.active = false return true end
    function p.isActiveCooling() return s.fluid end
    function p.getTemperature() return s.active and (s.temp > 0 and s.temp or 350) or 25 end
    function p.getEnergyGeneration() return s.active and s.gen or 0 end
    function p.getFluidCoolant() return s.coolant end
    function p.getMaxFluidCoolant() return s.maxCoolant end
    function p.getFluidCoolantConsume() return s.active and s.consume or 0 end
    function p.getAllFuelRodsStatus() return s.rods end
    return p
end

function M.me(opts)
    opts = opts or {}
    local s = {fluid = opts.fluid or 1000000}
    local p = {type = opts.type or "me_controller", address = addr("me"), state = s}
    function p.getItemsInNetwork(filter)
        return {{name = "ae2fc:fluid_drop", label = "drop of low_temperature_refrigerant", size = s.fluid}}
    end
    return p
end

function M.flux(opts)
    opts = opts or {}
    local s = {input = opts.input or 500000, output = opts.output or 320000}
    local p = {type = "flux_controller", address = addr("flux"), state = s}
    function p.getEnergyInfo() return {energyInput = s.input, energyOutput = s.output} end
    return p
end

function M.chatbox()
    local p = {type = "chat_box", address = addr("chatbox"), said = {}}
    function p.say(m) table.insert(p.said, m) __EMU__.trace("chat>", m) return true end
    function p.setName(n) return true end
    return p
end

return M
