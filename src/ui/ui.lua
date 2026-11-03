-- Интерфейс: рисует состояние в буфер и превращает нажатия в действия.
-- Ничего не опрашивает и ничего не ждёт. Модальное окно — это слой поверх главного экрана,
-- главный цикл и защита при этом работают как обычно.
local image = require("image")
local G = require("ui.gfx")
local theme = require("ui.theme")

local UI = {}
UI.__index = UI

UI.PRESS_TIME = 0.2       -- сколько кнопка выглядит нажатой
UI.CLOCK_INTERVAL = 1     -- перерисовка часов и таймеров
UI.MIN_FRAME = 0.1        -- не чаще 10 кадров в секунду

-- opts: imagesDir
function UI.new(app, buffer, opts)
    local self = setmetatable({}, UI)
    self.app = app
    self.buffer = buffer
    self.imagesDir = opts.imagesDir
    self.images = {}
    self.hits = {}
    self.pressed = {}         -- id -> время отпускания
    self.modal = nil          -- открытое окно (screens.settings / screens.info)
    self.drawnVersion = -1
    self.lastFrame = -math.huge
    self.nextClock = 0
    self.dirty = true
    self.main = require("ui.screens.main")
    G.init(buffer)
    return self
end

function UI:clock() return self.app.clock() end

function UI:theme() return self.app.cfg.theme == "light" and theme.light or theme.dark end

function UI:background()
    local t = self:theme()
    if self.images[t.name] == nil then
        local pic, err = image.load(self.imagesDir .. "/" .. t.image)
        self.images[t.name] = pic or false
        if not pic then self.app.log:error("Нет картинки " .. t.image .. ": " .. tostring(err)) end
    end
    return self.images[t.name] or nil
end

-- Зона нажатия на текущем кадре. Позже добавленные лежат сверху.
function UI:hit(x1, y1, x2, y2, fn, id)
    self.hits[#self.hits + 1] = {x1 = x1, y1 = y1, x2 = x2, y2 = y2, fn = fn, id = id}
end

function UI:isPressed(id) return id ~= nil and (self.pressed[id] or 0) > self:clock() end

-- Кнопка с зоной нажатия и анимацией
function UI:button(id, x, y, len, text, color, textColor, onClick)
    local x1, y1, x2, y2 = G.button(x, y, len, text, color, textColor or self:theme().textBtn, self:isPressed(id))
    self:hit(x1, y1, x2, y2, onClick, id)
end

function UI:invalidate() self.dirty = true end

function UI:openModal(screen)
    self.modal = screen
    if screen.open then screen.open(self) end
    self:invalidate()
end

function UI:closeModal()
    self.modal = nil
    self:invalidate()
end

-- Сколько можно спать до следующего кадра (для главного цикла)
function UI:timeUntilNext()
    local now = self:clock()
    local t = self.nextClock - now
    for _, untilT in pairs(self.pressed) do
        if untilT > now and untilT - now < t then t = untilT - now end
    end
    if self.modal and self.modal.wakeIn then
        local w = self.modal.wakeIn(self)
        if w and w < t then t = w end
    end
    if self.dirty then t = math.min(t, self.lastFrame + UI.MIN_FRAME - now) end
    return math.max(0, t)
end

function UI:frame(force)
    local now = self:clock()
    local state = self.app.state
    local need = force or self.dirty or state.version ~= self.drawnVersion or now >= self.nextClock
    for id, untilT in pairs(self.pressed) do
        if untilT <= now then self.pressed[id] = nil need = true end
    end
    if self.modal and self.modal.wakeIn then
        local w = self.modal.wakeIn(self)
        if w and w <= 0 then need = true end
    end
    if not need or (not force and now - self.lastFrame < UI.MIN_FRAME) then return false end
    self.lastFrame = now
    self.drawnVersion = state.version
    self.dirty = false
    self.nextClock = now + UI.CLOCK_INTERVAL
    self.hits = {}
    self.main.draw(self)
    if self.modal then
        self.hits = {}   -- под окном ничего не нажимается
        G.dim(0.4)
        self.modal.draw(self)
    end
    self.buffer.drawChanges()
    return true
end

function UI:touch(x, y, button, player)
    for i = #self.hits, 1, -1 do
        local h = self.hits[i]
        if x >= h.x1 and x <= h.x2 and y >= h.y1 and y <= h.y2 then
            -- сначала показать нажатие (действие может занять несколько тиков: каждый вызов реактора = тик),
            -- потом выполнить, и только после этого отсчитывать время "отжатия"
            if h.id then
                self.pressed[h.id] = math.huge
                self:frame(true)
            end
            if h.fn then h.fn(x, y, player) end
            if h.id then self.pressed[h.id] = self:clock() + UI.PRESS_TIME end
            self:invalidate()
            return true
        end
    end
    return false
end

function UI:key(char, code, player)
    if self.modal and self.modal.key then
        self.modal.key(self, char, code, player)
        self:invalidate()
    end
end

function UI:scroll(x, y, dir, player)
    if self.modal and self.modal.scroll then
        self.modal.scroll(self, x, y, dir)
        self:invalidate()
    end
end

-- Подключение к приложению: события и кадры в общем цикле
function UI:attach()
    local app = self.app
    app:on("touch", function(_, _, x, y, button, player) self:touch(x, y, button, player) end)
    app:on("key_down", function(_, _, char, code, player) self:key(char, code, player) end)
    app:on("scroll", function(_, _, x, y, dir, player) self:scroll(x, y, dir, player) end)
    app.onFrame = function() self:frame() end
    app.waitHint = function() return self:timeUntilNext() end
end

return UI
