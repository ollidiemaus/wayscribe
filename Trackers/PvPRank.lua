local _, ns = ...
local L, Compat, Store, Trace, YearCards = ns.L, ns.Compat, ns.Store, ns.Trace, ns.YearCards

-- PvP rank (docs/ARCHITECTURE.md §6.21): an entry for each new highest PvP rank the character
-- reaches in a season. Forever's honor ranks are the renown of the PvP rank faction (2800), reset
-- each arena season. A look compares the rank with the snapshot, state.pvpRank = { season, best },
-- so a missed event is caught at the next look. The first look, losing a rank and a new season take
-- the rank silently; a journal restored without the state gets a silent first look.
local ICON = "Interface\\Icons\\INV_BannerPVP_02"

local function rankText(data)
    if data.title then return L.PVP_RANK_REACHED:format(data.rank, data.title) end
    return L.PVP_RANK_REACHED_NUMBER:format(data.rank)
end

-- The year's best rank: `other` replaces `best` when it is higher, or the same rank reached earlier.
local function better(best, other)
    if best and (other.rank < best.rank or (other.rank == best.rank and other.ts >= best.ts)) then return best end
    return { rank = other.rank, season = other.season, title = other.title, ts = other.ts }
end

-- "Reached PvP rank 3: Sergeant"
ns.RecordTypes:Register("PVP_RANK", {
    version = 1,
    category = "pvp",
    fields = { rank = "number", season = "number", title = "string?" },
    -- The highest rank reached, the earliest time it was reached (Your Year).
    rollup = function(rollup, data, record)
        rollup.pvpRank = better(rollup.pvpRank,
            { rank = data.rank, season = data.season, title = data.title, ts = record.ts })
    end,
    merge = function(target, source)
        if source.pvpRank then target.pvpRank = better(target.pvpRank, source.pvpRank) end
    end,
    render = rankText,
})

-- The highest rank as the big number, its title, and when it was reached. After Duels.
YearCards:Register({
    id = "pvprank",
    order = 56,
    build = function(summary)
        local best = summary.rollup.pvpRank
        if not best then return nil end
        return {
            title = L.CARD_PVP_RANK, icon = ICON,
            big = YearCards.Number(best.rank), caption = best.title or L.CARD_PVP_RANK_CAPTION,
            lines = { L.CARD_PVP_RANK_REACHED:format(YearCards.Date(best.ts), best.season) },
        }
    end,
})

local PvPRank = ns.Trackers:New("PvPRank", {
    label = L.TRACKER_PVPRANK, tooltip = L.TRACKER_PVPRANK_TIP,
})

function PvPRank:OnEnable()
    self:TryRegisterEvent("PLAYER_PVP_RANK_CHANGED")
    self:TryRegisterEvent("MAJOR_FACTION_RENOWN_LEVEL_CHANGED")
    self:RegisterEvent("PLAYER_ENTERING_WORLD")
    self:AskForLook("enable")
end

function PvPRank:PLAYER_PVP_RANK_CHANGED() self:AskForLook("PLAYER_PVP_RANK_CHANGED") end
function PvPRank:PLAYER_ENTERING_WORLD() self:AskForLook("PLAYER_ENTERING_WORLD") end

-- Other renown tracks (Forever's Legacy Track) are no rank change.
function PvPRank:MAJOR_FACTION_RENOWN_LEVEL_CHANGED(factionID)
    local id = Compat.Safe(factionID, "number")
    if id and id ~= Compat.PVP_RANK_FACTION then return end
    self:AskForLook("MAJOR_FACTION_RENOWN_LEVEL_CHANGED")
end

-- Compares the rank with the snapshot and writes an entry for a new highest rank in the season;
-- returns how the look ended, for the trace.
local function compare(rank, season)
    if not Store:IsWritable() then return "read-only" end
    local saved = Store:GetState("pvpRank")
    local known = type(saved) == "table" and type(saved.season) == "number" and type(saved.best) == "number"
    if not known then
        return Store:SetState("pvpRank", { season = season, best = rank }) and "first look" or "read-only"
    end
    if season ~= saved.season then
        return Store:SetState("pvpRank", { season = season, best = rank }) and "new season" or "read-only"
    end
    if rank <= saved.best then return "unchanged" end
    local record, reason = Store:Append("PVP_RANK", { rank = rank, season = season, title = Compat.GetPvPRankTitle(rank) })
    if not record then return "not written: " .. tostring(reason) end
    return Store:SetState("pvpRank", { season = season, best = rank }) and "recorded " .. rank or "read-only"
end

function PvPRank:Look()
    local asked = self:TakeAsked()
    local rank, season, rawRank, rawSeason = Compat.GetPvPRank()
    local outcome = "unreadable"
    if rank and season then outcome = compare(rank, season) end
    Trace:Add(self.id, asked, outcome, "rank", rawRank, "season", rawSeason)
end
