-- Скриншот текстового режима (--nogui) для гайда
local emu = __EMU__
local mocks = require("mocks")
local OUT = os.getenv("EMU_OUT") or "/tmp/rc_emu_out"
emu.install("../../src", "/home/reactorcontrol")
local fs = require("filesystem")
fs.makeDirectory("/home/reactorcontrol/data")
local f = io.open("/home/reactorcontrol/data/config.cfg", "w")
f:write('{firstStart = false, users = {"P1KaChU337"}, usersApplied = {"P1KaChU337"}, threshold = 500000}')
f:close()
local rs = {}
local fuelBase = {3900, 6200, 2500, 7400, 5100, 8300}
for i = 1, 6 do
    local r = mocks.reactor({fluid = i ~= 5, gen = i == 5 and 651800 or 7793856, temp = i == 5 and 0 or 9998})
    local k = 0
    for _, rod in pairs(r.state.rods) do k = k + 1 rod.fuel = math.min(10000, fuelBase[i] + (k * 337) % 4500) end
    rs[i] = r
    emu.addComponent(r)
end
emu.addComponent(mocks.me({fluid = 10018613}))
emu.addComponent(mocks.flux())
emu.queue = {}
emu.at(2, function() emu.key(string.byte("s"), 31) end)
emu.at(100.5, function() rs[3].state.supply = false end)
emu.at(140, function() emu.dump(OUT .. "/guide_textmode.txt") end)
emu.endTime = 141
emu.runVirtual("/home/reactorcontrol/main.lua", "--nogui")
