local _, ns = ...

-- Other players are stored once in WayscribeCharDB.players and referenced by small integers,
-- which keeps rosters compact and makes "top companions" a plain count (docs/ARCHITECTURE.md §4.2).
-- The list is append-only: ids are referenced from records, so entries are never removed.
local Players = {}
ns.Players = Players

local byGuid = {}

function Players:Attach(list)
    self.list = list
    byGuid = {}
    for id, player in pairs(list) do
        if type(player) == "table" and type(player.guid) == "string" then
            byGuid[player.guid] = id
        end
    end
end

-- Returns the player's id, adding them or refreshing their name/realm/class.
function Players:Intern(guid, name, realm, class)
    guid = ns.Compat.Safe(guid, "string")
    if not self.list or not guid or guid == "" then
        return nil
    end
    local id = byGuid[guid]
    if not id then
        id = #self.list + 1
        self.list[id] = { guid = guid }
        byGuid[guid] = id
    end
    local player = self.list[id]
    name, realm, class = ns.Compat.Safe(name, "string"), ns.Compat.Safe(realm, "string"), ns.Compat.Safe(class, "string")
    if name and name ~= "" then player.name = name end
    if realm and realm ~= "" then player.realm = realm end
    if class and class ~= "" then player.class = class end
    return id
end

function Players:Get(id)
    return self.list and self.list[id]
end
