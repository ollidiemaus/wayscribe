-- Just enough of the WoW API to load the addon in plain Lua and drive it with events.
local Stubs = {}

-- A stand-in for a Midnight-style secret value: issecretvalue() is true only for this.
Stubs.SECRET = setmetatable({}, { __tostring = function() return "<SECRET>" end })

local state

local function newFrame()
    local frame = { events = {}, scripts = {}, shown = false }
    function frame:RegisterEvent(event)
        if state.unknownEvents[event] then error("Attempt to register unknown event \"" .. event .. "\"") end
        self.events[event] = true
    end
    function frame:RegisterUnitEvent(event) self:RegisterEvent(event) end
    function frame:UnregisterEvent(event) self.events[event] = nil end
    function frame:UnregisterAllEvents() self.events = {} end
    function frame:IsEventRegistered(event) return self.events[event] == true end
    function frame:SetScript(name, fn) self.scripts[name] = fn end
    state.frames[#state.frames + 1] = frame
    return frame
end

-- opts: now, guid, name, realm, level, interface, accountDB, charDB, locale, unknownEvents
function Stubs.Install(opts)
    opts = opts or {}
    state = {
        now = opts.now or os.time({ year = 2026, month = 10, day = 3, hour = 12 }),
        frames = {},
        timers = {},
        printed = {},
        level = opts.level or 10,
        unknownEvents = opts.unknownEvents or {},
    }
    Stubs.state = state

    _G.unpack = _G.unpack or table.unpack
    _G.time = function() return state.now end
    _G.date = os.date
    _G.issecretvalue = function(value) return value == Stubs.SECRET end
    _G.GetLocale = function() return opts.locale or "enUS" end
    _G.GetBuildInfo = function() return "1.60.1", "70009", "Oct 1 2026", opts.interface or 16001 end
    _G.WOW_PROJECT_ID, _G.WOW_PROJECT_MAINLINE = 1, 1
    _G.UnitGUID = function(unit) if unit == "player" then return opts.guid or "Player-1-0000AAAA" end end
    _G.UnitFullName = function() return opts.name or "Tester", opts.realm or "Forever" end
    _G.GetRealmName = function() return opts.realm or "Forever" end
    _G.UnitClass = function() return "Mage", "MAGE", 8 end
    _G.UnitLevel = function() return state.level end
    _G.C_Map = { GetBestMapForUnit = function() return 1411 end }
    _G.C_Timer = {
        After = function(seconds, fn)
            state.timers[#state.timers + 1] = { at = state.now + seconds, fn = fn }
        end,
    }
    _G.C_AddOns = nil
    _G.C_EventUtils = nil
    _G.CreateFrame = function() return newFrame() end
    _G.DEFAULT_CHAT_FRAME = { AddMessage = function(_, message) state.printed[#state.printed + 1] = message end }
    _G.geterrorhandler = function() return function() end end
    _G.SlashCmdList = {}
    _G.UISpecialFrames = {}
    _G.WayscribeDB = opts.accountDB
    _G.WayscribeCharDB = opts.charDB
end

function Stubs.TocFiles()
    local files = {}
    for rawLine in io.lines("Wayscribe.toc") do
        local line = rawLine:gsub("%s+$", "")
        if line ~= "" and not line:find("^#") then
            files[#files + 1] = (line:gsub("\\", "/"))
        end
    end
    return files
end

-- Loads every file in TOC order into a fresh namespace, like the client does.
function Stubs.LoadAddon(opts)
    Stubs.Install(opts)
    local ns = {}
    for _, file in ipairs(Stubs.TocFiles()) do
        local chunk = assert(loadfile(file))
        chunk("Wayscribe", ns)
    end
    Stubs.ns = ns
    return ns
end

-- Delivers a game event to every frame registered for it, in creation order.
function Stubs.Fire(event, ...)
    for _, frame in ipairs(state.frames) do
        if frame.events[event] and frame.scripts.OnEvent then
            frame.scripts.OnEvent(frame, event, ...)
        end
    end
end

function Stubs.Advance(seconds)
    state.now = state.now + seconds
    local due = {}
    local waiting = {}
    for _, timer in ipairs(state.timers) do
        if timer.at <= state.now then due[#due + 1] = timer else waiting[#waiting + 1] = timer end
    end
    state.timers = waiting
    for _, timer in ipairs(due) do
        timer.fn()
    end
end

function Stubs.SetTime(ts) state.now = ts end
function Stubs.Now() return state.now end
function Stubs.SetLevel(level) state.level = level end
function Stubs.Printed() return state.printed end

-- ADDON_LOADED -> PLAYER_LOGIN -> PLAYER_ENTERING_WORLD, as on a real login or /reload.
function Stubs.Login(reload)
    Stubs.Fire("ADDON_LOADED", "Wayscribe")
    Stubs.Fire("PLAYER_LOGIN")
    Stubs.Fire("PLAYER_ENTERING_WORLD", not reload, reload == true)
end

-- Logout, then load a fresh copy of the addon with exactly what the client would have saved.
function Stubs.Relog(opts, reload)
    local serialize = require("serialize")
    Stubs.Fire("PLAYER_LOGOUT")
    local saved = {
        accountDB = serialize.RoundTrip(_G.WayscribeDB),
        charDB = serialize.RoundTrip(_G.WayscribeCharDB),
    }
    opts = opts or {}
    for key, value in pairs(saved) do
        if opts[key] == nil then opts[key] = value end
    end
    opts.now = opts.now or state.now
    opts.level = opts.level or state.level
    local ns = Stubs.LoadAddon(opts)
    Stubs.Login(reload)
    return ns
end

function Stubs.Copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = Stubs.Copy(item) end
    return result
end

return Stubs
