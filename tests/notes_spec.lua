local T = require("testlib")
local Stubs = require("wow_stubs")
local describe, it = T.describe, T.it

local GUID = "Player-1-0000AAAA"
local WIDTH, HEIGHT = 1000, 668 -- the stub map's canvas

-- opts.map: with the world map; opts.scrollBox = false: a client without ScrollBox.
local function start(opts)
    opts = opts or {}
    local ns = Stubs.LoadAddon(opts)
    local map = opts.map and Stubs.InstallWorldMap() or nil
    if opts.scrollBox ~= false then Stubs.InstallScrollBox() end
    Stubs.Login()
    return ns, map
end

-- A place on map 1412 (u, v) in world yards.
local function placeOn(u, v)
    local x, y = Stubs.MapToWorld(1412, u, v)
    return { c = 1, x = x, y = y, map = 1412 }
end

-- Runs fn with Elwynn Forest (and the Eastern Kingdoms above it) among the stub's maps, named
-- like a German client names them.
local function withElwynn(fn)
    Stubs.MAPS[1415] = { name = "Östliche Königreiche", continent = 0, top = 4000, left = 4000, width = 12000,
        height = 9000, parent = 947, type = 2 }
    Stubs.MAPS[1429] = { name = "Wald von Elwynn", continent = 0, top = -7000, left = 1500, width = 3500,
        height = 2300, parent = 1415, type = 3 }
    local ok, err = pcall(fn)
    Stubs.MAPS[1415], Stubs.MAPS[1429] = nil, nil
    if not ok then error(err, 0) end
end

-- The default popups as far as notes use them: each popup shown gets a dialog with an edit box.
local function installPopups()
    local shown = {}
    _G.StaticPopupDialogs = {}
    _G.StaticPopup_Show = function(which, arg1, arg2, data)
        local info = StaticPopupDialogs[which]
        local dialog = CreateFrame("Frame")
        dialog.EditBox = CreateFrame("EditBox", nil, dialog)
        function dialog:GetEditBox() return self.EditBox end
        shown[#shown + 1] = { which = which, info = info, data = data, dialog = dialog, text = info.text:format(arg1, arg2) }
        if info.OnShow then info.OnShow(dialog, data) end
    end
    return shown
end

local function removePopups()
    _G.StaticPopupDialogs, _G.StaticPopup_Show = nil, nil
end

local function installTooltip()
    local tooltip = { lines = {} }
    function tooltip:SetOwner() self.lines = {} end
    function tooltip:SetText(text) self.lines[#self.lines + 1] = text end
    function tooltip:AddLine(text) self.lines[#self.lines + 1] = text end
    function tooltip:Show() end
    function tooltip:Hide() end
    _G.GameTooltip = tooltip
    return tooltip
end

-- What the player types: the text, then the box's own OnTextChanged.
local function typeInto(box, text)
    box:SetText(text)
    box.scripts.OnTextChanged(box, true)
end

-- The notes tab's list, top to bottom: "title | date".
local function rows(ns)
    local texts = {}
    local ui = ns.NotesView.ui
    for _, row in ipairs(ui.scrollBox and ui.scrollBox.rows or ui.fixedRows) do
        if row:IsShown() then texts[#texts + 1] = row.label:GetText() .. " | " .. row.detail:GetText() end
    end
    return texts
end

local function rowFor(ns, id)
    for _, row in ipairs(ns.NotesView.ui.scrollBox.rows) do
        if row.noteId == id then return row end
    end
end

-- The notes' markers shown on the map.
local function markers(ns)
    local view, list = ns.NotesMap.view, {}
    for i = 1, view.used do
        if view.frames[i]:IsShown() then list[#list + 1] = view.frames[i] end
    end
    return list
end

local function near(actual, expected, what)
    if math.abs(actual - expected) > 0.5 then
        error(what .. ": expected " .. expected .. ", got " .. actual, 2)
    end
end

describe("writing notes", function()
    it("adds, edits and deletes notes, newest first, and keeps them through a relog", function()
        local ns = start()
        local changed = {}
        ns.Bus:On("NOTES_CHANGED", changed, function(_, id) changed[#changed + 1] = id end)
        local first = ns.Notes:Add({ title = "Buy linen", text = "For First Aid" })
        Stubs.Advance(60)
        local second = ns.Notes:Add({ title = "Copper route" })
        T.eq(first.id, 1)
        T.eq(second.id, 2)
        T.eq(first.created, first.edited)
        local titles = {}
        for i, note in ipairs(ns.Notes:GetAll()) do titles[i] = note.title end
        T.same(titles, { "Copper route", "Buy linen" })

        Stubs.Advance(60)
        T.eq(ns.Notes:Update(1, { text = "For First Aid, 20 of them" }).edited, Stubs.Now())
        T.eq(ns.Notes:Get(1).created, first.created, "written when it was written")
        local edited = ns.Notes:Get(1).edited
        Stubs.Advance(60)
        ns.Notes:Update(1, { text = "For First Aid, 20 of them" })
        T.eq(ns.Notes:Get(1).edited, edited, "the same text changes nothing")
        T.truthy(ns.Notes:Delete(2))
        T.falsy(ns.Notes:Delete(2))
        T.same(changed, { 1, 2, 1, 2 })

        ns = Stubs.Relog()
        T.eq(ns.Notes:Count(), 1)
        T.eq(ns.Notes:Get(1).text, "For First Aid, 20 of them")
        T.eq(ns.Notes:Add({ title = "Next" }).id, 3, "ids are never reused")
        T.eq(#ns.Log:GetEntries(), 0)
    end)

    it("caps what it stores and refuses what a saved file can't hold", function()
        local ns = start()
        local title = string.rep("ä", ns.Notes.TITLE_LETTERS * 3)
        local note = ns.Notes:Add({ title = title })
        T.eq(#note.title, ns.Notes.MAX_TITLE)
        T.eq(note.title, string.rep("ä", ns.Notes.MAX_TITLE / 2), "no letter cut in half")
        T.same({ ns.Notes:Add({ title = Stubs.SECRET }) }, { nil, "invalid note" })
        T.same({ ns.Notes:Add({ text = {} }) }, { nil, "invalid note" })
        T.same({ ns.Notes:Update(note.id, { title = 12 }) }, { nil, "invalid note" })
        T.eq(ns.Notes:Count(), 1)
    end)

    it("gives a note's markers one of the eight icons", function()
        local ns = start()
        local note = ns.Notes:Add({ title = "Herbs", icon = 99 })
        T.eq(note.icon, nil, "not an icon")
        ns.Notes:Update(note.id, { icon = 8 })
        T.eq(note.icon, 8)
        ns.Notes:Update(note.id, { icon = 0 })
        T.eq(note.icon, 8)
        T.eq(ns.Notes.IconTexture(8), "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8")
        T.eq(ns.Notes.IconTexture(nil), "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1")
    end)
end)

describe("/way lines", function()
    it("reads them the way websites write them", function()
        local ns = start()
        local parse = ns.Notes.ParseWay
        T.same(parse("/way 49.0 86.4"), { zone = "", x = 49, y = 86.4, label = "" })
        T.same(parse("/way Elwynn Forest 49.0 86.4 The Kaldorei"),
            { zone = "Elwynn Forest", x = 49, y = 86.4, label = "The Kaldorei" })
        T.same(parse("/WAY #1412 45,2 58,8 - under the tent"), { map = 1412, zone = "", x = 45.2, y = 58.8, label = "under the tent" })
        T.same(parse("3. Mulgore: /way 45.2, 58.8"), { zone = "", x = 45.2, y = 58.8, label = "" })
        T.same(parse("/way Mulgore, 45 58"), { zone = "Mulgore", x = 45, y = 58, label = "" })
        T.eq(parse("/way 49.0"), nil, "one number is no place")
        T.eq(parse("/way 149 20"), nil, "percent of the map")
        T.eq(parse("/waypoint 49 86"), nil)
        T.eq(parse("see https://example.org//way 49 86"), nil)
        T.eq(parse("Just text"), nil)
    end)

    it("puts each line on the map, in the zone named above it or where the player is", function()
        local ns = start()
        Stubs.SetBestMap(1412)
        local note = ns.Notes:Add({ title = "Hidden Books", text = table.concat({
            "The books of the new questline.",
            "/way Kalimdor 50.0 50.0 On the continent",
            "/way 52.3 41.0 In the zone above",
            "/way #1412 45.2 58.8",
            "/way Nowhere Land 10 10 An unknown zone",
            "/way 20 20 Below the unknown zone",
        }, "\n") })
        local places, unplaced = ns.Notes.PlacesOf(note)
        T.eq(#places, 3)
        T.eq(unplaced, 2)
        T.same({ places[1].map, places[2].map, places[3].map }, { 1414, 1414, 1412 })
        T.eq(places[1].label, "On the continent")
        T.eq(places[2].line, 3)
        T.falsy(places[2].assumed)
        local x, y = Stubs.MapToWorld(1414, 0.523, 0.41)
        near(places[2].x, x, "x")
        near(places[2].y, y, "y")
        T.same({ ns.Notes:Count() }, { 1, 1 })
        T.eq(#ns.Notes:GetPlaced(1), 3)
        T.eq(#ns.Notes:GetPlaced(0), 0)

        local here = ns.Notes:Add({ text = "/way 40 50" })
        local place = ns.Notes.PlacesOf(here)[1]
        T.eq(place.map, 1412, "where the player is")
        T.truthy(place.assumed)
        Stubs.SetBestMap(1411) -- a map without a place in the world, like a dungeon's
        T.same({ #ns.Notes.PlacesOf(here), select(2, ns.Notes.PlacesOf(here)) }, { 0, 1 })
    end)

    it("finds English zone names on a German client, and the client's own", function()
        withElwynn(function()
            local ns = start({ locale = "deDE" })
            local note = ns.Notes:Add({ text = "/way Elwynn Forest 49.0 86.4\n/way Wald von Elwynn 10 10\n/way mulgore 5 5" })
            local places = ns.Notes.PlacesOf(note)
            T.same({ places[1].map, places[2].map, places[3].map }, { 1429, 1429, 1412 })
            T.eq(ns.Notes.ZoneLabel(1429), "Wald von Elwynn", "lines are written in the client's language")
            T.eq(ns.Notes.WayLine(1429, 0.49, 0.864, "Buch"), "/way Wald von Elwynn 49.0 86.4 Buch")
        end)
    end)

    it("turns the place a first test build kept into a /way line", function()
        start()
        local place = placeOn(0.3, 0.6)
        WayscribeCharDB.notes = { seq = 1, list = {
            { id = 1, created = Stubs.Now(), edited = Stubs.Now(), title = "Herbs", text = "By the lake",
              c = 1, x = math.floor(place.x + 0.5), y = math.floor(place.y + 0.5), map = 1412, icon = 3 },
        } }
        local ns = Stubs.Relog(nil, true)
        local note = ns.Notes:Get(1)
        T.eq(note.text, "By the lake\n/way Mulgore 30.0 60.0")
        T.eq(note.c, nil)
        T.eq(note.map, nil)
        T.eq(note.icon, 3)
        T.eq(#ns.Notes.PlacesOf(note), 1)
    end)

    it("changes nothing while the journal is read-only", function()
        local ns = start()
        ns.Notes:Add({ title = "Kept" })
        ns.SetSafeMode("test reason")
        T.same({ ns.Notes:Add({ title = "New" }) }, { nil, "read-only" })
        T.same({ ns.Notes:Update(1, { title = "Changed" }) }, { nil, "read-only" })
        T.falsy(ns.Notes:Delete(1))
        T.eq(ns.Notes:Get(1).title, "Kept")
    end)

    it("starts every journal with an empty notebook, older ones too", function()
        start()
        T.same(WayscribeCharDB.notes, {})
        local older = Stubs.Copy(WayscribeCharDB)
        older.notes = nil
        local ns = Stubs.LoadAddon({ charDB = older, accountDB = WayscribeDB })
        Stubs.Login()
        T.same(WayscribeCharDB.notes, {})
        T.eq(ns.Notes:Count(), 0)
        T.eq(ns.safeMode, nil)
    end)
end)

describe("the notes tab", function()
    it("says how to start when there are no notes", function()
        local ns = start()
        ns.Slash:Handle("notes")
        T.truthy(ns.Journal.ui.frame:IsShown())
        T.eq(ns.Journal.state.tab, "notes")
        local ui = ns.NotesView.ui
        T.eq(ui.header:GetText(), "Tester's notes")
        T.truthy(ui.empty:IsShown())
        T.truthy(ui.empty:GetText():find("^No notes yet"))
        T.falsy(ui.editor:IsShown())
        T.same(rows(ns), {})
        T.eq(ns.Journal.ui.pageText:GetText(), "")
    end)

    it("starts a note, saves every keystroke and shows it in the list", function()
        local ns = start()
        ns.Journal:OpenNotes()
        local ui = ns.NotesView.ui
        ui.newButton:Click()
        T.eq(ns.Notes:Count(), 1)
        T.eq(Stubs.Focus(), ui.titleBox, "the cursor is in the title")
        T.truthy(ui.editor:IsShown())
        T.truthy(ui.titleHint.shown, "Untitled, until a title is typed")
        typeInto(ui.titleBox, "Copper route")
        T.falsy(ui.titleHint.shown)
        T.eq(ns.Notes:Get(1).title, "Copper route")
        ui.titleBox.scripts.OnEnterPressed(ui.titleBox)
        T.eq(Stubs.Focus(), ui.body, "Enter goes on to the text")
        Stubs.Advance(120)
        typeInto(ui.body, "Start at Red Cloud Mesa,\nfollow the river north.")
        T.eq(ns.Notes:Get(1).text, "Start at Red Cloud Mesa,\nfollow the river north.")
        Stubs.Advance(0) -- the coalesced redraw
        T.same(rows(ns), { "Copper route | Today" })
        T.eq(ui.subtitle:GetText(), "Written Saturday, October 3, 2026 · edited 12:02 PM")
        T.eq(ui.body:GetText(), "Start at Red Cloud Mesa,\nfollow the river north.", "never set again while written")
        T.falsy(ui.mapButton:IsShown(), "no place, no map")
        T.falsy(ui.icons[1]:IsShown())
        T.eq(#ns.Log:GetEntries(), 0)
    end)

    it("drops a note left blank, and keeps the rest", function()
        local ns = start()
        ns.Notes:Add({ title = "Kept" })
        ns.Journal:OpenNotes()
        local ui = ns.NotesView.ui
        ui.newButton:Click()
        T.eq(ns.Notes:Count(), 2)
        rowFor(ns, 1):Click()
        T.eq(ns.Notes:Count(), 1, "the blank one went")
        T.eq(ui.titleBox:GetText(), "Kept")
        ui.newButton:Click()
        ns.Journal.ui.frame:Hide()
        T.eq(ns.Notes:Count(), 1, "closing the journal drops it too")
        T.eq(Stubs.Focus(), nil, "and lets go of the keyboard")
    end)

    it("turns notes with the page buttons, page 1 the oldest", function()
        local ns = start()
        ns.Notes:Add({ title = "First" })
        Stubs.Advance(24 * 3600)
        ns.Notes:Add({ title = "Second" })
        ns.Journal:OpenNotes()
        local ui, journal = ns.NotesView.ui, ns.Journal.ui
        T.same(rows(ns), { "Second | Today", "First | Yesterday" })
        T.eq(ui.titleBox:GetText(), "Second")
        T.eq(journal.pageText:GetText(), "Page 2/2")
        T.falsy(journal.newer:IsEnabled())
        T.eq(journal.older.tooltip, "Older note")
        journal.older:Click()
        T.eq(ui.titleBox:GetText(), "First")
        T.eq(journal.pageText:GetText(), "Page 1/2")
        T.falsy(journal.older:IsEnabled())
        journal.newer:Click()
        T.eq(ui.titleBox:GetText(), "Second")
    end)

    it("deletes a note after asking", function()
        local ns = start()
        local popups = installPopups()
        ns.Notes:Add({ title = "Old" })
        Stubs.Advance(60)
        ns.Notes:Add({ title = "Mageroyal spot", text = "By the lake" })
        ns.Journal:OpenNotes()
        ns.NotesView.ui.deleteButton:Click()
        T.eq(#popups, 1)
        T.eq(popups[1].text, "Delete the note \"Mageroyal spot\"?\n\nThis cannot be undone.")
        T.eq(ns.Notes:Count(), 2, "nothing yet")
        popups[1].info.OnAccept(popups[1].dialog, popups[1].data)
        T.eq(ns.Notes:Count(), 1)
        T.eq(ns.NotesView.ui.titleBox:GetText(), "Old", "the next one opens")
        removePopups()
    end)

    it("can only be read while the journal is read-only", function()
        local ns = start()
        ns.Notes:Add({ title = "Kept" })
        ns.SetSafeMode("test reason")
        ns.Journal:OpenNotes()
        local ui = ns.NotesView.ui
        T.falsy(ui.newButton:IsEnabled())
        T.falsy(ui.titleBox:IsEnabled())
        T.falsy(ui.body:IsEnabled())
        T.falsy(ui.deleteButton:IsEnabled())
        T.eq(ui.titleBox:GetText(), "Kept")
    end)

    it("works without a ScrollBox", function()
        local ns = start({ scrollBox = false })
        ns.Notes:Add({ title = "One" })
        ns.Notes:Add({ title = "Two" })
        ns.Journal:OpenNotes()
        T.same(rows(ns), { "Two | Today", "One | Today" })
    end)

    it("writes the player's zone into a /way line without one when the note is left", function()
        local ns = start()
        Stubs.SetBestMap(1412)
        ns.Notes:Add({ title = "Kept" })
        ns.Journal:OpenNotes()
        local ui = ns.NotesView.ui
        ui.newButton:Click()
        local written = "Books\n/way 49.0 86.4 First\n/way Kalimdor 10 10\n/way 20 20 Below Kalimdor"
        typeInto(ui.body, written)
        T.eq(ns.Notes:Get(2).text, written, "not while it's being written")
        Stubs.Advance(0)
        T.eq(ui.subtitle:GetText(), "Written Saturday, October 3, 2026 · 3 places on the map")
        rowFor(ns, 1):Click()
        local filled = "Books\n/way Mulgore 49.0 86.4 First\n/way Kalimdor 10 10\n/way 20 20 Below Kalimdor"
        T.eq(ns.Notes:Get(2).text, filled, "only the line with no zone above")
        rowFor(ns, 2):Click()
        T.eq(ui.body:GetText(), filled)
        typeInto(ui.body, filled .. "\n/way 30 30")
        ui.body.scripts.OnEditFocusLost(ui.body)
        T.eq(ns.Notes:Get(2).text, filled .. "\n/way 30 30", "below Kalimdor, so in Kalimdor")
        typeInto(ui.body, "/way 30 30")
        ui.body.scripts.OnEditFocusLost(ui.body)
        T.eq(ui.body:GetText(), "/way Mulgore 30 30", "also when the text lets go of the keyboard")
        typeInto(ui.body, "/way 40 40")
        ns = Stubs.Relog(nil, true)
        T.eq(ns.Notes:Get(2).text, "/way Mulgore 40 40", "and at a /reload with the journal open")
    end)

    it("counts a note's places, picks their icon and opens the map at the first", function()
        local ns, map = start({ map = true })
        ns.Notes:Add({ title = "Herbs", text = "/way Mulgore 40.0 50.0\n/way Mulgore 60 50\n/way Atlantis 1 1" })
        ns.Journal:OpenNotes(1)
        local ui = ns.NotesView.ui
        T.eq(ui.subtitle:GetText(), "Written Saturday, October 3, 2026 · 2 places on the map · 1 /way line not found")
        T.truthy(ui.iconLabel.shown)
        T.truthy(ui.icons[8]:IsShown())
        ui.icons[3]:Click()
        T.eq(ns.Notes:Get(1).icon, 3)
        T.truthy(ui.mapButton:IsShown())
        map.mapID = 1414
        ui.mapButton:Click()
        T.truthy(map:IsShown())
        T.eq(map:GetMapID(), 1412, "the map its line names")
        T.eq(#markers(ns), 2)
        T.eq(markers(ns)[1].icon.file, "Interface\\TargetingFrame\\UI-RaidTargetingIcon_3")
    end)
end)

describe("notes on the map", function()
    it("Alt+click starts a note there, named after the zone", function()
        local ns, map = start({ map = true })
        local popups = installPopups()
        map:Show()
        T.falsy(map:ClickCanvas("LeftButton", 0.4, 0.5), "a plain click zooms in, as always")
        Stubs.SetKeys({ alt = true })
        T.truthy(map:ClickCanvas("LeftButton", 0.4, 0.5))
        T.eq(#popups, 1)
        T.eq(popups[1].text, "A new note on the map. Its title:")
        local box = popups[1].dialog:GetEditBox()
        T.eq(box:GetText(), "Mulgore", "the zone's name to begin with")
        T.eq(ns.Notes:Count(), 0, "nothing until it's saved")
        box:SetText("  Peacebloom  ")
        popups[1].info.EditBoxOnEnterPressed(box, popups[1].data)
        local note = ns.Notes:Get(1)
        T.eq(note.title, "Peacebloom")
        T.eq(note.text, "/way Mulgore 40.0 50.0", "the spot as a /way line")
        local list = markers(ns)
        T.eq(#list, 1, "it shows at once")
        near(list[1].lastPoint[4], 0.4 * WIDTH, "x")
        near(list[1].lastPoint[5], -0.5 * HEIGHT, "y")
        T.eq(list[1].width, 18)

        Stubs.SetKeys({ alt = true, shift = true })
        T.falsy(map:ClickCanvas("LeftButton", 0.4, 0.5), "other modifiers are someone else's")
        Stubs.SetKeys({ alt = true })
        T.falsy(map:ClickCanvas("RightButton", 0.4, 0.5))
        map:SetMapID(1414)
        local u, v = Stubs.WorldToMap(1414, Stubs.MapToWorld(1412, 0.3, 0.6))
        map:ClickCanvas("LeftButton", u, v)
        popups[2].info.OnAccept(popups[2].dialog, popups[2].data)
        T.eq(ns.Notes:Get(2).text, "/way Mulgore 30.0 60.0", "on the continent: the zone there")
        map:SetMapID(947)
        T.truthy(map:ClickCanvas("LeftButton", 0.5, 0.5))
        T.eq(#popups, 2, "no note on the world map")
        T.truthy(Stubs.Printed()[#Stubs.Printed()]:find("zone or continent map"))
        Stubs.SetKeys()
        removePopups()
    end)

    it("adds the note right away where the client has no popups", function()
        local ns, map = start({ map = true })
        map:Show()
        Stubs.SetKeys({ alt = true })
        map:ClickCanvas("LeftButton", 0.2, 0.3)
        T.eq(ns.Notes:Get(1).title, "Mulgore")
        Stubs.SetKeys()
    end)

    it("draws a marker for every /way line, on zone and continent maps, with the note on mouseover", function()
        local ns, map = start({ map = true })
        local place = placeOn(0.3, 0.6)
        ns.Notes:Add({ title = "Hidden Books", icon = 4, text = table.concat({
            "Peacebloom by the river.", "/way Mulgore 30.0 60.0 The Kaldorei", "/way Mulgore 70 20",
        }, "\n") })
        ns.Notes:Add({ title = "No place" })
        map:Show()
        local list = markers(ns)
        T.eq(#list, 2)
        T.eq(list[1].icon.file, "Interface\\TargetingFrame\\UI-RaidTargetingIcon_4")
        near(list[2].lastPoint[4], 0.7 * WIDTH, "x")
        local tooltip = installTooltip()
        list[1].scripts.OnEnter(list[1])
        T.same(tooltip.lines, {
            "The Kaldorei", "Hidden Books", "Peacebloom by the river.", "Mulgore 30.0 60.0",
            "Click to open the note in the journal.",
        })
        list[2].scripts.OnEnter(list[2])
        T.eq(tooltip.lines[1], "Hidden Books", "the note's title without a label")
        _G.GameTooltip = nil
        map:SetMapID(1414)
        list = markers(ns)
        T.eq(#list, 2, "on the continent too")
        local u, v = Stubs.WorldToMap(1414, place.x, place.y)
        near(list[1].lastPoint[4], u * WIDTH, "x")
        near(list[1].lastPoint[5], -v * HEIGHT, "y")
        map:Zoom(2)
        T.eq(list[1].width, 9, "the same size on screen")
        T.eq(#ns.Log:GetEntries(), 0)
    end)

    it("opens the note in the journal from its marker", function()
        local ns, map = start({ map = true })
        ns.Notes:Add({ title = "Other" })
        ns.Notes:Add({ title = "Herbs", text = "/way Mulgore 30 60" })
        ns.Journal:Open()
        map:Show()
        markers(ns)[1]:Click()
        T.eq(ns.Journal.state.tab, "notes")
        T.eq(ns.NotesView.ui.titleBox:GetText(), "Herbs")
    end)

    it("hides the markers on request, but shows the note's the journal asks for", function()
        local ns, map = start({ map = true })
        ns.Notes:Add({ title = "Herbs", text = "/way Mulgore 30 60\n/way Mulgore 35 60" })
        ns.Notes:Add({ title = "Ore", text = "/way Mulgore 50 50" })
        map:Show()
        T.eq(#markers(ns), 3)
        ns.NotesMap:SetShownOnMap(false)
        T.eq(#markers(ns), 0)
        T.eq(WayscribeDB.settings.notesOnMap, false)
        Stubs.SetCombat(true)
        T.falsy(ns.NotesMap:ShowNote(1))
        T.truthy(Stubs.Printed()[#Stubs.Printed()]:find("combat"))
        Stubs.SetCombat(false)
        T.truthy(ns.NotesMap:ShowNote(1))
        local list = markers(ns)
        T.eq(#list, 2, "all of the note's places")
        T.same({ list[1].noteId, list[2].noteId }, { 1, 1 })
        T.eq(list[1].width, 27, "a little larger")
        map:Hide()
        map:Show()
        T.eq(#markers(ns), 0, "until the map closes")
        ns.NotesMap:SetShownOnMap(true)
        T.eq(WayscribeDB.settings.notesOnMap, nil, "the default isn't stored")
        T.eq(#markers(ns), 3)
    end)

    it("is switched in the map button's menu", function()
        local ns, map = start({ map = true })
        local checkbox
        local root = {}
        function root:CreateRadio() end
        function root:CreateDivider() end
        function root:CreateCheckbox(label, isChecked, toggle) checkbox = { label = label, isChecked = isChecked, toggle = toggle } end
        _G.MenuUtil = { CreateContextMenu = function(_, generator) generator(nil, root) end }
        map:Show()
        ns.FootstepsMap.button:Click()
        T.eq(checkbox.label, "My notes")
        T.truthy(checkbox.isChecked())
        checkbox.toggle()
        T.falsy(ns.NotesMap:IsShownOnMap())
        _G.MenuUtil = nil
    end)
end)

describe("/ws mark", function()
    it("marks where the player stands, titled after the subzone or as given", function()
        local ns = start()
        local place = placeOn(0.5, 0.5)
        Stubs.SetPosition(1, place.x + 0.4, place.y)
        Stubs.SetBestMap(1412)
        Stubs.SetSubZone("Red Cloud Mesa")
        ns.Slash:Handle("mark")
        local note = ns.Notes:Get(1)
        T.eq(note.title, "Red Cloud Mesa")
        T.eq(note.text, "/way Mulgore 50.0 50.0")
        T.eq(Stubs.Printed()[#Stubs.Printed()]:match(": (.*)$"),
            "The note \"Red Cloud Mesa\" is on the map now. /ws notes opens your notes.")
        ns.Slash:Handle("mark Rare Spawn")
        T.eq(ns.Notes:Get(2).title, "Rare Spawn", "as typed")
        Stubs.SetSubZone(nil)
        ns.Slash:Handle("mark")
        T.eq(ns.Notes:Get(3).title, "Mulgore")
    end)

    it("says so where there is no position", function()
        local ns = start()
        Stubs.SetPosition()
        ns.Slash:Handle("mark")
        T.eq(ns.Notes:Count(), 0)
        T.truthy(Stubs.Printed()[#Stubs.Printed()]:find("no position to mark"))
    end)

    it("/ws stats counts them", function()
        local ns = start()
        ns.Notes:Add({ title = "Plain" })
        ns.Notes:Add({ title = "Placed", text = "/way Mulgore 10 10\n/way Mulgore 20 20" })
        ns.Slash:Handle("stats")
        local found
        for _, line in ipairs(Stubs.Printed()) do
            found = found or line:find("Notes: 2, 1 of them on the map.", 1, true)
        end
        T.truthy(found)
    end)
end)

describe("notes and the journal's file", function()
    local function makeBackup(ns, opts)
        local text, header
        ns.Backup:Make(opts or {}, function(result, detail) text, header = result, detail end)
        T.truthy(text, tostring(header))
        return text, header
    end

    local function readBackup(ns, text)
        local found, reason
        ns.Backup:Read(text, function(result, detail) found, reason = result, detail end)
        return found, reason
    end

    it("go into a backup and come back with the journal", function()
        local ns = start()
        ns.Store:Append("LEVEL_UP", { level = 11 })
        ns.Notes:Add({ title = "Herbs", text = "Peacebloom | Silverleaf\nby the river\n/way Mulgore 10 20", icon = 3 })
        local text, header = makeBackup(ns)
        T.eq(header.notes, 1)
        ns.Slash:Handle("backup")
        local texts = Stubs.Texts(_G.WayscribeBackupFrame)
        T.truthy(texts[4]:find("^1 entry on 1 day, 0 trails, 1 note · "), texts[4])
        local saved = Stubs.Copy(WayscribeCharDB.notes)

        ns = Stubs.LoadAddon({ guid = "Player-1-0000BBBB" })
        Stubs.Login()
        local found = readBackup(ns, text)
        T.truthy(found)
        T.truthy(ns.Backup:Plan(found).journal)
        T.truthy(ns.Backup:Restore(found))
        Stubs.Relog(nil, true)
        T.same(WayscribeCharDB.notes, saved)
        T.eq(WayscribeDB.characters["Player-1-0000BBBB"].notes, 1, "the canary vouches for them")
    end)

    local function payloadOf(ns, text)
        local _, pos = ns.Backup.Deserialize(text, 6)
        return ns.Backup.Deserialize(text, pos)
    end

    -- The case a backup is made for: the journal's file didn't load. Notes and markers come back
    -- exactly, and work: listed in the tab, drawn on the map, new ids after the restored ones.
    it("brings notes and markers back into a journal that didn't load, ready to use", function()
        local ns = start()
        ns.Store:Append("LEVEL_UP", { level = 11 })
        ns.Notes:Add({ title = "Buy linen", text = "Für Erste Hilfe: 20× Leinenstoff\n|cffff0000not a color|r" })
        ns.Notes:Delete(ns.Notes:Add({ title = "Gone" }).id)
        ns.Notes:Add({ title = "Mageroyal", icon = 5, text = "By the lake\n/way Mulgore 30.0 60.0\n/way Mulgore 31 60 Upstairs" })
        local text, header = makeBackup(ns)
        T.eq(header.notes, 2)
        Stubs.Fire("PLAYER_LOGOUT")
        local saved = Stubs.Copy(WayscribeCharDB.notes)
        T.eq(saved.seq, 3)

        ns = Stubs.LoadAddon({ accountDB = Stubs.Copy(WayscribeDB) })
        Stubs.Login()
        T.eq(ns.Schema.safeKind, "missing")
        local found = readBackup(ns, text)
        local plan = ns.Backup:Plan(found)
        T.truthy(plan.journal and plan.missing)
        T.truthy(ns.Backup:Restore(found))
        local map
        ns = Stubs.Relog({ setup = function() map = Stubs.InstallWorldMap() end }, true)
        T.eq(ns.safeMode, nil)
        T.same(WayscribeCharDB.notes, saved, "word for word, the deleted one's id included")
        T.same({ ns.Notes:Count() }, { 2, 1 })

        map:Show()
        local list = markers(ns)
        T.eq(#list, 2, "the markers are on the map again")
        T.eq(list[1].icon.file, "Interface\\TargetingFrame\\UI-RaidTargetingIcon_5")
        ns.Journal:OpenNotes()
        T.same(rows(ns), { "Mageroyal | Today", "Buy linen | Today" })
        T.eq(ns.Notes:Add({ title = "After" }).id, 4, "no id is issued twice")
        Stubs.Fire("PLAYER_LOGOUT")
        T.eq(WayscribeDB.characters[GUID].notes, 4)
        for _, entry in ipairs(ns.Log:GetEntries()) do
            T.eq(entry.message, "missing: the account file counted 1 entries and 3 notes", "only the guard's own warning")
        end
    end)

    it("holds the notes as they were when the backup started, while they change", function()
        local ns = start()
        for day = 0, 99 do
            for i = 1, 3 do
                ns.Store:Append("LEVEL_UP", { level = 10 + i }, { ts = Stubs.Now() - day * 24 * 3600 - i })
            end
        end
        ns.Notes:Add({ title = "Before", text = "As it was" })
        local expected = makeBackup(ns)
        local clock = 0
        _G.debugprofilestop = function()
            clock = clock + 1
            return clock
        end
        local text
        ns.Backup:Make({}, function(result) text = result end)
        T.eq(text, nil, "not done within one frame")
        local frame, frames = ns.Backup.frames.make, 1
        while frame:GetScript("OnUpdate") do
            if frames == 2 then
                ns.Notes:Update(1, { title = "Changed", text = "Written during the backup" })
                ns.Notes:Add({ title = "Added during the backup", c = 1, x = 1, y = 2 })
            end
            frame:GetScript("OnUpdate")()
            frames = frames + 1
        end
        _G.debugprofilestop = nil
        T.truthy(frames > 2, "spread over " .. frames .. " frames")
        T.same(payloadOf(ns, text).journal.notes, payloadOf(ns, expected).journal.notes)
        T.eq(payloadOf(ns, text).journal.notes.list[1].title, "Before")
        T.eq(#payloadOf(ns, text).journal.notes.list, 1)
    end)

    it("restores an older backup without notes into an empty notebook", function()
        local ns = start()
        ns.Store:Append("LEVEL_UP", { level = 11 })
        ns.charDB.notes = nil -- what 0.6 wrote
        local text, header = makeBackup(ns)
        T.eq(header.notes, nil)
        T.eq(payloadOf(ns, text).journal.notes, nil)
        ns = Stubs.LoadAddon({ guid = "Player-1-0000BBBB" })
        Stubs.Login()
        T.truthy(ns.Backup:Restore(readBackup(ns, text)))
        ns = Stubs.Relog({ guid = "Player-1-0000BBBB" }, true)
        T.eq(ns.safeMode, nil)
        T.same(WayscribeCharDB.notes, {})
        T.eq(ns.Notes:Add({ title = "First" }).id, 1)
    end)

    it("won't restore over a journal with notes but no entries", function()
        local ns = start()
        ns.Store:Append("LEVEL_UP", { level = 11 })
        local text = makeBackup(ns, { trails = false })
        ns = Stubs.LoadAddon({ guid = "Player-1-0000BBBB" })
        Stubs.Login()
        ns.Notes:Add({ title = "Mine" })
        local found = readBackup(ns, text)
        local plan = ns.Backup:Plan(found)
        T.falsy(plan.journal)
        T.truthy(plan.refused:find("already has entries or notes"), plan.refused)
        T.falsy(ns.Backup:Restore(found))
        T.eq(ns.Notes:Get(1).title, "Mine")
    end)

    it("counts them in the canary, so a journal with only notes is guarded too", function()
        local ns = start()
        ns.Notes:Add({ title = "Only a note" })
        Stubs.Fire("PLAYER_LOGOUT")
        T.eq(WayscribeDB.characters[GUID].seq, 0)
        T.eq(WayscribeDB.characters[GUID].notes, 1)
        ns = Stubs.LoadAddon({ accountDB = require("serialize").RoundTrip(WayscribeDB) })
        Stubs.Login()
        T.eq(ns.Schema.safeKind, "missing")
        T.truthy(ns.safeMode:find("although it had 1 notes"), ns.safeMode)
        T.eq(ns.Log:GetEntries()[1].message, "missing: the account file counted 0 entries and 1 notes")
    end)

    it("go into the text export after the days", function()
        local ns = start()
        ns.Store:Append("LEVEL_UP", { level = 11 })
        ns.Notes:Add({ title = "Copper route", text = "Start at the mesa,\n\nthen north." })
        ns.Notes:Add({ title = "" })
        local text = ns.Export.BuildText("all")
        local tail = text:sub((text:find("\nNotes\n", 1, true)))
        T.eq(tail, table.concat({
            "", "Notes", "",
            "Copper route", "  Written Saturday, October 3, 2026", "  Start at the mesa,", "", "  then north.", "",
            "Untitled", "  Written Saturday, October 3, 2026", "", "",
        }, "\n"))
    end)

    it("are deleted by Reset, footsteps and journal with them", function()
        local ns = start()
        ns.Notes:Add({ title = "Gone" })
        T.truthy(ns.Schema:ResetCharacter())
        ns = Stubs.Relog(nil, true)
        T.eq(ns.Notes:Count(), 0)
    end)
end)

describe("notes in German", function()
    it("names the tab, the page and the marker in German", function()
        local ns, map = start({ locale = "deDE", map = true })
        ns.Notes:Add({ title = "", text = "/way Mulgore 30 60" })
        Stubs.Advance(2 * 3600)
        ns.Notes:Update(1, { text = "Kräuter\n/way Mulgore 30 60" })
        ns.Journal:OpenNotes()
        local ui = ns.NotesView.ui
        T.eq(ui.header:GetText(), "Notizen von Tester")
        T.eq(ui.subtitle:GetText(), "Geschrieben am Samstag, 3. Oktober 2026 · geändert um 14:00 · 1 Ort auf der Karte")
        T.same(rows(ns), { "Ohne Titel | Heute" })
        Stubs.Advance(2 * 24 * 3600)
        ns.Journal:Refresh()
        T.eq(ui.subtitle:GetText(), "Geschrieben am Samstag, 3. Oktober 2026 · geändert am 03.10.2026 · 1 Ort auf der Karte")
        T.same(rows(ns), { "Ohne Titel | 03.10.2026" })
        T.eq(_G.WayscribeJournalFrameTab2:GetText(), "Notizen")
        map:Show()
        local tooltip = installTooltip()
        markers(ns)[1].scripts.OnEnter(markers(ns)[1])
        T.eq(tooltip.lines[#tooltip.lines], "Klicken, um die Notiz im Tagebuch zu öffnen.")
        _G.GameTooltip = nil
    end)
end)
