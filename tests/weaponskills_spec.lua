local T = require("testlib")
local Stubs = require("wow_stubs")
local describe, it = T.describe, T.it

-- A Human warrior's Skills tab: Swords carries the racial +5 as its modifier.
local function skillsTab(weaponsCollapsed)
    return {
        { header = true, id = 7, name = "Class Skills", category = 7 },
        { id = 26, name = "Arms", category = 7, rank = 50, max = 60 },
        { header = true, id = 11, name = "Professions", category = 11 },
        { id = 186, name = "Mining", category = 11, rank = 75, max = 150 },
        { header = true, id = 6, name = "Weapon Skills", category = 6, collapsed = weaponsCollapsed },
        { id = 43, name = "Swords", category = 6, rank = 50, max = 60, modifier = 5, temp = 3 },
        { id = 95, name = "Defense", category = 6, rank = 55, max = 60 },
        { id = 118, name = "Dual Wield", category = 6, rank = 1, max = 1 },
        { id = 3014, name = "Feral Combat", category = 6, rank = 1, max = 60 },
        { header = true, id = 8, name = "Armor Proficiencies", category = 8 },
        { id = 413, name = "Mail", category = 8, rank = 1, max = 1 },
        { header = true, id = 10, name = "Languages", category = 10 },
        { id = 98, name = "Language: Common", category = 10, rank = 300, max = 300 },
    }
end

local WEAPON_SKILLS = {
    [43] = { rank = 50, max = 60, name = "Swords" },
    [95] = { rank = 55, max = 60, name = "Defense" },
    [3014] = { rank = 1, max = 60, name = "Feral Combat" },
}

describe("Compat.GetWeaponSkills", function()
    it("reads the trained points of the weapon skill lines, Defense and Feral Combat included", function()
        local ns = Stubs.LoadAddon()
        Stubs.SetSkillLines(skillsTab())
        Stubs.Login()
        T.truthy(ns.Compat.has.weaponSkills)
        T.same(ns.Compat.GetWeaponSkills(), WEAPON_SKILLS)
    end)

    it("reads the same with the Weapon Skills header collapsed, and leaves it collapsed", function()
        local ns = Stubs.LoadAddon()
        local lines = skillsTab(true)
        Stubs.SetSkillLines(lines)
        Stubs.Login()
        T.same(ns.Compat.GetWeaponSkills(), WEAPON_SKILLS)
        T.eq(lines[5].collapsed, true)
        T.eq(Stubs.state.headerToggles, 0)
    end)

    it("reads the changed points after SKILL_LINES_CHANGED", function()
        local ns = Stubs.LoadAddon()
        Stubs.SetSkillLines(skillsTab())
        Stubs.Login()
        local lines = skillsTab()
        lines[6].rank = 51
        Stubs.ChangeSkillLines(lines)
        T.eq(ns.Compat.GetWeaponSkills()[43].rank, 51)
    end)

    it("leaves out a line whose rank is secret", function()
        local ns = Stubs.LoadAddon()
        local lines = skillsTab()
        lines[6].rank = Stubs.SECRET
        lines[7].name = Stubs.SECRET
        Stubs.SetSkillLines(lines)
        Stubs.Login()
        local skills = ns.Compat.GetWeaponSkills()
        T.eq(skills[43], nil)
        T.same(skills[95], { rank = 55, max = 60 })
    end)

    it("reads nothing without the skill API", function()
        local ns = Stubs.LoadAddon()
        _G.C_SkillInfo = nil
        Stubs.Login()
        ns.Compat:Detect()
        T.eq(ns.Compat.has.weaponSkills, false)
        T.eq(ns.Compat.GetWeaponSkills(), nil)
    end)
end)

describe("/ws probe weapon skills", function()
    it("prints the flag and one line per weapon skill line", function()
        local ns = Stubs.LoadAddon()
        Stubs.SetSkillLines(skillsTab(true))
        Stubs.Login()
        local found = {}
        for _, line in ipairs(ns.Probe:Run()) do found[line] = true end
        T.truthy(found["has.weaponSkills = true"])
        T.truthy(found["weaponSkill.43 = Swords, category 6, 50/60"])
        T.truthy(found["weaponSkill.95 = Defense, category 6, 55/60"])
        T.truthy(found["weaponSkill.3014 = Feral Combat, category 6, 1/60"])
        T.falsy(found["weaponSkill.118 = Dual Wield, category 6, 1/1"])
        T.falsy(found["weaponSkill.26 = Arms, category 7, 50/60"])
    end)

    it("says when no weapon skill line can be read", function()
        local ns = Stubs.LoadAddon()
        _G.C_SkillInfo = nil
        Stubs.Login()
        local found = {}
        for _, line in ipairs(ns.Probe:Run()) do found[line] = true end
        T.truthy(found["has.weaponSkills = false"])
        T.truthy(found["weaponSkills = nil"])
    end)
end)

-- Login with the given Skills tab plus the delayed first look.
local function start(lines, opts)
    local ns = Stubs.LoadAddon(opts)
    Stubs.SetSkillLines(lines or skillsTab())
    Stubs.Login()
    Stubs.Advance(3)
    return ns
end

-- Swords (line 6) and Defense (line 7) at new ranks, settled.
local function train(swords, defense)
    local lines = skillsTab()
    lines[6].rank, lines[7].rank = swords or 50, defense or 55
    Stubs.ChangeSkillLines(lines)
    Stubs.Advance(1)
    return lines
end

-- The Skills tab with `line` added to the weapon skills, settled.
local function learn(line)
    local lines = skillsTab()
    table.insert(lines, 7, line)
    Stubs.ChangeSkillLines(lines)
    Stubs.Advance(1)
    return lines
end

-- The weapon skill entries, oldest first, a First marked "*".
local function entries(ns)
    local texts = {}
    for _, typeName in ipairs({ "WEAPON_SKILL_LEARNED", "WEAPON_SKILL_MASTERED" }) do
        for _, record in ipairs(ns.Store:GetRecordsOfType(typeName)) do
            texts[#texts + 1] = { record.id, (record.first and "*" or "") .. ns.RecordTypes:Render(record) }
        end
    end
    table.sort(texts, function(a, b) return a[1] < b[1] end)
    for i, pair in ipairs(texts) do texts[i] = pair[2] end
    return texts
end

local function counterLines(ns, day)
    local stored = ns.Store:GetDay(day or 20261003)
    return ns.RecordTypes:RenderCounters(stored and stored.counters or {})
end

describe("weapon skills tracker", function()
    it("takes the first look silently", function()
        local ns = start()
        T.eq(#ns.Store:GetDayRecords(20261003), 0)
        T.same(counterLines(ns), {})
        T.same(ns.Store:GetState("weaponSkills"), WEAPON_SKILLS)
    end)

    it("counts the points gained as one line on the day page, apart from profession gains", function()
        local ns = start()
        train(52, 56)
        train(53, 56)
        ns.Store:Count("skill", 186, 4)
        T.eq(#ns.Store:GetDayRecords(20261003), 0)
        T.same(ns.Store:GetDay(20261003).counters.weaponSkill, { [43] = 3, [95] = 1 })
        local texts = counterLines(ns)
        local found = {}
        for _, text in ipairs(texts) do found[text] = true end
        T.truthy(found["Weapon skills: Defense +1, Swords +3"])
        T.eq(#texts, 2)
    end)

    it("looks once per burst of SKILL_LINES_CHANGED", function()
        local ns = start()
        local calls = 0
        local original = ns.Compat.GetWeaponSkills
        ns.Compat.GetWeaponSkills = function() calls = calls + 1 return original() end
        local lines = skillsTab()
        lines[6].rank = 51
        Stubs.ChangeSkillLines(lines)
        Stubs.Fire("SKILL_LINES_CHANGED")
        Stubs.Fire("SKILL_LINES_CHANGED")
        Stubs.Advance(1)
        T.eq(calls, 1)
        T.eq(ns.Store:GetDay(20261003).counters.weaponSkill[43], 1)
    end)

    it("records nothing for a modifier change or a lower rank", function()
        local ns = start()
        local lines = skillsTab()
        lines[6].modifier, lines[6].temp = 15, 10
        Stubs.ChangeSkillLines(lines)
        Stubs.Advance(1)
        train(40, 55)
        T.same(counterLines(ns), {})
        train(41, 55)
        T.same(ns.Store:GetDay(20261003).counters.weaponSkill, { [43] = 1 })
    end)

    it("records a newly learned weapon skill as a First, without counting its points", function()
        local ns = start()
        learn({ id = 44, name = "Axes", category = 6, rank = 1, max = 60 })
        T.same(entries(ns), { "*Learned Axes" })
        T.same(counterLines(ns), {})
        learn({ id = 44, name = "Axes", category = 6, rank = 3, max = 60 })
        T.same(entries(ns), { "*Learned Axes" })
        T.same(ns.Store:GetDay(20261003).counters.weaponSkill, { [44] = 2 })
    end)

    it("makes no entry for the first look or a rankless line", function()
        local ns = start()
        learn({ id = 118, name = "Dual Wield", category = 6, rank = 1, max = 1 })
        T.same(entries(ns), {})
    end)

    it("learns nothing from a line that read secret at the first look", function()
        local lines = skillsTab()
        table.insert(lines, 7, { id = 44, name = "Axes", category = 6, rank = Stubs.SECRET, max = 60 })
        local ns = start(lines)
        learn({ id = 44, name = "Axes", category = 6, rank = 12, max = 60 })
        learn({ id = 44, name = "Axes", category = 6, rank = 13, max = 60 })
        T.same(entries(ns), {})
        T.same(ns.Store:GetDay(20261003).counters.weaponSkill, { [44] = 1 })
    end)

    it("records a skill reaching 300 as mastered, once", function()
        local ns = start()
        train(299, 55)
        T.same(entries(ns), {})
        train(300, 55)
        T.same(entries(ns), { "*Swords mastered" })
        train(300, 56)
        T.same(entries(ns), { "*Swords mastered" })
        T.same(ns.Store:GetDay(20261003).counters.weaponSkill, { [43] = 250, [95] = 1 })
    end)

    it("makes no entry for reaching the cap of the current level", function()
        local ns = start()
        local lines = skillsTab()
        lines[6].rank, lines[6].max = 60, 60
        Stubs.ChangeSkillLines(lines)
        Stubs.Advance(1)
        T.same(entries(ns), {})
        T.same(ns.Store:GetDay(20261003).counters.weaponSkill, { [43] = 10 })
    end)

    it("keeps a line missing from a look", function()
        local ns = start()
        local lines = skillsTab()
        table.remove(lines, 7)
        Stubs.ChangeSkillLines(lines)
        Stubs.Advance(1)
        T.eq(ns.Store:GetState("weaponSkills")[95].rank, 55)
        train(50, 57)
        T.same(ns.Store:GetDay(20261003).counters.weaponSkill, { [95] = 2 })
    end)

    it("counts gains made while the addon was off once, on the login day, and shows them in the recap", function()
        start()
        Stubs.Advance(3600)
        local lines = skillsTab()
        lines[6].rank, lines[7].rank = 60, 58
        Stubs.SetSkillLines(lines)
        local tomorrow = 20261004
        local ns = Stubs.Relog({ now = Stubs.Now() + 86400 })
        Stubs.Advance(3)
        T.same(ns.Store:GetDay(tomorrow).counters.weaponSkill, { [43] = 10, [95] = 3 })
        ns = Stubs.Relog()
        Stubs.Advance(3)
        T.same(ns.Store:GetDay(tomorrow).counters.weaponSkill, { [43] = 10, [95] = 3 })
        Stubs.Advance(600)
        ns = Stubs.Relog({ now = Stubs.Now() + 86400 })
        Stubs.Advance(3)
        local recap = ns.LoginRecap:Collect(true)
        local found = {}
        for _, text in ipairs(recap and recap.lines or {}) do found[text] = true end
        T.truthy(found["Weapon skills: Defense +3, Swords +10"])
    end)

    it("records a skill learned while the addon was off on the login day", function()
        start()
        local lines = skillsTab()
        table.insert(lines, 7, { id = 44, name = "Axes", category = 6, rank = 4, max = 60 })
        Stubs.SetSkillLines(lines)
        local ns = Stubs.Relog({ now = Stubs.Now() + 86400 })
        Stubs.Advance(3)
        T.same(entries(ns), { "*Learned Axes" })
        T.eq(#ns.Store:GetDayRecords(20261004), 1)
    end)

    it("marks no First twice after a backup is restored", function()
        local ns = start()
        train(300, 55)
        learn({ id = 44, name = "Axes", category = 6, rank = 1, max = 60 })
        local text
        ns.Backup:Make({}, function(result) text = result end)
        T.truthy(ns.Schema:ResetCharacter())
        ns = Stubs.Relog(nil, true)
        local found
        ns.Backup:Read(text, function(result) found = result end)
        T.truthy(ns.Backup:Restore(found))
        ns = Stubs.Relog(nil, true)
        Stubs.Advance(3)
        T.same(entries(ns), { "*Swords mastered", "*Learned Axes" })
        -- A snapshot that lost Axes sees it learned again, but not for the first time.
        local known = ns.Store:GetState("weaponSkills")
        known[44] = nil
        ns.Store:SetState("weaponSkills", known)
        learn({ id = 44, name = "Axes", category = 6, rank = 2, max = 60 })
        T.same(entries(ns), { "*Swords mastered", "*Learned Axes", "Learned Axes" })
    end)

    it("records nothing and raises nothing without the API or with secret values", function()
        local ns = start()
        local lines = skillsTab()
        lines[6].rank, lines[7].rank = Stubs.SECRET, 60
        lines[7].max = Stubs.SECRET
        Stubs.ChangeSkillLines(lines)
        Stubs.Advance(1)
        _G.C_SkillInfo.GetNumSkillLines = function() error("boom") end
        _G.C_SkillInfo.GetSkillLineInfoByID = function() return Stubs.SECRET end
        Stubs.Fire("SKILL_LINES_CHANGED")
        Stubs.Advance(1)
        T.same(counterLines(ns), {})
        T.eq(#ns.Log:GetEntries(), 0)

        ns = Stubs.LoadAddon()
        _G.C_SkillInfo = nil
        Stubs.Login()
        Stubs.Fire("SKILL_LINES_CHANGED")
        Stubs.Advance(3)
        T.eq(ns.Store:GetState("weaponSkills"), nil)

        ns = Stubs.LoadAddon()
        Stubs.SetSkillLines({})
        Stubs.Login()
        Stubs.Advance(3)
        T.eq(ns.Store:GetState("weaponSkills"), nil, "an empty read is no baseline")
        T.eq(#ns.Log:GetEntries(), 0)
    end)

    it("is switched off by its own setting, without touching Professions", function()
        local ns = start()
        T.eq(ns.Trackers:Get("WeaponSkills").default, true)
        ns.Trackers:SetWanted("WeaponSkills", false)
        train(55, 55)
        T.same(counterLines(ns), {})
        T.truthy(ns.Trackers:Get("Professions").enabled)
        ns.Trackers:SetWanted("WeaponSkills", true)
        Stubs.Advance(3)
        T.same(ns.Store:GetDay(20261003).counters.weaponSkill, { [43] = 5 })
    end)

    it("names a skill by the game, then by the saved name, then as unknown", function()
        local ns = start()
        train(51, 55)
        ns.Store:Count("weaponSkill", 999, 2)
        _G.C_SkillInfo.GetSkillLineInfoByID = function() return nil end
        T.same(counterLines(ns), { "Weapon skills: Swords +1, unknown skill (999) +2" })
    end)

    it("reads in German", function()
        local ns = start(nil, { locale = "deDE" })
        ns.Store:Count("weaponSkill", 999, 2)
        T.same(counterLines(ns), { "Waffenfertigkeiten: unbekannte Fertigkeit (999) +2" })
    end)

    it("traces each look in developer mode", function()
        local accountDB = { schema = 1, log = {}, characters = {}, settings = { devMode = true } }
        local ns = start(nil, { accountDB = accountDB, only = "WeaponSkills" })
        train(52, 56)
        train(52, 56)
        train(300, 56)
        learn({ id = 44, name = "Axes", category = 6, rank = 1, max = 60 })
        _G.C_SkillInfo = nil
        Stubs.Fire("SKILL_LINES_CHANGED")
        Stubs.Advance(1)
        local traced = {}
        for i, line in ipairs(ns.Trace:GetLines()) do traced[i] = line:gsub("^%S+ %S+ ", "") end
        T.same(traced, {
            "WeaponSkills enable: lines=3 -> first look",
            "WeaponSkills SKILL_LINES_CHANGED: lines=3 -> counted 43+2,95+1",
            "WeaponSkills SKILL_LINES_CHANGED: lines=3 -> unchanged",
            "WeaponSkills SKILL_LINES_CHANGED: lines=3 -> counted 43+248; mastered 43",
            "WeaponSkills SKILL_LINES_CHANGED: lines=4 -> learned 44",
            "WeaponSkills SKILL_LINES_CHANGED: lines=missing -> unreadable",
        })
    end)
end)

-- The Weapon skills card of 2026 as { title, big, caption, lines... }, or nil.
local function card(ns)
    for _, built in ipairs(ns.YearCards:Build(2026)) do
        if built.id == "weaponSkills" then
            local flat = { built.title, built.big, built.caption }
            for _, line in ipairs(built.lines) do flat[#flat + 1] = line end
            return flat
        end
    end
end

describe("weapon skills card", function()
    it("tells the points gained, the skills learned and mastered, and the gains per skill", function()
        local ns = start()
        learn({ id = 44, name = "Axes", category = 6, rank = 1, max = 60 })
        train(300, 60)
        T.same(card(ns), {
            "Weapon skills", "255", "weapon skill points gained", "Learned Axes", "Swords mastered",
            "Most practised: Swords +250, Defense +5",
        })
    end)

    it("leaves out a year without points gained or skills learned", function()
        local ns = start()
        train(50, 55)
        T.eq(card(ns), nil)
    end)

    it("counts the skills learned when no points were gained", function()
        local ns = start()
        learn({ id = 44, name = "Axes", category = 6, rank = 1, max = 60 })
        T.same(card(ns), { "Weapon skills", "1", "weapon skill learned", "Learned Axes" })
    end)

    it("reads in German", function()
        local ns = start(nil, { locale = "deDE" })
        learn({ id = 44, name = "Axes", category = 6, rank = 1, max = 60 })
        train(51, 55)
        T.same(card(ns), {
            "Waffenfertigkeiten", "1", "Waffenfertigkeitspunkt gewonnen", "Axes erlernt", "Am meisten geübt: Swords +1",
        })
    end)
end)
