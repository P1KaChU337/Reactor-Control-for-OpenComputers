-- Моки игровых компонентов. Форматы ответов сняты с реального сервера (tools/probe, McSkill HiTech 1.12.2).
local M = {}
local n = 0
local function addr(prefix) n = n + 1 return string.format("%s-%04d-0000-0000-000000000000", prefix, n) end
local function now() return __EMU__.time end

-- Слоты стержней в реальном реакторе идут с пропусками (10, 11, 14, 15 пустые)
M.DEFAULT_ROD_SLOTS = {1, 2, 3, 4, 5, 6, 7, 8, 9, 12, 13, 16, 17, 18, 19, 20, 21, 22, 23, 24}

local REACTOR_DOC = {
    activate = "function():boolean -- Включает реактор.",
    deactivate = "function():boolean -- Выключает реактор.",
    getAllFuelRodsStatus = "function():table -- Получает информацию о всех топливных стержнях.",
    getCoolantItem = "function(slot:int):table -- Получает информацию о предмете охлаждения в указанном слоте.",
    getEnergyGeneration = "function():long -- Получает текущую генерацию энергии.",
    getFluidCoolant = "function():int -- Получает текущий объём внутреннего буфера охлаждения.",
    getFluidCoolantConsume = "function():int -- Получает потребление охлаждающей жидкости в секунду.",
    getMaxFluidCoolant = "function():int -- Получает максимальный объём внутреннего буфера охлаждения.",
    getMaxTemperature = "function():int -- Получает максимальную температуру реактора.",
    getReactorComponent = "function(slot:int):table -- Получает информацию о компоненте схемы в указанном слоте.",
    getReactorComponents = "function():table -- Получает информацию о всех компонентах схемы реактора.",
    getReactorLevel = "function():int -- Уровень реактора.",
    getSelectStatusRod = "function(slot:int):table -- Получает информацию о топливном стержне в указанном слоте.",
    getTemperature = "function():int -- Получает текущую температуру реактора.",
    hasWork = "function():boolean -- Проверяет, работает ли реактор.",
    isActiveCooling = "function():boolean -- Проверяет, активно ли жидкостное охлаждение.",
    isFuelFilterActive = "function():boolean -- Проверяет, активен ли топливный фильтр.",
    setActiveCooling = "function(state:boolean):boolean -- Включает или выключает жидкостное охлаждение.",
}

-- Реактор HiTech (тип компонента "htc_reactors_nuclear_reactor").
-- Пока реактор работает: буфер убывает на consume/с (если не пополняется), топливо стержней убывает на fuelRate/с.
-- ВНИМАНИЕ: скорость топлива и поведение температуры пока не измерены (ждём probe --watch на работающем реакторе).
function M.reactor(opts)
    opts = opts or {}
    local s = {
        active = opts.active or false,
        fluid = opts.fluid ~= false,
        temp = opts.temp or 9998,          -- на сервере 9998 и у работающих, и у остановленных (у одного реактора 0)
        maxTemp = opts.maxTemp or 9999,
        gen = opts.gen or 7793856,
        coolant = opts.coolant or 983200,
        maxCoolant = opts.maxCoolant or 1080000,
        consume = opts.consume or 967,      -- номинальный расход, отдаётся и когда реактор стоит
        refill = opts.refill or 967,        -- сколько в секунду подливает ME (0 = не подливает)
        fuelRate = opts.fuelRate or 1,
        level = opts.level or 6,
        rods = {},
        lastT = 0,
    }
    for _, slot in ipairs(opts.rodSlots or M.DEFAULT_ROD_SLOTS) do
        s.rods[slot] = {fuel = opts.rodFuel or 7200, maxFuel = 10000, item = "htc_reactors:sixteen_mox_fuel_rod"}
    end
    local function tick()
        local t = now()
        local dt = t - s.lastT
        s.lastT = t
        if dt <= 0 then return end
        if s.active then
            if s.fluid then
                s.coolant = math.max(0, math.min(s.maxCoolant, s.coolant + (s.refill - s.consume) * dt))
            end
            for _, r in pairs(s.rods) do r.fuel = math.max(0, r.fuel - s.fuelRate * dt) end
        end
    end
    local p = {type = "htc_reactors_nuclear_reactor", address = addr("reactor"), state = s, __doc = REACTOR_DOC}
    function p.hasWork() tick() return s.active end
    function p.activate() tick() s.active = true return true end
    function p.deactivate() tick() s.active = false return true end
    function p.isActiveCooling() return s.fluid end
    function p.setActiveCooling(v) s.fluid = v and true or false return true end
    function p.isFuelFilterActive() return true end
    function p.getReactorLevel() return s.level end
    function p.getTemperature() tick() return s.temp end
    function p.getMaxTemperature() return s.maxTemp end
    function p.getEnergyGeneration() tick() return s.active and s.gen or 0 end
    function p.getFluidCoolant() tick() return math.floor(s.coolant) end
    function p.getMaxFluidCoolant() return s.maxCoolant end
    function p.getFluidCoolantConsume() return s.consume end
    -- плоский список ключ/значение, индексы = слоты
    local function rodEntry(r) return {"item", r.item, "type", "fuelrod", "fuel", math.floor(r.fuel), "maxFuel", r.maxFuel} end
    function p.getAllFuelRodsStatus()
        tick()
        local res = {}
        for slot, r in pairs(s.rods) do res[slot] = rodEntry(r) end
        return res
    end
    function p.getSelectStatusRod(slot)
        if type(slot) ~= "number" then error("bad arguments #1 (integer expected, got no value)", 0) end
        local r = s.rods[slot]
        return r and rodEntry(r) or nil
    end
    function p.getReactorComponents()
        local res = {}
        for i = 1, 80 do res[i] = {"item", "htc_reactors:draconium_heat_exchanger", "count", 6, "meta", 0} end
        return res
    end
    function p.getReactorComponent(slot)
        if type(slot) ~= "number" then error("bad arguments #1 (integer expected, got no value)", 0) end
        return {"item", "htc_reactors:draconium_heat_exchanger", "count", 6, "meta", 0}
    end
    function p.getCoolantItem(slot)
        if type(slot) ~= "number" then error("bad arguments #1 (integer expected, got no value)", 0) end
        return nil
    end
    return p
end

-- ME-контроллер. На сервере getItemsInNetwork и getFluidsInNetwork делят ОДИН кулдаун ~15 с:
-- во время него возвращают false, "cooldown", "14s"
function M.me(opts)
    opts = opts or {}
    local s = {fluid = opts.fluid or 10018613, cooldown = opts.cooldown or 15, last = -math.huge}
    local p = {type = opts.type or "me_controller", address = addr("me"), state = s, __doc = {
        getItemsInNetwork = "function([filter:table]):table -- Get a list of the stored items in the network.",
        getFluidsInNetwork = "function():table -- Get a list of the stored fluids in the network.",
    }}
    local function cooldown()
        local t = now()
        if t - s.last < s.cooldown then
            return string.format("%ds", math.ceil(s.cooldown - (t - s.last)))
        end
        s.last = t
    end
    function p.getItemsInNetwork(filter)
        local left = cooldown()
        if left then return false, "cooldown", left end
        return {
            {damage = 0, hasTag = true, isCraftable = true, label = "IC2 Coolant", maxDamage = 0, maxSize = 64, name = "ae2fc:fluid_drop", size = 133000},
            {damage = 0, hasTag = true, isCraftable = false, label = "fluid.low_temperature_refrigerant", maxDamage = 0, maxSize = 64, name = "ae2fc:fluid_drop", size = s.fluid},
        }
    end
    function p.getFluidsInNetwork()
        local left = cooldown()
        if left then return false, "cooldown", left end
        return {
            {amount = 87100800, hasTag = false, label = "Tritium", name = "tritium"},
            {amount = 133000, hasTag = false, label = "IC2 Coolant", name = "ic2coolant"},
            {amount = s.fluid, hasTag = false, label = "fluid.low_temperature_refrigerant", name = "low_temperature_refrigerant"},
        }
    end
    function p.isNetworkPowered() return true end
    function p.getAvgPowerUsage() return 306595.857 end
    function p.getAvgPowerInjection() return 0 end
    function p.getIdlePowerUsage() return 42687.09 end
    function p.getStoredPower() return 9.2236120417428e+14 end
    function p.getMaxStoredPower() return 9.2236120417428e+14 end
    return p
end

function M.flux(opts)
    opts = opts or {}
    local s = {input = opts.input or 259352091430, output = opts.output or 259351845674}
    local p = {type = "flux_controller", address = addr("flux"), state = s}
    function p.getEnergyInfo() return {energyInput = s.input, energyOutput = s.output, totalBuffer = 9935111243164, totalEnergy = 0} end
    function p.getCountInfo() return {controllerCount = 1, plugCount = 8, pointCount = 179, storageCount = 1} end
    function p.getFluxInfo() return {buffer = 27717, customName = "Flux Controller", priority = 0, surgeMode = true, transferLimit = 262144, unlimited = true} end
    function p.getNetworkInfo() return {averageTick = 186, energyType = "RF", id = 121, name = "Test Network", securityType = "encrypted"} end
    return p
end

function M.chatbox()
    local p = {type = "chat_box", address = addr("chatbox"), said = {}, name = "", distance = 100}
    function p.say(m) table.insert(p.said, m) __EMU__.trace("chat>", m) return true end
    function p.setName(nm) p.name = nm return nm end
    function p.getName() return p.name end
    function p.getDistance() return p.distance end
    function p.setDistance(d) p.distance = d return d end
    return p
end

return M
