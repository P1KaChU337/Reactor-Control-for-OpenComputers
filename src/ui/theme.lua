-- Цвета тем. Значения взяты из v1.1.3 (switchTheme), опечатка 0x3f3f3ff исправлена на то,
-- что реально показывал GPU (берёт младшие 24 бита): 0xf3f3ff.
local M = {}

M.dark = {
    name = "dark",
    image = "dark.pic",
    bg = 0x202020,       -- панели и виджеты
    bg2 = 0x101010,      -- нижние линии панелей
    bg3 = 0x3c3c3c,      -- фон под кнопками
    bg4 = 0x969696,      -- поле с виджетами
    text = 0xcccccc,
    textBtn = 0xffffff,
    btn = 0x059bff,      -- обычная кнопка
    btnPressed = 0x38afff,
    version = 0x666666,
    info = 0x61ff52,
    warn = 0xfff700,
    error = 0xff0000,
    title = 0x72f8ff,
}

M.light = {
    name = "light",
    image = "light.pic",
    bg = 0x000000,
    bg2 = 0x202020,
    bg3 = 0xffffff,
    bg4 = 0x5a5a5a,
    text = 0xf3f3ff,
    textBtn = 0x303030,
    btn = 0x059bff,
    btnPressed = 0x38afff,
    version = 0xc3c3c3,
    info = 0x61ff52,
    warn = 0xfff700,
    error = 0xff0000,
    title = 0x72f8ff,
}

-- общие цвета
M.red = 0xfd3232
M.redPressed = 0xfb3737
M.green = 0x2beb1a
M.greenBig = 0x35e525
M.greenPressed = 0x61ff52
M.purple = 0xa91df9
M.purpleDark = 0x8100cc
M.modal = 0xcccccc
M.coolantBottom = 0x0044ff
M.coolantTop = 0x00c8ff

function M.get(name) return name == "light" and M.light or M.dark end

return M
