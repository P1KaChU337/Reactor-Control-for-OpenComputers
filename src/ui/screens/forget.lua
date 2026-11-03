-- Подтверждение «Забыть реактор»: для реакторов без связи (взорвался, разобран, сломан адаптер).
local G = require("ui.gfx")
local T = require("ui.theme")

local M = {slot = nil}

local X, Y, W, H = 42, 15, 76, 17

function M.draw(ui)
    local app, slot = ui.app, M.slot
    local r = slot and app.state.reactors[slot]
    if not r or r.online then ui:closeModal() return end
    G.box(X - 1, Y, W + 2, H, T.modal)
    ui:hit(1, 1, 160, 50, function() ui:closeModal() end)
    ui:hit(X - 1, Y, X + W, Y + H - 1, function() end)
    G.center(X, W, 0x000000, "Забыть реактор #" .. slot .. "?", Y + 1)
    G.text(X + 3, Y + 3, 0x333333, "Используйте, если реактора больше нет: взорвался, разобран или заменён.")
    G.text(X + 3, Y + 4, 0x333333, "Адрес: " .. tostring(r.address))
    G.text(X + 3, Y + 6, 0x000000, "«Забыть» — номера остальных реакторов не меняются,")
    G.text(X + 3, Y + 7, 0x000000, "   новый реактор займёт номер #" .. slot .. ".")
    G.text(X + 3, Y + 8, 0x000000, "«Забыть и перенумеровать» — остальные сдвинутся по порядку")
    G.text(X + 3, Y + 9, 0x000000, "   (#2 станет #1 и т.д.), пустого места не останется.")
    G.text(X + 3, Y + H - 1, 0x999999, "Нажмите вне окна, чтобы отменить")
    local function run(renumber)
        local ok, err = app.actions:forget(slot, renumber)
        if not ok then app.log:warn(err) end
        ui:closeModal()
    end
    ui:button("fgOnly", X + 4, Y + H - 5, 18, "Забыть", 0x666666, 0xffffff, function() run(false) end)
    ui:button("fgRenum", X + 25, Y + H - 5, 28, "Забыть и перенумеровать", T.purpleDark, 0xffffff, function() run(true) end)
    ui:button("fgCancel", X + W - 16, Y + H - 5, 12, "Отмена", 0x999999, 0xffffff, function() ui:closeModal() end)
end

return M
