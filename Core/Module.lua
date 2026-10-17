local _, ns = ...
local L = ns.L

-- A module owns one hidden event frame and calls self[EVENT](self, ...) for registered events.
-- Every handler runs in an error boundary; a module that keeps failing switches itself off
-- instead of spamming errors (docs/ARCHITECTURE.md §3.2, §3.4).
local MAX_ERRORS = 10

local Module = {}
Module.__index = Module
ns.Module = Module

function ns.NewModule(name)
    return setmetatable({ name = name, enabled = false, errorCount = 0 }, Module)
end

local function onEvent(frame, event, ...)
    frame.owner:Dispatch(event, ...)
end

function Module:GetFrame()
    local frame = self.frame
    if not frame then
        frame = CreateFrame("Frame")
        frame.owner = self
        frame:SetScript("OnEvent", onEvent)
        self.frame = frame
    end
    return frame
end

function Module:RegisterEvent(event)
    self:GetFrame():RegisterEvent(event)
end

function Module:RegisterUnitEvent(event, ...)
    self:GetFrame():RegisterUnitEvent(event, ...)
end

-- For events that may not exist on this client: the Mainline engine errors on unknown events.
function Module:TryRegisterEvent(event)
    local frame = self:GetFrame()
    return (pcall(frame.RegisterEvent, frame, event))
end

-- TryRegisterEvent for a unit event: the client delivers it only for the given units.
function Module:TryRegisterUnitEvent(event, ...)
    local frame = self:GetFrame()
    return (pcall(frame.RegisterUnitEvent, frame, event, ...))
end

function Module:UnregisterEvent(event)
    if self.frame then
        self.frame:UnregisterEvent(event)
    end
end

function Module:UnregisterAllEvents()
    if self.frame then
        self.frame:UnregisterAllEvents()
    end
end

function Module:Dispatch(event, ...)
    local handler = self[event]
    if not handler or not self.enabled then return end
    local ok, err = pcall(handler, self, ...)
    if not ok then
        self:OnError(event, err)
    end
end

function Module:OnError(where, err)
    ns.Log:Error(self.name, tostring(where) .. ": " .. ns.Log.ToText(err))
    self.errorCount = self.errorCount + 1
    if self.errorCount >= MAX_ERRORS and self.enabled then
        self:Disable()
        ns.Print(L.MODULE_DISABLED:format(self.label or self.name))
    end
end

local function runTimer(module, fn)
    local ok, err = pcall(fn, module)
    if not ok then
        module:OnError("timer", err)
    end
end

-- Runs fn(self) later through the error boundary, unless the module was disabled meanwhile.
function Module:After(seconds, fn)
    C_Timer.After(seconds, function()
        if self.enabled then runTimer(self, fn) end
    end)
end

-- A debounce key's timers: pending.firesAt holds when each armed one fires, latest first. A timer is
-- armed only when none fires by `due`, so it fires before all the others: the last one fires next.
local function armUnlessOneFiresBy(pending, due, seconds)
    local firesAt = pending.firesAt
    if not firesAt[1] or firesAt[#firesAt] > due then
        firesAt[#firesAt + 1] = due
        C_Timer.After(seconds, pending.fire)
    end
end

local function fireDebounce(module, pending)
    local firesAt = pending.firesAt
    firesAt[#firesAt] = nil
    if not module.enabled then pending.due = nil end -- asked while switched off
    local due = pending.due
    if not due then return end
    local now = GetTime()
    if now < due then
        -- Asked again since this timer was armed: wait out the rest.
        armUnlessOneFiresBy(pending, due, due - now)
        return
    end
    pending.due = nil
    runTimer(module, pending.fn)
end

-- Runs fn(self) once, `seconds` after the last call with this key, unless the module was switched
-- off meanwhile: a burst of noisy events (SKILL_LINES_CHANGED, UPDATE_FACTION) costs one piece of
-- work and one timer (docs/ARCHITECTURE.md §3.3). A call arms a timer only when none armed for this
-- key fires by its due time; one that fires early arms one more for the rest.
function Module:Debounce(key, seconds, fn)
    local debounced = self.debounced
    if not debounced then
        debounced = {}
        self.debounced = debounced
    end
    local pending = debounced[key]
    if not pending then
        pending = { firesAt = {} }
        pending.fire = function() fireDebounce(self, pending) end
        debounced[key] = pending
    end
    local due = GetTime() + seconds
    pending.due, pending.fn = due, fn
    armUnlessOneFiresBy(pending, due, seconds)
end

function Module:Enable()
    if self.enabled then return true end
    self.enabled = true
    if self.OnEnable then
        local ok, err = pcall(self.OnEnable, self)
        if not ok then
            self:OnError("OnEnable", err)
            -- A half-enabled module must not keep listening.
            self:Disable()
            return false
        end
    end
    return true
end

function Module:Disable()
    if not self.enabled then return end
    self.enabled = false
    self:UnregisterAllEvents()
    if self.debounced then
        for _, pending in pairs(self.debounced) do
            pending.due = nil -- its armed timers run nothing
        end
    end
    if self.OnDisable then
        local ok, err = pcall(self.OnDisable, self)
        if not ok then
            ns.Log:Error(self.name, "OnDisable: " .. ns.Log.ToText(err))
        end
    end
end
