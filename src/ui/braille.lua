-- Брайль-графика: ячейка 2x4 точки, точки — цветом текста, остальное — цветом фона.
-- Спрайты задаются ASCII-артом: '#' (или любой символ кроме '.' и ' ') — точка, '.' — фон.
local unicode = require("unicode")

local M = {}

-- Бит каждой точки в символе U+2800 (строка r 0..3, колонка c 0..1)
local BIT = {
    [0] = {[0] = 0x01, [1] = 0x08},
    [1] = {[0] = 0x02, [1] = 0x10},
    [2] = {[0] = 0x04, [1] = 0x20},
    [3] = {[0] = 0x40, [1] = 0x80},
}

-- Все 256 символов считаются один раз
local GLYPH = {}
for m = 0, 255 do GLYPH[m] = unicode.char(0x2800 + m) end
M.GLYPH = GLYPH

function M.char(mask) return GLYPH[mask] end

local function isDot(ch) return ch ~= "." and ch ~= " " and ch ~= "" end

-- Картинка из ASCII-арта -> {w = ячеек, h = ячеек, [row][col] = символ}. Размеры добиваются до кратных 2x4.
function M.image(rows)
    local pw = 0
    for _, r in ipairs(rows) do if #r > pw then pw = #r end end
    local cw, ch = math.ceil(pw / 2), math.ceil(#rows / 4)
    local img = {w = cw, h = ch}
    for cy = 1, ch do
        img[cy] = {}
        for cx = 1, cw do
            local mask = 0
            for r = 0, 3 do
                local line = rows[(cy - 1) * 4 + r + 1] or ""
                for c = 0, 1 do
                    local px = (cx - 1) * 2 + c + 1
                    if isDot(line:sub(px, px)) then mask = mask + BIT[r][c] end
                end
            end
            img[cy][cx] = GLYPH[mask]
        end
    end
    return img
end

-- Одна ячейка из 4 строк по 2 символа -> символ
function M.cell(rows) return M.image(rows)[1][1] end

-- Набор отдельных ячеек: {{"..","##","..",".."}, ...} -> {символ, ...}
function M.set(list)
    local res = {}
    for i, rows in ipairs(list) do res[i] = M.cell(rows) end
    return res
end

-- Нарисовать картинку: точки цветом fg, фон под картинкой не трогается
function M.draw(buffer, x, y, img, fg)
    for cy = 1, img.h do
        local row = img[cy]
        for cx = 1, img.w do buffer.drawText(x + cx - 1, y + cy - 1, fg, row[cx]) end
    end
end

-- Строка из одинаковых ячеек
function M.line(buffer, x, y, n, ch, fg)
    if n > 0 then buffer.drawText(x, y, fg, string.rep(ch, n)) end
end

-- Совместимость со старым форматом: dots[1..8] = (r1c1, r1c2, r2c1, r2c2, r3c1, r3c2, r4c1, r4c2)
function M.fromDots(d)
    local mask = 0
    for r = 0, 3 do
        for c = 0, 1 do
            if (d[r * 2 + c + 1] or 0) == 1 then mask = mask + BIT[r][c] end
        end
    end
    return GLYPH[mask]
end

return M
