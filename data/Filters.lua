--[[
My Loot History addon
Copyright (C) 2026 RustyDaemon (https://github.com/RustyDaemon)

See License file for details.
--]]

-- The report's filters - date range, zone, quality, search, sort - and the choices offered for each.

local MLH = LibStub("AceAddon-3.0"):GetAddon("MyLootHistory")
local DU = LibStub("DateUtils-1.0")
local L = LibStub("AceLocale-3.0"):GetLocale("MyLootHistory")

local filters = nil

local SECONDS_PER_DAY = 86400

MLH.RANGE_SESSION = 1
MLH.RANGE_TODAY = 2
MLH.RANGE_YESTERDAY = 3
MLH.RANGE_RESET = 4
MLH.RANGE_MONTH = 5
MLH.RANGE_ALL = 6

local function secondsSinceMidnight(now)
    return now - time(DU:getDate(0, true))
end

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

-- The report's date ranges, in menu order. `id` is saved in params.selectedRangeValue, so ids never change.
-- matches(self, foundOn, entry) says whether a dated entry falls in the range;
-- duration(self, now) is the range's length in seconds so far, for the per-hour rates.
local ranges = {
    {
        id = MLH.RANGE_SESSION, labelKey = "RR_ThisSesion", shortKey = "RS_Session",
        -- the selected session, live or finished
        matches = function(self, foundOn, entry)
            local session = self:getSelectedSession()

            if (entry) then return self:isEntryInSession(entry, session) end

            if (session.startedOn == nil or foundOn < session.startedOn) then return false end

            return session.endedOn == nil or foundOn <= session.endedOn
        end,
        duration = function(self)
            return self:getSessionStats(self:getSelectedSession()).duration
        end,
    },
    {
        id = MLH.RANGE_TODAY, labelKey = "RR_Today", shortKey = "RS_Today",
        matches = function(_, foundOn) return DU:dateIsToday(foundOn) end,
        duration = function(_, now) return secondsSinceMidnight(now) end,
    },
    {
        id = MLH.RANGE_YESTERDAY, labelKey = "RR_Yesterday", shortKey = "RS_Yesterday",
        matches = function(_, foundOn) return DU:dateIsYesterday(foundOn, true) end,
        -- the one window that is already over
        duration = function() return SECONDS_PER_DAY end,
    },
    {
        id = MLH.RANGE_RESET, labelKey = "RR_WedToWed", shortKey = "RS_Reset",
        -- since the weekly reset
        matches = function(_, foundOn)
            local wday = DU:getToday().wday

            if (DU:isWed(wday)) then
                return DU:dateIsToday(foundOn)
            end

            return DU:dateInRangeTillToday(foundOn, DU:getLastWed(wday))
        end,
        duration = function(_, now)
            local wday = DU:getToday().wday

            if (DU:isWed(wday)) then return secondsSinceMidnight(now) end

            return now - time(DU:getLastWed(wday))
        end,
    },
    {
        id = MLH.RANGE_MONTH, labelKey = "RR_ThisMonth", shortKey = "RS_Month",
        matches = function(_, foundOn) return DU:dateIsInCurrentMonth(foundOn) end,
        duration = function(_, now)
            local monthStart = DU:getDate(0, true)

            monthStart.day = 1
            monthStart.isdst = nil

            return now - time(monthStart)
        end,
    },
    {
        id = MLH.RANGE_ALL, labelKey = "RR_AllTheTime", shortKey = "RS_All",
        matches = function() return true end,
        duration = function(self, now)
            local earliest = earliestFound(self)

            return earliest and (now - earliest) or 0
        end,
    },
}

local rangesById = {}

for i = 1, #ranges do rangesById[ranges[i].id] = ranges[i] end

-- Filter key -> saved param name in db.char.params.
local paramKeys = {
    view = "selectedView",
    scope = "selectedScope",
    session = "selectedSession",
    range = "selectedRangeValue",
    quality = "selectedQualityValue",
    exactQuality = "selectedExactItemQuality",
    zone = "selectedZoneID",
    search = "searchText",
    sortKey = "sortKey",
    sortDescending = "sortDescending",
    currencySort = "currencySortKey",
    currencySortDescending = "currencySortDescending",
}

function MLH:getFilters()
    if (filters) then return filters end

    local params = self.db.char.params
    local descending = params.sortDescending
    local currencyDescending = params.currencySortDescending

    if (descending == nil) then descending = true end
    if (currencyDescending == nil) then currencyDescending = true end

    filters = {
        view = params.selectedView or "items",
        scope = params.selectedScope or "char",
        session = params.selectedSession or 0,
        range = params.selectedRangeValue or MLH.RANGE_TODAY,
        quality = params.selectedQualityValue or 0,
        exactQuality = params.selectedExactItemQuality or false,
        zone = params.selectedZoneID or 0,
        search = params.searchText or "",
        sortKey = params.sortKey or "quantity",
        sortDescending = descending,
        currencySort = params.currencySortKey or "earned",
        currencySortDescending = currencyDescending,
    }

    return filters
end

function MLH:setFilter(key, value)
    local active = self:getFilters()

    active[key] = value

    self.db.char.params[paramKeys[key]] = value
end

function MLH:resetFilters()
    self:setFilter("range", MLH.RANGE_ALL)
    self:setFilter("quality", 0)
    self:setFilter("exactQuality", false)
    self:setFilter("zone", 0)
    self:setFilter("search", "")
end

function MLH:hasActiveFilters()
    local active = self:getFilters()

    return active.range ~= MLH.RANGE_ALL or active.quality ~= 0 or active.exactQuality
        or active.zone ~= 0 or active.search ~= ""
end

function MLH:isInSelectedRange(foundOn, entry)
    local id = self:getFilters().range

    -- Undated legacy entries belong only to the unbounded date range.
    if (foundOn == nil) then return id == MLH.RANGE_ALL end

    local range = rangesById[id]

    return range ~= nil and range.matches(self, foundOn, entry)
end

-- Seconds the selected range covers so far, at least 1 so it can divide. An unknown range counts as all time.
function MLH:getRangeDuration()
    local range = rangesById[self:getFilters().range] or rangesById[MLH.RANGE_ALL]

    return math.max(range.duration(self, time()), 1)
end

function MLH:isInSelectedZone(zoneID)
    local zone = self:getFilters().zone

    return zone == 0 or zoneID == zone
end

function MLH:getQualityList()
    local list = {}

    for i = Enum.ItemQuality.Poor, Enum.ItemQuality.Legendary do
        local _, _, _, hex = C_Item.GetItemQualityColor(i)
        local desc = _G["ITEM_QUALITY"..i.."_DESC"]

        if (desc) then
            list[#list+1] = { value = i, text = '|c'..hex..desc..'|r' }
        end
    end

    return list
end

function MLH:getQualityName(quality)
    local _, _, _, hex = C_Item.GetItemQualityColor(quality)
    local desc = _G["ITEM_QUALITY"..quality.."_DESC"] or tostring(quality)

    return '|c'..hex..desc..'|r'
end

local function rangeList(textKey)
    local list = {}

    for i = 1, #ranges do
        list[i] = { value = ranges[i].id, text = L[ranges[i][textKey]] }
    end

    return list
end

function MLH:getRangeList()
    return rangeList("labelKey")
end

function MLH:getRangeName(id)
    local range = rangesById[id or MLH.RANGE_TODAY]

    return range and L[range.labelKey]
end

function MLH:getShortRangeList()
    return rangeList("shortKey")
end

function MLH:getZoneList()
    local list = { { value = 0, text = L["RR_AnyZone"] } }
    local seen = {}
    local named = {}

    local function collect(records)
        for i = 1, #records do
            local lootData = records[i].lootData

            for j = 1, #lootData do
                local zoneID = lootData[j].zoneID

                if (zoneID and not seen[zoneID]) then
                    seen[zoneID] = true

                    local zoneName = self:getZoneName(zoneID)

                    if (zoneName) then
                        named[#named+1] = { value = zoneID, text = zoneName }
                    end
                end
            end
        end
    end

    local histories = self:getHistories()

    for h = 1, #histories do
        collect(histories[h].items)
        collect(histories[h].currency)
    end

    table.sort(named, function(l, r) return l.text < r.text end)

    for i = 1, #named do
        list[#list+1] = named[i]
    end

    return list
end

function MLH:getZoneFilterName()
    local zone = self:getFilters().zone

    if (zone == 0) then return L["RR_AnyZone"] end

    return self:getZoneName(zone) or L["R_UnknownZone"]
end
