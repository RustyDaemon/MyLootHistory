--[[
My Loot History addon
Copyright (C) 2026 RustyDaemon (https://github.com/RustyDaemon)

See License file for details.
--]]

-- The currency budget view.
--
-- The report has always been able to list currencies, but only as rows in the item list: a
-- name and a quantity, which answers "what did I pick up" and nothing else. What a player
-- actually wants to know about a crest or a valorstone is different - how much of it they
-- hold now, how close the weekly cap is, and how fast the thing they are doing is earning it.
--
-- None of that is in the history: the caps and the balance live in the client, and the rate
-- comes from the history divided by the window the filters describe. This file is where the
-- two meet, so the view can be a table of budgets rather than a list of pickups.

local MLH = LibStub("AceAddon-3.0"):GetAddon("MyLootHistory")
local DU = LibStub("DateUtils-1.0")

local SECONDS_PER_HOUR = 3600
local SECONDS_PER_DAY = 86400

-- The oldest dated pickup the current scope holds, which is what "all the time" is a
-- duration of. Loot entries are appended in time order, so the first entry of each record
-- is the oldest one it has and the walk never goes deeper than that.
local function earliestFound(self)
    local histories = self:getHistories()
    local earliest = nil

    local function consider(foundOn)
        if (foundOn and (earliest == nil or foundOn < earliest)) then earliest = foundOn end
    end

    local function considerRecords(records)
        for i = 1, #records do
            local first = records[i].lootData and records[i].lootData[1]

            consider(first and first.foundOn)
        end
    end

    for h = 1, #histories do
        local history = histories[h]

        considerRecords(history.items)
        considerRecords(history.currency)
        consider(history.gold[1] and history.gold[1].foundOn)
    end

    return earliest
end

-- How long the active date range covers, in seconds, so a quantity can be turned into a
-- rate. Every range but "yesterday" is still running, so it is measured up to now rather
-- than to its nominal end: half an hour into today, 60 crests is 120 an hour, not 2.5.
--
-- Never zero: a range that has only just begun would otherwise divide the rate by nothing.
function MLH:getRangeDuration()
    local range = self:getFilters().range
    local now = time()
    local duration

    if (range == 1) then --the selected session, live or finished
        duration = self:getSessionStats(self:getSelectedSession()).duration
    elseif (range == 2) then --today
        duration = now - time(DU:getDate(0, true))
    elseif (range == 3) then --yesterday, the one window that is over
        duration = SECONDS_PER_DAY
    elseif (range == 4) then --since the weekly reset
        local today = DU:getToday()

        if (DU:isWed(today.wday)) then
            duration = now - time(DU:getDate(0, true))
        else
            duration = now - time(DU:getLastWed(today.wday))
        end
    elseif (range == 5) then --this month
        local monthStart = DU:getDate(0, true)

        monthStart.day = 1
        monthStart.isdst = nil

        duration = now - time(monthStart)
    else --all the time
        local earliest = earliestFound(self)

        duration = earliest and (now - earliest) or 0
    end

    return math.max(duration, 1)
end

-- What the cap bar draws, or nil for a currency that has no cap at all - which is most of
-- them, and which has to read as "no cap" rather than as a full bar or an empty one.
--
-- A weekly allowance wins over a lifetime maximum where a currency has both: the weekly one
-- is the number that decides what the player does today. `useTotalEarnedForMaxQty` is the
-- client's own flag for a cap counted against everything ever earned rather than against
-- the balance in hand, which is how the season-long crest caps work.
local function capProgress(info)
    if (not info) then return nil end

    if (info.canEarnPerWeek and (info.maxWeeklyQuantity or 0) > 0) then
        return {
            kind = "weekly",
            current = info.quantityEarnedThisWeek or 0,
            max = info.maxWeeklyQuantity,
        }
    end

    if ((info.maxQuantity or 0) > 0) then
        return {
            kind = "total",
            current = info.useTotalEarnedForMaxQty and (info.totalEarned or 0) or (info.quantity or 0),
            max = info.maxQuantity,
        }
    end

    return nil
end

function MLH:sortCurrencyRows(rows)
    local active = self:getFilters()
    local key = active.currencySort or "earned"
    local descending = active.currencySortDescending

    local value = function(row)
        if (key == "earned") then return row.quantity end
        if (key == "perHour") then return row.perHour end
        -- a currency the client will not talk about sorts as nothing held rather than as a
        -- nil, which table.sort's comparator cannot order
        if (key == "held") then return row.held or 0 end
        if (key == "cap") then return row.capRatio or -1 end

        return row.name
    end

    table.sort(rows, function(l, r)
        local lv, rv = value(l), value(r)

        if (lv == rv) then return l.name < r.name end

        if (descending) then return lv > rv end

        return lv < rv
    end)
end

-- The whole currency view in one call, built on the same collectCurrencies the item list
-- uses - so the two can never disagree about what the filters select - with the live
-- balance and the caps read out of the client and hung off each row.
--
-- The balance and the caps belong to whoever is logged in. Under the account-wide scope the
-- earned column still covers every character, but "held" cannot: there is no way to ask the
-- client what a character who is not logged in is carrying, and inventing one would be
-- worse than saying so, which is what `heldIsCurrentCharacter` lets the view do.
function MLH:buildCurrencyReport()
    local rows = self:collectCurrencies()
    local duration = self:getRangeDuration()

    local report = {
        rows = rows,
        duration = duration,
        totalEarned = 0,
        cappedCount = 0,
        cappedTotal = 0,
        heldIsCurrentCharacter = self:getScope() ~= "account",
    }

    for i = 1, #rows do
        local row = rows[i]
        local info = C_CurrencyInfo.GetCurrencyInfo(row.currencyId)

        row.perHour = row.quantity / duration * SECONDS_PER_HOUR
        row.held = info and info.quantity or nil
        row.cap = capProgress(info)

        if (row.cap and row.cap.max > 0) then
            row.capRatio = math.min(row.cap.current / row.cap.max, 1)

            report.cappedTotal = report.cappedTotal + 1

            if (row.cap.current >= row.cap.max) then
                report.cappedCount = report.cappedCount + 1
            end
        end

        report.totalEarned = report.totalEarned + row.quantity
    end

    self:sortCurrencyRows(rows)

    return report
end
