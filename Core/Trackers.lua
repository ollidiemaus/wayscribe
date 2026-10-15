local _, ns = ...

-- Registry of everything that turns game events into journal facts. The settings page builds one
-- toggle per non-internal tracker from this list.
local Trackers = { list = {}, byId = {} }
ns.Trackers = Trackers

local LOOK_DELAY = 1 -- seconds after an event; login and a loading screen are one look

-- A tracker is a module (docs/ARCHITECTURE.md §3.2) with what the launch trackers share (§6.11).
local Tracker = setmetatable({}, { __index = ns.Module })
Tracker.__index = Tracker

-- A launch tracker reads the game in self:Look() a moment after an event asks for it: a burst of
-- events is one look, which the launch trace names by every event that asked. `seconds` replaces
-- the tracker's delay for this request.
function Tracker:AskForLook(event, seconds)
    local asked = self.asked or {}
    self.asked = asked
    if not asked[event] then
        asked[event] = true
        asked[#asked + 1] = event
    end
    self:Debounce("look", seconds or self.lookDelay, self.Look)
end

-- The events that asked for the look being taken, joined by "+", for its trace line; the next
-- burst starts afresh.
function Tracker:TakeAsked()
    local asked = self.asked
    self.asked = nil
    return asked and table.concat(asked, "+")
end

-- A look asked for before the tracker was switched off goes with it.
function Tracker:Disable()
    self.asked = nil
    ns.Module.Disable(self)
end

-- opts.label and opts.tooltip: shown in settings; opts.default: on unless false;
-- opts.internal: always on, no toggle; opts.lookDelay: seconds from an event to the look it asks
-- for (one by default).
function Trackers:New(id, opts)
    assert(not self.byId[id], "duplicate tracker " .. tostring(id))
    opts = opts or {}
    local tracker = setmetatable(ns.NewModule("tracker:" .. id), Tracker)
    tracker.id = id
    tracker.lookDelay = opts.lookDelay or LOOK_DELAY
    tracker.label = opts.label or id
    tracker.tooltip = opts.tooltip
    tracker.default = opts.default ~= false
    tracker.internal = opts.internal == true
    self.list[#self.list + 1] = tracker
    self.byId[id] = tracker
    return tracker
end

function Trackers:Get(id)
    return self.byId[id]
end

function Trackers:IsWanted(tracker)
    if tracker.internal then return true end
    local settings = ns.accountDB and ns.accountDB.settings
    local choice = settings and settings.trackers and settings.trackers[tracker.id]
    if choice == nil then
        return tracker.default
    end
    return choice == true
end

-- Nothing records while the journal is read-only.
function Trackers:EnableAll()
    if not ns.Store:IsWritable() then return end
    for _, tracker in ipairs(self.list) do
        if self:IsWanted(tracker) then
            tracker:Enable()
        end
    end
end

function Trackers:DisableAll()
    for _, tracker in ipairs(self.list) do
        tracker:Disable()
    end
end

function Trackers:SetWanted(id, wanted)
    local tracker = self.byId[id]
    if not tracker or tracker.internal then return end
    ns.accountDB.settings.trackers[id] = wanted == true
    if wanted and ns.Store:IsWritable() then
        tracker:Enable()
    else
        tracker:Disable()
    end
    -- The journal shows some tabs only while their tracker is on.
    ns.Bus:Fire("SETTINGS_CHANGED", "tracker:" .. id, wanted == true)
end
