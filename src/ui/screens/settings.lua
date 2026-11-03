-- Окно настроек. В отличие от v1.1.3 реакторы при открытии НЕ останавливаются:
-- окно — это слой интерфейса, защита продолжает работать.
local unicode = require("unicode")
local G = require("ui.gfx")
local S = require("ui.sprites")
local T = require("ui.theme")

local M = {}

local X, Y, W, H = 35, 10, 65, 27
local MAX_ROWS = 13

-- Черновик: правки применяются только по «Сохранить и выйти»
local draft

local function copyList(t) local r = {} for i, v in ipairs(t) do r[i] = v end return r end

function M.open(ui)
    local cfg = ui.app.cfg
    draft = {
        threshold = tostring(math.floor(cfg.threshold)),
        theme = cfg.theme == "light",
        updateCheck = cfg.updateCheck,
        debugLog = cfg.debugLog,
        autoRestart = cfg.autoRestart,
        users = copyList(cfg.users),
        nick = "",
        focus = nil,           -- "threshold" | "nick"
        nickHint = nil,
        blinkAt = ui:clock(),
        cursorOn = true,
        scroll = 0,
    }
end

function M.wakeIn(ui)
    if draft and draft.focus then return math.max(0, draft.blinkAt + 0.5 - ui:clock()) end
end

local function close(ui) draft = nil ui:closeModal() end

local function save(ui)
    local app = ui.app
    local cfg = app.cfg
    local thr = tonumber(draft.threshold)
    if thr then cfg.threshold = math.floor(thr) end
    cfg.theme = draft.theme and "light" or "dark"
    cfg.updateCheck = draft.updateCheck
    cfg.debugLog = draft.debugLog
    cfg.autoRestart = draft.autoRestart
    cfg.users = draft.users
    cfg.firstStart = false
    app.log:setFileLevel(cfg.debugLog and "debug" or "info")
    app.saveConfig()
    app.actions:syncUsers()
    app.log:info("Настройки сохранены!")
    app.state:touch()
    close(ui)
end

local function addNick(ui)
    local nick = draft.nick:match("^%s*(.-)%s*$")
    local err
    if nick == "" then err = "Не может быть пустым!"
    elseif #nick > 16 then err = "Нельзя > 16 символов!"
    elseif #nick < 3 then err = "Не меньше 3 символов!"
    else
        for _, n in ipairs(draft.users) do if n == nick then err = "Уже в белом списке!" end end
    end
    if err then draft.nickHint = err return end
    draft.users[#draft.users + 1] = nick
    draft.nick = ""
    draft.nickHint = nil
end

-- Переключатель в тёмной «кнопке» с подписью, как в v1.1.3
local function toggleRow(ui, id, y, title, label, key)
    G.text(X + 3, Y + y, 0x000000, title)
    G.button(X + 4, Y + y + 1, 20, "", 0x444444, 0xffffff, false)
    G.text(X + 5, Y + y + 2, 0xffffff, label)
    G.switch(X + 16, Y + y + 2, 7, draft[key], nil, 0x777777, nil, 0x444444)
    ui:hit(X + 3, Y + y + 1, X + 24, Y + y + 3, function() draft[key] = not draft[key] end, id)
end

function M.draw(ui)
    if not draft then M.open(ui) end
    local app = ui.app
    G.box(X - 1, Y, W + 2, H, T.modal)
    -- клик мимо окна — выйти без сохранения
    ui:hit(1, 1, 160, 50, function() close(ui) end)
    ui:hit(X - 1, Y, X + W, Y + H - 1, function() draft.focus = nil end)

    G.center(X, W, 0x000000, "Меню настроек приложения ReactorControl v" .. app.VERSION_SHORT, Y + 1)

    -- порог
    G.text(X + 7, Y + 3, 0x000000, "Порог жидкости (mB)")
    G.field(X + 3, Y + 5, 22, draft.threshold, "Введите порог(Mb)", draft.focus == "threshold", draft.cursorOn)
    ui:hit(X + 3, Y + 4, X + 24, Y + 6, function() draft.focus = "threshold" draft.cursorOn = true draft.blinkAt = ui:clock() end)

    toggleRow(ui, "swTheme", 7, "Тема по умолчанию", "Светлая", "theme")
    toggleRow(ui, "swUpdate", 11, "Новые версии приложения", "Проверять", "updateCheck")
    toggleRow(ui, "swDebug", 15, "Расширенное логирование", "Включено", "debugLog")
    toggleRow(ui, "swAuto", 19, "Автозапуск реакторов", "Включён", "autoRestart")

    ui:button("save", X + 5, Y + H - 4, 18, "Сохранить и выйти", ui:isPressed("save") and T.purple or T.purpleDark, 0xffffff, function() save(ui) end)
    G.text(X + 1, Y + H - 1, 0x999999, "P.S. Нажмите в любом месте вне окна, чтобы выйти без сохранения")

    -- белый список
    G.text(X + 29, Y + 3, 0x000000, "Игроки добавленные в белый список:")
    local wx, wy, ww, wh = X + 30, Y + 4, 32, 18
    G.rect(wx, wy, ww, 1, 0x333333)
    G.rect(wx - 1, wy + 1, ww + 2, wh - 2, 0x333333)
    G.rect(wx, wy + wh - 1, ww, 1, 0x333333)
    ui.buffer.drawRectangle(wx, wy, ww, 1, 0x333333, 0xcccccc, S.button[7])
    ui.buffer.drawText(wx - 1, wy, 0x333333, S.button[4])
    ui.buffer.drawText(wx + ww, wy, 0x333333, S.button[2])
    ui.buffer.drawText(wx + ww, wy + wh - 1, 0x333333, S.button[8])
    ui.buffer.drawText(wx - 1, wy + wh - 1, 0x333333, S.button[9])
    for i = 1, MAX_ROWS do
        local yy = wy + i
        G.rect(wx, yy, ww, 1, i % 2 == 0 and 0x444444 or 0x555555)
        local idx = i + draft.scroll
        local name = draft.users[idx]
        if name then
            G.center(wx + 1, ww - 7, 0xffffff, name, yy)
            G.text(wx + ww - 4, yy, ui:isPressed("del" .. idx) and 0xcc0000 or 0xff2121, "Del")
            ui:hit(wx + ww - 4, yy, wx + ww - 2, yy, function()
                table.remove(draft.users, idx)
                if draft.scroll > 0 and draft.scroll > #draft.users - MAX_ROWS then draft.scroll = draft.scroll - 1 end
            end, "del" .. idx)
        else
            G.center(wx + 1, ww - 2, 0xcbcbcb, "* Пусто *", yy)
        end
    end
    G.field(X + 30, Y + 20, 24, draft.nick, draft.nickHint or "Введите никнейм", draft.focus == "nick", draft.cursorOn,
        0x353535, 0x333333, draft.nickHint and 0xff0000 or 0xececec)
    ui:hit(X + 30, Y + 19, X + 53, Y + 21, function() draft.focus = "nick" draft.nickHint = nil draft.cursorOn = true draft.blinkAt = ui:clock() end)
    ui:button("add", X + 56, Y + 19, 5, "ADD", ui:isPressed("add") and 0x21ff21 or 0x37c72a, 0xffffff, function() addNick(ui) end)

    -- мигание курсора
    if draft.focus and ui:clock() - draft.blinkAt >= 0.5 then
        draft.cursorOn = not draft.cursorOn
        draft.blinkAt = ui:clock()
    end
end

function M.key(ui, char, code)
    if not draft or not draft.focus then return end
    local key = draft.focus == "threshold" and "threshold" or "nick"
    local text = draft[key]
    draft.cursorOn = true
    draft.blinkAt = ui:clock()
    if code == 14 then                     -- Backspace
        draft[key] = unicode.sub(text, 1, -2)
    elseif code == 28 then                 -- Enter
        if key == "nick" then addNick(ui) else draft.focus = nil end
    elseif char and char >= 32 then
        local c = unicode.char(char)
        if key == "threshold" then
            if c:match("%d") and #text < 15 then draft[key] = text .. c end
        elseif unicode.len(text) < 16 then
            draft[key] = text .. c
        end
    end
end

function M.scroll(ui, x, y, dir)
    if not draft then return end
    local maxScroll = math.max(0, #draft.users - MAX_ROWS)
    draft.scroll = math.max(0, math.min(maxScroll, draft.scroll - dir))
end

return M
