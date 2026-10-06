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

-- Runs fn(self) later through the error boundary, unless the module was disabled meanwhile.
function Module:After(seconds, fn)
    C_Timer.After(seconds, function()
        if not self.enabled then return end
        local ok, err = pcall(fn, self)
        if not ok then
            self:OnError("timer", err)
        end
    end)
end

-- Runs fn(self) once, `seconds` after the last call with this key: a burst of noisy events
-- (SKILL_LINES_CHANGED, BAG_UPDATE) costs one piece of work (docs/ARCHITECTURE.md §3.3).
function Module:Debounce(key, seconds, fn)
    self.debounced = self.debounced or {}
    local generation = (self.debounced[key] or 0) + 1
    self.debounced[key] = generation
    self:After(seconds, function(module)
        if module.debounced[key] == generation then
            fn(module)
        end
    end)
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
    if self.OnDisable then
        local ok, err = pcall(self.OnDisable, self)
        if not ok then
            ns.Log:Error(self.name, "OnDisable: " .. ns.Log.ToText(err))
        end
    end
end
