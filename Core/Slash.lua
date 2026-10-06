local _, ns = ...
local L = ns.L

local Slash = { commands = {} }
ns.Slash = Slash

local commands = Slash.commands

commands[""] = function()
    ns.Journal:Toggle()
end

commands.help = function()
    ns.Print(L.HELP)
end

commands.settings = function()
    ns.SettingsPanel:Open()
end
commands.config = commands.settings

-- Shows the login recap now, regardless of the setting and of whether it was shown today.
commands.recap = function()
    local recap = ns.LoginRecap:Collect(true)
    if recap then
        ns.LoginRecap:Show(recap)
    else
        ns.Print(L.RECAP_NOTHING)
    end
end

commands.probe = function()
    ns.Probe:Run()
end

commands.stats = function()
    local stats = ns.Store:GetStats()
    ns.Print(L.STATS_LINE:format(stats.records, stats.days, stats.months, stats.sessions, stats.seq))
end

commands.log = function()
    local entries = ns.Log:GetEntries()
    if #entries == 0 then
        ns.Print(L.LOG_EMPTY)
        return
    end
    for i = math.max(1, #entries - 9), #entries do
        local entry = entries[i]
        ns.Print(date("%Y-%m-%d %H:%M", entry.ts) .. " [" .. entry.source .. "] " .. entry.message)
    end
end

commands.rebuild = function()
    local total = ns.Store:Rebuild()
    if total then
        ns.Print(L.REBUILT:format(total))
    elseif ns.safeMode then
        ns.Print(L.SAFE_MODE_BANNER:format(ns.safeMode))
    end
end

commands.dev = function()
    ns.devMode = not ns.devMode
    ns.accountDB.settings.devMode = ns.devMode or nil
    ns.Print(L.DEV_MODE:format(ns.devMode and L.ON or L.OFF))
end

commands.accept = function()
    ns.Print(ns.Schema:Accept() and L.ACCEPTED or L.NOTHING_TO_ACCEPT)
end

local function parseValue(text)
    local number = tonumber(text)
    if number then return number end
    if text == "true" then return true end
    if text == "false" then return false end
    return text
end

-- /ws simulate LEVEL_UP level=12 map=1411 — goes through the real write path, flagged as test data.
commands.simulate = function(rest)
    if not ns.devMode then
        ns.Print(L.SIM_NEEDS_DEV)
        return
    end
    local typeName, args = rest:match("^(%S+)%s*(.*)$")
    if not typeName then
        ns.Print(L.SIM_USAGE)
        return
    end
    if typeName:lower() == "clear" then
        ns.Print(L.SIM_CLEARED:format(ns.Store:RemoveSimulated() or 0))
        return
    end
    local data = {}
    for key, value in args:gmatch("([%w_]+)=(%S+)") do
        data[key] = parseValue(value)
    end
    local record, reason = ns.Store:Append(typeName:upper(), data, { simulated = true })
    if record then
        ns.Print(L.SIM_ADDED:format(record.type))
    else
        ns.Print(L.SIM_FAILED:format(tostring(reason)))
    end
end

function Slash:Handle(input)
    local command, rest = (input or ""):match("^%s*(%S*)%s*(.-)%s*$")
    local handler = commands[command:lower()] or commands.help
    local ok = ns.SafeCall("slash:" .. command, handler, rest)
    if not ok then
        ns.Print(L.COMMAND_FAILED)
    end
end

SLASH_WAYSCRIBE1 = "/wayscribe"
SLASH_WAYSCRIBE2 = "/ws"
SlashCmdList.WAYSCRIBE = function(input)
    Slash:Handle(input)
end
