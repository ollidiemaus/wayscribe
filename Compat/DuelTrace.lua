local _, ns = ...
local Compat = ns.Compat

-- Developer mode only: a log of the raw duel events, to learn from a real duel what a duel tracker
-- could rely on: whether the chat line naming the winner is a secret value, which name form the
-- events and that line use (Forever names have surnames), and where the opponent's class can be
-- read. Each line is printed and kept in WayscribeDB.duelTrace; /ws duellog shows them again.
local DuelTrace = ns.NewModule("dueltrace")
ns.DuelTrace = DuelTrace

local MAX_LINES = 200
-- System chat is logged only around a duel (plus every line that names a duel's winner): from a
-- challenge until the request runs out, and for a moment after the duel ends.
local REQUEST_WINDOW = 300
local AFTER_FINISH = 10

local EVENTS = {
    "DUEL_REQUESTED", "DUEL_TO_THE_DEATH_REQUESTED", "DUEL_INBOUNDS", "DUEL_OUTOFBOUNDS", "DUEL_FINISHED",
    "CHAT_MSG_SYSTEM", "PLAYER_TARGET_CHANGED", "PLAYER_DEAD",
}

-- "%1$s has defeated %2$s in a duel", "%2$s has fled from %1$s in a duel": %1$s is the winner in both.
local RESULT_STRINGS = { "DUEL_WINNER_KNOCKOUT", "DUEL_WINNER_RETREAT" }

-- Units the challenger may be found as; DUEL_REQUESTED only says their name.
local SEARCH_UNITS = { "target", "mouseover", "focus", "softfriend", "softenemy", "softinteract" }
for i = 1, 40 do SEARCH_UNITS[#SEARCH_UNITS + 1] = "nameplate" .. i end

local function now()
    return Compat.Call(GetTime) or time()
end

local function describe(value)
    if Compat.IsSecret(value) then return "<secret>" end
    if type(value) == "string" then return '"' .. value .. '"' end
    return tostring(value)
end

local function describeAll(...)
    local parts = {}
    for i = 1, select("#", ...) do
        parts[i] = describe((select(i, ...)))
    end
    return table.concat(parts, ", ")
end

-- The event arguments that carry something, by position ("2=..., 7=..."); chat events have many.
local function describeSet(...)
    local parts = {}
    for i = 1, select("#", ...) do
        local value = select(i, ...)
        if Compat.IsSecret(value) or (value ~= nil and value ~= "" and value ~= 0 and value ~= false) then
            parts[#parts + 1] = i .. "=" .. describe(value)
        end
    end
    return table.concat(parts, ", ")
end

local function afterRead(ok, ...)
    if not ok then return "error" end
    return describeAll(...)
end

-- Values are read raw, not through Compat.Safe, so the log shows which ones are secret.
local function read(fn, ...)
    if type(fn) ~= "function" then return "missing" end
    return afterRead(pcall(fn, ...))
end

local function describeUnit(unit)
    if Compat.Call(UnitExists, unit) == false then
        return unit .. ": none"
    end
    return unit .. ": UnitName=" .. read(UnitName, unit)
        .. " GetUnitName=" .. read(GetUnitName, unit, true)
        .. " guid=" .. read(UnitGUID, unit)
        .. " class=" .. read(UnitClass, unit)
        .. " race=" .. read(UnitRace, unit)
        .. " level=" .. read(UnitLevel, unit)
        .. " canAttack=" .. read(UnitCanAttack, "player", unit)
end

-- The ways a unit's name may be written, by label; secret parts are left out.
local function nameForms(unit)
    local first, second = Compat.Call(UnitName, unit)
    local forms = {}
    if type(first) == "string" then
        forms.UnitName = first
        if type(second) == "string" and second ~= "" then
            forms["UnitName+space"] = first .. " " .. second
            forms["UnitName+dash"] = first .. "-" .. second
        end
    end
    local full = Compat.Call(GetUnitName, unit, true)
    if type(full) == "string" then forms.GetUnitName = full end
    return forms
end

-- Which form of the unit's name `name` is ("UnitName", "GetUnitName", ...), or nil.
local function matchName(name, unit)
    name = Compat.Safe(name, "string")
    if not name then return nil end
    local labels = {}
    for label, form in pairs(nameForms(unit)) do
        if form == name then labels[#labels + 1] = label end
    end
    table.sort(labels)
    return labels[1] and table.concat(labels, "/") or nil
end

-- The result string `text` matches, with the winner and the loser; nil for any other line.
local function matchResult(text)
    for _, key in ipairs(RESULT_STRINGS) do
        local values = Compat.ParseGlobalString(key, text)
        if values then
            return key, values[1], values[2]
        end
    end
end

function DuelTrace:Add(text)
    local t = now()
    local line = string.format("%s.%03d %s", date("%H:%M:%S"), math.floor(t % 1 * 1000), text)
    local db = ns.accountDB
    if db then
        db.duelTrace = db.duelTrace or {}
        local lines = db.duelTrace
        lines[#lines + 1] = line
        while #lines > MAX_LINES do table.remove(lines, 1) end
    end
    ns.Print("duel " .. line)
end

function DuelTrace:InWindow()
    return (self.windowUntil or 0) > now()
end

-- Starts the window around a duel; the first time, with what a tracker would match the lines against.
function DuelTrace:Open()
    if not self:InWindow() then
        self:Add("--- duel window opens")
        self:Add(describeUnit("player"))
        for _, key in ipairs(RESULT_STRINGS) do
            self:Add(key .. " = " .. describe(_G[key]))
        end
    end
    self.windowUntil = now() + REQUEST_WINDOW
end

-- Finds the challenger among the units the player can see, and says which name form matched.
function DuelTrace:FindUnit(name)
    local found = false
    for _, unit in ipairs(SEARCH_UNITS) do
        local form = matchName(name, unit)
        if form then
            found = true
            self:Add("  found as " .. unit .. " (" .. form .. ") " .. describeUnit(unit))
        end
    end
    if not found then
        self:Add("  not found among target, mouseover, focus, soft targets, nameplates")
    end
end

function DuelTrace:DUEL_REQUESTED(name)
    self:Open()
    self:Add("DUEL_REQUESTED(" .. describe(name) .. ")")
    self:FindUnit(name)
end

function DuelTrace:DUEL_TO_THE_DEATH_REQUESTED(name)
    self:Open()
    self:Add("DUEL_TO_THE_DEATH_REQUESTED(" .. describe(name) .. ")")
    self:FindUnit(name)
end

-- StartDuel(unit or name, ...) is how the unit menu, /duel and the duel-to-the-death dialog send a
-- challenge; no event says the player sent one.
function DuelTrace:START_DUEL(target, ...)
    self:Open()
    self:Add("StartDuel(" .. describeAll(target, ...) .. ")")
    if Compat.Call(UnitExists, target) then
        self:Add("  " .. describeUnit(target))
    else
        self:FindUnit(target)
    end
end

function DuelTrace:DUEL_INBOUNDS(...)
    self:Open()
    self:Add("DUEL_INBOUNDS(" .. describeAll(...) .. ")")
end

function DuelTrace:DUEL_OUTOFBOUNDS(...)
    self:Open()
    self:Add("DUEL_OUTOFBOUNDS(" .. describeAll(...) .. ")")
end

-- Says nothing about the winner; the health is here in case it has to tell instead of the chat line.
function DuelTrace:DUEL_FINISHED(...)
    self:Add("DUEL_FINISHED(" .. describeAll(...) .. ") health=" .. read(UnitHealth, "player")
        .. " max=" .. read(UnitHealthMax, "player") .. " deadOrGhost=" .. read(UnitIsDeadOrGhost, "player"))
    self:Add("  " .. describeUnit("target"))
    self.windowUntil = now() + AFTER_FINISH
end

function DuelTrace:CHAT_MSG_SYSTEM(text, ...)
    local plain = Compat.Safe(text, "string")
    local key, winner, loser
    if plain then
        key, winner, loser = matchResult(plain)
    end
    if not key and not self:InWindow() then return end
    local line = "CHAT_MSG_SYSTEM(" .. describeSet(text, ...) .. ")"
    if key then
        line = line .. " -> " .. key .. " winner=" .. describe(winner) .. " (me: " .. tostring(matchName(winner, "player"))
            .. ") loser=" .. describe(loser) .. " (me: " .. tostring(matchName(loser, "player")) .. ")"
    end
    self:Add(line)
end

function DuelTrace:PLAYER_TARGET_CHANGED()
    if self:InWindow() then
        self:Add("PLAYER_TARGET_CHANGED " .. describeUnit("target"))
    end
end

function DuelTrace:PLAYER_DEAD()
    if self:InWindow() then
        self:Add("PLAYER_DEAD")
    end
end

-- A post-hook can't be removed: it stays, and Dispatch drops the calls while the trace is off.
function DuelTrace:HookStartDuel()
    if self.hooked or type(hooksecurefunc) ~= "function" or type(StartDuel) ~= "function" then return end
    self.hooked = true
    hooksecurefunc("StartDuel", function(...)
        DuelTrace:Dispatch("START_DUEL", ...)
    end)
end

function DuelTrace:OnEnable()
    for _, event in ipairs(EVENTS) do
        self:TryRegisterEvent(event)
    end
    self:HookStartDuel()
end

function DuelTrace:Follow()
    if ns.devMode then
        self:Enable()
    else
        self:Disable()
    end
end

function DuelTrace:OnSettingsChanged(key)
    if key == "devMode" then self:Follow() end
end

ns.Bus:On("READY", DuelTrace, DuelTrace.Follow)
ns.Bus:On("SETTINGS_CHANGED", DuelTrace, DuelTrace.OnSettingsChanged)
