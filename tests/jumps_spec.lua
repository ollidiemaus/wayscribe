local T = require("testlib")
local Stubs = require("wow_stubs")
local describe, it = T.describe, T.it

-- opts.only = "Jumps" switches every other tracker off.
local function start(opts)
    if opts and opts.only then
        opts.accountDB = opts.accountDB or { schema = 1, log = {}, characters = {}, settings = {} }
    end
    local ns = Stubs.LoadAddon(opts)
    Stubs.Login()
    return ns
end

local function at(month, day, hour, min, sec)
    return os.time({ year = 2026, month = month, day = day, hour = hour or 12, min = min or 0, sec = sec or 0 })
end

-- The year's jumps card, or nil.
local function card(ns, year)
    for _, built in ipairs(ns.YearCards:Build(year or 2026)) do
        if built.id == "jumps" then return built end
    end
end

-- The jumps saved for a day, today by default.
local function jumps(ns, dayKey)
    local day = ns.Store:GetDay(dayKey or ns.Time.DayKey(Stubs.Now()))
    local bucket = day and day.counters.jumps
    return bucket and bucket.count or 0
end

describe("jumps", function()
    it("count ground jumps, written once a minute and not on each press", function()
        local ns = start()
        Stubs.Jump(3)
        T.eq(jumps(ns), 0, "nothing is written on a press")
        Stubs.Advance(60)
        T.eq(jumps(ns), 3)
        Stubs.Jump()
        Stubs.Advance(59)
        T.eq(jumps(ns), 3)
        Stubs.Advance(1)
        T.eq(jumps(ns), 4)
        T.eq(#ns.Log:GetEntries(), 0)
    end)

    it("show nothing on the day page, so a day of only jumps stays out of the journal and the export", function()
        local ns = start({ only = "Jumps" })
        Stubs.Jump(5)
        Stubs.Advance(60)
        local dayKey = ns.Time.DayKey(Stubs.Now())
        T.eq(jumps(ns), 5)
        T.same(ns.RecordTypes:RenderCounters(ns.Store:GetDay(dayKey).counters), {})
        T.falsy(ns.DayView.HasVisible(dayKey, function() return true end), "no day in the journal's list")
        local _, days = ns.Export.BuildText("all")
        T.eq(days, 0, "no day in the export")
        for _, category in ipairs(ns.RecordTypes:Categories()) do
            T.truthy(category ~= "misc", "no filter category")
        end
    end)

    it("leave a journal of only jumps empty, not filtered", function()
        local ns = Stubs.LoadAddon({ accountDB = { schema = 1, log = {}, characters = {}, settings = {} }, only = "Jumps" })
        Stubs.InstallScrollBox()
        Stubs.Login()
        Stubs.Jump()
        Stubs.Advance(60)
        ns.Journal:Toggle()
        T.same(Stubs.Texts(ns.DayView.ui.content), { "Your journal is still empty. Go on an adventure!" })
    end)

    it("skip a press in mid-air, in water, flying, on a flight path or in a vehicle", function()
        local ns = start()
        Stubs.Jump()
        for _, set in ipairs({ Stubs.SetFalling, Stubs.SetSwimming, Stubs.SetFlying, Stubs.SetTaxi, Stubs.SetVehicle }) do
            set(true)
            Stubs.Jump(4)
            set(false)
        end
        Stubs.Jump()
        Stubs.Advance(60)
        T.eq(jumps(ns), 2)
    end)

    it("count jumps on a ground mount, shapeshifted and as a ghost", function()
        local ns = start()
        Stubs.SetMounted(true)
        Stubs.Jump(2)
        Stubs.SetMounted(false)
        Stubs.Jump() -- Cat form, Bear form and Ghost Wolf are no mount, no vehicle and no flight
        Stubs.SetDead(true)
        Stubs.Jump(3)
        Stubs.Advance(60)
        T.eq(jumps(ns), 6)
    end)

    it("take a secret or missing state as not so", function()
        local ns = start()
        Stubs.SetFalling(Stubs.SECRET)
        Stubs.SetSwimming(Stubs.SECRET)
        Stubs.Jump()
        _G.IsFlying, _G.UnitInVehicle = nil, nil
        Stubs.Jump()
        _G.IsFalling = function() error("not now") end
        Stubs.Jump()
        Stubs.Advance(60)
        T.eq(jumps(ns), 3)
        T.eq(#ns.Log:GetEntries(), 0)
    end)

    it("write a day's jumps on that day, also in the minute around midnight", function()
        local ns = start({ now = os.time({ year = 2026, month = 10, day = 3, hour = 23, min = 59, sec = 30 }) })
        Stubs.Jump(2)
        Stubs.Advance(29)
        Stubs.Jump(3)
        Stubs.Advance(1) -- midnight
        Stubs.Jump(4)
        Stubs.Advance(60)
        T.eq(jumps(ns, 20261003), 5)
        T.eq(jumps(ns, 20261004), 4)
    end)

    it("keep the jumps not yet written over a logout and a reload", function()
        start()
        Stubs.Jump(3)
        local ns = Stubs.Relog(nil, true)
        T.eq(jumps(ns), 3, "a reload")
        Stubs.Jump(2)
        ns = Stubs.Relog()
        T.eq(jumps(ns), 5, "a logout")
    end)

    it("write nothing for a minute without a jump", function()
        start({ only = "Jumps" })
        Stubs.Advance(600)
        local ns = Stubs.Relog()
        T.eq(ns.Store:GetDay(ns.Time.DayKey(Stubs.Now())), nil)
    end)

    it("count nothing while switched off, write what was pressed before, and resume when switched on", function()
        local ns = start()
        Stubs.Jump(2)
        ns.Trackers:SetWanted("Jumps", false)
        T.eq(jumps(ns), 2, "written when switched off")
        Stubs.Jump(5)
        Stubs.Advance(60)
        T.eq(jumps(ns), 2)
        ns.Trackers:SetWanted("Jumps", true)
        Stubs.Jump()
        Stubs.Advance(60)
        T.eq(jumps(ns), 3)
        ns.Trackers:SetWanted("Jumps", false)
        ns.Trackers:SetWanted("Jumps", true)
        Stubs.Jump()
        Stubs.Advance(60)
        T.eq(jumps(ns), 4, "hooked once")
    end)

    it("stay silent without JumpOrAscendStart or hooksecurefunc", function()
        for _, missing in ipairs({ "JumpOrAscendStart", "hooksecurefunc" }) do
            local ns = Stubs.LoadAddon()
            _G[missing] = nil
            Stubs.Login()
            Stubs.Advance(120)
            T.truthy(ns.Trackers:Get("Jumps").enabled, missing)
            T.eq(#ns.Log:GetEntries(), 0, missing)
        end
    end)

    it("give Your Year a card with the total, the best day and the average per day played", function()
        start()                                 -- Oct 3
        Stubs.Jump(10)
        Stubs.Advance(60)
        Stubs.Jump(20)
        Stubs.Advance(60)
        Stubs.Relog({ now = at(10, 4) })        -- as many, so Oct 3 stays the best day
        Stubs.Jump(30)
        Stubs.Advance(60)
        Stubs.Relog({ now = at(10, 5) })        -- played without a jump
        Stubs.Advance(60)
        local ns = Stubs.Relog({ now = at(11, 2) }) -- as many in a later month
        Stubs.Jump(30)
        Stubs.Advance(60)
        local jumpsCard = card(ns)
        T.eq(jumpsCard.title, "Jumps")
        T.eq(jumpsCard.big, "90")
        T.eq(jumpsCard.caption, "jumps")
        T.same(jumpsCard.lines, { "Bounciest day: Saturday, October 3, 2026 (30 jumps)",
            "Average: 23 jumps per day played" }, "90 jumps on 4 days played")
        local order = {}
        for i, def in ipairs(ns.YearCards.list) do order[def.id] = i end
        T.truthy(order.footsteps < order.jumps and order.jumps < order.gold, "after Footsteps, before Gold")
        ns.Store:Rebuild()
        T.same(card(ns).lines[1], "Bounciest day: Saturday, October 3, 2026 (30 jumps)",
            "the best day comes back from the counters")
    end)

    it("show no card in a year without jumps", function()
        local ns = start()
        Stubs.Advance(600)
        T.eq(card(ns), nil)
    end)

    it("read naturally for one jump, and leave out an average under one", function()
        local ns = start()
        Stubs.Jump()
        Stubs.Advance(60)
        local jumpsCard = card(ns)
        T.eq(jumpsCard.big, "1")
        T.eq(jumpsCard.caption, "jump")
        T.same(jumpsCard.lines, { "Bounciest day: Saturday, October 3, 2026 (1 jump)", "Average: 1 jump per day played" })
        Stubs.Relog({ now = at(10, 4) })
        Stubs.Advance(60)
        ns = Stubs.Relog({ now = at(10, 5) })
        Stubs.Advance(60)
        T.same(card(ns).lines, { "Bounciest day: Saturday, October 3, 2026 (1 jump)" }, "1 jump on 3 days played")
    end)

    it("start a new year at zero", function()
        local ns = start({ now = os.time({ year = 2026, month = 12, day = 31, hour = 23, min = 59, sec = 50 }) })
        Stubs.Jump(2)
        Stubs.Advance(10)
        Stubs.Jump(3)
        Stubs.Advance(60)
        T.eq(card(ns, 2026).big, "2")
        T.eq(card(ns, 2027).big, "3")
    end)

    it("trace each flush with a press in developer mode, counted and skipped by reason", function()
        local accountDB = { schema = 1, log = {}, characters = {}, settings = { devMode = true } }
        local ns = start({ accountDB = accountDB, only = "Jumps", now = at(10, 3, 23, 58, 30) })
        Stubs.Jump(3)
        Stubs.SetFalling(true)
        Stubs.Jump(2)
        Stubs.SetFalling(false)
        Stubs.SetTaxi(true)
        Stubs.Jump()
        Stubs.SetTaxi(false)
        Stubs.Advance(60)
        Stubs.SetSwimming(true)
        Stubs.Jump(4)
        Stubs.SetSwimming(false)
        Stubs.Advance(30) -- midnight
        Stubs.Advance(60) -- a minute without a press
        Stubs.Jump()
        Stubs.SetFlying(true)
        Stubs.Jump()
        Stubs.SetFlying(false)
        Stubs.SetVehicle(true)
        Stubs.Jump()
        Stubs.SetVehicle(false)
        ns.Trackers:SetWanted("Jumps", false)
        ns.Trackers:SetWanted("Jumps", true)
        Stubs.Jump(2)
        ns = Stubs.Relog()
        local traced = {}
        for i, line in ipairs(ns.Trace:GetLines()) do traced[i] = line:gsub("^%S+ %S+ ", "") end
        T.same(traced, {
            "Jumps minute: counted=3 skipped=3 falling=2 taxi=1 -> written",
            "Jumps midnight: counted=0 skipped=4 swimming=4 -> none counted",
            "Jumps disable: counted=1 skipped=2 flying=1 vehicle=1 -> written",
            "Jumps PLAYER_LOGOUT: counted=2 skipped=0 -> written",
        })
    end)

    it("make no garbage on a press", function()
        start()
        local made = T.garbage(function()
            Stubs.Jump(1000)
            Stubs.SetFalling(true)
            Stubs.Jump(1000)
        end)
        T.truthy(made < 1, string.format("%.1f KB for 2,000 presses", made))
    end)

    it("come back with a restored backup, the best day too", function()
        local ns = start({ only = "Jumps" })
        Stubs.Jump(7)
        Stubs.Advance(60)
        local text
        ns.Backup:Make({}, function(result) text = result end)
        ns = start({ only = "Jumps", now = at(10, 4) }) -- a fresh install
        local found
        ns.Backup:Read(text, function(result) found = result end)
        T.truthy(ns.Backup:Restore(found))
        ns = Stubs.Relog(nil, true)
        T.eq(jumps(ns, 20261003), 7)
        T.eq(card(ns).lines[1], "Bounciest day: Saturday, October 3, 2026 (7 jumps)")
    end)

    it("read in German", function()
        local ns = start({ locale = "deDE" })
        Stubs.Jump(1204)
        Stubs.Advance(60)
        T.eq(ns.Trackers:Get("Jumps").label, "Sprünge")
        local jumpsCard = card(ns)
        T.eq(jumpsCard.title, "Sprünge")
        T.eq(jumpsCard.big, "1.204")
        T.eq(jumpsCard.caption, "Sprünge")
        T.same(jumpsCard.lines, { "Sprungfreudigster Tag: Samstag, 3. Oktober 2026 (1.204 Sprünge)",
            "Im Schnitt 1.204 Sprünge pro gespieltem Tag" })
    end)
end)
