-- Flux Networks: все методы direct (бесплатные), но компонент может пропасть — всё через pcall.
local M = {}

function M.read(proxy, flux)
    if not proxy then flux.present = false return false end
    local ok, info = pcall(proxy.getEnergyInfo)
    if not ok or type(info) ~= "table" then return false end
    flux.input = tonumber(info.energyInput)
    flux.output = tonumber(info.energyOutput)
    flux.buffer = tonumber(info.totalBuffer)
    return true
end

return M
