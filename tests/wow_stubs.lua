-- Just enough of the WoW API to load the addon in plain Lua and drive it with events.
local Stubs = {}

-- A stand-in for a Midnight-style secret value: issecretvalue() is true only for this.
Stubs.SECRET = setmetatable({}, { __tostring = function() return "<SECRET>" end })

-- Globals created by CreateFrame(type, name); a fresh load removes them again.
Stubs.namedFrames = {}

local state

local function noop() end

-- Regions accept any widget method (unknown ones do nothing), so UI code runs in tests. Methods
-- whose results the code uses are implemented; fields stay plain (an unknown field is nil).
local function permissive(region)
    return setmetatable(region, {
        __index = function(_, key)
            if type(key) == "string" and key:find("^%u") then return noop end
            return nil
        end,
    })
end

local function newFontString()
    local fontString = { shown = true, text = nil }
    function fontString:SetText(text) self.text = text end
    function fontString:GetText() return self.text end
    function fontString:GetStringHeight() return 12 end
    function fontString:GetStringWidth() return 100 end
    function fontString:Show() self.shown = true end
    function fontString:Hide() self.shown = false end
    function fontString:SetShown(shown) self.shown = shown == true end
    function fontString:IsShown() return self.shown end
    return permissive(fontString)
end

local function newFrame(frameType, name, parent, template)
    local frame = {
        events = {}, scripts = {}, shown = true, width = 0, height = 0, regions = {}, name = name,
        frameType = frameType, template = template, parent = parent,
    }
    function frame:RegisterEvent(event)
        if state.unknownEvents[event] then error("Attempt to register unknown event \"" .. event .. "\"") end
        self.events[event] = true
    end
    function frame:RegisterUnitEvent(event) self:RegisterEvent(event) end
    function frame:UnregisterEvent(event) self.events[event] = nil end
    function frame:UnregisterAllEvents() self.events = {} end
    function frame:IsEventRegistered(event) return self.events[event] == true end
    function frame:SetScript(script, fn) self.scripts[script] = fn end
    function frame:GetScript(script) return self.scripts[script] end
    function frame:Show()
        if self.shown then return end
        self.shown = true
        if self.scripts.OnShow then self.scripts.OnShow(self) end
    end
    function frame:Hide()
        if not self.shown then return end
        self.shown = false
        if self.scripts.OnHide then self.scripts.OnHide(self) end
    end
    function frame:SetShown(shown) if shown then self:Show() else self:Hide() end end
    function frame:IsShown() return self.shown end
    function frame:SetSize(width, height) self.width, self.height = width, height end
    function frame:SetWidth(width) self.width = width end
    function frame:SetHeight(height) self.height = height end
    function frame:GetWidth() return self.width end
    function frame:GetHeight() return self.height end
    function frame:GetName() return self.name end
    function frame:SetChecked(checked) self.checked = checked == true end
    function frame:GetChecked() return self.checked == true end
    function frame:SetEnabled(enabled) self.disabled = not enabled end
    function frame:IsEnabled() return not self.disabled end
    function frame:SetTitle(text) self.title = text end
    function frame:SetupMenu(generator) self.menuGenerator = generator end
    function frame:GetFrameLevel() return 1 end
    function frame:SetPoint(...) self.lastPoint = { ... } end
    function frame:SetText(text) self.text = text end
    function frame:GetText() return self.text end
    function frame:GetNumLetters() return #(self.text or "") end
    function frame:CreateFontString()
        local fontString = newFontString()
        self.regions[#self.regions + 1] = fontString
        return fontString
    end
    function frame:CreateTexture()
        local texture = { shown = true }
        function texture:Show() self.shown = true end
        function texture:Hide() self.shown = false end
        function texture:SetShown(shown) self.shown = shown == true end
        function texture:IsShown() return self.shown end
        function texture:SetTexture(file) self.file = file end
        return permissive(texture)
    end
    -- Lines remember where they were drawn (in the frame's coordinates) for map assertions.
    function frame:CreateLine(_, layer, _, sublevel)
        local line = { shown = true, layer = layer, sublevel = sublevel }
        function line:Show() self.shown = true end
        function line:Hide() self.shown = false end
        function line:IsShown() return self.shown end
        function line:SetStartPoint(_, _, x, y) self.x1, self.y1 = x, y end
        function line:SetEndPoint(_, _, x, y) self.x2, self.y2 = x, y end
        function line:SetThickness(thickness) self.thickness = thickness end
        function line:SetColorTexture(r, g, b, a) self.color = { r, g, b, a } end
        self.lines = self.lines or {}
        self.lines[#self.lines + 1] = line
        return permissive(line)
    end
    function frame:Click(button)
        if self.scripts.OnClick then self.scripts.OnClick(self, button or "LeftButton") end
    end
    state.frames[#state.frames + 1] = frame
    if name then
        _G[name] = frame
        Stubs.namedFrames[name] = true
    end
    return permissive(frame)
end

-- Every visible text of all frames, in creation order.
function Stubs.AllTexts()
    local texts = {}
    for _, frame in ipairs(state.frames) do
        for _, text in ipairs(Stubs.Texts(frame)) do texts[#texts + 1] = text end
    end
    return texts
end

-- Every visible text of a frame, in creation order (for UI assertions).
function Stubs.Texts(frame)
    local texts = {}
    for _, region in ipairs(frame.regions) do
        if region.shown and region.text then texts[#texts + 1] = region.text end
    end
    return texts
end

local function unitGuid(unit)
    if unit == "player" then return state.player.guid end
    local index = tonumber(unit:match("^party(%d)$") or unit:match("^raid(%d+)$"))
    local member = index and state.group[index]
    return member and member.guid
end

local function unitMember(unit)
    if unit == "player" then return state.player end
    local index = tonumber(unit:match("^party(%d)$") or unit:match("^raid(%d+)$"))
    return index and state.group[index]
end

local function installUnits(opts)
    state.player = {
        guid = opts.guid or "Player-1-0000AAAA", name = opts.name or "Tester", realm = opts.realm or "Forever", class = "MAGE",
    }
    _G.UnitGUID = unitGuid
    _G.UnitFullName = function(unit)
        local member = unitMember(unit)
        if not member then return nil end
        return member.name, member.realm
    end
    _G.GetRealmName = function() return state.player.realm end
    _G.UnitClass = function(unit)
        local member = unitMember(unit)
        if member then return member.class, member.class end
    end
    _G.UnitLevel = function() return state.level end
    -- UnitPosition: x, y, z, instance (the continent); nil when no position is set.
    _G.UnitPosition = function(unit)
        local position = unit == "player" and state.position
        if position then return position.x, position.y, 0, position.c end
    end
    _G.UnitOnTaxi = function() return state.onTaxi == true end
    _G.UnitIsDeadOrGhost = function() return state.dead == true end
    _G.IsInRaid = function() return #state.group > 4 end
    _G.GetNumGroupMembers = function() return #state.group > 0 and #state.group + 1 or 0 end
    _G.GetNumSubgroupMembers = function() return #state.group end
end

-- Two maps of Kalimdor (continent 1), laid out like the client's: u runs west to east (world -y),
-- v north to south (world -x). 1412 is a zone (map type 3) inside the continent map 1414 (type 2),
-- whose parent 947 (the world) has no world coordinates. 1412 puts map 0.4416, 0.7706 at world
-- -2894.3, -238.8, like the probe on build 70235.
local MAPS = {
    [1412] = { name = "Mulgore", continent = 1, top = -255.0, left = 2029.9, width = 5137.5, height = 3425, parent = 1414,
        type = 3 },
    [1414] = { name = "Kalimdor", continent = 1, top = 6000, left = 9000, width = 20000, height = 15000, parent = 947,
        type = 2 },
}
Stubs.MAPS = MAPS

function Stubs.MapToWorld(mapID, u, v)
    local map = MAPS[mapID]
    return map.top - v * map.height, map.left - u * map.width
end

function Stubs.WorldToMap(mapID, x, y)
    local map = MAPS[mapID]
    return (map.left - y) / map.width, (map.top - x) / map.height
end

local function installMaps()
    _G.CreateVector2D = function(x, y) return { x = x, y = y } end
    _G.C_Map = {
        GetBestMapForUnit = function() return state.bestMap or 1411 end,
        GetWorldPosFromMapPos = function(mapID, position)
            local map = MAPS[mapID]
            if not map then return nil end
            local x, y = Stubs.MapToWorld(mapID, position.x, position.y)
            return map.continent, { x = x, y = y }
        end,
        -- Like the client: the continent's map, unless a map is asked for.
        GetMapPosFromWorldPos = function(continent, position, overrideMapID)
            local mapID = overrideMapID or 1414
            local map = MAPS[mapID]
            if not map or map.continent ~= continent then return nil end
            local u, v = Stubs.WorldToMap(mapID, position.x, position.y)
            return mapID, { x = u, y = v }
        end,
        -- The zone at a point of the continent map.
        GetMapInfoAtPosition = function(mapID, u, v)
            if mapID ~= 1414 then return nil end
            local zoneU, zoneV = Stubs.WorldToMap(1412, Stubs.MapToWorld(1414, u, v))
            if zoneU >= 0 and zoneU <= 1 and zoneV >= 0 and zoneV <= 1 then
                return { mapID = 1412, parentMapID = 1414 }
            end
            return { mapID = 1414, parentMapID = 947 }
        end,
        GetPlayerMapPosition = function(mapID)
            local position, map = state.position, MAPS[mapID]
            if not (position and map and map.continent == position.c) then return nil end
            local u, v = Stubs.WorldToMap(mapID, position.x, position.y)
            return { x = u, y = v }
        end,
        GetMapInfo = function(mapID)
            local map = MAPS[mapID]
            return { mapID = mapID, name = map and map.name, parentMapID = map and map.parent or 0 }
        end,
        -- The maps under mapID (all levels down with allDescendants), of one map type if given.
        GetMapChildrenInfo = function(mapID, mapType, allDescendants)
            local children = {}
            for childID, map in pairs(MAPS) do
                local parent = map.parent
                while allDescendants and parent and parent ~= mapID do
                    parent = MAPS[parent] and MAPS[parent].parent
                end
                if parent == mapID and (not mapType or map.type == mapType) then
                    children[#children + 1] = { mapID = childID, mapType = map.type, parentMapID = map.parent }
                end
            end
            table.sort(children, function(a, b) return a.mapID < b.mapID end)
            return children
        end,
    }
end

local function installWorld()
    installMaps()
    _G.GetInstanceInfo = function()
        local i = state.instance
        return i.name, i.type, i.difficulty, "", 5, 0, false, i.id, 0, nil
    end
    _G.GetProfessions = function()
        local p = state.professions
        return p[1] and 1, p[2] and 2, nil, nil, nil
    end
    _G.GetProfessionInfo = function(index)
        local p = state.professions[index]
        if p then return p.name, 0, p.rank, p.max, 0, 0, p.skillLine end
    end
    _G.C_TradeSkillUI = nil
    _G.C_Spell = {
        GetSpellName = function(spellID) return state.spellNames[spellID] end,
        GetSpellTexture = function(spellID) return state.spellIcons[spellID] end,
    }
    _G.GetSubZoneText = function() return state.subZone or "" end
    _G.C_Item = {
        GetItemNameByID = function(itemID) return state.itemNames[itemID] end,
        GetItemInfoInstant = function(itemID)
            local class = state.itemClasses[itemID]
            if class then return itemID, "", "", "", 0, class[1], class[2] end
        end,
        RequestLoadItemDataByID = function(itemID) state.requestedItems[itemID] = true end,
    }
    _G.GetNumLootItems = function() return state.loot and #state.loot.items or 0 end
    _G.GetLootSlotLink = function(slot)
        local item = state.loot and state.loot.items[slot]
        if item and not item.looted then return "|cffffffff|Hitem:" .. item.id .. "::::::::|h[x]|h|r" end
    end
    _G.GetLootSlotInfo = function(slot)
        local item = state.loot and state.loot.items[slot]
        if item then return 0, "x", item.quantity or 1 end
    end
    _G.GetLootSourceInfo = function()
        return state.loot and state.loot.source, 1
    end
    _G.C_QuestLog = { GetTitleForQuestID = function(questID) return state.questTitles[questID] end }
    _G.C_QuestLine = nil
    _G.C_CVar = { GetCVar = function(name) return state.cvars[name] end }
end

-- The default UI's templates and atlases the journal asks for, as a client confirms them.
-- Includes the ScrollBox double. Call before Stubs.Login().
function Stubs.InstallNativeUI()
    Stubs.InstallScrollBox()
    local templates = {
        PortraitFrameTemplate = true, WowStyle1FilterDropdownTemplate = true,
        WowScrollBoxList = true, MinimalScrollBar = true, PanelTabButtonTemplate = true,
    }
    -- The default UI's tabs: the selected one is remembered on the frame.
    _G.PanelTemplates_SetNumTabs = function(frame, count) frame.numTabs = count end
    _G.PanelTemplates_SetTab = function(frame, id) frame.selectedTab = id end
    _G.C_XMLUtil = { GetTemplateInfo = function(name) return templates[name] and { type = "Frame" } or nil end }
    _G.C_Texture = { GetAtlasInfo = function(name) return name:find("^spellbook%-") and { width = 1 } or nil end }
    _G.ScrollUtil.InitScrollFrameWithScrollBar = function(scrollFrame, scrollBar)
        scrollFrame.scrollBar = scrollBar
        scrollFrame:SetScript("OnScrollRangeChanged", function() end)
    end
    _G.ScrollUtil.AddManagedScrollBarVisibilityBehavior = function() end
end

-- ScrollBox, as far as the journal uses it. Every element gets its own row (no virtualization),
-- created through the view's initializer like the client does. Call before Stubs.Login().
function Stubs.InstallScrollBox()
    _G.CreateScrollBoxListLinearView = function()
        local view = {}
        function view:SetElementExtent(extent) self.extent = extent end
        function view:SetElementInitializer(frameType, initializer) self.frameType, self.initializer = frameType, initializer end
        return view
    end
    _G.CreateDataProvider = function(list)
        local provider = { items = {} }
        for i, item in ipairs(list or {}) do provider.items[i] = item end
        return provider
    end
    _G.ScrollBoxConstants = { RetainScrollPosition = 1, AlignNearest = 2 }
    _G.ScrollUtil = {
        InitScrollBoxListWithScrollBar = function(scrollBox, _, view)
            scrollBox.rows = {}
            function scrollBox:SetDataProvider(provider)
                for _, row in ipairs(self.rows) do row:Hide() end
                self.rows = {}
                for _, element in ipairs(provider.items) do
                    local row = CreateFrame(view.frameType, nil, self)
                    self.rows[#self.rows + 1] = row
                    view.initializer(row, element)
                end
            end
            function scrollBox:ForEachFrame(fn)
                for _, row in ipairs(self.rows) do fn(row) end
            end
            function scrollBox:ScrollToElementData(element) self.scrolledTo = element end
        end,
    }
end

-- opts: now, guid, name, realm, level, interface, accountDB, charDB, footstepsDB, locale, unknownEvents
function Stubs.Install(opts)
    opts = opts or {}
    state = {
        now = opts.now or os.time({ year = 2026, month = 10, day = 3, hour = 12 }),
        frames = {},
        timers = {},
        printed = {},
        level = opts.level or 10,
        unknownEvents = opts.unknownEvents or {},
        instance = { id = 1, type = "none", difficulty = 0, name = "Kalimdor" },
        group = {},
        professions = {},
        spellNames = {},
        spellIcons = {},
        itemNames = {},
        itemClasses = {},
        requestedItems = {},
        questTitles = {},
        cvars = {},
        tickers = {},
    }
    Stubs.state = state
    for name in pairs(Stubs.namedFrames) do
        _G[name] = nil
    end

    _G.unpack = _G.unpack or table.unpack
    _G.tinsert = table.insert
    _G.time = function(t)
        if t then return os.time(t) end
        return state.now
    end
    _G.date = os.date
    _G.issecretvalue = function(value) return value == Stubs.SECRET end
    _G.GetLocale = function() return opts.locale or "enUS" end
    _G.GetBuildInfo = function() return "1.60.1", "70009", "Oct 1 2026", opts.interface or 16001 end
    _G.WOW_PROJECT_ID, _G.WOW_PROJECT_MAINLINE = 1, 1
    installUnits(opts)
    installWorld()
    _G.C_Timer = {
        After = function(seconds, fn)
            state.timers[#state.timers + 1] = { at = state.now + seconds, fn = fn }
        end,
        -- Fires once per Advance at most; advance in steps of `seconds` to see every tick.
        NewTicker = function(seconds, fn)
            local ticker = { cancelled = false }
            function ticker:Cancel() self.cancelled = true end
            local function schedule()
                state.timers[#state.timers + 1] = { at = state.now + seconds, fn = function()
                    if ticker.cancelled then return end
                    fn(ticker)
                    if not ticker.cancelled then schedule() end
                end }
            end
            schedule()
            state.tickers[#state.tickers + 1] = ticker
            return ticker
        end,
    }
    _G.C_AddOns = nil
    _G.C_EventUtils = nil
    _G.CreateFrame = newFrame
    _G.UIParent = newFrame()
    _G.DEFAULT_CHAT_FRAME = { AddMessage = function(_, message) state.printed[#state.printed + 1] = message end }
    _G.geterrorhandler = function() return function() end end
    _G.SlashCmdList = {}
    _G.UISpecialFrames = {}
    _G.Settings = nil
    _G.LibStub = nil
    _G.CreateScrollBoxListLinearView, _G.CreateDataProvider, _G.ScrollUtil, _G.ScrollBoxConstants = nil, nil, nil, nil
    _G.C_XMLUtil, _G.C_Texture = nil, nil
    _G.MapCanvasDataProviderMixin, _G.CreateFromMixins, _G.OpenWorldMap, _G.MenuUtil = nil, nil, nil, nil
    _G.PanelTemplates_SetNumTabs, _G.PanelTemplates_SetTab, _G.StaticPopup_Show, _G.debugprofilestop = nil, nil, nil, nil
    _G.WayscribeDB = opts.accountDB
    _G.WayscribeCharDB = opts.charDB
    _G.WayscribeFootstepsDB = opts.footstepsDB
end

-- The default world map as far as Footsteps uses it: a MapCanvas with data providers, showing
-- map 1412 on a 1000 x 668 canvas. Call before Stubs.Login().
function Stubs.InstallWorldMap()
    local map = newFrame("Frame", "WorldMapFrame")
    map.shown = false
    map.providers = {}
    map.mapID = 1412
    map.canvasScale = 1
    local canvas = newFrame("Frame")
    canvas:SetSize(1000, 668)
    map.canvas = canvas
    map.ScrollContainer = newFrame("Frame")
    function map:GetCanvas() return canvas end
    function map:GetCanvasScale() return self.canvasScale end
    function map:GetMapID() return self.mapID end
    function map:SetMapID(mapID)
        self.mapID = mapID
        for _, provider in ipairs(self.providers) do provider:OnMapChanged() end
    end
    function map:AddDataProvider(provider)
        self.providers[#self.providers + 1] = provider
        provider:OnAdded(self)
        if self.shown then provider:RefreshAllData() end
    end
    function map:Show()
        if self.shown then return end
        self.shown = true
        for _, provider in ipairs(self.providers) do
            provider:OnShow()
            provider:RefreshAllData(true)
        end
    end
    function map:Hide()
        if not self.shown then return end
        self.shown = false
        for _, provider in ipairs(self.providers) do provider:OnHide() end
    end
    function map:Zoom(scale)
        self.canvasScale = scale
        for _, provider in ipairs(self.providers) do provider:OnCanvasScaleChanged() end
    end
    _G.MapCanvasDataProviderMixin = {
        OnAdded = function(self, owner) self.owningMap = owner end,
        GetMap = function(self) return self.owningMap end,
        OnMapChanged = function(self) self:RefreshAllData() end,
        OnShow = function() end,
        OnHide = function() end,
        RemoveAllData = function() end,
        RefreshAllData = function() end,
        OnCanvasScaleChanged = function() end,
    }
    _G.CreateFromMixins = function(...)
        local object = {}
        for i = 1, select("#", ...) do
            for key, value in pairs((select(i, ...))) do object[key] = value end
        end
        return object
    end
    _G.OpenWorldMap = function(mapID)
        map:Show()
        if mapID then map:SetMapID(mapID) end
    end
    return map
end

-- Lua files in TOC order; embeds.xml (the libraries) is skipped, like a copy without Libs.
function Stubs.TocFiles()
    local files = {}
    for rawLine in io.lines("Wayscribe.toc") do
        local line = rawLine:gsub("%s+$", "")
        if line ~= "" and not line:find("^#") and line:find("%.lua$") then
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

-- Where the player is: Stubs.SetInstance(389, "party", "Ragefire Chasm"); no arguments = outdoors.
function Stubs.SetInstance(id, instanceType, name, difficulty)
    if not id then
        state.instance = { id = 1, type = "none", difficulty = 0, name = "Kalimdor" }
    else
        state.instance = { id = id, type = instanceType, difficulty = difficulty or 1, name = name }
    end
end

-- Where the player stands: continent and world yards; no arguments = no position (instances).
function Stubs.SetPosition(continent, x, y)
    state.position = continent and { c = continent, x = x, y = y } or nil
end

function Stubs.SetTaxi(onTaxi) state.onTaxi = onTaxi end
-- The map C_Map.GetBestMapForUnit reports (default 1411), and GetSubZoneText (default "").
function Stubs.SetBestMap(mapID) state.bestMap = mapID end
function Stubs.SetSubZone(name) state.subZone = name end
function Stubs.SetDead(dead) state.dead = dead end

-- Group members other than the player: list of { guid, name, realm, class }.
function Stubs.SetGroup(members) state.group = members end

-- Learned professions: list of { skillLine, name, rank, max } (slots prof1, prof2).
function Stubs.SetProfessions(list) state.professions = list end

-- An open loot window: { source = guid, items = { { id = itemID, quantity = n }, ... } } or nil.
function Stubs.SetLoot(loot) state.loot = loot end

-- Loots one slot the way the client does: the slot empties, then LOOT_SLOT_CLEARED fires.
function Stubs.LootSlot(slot)
    state.loot.items[slot].looted = true
    Stubs.Fire("LOOT_SLOT_CLEARED", slot)
end

-- ADDON_LOADED -> PLAYER_LOGIN -> PLAYER_ENTERING_WORLD, as on a real login or /reload.
function Stubs.Login(reload)
    Stubs.Fire("ADDON_LOADED", "Wayscribe")
    Stubs.Fire("PLAYER_LOGIN")
    Stubs.Fire("PLAYER_ENTERING_WORLD", not reload, reload == true)
end

-- Logout, then load a fresh copy of the addon with exactly what the client would have saved.
-- The world (instance, group, professions) stays as it was, like on a real /reload.
-- opts.setup(ns) runs after the files are loaded and before the login, e.g. to change StaticData.
function Stubs.Relog(opts, reload)
    local serialize = require("serialize")
    Stubs.Fire("PLAYER_LOGOUT")
    local saved = {
        accountDB = serialize.RoundTrip(_G.WayscribeDB),
        charDB = serialize.RoundTrip(_G.WayscribeCharDB),
        footstepsDB = serialize.RoundTrip(_G.WayscribeFootstepsDB),
    }
    local world = {
        instance = state.instance, group = state.group, professions = state.professions,
        spellNames = state.spellNames, itemNames = state.itemNames, itemClasses = state.itemClasses,
        questTitles = state.questTitles, cvars = state.cvars, position = state.position,
        onTaxi = state.onTaxi, dead = state.dead, subZone = state.subZone, bestMap = state.bestMap,
        spellIcons = state.spellIcons,
    }
    opts = opts or {}
    for key, value in pairs(saved) do
        if opts[key] == nil then opts[key] = value end
    end
    opts.now = opts.now or state.now
    opts.level = opts.level or state.level
    Stubs.Install(opts)
    for key, value in pairs(world) do state[key] = value end
    local ns = {}
    for _, file in ipairs(Stubs.TocFiles()) do
        assert(loadfile(file))("Wayscribe", ns)
    end
    Stubs.ns = ns
    if opts.setup then opts.setup(ns) end
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
