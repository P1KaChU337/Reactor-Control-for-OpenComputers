local remote = require("net.remote")
local Http = require("net.http")
local T = T

T.test("remote: changelog.lua из репозитория разбирается без исполнения кода", function()
    local text = io.open("changelog.lua"):read("a")
    local list = remote.parseChangelog(text)
    T.ok(list and #list >= 3, "версий: " .. tostring(list and #list))
    T.eq(list[1].version, "1.0"); T.ok(#list[1].changes > 0)
    T.no(remote.parseChangelog("return os.execute('rm -rf /')"))
    T.no(remote.parseChangelog("мусор"))
end)

T.test("remote: сравнение версий", function()
    T.ok(remote.isNewer("2.0.1", "2.0.0-dev")); T.ok(remote.isNewer("2.0.0", "2.0.0-dev"))
    T.no(remote.isNewer("2.0.0-dev", "2.0.0-dev")); T.no(remote.isNewer("1.1.3", "2.0.0-dev"))
    T.ok(remote.isNewer("2.1", "2.0.9")); T.no(remote.isNewer("2.0.0", "2.0.0"))
end)

T.test("remote: about_v2.txt — текст без комментариев", function()
    local lines = remote.parseAbout(io.open("about_v2.txt"):read("a"))
    T.ok(lines and #lines > 5)
    T.no(lines[1]:match("^#")); T.eq(lines[1], "Автор программы: P1KaChU337")
    local found = false
    for _, l in ipairs(lines) do if l:find("Спасибо за поддержку") then found = true end end
    T.ok(found, "есть благодарности")
    T.no(remote.parseAbout("# только комментарий\n\n"))
    T.eq(#remote.parseAbout("a\r\n\r\nb"), 3)
end)

T.test("http: запрос по шагам, ответ и ошибки", function()
    local c = T.clock(0)
    local reads = {"he", "", "llo", nil}
    local idx = 0
    local comp = {isAvailable = function() return true end, internet = {request = function(url)
        if url == "bad" then error("unknown host") end
        local connected = false
        return {
            finishConnect = function() local r = connected connected = true return r end,
            response = function() return url == "404" and 404 or 200 end,
            read = function() idx = idx + 1 return reads[idx] end,
            close = function() end,
        }
    end}}
    local h = Http.new(comp, c.fn)
    local got, okGot, err404, errBad
    h:get("ok", function(ok, d) okGot, got = ok, d end)
    h:get("404", function(ok, d) err404 = d end)
    h:get("bad", function(ok, d) errBad = d end)
    for _ = 1, 10 do c.t = c.t + 0.25 h:step() end
    T.ok(okGot); T.eq(got, "hello"); T.eq(err404, "HTTP 404"); T.ok(errBad and errBad:find("unknown host"))
    T.no(h:busy())
end)

T.test("http: таймаут", function()
    local c = T.clock(0)
    local comp = {isAvailable = function() return true end, internet = {request = function()
        return {finishConnect = function() return false end, close = function() end}
    end}}
    local h = Http.new(comp, c.fn)
    local err
    h:get("x", function(ok, d) err = d end, 5)
    for _ = 1, 30 do c.t = c.t + 0.25 h:step() end
    T.eq(err, "таймаут")
end)

T.test("remote: changelog_v2.lua разбирается, в окно обновления идут только версии новее текущей", function()
    local list = remote.parseChangelog(io.open("changelog_v2.lua"):read("a"))
    T.ok(list and #list >= 1); T.eq(list[1].version, "2.0.0")
    local all = {{version = "2.0.0-dev", changes = {"a"}}, {version = "2.0.0", changes = {"b"}},
        {version = "2.0.1", changes = {"c"}}, {version = "2.1.0", changes = {"d"}}}
    local notes = remote.notesBetween(all, "2.0.0-dev", "2.0.1")
    T.eq(#notes, 2); T.eq(notes[1].version, "2.0.1"); T.eq(notes[2].version, "2.0.0")
end)
