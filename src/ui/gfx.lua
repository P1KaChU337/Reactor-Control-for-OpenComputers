-- Графические примитивы поверх doubleBuffering. Внешне повторяют v1.1.3, но ничего не ждут (без os.sleep)
-- и ничего не знают о логике программы.
local unicode = require("unicode")
local braille = require("ui.braille")
local S = require("ui.sprites")

local G = {}
local buffer

function G.init(buf) buffer = buf G.buffer = buf end

local function wlen(s) return unicode.wlen and unicode.wlen(s) or unicode.len(s) end
G.wlen = wlen

-- Текст с учётом широких символов (🔧, ⓘ, ⚠ занимают 2 колонки).
-- doubleBuffering считает любой символ за 1 ячейку, а GPU сдвигает всё после широкого символа.
-- Поэтому после широкого символа в буфер кладётся пустая строка: GPU получит ровно то, что нужно.
function G.text(x, y, color, s)
    s = tostring(s)
    if not unicode.isWide or wlen(s) == unicode.len(s) then
        buffer.drawText(x, y, color, s)
        return
    end
    for i = 1, unicode.len(s) do
        local ch = unicode.sub(s, i, i)
        buffer.drawText(x, y, color, ch)
        if unicode.isWide(ch) then
            local bg, fg = buffer.get(x + 1, y)
            if bg then buffer.set(x + 1, y, bg, color, "") end
            x = x + 2
        else
            x = x + 1
        end
    end
end

-- Обрезать по ширине с "..."
function G.fit(s, width)
    s = tostring(s)
    if wlen(s) <= width then return s end
    local out, w = {}, 0
    for i = 1, unicode.len(s) do
        local ch = unicode.sub(s, i, i)
        local cw = (unicode.isWide and unicode.isWide(ch)) and 2 or 1
        if w + cw > width - 3 then break end
        out[#out + 1] = ch
        w = w + cw
    end
    return table.concat(out) .. "..."
end

function G.center(x, width, color, s, y)
    s = G.fit(s, width)
    G.text(x + math.floor((width - wlen(s)) / 2), y, color, s)
end

function G.rect(x, y, w, h, color)
    if w > 0 and h > 0 then buffer.drawRectangle(x, y, w, h, color, 0, " ") end
end

-- Затемнить весь экран (под модальным окном)
function G.dim(alpha)
    local W, H = buffer.getResolution()
    buffer.drawRectangle(1, 1, W, H, 0x000000, 0, " ", alpha or 0.4)
end

-- Скруглённый блок, как виджеты и окна v1.1.3: углы — брайль цвета блока на фоне родителя
function G.box(x, y, w, h, color)
    buffer.drawRectangle(x + 1, y, w - 2, h, color, 0, " ")
    buffer.drawRectangle(x, y + 1, w, h - 2, color, 0, " ")
    buffer.drawText(x, y, color, S.corner[1])
    buffer.drawText(x + w - 1, y, color, S.corner[2])
    buffer.drawText(x + w - 1, y + h - 1, color, S.corner[3])
    buffer.drawText(x, y + h - 1, color, S.corner[4])
end

-- Горизонтальная брайль-линия из одинаковых ячеек
function G.hline(x, y, w, ch, color) braille.line(buffer, x, y, w, ch, color) end

-- Кнопка v1.1.3 (animatedButton): занимает x-1..x+len, y..y+2, текст по центру строки y+1.
-- -> x1, y1, x2, y2 для попаданий
function G.button(x, y, len, text, color, textColor, pressed)
    local b = pressed and S.buttonPushed or S.button
    buffer.drawRectangle(x, y + 1, len, 1, color, 0, " ")
    G.center(x, len, textColor, text, y + 1)
    buffer.drawText(x - 1, y, color, b[4])
    buffer.drawText(x - 1, y + 1, color, b[3])
    buffer.drawText(x - 1, y + 2, color, b[5])
    buffer.drawText(x + len, y, color, b[2])
    buffer.drawText(x + len, y + 1, color, b[3])
    buffer.drawText(x + len, y + 2, color, b[6])
    G.hline(x, y, len, b[1], color)
    G.hline(x, y + 2, len, b[7], color)
    return x - 1, y, x + len, y + 2
end

-- Число брайль-цифрами (2x2 ячейки на цифру, точка — 1 ячейка) по центру cx, плюс подпись справа сверху
function G.number(cx, y, value, color, suffix, suffixColor)
    local str = tostring(value)
    local glyphs, width = {}, 0
    for i = 1, #str do
        local ch = str:sub(i, i)
        local img = S.digits[ch]
        if img then
            local w = ch == "." and 1 or 2
            glyphs[#glyphs + 1] = {img = img, w = w}
            width = width + w
        end
    end
    local sw = suffix and #suffix > 0 and (unicode.len(suffix) + 1) or 0
    local x = math.floor(cx - (width + sw) / 2)
    for _, g in ipairs(glyphs) do
        if g.w == 1 then
            buffer.drawText(x, y, color, g.img[1][1])
            buffer.drawText(x, y + 1, color, g.img[2][1])
        else
            braille.draw(buffer, x, y, g.img, color)
        end
        x = x + g.w
    end
    if sw > 0 then buffer.drawText(x, y, suffixColor or color, suffix) end
end

-- Значок 2x2 ячейки
function G.icon(x, y, img, color) braille.draw(buffer, x, y, img, color) end

local function lerp(c1, c2, t)
    local r1, g1, b1 = math.floor(c1 / 65536) % 256, math.floor(c1 / 256) % 256, c1 % 256
    local r2, g2, b2 = math.floor(c2 / 65536) % 256, math.floor(c2 / 256) % 256, c2 % 256
    return math.floor(r1 + (r2 - r1) * t) * 65536 + math.floor(g1 + (g2 - g1) * t) * 256 + math.floor(b1 + (b2 - b1) * t)
end
G.lerp = lerp

-- Вертикальная полоса (буфер хладагента): 4 деления на ячейку, градиент снизу вверх
function G.vbar(x, y, h, value, max, cBottom, cTop, inactive)
    if not max or max <= 0 then max = 1 end
    value = math.max(0, math.min(tonumber(value) or 0, max))
    local parts = math.floor(h * 4 * value / max)
    buffer.drawRectangle(x, y, 1, h, inactive, 0, " ")
    local full, rem = math.floor(parts / 4), parts % 4
    for i = 0, full - 1 do
        buffer.drawText(x, y + h - i - 1, lerp(cBottom, cTop, (i + 1) / h), S.vbar[4])
    end
    if rem > 0 then
        buffer.drawText(x, y + h - full - 1, lerp(cBottom, cTop, (full + 1) / h), S.vbar[rem])
    end
end

-- Переключатель v1.1.3 (◖███◗): w ячеек
function G.switch(x, y, w, on, activeColor, passiveColor, pipeColor, bgColor)
    activeColor, passiveColor = activeColor or 0x0088ff, passiveColor or 0x777777
    pipeColor, bgColor = pipeColor or 0xffffff, bgColor or 0x444444
    local pos = on and (w - 2) or 1
    buffer.drawRectangle(x, y, w, 1, bgColor, 0, " ")
    if pos > 1 then buffer.drawText(x, y, activeColor, "◖") end
    if pos < w - 1 then buffer.drawText(x + w - 1, y, passiveColor, "◗") end
    if pos - 1 > 0 then buffer.drawRectangle(x + 1, y, pos - 1, 1, activeColor, 0, " ") end
    if w - pos - 1 > 0 then buffer.drawRectangle(x + pos, y, w - pos - 1, 1, passiveColor, 0, " ") end
    buffer.drawText(x + pos - 1, y, pipeColor, "◖")
    buffer.set(x + pos, y, pipeColor, pipeColor, " ")
    buffer.drawText(x + pos + 1, y, pipeColor, "◗")
end

-- Поле ввода v1.1.3: строка y, рамка y-1..y+1
function G.field(x, y, w, text, placeholder, active, cursorOn, color, bgColor, placeholderColor)
    color, bgColor = color or 0x444444, bgColor or 0xcccccc
    buffer.drawRectangle(x, y, w, 1, color, bgColor, " ")
    buffer.drawRectangle(x + 1, y - 1, w - 2, 1, color, bgColor, S.field[6])
    buffer.drawRectangle(x + 1, y + 1, w - 2, 1, color, bgColor, S.field[5])
    buffer.drawText(x, y - 1, color, S.field[1])
    buffer.drawText(x, y + 1, color, S.field[4])
    buffer.drawText(x + w - 1, y - 1, color, S.field[2])
    buffer.drawText(x + w - 1, y + 1, color, S.field[3])
    local maxVisible = w - 2
    if active then
        local visible = text
        if unicode.len(visible) > maxVisible - 1 then visible = unicode.sub(visible, -(maxVisible - 1)) end
        buffer.drawText(x + 1, y, 0xffffff, visible .. (cursorOn and "|" or ""))
    elseif text == "" then
        G.center(x, w, placeholderColor or 0xececec, placeholder or "", y)
    else
        G.center(x + 1, maxVisible, placeholderColor or 0xececec, text, y)
    end
end

return G
