local _, ns = ...
local L, Compat, Store, Time, Players = ns.L, ns.Compat, ns.Store, ns.Time, ns.Players
local StaticData = ns.StaticData

-- Dungeon and raid runs (docs/ARCHITECTURE.md §6.6). A run lives in state.activeRun from entering
-- an instance until it is closed, so /reload, corpse runs and disconnects continue the same run:
--   * a run whose final boss died is closed (DUNGEON_COMPLETED) as soon as the player leaves;
--   * any other run stays open outside for RESUME_WINDOW, then closes as DUNGEON_VISITED.
local RESUME_WINDOW = 30 * 60
-- A run without a single kill shorter than this isn't worth an entry (zoning in and out again).
local MIN_VISIT = 60
-- The same boss killed again after this long means the instance was reset: a new run.
local REPEAT_KILL = 120
local TRACKED_TYPES = { party = true, raid = true }
local INSTANCE_EVENTS = { "ENCOUNTER_END", "BOSS_KILL", "LFG_COMPLETION_REWARD", "SCENARIO_COMPLETED" }
local MAX_NAMES = 5

local function instanceTitle(data)
    local title = data.name or L.UNKNOWN_INSTANCE:format(data.instanceID)
    if data.wing then
        title = L.INSTANCE_WING:format(title, L["WING_" .. data.wing:upper()])
    end
    return title
end

local function withGroup(text, data)
    if data.roster and #data.roster > 0 then
        text = text .. " " .. L.DUNGEON_WITH:format(Players:FormatNames(data.roster, MAX_NAMES))
    end
    return text
end

-- Everyone who was there, counted once per run: "top companions" in the yearly recap.
local function countCompanions(rollup, data)
    if not data.roster then return end
    rollup.companions = rollup.companions or {}
    for _, id in ipairs(data.roster) do
        rollup.companions[id] = (rollup.companions[id] or 0) + 1
    end
end

local function addCounts(target, source)
    for key, count in pairs(source) do
        target[key] = (target[key] or 0) + count
    end
end

local RUN_FIELDS = {
    instanceID = "number", name = "string?", difficultyID = "number?", wing = "string?",
    roster = "table?", bosses = "table?", dur = "number?",
}

ns.RecordTypes:Register("DUNGEON_COMPLETED", {
    version = 1,
    category = "adventure",
    fields = RUN_FIELDS,
    firstKey = function(data)
        return "DUNGEON:" .. data.instanceID .. (data.wing and (":" .. data.wing) or "")
    end,
    rollup = function(rollup, data)
        rollup.dungeons = rollup.dungeons or {}
        rollup.dungeons[data.instanceID] = (rollup.dungeons[data.instanceID] or 0) + 1
        countCompanions(rollup, data)
    end,
    -- Also merges `companions`, which DUNGEON_VISITED fills too: one merge per rollup field.
    merge = function(target, source)
        for _, field in ipairs({ "dungeons", "companions" }) do
            if source[field] then
                target[field] = target[field] or {}
                addCounts(target[field], source[field])
            end
        end
    end,
    render = function(data, record)
        local text = (record.first and L.DUNGEON_CLEARED_FIRST or L.DUNGEON_CLEARED):format(instanceTitle(data))
        text = withGroup(text, data)
        if data.dur then
            text = text .. " " .. L.IN_PARENTHESES:format(Time.FormatDuration(data.dur))
        end
        return text
    end,
})

ns.RecordTypes:Register("DUNGEON_VISITED", {
    version = 1,
    category = "adventure",
    fields = RUN_FIELDS,
    rollup = countCompanions,
    render = function(data)
        local bosses = data.bosses and #data.bosses or 0
        local text
        if bosses == 0 then
            text = L.DUNGEON_VISITED:format(instanceTitle(data))
        elseif bosses == 1 then
            text = L.DUNGEON_VISITED_BOSS:format(instanceTitle(data))
        else
            text = L.DUNGEON_VISITED_BOSSES:format(instanceTitle(data), bosses)
        end
        return withGroup(text, data)
    end,
})

local Dungeons = ns.Trackers:New("Dungeons", { label = L.TRACKER_DUNGEONS, tooltip = L.TRACKER_DUNGEONS_TIP })

function Dungeons:OnEnable()
    self.instanceEvents = false
    self.closePending = false
    self:RegisterEvent("PLAYER_ENTERING_WORLD")
    self:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    self:RegisterEvent("PLAYER_LOGOUT")
    self:Update()
end

function Dungeons:GetRun()
    local run = Store:GetState("activeRun")
    return type(run) == "table" and type(run.instanceID) == "number" and run or nil
end

local function contains(list, value)
    for _, item in ipairs(list) do
        if item == value then return true end
    end
    return false
end

local function newRun(instanceID, name, difficultyID, now)
    return {
        instanceID = instanceID, name = name, difficultyID = difficultyID, start = now,
        bosses = {}, killedAt = {}, roster = {},
    }
end

-- Context-scoped events: boss kills only matter for a run while inside its instance.
function Dungeons:SetInstanceEvents(inside)
    if inside == self.instanceEvents then return end
    self.instanceEvents = inside
    for _, event in ipairs(INSTANCE_EVENTS) do
        if inside then
            self:TryRegisterEvent(event)
        else
            self:UnregisterEvent(event)
        end
    end
end

function Dungeons:PLAYER_ENTERING_WORLD()
    self:Update()
end

function Dungeons:ZONE_CHANGED_NEW_AREA()
    self:Update()
end

-- Keep the run open across logout and /reload; the leave time decides whether it resumes.
function Dungeons:PLAYER_LOGOUT()
    local run = self:GetRun()
    if run and not run.left then
        run.left = Time.Now()
        Store:SetState("activeRun", run)
    end
end

function Dungeons:Update()
    local now = Time.Now()
    local instanceID, instanceType, difficultyID, name = Compat.GetInstance()
    local run = self:GetRun()
    if instanceID and TRACKED_TYPES[instanceType] then
        if run and (run.instanceID ~= instanceID or (run.left and now - run.left > RESUME_WINDOW)) then
            self:Close(run)
            run = nil
        end
        run = run or newRun(instanceID, name, difficultyID, now)
        run.left = nil
        run.name = run.name or name
        Store:SetState("activeRun", run)
        self:SetInstanceEvents(true)
        return
    end

    self:SetInstanceEvents(false)
    if not run then return end
    run.left = run.left or now
    if run.completed or now - run.left > RESUME_WINDOW then
        self:Close(run)
    else
        Store:SetState("activeRun", run)
        self:ScheduleClose()
    end
end

-- Closes the run once the resume window has passed, if the player stays out without zoning.
function Dungeons:ScheduleClose()
    if self.closePending then return end
    self.closePending = true
    self:After(RESUME_WINDOW + 1, function(module)
        module.closePending = false
        module:Update()
    end)
end

function Dungeons:ENCOUNTER_END(encounterID, _, _, _, success)
    success = Compat.Safe(success)
    if success == 1 or success == true then
        self:Kill(encounterID)
    end
end

function Dungeons:BOSS_KILL(encounterID)
    self:Kill(encounterID)
end

-- Optional completion signals, used if this client sends them (dungeon finder, scenarios).
function Dungeons:LFG_COMPLETION_REWARD()
    local run = self:GetRun()
    if run and not run.left and not run.completed then
        run.completed = true
        run.completedAt = Time.Now()
        Store:SetState("activeRun", run)
    end
end
Dungeons.SCENARIO_COMPLETED = Dungeons.LFG_COMPLETION_REWARD

function Dungeons:Kill(encounterID)
    encounterID = Compat.Safe(encounterID, "number")
    local run = self:GetRun()
    if not encounterID or not run or run.left then return end
    local now = Time.Now()
    local killedAt = run.killedAt[encounterID]
    if killedAt then
        if now - killedAt < REPEAT_KILL then return end -- one kill reported by two events
        self:Close(run)
        run = newRun(run.instanceID, run.name, run.difficultyID, now)
    end
    run.killedAt[encounterID] = now
    run.bosses[#run.bosses + 1] = encounterID
    run.last = now
    for _, id in ipairs(Players:InternAll(Compat.GetGroupMembers()) or {}) do
        if not contains(run.roster, id) then
            run.roster[#run.roster + 1] = id
        end
    end
    local finals = StaticData.Dungeons[run.instanceID]
    local final = finals and finals[encounterID]
    if final then
        run.completed = true
        run.completedAt = now
        run.wing = type(final) == "string" and final or nil
    end
    Store:SetState("activeRun", run)
end

function Dungeons:IsRightAfterClear(run)
    local cleared = Store:GetState("lastCleared")
    return type(cleared) == "table" and cleared.instanceID == run.instanceID
        and run.start - cleared.ts < RESUME_WINDOW
end

-- The record is dated when the final boss died, or when the player left.
function Dungeons:Close(run)
    Store:SetState("activeRun", nil)
    local ts = run.completedAt or run.left or run.last or Time.Now()
    -- The run is no longer in the state, so the record can take over its tables.
    local data = {
        instanceID = run.instanceID, name = run.name, difficultyID = run.difficultyID, wing = run.wing,
        roster = #run.roster > 0 and run.roster or nil,
        bosses = #run.bosses > 0 and run.bosses or nil,
        dur = math.max(0, ts - run.start),
    }
    if run.completed then
        Store:SetState("lastCleared", { instanceID = run.instanceID, ts = ts })
        Store:Append("DUNGEON_COMPLETED", data, { ts = ts })
    elseif data.bosses or (data.dur >= MIN_VISIT and not self:IsRightAfterClear(run)) then
        -- Zoning back in after a clear (to loot or wait for the group) is not a new visit.
        Store:Append("DUNGEON_VISITED", data, { ts = ts })
    end
end
