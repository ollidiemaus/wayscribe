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
