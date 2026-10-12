local _, ns = ...
local L, Compat, Store, Time, Players, YearCards = ns.L, ns.Compat, ns.Store, ns.Time, ns.Players, ns.YearCards

-- Duels (docs/ARCHITECTURE.md §6.10): who you dueled, who won, the opponent's class and level.
-- DUEL_FINISHED doesn't say who won; the client's system chat line does ("%1$s has defeated %2$s
-- in a duel", or "%2$s has fled from %1$s"), read through its own global strings, so it works in
-- every language. The opponent comes from the challenge: the unit the player challenged
-- (StartDuel), or the name DUEL_REQUESTED gives, looked up among nearby units. A challenge that
-- is declined or runs out ends without such a line and leaves no entry.
local ICON = "Interface\\Icons\\Ability_DualWield"
local RESULT_WAIT = 3     -- seconds after DUEL_FINISHED for the result line (it comes in the same frame)
local MAX_PENDING = 1800  -- a challenge nobody finished is forgotten after this long

-- "Kangal Mooran (Warrior, level 6)"; just the name when neither is known.
local function opponentText(data)
    local player = data.p and Players:Get(data.p)
    local name = player and player.name or data.name or L.DUEL_SOMEONE
    local class = Compat.GetClassName(data.cls or (player and player.class))
    local detail
    if class and data.lv then
        detail = L.DUEL_CLASS_LEVEL:format(class, data.lv)
    elseif data.lv then
        detail = L.DUEL_LEVEL:format(data.lv)
    else
        detail = class
    end
    return detail and L.DUEL_OPPONENT:format(name, detail) or name
end

-- "Goldshire, Elwynn Forest", or whichever of the two is known.
local function placeOf(data)
    local zone = data.map and Compat.GetMapName(data.map)
    local sub = data.sub
    if sub and zone and sub ~= zone then
        return L.PLACE_IN_ZONE:format(sub, zone)
    end
    return sub or zone
end

-- The key an opponent is counted under: their player id, or their name when the client never
-- showed them as a unit.
local function opponentKey(data)
    return data.p or data.name
end

local function addCount(map, key, amount)
    map[key] = (map[key] or 0) + (amount or 1)
end

local function mergeCounts(target, source, field)
    if not source[field] then return end
    target[field] = target[field] or {}
    for key, count in pairs(source[field]) do
        addCount(target[field], key, count)
    end
end

local COUNT_FIELDS = { "duelClasses", "duelClassWins", "duelOpponents", "duelOpponentWins" }

ns.RecordTypes:Register("DUEL", {
    version = 1,
    category = "pvp",
    -- p: the opponent (Players id), or name when they were never seen as a unit; cls, lv: their
    -- class file and level; ml: the player's level; won: the player won; fled: the loser left the
    -- duel area; death: a duel to the death; dur: seconds from the countdown's end; map, sub: where
    fields = {
        p = "number?", name = "string?", cls = "string?", lv = "number?", ml = "number?", won = "boolean",
        fled = "boolean?", death = "boolean?", dur = "number?", map = "number?", sub = "string?",
    },
    -- Wins, and duels and wins per class and per opponent, for Your Year.
    rollup = function(rollup, data)
        if data.won then rollup.duelsWon = (rollup.duelsWon or 0) + 1 end
        local key = opponentKey(data)
        for _, field in ipairs(COUNT_FIELDS) do rollup[field] = rollup[field] or {} end
        if data.cls then
            addCount(rollup.duelClasses, data.cls)
            if data.won then addCount(rollup.duelClassWins, data.cls) end
        end
        if key then
            addCount(rollup.duelOpponents, key)
            if data.won then addCount(rollup.duelOpponentWins, key) end
        end
    end,
    merge = function(target, source)
        if source.duelsWon then target.duelsWon = (target.duelsWon or 0) + source.duelsWon end
        for _, field in ipairs(COUNT_FIELDS) do mergeCounts(target, source, field) end
    end,
    render = function(data)
        local pattern
        if data.death then
            pattern = data.won and L.DUEL_WON_DEATH or L.DUEL_LOST_DEATH
        elseif data.fled then
            pattern = data.won and L.DUEL_WON_FLED or L.DUEL_LOST_FLED
        else
            pattern = data.won and L.DUEL_WON or L.DUEL_LOST
        end
        return pattern:format(opponentText(data))
    end,
})

local Duels = ns.Trackers:New("Duels", { label = L.TRACKER_DUELS, tooltip = L.TRACKER_DUELS_TIP })
ns.Duels = Duels
Duels.ICON = ICON
Duels.OpponentText = opponentText
Duels.PlaceOf = placeOf

------------------------------------------------------------------------------------------------
-- Numbers for the Duels page and Your Year

-- An opponent's name from a rollup or record key.
function Duels.NameOf(key)
    if type(key) == "number" then
        local player = Players:Get(key)
        return player and player.name or L.DUEL_SOMEONE
    end
    return key or L.DUEL_SOMEONE
end

-- "Won", "Fled", "Lost to the death", ...: a duel's result, short.
function Duels.ResultText(data)
    local key = data.won and "DUELS_RESULT_WON" or "DUELS_RESULT_LOST"
    if data.death then
        key = key .. "_DEATH"
    elseif data.fled then
        key = key .. "_FLED"
    end
    return L[key]
end

-- "65%"
function Duels.Rate(won, total)
    return L.PERCENT:format(total > 0 and math.floor(won / total * 100 + 0.5) or 0)
end

-- Everything the Duels page shows, from the records (all time, newest first):
-- { total, won, records, classes = { { class, n, won } }, opponents = { { key, name, class, level, n, won, last } } }
-- Classes are sorted by duels, opponents by duels, then by the last one.
function Duels.Collect()
    local records = Store.db and Store:GetRecordsOfType("DUEL") or {}
    local stats = { total = #records, won = 0, records = {}, classes = {}, opponents = {} }
    local classes, opponents = {}, {}
    for i = #records, 1, -1 do
        local record = records[i]
        local data = record.data
        stats.records[#stats.records + 1] = record
        if data.won then stats.won = stats.won + 1 end
        local player = data.p and Players:Get(data.p)
        local class = data.cls or (player and player.class)
        if class then
            local entry = classes[class]
            if not entry then
                entry = { class = class, n = 0, won = 0 }
                classes[class] = entry
                stats.classes[#stats.classes + 1] = entry
            end
            entry.n = entry.n + 1
            if data.won then entry.won = entry.won + 1 end
        end
        local key = opponentKey(data)
        if key then
            local entry = opponents[key]
            if not entry then
                -- The newest record comes first: its class and level are the latest seen.
                entry = { key = key, name = Duels.NameOf(key), class = class, level = data.lv, n = 0, won = 0, last = record.ts }
                opponents[key] = entry
                stats.opponents[#stats.opponents + 1] = entry
            end
            entry.n = entry.n + 1
            if data.won then entry.won = entry.won + 1 end
        end
    end
    table.sort(stats.classes, function(a, b)
        if a.n ~= b.n then return a.n > b.n end
        return a.class < b.class
    end)
    table.sort(stats.opponents, function(a, b)
        if a.n ~= b.n then return a.n > b.n end
        if a.last ~= b.last then return a.last > b.last end
        return a.name < b.name
    end)
    return stats
end

-- The class with the best (or worst) win rate among those dueled at least `min` times.
local function classByRate(rollup, min, worst)
    local bestClass, bestRate, bestCount
    for class, count in pairs(rollup.duelClasses or {}) do
        if count >= min then
            local rate = ((rollup.duelClassWins or {})[class] or 0) / count
            local better = not bestRate or (worst and rate < bestRate) or (not worst and rate > bestRate)
                or (rate == bestRate and (count > bestCount or (count == bestCount and class < bestClass)))
            if better then
                bestClass, bestRate, bestCount = class, rate, count
            end
        end
    end
    return bestClass, bestCount
end

local CLASS_MIN = 3 -- duels against a class before it can be the best or the worst

-- "37 duels. 24 won, 13 lost (65%). Most often against Kangal Mooran (12 duels). ..."
YearCards:Register({
    id = "duels",
    order = 55,
    build = function(summary)
        local rollup = summary.rollup
        local total = rollup.records.DUEL or 0
        if total == 0 then return nil end
        local won = rollup.duelsWon or 0
        local card = {
            title = L.CARD_DUELS, icon = ICON,
            big = YearCards.Number(total), caption = YearCards.Plural("CARD_DUELS_COUNT", total),
            lines = { L.CARD_DUELS_RESULT:format(YearCards.Plural("CARD_DUELS_WON", won),
                YearCards.Plural("CARD_DUELS_LOST", total - won), Duels.Rate(won, total)) },
        }
        local rival, count = YearCards.Top(rollup.duelOpponents)
        if rival and count > 1 then
            card.lines[#card.lines + 1] = L.CARD_DUELS_RIVAL:format(Duels.NameOf(rival), YearCards.Plural("CARD_DUELS_TIMES", count))
        end
        local losses = {}
        for key, n in pairs(rollup.duelOpponents or {}) do
            local lost = n - ((rollup.duelOpponentWins or {})[key] or 0)
            if lost > 0 then losses[key] = lost end
        end
        local nemesis, lost = YearCards.Top(losses)
        if nemesis and lost > 1 then
            card.lines[#card.lines + 1] = L.CARD_DUELS_NEMESIS:format(Duels.NameOf(nemesis), YearCards.Plural("CARD_DUELS_BEATEN", lost))
        end
        local best, bestCount = classByRate(rollup, CLASS_MIN)
        local worst, worstCount = classByRate(rollup, CLASS_MIN, true)
        local function classLine(pattern, class, n)
            local wins = (rollup.duelClassWins or {})[class] or 0
            return pattern:format(Compat.GetClassName(class) or class, L.CARD_DUELS_OF:format(wins, n))
        end
        if best then
            card.lines[#card.lines + 1] = classLine(L.CARD_DUELS_BEST_CLASS, best, bestCount)
        end
        if worst and worst ~= best then
            card.lines[#card.lines + 1] = classLine(L.CARD_DUELS_WORST_CLASS, worst, worstCount)
        end
        return card
    end,
})

------------------------------------------------------------------------------------------------
-- The tracker

-- The duel under way, from the challenge to the result: { name, guid, class, level, realm, death,
-- began }. While there is one, system chat is listened to; the rest of the time it isn't.
function Duels:OnEnable()
    self.pending = nil
    self:TryRegisterEvent("DUEL_REQUESTED")
    self:TryRegisterEvent("DUEL_TO_THE_DEATH_REQUESTED")
    self:TryRegisterEvent("DUEL_FINISHED")
    self:HookStartDuel()
end

function Duels:OnDisable()
    self.pending = nil
end

-- StartDuel(unit or name, ...) is how the unit menu, /duel and the duel-to-the-death dialog send a
-- challenge; no event says the player sent one. A post-hook can't be removed: it stays, and
-- Dispatch drops the calls while the tracker is off.
function Duels:HookStartDuel()
    if self.hooked or type(hooksecurefunc) ~= "function" or type(StartDuel) ~= "function" then return end
    self.hooked = true
    hooksecurefunc("StartDuel", function(...)
        Duels:Dispatch("START_DUEL", ...)
    end)
end

function Duels:Begin(pending)
    self.pending = pending
    self:TryRegisterEvent("CHAT_MSG_SYSTEM")
    self:After(MAX_PENDING, function(module)
        if module.pending == pending then module:Clear() end
    end)
end

function Duels:Clear()
    self.pending = nil
    self:UnregisterEvent("CHAT_MSG_SYSTEM")
end

-- The challenged unit is right there: its identity is read now. A name (/duel Name) is looked up.
function Duels:START_DUEL(target, _, toTheDeath)
    target = Compat.Safe(target, "string")
    if not target then return end
    local info
    if Compat.Call(UnitExists, target) == true then
        info = Compat.GetUnitIdentity(target)
    else
        info = Compat.FindNearbyPlayer(target) or { name = target }
    end
    info.death = Compat.Safe(toTheDeath) == true or nil
    self:Begin(info)
end

-- Someone challenged the player: the event names them, so they are looked up among nearby units.
function Duels:Challenged(name, death)
    name = Compat.Safe(name, "string")
    if not name then return end
    local info = Compat.FindNearbyPlayer(name) or { name = name }
    info.death = death
    self:Begin(info)
end

function Duels:DUEL_REQUESTED(name)
    self:Challenged(name)
end

function Duels:DUEL_TO_THE_DEATH_REQUESTED(name)
    self:Challenged(name, true)
end

-- The result line follows in the same frame; without one the challenge was declined or ran out.
function Duels:DUEL_FINISHED()
    local pending = self.pending
    if not pending then return end
    self:After(RESULT_WAIT, function(module)
        if module.pending == pending then module:Clear() end
    end)
end

-- Is `name` the player, as a chat line names them ("First Surname", or "Name-Realm")?
local function isPlayer(name)
    local me = Compat.GetPlayerIdentity()
    return name ~= nil and (name == me.name or (me.realm ~= nil and name == me.name .. "-" .. me.realm))
end

function Duels:CHAT_MSG_SYSTEM(text)
    local pending = self.pending
    if not pending then return end
    local countdown = Compat.ParseGlobalString("DUEL_COUNTDOWN", text)
    if countdown then
        pending.began = Time.Now() + (tonumber(countdown[1]) or 0)
        return
    end
    for _, key in ipairs({ "DUEL_WINNER_KNOCKOUT", "DUEL_WINNER_RETREAT" }) do
        local names = Compat.ParseGlobalString(key, text)
        if names then
            -- Both strings put the winner first. A line about two others is someone else's duel.
            local winner, loser = names[1], names[2]
            if isPlayer(winner) or isPlayer(loser) then
                self:Record(pending, isPlayer(winner), isPlayer(winner) and loser or winner, key == "DUEL_WINNER_RETREAT")
            end
            return
        end
    end
end

function Duels:Record(pending, won, opponent, fled)
    -- The challenge named this opponent; otherwise (or without their GUID) look again now.
    local info = pending
    if not (pending.guid and pending.name == opponent) then
        info = Compat.FindNearbyPlayer(opponent) or { name = opponent }
    end
    local id = info.guid and Players:Intern(info.guid, info.name, info.realm, info.class)
    local now = Time.Now()
    local data = {
        p = id, name = not id and opponent or nil, cls = info.class, lv = info.level, ml = Compat.GetPlayerLevel(),
        won = won, fled = fled or nil, death = pending.death, map = Compat.GetPlayerMapID(), sub = Compat.GetSubZoneName(),
        dur = pending.began and now >= pending.began and now - pending.began or nil,
    }
    self:Clear()
    Store:Append("DUEL", data)
end
