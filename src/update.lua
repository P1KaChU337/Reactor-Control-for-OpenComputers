-- Обновление Reactor Control v2: скачивает свежий установщик и запускает его.
-- Запуск: /home/reactorcontrol/update.lua
local shell = require("shell")
local fs = require("filesystem")
local args, opts = shell.parse(...)
local BRANCH = type(opts.branch) == "string" and opts.branch or "claude/keen-volta-rnypyl"
local URL = "https://raw.githubusercontent.com/P1KaChU337/Reactor-Control-for-OpenComputers/" .. BRANCH .. "/installer/install_v2.lua"
local PATH = "/home/rc_install.lua"
print("Загрузка установщика...")
if fs.exists(PATH) then fs.remove(PATH) end
shell.execute("wget -fq " .. URL .. " " .. PATH)
if not fs.exists(PATH) then
    io.stderr:write("Не удалось скачать установщик. Проверьте интернет-карту.\n")
    return
end
shell.execute(PATH, nil, table.unpack({...}))
