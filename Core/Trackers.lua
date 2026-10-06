local _, ns = ...

-- Registry of everything that turns game events into journal facts. The settings page (0.2)
-- builds one toggle per non-internal tracker from this list.
local Trackers = { list = {}, byId = {} }
ns.Trackers = Trackers

-- opts.label: shown in settings; opts.default: on unless false; opts.internal: always on, no toggle.
function Trackers:New(id, opts)
    assert(not self.byId[id], "duplicate tracker " .. tostring(id))
    opts = opts or {}
    local tracker = ns.NewModule("tracker:" .. id)
    tracker.id = id
    tracker.label = opts.label or id
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
end
