-- Reactor Control v1.1 build 3

-- ----------------------------------------------------------------------------------------------------
local computer = require("computer")
local image = require("image")
local buffer = require("doubleBuffering")
local shell = require("shell")
local event = require("event")
local component = require("component")
local fs = require("filesystem")
local term = require("term")
local unicode = require("unicode")
local bit = require("bit32")
-- ----------------------------------------------------------------------------------------------------

buffer.setResolution(160, 50)
buffer.clear(0x000000)

local lastTime = computer.uptime()
local exit = false
local version = "1.1"
local build = "3"
local progVer = version .. "." .. build

local imagesFolder = "/home/images/" -- Путь к изображению
local dataFolder = "/home/data/"
local imgPath = imagesFolder .. "reactorGUI.pic"
local imgPathWhite = imagesFolder .. "reactorGUI_white.pic"
local configPath = dataFolder .. "config.lua"

if not fs.exists(imagesFolder) then
    fs.makeDirectory(imagesFolder)
end
if not fs.exists(dataFolder) then
    fs.makeDirectory(dataFolder)
end
if not fs.exists(configPath) then
    local file = io.open(configPath, "w")
    if file then
        file:write("-- Конфигурация программы Reactor Control v" .. version .."\n")
        file:write("-- Прежде чем что-то изменять, пожалуйста внимательно читайте описание!\n\n")
        file:write("porog = 50000 -- Минимальное значение порога жидкости в mB\n\n")
        file:write("-- Впишите никнеймы игроков которым будет разрешеннен доступ к ПК, обязательно ради вашей безопасности!\n")
        file:write("users = {} -- Пример: {\"P1KaChU337\", \"Nickname1\"} -- Именно что с кавычками и запятыми!\n")
        file:write("usersold = {} -- Не трогайте, может заблокировать ПК!\n\n")
        file:write("-- Тема интерфейса в системе по стандарту\n")
        file:write("theme = false -- (false темная, true светлая)\n\n")
        file:write("updateCheck = true -- (false не проверять на наличие обновлений, true проверять обновления)\n\n")
        file:write("debugLog = false\n\n")
        file:write("isFirstStart = true\n\n")
        file:write("-- После внесение изменений сохраните данные (Ctrl+S) и выйдите из редактора (Ctrl+W)\n")
        file:write("-- Если в будущем захотите поменять данные то пропишите \"cd data\" затем \"edit config.lua\"\n")
        file:close()
        shell.setWorkingDirectory("/home/data")
        shell.execute("edit config.lua")
        shell.setWorkingDirectory("/home")
    else
        io.stderr:write("Ошибка: не удалось создать файл " .. configPath .. "\n")
    end
end

local ok, err = pcall(function()
    dofile(configPath)
end)
if not ok then
    io.stderr:write("Ошибка загрузки конфига: " .. tostring(err) .. "\n")
    return
end

local any_reactor_on = false
local any_reactor_off = false

local reactors = 0
local metric = 0
local status_metric = "Auto"
local metricRf = "Rf"
local metricMb = "Mb"
local second = 0
local minute = 0
local hour = 0
local testvalue = 0
local rf = 0
local fluidInMe = 0
local ismechecked = false
local flux_network = false
local flux_checked = false

local consoleLines = {}
local work = false
local starting = false
local offFluid = false

local reactor_work       = {}
local reactor_aborted    = {}
local temperature        = {}
local reactor_type       = {}
local reactor_address    = {}
local reactors_proxy     = {}
local reactor_rf         = {}
local reactor_getcoolant = {}
local reactor_maxcoolant = {}
local reactor_depletionTime = {}
local last_me_address = nil
local me_network = false
local me_proxy = nil
local lastValidFluid = 0
local maxThreshold = 10^12
local reason = nil
local depletionTime = 0
local consumeSecond = 0
local supportersText = nil
local MeSecond = 0

local isChatBox = component.isAvailable("chat_box") or false
local chatBox = isChatBox and component.chat_box or nil
local chatThread = nil
local chatCommands = {
    ["@help"] = true,
    ["@status"] = true,
    ["@setporog"] = true,
    ["@start"] = true,
    ["@stop"] = true,
    ["@restart"] = true,
    ["@exit"] = true,
    ["@changelog"] = true,
    ["@useradd"] = true,
    ["@userdel"] = true,
    ["@info"] = true
}

local widgetCoords = {
    {10, 6}, {36, 6}, {65, 6}, {91, 6},
    {10, 18}, {36, 18}, {65, 18}, {91, 18},
    {10, 30}, {36, 30}, {65, 30}, {91, 30}
}

local config = {
    clickArea19 = {x1=4,  y1=44, x2=9,  y2=46}, -- Кнопка 🔧 (x:5, y:44)
    clickArea20 = {x1=4,  y1=47, x2=9,  y2=49}, -- Кнопка ⓘ (x:5, y:47)

    clickArea1  = {x1=12,  y1=44, x2=37, y2=46}, -- Отключить реакторы (x:13, y:44)
    clickArea2  = {x1=12,  y1=47, x2=37, y2=49}, -- Рестарт программы (x:13, y:47)

    clickArea4  = {x1=40, y1=44, x2=64, y2=46}, -- Запуск реакторов (x:41, y:44)
    clickArea3  = {x1=40, y1=47, x2=64, y2=49}, -- Выход из программы (x:41, y:47)

    clickArea5  = {x1=67, y1=44, x2=86, y2=46}, -- Обновить МЭ (x:68, y:44)
    clickArea6  = {x1=67, y1=47, x2=86, y2=49}, -- Метрика (x:68, y:47)
    -- Координаты для кнопок на виджетах
    clickArea7 = {x1=widgetCoords[1][1]+5, y1=widgetCoords[1][2]+9, x2=widgetCoords[1][1]+11, y2=widgetCoords[1][2]+10}, -- Реактор 1
    clickArea8 = {x1=widgetCoords[2][1]+5, y1=widgetCoords[2][2]+9, x2=widgetCoords[2][1]+11, y2=widgetCoords[2][2]+10}, -- Реактор 2
    clickArea9 = {x1=widgetCoords[3][1]+5, y1=widgetCoords[3][2]+9, x2=widgetCoords[3][1]+11, y2=widgetCoords[3][2]+10}, -- Реактор 3
    clickArea10 = {x1=widgetCoords[4][1]+5, y1=widgetCoords[4][2]+9, x2=widgetCoords[4][1]+11, y2=widgetCoords[4][2]+10}, -- Реактор 4
    clickArea11 = {x1=widgetCoords[5][1]+5, y1=widgetCoords[5][2]+9, x2=widgetCoords[5][1]+11, y2=widgetCoords[5][2]+10}, -- Реактор 5
    clickArea12 = {x1=widgetCoords[6][1]+5, y1=widgetCoords[6][2]+9, x2=widgetCoords[6][1]+11, y2=widgetCoords[6][2]+10}, -- Реактор 6
    clickArea13 = {x1=widgetCoords[7][1]+5, y1=widgetCoords[7][2]+9, x2=widgetCoords[7][1]+11, y2=widgetCoords[7][2]+10}, -- Реактор 7
    clickArea14 = {x1=widgetCoords[8][1]+5, y1=widgetCoords[8][2]+9, x2=widgetCoords[8][1]+11, y2=widgetCoords[8][2]+10}, -- Реактор 8
    clickArea15 = {x1=widgetCoords[9][1]+5, y1=widgetCoords[9][2]+9, x2=widgetCoords[9][1]+11, y2=widgetCoords[9][2]+10}, -- Реактор 9
    clickArea16 = {x1=widgetCoords[10][1]+5, y1=widgetCoords[10][2]+9, x2=widgetCoords[10][1]+11, y2=widgetCoords[10][2]+10}, -- Реактор 10
    clickArea17 = {x1=widgetCoords[11][1]+5, y1=widgetCoords[11][2]+9, x2=widgetCoords[11][1]+11, y2=widgetCoords[11][2]+10}, -- Реактор 11
    clickArea18 = {x1=widgetCoords[12][1]+5, y1=widgetCoords[12][2]+9, x2=widgetCoords[12][1]+11, y2=widgetCoords[12][2]+10}, -- Реактор 12
    -- Координаты для кнопок в правом меню
    clickAreaPorogPlus = {x1=124, y1=36, x2=125, y2=33}, -- Кнопка "+ Порог"
    clickAreaPorogMinus = {x1=126, y1=36, x2=127, y2=33} -- Кнопка "- Порог"
}
local colors = {
    bg = 0x202020,
    bg2 = 0x101010,
    bg3 = 0x3c3c3c,
    bg4 = 0x969696,
    bg5 = 0xff0000,
    textclr = 0xcccccc,
    textbtn = 0xffffff,
    whitebtn = nil,
    whitebtn2 = 0x38afff,
    msginfo = 0x61ff52,
    msgwarn = 0xfff700,
    msgerror = 0xff0000,
}

-- ----------------------------------------------------------------------------------------------------

local function brailleChar(dots)
    return unicode.char(
        10240 +
        (dots[8] or 0) * 128 +
        (dots[7] or 0) * 64 +
        (dots[6] or 0) * 32 +
        (dots[4] or 0) * 16 +
        (dots[2] or 0) * 8 +
        (dots[5] or 0) * 4 +
        (dots[3] or 0) * 2 +
        (dots[1] or 0)
    )
end

local braill0 = {
    {1,1,1,0,1,0,1,0},
    {1,0,1,0,1,0,1,0},
    {1,1,0,0,0,0,0,0},
    {1,0,0,0,0,0,0,0},
}
local braill1 = {
    {0,1,1,1,0,1,0,1},
    {0,0,0,0,0,0,0,0},
    {1,1,0,0,0,0,0,0},
    {1,0,0,0,0,0,0,0},
}
local braill2 = {
    {1,1,0,0,1,1,1,0},
    {1,0,1,0,1,0,0,0},
    {1,1,0,0,0,0,0,0},
    {1,0,0,0,0,0,0,0},
}
local braill3 = {
    {1,1,0,0,1,1,0,0},
    {1,0,1,0,1,0,1,0},
    {1,1,0,0,0,0,0,0},
    {1,0,0,0,0,0,0,0},
}
local braill4 = {
    {1,0,1,0,1,1,0,0},
    {1,0,1,0,1,0,1,0},
    {0,0,0,0,0,0,0,0},
    {1,0,0,0,0,0,0,0},
}
local braill5 = {
    {1,1,1,0,1,1,0,0},
    {1,0,0,0,1,0,1,0},
    {1,1,0,0,0,0,0,0},
    {1,0,0,0,0,0,0,0},
}
local braill6 = {
    {1,1,1,0,1,1,1,0},
    {1,0,0,0,1,0,1,0},
    {1,1,0,0,0,0,0,0},
    {1,0,0,0,0,0,0,0},
}
local braill7 = {
    {1,1,0,0,0,0,0,0},
    {1,0,1,0,1,0,1,0},
    {0,0,0,0,0,0,0,0},
    {1,0,0,0,0,0,0,0},
}
local braill8 = {
    {1,1,1,0,1,1,1,0},
    {1,0,1,0,1,0,1,0},
    {1,1,0,0,0,0,0,0},
    {1,0,0,0,0,0,0,0},
}
local braill9 = {
    {1,1,1,0,1,1,0,0},
    {1,0,1,0,1,0,1,0},
    {1,1,0,0,0,0,0,0},
    {1,0,0,0,0,0,0,0},
}
local braill_minus = {
    {0,0,0,0,1,1,0,0},
    {0,0,0,0,1,0,0,0},
    {0,0,0,0,0,0,0,0},
    {0,0,0,0,0,0,0,0},
}
local braill_dot = {
    {0,0,0,0,0,0,0,0},
    {0,0,0,0,0,0,0,0},
    {1,0,0,0,0,0,0,0},
    {0,0,0,0,0,0,0,0},
}

local brail_console = {
    {0,0,0,0,1,1,1,1},
    {0,0,1,1,0,0,0,0}
}

local brail_fluid = {
    {0,1,0,1,1,1,1,1},
    {1,0,1,0,1,1,1,1},
    {1,1,0,1,0,0,0,0},
    {1,1,1,0,0,0,0,0}
}

local brail_greenbtn = {
    {0,0,0,1,1,1,0,1},
    {0,0,0,0,1,0,0,0},
    {0,0,0,0,0,0,0,0},
    {0,0,0,0,0,0,0,0},
}

local brail_redbtn = {
    {0,0,0,0,0,1,0,0},
    {0,0,0,0,1,1,0,0},
    {0,0,0,0,0,0,0,0},
    {0,0,0,0,0,0,0,0},
}

local brail_thunderbolt = {
    {0,0,0,0,0,1,0,0},
    {0,1,1,0,1,1,0,1},
    {0,0,0,1,0,0,0,0},
    {1,0,0,0,0,0,0,0},
}

local brail_cherta = {
    {1,0,1,0,1,0,1,0},
    {1,0,1,1,1,0,1,0},
    {0,0,0,0,1,0,1,0},
    {1,0,1,0,1,0,1,0},
    {0,0,1,1,0,1,0,1},
    {0,1,0,1,0,1,0,1},
    {0,0,1,1,1,0,1,0},
}

local brail_time = {
    {1,1,1,0,0,1,1,0},
    {1,1,0,1,1,0,0,1},
    {1,0,1,1,0,0,0,0},
    {0,1,1,1,0,0,0,0},
}

local button1 = {
    {0,0,0,0,1,1,1,1},
    {0,0,0,0,1,0,1,1},
    {1,1,1,1,1,1,1,1},
    {0,0,0,0,0,1,1,1},
    {1,1,0,1,0,0,0,0},
    {1,1,1,0,0,0,0,0},
    {1,1,1,1,0,0,0,0},
    {1,1,1,1,1,1,1,0},
    {1,1,1,1,1,1,0,1},
}

local button1_push = {
    {0,0,0,0,0,0,1,1},
    {0,0,0,0,0,0,1,0},
    {1,1,1,1,1,1,1,1},
    {0,0,0,0,0,0,0,1},
    {0,1,0,0,0,0,0,0},
    {1,0,0,0,0,0,0,0},
    {1,1,0,0,0,0,0,0},
}

local brail_status = {
    {0,0,0,1,1,1,1,1}, -- Уголки
    {0,0,1,0,1,1,1,1},
    {1,1,1,1,1,0,0,0},
    {1,1,1,1,0,1,0,0},
}

local brail_fields = {
    {0,0,0,0,0,1,1,1},
    {0,0,0,0,1,0,1,1},
    {1,1,1,0,0,0,0,0},
    {1,1,0,1,0,0,0,0},
    {1,1,0,0,1,1,1,1},
    {1,1,1,1,0,0,0,0},
}
local brail_verticalbar = {
    {0,0,0,0,0,0,1,1},
    {0,0,0,0,1,1,1,1},
    {0,0,1,1,1,1,1,1},
    {1,1,1,1,1,1,1,1},
}

-- ----------------------------------------------------------------------------------------------------
local function saveCfg(param)
    local file = io.open(configPath, "w")
    if not file then
        io.stderr:write("Ошибка: не удалось открыть файл для записи.\n")
        return
    end

    file:write("-- Конфигурация программы Reactor Control v" .. version .."\n")
    file:write("-- Прежде чем что-то изменять, пожалуйста внимательно читайте описание!\n\n")
    file:write(string.format("porog = %d -- Минимальное значение порога жидкости в mB\n\n", math.max(0, porog)))
    
    -- users
    file:write("-- Впишите никнеймы игроков которым будет разрешеннен доступ к ПК, обязательно ради вашей безопасности!\n")
    file:write("users = {")
    for i, user in ipairs(users) do
        file:write(string.format("%q", user))
        if i < #users then
            file:write(", ")
        end
    end
    file:write("} -- Пример: {\"P1KaChU337\", \"Nickname1\"} -- Именно что с кавычками и запятыми!\n")

    file:write("usersold = {")
    for i, user in ipairs(usersold) do
        file:write(string.format("%q", user))
        if i < #users then
            file:write(", ")
        end
    end
    file:write("} -- Не трогайте вообще, даже при удалении пользователей, оставьте оно само очистится, можно трогать только users но не usersold, может заблокировать ПК!\n\n")
    
    -- theme
    file:write("-- Тема интерфейса в системе по стандарту\n")
    file:write(string.format("theme = %s -- Тема интерфейса (false тёмная, true светлая)\n\n", tostring(theme)))
    file:write(string.format("updateCheck = %s -- (false не проверять на наличие обновлений, true проверять обновления)\n\n", tostring(updateCheck)))
    file:write(string.format("debugLog = %s\n\n", tostring(debugLog)))
    file:write(string.format("isFirstStart = %s\n\n", tostring(isFirstStart)))
    file:write("-- После внесение изменений сохраните данные (Ctrl+S) и выйдите из редактора (Ctrl+W)\n")
    file:write("-- Для запуска основой программы перейдите в домашнюю директорию \"cd ..\", и напишите \"main.lua\"\n")
    
    file:close()
end

local function switchTheme(val)
    if theme == true then
        colors = {
            bg = 0x000000,
            bg2 = 0x202020,
            bg3 = 0xffffff,
            bg4 = 0x5a5a5a,
            bg5 = 0xff0000,
            textclr = 0x3f3f3ff,
            textbtn = 0x303030,
            whitebtn = nil,
            whitebtn2 = 0x38afff,
            msginfo = 0x61ff52,
            msgwarn = 0xfff700,
            msgerror = 0xff0000,
        }
        saveCfg()
    else
        colors = {
            bg = 0x202020,
            bg2 = 0x101010,
            bg3 = 0x3c3c3c,
            bg4 = 0x969696,
            bg5 = 0xff0000,
            textclr = 0xcccccc,
            textbtn = 0xffffff,
            whitebtn = nil,
            whitebtn2 = 0x38afff,
            msginfo = 0x61ff52,
            msgwarn = 0xfff700,
            msgerror = 0xff0000,
        }
        saveCfg()
    end
end

local function initReactors()
    reactors = 0
    reactor_address = {}
    reactors_proxy = {}

    for address, ctype in component.list("htc_reactors") do
        reactors = reactors + 1
        reactor_address[reactors] = address
        reactors_proxy[reactors] = component.proxy(address)
        if reactors >= 12 then
            break
        end
    end
    for i = 1, reactors do
        reactor_rf[i] = 0
        reactor_getcoolant[i] = 0
        reactor_maxcoolant[i] = 0
        temperature[i] = 0
        reactor_aborted[i] = false
        reactor_depletionTime[i] = 0
    end
end

local function initMe()
    me_network = component.isAvailable("me_controller") or component.isAvailable("me_interface")
    if me_network == true then
        if component.isAvailable("me_controller") then
            local addr = component.list("me_controller")()
            me_proxy = component.proxy(addr)
            current_me_address = addr
        elseif component.isAvailable("me_interface") then
            local addr = component.list("me_interface")()
            me_proxy = component.proxy(addr)
            current_me_address = addr
        else
            me_proxy = nil
            current_me_address = nil
        end
    else
        offFluid = true
        reason = "МЭ не найдена!"
    end
    return current_me_address
end

local function initChatBox()
    isChatBox = component.isAvailable("chat_box") or false
    if isChatBox then
        chatBox = component.chat_box
        chatBox.setName("§6§lКомплекс§7§o")
    end
end

local function initFlux()
    flux_network = (component.isAvailable("flux_controller") and true or false)
end

local function drawDigit(x, y, braill, color)
    buffer.drawText(x,     y,     color, brailleChar(braill[1]))
    buffer.drawText(x,     y + 1, color, brailleChar(braill[3]))
    buffer.drawText(x + 1, y,     color, brailleChar(braill[2]))
    buffer.drawText(x + 1, y + 1, color, brailleChar(braill[4]))
end

-- Работа с текстом
local function centerText(text, totalWidth)
    local textLen = unicode.len(text)
    local pad = math.floor((totalWidth - textLen) / 2)
    if pad < 0 then pad = 0 end
    return string.rep(" ", pad) .. text
end

local function shortenNameCentered(name, maxLength)
    maxLength = maxLength or 12
    if unicode.len(name) > maxLength then
        name = unicode.sub(name, 1, maxLength - 3) .. "..."
    end
    return centerText(name, maxLength)
end

-- local function centerMSG(x, y, msg, color)
--     local len = unicode.len(msg)
--     local startX = x - math.floor(len / 2)
--     buffer.drawText(startX, y, color, msg)
--     buffer.drawChanges()
-- end

-- ----------------------------------------------------------------------------------------------------
local function animatedButton(push, x, y, text, tx, ty, length, time, clearWidth, color, textcolor)
    local btn = push == 1 and button1 or button1_push
    local bgColor = color or 0x059bff
    local tColor = textcolor or colors.textbtn
    local clear = clearWidth or length
    if not text then tx = x  end
    local ftext = text or "* Клик *"
    local ftx = tx or x
    local fty = ty or y + 1
    local ftime = time or 0.3

    if push == 1 then
        buffer.drawRectangle(x, y + 1, length, 1, bgColor, 0, " ")
        buffer.drawText(ftx, fty, tColor, shortenNameCentered(ftext, length))
    end
    -- Левая граница
    buffer.drawText(x - 1, y, bgColor, brailleChar(btn[4]))
    buffer.drawText(x - 1, y + 1, bgColor, brailleChar(btn[3]))
    buffer.drawText(x - 1, y + 2, bgColor, brailleChar(btn[5]))

    -- Правая граница
    buffer.drawText(x + length, y, bgColor, brailleChar(btn[2]))
    buffer.drawText(x + length, y + 1, bgColor, brailleChar(btn[3]))
    buffer.drawText(x + length, y + 2, bgColor, brailleChar(btn[6]))

    -- Центральная линия
    for i = 0, length - 1 do
        buffer.drawText(x + i, y,     bgColor, brailleChar(btn[1]))
        buffer.drawText(x + i, y + 2, bgColor, brailleChar(btn[7]))
    end

    if push == 0 and clearWidth and clearWidth > length then
        buffer.drawText(x - 2, y + 1, tColor, " ")
        buffer.drawText(x - 2, y, tColor, " ")
        buffer.drawText(x - 2, y + 2, tColor, " ")
        buffer.drawText(x + length + 1, y + 1, tColor, " ")
        buffer.drawText(x + length + 1, y, tColor, " ")
        buffer.drawText(x + length + 1, y + 2, tColor, " ")
        buffer.drawRectangle(x, y + 1, length, 1, bgColor, 0, " ")
        buffer.drawText(ftx, fty, tColor, shortenNameCentered(ftext, length))
    end

    if push == 0 then os.sleep(ftime) end
end

-- ----------------------------------------------------------------------------------------------------
local function lerpColor(c1, c2, t)
    local r1, g1, b1 = bit.rshift(c1, 16) % 0x100, bit.rshift(c1, 8) % 0x100, c1 % 0x100
    local r2, g2, b2 = bit.rshift(c2, 16) % 0x100, bit.rshift(c2, 8) % 0x100, c2 % 0x100
    local r = r1 + (r2 - r1) * t
    local g = g1 + (g2 - g1) * t
    local b = b1 + (b2 - b1) * t
    return bit.lshift(math.floor(r), 16) + bit.lshift(math.floor(g), 8) + math.floor(b)
end

-- НЕВЕРОЯТНЫЙ КОСТЫЛЬ, ПРОСТИТЕ)
local function safeCallwg(proxy, method, default, ...)
    if proxy and proxy[method] then
        local ok, result = pcall(proxy[method], proxy, ...)
        if ok and result ~= nil then
            -- Для числовых значений по умолчанию гарантируем возврат числа
            if type(default) == "number" then
                local numberResult = tonumber(result)
                if numberResult then
                    return numberResult
                else
                    -- Логируем нечисловой результат
                    local logFile = io.open("/home/reactor_errors.log", "a")
                    if logFile then
                        logFile:write(string.format("[%s] safeCall non-number error: method=%s, result=%s\n",
                            os.date("%Y-%m-%d %H:%M:%S"),
                            tostring(method),
                            tostring(result)))
                        logFile:close()
                    end
                    return default
                end
            else
                return result
            end
        else
            -- Логируем ошибку
            local logFile = io.open("/home/reactor_errors.log", "a")
            if logFile then
                logFile:write(string.format("[%s] safeCall error: method=%s, result=%s\n",
                    os.date("%Y-%m-%d %H:%M:%S"),
                    tostring(method),
                    tostring(result)))
                logFile:close()
            end

            -- Убрал рекурсивный вызов safeCall чтобы избежать потенциальной бесконечной рекурсии
            -- Вместо этого просто возвращаем значение по умолчанию
            return default
        end
    end
    return default
end

local function secondsToHMS(totalSeconds)
    if type(totalSeconds) ~= "number" or totalSeconds < 0 then
        totalSeconds = 0
    end
    local hours   = math.floor(totalSeconds / 3600)
    local minutes = math.floor((totalSeconds % 3600) / 60)
    local seconds = math.floor(totalSeconds % 60)
    return string.format("%02d:%02d:%02d", hours, minutes, seconds)
end

local function getDepletionTime(num)
    if reactors == 0 then
        return 0
    end

    local minReactorTime = math.huge
    
    if #reactor_depletionTime == 0 then
        for i = 1, reactors do
            reactor_depletionTime[i] = 0
        end
    end

    for i = 1, reactors do
        local rods = safeCallwg(reactors_proxy[i], "getAllFuelRodsStatus", nil)
        local isFluid = reactor_type[i] == "Fluid"
        local reactorTime = 0

        if type(rods) == "table" and #rods > 0 then
            local maxRod = 0
            for _, rod in ipairs(rods) do
                if type(rod) == "table" and rod[6] then
                    -- Добавлена проверка на число
                    local fuelLeft = tonumber(rod[6]) or 0
                    if isFluid then
                        fuelLeft = fuelLeft / 2
                    end
                    if fuelLeft > maxRod then
                        maxRod = fuelLeft
                    end
                end
            end

            reactorTime = maxRod
            reactor_depletionTime[i] = reactorTime
            
            if reactorTime > 0 and reactorTime < minReactorTime then
                minReactorTime = reactorTime
            end
        else
            reactor_depletionTime[i] = 0
        end
    end

    if minReactorTime == math.huge then
        return 0
    else
        return math.floor(minReactorTime or 0)
    end
end

local function drawVerticalProgressBar(x, y, height, value, maxValue, colorBottom, colorTop, colorInactive)
    if not maxValue or maxValue <= 0 then
        maxValue = 1
    end
    if not value or value < 0 then
        value = 0
    end
    value = math.min(value, maxValue)
    if value > maxValue then
        value = maxValue
    end

    local totalParts = height * 4
    local filledParts = math.floor(totalParts * (value / maxValue))

    buffer.drawRectangle(x, y, 1, height, colorInactive, 0, " ")

    local fullBlocks = math.floor(filledParts / 4)
    local remainder = filledParts % 4

    for i = 0, fullBlocks - 1 do
        local pos = (i + 1) / height
        local clr = lerpColor(colorBottom, colorTop, pos)
        buffer.drawText(x, y + height - i - 1, clr, brailleChar(brail_verticalbar[4]))
    end

    if remainder > 0 then
        local pos = (fullBlocks + 1) / height
        local clr = lerpColor(colorBottom, colorTop, pos)
        buffer.drawText(x, y + height - fullBlocks - 1, clr, brailleChar(brail_verticalbar[remainder]))
    end
end


local function formatRFwidgets(value)
    if type(value) ~= "number" then
        return "Ген: 0 RF/t"
    end

    local suffixes = {"", "k", "m", "g"}
    local i = 1

    if value < 10000 then
        return "Ген: " .. tostring(value) .. " RF/t"
    end

    while value >= 1000 and i < #suffixes do
        value = value / 1000
        i = i + 1
    end

    local str = string.format("%.1f", value)
    str = str:gsub("%.0$", "")

    return "Ген: " .. str .. " " .. suffixes[i] .. "RF/t"
end


local function drawWidgets()
    if reactors <= 0 then
        buffer.drawRectangle(5, 5, 114, 37, colors.bg4, 0, " ")
        buffer.drawRectangle(37, 19, 50, 3, colors.bg2, 0, " ")
        buffer.drawRectangle(36, 20, 52, 1, colors.bg2, 0, " ")
        local cornerPos = {
            {36, 19, 1}, {87, 19, 2},
            {87, 21, 3}, {36, 21, 4}
        }
        for _, c in ipairs(cornerPos) do
            buffer.drawText(c[1], c[2], colors.bg2, brailleChar(brail_status[c[3]]))
        end
        buffer.drawText(43, 20, 0xcccccc, "У вас не подключенно ни одного реактора!")
        buffer.drawText(40, 20, 0xffd900, "⚠")
        return
    end

    buffer.drawRectangle(5, 5, 114, 37, colors.bg4, 0, " ")

    for i = 1, math.min(reactors, #widgetCoords) do
        if reactor_aborted[i] == false then
            local x, y = widgetCoords[i][1], widgetCoords[i][2]
            buffer.drawRectangle(x + 1, y, 20, 11, colors.bg, 0, " ")
            buffer.drawRectangle(x, y + 1, 22, 9, colors.bg, 0, " ")

            buffer.drawText(x,  y,  colors.bg, brailleChar(brail_status[1]))
            buffer.drawText(x + 21, y,  colors.bg, brailleChar(brail_status[2]))
            buffer.drawText(x + 21, y + 10,  colors.bg, brailleChar(brail_status[3]))
            buffer.drawText(x,  y + 10,  colors.bg, brailleChar(brail_status[4]))

            if reactor_work[i] then
                if (reactor_depletionTime[i] or 0) <= 0 then
                    local newTime = getDepletionTime(i)
                    if newTime > 0 then
                        reactor_depletionTime[i] = newTime
                    else
                        reactor_depletionTime[i] = 0
                    end
                else
                    reactor_depletionTime[i] = reactor_depletionTime[i] - 1
                end
            else
                reactor_depletionTime[i] = 0
            end

            buffer.drawText(x + 6,  y + 1,  colors.textclr, "Реактор #" .. i)
            buffer.drawText(x + 4,  y + 3,  colors.textclr, "Нагрев: " .. (temperature[i] or "-") .. "°C")
            buffer.drawText(x + 4,  y + 4,  colors.textclr, formatRFwidgets(reactor_rf[i]))
            buffer.drawText(x + 4,  y + 5,  colors.textclr, "Тип: " .. (reactor_type[i] or "-"))
            buffer.drawText(x + 4,  y + 6,  colors.textclr, "Запущен: " .. (reactor_work[i] and "Да" or "Нет"))
            buffer.drawText(x + 4,  y + 7,  colors.textclr, "Распад: " .. secondsToHMS(reactor_depletionTime[i] or 0))
            animatedButton(1, x + 6, y + 8, (reactor_work[i] and "Отключить" or "Включить"), nil, nil, 10, nil, nil, (reactor_work[i] and 0xfd3232 or 0x2beb1a))
            if reactor_type[i] == "Fluid" then
                drawVerticalProgressBar(x + 1, y + 1, 9, reactor_getcoolant[i], reactor_maxcoolant[i], 0x0044FF, 0x00C8FF, colors.bg2)
            end
        else
            local x, y = widgetCoords[i][1], widgetCoords[i][2]
            buffer.drawRectangle(x + 1, y, 20, 11, colors.msgwarn, 0, " ")
            buffer.drawRectangle(x, y + 1, 22, 9, colors.msgwarn, 0, " ")

            buffer.drawText(x,  y,  colors.msgwarn, brailleChar(brail_status[1]))
            buffer.drawText(x + 21, y,  colors.msgwarn, brailleChar(brail_status[2]))
            buffer.drawText(x + 21, y + 10,  colors.msgwarn, brailleChar(brail_status[3]))
            buffer.drawText(x,  y + 10,  colors.msgwarn, brailleChar(brail_status[4]))

            buffer.drawText(x + 6,  y + 1,  colors.msgerror, "Реактор #" .. i)
            buffer.drawText(x + 4,  y + 3,  colors.msgerror, "Нагрев: " .. (temperature[i] or "-") .. "°C")
            buffer.drawText(x + 4,  y + 4,  colors.msgerror, "Тип: " .. (reactor_type[i] or "-"))
            buffer.drawText(x + 4,  y + 5,  colors.msgerror, "Cтатус:")
            buffer.drawText(x + 4,  y + 6,  colors.msgerror, "Аварийно отключен!")
            buffer.drawText(x + 4,  y + 7,  colors.msgerror, "Причина:")
            buffer.drawText(x + 4,  y + 8,  colors.msgerror, (reason or "Неизвестная ошибка!"))
            if reactor_type[i] == "Fluid" then
                drawVerticalProgressBar(x + 1, y + 1, 9, reactor_getcoolant[i], reactor_maxcoolant[i], 0x0044FF, 0x00C8FF, colors.bg2)
            end
        end
    end
end

local braillMap = {
    [0] = braill0,
    [1] = braill1,
    [2] = braill2,
    [3] = braill3,
    [4] = braill4,
    [5] = braill5,
    [6] = braill6,
    [7] = braill7,
    [8] = braill8,
    [9] = braill9,
    ["-"] = braill_minus,
    ["."] = braill_dot,
}

local function drawNumberWithText(centerX, centerY, number, digitWidth, color, suffix, suffixColor)
    suffixColor = suffixColor or color

    local digits = {}
    local widths = {}
    local strNum = tostring(number)

    for i = 1, #strNum do
        local ch = strNum:sub(i, i)
        local n = tonumber(ch)
        if n then
            table.insert(digits, braillMap[n])
            table.insert(widths, digitWidth)
        elseif braillMap[ch] then
            table.insert(digits, braillMap[ch])
            if ch == "." then
                table.insert(widths, 1)
            else
                table.insert(widths, digitWidth)
            end
        end
    end

    local suffixWidth = suffix and #suffix or 0
    local totalWidth = 0
    for _, w in ipairs(widths) do totalWidth = totalWidth + w end
    totalWidth = totalWidth + (suffixWidth > 0 and (suffixWidth + 1) or 0)

    local startX = math.floor(centerX - totalWidth / 2)

    buffer.drawText(startX, centerY, colors.bg, string.rep(" ", totalWidth))

    local x = startX
    for i, digit in ipairs(digits) do   
        drawDigit(x, centerY, digit, color)
        x = x + widths[i]
    end

    if suffix and suffixWidth > 0 then
        buffer.drawText(x, centerY, suffixColor, suffix)
    end
end

local function darkenColor(baseColor, t)
    return lerpColor(baseColor, 0x303030, 1 - t)
end

local function utf8len(str)
    local _, count = str:gsub("[^\128-\191]", "")
    return count
end

-- вырезаем подстроку по символам
local function utf8sub(str, startChar, numChars)
    local startIndex = 1
    while startChar > 1 do
        local c = str:byte(startIndex)
        if not c then break end
        if c < 128 or c >= 192 then
            startChar = startChar - 1
        end
        startIndex = startIndex + 1
    end

    local currentIndex = startIndex
    while numChars > 0 and currentIndex <= #str do
        local c = str:byte(currentIndex)
        if not c then break end
        if c < 128 or c >= 192 then
            numChars = numChars - 1
        end
        currentIndex = currentIndex + 1
    end

    return str:sub(startIndex, currentIndex - 1)
end

-- перенос текста с учётом UTF-8
local function wrapText(msg, limit)
    local result = {}
    limit = limit or 34

    while utf8len(msg) > limit do
        local chunk = utf8sub(msg, 1, limit)
        local spacePos = chunk:match(".*()%s")

        if spacePos then
            -- перенос по пробелу
            table.insert(result, msg:sub(1, spacePos - 1))
            msg = msg:sub(spacePos + 1)
        else
            -- перенос с дефисом
            table.insert(result, utf8sub(msg, 1, limit - 1) .. "-")
            msg = utf8sub(msg, limit)
        end
    end

    if utf8len(msg) > 0 then
        table.insert(result, msg)
    end

    return result
end

local scrollPos = 1
local maxWidth = 33

-- функция бегущей строки
local function drawMarquee(x, y, text, color)
    local textLength = unicode.len(text) -- считаем символы, а не байты

    if textLength > maxWidth then
        -- видимый кусок
        local visible = unicode.sub(text, scrollPos, scrollPos + maxWidth - 1)

        local visibleLen = unicode.len(visible)
        if visibleLen < maxWidth then
            local need = maxWidth - visibleLen
            visible = visible .. unicode.sub(text, 1, need)
        end

        buffer.drawText(x, y, color, visible)

        scrollPos = scrollPos + 1
        if scrollPos > textLength then
            scrollPos = 1
        end
    else
        buffer.drawText(x, y, color, text)
    end
    buffer.drawChanges()
end

if not fs.exists("tmp") then
    fs.makeDirectory("tmp")
end
local function loadSupportersFromURL(url, tmpFile)
    tmpFile = tmpFile or "/tmp/supporters.txt"
    os.execute("wget -fq " .. url .. " " .. tmpFile .. " > /dev/null 2>&1")

    local f = io.open(tmpFile, "r")
    local content = f:read("*l")
    f:close()
    os.execute("rm /tmp/supporters.txt > /dev/null 2>&1")
    return content
end

local function drawRightMenu()
    local startColor = colors.textclr
    local endColor   = colors.textclr
    local totalLines = #consoleLines
    local windowHeight = flux_network and 19 or 22
    buffer.drawRectangle(123, 5, 35, windowHeight, colors.bg, 0, " ")
    
    for i = 1, math.min(totalLines, windowHeight) do
        local entry = consoleLines[i]
        local t = (i - 1) / math.max(totalLines - 1, 1)
        local baseColor = entry.color or lerpColor(startColor, endColor, t)
        local alpha = 1 - t
        buffer.drawText(124, 4 + i, baseColor, entry.text or "", alpha)
    end

    if supportersText then
        buffer.drawText(124, 5, colors.textclr, "Спасибо за поддержку на Boosty:")
        buffer.drawText(148, 5, 0xF15F2C, "Boosty")
        drawMarquee(124, 6, supportersText ..  "                            ", 0xF15F2C)
    end
    
    buffer.drawChanges()
end



local function message(msg, colormsg, limit, noStack)
    limit = limit or 34
    msg = tostring(msg)

    -- режем сообщение
    local parts = wrapText(msg, limit)

    local found = false

    if not noStack then
        -- ищем совпадение среди последних строк
        for i = #consoleLines, 11, -1 do
            local line = consoleLines[i]
            if line.textBase == msg then
                line.count = (line.count or 1) + 1

                -- пересобираем все части, икс только на последней
                local lastPart = parts[#parts] .. "(x" .. line.count .. ")"

                -- если влезает → заменяем последнюю строку
                if utf8len(lastPart) <= limit then
                    -- обновляем существующие строки
                    for j = 1, #parts - 1 do
                        local idx = i - (#parts - j)
                        if consoleLines[idx] then
                            consoleLines[idx].text = parts[j]
                        end
                    end
                    consoleLines[i].text = lastPart
                    found = true
                end

                break
            end
        end
    end

    -- если не нашли или не влезло → добавляем как новые строки
    if not found then
        for _, part in ipairs(parts) do
            table.remove(consoleLines, 1)
            table.insert(consoleLines, {
                text = part,
                textBase = msg, -- вся строка как ключ для стака
                color = colormsg,
                count = 1
            })
        end
    end

    drawRightMenu()
end


local function userUpdate()
    if not users or type(users) ~= "table" then
        message("Ошибка: users должен быть таблицей", nil, 34)
        return
    end

    if #users == 0 then
        message("Компьютер не защищен!", colors.msgwarn, 34)
        message("Перейдите в настройки и добавьте никнеймы в белый список", colors.msgwarn, 34)
    end

    local desiredUsers = {}
    for _, name in ipairs(users) do
        desiredUsers[name] = true
    end

    for _, name in ipairs(users) do
        local found = false
        for _, old in ipairs(usersold) do
            if old == name then
                found = true
                break
            end
        end
        if not found then
            table.insert(usersold, name)
            message("Добавлен новый пользователь:", nil, 34)
            message(name, nil, 34)
            computer.addUser(name)
            saveCfg()
        end
    end

    local i = 1
    while i <= #usersold do
        local name = usersold[i]
        if not desiredUsers[name] then
            table.remove(usersold, i)
            message("Пользователь удален:", nil, 34)
            message(name, nil, 34)
            computer.removeUser(name)
            saveCfg()
        else
            i = i + 1
        end
    end
end


local function safeCall(proxy, method, default, ...)
    if proxy and proxy[method] then
        local ok, result = pcall(proxy[method], proxy, ...)
        if ok and result ~= nil then
            -- Для числовых значений по умолчанию гарантируем возврат числа
            if type(default) == "number" then
                local numberResult = tonumber(result)
                if numberResult then
                    return numberResult
                else
                    -- Логируем нечисловой результат
                    local logFile = io.open("/home/reactor_errors.log", "a")
                    if logFile then
                        logFile:write(string.format("[%s] safeCall non-number error: method=%s, result=%s\n",
                            os.date("%Y-%m-%d %H:%M:%S"),
                            tostring(method),
                            tostring(result)))
                        logFile:close()
                    end
                    return default
                end
            else
                return result
            end
        else
            -- Логируем ошибку
            local logFile = io.open("/home/reactor_errors.log", "a")
            if logFile then
                logFile:write(string.format("[%s] safeCall error: method=%s, result=%s\n",
                    os.date("%Y-%m-%d %H:%M:%S"),
                    tostring(method),
                    tostring(result)))
                logFile:close()
            end

            if debugLog == true then
                message("'" .. method .. "': " .. tostring(result), colors.msgwarn, 34)
            end

            -- Убрал рекурсивный вызов safeCall чтобы избежать потенциальной бесконечной рекурсии
            -- Вместо этого просто возвращаем значение по умолчанию
            return default
        end
    end
    return default
end

local function checkReactorStatus(num)
    any_reactor_on = false
    any_reactor_off = false

    for i = num or 1, num or reactors do
        local status = safeCall(reactors_proxy[i], "hasWork", false)
        if status == true then
            reactor_work[i] = true
            any_reactor_on = true
            work = true
        else
            reactor_work[i] = false
            any_reactor_off = true
        end
        if any_reactor_on and any_reactor_off then
            break
        end
    end
end


local function drawTimeInfo()
    local fl_y1 = 45
    if flux_network == true then
        fl_y1 = 46
    end
    buffer.drawRectangle(123, fl_y1, 35, 4, colors.bg, 0, " ") 
    for i = 0, 35 - 1 do
        buffer.drawText(123 + i, fl_y1-1, colors.bg, brailleChar(brail_console[1]))
    end
    for i = 0, 35 - 1 do
        buffer.drawText(123 + i, fl_y1+1, colors.bg2, brailleChar(brail_console[2]))
    end
    buffer.drawText(124, fl_y1, colors.textclr, "МЭ: Обн. ч/з..")
    buffer.drawText(141, fl_y1, colors.textclr, "Время работы:")
    buffer.drawText(139, fl_y1, colors.bg2, brailleChar(brail_cherta[1]))
    buffer.drawText(139, fl_y1+1, colors.bg2, brailleChar(brail_cherta[2]))
    buffer.drawText(139, fl_y1+2, colors.bg2, brailleChar(brail_cherta[1]))
    buffer.drawText(139, fl_y1+3, colors.bg2, brailleChar(brail_cherta[1]))
    drawDigit(125, fl_y1+2, brail_time, 0xaa4b2e)
    -- ---------------------------------------------------------------------------
    buffer.drawRectangle(127, fl_y1+2, 12, 2, colors.bg, 0, " ")
    
    drawNumberWithText(134, fl_y1+2, (me_network and (60 - MeSecond) or 0), 2, colors.textclr, "Sec", colors.textclr)
    
    buffer.drawRectangle(140, fl_y1+2, 18, 2, colors.bg, 0, " ")

    if hour > 0 then
        if hour >= 100 and hour < 1000 and minute < 10 then 
            drawNumberWithText(146, fl_y1+2, hour, 2, colors.textclr, "Hrs", colors.textclr)
            drawNumberWithText(154, fl_y1+2, minute, 2, colors.textclr, "Min", colors.textclr)
        elseif hour >= 100 and hour < 1000 and minute >= 10 then
            drawNumberWithText(145, fl_y1+2, hour, 2, colors.textclr, "Hrs", colors.textclr)
            drawNumberWithText(154, fl_y1+2, minute , 2, colors.textclr, "Min", colors.textclr)
        elseif hour >= 1000 then
            drawNumberWithText(150, fl_y1+2, hour, 2, colors.textclr, "Hrs", colors.textclr)
        elseif hour < 10 and minute < 10 then
            drawNumberWithText(146, fl_y1+2, hour, 2, colors.textclr, "Hrs", colors.textclr)
            drawNumberWithText(152, fl_y1+2, minute , 2, colors.textclr, "Min", colors.textclr)
        elseif hour < 10 and minute >= 10 then
            drawNumberWithText(146, fl_y1+2, hour, 2, colors.textclr, "Hrs", colors.textclr)
            drawNumberWithText(153, fl_y1+2, minute , 2, colors.textclr, "Min", colors.textclr)
        elseif hour >= 10 and minute < 10 then
            drawNumberWithText(146, fl_y1+2, hour, 2, colors.textclr, "Hrs", colors.textclr)
            drawNumberWithText(153, fl_y1+2, minute, 2, colors.textclr, "Min", colors.textclr)
        else
            drawNumberWithText(146, fl_y1+2, hour, 2, colors.textclr, "Hrs", colors.textclr)
            if minute < 10 then
                drawNumberWithText(153, fl_y1+2, minute, 2, colors.textclr, "Min", colors.textclr)
            else
                drawNumberWithText(154, fl_y1+2, minute, 2, colors.textclr, "Min", colors.textclr)
            end
        end
    else
        if minute < 10 and second < 10 then
            drawNumberWithText(147, fl_y1+2, minute, 2, colors.textclr, "Min", colors.textclr)
            drawNumberWithText(153, fl_y1+2, second, 2, colors.textclr, "Sec", colors.textclr)
        elseif minute < 10 and second >= 10 then
            drawNumberWithText(146, fl_y1+2, minute, 2, colors.textclr, "Min", colors.textclr)
            drawNumberWithText(153, fl_y1+2, second, 2, colors.textclr, "Sec", colors.textclr)
        elseif minute >= 10 and second < 10 then
            drawNumberWithText(146, fl_y1+2, minute , 2, colors.textclr, "Min", colors.textclr)
            drawNumberWithText(153, fl_y1+2, second, 2, colors.textclr, "Sec", colors.textclr)
        else
            drawNumberWithText(146, fl_y1+2, minute, 2, colors.textclr, "Min", colors.textclr)
            if second < 10 then
                drawNumberWithText(153, fl_y1+2, second, 2, colors.textclr, "Sec", colors.textclr)
            else
                drawNumberWithText(154, fl_y1+2, second, 2, colors.textclr, "Sec", colors.textclr)
            end
        end
    end
    buffer.drawChanges()
end

local function drawStatic()
    local picture
    if theme == false then
        picture = image.load(imgPath)
    else
        picture = image.load(imgPathWhite)
    end

    if picture then
        buffer.drawImage(1, 1, picture)
    else
        buffer.drawText(1, 1, colors.msgerror, "Ошибка загрузки изображения! Проверьте наличие файлов 'image/reactorGUI.pic'")
        return
    end
    animatedButton(1, 5, 44, "🔧", nil, nil, 4, nil, nil, 0xa91df9, 0xffffff)
    animatedButton(1, 5, 47, "ⓘ", nil, nil, 4, nil, nil, 0xa91df9, 0x05e2ff)
    animatedButton(1, 13, 44, "Отключить реакторы!", nil, nil, 24, nil, nil, 0xfd3232)
    animatedButton(1, 41, 44, "Запуск реакторов!", nil, nil, 23, nil, nil, 0x35e525)
    animatedButton(1, 68, 44, "Пр.Обновить МЭ", nil, nil, 18, nil, nil, nil)
    animatedButton(1, 13, 47, "Рестарт программы.", nil, nil, 24, nil, nil, colors.whitebtn)
    animatedButton(1, 41, 47, "Выход из программы.", nil, nil, 23, nil, nil, colors.whitebtn)
    animatedButton(1, 68, 47, "Метрика: " .. status_metric, nil, nil, 18, nil, nil, colors.whitebtn)

    buffer.drawText(123, 50, (theme and 0xc3c3c3 or 0x666666), "Reactor Control v" .. version .. "." .. build .. " by P1KaChU337")
    -- buffer.drawText(130, 50, (theme and 0xc3c3c3 or 0x666666), "by P1KaChU337") -- Контакты: VK: @p1kachu337, Discord: p1kachu337 TG: @sh1zurz
    
    buffer.drawChanges()
end

local function getTotalFluidConsumption()
    local total = 0
    
    for i = 1, #reactors_proxy do
        local reactor = reactors_proxy[i]
        if reactor_type[i] == "Fluid" then
            if reactor_work[i] then
                total = total + safeCall(reactor, "getFluidCoolantConsume", 0) or 0
            end
        end
    end
    
    return total
end

local function drawStatus(num)
    checkReactorStatus()
    if reactors >= 12 then
        reactors = 12
    end

    -- Сдвиг x с 87 на 89
    buffer.drawRectangle(89, 44, 31, 6, colors.bg, 0, " ")
    -- Сдвиг x с 88 на 90
    buffer.drawText(90, 44, colors.textclr, "Статус комплекса:")
    
    for i = 0, 31 - 1 do
        -- Сдвиг x с 87 на 89
        buffer.drawText(89 + i, 43, colors.bg, brailleChar(brail_console[1]))
    end
    for i = 0, 31 - 1 do
        -- Сдвиг x с 87 на 89
        buffer.drawText(89 + i, 45, colors.bg2, brailleChar(brail_console[2]))
    end

    -- Сдвиг x с 108 на 110
    buffer.drawText(110, 45, colors.bg2, brailleChar(brail_cherta[5]))
    buffer.drawText(110, 46, colors.bg2, brailleChar(brail_cherta[6]))
    buffer.drawText(110, 47, colors.bg2, brailleChar(brail_cherta[6]))
    buffer.drawText(110, 48, colors.bg2, brailleChar(brail_cherta[6]))
    buffer.drawText(110, 49, colors.bg2, brailleChar(brail_cherta[6]))

    -- Сдвиг x с 88 на 90
    buffer.drawText(90, 46, colors.textclr, "Кол-во реакторов: " .. reactors)
    buffer.drawText(90, 47, colors.textclr, "Общее потребление")
    buffer.drawText(90, 48, colors.textclr, "жидкости: " .. consumeSecond .. " Mb/s")

    if any_reactor_on == true then
        -- Сдвиг координат индикатора (110->112, 111->113, 115->117)
        buffer.drawRectangle(112, 47, 6, 1, 0x61ff52, 0, " ")
        buffer.drawRectangle(113, 46, 4, 3, 0x61ff52, 0, " ")
        buffer.drawText(112, 46, 0x61ff52, brailleChar(brail_status[1]))
        buffer.drawText(117, 46, 0x61ff52, brailleChar(brail_status[2]))
        buffer.drawText(117, 48, 0x61ff52, brailleChar(brail_status[3]))
        buffer.drawText(112, 48, 0x61ff52, brailleChar(brail_status[4]))
        buffer.drawText(113, 47, 0x0d9f00, "Work") 
    else
        -- Сдвиг координат индикатора (110->112, 111->113, 115->117)
        buffer.drawRectangle(112, 47, 6, 1, 0xfd3232, 0, " ")
        buffer.drawRectangle(113, 46, 4, 3, 0xfd3232, 0, " ")
        buffer.drawText(112, 46, 0xfd3232, brailleChar(brail_status[1]))
        buffer.drawText(117, 46, 0xfd3232, brailleChar(brail_status[2]))
        buffer.drawText(117, 48, 0xfd3232, brailleChar(brail_status[3])) 
        buffer.drawText(112, 48, 0xfd3232, brailleChar(brail_status[4]))
        buffer.drawText(113, 47, 0x9d0000, "Stop")
    end

    buffer.drawChanges()
end

local function drawPorog()
    local fl_y1 = 35
    if flux_network == true then fl_y1 = 32 end
    buffer.drawRectangle(123, fl_y1-1, 35, 4, colors.bg, 0, " ")
    for i = 0, 35 - 1 do
        buffer.drawText(123 + i, fl_y1-2, colors.bg, brailleChar(brail_console[1]))
    end
    for i = 0, 35 - 1 do
        buffer.drawText(123 + i, fl_y1, colors.bg2, brailleChar(brail_console[2]))
    end
    buffer.drawText(124, fl_y1-1, colors.textclr, "Настройка порога жидкости:")
    
    drawDigit(124, fl_y1+1, brail_greenbtn, 0xa6ff00)
    drawDigit(126, fl_y1+1, brail_redbtn, 0xff2121) 
  
    drawNumberWithText(144, fl_y1+1, porog, 2, colors.textclr, "Mb", colors.textclr)
    buffer.drawChanges()
end

local function round(num, digits)
    local mult = 10 ^ (digits or 0)
    local result = math.floor(num * mult + 0.5) / mult
    if result == math.floor(result) then
        return tostring(math.floor(result))
    else
        return tostring(result)
    end
end

local function formatRF(value)
    if type(value) ~= "number" then value = 0 end
    if metric == 0 then
        -- Auto
        if value >= 1e9 then
            return round(value / 1e9, 1), "gRf"
        elseif value >= 1e6 then
            return round(value / 1e6, 1), "mRf"
        elseif value >= 1e3 then
            return round(value / 1e3, 1), "kRf"
        else
            return round(value, 1), "Rf"
        end
    elseif metric == 1 then
        return round(value, 1), "Rf"
    elseif metric == 2 then
        return round(value / 1e3, 1), "kRf"
    elseif metric == 3 then
        return round(value / 1e6, 1), "mRf"
    elseif metric == 4 then
        return round(value / 1e9, 1), "gRf"
    end
end

local function formatFluxRF(value)
    if type(value) ~= "number" then
        return "0 Rf"
    end

    local suffixes = {"Rf", "kRf", "mRf", "gRf"}
    local i = 1

    while value >= 1000 and i < #suffixes do
        value = value / 1000
        i = i + 1
    end

    local str
    if value < 10 then
        str = string.format("%.2f", value)
    elseif value < 100 then
        str = string.format("%.1f", value)
    else
        str = string.format("%.0f", value)
    end

    str = str:gsub("%.0$", "")

    return str, suffixes[i]
end

local function formatFluid(value)
    if type(value) ~= "number" then value = 0 end
    if metric == 0 then
        -- Auto
        if value >= 1e9 then
            return round(value / 1e9, 1), "gMb"
        elseif value >= 1e6 then
            return round(value / 1e6, 1), "mMb"
        elseif value >= 1e3 then
            return round(value / 1e3, 1), "kMb"
        else
            return round(value, 1), "Mb"
        end
    elseif metric == 1 then
        return round(value, 1), "Mb"
    elseif metric == 2 then
        return round(value / 1e3, 1), "kMb"
    elseif metric == 3 then
        return round(value / 1e6, 1), "mMb"
    elseif metric == 4 then
        return round(value / 1e9, 1), "gMb"
    end
end

local function drawFluidinfo()
    local fl_y1 = 30
    if flux_network == true then fl_y1 = 27 end
    buffer.drawRectangle(123, fl_y1-1, 35, 4, colors.bg, 0, " ")
    for i = 0, 35 - 1 do
        buffer.drawText(123 + i, fl_y1-2, colors.bg, brailleChar(brail_console[1]))
    end
    for i = 0, 35 - 1 do
        buffer.drawText(123 + i, fl_y1, colors.bg2, brailleChar(brail_console[2]))
    end
    buffer.drawText(124, fl_y1-1, colors.textclr, "Жидкости в МЭ сети:")
    
    drawDigit(125, fl_y1+1, brail_fluid, 0x0088ff)

    local val, unit = formatFluid(fluidInMe or 0)
    drawNumberWithText(143, fl_y1+1, (me_network and (val or 0) or 0), 2, colors.textclr, unit, colors.textclr)
end

local function drawFluxRFinfo()
    initFlux()
    if flux_network == true then
        local energyInfo = component.flux_controller.getEnergyInfo()
        local rf1 = energyInfo.energyInput
        local rf2 = energyInfo.energyOutput
        local fl_y1 = 36

        buffer.drawRectangle(123, fl_y1, 35, 4, colors.bg, 0, " ")
        for i = 0, 35 - 1 do
            buffer.drawText(123 + i, fl_y1-1, colors.bg, brailleChar(brail_console[1]))
        end
        for i = 0, 35 - 1 do
            buffer.drawText(123 + i, fl_y1+1, colors.bg2, brailleChar(brail_console[2]))
        end
        buffer.drawText(124, fl_y1, colors.textclr, "Общий вход/выход в Flux сети:")
        
        buffer.drawText(142, fl_y1+1, colors.bg2, brailleChar(brail_cherta[7]))
        buffer.drawText(142, fl_y1+2, colors.bg2, brailleChar(brail_cherta[1]))
        buffer.drawText(142, fl_y1+3, colors.bg2, brailleChar(brail_cherta[1]))

        drawDigit(125, fl_y1+2, brail_thunderbolt, 0xff2200)

        local valIn, unitIn = formatFluxRF(rf1)
        drawNumberWithText(136, fl_y1+2, (valIn or 0), 2, colors.textclr, unitIn .. "/t", colors.textclr)

        local valOut, unitOut = formatFluxRF(rf2)
        drawNumberWithText(152, fl_y1+2, (valOut or 0), 2, colors.textclr, unitOut .. "/t", colors.textclr)
    end
end

local function drawRFinfo()
    rf = 0
    for i = 1, reactors do
        rf = rf + (reactor_rf[i] or 0)
    end 
    local fl_y1 = 40
    if flux_network == true then fl_y1 = 41 end

    buffer.drawRectangle(123, fl_y1, 35, 4, colors.bg, 0, " ")
    for i = 0, 35 - 1 do
        buffer.drawText(123 + i, fl_y1-1, colors.bg, brailleChar(brail_console[1]))
    end
    for i = 0, 35 - 1 do
        buffer.drawText(123 + i, fl_y1+1, colors.bg2, brailleChar(brail_console[2]))
    end
    buffer.drawText(124, fl_y1, colors.textclr, "Генерация всех реакторов:")

    drawDigit(125, fl_y1+2, brail_thunderbolt, 0xffc400)

    local val, unit = formatRF(rf)
    drawNumberWithText(144, fl_y1+2, (any_reactor_on and val or 0), 2, colors.textclr, unit .. "/t", colors.textclr)
end
local function clearRightWidgets()
    color = (theme and 0xffffff or 0x3c3c3c)
    buffer.drawRectangle(123, 3, 35, 47, color, 0, " ")
end

local function drawDynamic()
    buffer.drawRectangle(123, 3, 35, (flux_network and 22 or 24), colors.bg, 0, " ")
    for i = 0, 35 - 1 do
        buffer.drawText(123 + i, 2, colors.bg, brailleChar(brail_console[1]))
    end
    for i = 0, 35 - 1 do
        buffer.drawText(123 + i, 4, colors.bg2, brailleChar(brail_console[2]))
    end
    buffer.drawText(124, 3, colors.textclr, "Информационное окно отладки:")
    drawStatus()
    -- -----------------------------------------------------------
    drawFluidinfo()

    -- -----------------------------------------------------------
    drawPorog()

    -- -----------------------------------------------------------
    drawFluxRFinfo()

    -- -----------------------------------------------------------
    drawRFinfo()
    
    -- -----------------------------------------------------------
    drawTimeInfo()

    -- -----------------------------------------------------------

    drawWidgets()
    drawRightMenu()
    buffer.drawChanges()
end

local function updateReactorData(num)
    for i = num or 1, num or reactors do
        local proxy = reactors_proxy[i]
        temperature[i]      = safeCall(proxy, "getTemperature", 0)
        reactor_type[i]     = safeCall(proxy, "isActiveCooling", false) and "Fluid" or "Air"
        reactor_rf[i]       = safeCall(proxy, "getEnergyGeneration", 0)
        reactor_work[i]     = safeCall(proxy, "hasWork", false)

        if reactor_type[i] == "Fluid" then
            reactor_getcoolant[i] = safeCall(proxy, "getFluidCoolant", 0) or 0
            reactor_maxcoolant[i] = safeCall(proxy, "getMaxFluidCoolant", 0) or 1
        end
    end
    drawWidgets()
    drawRFinfo()
end

local function start(num)
    if num then
        message("Запускаю реактор #" .. num .. "...", colors.textclr, 34)
    else
        message("Запуск реакторов...", colors.textclr, 34)
    end
    for i = num or 1, num or reactors do
        local rType = reactor_type[i]
        local proxy = reactors_proxy[i]


        if rType == "Fluid" then
            if offFluid == false then
                safeCall(proxy, "activate")
                reactor_work[i] = true
                if num then
                    message("Реактор #" .. i .. " (жидкостный) запущен!", colors.msginfo, 34)
                end
            else
                if fluidInMe <= porog then
                    if num then
                        message("Ошибка по жидкости! Реактор #" .. i .. " (жидкостный) не был запущен!", colors.msgwarn, 34)
                    end
                    offFluid = true
                    if reason == nil then
                        reason = "Ошибка жидкости!"
                        reactor_aborted[i] = true
                    end
                else
                    offFluid = false
                    safeCall(proxy, "activate")
                    reactor_work[i] = true
                    if num then
                        message("Реактор #" .. i .. " (жидкостный) запущен!", colors.msginfo, 34)
                    end
                end
            end
        else
            safeCall(proxy, "activate")
            reactor_work[i] = true
            if num then
                message("Реактор #" .. i .. " (воздушный) запущен!", colors.msginfo, 34)
            end
        end
    end
    if not num then
        if offFluid == true then
            local isAir = false
            for i = 1, reactors do
                local rType = reactor_type[i]
                if rType == "Air" then
                    isAir = true
                    break
                end
            end
            if isAir == true then
                message("Воздушные реакторы запущены!", colors.msginfo, 34)
            end
            message("Ошибка по жидкости! Жидкостные реакторы не будут запущены!", colors.msgwarn, 34)
        else
            message("Реакторы запущены!", colors.msginfo, 34)
        end
    end
    drawWidgets()
end


local function stop(num)
    if num then
        message("Отключаю реактор #" .. num .. "...", colors.textclr, 34)
    else
        message("Отключение реакторов...", colors.textclr, 34)
    end
    for i = num or 1, num or reactors do
        local proxy = reactors_proxy[i]
        local rType = reactor_type[i]
        safeCall(proxy, "deactivate")
        reactor_work[i] = false
        drawStatus()
        if rType == "Fluid" then
            if num then
                message("Реактор #" .. i .. " (жидкостный) отключен!", colors.msginfo, 34)
            end
        else
            if num then
                message("Реактор #" .. i .. " (воздушный) отключен!", colors.msginfo, 34)
            end
        end

        if any_reactor_on == false then
            work = false
        end
    end
    if not num then
        message("Реакторы отключены!", colors.msginfo, 34)
    end
end

local function silentstop(num) -- Ещё один костыльчик
    for i = num or 1, num or reactors do
        local proxy = reactors_proxy[i]
        local rType = reactor_type[i]
        safeCall(proxy, "deactivate")
        reactor_work[i] = false
        if any_reactor_on == false then
            work = false
        end
    end
end

local function updateMeProxy()
    if component.isAvailable("me_controller") then
        me_proxy = component.proxy(component.list("me_controller")())
    elseif component.isAvailable("me_interface") then
        me_proxy = component.proxy(component.list("me_interface")())
    else
        me_proxy = nil
    end
end

local function checkFluid()
    MeSecond = 0
    if not me_network then
        offFluid = true
        reason = "МЭ не найдена!"
        return
    end

    if not me_proxy then
        updateMeProxy()
        if not me_proxy then
            offFluid = true
            reason = "Нет прокси МЭ!"
            return
        end
    end

    local ok, items = pcall(me_proxy.getItemsInNetwork, { name = "ae2fc:fluid_drop" })
    if not ok or type(items) ~= "table" then
        offFluid = true
        reason = "Ошибка жидкости!"
        return
    end

    local targetFluid = "low_temperature_refrigerant"
    local count = 0

    for _, item in ipairs(items) do
        if item.label and item.label:find(targetFluid) then
            count = count + (item.size or 0)
        end
    end

    if count == 0 then
        offFluid = true
        reason = "Нет хладагента!"
    end

    if count > maxThreshold then
        count = lastValidFluid
    else
        lastValidFluid = count
    end

    fluidInMe = count

    if fluidInMe <= porog then
        if ismechecked == false then
            message("Жидкости в МЭ меньше порога!", colors.msgwarn, 34)
            for i = 1, reactors do
                if reactor_type[i] == "Fluid" then
                    drawStatus(i)
                    if reactor_work[i] == true then
                        message("Отключаю жидкостные реакторы...", colors.textclr, 34)
                        break
                    end
                end
            end
        end
        offFluid = true
        reason = "Нет хладагента!"
        ismechecked = true
    else
        if offFluid == true and starting == true then
            message("Жидкости хватает, включаю реакторы...", colors.textclr, 34)
            offFluid = false
            ismechecked = false
            for i = 1, reactors do
                if reactor_type[i] == "Fluid" then
                    start(i)
                    reactor_aborted[i] = false
                    updateReactorData(i)
                end
            end
        end
        if offFluid == true then 
            offFluid = false 
            for i = 1, reactors do
                if reactor_type[i] == "Fluid" then
                    if reactor_aborted[i] == true then
                        reactor_aborted[i] = false
                        updateReactorData(i)
                    end
                end
            end
        end
    end
end

function onInterrupt()
    message("Обнаружено прерывание!", colors.msgerror)
    os.sleep(0.2)
    if work == true then
        stop()
        updateReactorData()
        os.sleep(0.2)
        drawWidgets()
        drawRFinfo()
        os.sleep(0.3)
    end
    message("Завершаю работу программы...", colors.msgerror, 34)

    if chatThread then
        chatThread:kill()
    end

    buffer.drawChanges()
    os.sleep(0.5)
    buffer.clear(0x000000)
    buffer.drawChanges()
    shell.execute("clear")
    exit = true
    os.exit()
end

_G.__NR_ON_INTERRUPT__ = function()
    onInterrupt()
end

local function reactorsChanged()
    local currentCount = 0
    local current = {}

    for address in component.list("htc_reactors") do
        current[address] = true
        currentCount = currentCount + 1
    end

    if currentCount ~= reactors then
        return true
    end

    for i = 1, #reactor_address do
        local addr = reactor_address[i]
        if addr and not current[addr] then
            return true
        end
    end

    return false
end

local function meChanged()
    local current_me_address = nil

    if component.isAvailable("me_controller") then
        current_me_address = component.list("me_controller")()
    elseif component.isAvailable("me_interface") then
        current_me_address = component.list("me_interface")()
    end

    if last_me_address ~= current_me_address then
        last_me_address = current_me_address
        return true
    end

    return false
end

-- -------------------------------------------------------------------------------------------------------------------------------------

local function logError(err)
    if debugLog == true then
        local f = io.open("/home/reactor_errors.log", "a")
        if f then
            f:write(os.date("[%Y-%m-%d %H:%M:%S] ") .. tostring(err) .. "\n")
            f:write("starting=" .. tostring(starting) ..
                    ", reactors=" .. tostring(reactors) ..
                    ", me_network=" .. tostring(me_network) ..
                    ", fluidInMe=" .. tostring(fluidInMe) ..
                    ", work=" .. tostring(work) ..
                    ", any_reactor_on=" .. tostring(any_reactor_on) .. "\n")

            if reactors > 0 then
                local coolant_line = "coolant_levels="
                for i = 1, reactors do
                    coolant_line = coolant_line .. tostring(reactor_getcoolant[i] or "nil")
                    if i < reactors then
                        coolant_line = coolant_line .. ", "
                    end
                end
                f:write(coolant_line .. "\n")
            end

            f:write("\n")
            f:close()
        end
    end
end

-- -----------------------------------------------------[MD.GUI Functions]--------------------------------------------------------------

-- --------------------------------[SWITCH]----------------------------------------
local function drawSwitch(x, y, w, pipePos, state, activeClr, passiveClr, pipeClr, bgClr)
    local activeCol = activeClr or 0x0088ff
    local passiveCol = passiveClr or 0x444444
    local pipeCol = pipeClr or 0xFFFFFF
    local bgCol = bgClr or 0xcccccc

    -- Очищаем область под ним (опционально, если фон однотонный)
    buffer.drawRectangle(x, y, w, 1, bgCol, 0, " ") 

    -- Левый край
    if pipePos > 1 then
        buffer.drawText(x, y, activeCol, "◖")
    end
    -- Правый край
    if pipePos < w - 1 then
        buffer.drawText(x + w - 1, y, passiveCol, "◗")
    end
    -- Фон
    if pipePos - 1 > 0 then
        buffer.drawRectangle(x + 1, y, pipePos - 1, 1, activeCol, 0, " ")
    end
    if w - pipePos - 1 > 0 then
        buffer.drawRectangle(x + pipePos, y, w - pipePos - 1, 1, passiveCol, 0, " ")
    end
    -- Ползунок
    buffer.drawText(x + pipePos - 1, y, pipeCol, "◖")
    buffer.set(x + pipePos, y, pipeCol, pipeCol, " ")
    buffer.drawText(x + pipePos + 1, y, pipeCol, "◗")
end

-- ------------------------------[SEARCH FIELD]------------------------------------
local searchFields = {}
local function createSearchField(x, y, width, placeholder, hidden, clr, bgclr, placeholderClr)
    table.insert(searchFields, {
        x = x,
        y = y,
        width = width,
        placeholder = placeholder or "Введите текст...",
        text = "",
        cursorPos = 1,
        scrollOffset = 0,
        cursorVisible = false,
        lastBlink = computer.uptime(),
        active = false,
        hidden = (hidden and true or false),
        clr = clr or 0x444444,
        bgclr = bgclr or 0xcccccc,
        placeholderClr = placeholderClr or 0xececec,
    })
end

local function removeSearchField(index)
    if searchFields[index] then
        table.remove(searchFields, index)
    end
end


-- функция отрисовки одного поля
local function drawSearchField(field)
    local fieldColor = field.clr
    local fieldBgColor = field.bgclr
    local placeholderColor = field.placeholderClr
    local fieldTextColor = 0xffffff

    buffer.drawRectangle(field.x, field.y, field.width, 1, fieldColor, fieldBgColor, " ")
    buffer.drawRectangle(field.x+1, field.y-1, field.width-2, 1, fieldColor, fieldBgColor, brailleChar(brail_fields[6]))
    buffer.drawRectangle(field.x+1, field.y+1, field.width-2, 1, fieldColor, fieldBgColor, brailleChar(brail_fields[5]))
    buffer.drawText(field.x, field.y-1, fieldColor, brailleChar(brail_fields[1]))
    buffer.drawText(field.x, field.y+1, fieldColor, brailleChar(brail_fields[4]))
    buffer.drawText(field.x + field.width-1, field.y-1, fieldColor, brailleChar(brail_fields[2]))
    buffer.drawText(field.x + field.width-1, field.y+1, fieldColor, brailleChar(brail_fields[3]))

    local visibleText
    local maxVisible = field.width - 2
    local startX, startY = field.x + 1, field.y

    if not field.active then
        if field.text == "" then
            -- плейсхолдер
            buffer.drawText(startX, startY, placeholderColor, centerText(field.placeholder, field.width))
        else
            buffer.drawText(startX, startY, placeholderColor, shortenNameCentered((field.hidden and string.rep("*", unicode.len(field.text:sub(field.scrollOffset + 1, field.scrollOffset + maxVisible))) or field.text), maxVisible))
        end
    else
        -- скролл текста
        if field.cursorPos - field.scrollOffset > maxVisible then
            field.scrollOffset = field.cursorPos - maxVisible
        elseif field.cursorPos <= field.scrollOffset then
            field.scrollOffset = math.max(0, field.cursorPos - 1)
        end
        if field.hidden == true then
            visibleText = string.rep("*", unicode.len(field.text:sub(field.scrollOffset + 1, field.scrollOffset + maxVisible)))
        else
            visibleText = field.text:sub(field.scrollOffset + 1, field.scrollOffset + maxVisible)
        end

        -- вывод текста
        buffer.drawText(startX, startY, fieldTextColor, visibleText)

        if field.cursorVisible then
            local cursorX = startX + (field.cursorPos - 1 - field.scrollOffset)
            buffer.drawText(cursorX, startY, fieldTextColor, "|")
        end
    end
end

-- функция отрисовки всех полей
local function drawAllFields()
    for _, f in ipairs(searchFields) do
        drawSearchField(f)
    end
    buffer.drawChanges()
end

local function removeAllFields()
    for i = #searchFields, 1, -1 do
        removeSearchField(i)
    end
    buffer.drawChanges()
end
-- --------------------------------------------------------------------------------

-- -----------------------------------------------------[MODAL WINDOWS]-----------------------------------------------------------------
-- -----------------------------{SETTINGS MENU}------------------------------------
local function drawSettingsMenu()
    local isSaved = false
    local isStart = false
    if work == true and any_reactor_on == true then
        isStart = true
        stop()
    end

    local modalX, modalY, modalW, modalH = 35, 10, 65, 23 -- Размеры модального окна, w - ширина, h - высота
    local old = buffer.copy(1, 1, 160, 50)
    buffer.drawRectangle(1, 1, 160, 50, 0x000000, 0, " ", 0.4)
    buffer.drawRectangle(modalX, modalY, modalW, modalH, 0xcccccc, 0, " ")
    buffer.drawRectangle(modalX-1, modalY+1, modalW+2, modalH-2, 0xcccccc, 0, " ")
    local cornerPos = {
        {modalX-1, modalY, 1}, {modalX+modalW, modalY, 2},
        {modalX+modalW, modalY+modalH-1, 3}, {modalX-1, modalY+modalH-1, 4}
    }
    for _, c in ipairs(cornerPos) do
        buffer.drawText(c[1], c[2], 0xcccccc, brailleChar(brail_status[c[3]]))
    end
    removeAllFields()
    -- Заголовки
    buffer.drawText(modalX + 11, modalY + 1, 0x000000, "Меню настроек приложения ReactorControl v" .. version .. "." .. build)

    buffer.drawText(modalX + 7, modalY + 3, 0x000000, "Порог жидкости")
    createSearchField(modalX + 3, modalY + 5, 22, "Введите порог(Mb)")
    searchFields[1].text = tostring(porog)
    local offset = unicode.len(searchFields[1].text) + 1
    searchFields[1].cursorPos = offset

    buffer.drawText(modalX + 5, modalY + 7, 0x000000, "Тема по умолчанию")
    animatedButton(1, modalX + 4, modalY + 8, "Светлая      ", nil, nil, 20, nil, nil, 0x444444, 0xffffff)
    local sw1_x, sw1_y, sw1_w = modalX+16, modalY+9, 7
    local sw1_state = theme -- текущее состояние
    local sw1_pipePos = (sw1_state and (sw1_w - 2) or 1)   -- позиция (1 - лево, sw1_w-2 - право)
    drawSwitch(sw1_x, sw1_y, sw1_w, sw1_pipePos, sw1_state, nil, 0x777777, nil, 0x444444)

    buffer.drawText(modalX + 3, modalY + 11, 0x000000, "Новые версии приложения")
    animatedButton(1, modalX + 4, modalY + 12, "Проверять        ", nil, nil, 20, nil, nil, 0x444444, 0xffffff)
    local sw2_x, sw2_y, sw2_w = modalX+16, modalY+13, 7
    local sw2_state = updateCheck -- текущее состояние
    local sw2_pipePos = (sw2_state and (sw2_w - 2) or 1)   -- позиция (1 - лево, sw2_w-2 - право)
    drawSwitch(sw2_x, sw2_y, sw2_w, sw2_pipePos, sw2_state, nil, 0x777777, nil, 0x444444)

    buffer.drawText(modalX + 3, modalY + 15, 0x000000, "Расширенное логирование")
    animatedButton(1, modalX + 4, modalY + 16, "Включенно         ", nil, nil, 20, nil, nil, 0x444444, 0xffffff)
    local sw3_x, sw3_y, sw3_w = modalX+16, modalY+17, 7
    local sw3_state = debugLog -- текущее состояние
    local sw3_pipePos = (sw3_state and (sw3_w - 2) or 1)   -- позиция (1 - лево, sw3_w-2 - право)
    drawSwitch(sw3_x, sw3_y, sw3_w, sw3_pipePos, sw3_state, nil, 0x777777, nil, 0x444444)

    -- nickname widget
    local function drawNicknameWidget(placeholder, clr)
        if placeholder == nil then
            placeholder = "Введите никнейм"
        end
        buffer.drawText(modalX + 29, modalY + 3, 0x000000, "Игроки добавленные в белый список:")
        local winX, winY, winW, winH = modalX+30, modalY+4, 32, 18
        buffer.drawRectangle(winX, winY, winW, 1, 0x333333, 0, " ")
        buffer.drawRectangle(winX-1, winY+1, winW+2, winH-2, 0x333333, 0, " ")

        buffer.drawRectangle(winX, winY, winW, 1, 0x333333, 0xcccccc, brailleChar(button1[7]))
        buffer.drawRectangle(winX, winY+(winH-1), winW, 1, 0x333333, 0xcccccc, " ")

        local winCornerPos = {
            {winX-1, winY, 4}, {winX+winW, winY, 2},
            {winX+winW, winY+winH-1, 8}, {winX-1, winY+winH-1, 9}
        }
        for _, c in ipairs(winCornerPos) do
            buffer.drawText(c[1], c[2], 0x333333, brailleChar(button1[c[3]]))
        end

        local maxRows = 14
        local startY = modalY + 4
        for i = 1, maxRows do
            local y = startY + i
            local bg = (i % 2 == 0) and 0x444444 or 0x555555

            buffer.drawRectangle(winX, y, winW, 1, bg, 0, " ")

            local name = users[i]
            if name then
                buffer.drawText(modalX + 33, y, 0xffffff, shortenNameCentered(name, winW - 7))
                buffer.drawText(modalX + 58, y, 0xff2121, "Del")
            else
                buffer.drawText(modalX + 31, y, 0xcbcbcb, shortenNameCentered("* Пусто *", winW - 2))
            end
        end
        removeSearchField(2)
        createSearchField(modalX + 30, modalY + 20, 24, placeholder, false, 0x353535, 0x333333, clr)
        animatedButton(1, modalX + 56, modalY + 19, "ADD", nil, nil, 5, nil, nil, 0x37c72a, 0xffffff) -- 0x21ff21
        drawAllFields()
    end

    local function nicknameExists(nick)
        for _, user in ipairs(users) do
            if user == nick then
                return true
            end
        end
        return false
    end
    -- function msgModal(x, y, w, h, color, text, textclr)
    --     local winX, winY, winW, winH = x, y, w, h
    --     buffer.drawRectangle(winX, winY, winW, winH-2, color, 0x3a3a3a, brailleChar(button1[7]))

    --     buffer.drawRectangle(winX-1, winY+1, winW+2, winH-2, color, 0, " ")

    --     buffer.drawRectangle(winX, winY+(winH-1), winW, 1, color, 0x3a3a3a, brailleChar(button1[1]))

    --     local winCornerPos = {
    --         {winX-1, winY, 4}, {winX+winW, winY, 2},
    --         {winX+winW, winY+winH-1, 6}, {winX-1, winY+winH-1, 5}
    --     }
    --     for _, c in ipairs(winCornerPos) do
    --         buffer.drawText(c[1], c[2], color, brailleChar(button1[c[3]]))
    --     end
    --     buffer.drawText(winX, winY+1, textclr or 0x000000, text)
    -- end
    -- ---------

    buffer.drawText(modalX + 1, modalY + modalH - 1, 0x999999, "P.S. Нажмите в любом месте вне окна, чтобы выйти без сохранения")
    animatedButton(1, modalX + 5, modalY + modalH - 4, "Сохранить и выйти", nil, nil, 18, nil, nil, 0x8100cc, 0xffffff)

    drawNicknameWidget()

    local themetoggle = theme

    local NSporog = porog
    local NSTheme = theme
    local NSUpdateCheck = updateCheck
    local NSDebugLog = debugLog
    local NSusers = {}
    for _, u in ipairs(users) do
        table.insert(NSusers, u)
    end

    while true do
        local eventData = {event.pull(0.05)}
        local eventType = eventData[1]

        -- Блинкер
        for _, f in ipairs(searchFields) do
            if f.active and computer.uptime() - f.lastBlink >= 0.5 then
                f.cursorVisible = not f.cursorVisible
                f.lastBlink = computer.uptime()
                drawAllFields()
            end
        end

        if eventType == "touch" then
            local _, _, x, y, button, uuid = table.unpack(eventData)

            for i, f in ipairs(searchFields) do
                if y == f.y and x >= f.x and x <= f.x + f.width - 1 then
                    -- активация полей
                    for _, f2 in ipairs(searchFields) do
                        f2.active, f2.cursorVisible = false, false
                    end
                    f.active = true
                    f.cursorVisible = true
                    f.lastBlink = computer.uptime()
                else
                    -- снимаем активность если клик не по полю
                    if f.active then
                        f.active = false
                        f.cursorVisible = false
                    end
                end
            end
            drawAllFields()

            for i, user in ipairs(users) do
                local rowY = modalY + 4 + i
                if y == rowY and x >= modalX + 58 and x <= modalX + 61 then
                    -- Удаляем никнейм из белого списка
                    buffer.drawText(modalX + 58, y, 0xff2121, "Del")
                    buffer.drawChanges()
                    os.sleep(0.2)
                    buffer.drawText(modalX + 58, y, 0xcc0000, "Del")
                    local delNick = users[i]
                    table.remove(users, i)
                    drawNicknameWidget()
                    buffer.drawChanges()
                    break
                end
            end
            -- ----------------------------------------------------------

            if x < modalX-1 or x > modalX + modalW or y < modalY or y > (modalY-1) + modalH then    
                buffer.paste(1, 1, old)
                buffer.drawChanges()
                if isStart == true then
                    start()
                end
                theme = NSTheme
                porog = NSporog
                updateCheck = NSUpdateCheck
                debugLog = NSDebugLog
                users = NSusers
                saveCfg()
                break
            end

            if x >= sw1_x and x <= sw1_x + sw1_w - 1 and y == sw1_y then
                sw1_state = not sw1_state
                
                -- Анимация (простая)
                local targetPos = sw1_state and (sw1_w - 2) or 1
                local step = (targetPos > sw1_pipePos) and 1 or -1
                
                repeat
                    sw1_pipePos = sw1_pipePos + step
                    drawSwitch(sw1_x, sw1_y, sw1_w, sw1_pipePos, sw1_state, nil, 0x777777, nil, 0x444444)
                    buffer.drawChanges()
                    os.sleep(0.02)
                until sw1_pipePos == targetPos
                
            elseif x >= sw2_x and x <= sw2_x + sw2_w - 1 and y == sw2_y then
                sw2_state = not sw2_state
                
                -- Анимация (простая)
                local targetPos = sw2_state and (sw2_w - 2) or 1
                local step = (targetPos > sw2_pipePos) and 1 or -1
                
                repeat
                    sw2_pipePos = sw2_pipePos + step
                    drawSwitch(sw2_x, sw2_y, sw2_w, sw2_pipePos, sw2_state, nil, 0x777777, nil, 0x444444)
                    buffer.drawChanges()
                    os.sleep(0.02)
                until sw2_pipePos == targetPos
                
                -- Тут можно добавить действие при переключении
                -- example: check_updates = sw_state
            elseif x >= sw3_x and x <= sw3_x + sw3_w - 1 and y == sw3_y then
                sw3_state = not sw3_state
                -- Анимация (простая)
                local targetPos = sw3_state and (sw3_w - 2) or 1
                local step = (targetPos > sw3_pipePos) and 1 or -1
                
                repeat
                    sw3_pipePos = sw3_pipePos + step
                    drawSwitch(sw3_x, sw3_y, sw3_w, sw3_pipePos, sw3_state, nil, 0x777777, nil, 0x444444)
                    buffer.drawChanges()
                    os.sleep(0.02)
                until sw3_pipePos == targetPos
                
                -- Тут можно добавить действие при переключении
                -- example: debug_log = sw_state
            elseif y >= modalY + 19 and y <= modalY + 21 and x >= modalX + 55 and x <= modalX + 56+5 then
                -- Добавляем никнейм в белый список
                animatedButton(1, modalX + 56, modalY + 19, "ADD", nil, nil, 5, nil, nil, 0x21ff21, 0xffffff) -- 0x21ff21
                animatedButton(2, modalX + 56, modalY + 19, "ADD", nil, nil, 5, nil, nil, 0x21ff21, 0xffffff) -- 0x21ff21
                buffer.drawChanges()
                os.sleep(0.2)
                animatedButton(1, modalX + 56, modalY + 19, "ADD", nil, nil, 5, nil, nil, 0x37c72a, 0xffffff) -- 0x21ff21
                local placehold
                local placeclr
                local newNick = searchFields[2].text:match("^%s*(.-)%s*$") -- trim
                if newNick == "" then
                    -- buffer.drawText(modalX + 30, modalY + 20, 0xff0000, "Никнейм не может быть пустым!")
                    -- msgModal(modalX + 18, modalY + 24, 29, 3, 0xcccccc, "Никнейм не может быть пустым!", 0xff0000)
                    placehold = "Не может быть пустым!"
                    placeclr = 0xff0000
                elseif #newNick > 16 then
                    -- message("Никнейм не может быть длиннее 16 символов!", colors.msgwarn, 34)
                    placehold = "Нельзя > 16 символов!"
                    placeclr = 0xff0000
                elseif nicknameExists(newNick) then
                    -- buffer.drawText(modalX + 3, modalY + 22, 0xff0000, "Никнейм уже в белом списке!")
                    placehold = "Уже в белом списке!"
                    placeclr = 0xff0000
                elseif #newNick < 3 then
                    -- message("Никнейм не может быть короче 2 символов!", colors.msgwarn, 34)
                    placehold = "Не меньше 3 символов!"
                    placeclr = 0xff0000
                else
                    table.insert(users, newNick)
                end
                drawNicknameWidget(placehold, placeclr)
                
            elseif y >= modalY + modalH - 4 and y <= modalY + modalH - 2 and x >= modalX + 4 and x <= modalX + (5+18) then
                buffer.drawRectangle(modalX + 4, modalY + modalH - 4, 19, 3, 0xcccccc, 0, " ")
                animatedButton(1, modalX + 5, modalY + modalH - 4, "Сохранить и выйти", nil, nil, 18, nil, nil, 0xa91df9, 0xffffff)
                animatedButton(2, modalX + 5, modalY + modalH - 4, "Сохранить и выйти", nil, nil, 18, nil, nil, 0xa91df9, 0xffffff)
                buffer.drawChanges()
                os.sleep(0.2)
                animatedButton(1, modalX + 5, modalY + modalH - 4, "Сохранить и выйти", nil, nil, 18, nil, nil, 0x8100cc, 0xffffff)
                buffer.drawChanges()
                -- Сохраняем настройки
                porog = tonumber(searchFields[1].text) or porog
                theme = sw1_state
                updateCheck = sw2_state
                debugLog = sw3_state
                saveCfg()
                
                switchTheme()
                drawStatic()
                drawDynamic()
                userUpdate()
                message("Настройки сохранены!", nil, 34)
                break
            end

            -- ----------------------------------------------------------

        elseif eventType == "key_down" then
            local _, _, char, code = table.unpack(eventData)
            for i, f in ipairs(searchFields) do
                if f.active then
                    if code == 14 then -- Backspace
                        if f.cursorPos > 1 then
                            f.text = f.text:sub(1, f.cursorPos - 2) .. f.text:sub(f.cursorPos)
                            f.cursorPos = f.cursorPos - 1
                        end
                    elseif code == 203 then -- стрелка влево
                        if f.cursorPos > 1 then
                            f.cursorPos = f.cursorPos - 1
                        end
                    elseif code == 205 then -- стрелка вправо
                        if f.cursorPos <= #f.text then
                            f.cursorPos = f.cursorPos + 1
                        end
                    elseif char >= 32 and char <= 126 then -- Печатаемые символы
                        if i == 1 then -- Поле порога жидкости - только цифры
                            local c = string.char(char)
                            if c:match("%d") then
                                f.text = f.text:sub(1, f.cursorPos - 1)
                                    .. c
                                    .. f.text:sub(f.cursorPos)
                                f.cursorPos = f.cursorPos + 1
                            end
                        else -- всё остальное - любые символы
                            local c = string.char(char) 
                            f.text = f.text:sub(1, f.cursorPos - 1) .. c .. f.text:sub(f.cursorPos) 
                            f.cursorPos = f.cursorPos + 1 
                        end
                    elseif code == 28 then -- Enter
                        f.active = false
                        f.cursorVisible = false
                    end
                end
            end
            drawAllFields()
        end
    end
end

-- -------------------------------{TEST MENU}--------------------------------------
local function testMenu()
    local isStart = false
    if work == true and any_reactor_on == true then
        isStart = true
        stop()
    end
    local old = buffer.copy(1, 1, 160, 50)
    buffer.drawRectangle(1, 1, 160, 50, 0x000000, 0, " ", 0.4)

    buffer.drawRectangle(7, 4, 110, 37, 0xcccccc, 0, " ")
    buffer.drawRectangle(6, 5, 112, 35, 0xcccccc, 0, " ")
    local cornerPos = {
        {6, 4, 1}, {117, 4, 2},
        {117, 40, 3}, {6, 40, 4}
    }
    for _, c in ipairs(cornerPos) do
        buffer.drawText(c[1], c[2], 0xcccccc, brailleChar(brail_status[c[3]]))
    end
    buffer.drawText(51, 5, 0x000000, "Меню настроек приложения") -- ✕ ◖⨷◗
    buffer.drawText(43, 6, 0x000000, "Нажмите \"ОК\" для продолжения.")
    
    removeAllFields()
    createSearchField(20, 15, 32, "Введите никнейм(клик)")
    createSearchField(20, 15+3, 32, "Введи текст чушпан...")
    createSearchField(20, 15+6, 32, "Скрытый текст, епта", true)

    animatedButton(1, 70, 25, "Сохранить", nil, nil, 11, nil, nil, 0x8100cc, 0xffffff)  
    
    -- Параметры нашего ползунка
    local sw_x, sw_y, sw_w = 50, 25, 6
    local sw_state = false -- текущее состояние
    local sw_pipePos = (sw_state and (sw_w - 2) or 1)   -- позиция (1 - лево, sw_w-2 - право)
    drawSwitch(sw_x, sw_y, sw_w, sw_pipePos, sw_state)
    drawAllFields()

    buffer.drawChanges()
    while true do
        local eventData = {event.pull(0.05)}
        local eventType = eventData[1]

        for _, f in ipairs(searchFields) do
            if f.active and computer.uptime() - f.lastBlink >= 0.5 then
                f.cursorVisible = not f.cursorVisible
                f.lastBlink = computer.uptime()
                drawAllFields()
            end
        end

        if eventType == "touch" then
            local _, _, x, y, button, uuid = table.unpack(eventData)

            for i, f in ipairs(searchFields) do
                if y == f.y and x >= f.x and x <= f.x + f.width - 1 then
                    if i == 1 then
                        searchFields[1].text = uuid or "" -- или nickname
                        searchFields[1].active = false
                        searchFields[1].cursorVisible = false
                    else
                        -- обычная активация остальных полей
                        for _, f2 in ipairs(searchFields) do
                            f2.active, f2.cursorVisible = false, false
                        end
                        f.active = true
                        f.cursorVisible = true
                        f.lastBlink = computer.uptime()
                    end
                else
                    -- снимаем активность если клик не по полю
                    if f.active then
                        f.active = false
                        f.cursorVisible = false
                    end
                end
            end
            drawAllFields()

            if y >= 25 and y <= 27 and x >= 69 and x <= 76+5 then
                buffer.drawRectangle(69, 25, 7, 3, 0xcccccc, 0, " ")
                animatedButton(1, 70, 25, "Сохранить", nil, nil, 11, nil, nil, 0xa91df9, 0xffffff)
                animatedButton(2, 70, 25, "Сохранить", nil, nil, 11, nil, nil, 0xa91df9, 0xffffff)
                buffer.drawChanges()
                os.sleep(0.2)
                animatedButton(1, 70, 25, "Сохранить", nil, nil, 11, nil, nil, 0x8100cc, 0xffffff)
                buffer.drawChanges()

                buffer.paste(1, 1, old)
                buffer.drawChanges()
                message("Настройки сохранены!", nil, 34)
                break
            end
            if x >= sw_x and x <= sw_x + sw_w - 1 and y == sw_y then
                sw_state = not sw_state
                
                -- Анимация (простая)
                local targetPos = sw_state and (sw_w - 2) or 1
                local step = (targetPos > sw_pipePos) and 1 or -1
                
                repeat
                    sw_pipePos = sw_pipePos + step
                    drawSwitch(sw_x, sw_y, sw_w, sw_pipePos, sw_state)
                    buffer.drawChanges()
                    os.sleep(0.02)
                until sw_pipePos == targetPos
                
                -- Тут можно добавить действие при переключении
                -- example: reactor_auto_mode = sw_state
            end

        elseif eventType == "key_down" then
            local _, _, char, code = table.unpack(eventData)
            for _, f in ipairs(searchFields) do
                if f.active then
                    if code == 14 then -- Backspace
                        if f.cursorPos > 1 then
                            f.text = f.text:sub(1, f.cursorPos - 2) .. f.text:sub(f.cursorPos)
                            f.cursorPos = f.cursorPos - 1
                        end
                    elseif code == 203 then -- стрелка влево
                        if f.cursorPos > 1 then
                            f.cursorPos = f.cursorPos - 1
                        end
                    elseif code == 205 then -- стрелка вправо
                        if f.cursorPos <= #f.text then
                            f.cursorPos = f.cursorPos + 1
                        end
                    elseif char >= 32 and char <= 126 then
                        local c = string.char(char)
                        f.text = f.text:sub(1, f.cursorPos - 1) .. c .. f.text:sub(f.cursorPos)
                        f.cursorPos = f.cursorPos + 1
                    elseif code == 28 then -- Enter
                        f.active = false
                        f.cursorVisible = false
                    end
                end
            end
            drawAllFields()
        end
    end
end

-- -----------------------------------------------------
local function checkVer()
    if updateCheck == true then
        local update = false
        local newVer = progVer

        local ok = os.execute("wget -fq https://github.com/P1KaChU337/Reactor-Control-for-OpenComputers/raw/refs/heads/main/versions.txt versions.txt > /dev/null 2>&1")
        if ok then
            local f = io.open("versions.txt", "r")
            if f then
                local remoteVer = f:read("*l")
                f:close()

                if remoteVer and remoteVer ~= "" then
                    local function verToTable(v)
                        local t = {}
                        for num in v:gmatch("%d+") do
                            table.insert(t, tonumber(num))
                        end
                        return t
                    end

                    local function isNewer(v1, v2) -- v1 > v2 ?
                        local a, b = verToTable(v1), verToTable(v2)
                        for i = 1, math.max(#a, #b) do
                            local n1, n2 = a[i] or 0, b[i] or 0
                            if n1 > n2 then return true end
                            if n1 < n2 then return false end
                        end
                        return false
                    end

                    if isNewer(remoteVer, progVer) then
                        update = true
                        newVer = remoteVer
                    end
                end
            end
        end

        os.execute("rm versions.txt > /dev/null 2>&1")
        os.execute("rm updater > /dev/null 2>&1")

        if update == true then
            message("Вышла новая версия программы...", nil, 34)
            local verfile = io.open("oldVersion.txt", "w")
            if verfile then
                verfile:write(progVer)
                verfile:close()
            end
            
            if work == true and any_reactor_on == true then
                stop()
            end
            local old = buffer.copy(1, 1, 160, 50)
            buffer.drawRectangle(1, 1, 160, 50, 0x000000, 0, " ", 0.4)

            buffer.drawRectangle(40, 22, 80, 6, 0xcccccc, 0, " ")
            buffer.drawRectangle(39, 23, 82, 4, 0xcccccc, 0, " ")
            local cornerPos = {
                {39, 22, 1}, {120, 22, 2},
                {120, 27, 3}, {39, 27, 4}
            }
            for _, c in ipairs(cornerPos) do
                buffer.drawText(c[1], c[2], 0xcccccc, brailleChar(brail_status[c[3]]))
            end
            buffer.drawText(45, 23, 0x000000, "Доступно обновление Reactor Control by P1KaChU337 (v" .. progVer ..", --> v" .. newVer .. ").")
            buffer.drawText(43, 24, 0x000000, "Нажмите \"ОК\" для продолжения без обновления или \"Установить\" для обновления.")
            animatedButton(1, 70, 25, "Ок", nil, nil, 6, nil, nil, 0x8100cc, 0xffffff)
            animatedButton(1, 80, 25, "Установить", nil, nil, 10, nil, nil, 0x8100cc, 0xffffff)    

            buffer.drawChanges()
            while true do
                local eventData = {event.pull(0.05)}
                local eventType = eventData[1]
                if eventType == "touch" then
                    local _, _, x, y = table.unpack(eventData)

                    if y >= 25 and y <= 27 and x >= 69 and x <= 76 then
                        buffer.drawRectangle(69, 25, 7, 3, 0xcccccc, 0, " ")
                        animatedButton(1, 70, 25, "Ок", nil, nil, 6, nil, nil, 0xa91df9, 0xffffff)
                        animatedButton(2, 70, 25, "Ок", nil, nil, 6, nil, nil, 0xa91df9, 0xffffff)
                        buffer.drawChanges()
                        os.sleep(0.2)
                        animatedButton(1, 70, 25, "Ок", nil, nil, 6, nil, nil, 0x8100cc, 0xffffff)
                        buffer.drawChanges()

                        buffer.paste(1, 1, old)
                        buffer.drawChanges()
                        message("Установка обновлений отменена!", nil, 34)
                        break
                    end

                    if y >= 25 and y <= 27 and x >= 79 and x <= 90 then
                        buffer.drawRectangle(79, 25, 11, 3, 0xcccccc, 0, " ")
                        animatedButton(1, 80, 25, "Установить", nil, nil, 10, nil, nil, 0xa91df9, 0xffffff)
                        animatedButton(2, 80, 25, "Установить", nil, nil, 10, nil, nil, 0xa91df9, 0xffffff)
                        buffer.drawChanges()
                        os.sleep(0.2)
                        animatedButton(1, 80, 25, "Установить", nil, nil, 10, nil, nil, 0x8100cc, 0xffffff)
                        buffer.drawChanges()
                        os.sleep(0.5)
                        buffer.drawRectangle(69, 25, 25, 3, 0xcccccc, 0, " ")
                        buffer.drawText(70, 26, 0x767676, "Установка обновлений...")
                        buffer.drawChanges()

                        local ok = os.execute("wget -fq https://github.com/P1KaChU337/Reactor-Control-for-OpenComputers/raw/refs/heads/main/installer/updater.lua updater > /dev/null 2>&1")
                        if not ok then
                            buffer.paste(1, 1, old)
                            message("Обновление прервано из-за ошибки!", colors.msgwarn, 34)
                            os.execute("rm updater > /dev/null 2>&1")
                            buffer.drawChanges()
                            return
                        end

                        local f = io.open("updater", "r")
                        if not f then
                            buffer.paste(1, 1, old)
                            message("Обновление прервано из-за ошибки!", colors.msgwarn, 34)
                            os.execute("rm updater > /dev/null 2>&1")
                            buffer.drawChanges()
                            return
                        end
                        local content = f:read("*a")
                        f:close()

                        if not content or content == "" then
                            buffer.paste(1, 1, old)
                            message("Обновление прервано из-за ошибки!", colors.msgwarn, 34)
                            os.execute("rm updater > /dev/null 2>&1")
                            buffer.drawChanges()
                            return
                        end

                        buffer.clear(0x000000)
                        buffer.drawChanges()
                        shell.execute("clear")
                        rawset(_G, "__NR_ON_INTERRUPT__", nil)
                        exit = true
                        os.execute("updater")
                        os.exit()
                    end
                end
            end
        end
    end
end

-- ----------------------------------------------------------------------------------------------------
local function loadChangelog(url, tmpFile)
    tmpFile = tmpFile or "/tmp/changelog.lua"
    os.execute("wget -fq " .. url .. " " .. tmpFile .. " > /dev/null 2>&1")

    local ok, chunk = pcall(loadfile, tmpFile)
    if ok and chunk then
        local ok2, data = pcall(chunk)
        if ok2 and type(data) == "table" then
            return data
        end
    end
    return nil
end

local function handleChatCommand(nick, msg, args)
    -- Проверяем разрешения пользователя
    local hasPermission = false
    for _, user in ipairs(users) do
        if user == nick then
            hasPermission = true
            break
        end
    end
    
    if not hasPermission then
        if isChatBox then
            chatBox.say("§cУ вас нет прав для управления реакторами!")
        end
        return
    end
    
    -- Обрабатываем команды
    if msg == "@help" then
        if isChatBox then
            chatBox.say("§e=== Команды Reactor Control ===")
            chatBox.say("§a@help - список команд")
            chatBox.say("§a@info - информация о системе")
            chatBox.say("§a@useradd - добавить пользователя (пример: @useradd Ник)") -- Сделай
            chatBox.say("§a@userdel - удалить пользователя (пример: @userdel Ник)")
            chatBox.say("§a@status - статус системы")
            chatBox.say("§a@setporog - установка порога жидкости (пример: @setporog 500)")
            chatBox.say("§a@start - запуск всех реакторов (или @start 1 для запуска только 1-го)")
            chatBox.say("§a@stop - остановка всех реакторов (или @stop 1 для остановки только 1-го)")
            chatBox.say("§a@exit - выход из программы")
            chatBox.say("§a@restart - перезагрузка компьютера")
            chatBox.say("§a@changelog - показать изменения в обновлениях(пример: @changelog 1.1.1)") -- Скачивается массив из гитхаба в массиве ченджлог выглядит так {"1.0.0 - описание, переносы строк и тп, все учитывать и выводить в чат","1.0.1 - описание","1.1.0 - описание"}
        end
        
    elseif msg:match("^@status") then
        if isChatBox then
            chatBox.say("§a=== Статус системы ===")
            chatBox.say("§aРеакторов: " .. reactors)

            local running = {} -- список номеров запущенных реакторов
            for i = 1, reactors do
                if reactor_work[i] == true then
                    table.insert(running, tostring(i))
                end
            end

            if #running == reactors then
                chatBox.say("§aЗапущены: Все")
            elseif #running == 0 then
                chatBox.say("§aЗапущены: Нет активных")
            else
                chatBox.say("§aЗапущены: " .. table.concat(running, ", "))
            end

            chatBox.say("§aЖидкость в МЭ: " .. fluidInMe .. " Mb")
            chatBox.say("§aПорог: " .. porog .. " Mb")
            chatBox.say("§aГенерация реакторов: " .. rf .. " RF/t")
        end

    elseif msg:match("^@start") then
        local num = tonumber(args:match("^(%d+)"))
        if isChatBox then
            if num then
                if num > 0 and num <= reactors then
                    chatBox.say("§2Запускаю реактор " .. num .. "...")
                    start(num)
                else
                    chatBox.say("§cНеверный номер реактора!")
                end
            else
                chatBox.say("§2Запускаю все реакторы...")
                starting = true
                start()
            end
        end

    elseif msg:match("^@stop") then
        local num = tonumber(args:match("^(%d+)"))
        if isChatBox then
            if num then
                if num > 0 and num <= reactors then
                    chatBox.say("§cОстанавливаю реактор " .. num .. "...")
                    stop(num)
                else
                    chatBox.say("§cНеверный номер реактора!")
                end
            else
                chatBox.say("§cОстанавливаю все реакторы...")
                starting = false
                stop()
            end
        end

    elseif msg:match("^@setporog") then
        local newPorog = tonumber(args:match("^(%d+)"))
        if newPorog then
            if newPorog <= 0 then
                chatBox.say("§cПорог жидкости не может быть отрицательным или нулевым!")
            else
                porog = newPorog
                if isChatBox then
                    chatBox.say("§2Порог жидкости установлен на " .. porog .. " Mb")
                end
            end
        else
            if isChatBox then
                chatBox.say("§aЧтобы изменить порог жидкости, используйте: @setporog <значение>")
                chatBox.say("§aПример: @setporog 500")
            end
        end
        
    elseif msg == "@info" then
        if isChatBox then
            chatBox.say("§bReactor Control v" .. version .. " Build " .. build)
            chatBox.say("§aАвтор: §eP1KaChU337")
            chatBox.say("§aGitHub: §1https://github.com/P1KaChU337/Reactor-Control-for-OpenComputers")
            chatBox.say("§aПоддержать автора на §6Boosty: §1https://boosty.to/p1kachu337")
            chatBox.say("§aИгроки с доступом: §5" .. table.concat(users, ", "))
            chatBox.say("§aСпасибо за использование программы!")
        end
    elseif msg == "@exit" then
        if isChatBox then
            chatBox.say("§cЗавершаю работу программы...")
            if work == true then
                work = false
                message("Отключаю реакторы!", colors.msginfo)
                stop()
                drawWidgets()
                drawRFinfo()
                os.sleep(0.3)
            end
            message("Завершаю работу программы...", colors.msgerror)
            buffer.drawChanges()
            os.sleep(0.2)
            buffer.drawChanges()
            os.sleep(0.5)
            buffer.clear(0x000000)
            buffer.drawChanges()
            shell.execute("clear")
            rawset(_G, "__NR_ON_INTERRUPT__", nil)
            exit = true
            os.exit()
        end
    elseif msg:match("^@useradd") then
        local newUser = args:match("^(%S+)")
        if newUser then
            -- Проверка, нет ли уже такого пользователя
            for _, u in ipairs(users) do
                if u == newUser then
                    chatBox.say("§cПользователь §5" .. newUser .. " §cуже есть в списке!")
                    return
                end
            end

            table.insert(users, newUser)
            chatBox.say("§2Пользователь §5" .. newUser .. " §2добавлен!")
            userUpdate()
        else
            chatBox.say("§aИспользование: @useradd <ник>")
        end
    elseif msg:match("^@userdel") then
        local delUser = args:match("^(%S+)")
        if delUser then
            local found = false
            for i, u in ipairs(users) do
                if u == delUser then
                    table.remove(users, i)
                    chatBox.say("§2Пользователь §5" .. delUser .. " §2удалён!")
                    found = true
                    userUpdate()
                    break
                end
            end
            if not found then
                chatBox.say("§cПользователь §5" .. delUser .. " §cне найден!")
            end
        else
            chatBox.say("§aИспользование: @userdel <ник>")
        end

    elseif msg:match("^@changelog") then
        local versionReq = args:match("^(%S+)")
        if not changelog then
            chatBox.say("§cОшибка загрузки changelog.lua!")
            return
        end

        if versionReq then
            local found = false
            for _, entry in ipairs(changelog) do
                if entry.version == versionReq then
                    chatBox.say("§eИзменения в версии " .. entry.version .. ":")
                    for _, line in ipairs(entry.changes) do
                        chatBox.say("§a- " .. line)
                    end
                    found = true
                    break
                end
            end
            if not found then
                chatBox.say("§cВерсия " .. versionReq .. " не найдена в ченджлоге!")
            end
        else
            chatBox.say("§eДоступные версии:")
            for _, entry in ipairs(changelog) do
                chatBox.say("§a" .. entry.version)
            end
            chatBox.say("§aИспользуйте: @changelog <версия>")
        end

    elseif msg == "@restart" then
        if isChatBox then
            chatBox.say("§cПерезагрузка системы...")
        end
        computer.shutdown(true)
    end
end

local function stripFormatting(s)
    if not s then return "" end
    -- убираем Minecraft-подобные цветовые коды '§x'
    s = s:gsub("§.", "")
    return s
end

local function trim(s)
    return (s or ""):match("^%s*(.-)%s*$") or ""
end

local function chatMessageHandler()
    while not exit do
        local eventData = { event.pull(1, "chat_message") }
        if eventData[1] == "chat_message" then
            local _, _, nick, rawMsg = table.unpack(eventData)

            -- очистить сообщение, привести к нижнему регистру и обрезать пробелы
            local clean = trim(stripFormatting(tostring(rawMsg)):lower())

            -- вытащить первую "словную" часть (команду) и остаток (аргументы)
            local command = clean:match("^(%S+)")
            local args = ""
            if command then
                args = clean:match("^%S+%s*(.*)$") or ""
            end

            -- если команда есть в списке — передаём в обработчик
            if command and chatCommands[command] then
                -- изменил сигнатуру: передаю команду и аргументы отдельно
                handleChatCommand(nick, command, args)
            end
        end
        os.sleep(0)
    end
end

-- ----------------------------------------------------------------------------------------------------

local function handleTouch(x, y, uuid)
    local fl_y1 = config.clickAreaPorogPlus.y1
    if flux_network == true then fl_y1 = config.clickAreaPorogPlus.y2 end
    if y >= config.clickArea1.y1 and
        y <= config.clickArea1.y2 and 
        x >= config.clickArea1.x1 and 
        x <= config.clickArea1.x2 then
        buffer.drawRectangle(12, 44, 26, 3, colors.bg3, 0, " ")
        animatedButton(1, 13, 44, "Отключить реакторы!", nil, nil, 24, nil, nil, 0xfb3737)
        animatedButton(2, 13, 44, "Отключить реакторы!", nil, nil, 24, nil, nil, 0xfb3737)
        buffer.drawChanges()
        starting = false
        if reactors <= 0 then
            message("У вас не подключено ни одного реактора!", colors.msgwarn, 34)
            os.sleep(0.2)
            animatedButton(1, 13, 44, "Отключить реакторы!", nil, nil, 24, nil, nil, 0xfd3232)
            buffer.drawChanges()
            return
        end
        if work == false then
            drawStatus()
            if any_reactor_on == false then
                message("Реакторы уже отключенны!", colors.msgwarn)
                os.sleep(0.2)
                animatedButton(1, 13, 44, "Отключить реакторы!", nil, nil, 24, nil, nil, 0xfd3232)
                buffer.drawChanges()
            else
                stop()
                updateReactorData()
                drawWidgets()
                drawRFinfo()
                os.sleep(0.2)
                animatedButton(1, 13, 44, "Отключить реакторы!", nil, nil, 24, nil, nil, 0xfd3232)
                buffer.drawChanges()
            end
            return
        end
        work = false
        stop()
        updateReactorData()
        os.sleep(0.2)
        animatedButton(1, 13, 44, "Отключить реакторы!", nil, nil, 24, nil, nil, 0xfd3232)
        buffer.drawChanges()

        os.sleep(0.3)
        drawDynamic()
    elseif 
        y >= config.clickArea19.y1 and
        y <= config.clickArea19.y2 and 
        x >= config.clickArea19.x1 and 
        x <= config.clickArea19.x2 then
        buffer.drawRectangle(4, 44, 6, 3, colors.bg3, 0, " ")
        animatedButton(1, 5, 44, "🔧", nil, nil, 4, nil, nil, 0x8100cc, 0xffffff)
        animatedButton(2, 5, 44, "🔧", nil, nil, 4, nil, nil, 0x8100cc, 0xffffff)
        buffer.drawChanges()
        
        os.sleep(0.2)
        animatedButton(1, 5, 44, "🔧", nil, nil, 4, nil, nil, 0xa91df9, 0xffffff)
        buffer.drawChanges()
        
        drawSettingsMenu()
        drawDynamic()
    elseif 
        y >= config.clickArea20.y1 and
        y <= config.clickArea20.y2 and 
        x >= config.clickArea20.x1 and 
        x <= config.clickArea20.x2 then
        buffer.drawRectangle(4, 47, 6, 3, colors.bg3, 0, " ")
        animatedButton(1, 5, 47, "ⓘ", nil, nil, 4, nil, nil, 0x8100cc, 0x05e2ff)
        animatedButton(2, 5, 47, "ⓘ", nil, nil, 4, nil, nil, 0x8100cc, 0x05e2ff)
        buffer.drawChanges()
        
        os.sleep(0.2)
        animatedButton(1, 5, 47, "ⓘ", nil, nil, 4, nil, nil, 0xa91df9, 0x05e2ff)
        buffer.drawChanges()
        
        testMenu()
        drawDynamic()    
    elseif 
        y >= config.clickArea4.y1 and
        y <= config.clickArea4.y2 and 
        x >= config.clickArea4.x1 and 
        x <= config.clickArea4.x2 then
        buffer.drawRectangle(40, 44, 25, 3, colors.bg3, 0, " ")
        animatedButton(1, 41, 44, "Запуск реакторов!", nil, nil, 23, nil, nil, 0x61ff52)
        animatedButton(2, 41, 44, "Запуск реакторов!", nil, nil, 23, nil, nil, 0x61ff52)
        buffer.drawChanges()
        starting = true
        if reactors <= 0 then
            message("У вас не подключено ни одного реактора!", colors.msgwarn, 34)
            os.sleep(0.2)
            animatedButton(1, 41, 44, "Запуск реакторов!", nil, nil, 23, nil, nil, 0x35e525)
            buffer.drawChanges()
            return
        end
        if work == true then
            drawStatus()
            if any_reactor_off == true then
                start()
                os.sleep(0.2)
                animatedButton(1, 41, 44, "Запуск реакторов!", nil, nil, 23, nil, nil, 0x35e525)
                buffer.drawChanges()
                drawWidgets()
                drawRFinfo()
            else
                message("Реакторы уже запущены!", colors.msgwarn)
                os.sleep(0.2)
                animatedButton(1, 41, 44, "Запуск реакторов!", nil, nil, 23, nil, nil, 0x35e525)
                buffer.drawChanges()
                return
            end
            return
        end
        work = true
        start()
        updateReactorData()
        os.sleep(0.2)
        animatedButton(1, 41, 44, "Запуск реакторов!", nil, nil, 23, nil, nil, 0x35e525)
        buffer.drawChanges()
        
        os.sleep(0.3)
        drawDynamic()
    elseif
        y >= config.clickArea2.y1 and
        y <= config.clickArea2.y2 and 
        x >= config.clickArea2.x1 and 
        x <= config.clickArea2.x2 then
        buffer.drawRectangle(12, 47, 26, 3, colors.bg3, 0, " ")
        animatedButton(1, 13, 47, "Рестарт программы.", nil, nil, 24, nil, nil, colors.whitebtn2)
        animatedButton(2, 13, 47, "Рестарт программы.", nil, nil, 24, nil, nil, colors.whitebtn2)
        stop()
        message("Перезагружаюсь!")
        buffer.drawChanges()
        os.sleep(0.2)
        animatedButton(1, 13, 47, "Рестарт программы.", nil, nil, 24, nil, nil, colors.whitebtn)
        buffer.drawChanges()
        os.sleep(1)
        shell.execute("reboot")
    elseif
        y >= config.clickArea3.y1 and
        y <= config.clickArea3.y2 and 
        x >= config.clickArea3.x1 and 
        x <= config.clickArea3.x2 then
        buffer.drawRectangle(40, 47, 25, 3, colors.bg3, 0, " ")
        animatedButton(1, 41, 47, "Выход из программы.", nil, nil, 23, nil, nil, colors.whitebtn2)
        animatedButton(2, 41, 47, "Выход из программы.", nil, nil, 23, nil, nil, colors.whitebtn2)
        if work == true then
            work = false
            message("Отключаю реакторы!", colors.msginfo)
            stop()
            drawWidgets()
            drawRFinfo()
            os.sleep(0.3)
        end
        message("Завершаю работу программы...", colors.msgerror)
        buffer.drawChanges()
        os.sleep(0.2)
        animatedButton(1, 41, 47, "Выход из программы.", nil, nil, 23, nil, nil, colors.whitebtn)
        buffer.drawChanges()
        os.sleep(0.5)
        buffer.clear(0x000000)
        buffer.drawChanges()
        shell.execute("clear")
        rawset(_G, "__NR_ON_INTERRUPT__", nil)
        exit = true
        os.exit()
    elseif
        y >= config.clickArea5.y1 and
        y <= config.clickArea5.y2 and 
        x >= config.clickArea5.x1 and 
        x <= config.clickArea5.x2 then
        buffer.drawRectangle(67, 44, 20, 3, colors.bg3, 0, " ")
        animatedButton(1, 68, 44, "Пр.Обновить МЭ", nil, nil, 18, nil, nil, 0x38afff)
        animatedButton(2, 68, 44, "Пр.Обновить МЭ", nil, nil, 18, nil, nil, 0x38afff)
        buffer.drawChanges()
        checkFluid()
        os.sleep(0.2)
        animatedButton(1, 68, 44, "Пр.Обновить МЭ", nil, nil, 18, nil, nil, nil)
        buffer.drawChanges()
    elseif
        y >= config.clickArea6.y1 and
        y <= config.clickArea6.y2 and 
        x >= config.clickArea6.x1 and 
        x <= config.clickArea6.x2 then
        buffer.drawRectangle(67, 47, 20, 3, colors.bg3, 0, " ")
        animatedButton(1, 68, 47, "Метрика: " .. status_metric, nil, nil, 18, nil, nil, colors.whitebtn2)
        animatedButton(2, 68, 47, "Метрика: " .. status_metric, nil, nil, 18, nil, nil, colors.whitebtn2)
        metric = metric + 1
        if metric == 0 then
            status_metric = "Auto"
        elseif metric == 1 then
            status_metric = "Rf, Mb"
            metricRf = "Rf"
            metricMb = "Mb"
            message("Метрика изменена на: Rf, Mb!", nil, 34)
        elseif metric == 2 then
            status_metric = "kRf, kMb"
            metricRf = "kRf"
            metricMb = "kMb"
            message("Метрика изменена на: kRf, kMb!", nil, 34)
        elseif metric == 3 then
            status_metric = "mRf, mMb"
            metricRf = "mRf"
            metricMb = "mMb"
            message("Метрика изменена на: mRf, mMb!", nil, 34)
        elseif metric == 4 then
            status_metric = "gRf, mMb"
            metricRf = "gRf"
            metricMb = "mMb"
            message("Метрика изменена на: gRf, mMb!", nil, 34)
        elseif metric > 4 then
            status_metric = "Auto"
            metricRf = "Rf"
            metricMb = "Mb"
            message("Метрика изменена на: Auto!", nil, 34)
            metric = 0
        end
        os.sleep(0.2)
        animatedButton(1, 68, 47, "Метрика: " .. status_metric, nil, nil, 18, nil, nil, colors.whitebtn)
        drawDynamic()
    elseif
    
        y >= fl_y1 and
        y <= fl_y1 and 
        x >= config.clickAreaPorogPlus.x1 and 
        x <= config.clickAreaPorogPlus.x2 then

        porog = porog + 2500
        saveCfg()
        drawDigit(124, fl_y1, brail_greenbtn, 0x5f9300)
        buffer.drawChanges()
        os.sleep(0.2)
        drawPorog()
    elseif
        y >= fl_y1 and
        y <= fl_y1 and
        x >= config.clickAreaPorogMinus.x1 and
        x <= config.clickAreaPorogMinus.x2 then
        if porog > 0 then
            porog = porog - 2500
            saveCfg()
            if porog == 27500 then
                message("Порог ниже рекомендованного!", colors.msgwarn)
            end     
        end
        drawDigit(126, fl_y1, brail_redbtn, 0x9d0000)
        buffer.drawChanges()
        os.sleep(0.2)
        drawPorog()
    end
    for i = 1, reactors do
        local clickArea = config["clickArea" .. (6 + i)]
        if y >= clickArea.y1 and y <= clickArea.y2 and x >= clickArea.x1 and x <= clickArea.x2 and reactor_aborted[i] == false or nil then
            local Rnum = i
            local xw, yw = widgetCoords[Rnum][1], widgetCoords[Rnum][2]

            buffer.drawRectangle(xw + 5, yw + 8, 12, 3, colors.bg, 0, " ")
            animatedButton(1, xw + 6, yw + 8, (reactor_work[Rnum] and "Отключить" or "Включить"), nil, nil, 10, nil, nil, (reactor_work[Rnum] and 0xfb3737 or 0x61ff52))
            animatedButton(2, xw + 6, yw + 8, (reactor_work[Rnum] and "Отключить" or "Включить"), nil, nil, 10, nil, nil, (reactor_work[Rnum] and 0xfb3737 or 0x61ff52))
            buffer.drawChanges()

            drawStatus(Rnum)

            if reactor_work[Rnum] then
                stop(Rnum)
                updateReactorData(Rnum)
            else
                start(Rnum)
                starting = true
                updateReactorData(Rnum)
            end
            
            if not any_reactor_on then
                work = false
                starting = false
            end

            os.sleep(0.2)
            animatedButton(1, xw + 6, yw + 8, (reactor_work[Rnum] and "Отключить" or "Включить"), nil, nil, 10, nil, nil, (reactor_work[Rnum] and 0xfd3232 or 0x2beb1a))
            drawWidgets()
            break
        end
        
    end
end

-- ----------------------------------------------------------------------------------------------------
local function mainLoop()
    -- Сбрасываем все динамические переменные, чтобы избежать конфликта данных.
    -- Это обеспечивает "чистый" старт при каждом запуске.
    reactors = 0
    any_reactor_on = false
    any_reactor_off = false

    -- Очищаем массивы вместо сброса каждого элемента.
    -- Это более надежно, так как гарантирует, что в массивах не останется старых данных.
    reactor_work = {}
    temperature = {}
    reactor_type = {}
    reactor_address = {}
    reactor_aborted = {}
    reactors_proxy = {}
    reactor_rf = {}
    reactor_getcoolant = {}
    reactor_maxcoolant = {}
    reactor_depletionTime = {}
    
    me_proxy = nil
    me_network = false
    flux_network = false
    flux_checked = false
    second = 0
    minute = 0
    hour = 0
    last_me_address = nil
    
    if porog < 0 then porog = 0 end
    
    switchTheme(theme)
    initReactors()
    local addr = initMe()
    initFlux()
    initChatBox()
    silentstop()
    
    for i = 1, (flux_network and 19 or 21) do
        consoleLines[i] = ""
    end 
    last_me_address = addr
    drawStatic()
    drawDynamic()
    message("------Reactor Control v" .. version .. "-------", 0x72f8ff)
    message("Автор приложения: P1KaChU337", 0x72f8ff)
    message("Версия приложения: " .. version .. ", Build " .. build, 0x72f8ff)
    message("Авто-обновление: " .. (updateCheck and "Включенно" or "Выключенно"), 0x72f8ff, 34)
    message("Реакторов найдено: " .. reactors, 0x72f8ff)
    message("МЭ-сеть: " .. (me_network and "Подключена" or "Не подключена"), 0x72f8ff)
    message("Flux-сеть: " .. (flux_network and "Подключена" or "Не подключена"), 0x72f8ff)
    message("ChatBox: " .. (isChatBox and "Подключен" or "Не подключен"), 0x72f8ff)
    message("---------------------------------", 0x72f8ff) --34
    message(" ")
    userUpdate()
    message("Инициализация реакторов...", colors.textclr)
    supportersText = loadSupportersFromURL("https://github.com/P1KaChU337/Reactor-Control-for-OpenComputers/raw/refs/heads/main/supporters.txt")
    changelog = loadChangelog("https://github.com/P1KaChU337/Reactor-Control-for-OpenComputers/raw/refs/heads/main/changelog.lua")
    updateReactorData()
    if reactors ~= 0 then
        message("Реакторы инициализированы!", colors.msginfo, 34)
    else
        message("Реакторы не найдены!", colors.msgerror)
        message("Проверьте подключение реакторов!", colors.msgerror, 34)
    end
    checkFluid()
    if starting == true then
        start()
    end

    if isChatBox then
        chatThread = require("thread").create(chatMessageHandler)
        message("Чат-бокс подключен! Список команд: @help", colors.msginfo)
        chatBox.say("§2Чат-бокс подключен! §aСписок команд: @help")
    end

    if work == true then
        if any_reactor_off == true then
            start()
            os.sleep(0.2)
            drawWidgets()
            drawRFinfo()
        else
            os.sleep(0.2)
            return
        end
        return
    end
    if offFluid == true then
        for i = 1, reactors do
            if reactor_type[i] == "Fluid" then
                if reactor_work[i] == true then
                    stop(i)
                end
                updateReactorData(i)
                reactor_aborted[i] = true
            end
        end
        drawFluidinfo()
        drawWidgets()
    end
    checkVer()
    if isFirstStart == true then
        drawSettingsMenu()
        message("Первый запуск программы завершен!", colors.msginfo)
        isFirstStart = false
        saveCfg()
    end
    depletionTime = depletionTime or 0
    reactors = tonumber(reactors) or 0
    while true do
        if exit == true then
            return
        end

        local now = computer.uptime()

        if reactors > 0 and reactorsChanged() then
            os.sleep(1)
            initReactors()
            drawDynamic()
            updateReactorData()
            message("Список реакторов обновлён", colors.textclr)
        end

        if meChanged() then
            os.sleep(1)
            initMe()
            message("МЭ система обновленна", colors.textclr)
            if offFluid == true then
                for i = 1, reactors do
                    if reactor_type[i] == "Fluid" then
                        drawStatus(i)
                        if reactor_work[i] == true then
                            stop(i)
                        end
                        ismechecked = false
                        reactor_aborted[i] = true
                        updateReactorData(i)
                    end
                end
                drawFluidinfo()
                drawWidgets()
            end
        end

        if now - lastTime >= 1 then
            lastTime = now
            second = second + 1
            if me_network then
                MeSecond = MeSecond + 1
            end
            if work == true then
                if second % 5 == 0 then
                    for i = 1, reactors do
                        local proxy = reactors_proxy[i]
                        if proxy and proxy.getTemperature then
                            reactor_rf[i] = safeCall(proxy, "getEnergyGeneration", 0)
                        else
                            reactor_rf[i] = 0
                        end
                        
                    end
                    drawRFinfo()
                end

                if second % 2 == 0 then
                    for i = 1, reactors do
                        if reactor_type[i] == "Fluid" then
                            local proxy = reactors_proxy[i]
                            if proxy and proxy.getFluidCoolant then
                                temperature[i]  = safeCall(proxy, "getTemperature", 0)
                                reactor_getcoolant[i] = safeCall(proxy, "getFluidCoolant", 0) or 0
                                reactor_maxcoolant[i] = safeCall(proxy, "getMaxFluidCoolant", 0) or 1
                            else
                                reactor_getcoolant[i] = 0
                                reactor_maxcoolant[i] = 1
                                temperature[i] = 0
                            end
                        end
                        
                    end
                end
            else
                if second % 20 == 0 then
                    for i = 1, reactors do
                        local proxy = reactors_proxy[i]
                        if proxy and proxy.hasWork then
                            reactor_work[i] = safeCall(proxy, "hasWork", false)
                            reactor_type[i] = safeCall(proxy, "isActiveCooling", false) and "Fluid" or "Air"
                        else
                            reactor_work[i] = false
                        end
                        
                    end
                end
            end

            if second % 5 == 0 then
                consumeSecond = getTotalFluidConsumption()
                drawStatus()
                drawFluxRFinfo()
                if flux_network == true and flux_checked == false then
                    clearRightWidgets()
                    drawDynamic()
                    flux_checked = true
                elseif flux_network == false and flux_checked == true then
                    clearRightWidgets()
                    drawDynamic()
                    flux_checked = false
                end
            end

            if any_reactor_on then
                if depletionTime <= 0 then
                    local newTime = getDepletionTime()
                    if newTime > 0 then
                        depletionTime = newTime
                    else
                        depletionTime = 0
                    end
                else
                    depletionTime = depletionTime - 1
                end
            else
                depletionTime = 0
            end
            if second >= 60 then
                minute = minute + 1
                if minute % 10 == 0 then
                    supportersText = loadSupportersFromURL("https://github.com/P1KaChU337/Reactor-Control-for-OpenComputers/raw/refs/heads/main/supporters.txt")
                end
                if minute >= 60 then
                    checkVer()
                    hour = hour + 1
                    minute = 0
                end
                second = 0
            end
            if MeSecond >= 60 then
                checkFluid()
                if offFluid == true then
                    for i = 1, reactors do
                        if reactor_type[i] == "Fluid" and reactor_work[i] then
                            stop(i)
                            updateReactorData(i)
                            reactor_aborted[i] = true
                        end
                    end
                end
                drawFluidinfo()
            end
            drawTimeInfo()
            drawWidgets()
        end
        if supportersText then
            drawMarquee(124, 6, supportersText ..  "                            ", 0xF15F2C)
        end
        local eventData = {event.pull(0.05)}
        local eventType = eventData[1]
        if eventType == "touch" then
            local _, _, x, y, button, uuid = table.unpack(eventData)
            handleTouch(x, y)
        end
        os.sleep(0)
    end
end

-- ----------------------------------------------------------------------------------------------------
local lastCrashTime = 0
while not exit do
    local ok, err = xpcall(mainLoop, debug.traceback)
    if not ok then
        local now = computer.uptime() -- Заменил os.time() на computer.uptime()

        if tostring(err):lower():find("interrupted") or exit == true then
            return
        end
        
        if now - lastCrashTime < 5 then
            logError("FAILSAFE: Rapid crashing detected.")
            message("Rapid crashing detected.", 0xff0000, 34)
            os.sleep(5)
        end
        lastCrashTime = now

        logError("Global Error:")
        logError(err)
        message("Code: " .. tostring(err), 0xff0000, 34)
        message("Global Error!", 0xff0000, 34)
        message("Restarting in 3 seconds...", 0xffa500, 34)
    
        os.sleep(3)
    end
end
