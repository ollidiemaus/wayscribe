local _, ns = ...
local L, Compat, Store, Time, Trace, YearCards = ns.L, ns.Compat, ns.Store, ns.Time, ns.Trace, ns.YearCards

-- Gold (docs/ARCHITECTURE.md §6.13): the money earned and spent each day, as the per-day counter
-- gold = { earned, spent } in copper. On PLAYER_MONEY the current money is compared with the saved
-- amount, so every source counts and a missed event is caught at the next one. The look when the
-- tracker is switched on (every login and /reload) takes the amount silently, and so does the first
-- loading screen after it, in case the money wasn't known yet at login: money that changed while
-- Wayscribe wasn't watching never lands on the wrong day.
--
-- The best day comes from the counters (the month rollup's goldBest). The most held at once isn't
-- in them, so it is kept per year in the tracker's state: state.gold = { money, most = { [year] } }.
local ICON = "Interface\\Icons\\INV_Misc_Coin_01"
local COPPER_PER_SILVER, COPPER_PER_GOLD = 100, 10000

local function symbol(global, fallback)
    return Compat.Safe(_G[global], "string") or fallback
end

-- The game's coin format, as GetMoneyString writes it without coin icons: "1,203g 20s 5c", zero
-- denominations left out.
local function coins(copper)
    local gold = math.floor(copper / COPPER_PER_GOLD)
    local silver = math.floor(copper / COPPER_PER_SILVER) % 100
    local parts = {}
    if gold > 0 then parts[#parts + 1] = YearCards.Number(gold) .. symbol("GOLD_AMOUNT_SYMBOL", L.GOLD_SYMBOL) end
    if silver > 0 then parts[#parts + 1] = silver .. symbol("SILVER_AMOUNT_SYMBOL", L.SILVER_SYMBOL) end
    if copper % 100 > 0 or #parts == 0 then
        parts[#parts + 1] = copper % 100 .. symbol("COPPER_AMOUNT_SYMBOL", L.COPPER_SYMBOL)
    end
    return table.concat(parts, " ")
end

-- Whether a { earned, day } beats the best so far: more earned, or the earlier day on a tie.
local function beats(candidate, best)
    return not best or candidate.earned > best.earned
        or (candidate.earned == best.earned and candidate.day < best.day)
end

-- "Gold: 3g 20s earned, 1g 5s spent"
ns.RecordTypes:RegisterCounter("gold", {
    category = "progress",
    order = 30,
    render = function(bucket)
        local parts = {}
        if (bucket.earned or 0) > 0 then parts[#parts + 1] = L.GOLD_EARNED:format(coins(bucket.earned)) end
        if (bucket.spent or 0) > 0 then parts[#parts + 1] = L.GOLD_SPENT:format(coins(bucket.spent)) end
        if #parts == 0 then return nil end
        return L.COUNTER_GOLD:format(table.concat(parts, L.LIST_SEPARATOR))
    end,
    -- The month's day with the most earned (the earlier one on a tie).
    rollup = function(rollup, key, dayAmount, dayKey)
        if key ~= "earned" then return end
        local day = { earned = dayAmount, day = dayKey }
        if beats(day, rollup.goldBest) then rollup.goldBest = day end
    end,
    merge = function(target, source)
        local other = source.goldBest
        if other and beats(other, target.goldBest) then
            target.goldBest = { earned = other.earned, day = other.day }
        end
    end,
})

local function savedState()
    local saved = Store:GetState("gold")
    return type(saved) == "table" and saved or nil
end

-- "12g 5s earned" (big), spent, the best day and the most held at once; a year of only spending
-- leads with that. Before Time played.
YearCards:Register({
    id = "gold",
    order = 95,
    build = function(summary)
        local bucket = summary.rollup.counters.gold or {}
        local earned, spent = bucket.earned or 0, bucket.spent or 0
        if earned + spent <= 0 then return nil end
        local card = { title = L.CARD_GOLD, icon = ICON, lines = {} }
        if earned > 0 then
            card.big, card.caption = coins(earned), L.CARD_GOLD_EARNED
            if spent > 0 then card.lines[1] = L.CARD_GOLD_SPENT:format(coins(spent)) end
        else
            card.big, card.caption = coins(spent), L.CARD_GOLD_SPENT_CAPTION
        end
        local best = summary.rollup.goldBest
        if best then
            card.lines[#card.lines + 1] = L.CARD_GOLD_BEST_DAY:format(Time.FormatLongDay(best.day), coins(best.earned))
        end
        local saved = savedState()
        local most = saved and type(saved.most) == "table" and saved.most[summary.year]
        if type(most) == "number" and most > 0 then
            card.lines[#card.lines + 1] = L.CARD_GOLD_MOST_HELD:format(coins(most))
        end
        return card
    end,
})

local Gold = ns.Trackers:New("Gold", { label = L.TRACKER_GOLD, tooltip = L.TRACKER_GOLD_TIP })

function Gold:OnEnable()
    self:RegisterEvent("PLAYER_MONEY")
    self:RegisterEvent("PLAYER_ENTERING_WORLD")
    self:Look("enable", true)
end

function Gold:PLAYER_ENTERING_WORLD()
    self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    self:Look("PLAYER_ENTERING_WORLD", true)
end

function Gold:PLAYER_MONEY()
    self:Look("PLAYER_MONEY")
end

-- Counts the change since the saved amount (unless `silent`) and saves the new one; returns how the
-- look ended, for the trace.
local function take(money, silent, saved)
    local before = saved and Compat.Safe(saved.money, "number")
    local outcome
    if not before then
        outcome = "first look"
    elseif silent then
        outcome = "taken"
    elseif money == before then
        return "unchanged"
    elseif money > before then
        outcome = Store:Count("gold", "earned", money - before) and "earned" or "read-only"
    else
        outcome = Store:Count("gold", "spent", before - money) and "spent" or "read-only"
    end
    if outcome == "read-only" then return outcome end
    local most = saved and type(saved.most) == "table" and saved.most or {}
    local year = Time.SplitDay(Time.DayKey(Time.Now()))
    if money > (tonumber(most[year]) or 0) then most[year] = money end
    if not Store:SetState("gold", { money = money, most = most }) then return "read-only" end
    return outcome
end

function Gold:Look(event, silent)
    local money, raw = Compat.GetMoney()
    local saved = savedState()
    local outcome = money and take(money, silent, saved) or "no money"
    Trace:Add(self.id, event, outcome, "money", raw, "saved", saved and saved.money)
end
