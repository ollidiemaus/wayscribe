local _, ns = ...

-- Internal messages between layers (docs/ARCHITECTURE.md §3.3):
--   READY, LOGOUT, SAFE_MODE(reason), RECORD_ADDED(record), COUNTER_CHANGED(path, key, amount),
--   SETTINGS_CHANGED(key, value), ITEM_NAMES_LOADED, REBUILT
local Bus = { handlers = {} }
ns.Bus = Bus

function Bus:On(message, owner, fn)
    local list = self.handlers[message]
    if not list then
        list = {}
        self.handlers[message] = list
    end
    list[owner] = fn
end

function Bus:Off(message, owner)
    local list = self.handlers[message]
    if list then
        list[owner] = nil
    end
end

-- Each listener runs in its own error boundary, so one failing listener can't block the others.
function Bus:Fire(message, ...)
    local list = self.handlers[message]
    if not list then return end
    for owner, fn in pairs(list) do
        ns.SafeCall("bus:" .. message, fn, owner, ...)
    end
end
