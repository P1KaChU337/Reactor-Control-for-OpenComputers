-- Reactor Control: установка. Старая команда установки ведёт сюда — теперь она ставит v2.
--   wget -fq https://github.com/P1KaChU337/Reactor-Control-for-OpenComputers/raw/refs/heads/main/installer/installer.lua ins && ins
local shell = require("shell")
local fs = require("filesystem")

local URL = "https://raw.githubusercontent.com/P1KaChU337/Reactor-Control-for-OpenComputers/main/installer/install_v2.lua"
local PATH = "/home/rc_install.lua"

if fs.exists(PATH) then fs.remove(PATH) end
shell.execute("wget -fq " .. URL .. " " .. PATH)
if not fs.exists(PATH) or fs.size(PATH) == 0 then
    io.stderr:write("Не удалось скачать установщик. Проверьте интернет-карту.\n")
    return
end
shell.execute(PATH, nil, ...)
