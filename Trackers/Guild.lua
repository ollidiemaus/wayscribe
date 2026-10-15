local _, ns = ...
local L, Compat, Store, Trace = ns.L, ns.Compat, ns.Store, ns.Trace

-- Guild (docs/ARCHITECTURE.md §6.18): an entry when the character joins a guild, with its name, and
-- when it leaves. PLAYER_GUILD_UPDATE and the login ask for a look, which compares the guild with
-- the saved snapshot, state.guild = { name = guild's name or false }, so a change made while
-- Wayscribe was off is caught at the next look. Right after login the name can still be missing, so
-- only "not in a guild" means the character left. Rank changes are no entries, and the first look is
-- silent.
local SETTLE = 1   -- seconds after an event; a burst of PLAYER_GUILD_UPDATE is one look
local RETRY = 5    -- seconds before another look while the guild's name hasn't loaded
local RETRIES = 3

-- "Joined the guild <Red Hand>", "Left the guild <Red Hand>"
ns.RecordTypes:Register("GUILD", {
    version = 1,
    category = "adventure",
    fields = { joined = "boolean", name = "string" },
    render = function(data)
        return (data.joined and L.GUILD_JOINED or L.GUILD_LEFT):format(data.name)
    end,
})

local Guild = ns.Trackers:New("Guild", {
    label = L.TRACKER_GUILD, tooltip = L.TRACKER_GUILD_TIP,
})

-- Each event asks for a look a second later; a burst of them is one look, which the launch trace
-- names by every event that asked.
function Guild:AskForLook(event, seconds)
    local asked = self.asked or {}
    self.asked = asked
    if not asked[event] then
        asked[event] = true
        asked[#asked + 1] = event
    end
    self:Debounce("look", seconds or SETTLE, self.Look)
end

function Guild:OnEnable()
    self.asked, self.retries = nil, 0
    self:TryRegisterEvent("PLAYER_GUILD_UPDATE")
    self:RegisterEvent("PLAYER_ENTERING_WORLD")
    self:AskForLook("enable")
end

function Guild:PLAYER_GUILD_UPDATE(unit)
    if unit == nil or Compat.Safe(unit, "string") == "player" then self:AskForLook("PLAYER_GUILD_UPDATE") end
end

function Guild:PLAYER_ENTERING_WORLD()
    self:AskForLook("PLAYER_ENTERING_WORLD")
end

-- Compares the guild (its name, false for none) with the snapshot and writes the entries; returns
-- how the look ended, for the trace. The snapshot follows each entry written, so a failed write
-- repeats nothing that was written before it.
local function compare(now)
    if not Store:IsWritable() then return "read-only" end
    local saved = Store:GetState("guild")
    if type(saved) ~= "table" or (saved.name ~= false and type(saved.name) ~= "string") then
        if not Store:SetState("guild", { name = now }) then return "read-only" end
        return "first look"
    end
    local before = saved.name
    if before == now then return "unchanged" end
    local outcomes = {}
    if before then
        local entry, reason = Store:Append("GUILD", { joined = false, name = before })
        if not entry then return "not written: " .. tostring(reason) end
        if not Store:SetState("guild", { name = false }) then return "read-only" end
        outcomes[#outcomes + 1] = "left"
    end
    if now then
        local entry, reason = Store:Append("GUILD", { joined = true, name = now })
        if not entry then return "not written: " .. tostring(reason) end
        if not Store:SetState("guild", { name = now }) then return "read-only" end
        outcomes[#outcomes + 1] = "joined"
    end
    return table.concat(outcomes, " + ")
end

function Guild:Look()
    local asked = self.asked
    self.asked = nil
    local inGuild, name, rawIn, rawName = Compat.GetGuild()
    local outcome
    if inGuild == nil then
        outcome = "unreadable"
    elseif inGuild and not name then
        outcome = "name missing"
        if self.retries < RETRIES then
            self.retries = self.retries + 1
            self:AskForLook("retry", RETRY)
        end
    else
        self.retries = 0
        outcome = compare(inGuild and name or false)
    end
    Trace:Add(self.id, asked and table.concat(asked, "+"), outcome, "inGuild", rawIn, inGuild and "name", rawName)
end
