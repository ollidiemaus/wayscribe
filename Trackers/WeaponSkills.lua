local _, ns = ...
local L, Compat, Store, Trace = ns.L, ns.Compat, ns.Store, ns.Trace

-- Weapon skills (docs/ARCHITECTURE.md §6.22): the points gained in each weapon skill, Defense
-- included, as one counter line on the day page. Snapshot-diff as Professions (§6.3) does it: a look
-- after SKILL_LINES_CHANGED settles, and one after login, compares the trained points with
-- state.weaponSkills, so points gained while the addon was off are counted once, at the next login.
-- A line the snapshot doesn't know yet (the first look, a newly learned weapon) is taken silently.
-- Only the trained points are compared: a racial bonus or a buff changes no rank.
local SETTLE = 0.5
-- The Skills tab can still be loading right after login.
local FIRST_LOOK_DELAY = 3

local function skillName(skillLine)
    local name = Compat.GetWeaponSkillName(skillLine)
    if name then return name end
    local known = Store:GetState("weaponSkills")
    local entry = type(known) == "table" and known[skillLine]
    return type(entry) == "table" and entry.name or L.UNKNOWN_WEAPON_SKILL:format(skillLine)
end

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

local WeaponSkills = ns.Trackers:New("WeaponSkills", {
    label = L.TRACKER_WEAPONSKILLS, tooltip = L.TRACKER_WEAPONSKILLS_TIP, lookDelay = SETTLE,
})

function WeaponSkills:OnEnable()
    if not Compat.has.weaponSkills then return end
    self:TryRegisterEvent("SKILL_LINES_CHANGED")
    self:AskForLook("enable", FIRST_LOOK_DELAY)
end

function WeaponSkills:SKILL_LINES_CHANGED() self:AskForLook("SKILL_LINES_CHANGED") end

-- Counts the points gained since the snapshot and saves the look; returns how it ended, for the trace.
local function compare(current)
    if not Store:IsWritable() then return "read-only" end
    local saved = Store:GetState("weaponSkills")
    local known = type(saved) == "table" and saved or {}
    local gains = {}
    for skillLine, now in pairs(current) do
        local before = known[skillLine]
        -- A lower rank (the skill unlearned and learned again) is no gain either.
        if type(before) == "table" and type(before.rank) == "number" and now.rank > before.rank then
            Store:Count("weaponSkill", skillLine, now.rank - before.rank)
            gains[#gains + 1] = skillLine .. "+" .. (now.rank - before.rank)
        end
        -- The game's name may be missing this time; the saved one stays.
        if not now.name and type(before) == "table" then now.name = before.name end
        known[skillLine] = now
    end
    -- A line missing from this look stays saved, or it would be taken silently again later.
    if not Store:SetState("weaponSkills", known) then return "read-only" end
    if type(saved) ~= "table" then return "first look" end
    if #gains == 0 then return "unchanged" end
    table.sort(gains)
    return "counted " .. table.concat(gains, ",")
end

function WeaponSkills:Look()
    local asked = self:TakeAsked()
    local current = Compat.GetWeaponSkills()
    local lines = 0
    for _ in pairs(current or {}) do lines = lines + 1 end
    -- Every character has Defense: a look that reads no line at all has read nothing.
    local outcome = lines > 0 and compare(current) or "unreadable"
    Trace:Add(self.id, asked, outcome, "lines", current and lines)
end
