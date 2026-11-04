-- Reactor Control: переход с v1 на v2.
-- Этот файл скачивает и запускает старая программа v1, когда видит в versions.txt новую версию.
-- Он ставит v2 без вопросов: настройки v1 переносятся, автозапуск переключается на v2,
-- компьютер перезагружается и запускается новая программа. Файлы v1 остаются на месте.
local shell = require("shell")
local fs = require("filesystem")

local URL = "https://raw.githubusercontent.com/P1KaChU337/Reactor-Control-for-OpenComputers/main/installer/install_v2.lua"
local PATH = "/home/rc_install.lua"

print("Reactor Control: обновление до v2...")
os.execute("rm /home/oldVersion.txt > /dev/null 2>&1")
os.execute("rm oldVersion.txt > /dev/null 2>&1")
if fs.exists(PATH) then fs.remove(PATH) end
shell.execute("wget -fq " .. URL .. " " .. PATH)
if not fs.exists(PATH) or fs.size(PATH) == 0 then
    io.stderr:write("Не удалось скачать установщик v2. Проверьте интернет-карту и выполните:\n")
    io.stderr:write("wget -fq " .. URL .. " " .. PATH .. " && " .. PATH .. "\n")
    return
end
shell.execute(PATH, nil, "--auto")
