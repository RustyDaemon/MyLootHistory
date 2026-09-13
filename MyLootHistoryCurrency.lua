--[[
My Loot History addon
Copyright (C) 2026 RustyDaemon (https://github.com/RustyDaemon)

See License file for details.
--]]

local MLH = LibStub("AceAddon-3.0"):GetAddon("MyLootHistory")
local DU = LibStub("DateUtils-1.0")

local SECONDS_PER_HOUR = 3600
local SECONDS_PER_DAY = 86400

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

-- Balances and caps are for the logged-in character, even under account-wide scope.
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
