package.preload.unicode = package.preload.unicode or function() return {char = utf8.char, len = utf8.len} end
local chat = require("commands.chat")
local State = require("core.state")
local Log = require("core.log")
local Actions = require("core.actions")
local config = require("core.config")
local T = T

local function makeApp()
    local c = T.clock(0)
    local app = {clock = c.fn, cfg = config.defaults(), log = Log.new({clock = c.fn}), state = State.new(c.fn),
        proxies = {reactors = {}}, saveConfig = function() end, VERSION = "2.0.0-dev", handlers = {}}
    app.cfg.users = {"Boss"}
    app.said = {}
    app.proxies.chat = {say = function(t) app.said[#app.said + 1] = t end, setName = function() end}
    for i = 1, 2 do
        local r = app.state:newReactor(i, "a" .. i)
        r.kind = i == 1 and "fluid" or "air"
        r.coolant, r.coolantMax, r.consumeNominal = 900000, 1080000, 967
        app.proxies.reactors[i] = {activate = function() return true end, deactivate = function() return true end}
    end
    app.state.me.present = true
    app.state.me.amount = 10000000
    app.actions = Actions.new(app)
    function app:requestExit() self.exited = true end
    function app:requestRestart() self.restarted = true end
    return app
end

local function saidHas(app, pat)
    for _, l in ipairs(app.said) do if l:find(pat, 1, true) then return true end end
    return false
end

T.test("чат: чужой игрок не управляет", function()
    local app = makeApp()
    T.ok(chat.handle(app, "Stranger", "@start"))
    T.no(app.state.reactors[1].running)
    T.ok(saidHas(app, "нет прав"))
end)

T.test("чат: @start / @stop / @start 2 отвечают тем же, что в журнале", function()
    local app = makeApp()
    chat.handle(app, "Boss", "@start")
    T.ok(app.state.reactors[1].running and app.state.reactors[2].running)
    T.ok(saidHas(app, "Реактор #1 (жидкостный) запущен!"))
    app.said = {}
    chat.handle(app, "Boss", "§a@stop 2")
    T.no(app.state.reactors[2].running); T.ok(app.state.reactors[1].running)
    chat.handle(app, "Boss", "@stop 9")
    T.ok(saidHas(app, "Неверный номер"))
end)

T.test("чат: @status, @help, @setporog, @useradd, @exit", function()
    local app = makeApp()
    chat.handle(app, "Boss", "@status"); T.ok(saidHas(app, "Статус комплекса")); T.ok(saidHas(app, "#2"))
    chat.handle(app, "Boss", "@HELP"); T.ok(saidHas(app, "Команды"))
    chat.handle(app, "Boss", "@setporog 123456"); T.eq(app.cfg.threshold, 123456)
    chat.handle(app, "Boss", "@useradd Friend"); T.eq(app.cfg.users[2], "Friend")
    chat.handle(app, "Boss", "@exit"); T.ok(app.exited)
    T.no(chat.handle(app, "Boss", "просто сообщение"))
end)
