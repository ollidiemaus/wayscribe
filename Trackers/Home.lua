local _, ns = ...
local L, Compat, Store, Trace = ns.L, ns.Compat, ns.Store, ns.Trace

-- Home (docs/ARCHITECTURE.md §6.19): an entry when the character binds its hearthstone at a new inn.
-- HEARTHSTONE_BOUND, CONFIRM_BINDER and the login ask for a look, which compares the inn's place
-- with the saved snapshot, state.home = { name = place }. The place is read in the client's
-- language, so the first look of each session (the login) takes it silently: a switched client
-- language, or a bind made while Wayscribe was off, is no move.

-- Whether this session has read the home yet. The file loads anew on each login and /reload, so
-- switching the tracker off and on again during play doesn't make its next look silent.
local takenThisSession = false

-- "Hearthstone bound to Thunder Bluff"
ns.RecordTypes:Register("HOME", {
    version = 1,
    category = "travel",
    fields = { name = "string" },
    render = function(data)
        return L.HOME_BOUND:format(data.name)
    end,
})

local Home = ns.Trackers:New("Home", {
    label = L.TRACKER_HOME, tooltip = L.TRACKER_HOME_TIP,
})

function Home:OnEnable()
    self:TryRegisterEvent("HEARTHSTONE_BOUND")
    self:TryRegisterEvent("CONFIRM_BINDER")
    self:RegisterEvent("PLAYER_ENTERING_WORLD")
    self:AskForLook("enable")
end

function Home:HEARTHSTONE_BOUND() self:AskForLook("HEARTHSTONE_BOUND") end
function Home:CONFIRM_BINDER() self:AskForLook("CONFIRM_BINDER") end
function Home:PLAYER_ENTERING_WORLD() self:AskForLook("PLAYER_ENTERING_WORLD") end

-- Compares the place with the snapshot and writes the entry; returns how the look ended, for the
-- trace, then true unless the journal was read-only: this session has read the home.
local function compare(now)
    if not Store:IsWritable() then return "read-only", false end
    local saved = Store:GetState("home")
    local before = type(saved) == "table" and type(saved.name) == "string" and saved.name or nil
    if before == now then return "unchanged", true end
    if not before or not takenThisSession then
        if not Store:SetState("home", { name = now }) then return "read-only", false end
        return before and "taken at login" or "first look", true
    end
    local entry, reason = Store:Append("HOME", { name = now })
    if not entry then return "not written: " .. tostring(reason), true end
    if not Store:SetState("home", { name = now }) then return "read-only", false end
    return "moved", true
end

function Home:Look()
    local asked = self:TakeAsked()
    local name, raw = Compat.GetBindLocation()
    local outcome
    if not name then
        outcome = "unreadable"
    else
        local taken
        outcome, taken = compare(name)
        if taken then takenThisSession = true end
    end
    Trace:Add(self.id, asked, outcome, "bind", raw)
end
