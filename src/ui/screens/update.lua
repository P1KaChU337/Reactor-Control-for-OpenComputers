-- Окно «Доступно обновление»: текущая -> новая версия, список изменений из changelog_v2.lua,
-- кнопки «Обновить» (реакторы останавливаются, установщик ставит новую версию, компьютер перезагружается
-- и программа запускается) и «Позже». Открывается само, когда проверка нашла новую версию.
local unicode = require("unicode")
local G = require("ui.gfx")
local T = require("ui.theme")

local M = {}

local X, Y, W, H = 30, 8, 70, 33
local LIST_Y, LIST_H = Y + 7, 18
local scroll = 0
local cache, cacheKey

local function wrap(text, width, indent)
    local out, cur = {}, ""
    for word in text:gmatch("%S+") do
        if cur == "" then cur = word
        elseif unicode.len(cur) + 1 + unicode.len(word) <= width then cur = cur .. " " .. word
        else out[#out + 1] = cur cur = indent .. word end
    end
    if cur ~= "" then out[#out + 1] = cur end
    return out
end

local function lines(app)
    local notes = app.remote.notes
    if cache and cacheKey == notes then return cache end
    local out = {}
    if notes and #notes > 0 then
        for _, e in ipairs(notes) do
            out[#out + 1] = {"Версия " .. e.version .. ":", T.purpleDark}
            for _, c in ipairs(e.changes) do
                local title = c:match("^#%s*(.+)$")
                if title then
                    out[#out + 1] = {"", 0}
                    out[#out + 1] = {title .. ":", 0x000000}
                else
                    for _, l in ipairs(wrap("  • " .. c, W - 8, "    ")) do out[#out + 1] = {l, 0x333333} end
                end
            end
            out[#out + 1] = {"", 0}
        end
    else
        out[#out + 1] = {"Описание изменений не найдено.", 0x555555}
        out[#out + 1] = {"Полная история — в окне «Информация».", 0x555555}
    end
    cache, cacheKey = out, notes
    return out
end

function M.open() scroll = 0 end

local function setScroll(app, v)
    scroll = math.max(0, math.min(math.max(0, #lines(app) - LIST_H), v))
end

function M.draw(ui)
    local app = ui.app
    local latest = app.remote.latest or "?"
    G.box(X - 1, Y, W + 2, H, T.modal)
    ui:hit(1, 1, 160, 50, function() end)            -- клик мимо не закрывает: решение нужно принять явно
    G.center(X, W, 0x000000, "Доступно обновление Reactor Control", Y + 1)
    G.center(X, W, 0x444444, "v" .. app.VERSION .. "  →  v" .. latest, Y + 3)
    G.text(X + 3, Y + 5, 0x000000, "Что нового:")
    G.rect(X + 2, LIST_Y - 1, W - 4, LIST_H + 2, 0xdddddd)
    local l = lines(app)
    for i = 1, LIST_H do
        local row = l[i + scroll]
        if row then G.text(X + 4, LIST_Y + i - 1, row[2], row[1]) end
    end
    if #l > LIST_H then
        local pos = math.floor(scroll / math.max(1, #l - LIST_H) * (LIST_H - 1))
        G.rect(X + W - 3, LIST_Y, 1, LIST_H, 0xb4b4b4)
        G.rect(X + W - 3, LIST_Y + pos, 1, 1, T.purpleDark)
        ui:hit(X + 2, LIST_Y, X + W - 3, LIST_Y + math.floor(LIST_H / 2) - 1, function() setScroll(app, scroll - 8) end)
        ui:hit(X + 2, LIST_Y + math.floor(LIST_H / 2), X + W - 3, LIST_Y + LIST_H - 1, function() setScroll(app, scroll + 8) end)
    end
    G.text(X + 3, Y + H - 6, 0x7a0000, "При обновлении реакторы будут остановлены, компьютер перезагрузится,")
    G.text(X + 3, Y + H - 5, 0x7a0000, "и программа запустится заново. Настройки сохранятся.")
    ui:button("updNow", X + 8, Y + H - 4, 24, "Обновить", ui:isPressed("updNow") and T.purple or T.purpleDark, 0xffffff, function()
        app.log:warn("Обновление до v" .. latest .. ": останавливаю реакторы и запускаю установщик")
        app:requestUpdate()
    end)
    ui:button("updLater", X + W - 32, Y + H - 4, 24, "Позже", 0x666666, 0xffffff, function()
        app.log:info("Обновление отложено. Обновить: окно «Информация» или /home/reactorcontrol/update.lua")
        ui:closeModal()
    end)
end

function M.scroll(ui, x, y, dir) setScroll(ui.app, scroll - dir * 3) end

return M
