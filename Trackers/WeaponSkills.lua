local _, ns = ...
local L, Compat, Store, Trace, YearCards = ns.L, ns.Compat, ns.Store, ns.Trace, ns.YearCards

-- Weapon skills (docs/ARCHITECTURE.md §6.22): the points gained in each weapon skill, Defense
-- included, as one counter line on the day page, and entries for a skill learned or mastered.
-- Snapshot-diff as Professions (§6.3) does it: a look after SKILL_LINES_CHANGED settles, and one after
-- login, compares the trained points with state.weaponSkills, so what happened while the addon was
-- off is recorded once, at the next login.
-- The first look is taken silently; a line it doesn't know after that is a newly learned weapon, an
-- entry marked First, whose points so far count nothing. Only the trained points are compared: a
-- racial bonus or a buff changes no rank.
-- The level-60 cap: crossing it is an entry, reaching the cap of a lower level is not.
local MASTERED = 300
local SETTLE = 0.5
-- The Skills tab can still be loading right after login.
local FIRST_LOOK_DELAY = 3
local ICON = "Interface\\Icons\\INV_Sword_04"

local function skillName(skillLine)
    local name = Compat.GetWeaponSkillName(skillLine)
    if name then return name end
    local known = Store:GetState("weaponSkills")
    local entry = type(known) == "table" and known[skillLine]
    return type(entry) == "table" and entry.name or L.UNKNOWN_WEAPON_SKILL:format(skillLine)
end

-- The skill lines learned (Your Year), per month like every rollup.
ns.RecordTypes:Register("WEAPON_SKILL_LEARNED", {
    version = 1,
    category = "progress",
    fields = { skillLine = "number" },
    firstKey = function(data) return "WEAPONLEARNED:" .. data.skillLine end,
    rollup = function(rollup, data)
        rollup.weaponSkillsLearned = rollup.weaponSkillsLearned or {}
        rollup.weaponSkillsLearned[data.skillLine] = true
    end,
    merge = function(target, source)
        for skillLine in pairs(source.weaponSkillsLearned or {}) do
            target.weaponSkillsLearned = target.weaponSkillsLearned or {}
            target.weaponSkillsLearned[skillLine] = true
        end
    end,
    render = function(data)
        return L.WEAPON_SKILL_LEARNED:format(skillName(data.skillLine))
    end,
})

-- The skill lines that reached MASTERED (Your Year).
ns.RecordTypes:Register("WEAPON_SKILL_MASTERED", {
    version = 1,
    category = "progress",
    fields = { skillLine = "number" },
    firstKey = function(data) return "WEAPONMASTERED:" .. data.skillLine end,
    rollup = function(rollup, data)
        rollup.weaponSkillsMastered = rollup.weaponSkillsMastered or {}
        rollup.weaponSkillsMastered[data.skillLine] = true
    end,
    merge = function(target, source)
        for skillLine in pairs(source.weaponSkillsMastered or {}) do
            target.weaponSkillsMastered = target.weaponSkillsMastered or {}
            target.weaponSkillsMastered[skillLine] = true
        end
    end,
    render = function(data)
        return L.WEAPON_SKILL_MASTERED:format(skillName(data.skillLine))
    end,
})

-- skillLine -> points gained that day: "Weapon skills: Swords +14, Defense +9". After Skill gains.
ns.RecordTypes:RegisterCounter("weaponSkill", {
    category = "progress",
    order = 35,
    render = function(bucket)
        local parts = {}
        for skillLine, gained in pairs(bucket) do
            parts[#parts + 1] = L.SKILL_GAIN:format(skillName(skillLine), gained)
        end
        table.sort(parts)
        return L.COUNTER_WEAPON_SKILL:format(table.concat(parts, L.LIST_SEPARATOR))
    end,
})

-- The skill names of a rollup set, sorted.
local function namesOf(set)
    local names = {}
    for skillLine in pairs(set or {}) do names[#names + 1] = skillName(skillLine) end
    table.sort(names)
    return names
end

-- "255 weapon skill points gained. Learned Axes. Swords mastered. Most practised: Swords +250, Defense +5"
YearCards:Register({
    id = "weaponSkills",
    order = 72,
    build = function(summary)
        local rollup = summary.rollup
        local gained = rollup.counters.weaponSkill
        local points = YearCards.Sum(gained)
        local learned, mastered = namesOf(rollup.weaponSkillsLearned), namesOf(rollup.weaponSkillsMastered)
        if points == 0 and #learned == 0 then return nil end
        local card = { title = L.CARD_WEAPON_SKILLS, icon = ICON, lines = {} }
        if points > 0 then
            card.big, card.caption = YearCards.Number(points), YearCards.Plural("CARD_WEAPON_SKILLS_POINTS", points)
        else
            card.big, card.caption = YearCards.Number(#learned), YearCards.Plural("CARD_WEAPON_SKILLS_LEARNED_COUNT", #learned)
        end
        if #learned > 0 then
            card.lines[#card.lines + 1] = L.WEAPON_SKILL_LEARNED:format(YearCards.List(learned))
        end
        if #mastered > 0 then
            card.lines[#card.lines + 1] = L.WEAPON_SKILL_MASTERED:format(YearCards.List(mastered))
        end
        if points > 0 then
            local parts = {}
            for i, skillLine in ipairs(YearCards.Ranked(gained)) do
                parts[i] = L.SKILL_GAIN:format(skillName(skillLine), gained[skillLine])
            end
            card.lines[#card.lines + 1] = L.CARD_WEAPON_SKILLS_GAINS:format(table.concat(parts, L.LIST_SEPARATOR))
        end
        return card
    end,
})

local WeaponSkills = ns.Trackers:New("WeaponSkills", {
    label = L.TRACKER_WEAPONSKILLS, tooltip = L.TRACKER_WEAPONSKILLS_TIP, lookDelay = SETTLE,
})

function WeaponSkills:OnEnable()
    if not Compat.has.weaponSkills then return end
    self:TryRegisterEvent("SKILL_LINES_CHANGED")
    self:AskForLook("enable", FIRST_LOOK_DELAY)
end

function WeaponSkills:SKILL_LINES_CHANGED() self:AskForLook("SKILL_LINES_CHANGED") end

-- "learned 44; counted 43+2,95+1; mastered 43", or "unchanged".
local OUTCOMES = { "learned", "counted", "mastered" }
local function describe(found)
    local parts = {}
    for _, kind in ipairs(OUTCOMES) do
        local list = found[kind]
        if #list > 0 then
            table.sort(list, function(a, b) return tostring(a) < tostring(b) end)
            parts[#parts + 1] = kind .. " " .. table.concat(list, ",")
        end
    end
    return #parts > 0 and table.concat(parts, "; ") or "unchanged"
end

-- Records the skills learned and mastered and counts the points gained since the snapshot, then saves
-- the look; returns how it ended, for the trace.
local function compare(current, unread)
    if not Store:IsWritable() then return "read-only" end
    local saved = Store:GetState("weaponSkills")
    local firstLook = type(saved) ~= "table"
    local known = firstLook and {} or saved
    local learned, gains, mastered = {}, {}, {}
    for skillLine, now in pairs(current) do
        local before = known[skillLine]
        if not firstLook and type(before) ~= "table" then
            Store:Append("WEAPON_SKILL_LEARNED", { skillLine = skillLine })
            learned[#learned + 1] = skillLine
        end
        -- A lower rank (the skill unlearned and learned again) is no gain either.
        if type(before) == "table" and type(before.rank) == "number" and now.rank > before.rank then
            Store:Count("weaponSkill", skillLine, now.rank - before.rank)
            gains[#gains + 1] = skillLine .. "+" .. (now.rank - before.rank)
            if before.rank < MASTERED and now.rank >= MASTERED then
                Store:Append("WEAPON_SKILL_MASTERED", { skillLine = skillLine })
                mastered[#mastered + 1] = skillLine
            end
        end
        -- The game's name may be missing this time; the saved one stays.
        if not now.name and type(before) == "table" then now.name = before.name end
        known[skillLine] = now
    end
    -- A line missing from this look stays saved, or it would be recorded as learned again later. One
    -- that read secret is saved without a rank: known, so not learned later, and its first rank no gain.
    for skillLine in pairs(unread or {}) do
        if type(known[skillLine]) ~= "table" then known[skillLine] = {} end
    end
    if not Store:SetState("weaponSkills", known) then return "read-only" end
    if firstLook then return "first look" end
    return describe({ learned = learned, counted = gains, mastered = mastered })
end

function WeaponSkills:Look()
    local asked = self:TakeAsked()
    local current, unread = Compat.GetWeaponSkills()
    local lines = 0
    for _ in pairs(current or {}) do lines = lines + 1 end
    -- Every character has Defense: a look that reads no line at all has read nothing.
    local outcome = lines > 0 and compare(current, unread) or "unreadable"
    Trace:Add(self.id, asked, outcome, "lines", current and lines)
end
