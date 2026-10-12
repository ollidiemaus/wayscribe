local T = require("testlib")
local Stubs = require("wow_stubs")
local describe, it = T.describe, T.it

local function start(devMode, opts)
    opts = opts or {}
    opts.accountDB = { schema = 1, settings = { trackers = {}, devMode = devMode or nil }, log = {}, characters = {} }
    local ns = Stubs.LoadAddon(opts)
    Stubs.Login()
    return ns
end

local function traced(ns)
    return ns.accountDB.duelTrace or {}
end

-- The lines without their time stamp.
local function texts(ns)
    local list = {}
    for i, line in ipairs(traced(ns)) do
        list[i] = line:gsub("^%d%d:%d%d:%d%d%.%d%d%d ", "")
    end
    return list
end

local function find(ns, prefix)
    for _, text in ipairs(texts(ns)) do
        if text:sub(1, #prefix) == prefix then return text end
    end
end

describe("duel trace", function()
    it("logs a duel from the challenge to the winner's line, and which name is the player's", function()
        local ns = start(true)
        Stubs.Fire("DUEL_REQUESTED", "Bo")
        Stubs.Fire("CHAT_MSG_SYSTEM", "Bo has defeated Tester in a duel", "", "", "", "", "", "", 0, 0, "", 0, 0, nil, false, false)
        Stubs.Fire("DUEL_FINISHED")
        T.truthy(find(ns, "--- duel window opens"))
        T.eq(find(ns, "DUEL_REQUESTED"), 'DUEL_REQUESTED("Bo")')
        T.truthy(find(ns, "  not found"))
        T.eq(find(ns, "DUEL_WINNER_RETREAT"), 'DUEL_WINNER_RETREAT = "%2$s has fled from %1$s in a duel"')
        T.eq(find(ns, "CHAT_MSG_SYSTEM"), 'CHAT_MSG_SYSTEM(1="Bo has defeated Tester in a duel") -> DUEL_WINNER_KNOCKOUT'
            .. ' winner="Bo" (me: nil) loser="Tester" (me: GetUnitName/UnitName)')
        T.truthy(find(ns, "DUEL_FINISHED() health=missing"))
        T.truthy(#Stubs.Printed() >= #traced(ns))
        T.eq(#ns.Log:GetEntries(), 0)
    end)

    it("matches the player's name with the surname", function()
        local ns = start(true, { name = "Tester", surname = "Ashford" })
        Stubs.Fire("CHAT_MSG_SYSTEM", "Tester Ashford has fled from Bo in a duel")
        T.eq(find(ns, "CHAT_MSG_SYSTEM"), 'CHAT_MSG_SYSTEM(1="Tester Ashford has fled from Bo in a duel") -> DUEL_WINNER_RETREAT'
            .. ' winner="Bo" (me: nil) loser="Tester Ashford" (me: GetUnitName/UnitName+space)')
    end)

    it("keeps other system lines only around a duel, secret ones too", function()
        local ns = start(true)
        Stubs.Fire("CHAT_MSG_SYSTEM", "You are now away.")
        Stubs.Fire("CHAT_MSG_SYSTEM", Stubs.SECRET)
        T.eq(#traced(ns), 0)
        _G.StartDuel("target", true)
        T.eq(find(ns, "StartDuel"), 'StartDuel("target", true)')
        Stubs.Fire("CHAT_MSG_SYSTEM", Stubs.SECRET)
        T.eq(find(ns, "CHAT_MSG_SYSTEM"), "CHAT_MSG_SYSTEM(1=<secret>)")
        Stubs.Fire("DUEL_FINISHED")
        Stubs.Advance(11)
        local count = #traced(ns)
        Stubs.Fire("CHAT_MSG_SYSTEM", "You are now away.")
        T.eq(#traced(ns), count)
    end)

    it("records nothing outside developer mode, and follows /ws dev", function()
        local ns = start(false)
        Stubs.Fire("DUEL_REQUESTED", "Bo")
        _G.StartDuel("target")
        T.eq(#traced(ns), 0)
        ns.Slash:Handle("dev")
        Stubs.Fire("DUEL_REQUESTED", "Bo")
        T.truthy(find(ns, "DUEL_REQUESTED"))
        ns.Slash:Handle("dev")
        local count = #traced(ns)
        Stubs.Fire("DUEL_FINISHED")
        T.eq(#traced(ns), count)
    end)

    it("keeps the last 200 lines; /ws duellog shows the newest and clears", function()
        local ns = start(true)
        for i = 1, 210 do
            Stubs.Fire("DUEL_OUTOFBOUNDS", i)
        end
        local lines = traced(ns)
        T.eq(#lines, 200)
        T.truthy(lines[200]:find("DUEL_OUTOFBOUNDS%(210%)$"))
        local before = #Stubs.Printed()
        ns.Slash:Handle("duellog")
        T.eq(#Stubs.Printed() - before, 20)
        ns.Slash:Handle("duellog clear")
        T.eq(ns.accountDB.duelTrace, nil)
    end)
end)
