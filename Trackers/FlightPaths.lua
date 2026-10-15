local _, ns = ...
local L, Compat, Store, Trace = ns.L, ns.Compat, ns.Store, ns.Trace

-- Flight paths (docs/ARCHITECTURE.md §6.17): an entry for each flight master the character learns,
-- once per node (the firsts key FLIGHT:<node>). The known nodes can only be read while a taxi map is
-- open (Compat.GetTaxiNodes), so TAXIMAP_OPENED asks for a look and the "New flight path
-- discovered!" chat line only asks for another. A look compares the known nodes with
-- state.flightPaths = { seen = { [continent] = true }, known = { [node] = true } }, so a path learned
-- without a look is caught at the next flight master. The first map on each continent is silent,
-- unless the only node known is the one the player stands at: then it was just learned.
local SETTLE = 0.2 -- seconds after an event; the chat line and the map opening are one look

-- A node by its ID on the flight map, by its name on the old taxi frame, which has no IDs.
local function nodeKey(node)
    return node.id or "name:" .. node.name
end

-- "New flight path: Thunder Bluff, Mulgore"
ns.RecordTypes:Register("FLIGHT_PATH", {
    version = 1,
    category = "travel",
    fields = { node = "number?", name = "string?" },
    firstKey = function(data) return "FLIGHT:" .. nodeKey({ id = data.node, name = data.name or "?" }) end,
    render = function(data)
        return data.name and L.FLIGHT_PATH_NEW:format(data.name) or L.FLIGHT_PATH_NEW_UNNAMED
    end,
})

local FlightPaths = ns.Trackers:New("FlightPaths", {
    label = L.TRACKER_FLIGHT_PATHS, tooltip = L.TRACKER_FLIGHT_PATHS_TIP, lookDelay = SETTLE,
})

function FlightPaths:OnEnable()
    self:TryRegisterEvent("TAXIMAP_OPENED")
    self:TryRegisterEvent("CHAT_MSG_SYSTEM")
end

function FlightPaths:TAXIMAP_OPENED()
    self:AskForLook("TAXIMAP_OPENED")
end

function FlightPaths:CHAT_MSG_SYSTEM(text)
    local line = Compat.Safe(ERR_NEWTAXIPATH, "string")
    if line and Compat.Safe(text, "string") == line then self:AskForLook("CHAT_MSG_SYSTEM") end
end

local function copy(set)
    local result = {}
    for key, value in pairs(type(set) == "table" and set or {}) do result[key] = value end
    return result
end

-- Compares the known nodes with the snapshot and writes an entry for each newly known one; returns
-- how the look ended and the new nodes, for the trace (at a first look, only the one recorded). A failed write keeps nothing of the look.
local function compare(nodes, continent)
    if not Store:IsWritable() then return "read-only", {} end
    local saved = Store:GetState("flightPaths")
    saved = type(saved) == "table" and saved or {}
    local seen, known = copy(saved.seen), copy(saved.known)
    local new = {}
    for _, node in ipairs(nodes) do
        if not known[nodeKey(node)] then new[#new + 1] = node end
    end
    local first = not seen[continent]
    local record = new
    if first then
        record = (#nodes == 1 and nodes[1].current) and nodes or {}
        new = record -- the rest was known before
    end
    local written = 0
    for _, node in ipairs(record) do
        if not Store:GetFirst("FLIGHT:" .. nodeKey(node)) then
            local entry, reason = Store:Append("FLIGHT_PATH", { node = node.id, name = node.name })
            if not entry then return "not written: " .. tostring(reason), new end
            written = written + 1
        end
    end
    for _, node in ipairs(nodes) do known[nodeKey(node)] = true end
    seen[continent] = true
    if not Store:SetState("flightPaths", { seen = seen, known = known }) then return "read-only", new end
    if written > 0 then return "recorded " .. written, new end
    return first and "first look" or "unchanged", new
end

function FlightPaths:Look()
    local asked = self:TakeAsked()
    local nodes, read = Compat.GetTaxiNodes()
    -- The flight map is one per continent; the old frame's continent is the player's.
    local map = read and (read.map or Compat.GetContinentOf(Compat.GetPlayerMapID()))
    local outcome, new, current = read and "no known nodes" or "no taxi map", nil, nil
    if nodes then
        for _, node in ipairs(nodes) do
            if node.current then current = node.id or node.name end
        end
        outcome, new = compare(nodes, read.source .. ":" .. tostring(map))
    end
    local newKeys = {}
    for i, node in ipairs(new or {}) do newKeys[i] = tostring(nodeKey(node)) end
    Trace:Add(self.id, asked, outcome, "source", read and read.source,
        read and "map", map, read and "nodes", read and read.nodes, read and "known", nodes and #nodes or 0,
        current and "current", current, #newKeys > 0 and "new", table.concat(newKeys, " "))
end
