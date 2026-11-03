-- Окно «Информация»: общая информация (about_v2.txt с GitHub, иначе встроенный текст), изменения, лицензия. Текст прокручивается колесом мыши
-- или нажатием на верхнюю/нижнюю половину текста.
local unicode = require("unicode")
local G = require("ui.gfx")
local T = require("ui.theme")

local M = {}

local X, Y, W, H = 20, 5, 83, 36
local TEXT_H = 29

local INFO = {
        "Автор программы: P1KaChU337",
        "",
        "Сайт автора (основной способ связи): www.pzapps.uz",
    "",
    "Другие контакты: vk.com/p1kachu337, Discord: p1kachu337, Telegram: @sh1zurz",
        "",
        "GitHub проекта: github.com/P1KaChU337/Reactor-Control-for-OpenComputers",
        "",
        "Поддержать проект можно, предварительно связавшись со мной для согласования способа поддержки (на карту, boosty, или иной подарок).",
    "",
    "Спасибо за поддержку:",
    "- DroperToper - за донат 10$",
    "- boychhhik666 - За реакторы для тестов",
    "- Fiellyns - За тесты и обратную связь",
    "- Insonain - За тесты и обратную связь",
        "",
        "Лицензия: MIT License",
        "",
        "Описание программы:",
        "Reactor Control — программа мониторинга, контроля и управления критически важными системами реакторного комплекса для игроков сервера McSkill HiTech 1.12.2, разработанная на базе мода OpenComputers. Программа предназначена для централизованного управления реакторами и связанными с ними инфраструктурными системами, а также для автоматического предотвращения аварийных ситуаций без необходимости постоянного ручного контроля.",
        "",
        "Программа поддерживает работу с жидкостными и воздушными HT-реакторами, интеграцию с Applied Energistics 2 для мониторинга и анализа жидкостей, а также интеграцию с Flux Networks для контроля энергетической сети. Подключение осуществляется через адаптеры OpenComputers к соответствующим контроллерам. Основной упор сделан на стабильность, безопасность и корректную работу реакторных комплексов любого масштаба.",
        "",
        "Реализована автоматическая система безопасности для жидкостных реакторов. Буфер каждого работающего реактора проверяется каждую секунду и считается в секундах работы по реально измеренному расходу: реактор останавливается заранее, пока буфера ещё хватает на безопасный перезапуск. Если хладагент в МЭ-сети опустился ниже порога или МЭ-сеть недоступна, жидкостные реакторы останавливаются и после восстановления запускаются автоматически. Если опустел буфер самого реактора, значит хладагент не доходит из МЭ до реактора — такой реактор нужно запустить вручную после проверки подключения. Воздушные реакторы при проблемах с жидкостью не затрагиваются.",
        "",
        "Графический интерфейс программы отображает детальную информацию по каждому реактору, включая температуру, текущую генерацию энергии, тип реактора, статус включения, уровень хладагента в буфере, индивидуальный отсчёт времени до распада топливных стержней и данные о потреблении жидкости. В общем статусе комплекса выводится количество установленных реакторов и текущее состояние системы.",
        "",
        "Программа поддерживает управление и получение информации через игровой чат с использованием Chat Box. Это позволяет запускать и останавливать реакторы, получать статус комплекса, изменять параметры безопасности и управлять списком пользователей без прямого взаимодействия с интерфейсом компьютера. Реализована система пользователей и прав доступа, а также гибкая конфигурация с пользовательскими настройками.",
        "",
        "Особое внимание уделено надёжности и стабильности работы. Программа устойчиво обрабатывает ошибки, корректно работает при потере связи с МЭ- и Flux-сетями, использует безопасные вызовы компонентов и оптимизированную отрисовку интерфейса. Архитектура кода переработана с упором на предотвращение зависаний и циклических перезагрузок, что делает программу пригодной для длительной непрерывной работы.",
        "",
        "Программа не проверяет корректность сборки самих реакторов. В случае неверной схемы реактора вся ответственность за возможные последствия полностью лежит на пользователе.",
        "",
        "Программа распространяется бесплатно и предоставляется «как есть». Возможны ошибки и баги, но они оперативно исправляются, в случае если вы нашли баг настоятельная просьба сообщить об этом автору.", 
        "Так-же автор не несёт ответственности за взрывы реакторов или иной ущерб, возникший в результате использования программы."
    }


local LICENSE = {
        "MIT License", 
        "",
        "Copyright (c) 2025 P1KaChU337",
        "",
        "English Version",
        "Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the \"Software\"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions: The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.",
        "",
        "THE SOFTWARE IS PROVIDED \"AS IS\", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.",
        "",
        "Русская версия",
        "Настоящим предоставляется разрешение любому лицу, получающему копию данного программного обеспечения и связанных с ним файлов документации («Программное обеспечение»), безвозмездно использовать Программное обеспечение без ограничений, включая, помимо прочего, права использовать, копировать, изменять, объединять, публиковать, распространять, сублицензировать и/или продавать копии Программного обеспечения, а также разрешать лицам, которым предоставляется Программное обеспечение, делать это при соблюдении следующих условий: Вышеуказанное уведомление об авторских правах и настоящее уведомление о разрешении должны быть включены во все копии или существенные части Программного обеспечения.",
        "",
        "ПРОГРАММНОЕ ОБЕСПЕЧЕНИЕ ПРЕДОСТАВЛЯЕТСЯ «КАК ЕСТЬ», БЕЗ КАКИХ-ЛИБО ГАРАНТИЙ, ЯВНЫХ ИЛИ ПОДРАЗУМЕВАЕМЫХ, ВКЛЮЧАЯ, НО НЕ ОГРАНИЧИВАЯСЬ, ГАРАНТИЯМИ ТОВАРНОЙ ПРИГОДНОСТИ,  ПРИГОДНОСТИ ДЛЯ КОНКРЕТНОЙ ЦЕЛИ И ОТСУТСТВИЯ НАРУШЕНИЯ ПРАВ. НИ ПРИ КАКИХ ОБСТОЯТЕЛЬСТВАХ  АВТОРЫ ИЛИ ПРАВООБЛАДАТЕЛИ НЕ НЕСУТ ОТВЕТСТВЕННОСТИ ЗА ЛЮБЫЕ ПРЕТЕНЗИИ, УБЫТКИ ИЛИ  ИНЫЕ ОБЯЗАТЕЛЬСТВА, БУДЬ ТО ПО ДОГОВОРНЫМ, ДЕЛИКТНЫМ ИЛИ ИНЫМ ПРИЧИНАМ,  ВОЗНИКАЮЩИЕ ИЗ ПРОГРАММНОГО ОБЕСПЕЧЕНИЯ ИЛИ В СВЯЗИ С НИМИ, НИ С ИСПОЛЬЗОВАНИЕМ  ПРОГРАММНОГО ОБЕСПЕЧЕНИЯ ИЛИ ИНЫМИ ОПЕРАЦИЯМИ С ПРОГРАММНЫМ ОБЕСПЕЧЕНИЕМ."
    }


local CHANGELOG = {
    "Версия 2.0 (в разработке):",
    "- Программа переписана с нуля: логика отделена от интерфейса, защита работает всегда, даже при открытых окнах",
    "- Буфер реактора проверяется каждую секунду и считается в секундах работы по измеренному расходу",
    "- Один пропущенный долив хладагента больше не останавливает реактор",
    "- Пауза МЭ (ограничение сервера ~15 с) больше не считается аварией",
    "- Автозапуск после восстановления хладагента в МЭ, с ограничением частоты",
    "- Время до распада считается по измеренной скорости выгорания (учитывает наниты)",
    "- Учитываются все топливные стержни (раньше только первые 9)",
    "- Реальный расход хладагента на экране (раньше занижен в 100 раз)",
    "- Номера реакторов закреплены за адресами и не меняются после перезагрузки",
    "- Открытие настроек больше не останавливает реакторы",
    "- Настройки сохраняются атомарно и переносятся из старой версии",
    "",
    "Полная история изменений: github.com/P1KaChU337/Reactor-Control-for-OpenComputers",
}

local TABS = {
    {title = "Общая информация", x = 5, w = 18, text = INFO},
    {title = "Изменения в версиях", x = 32, w = 21, text = CHANGELOG},
    {title = "MIT License", x = 65, w = 13, text = LICENSE},
}

local tab, scroll = 1, 0
local wrappedCache = {}

local function wrapText(lines, width)
    local out = {}
    for _, line in ipairs(lines) do
        if line == "" then
            out[#out + 1] = ""
        else
            local cur = ""
            for word in line:gmatch("%S+") do
                if cur == "" then cur = word
                elseif unicode.len(cur) + 1 + unicode.len(word) <= width then cur = cur .. " " .. word
                else out[#out + 1] = cur cur = word end
            end
            if cur ~= "" then out[#out + 1] = cur end
        end
    end
    return out
end

local remoteChangelog
local function changelogText(app)
    local out = {}
    local v2 = app.remote and app.remote.changelogV2
    if v2 then
        for i = #v2, 1, -1 do
            local e = v2[i]
            out[#out + 1] = "Версия " .. e.version .. ":"
            for _, c in ipairs(e.changes) do out[#out + 1] = "- " .. c end
            out[#out + 1] = ""
        end
    else
        for _, l in ipairs(CHANGELOG) do out[#out + 1] = l end
    end
    local list = app.remote and app.remote.changelog
    if list then
        out[#out + 1] = ""
        for i = #list, 1, -1 do
            local e = list[i]
            out[#out + 1] = "Версия " .. e.version .. ":"
            for _, c in ipairs(e.changes) do out[#out + 1] = "- " .. c end
            out[#out + 1] = ""
        end
    else
        out[#out + 1] = ""
        out[#out + 1] = "История версий 1.x загружается с GitHub (нужна интернет-карта)..."
    end
    return out
end

local currentApp
local function lines()
    local r = currentApp and currentApp.remote
    local key = r and tostring(r.changelog) .. tostring(r.changelogV2) .. tostring(r.about)
    if key ~= remoteChangelog then
        remoteChangelog = key
        wrappedCache[1], wrappedCache[2] = nil, nil
    end
    if not wrappedCache[tab] then
        local text = TABS[tab].text
        if tab == 2 and currentApp then text = changelogText(currentApp)
        elseif tab == 1 and r and r.about then text = r.about end
        wrappedCache[tab] = wrapText(text, W - 4)
    end
    return wrappedCache[tab]
end

local textH = TEXT_H
local function setScroll(v)
    local maxScroll = math.max(0, #lines() - textH)
    scroll = math.max(0, math.min(maxScroll, v))
end

function M.open() tab, scroll = 1, 0 end

function M.draw(ui)
    local app = ui.app
    currentApp = app
    G.box(X - 1, Y, W + 2, H, T.modal)
    ui:hit(1, 1, 160, 50, function() ui:closeModal() end)
    ui:hit(X - 1, Y, X + W, Y + H - 1, function() end)
    G.center(X, W, 0x000000, "Меню информации приложения ReactorControl v" .. app.VERSION_SHORT, Y + 1)
    for i, t in ipairs(TABS) do
        G.text(X + t.x, Y + 3, 0x111111, t.title)
        ui.buffer.drawRectangle(X + t.x - 1, Y + 4, t.w, 1, T.modal, i == tab and T.purpleDark or 0x666666, "⠉")
        ui:hit(X + t.x - 1, Y + 3, X + t.x + t.w - 2, Y + 4, function() tab, scroll = i, 0 end)
    end
    local latest = app.remote and app.remote.latest
    textH = latest and TEXT_H - 3 or TEXT_H
    local l = lines()
    for i = 1, textH do
        local s = l[i + scroll]
        if s then G.text(X + 2, Y + 4 + i, 0x000000, s) end
    end
    -- прокрутка нажатием: верхняя половина текста — вверх, нижняя — вниз
    ui:hit(X, Y + 5, X + W - 1, Y + 4 + math.floor(textH / 2), function() setScroll(scroll - 10) end)
    ui:hit(X, Y + 5 + math.floor(textH / 2), X + W - 1, Y + 4 + textH, function() setScroll(scroll + 10) end)
    if #l > textH then
        local pos = math.floor(scroll / math.max(1, #l - textH) * (textH - 1))
        G.rect(X + W - 1, Y + 5, 1, textH, 0xb4b4b4)
        G.rect(X + W - 1, Y + 5 + pos, 1, 1, T.purpleDark)
    end
    G.text(X + 4, Y + H - 1, 0x999999, "P.S. Нажмите вне окна, чтобы выйти. Текст листается колесом или нажатием")
    if latest then
        G.text(X + 3, Y + H - 3, 0x000000, "Доступна новая версия v" .. latest .. "!")
        ui:button("update", X + W - 30, Y + H - 4, 26, "Подробнее об обновлении", T.purpleDark, 0xffffff, function()
            ui:openModal(require("ui.screens.update"))
        end)
    end
end

function M.scroll(ui, x, y, dir) setScroll(scroll - dir * 3) end

return M
