--[[
My Loot History addon
Copyright (C) 2026 RustyDaemon (https://github.com/RustyDaemon)

See License file for details.
--]]

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

function MLH:calculateGoldFound()
    local histories = self:getHistories()
    local total = 0

    for h = 1, #histories do
        local history = histories[h]
        local gold = history.gold

        for i = 1, #gold do
            local entry = gold[i]

            if (self:isInSelectedZone(entry.zoneID) and self:isInSelectedRange(entry.foundOn, entry)) then
                total = total + entry.quantity
            end
        end
    end

    return total
end

function MLH:collectCurrencies()
    local search = self:getFilters().search
    local currencies = {}
    local histories = self:getHistories()
    local matchedById = {}
    local recordById = {}
    local order = {}

    search = search ~= "" and search:lower() or nil

    for h = 1, #histories do
        local foundCurrency = histories[h].currency

        for i = 1, #foundCurrency do
            local record = foundCurrency[i]
            local id = record.currencyId
            local lootData = record.lootData

            if (not matchedById[id]) then
                matchedById[id] = {}
                recordById[id] = record
                order[#order+1] = id
            end

            local matched = matchedById[id]

            for j = 1, #lootData do
                local entry = lootData[j]

                if (self:isInSelectedZone(entry.zoneID) and self:isInSelectedRange(entry.foundOn, entry)) then
                    matched[#matched+1] = entry
                end
            end
        end
    end

    for i = 1, #order do
        local id = order[i]
        local record = recordById[id]
        local quantity, zones, firstFound, lastFound =
            self:aggregateLoot(matchedById[id], L["R_UnknownZone"])

        local info = C_CurrencyInfo.GetCurrencyInfo(id)
        local name = (info and info.name) or record.currencyName or ("#"..id)

        if (quantity > 0 and (not search or name:lower():find(search, 1, true))) then
            currencies[#currencies+1] = {
                currencyId = id,
                name = name,
                icon = (info and info.iconFileID) or record.currencyIcon,
                quality = (info and info.quality) or record.quality or 1,
                quantity = quantity,
                zones = zones,
                zoneName = zones[1] and zones[1].name or L["R_UnknownZone"],
                firstFound = firstFound,
                lastFound = lastFound,
            }
        end
    end

    table.sort(currencies, MLH.byQuantityThenName)

    return currencies
end

local function formatDateRange(firstFound, lastFound)
    if (firstFound == nil or lastFound == nil) then return "" end

    local firstDate = date('*t', firstFound)
    local lastDate = date('*t', lastFound)

    if (firstDate.yday == lastDate.yday and firstDate.year == lastDate.year) then
        return date("%d %b %Y", firstFound)
    end

    local dateFormat = "%d %b"
    local firstFormat = dateFormat..(firstDate.year ~= lastDate.year and ' %Y' or '')

    return date(firstFormat, firstFound)..' - '..date(dateFormat..' %Y', lastFound)
end

-- The loot entries of one record that the zone and date filters select, and their total quantity.
local function matchingLoot(self, lootData)
    local matched, quantity = {}, 0

    for i = 1, #lootData do
        local entry = lootData[i]

        if (self:isInSelectedZone(entry.zoneID) and self:isInSelectedRange(entry.foundOn, entry)) then
            matched[#matched+1] = entry
            quantity = quantity + (tonumber(entry.quantity) or 1)
        end
    end

    return matched, quantity
end

-- Items hidden from the report, shared by every character: item id -> the name it was hidden under.
-- Their loot is still recorded, so unhiding one brings its whole history back.
function MLH:getHiddenItems()
    self.db.global = self.db.global or {}
    self.db.global.hiddenItems = self.db.global.hiddenItems or {}

    return self.db.global.hiddenItems
end

function MLH:isItemHidden(itemID)
    return itemID ~= nil and self:getHiddenItems()[itemID] ~= nil
end

function MLH:setItemHidden(itemID, hidden, itemName)
    if (not itemID) then return end

    self:getHiddenItems()[itemID] = hidden and (itemName or C_Item.GetItemInfo(itemID) or ("#"..itemID)) or nil
    self:bumpRevision()
end

-- The hidden items by name, for the settings page: { itemId, name }.
function MLH:getHiddenItemList()
    local list = {}

    for itemID, name in pairs(self:getHiddenItems()) do
        list[#list+1] = { itemId = itemID, name = C_Item.GetItemInfo(itemID) or name }
    end

    table.sort(list, function(l, r) return l.name < r.name end)

    return list
end

-- Groups an item's loot by the link it dropped as: one variant per item level, quality and bonus roll.
-- An entry without a link of its own dropped as its record's link.
local function addVariant(self, newItem, entry, record)
    local link = entry.itemLink or record.itemLink
    local key = self:itemVariantKey(link) or ""
    local variant = newItem.variantsByKey[key]

    if (not variant) then
        variant = { link = link, quantity = 0, quality = entry.quality or record.quality }
        newItem.variantsByKey[key] = variant
        newItem.variants[#newItem.variants+1] = variant
    end

    variant.quantity = variant.quantity + (tonumber(entry.quantity) or 1)
    variant.sellPrice = entry.sellPrice or variant.sellPrice

    if (variant.quality and (newItem.quality == nil or variant.quality > newItem.quality)) then
        newItem.quality = variant.quality
    end
end

-- One entry per item id across every character in scope, holding only the matching loot.
-- Hidden items are left out; the second return value counts those with loot in the date and zone.
local function mergeMatchingItems(self)
    local histories = self:getHistories()
    local hiddenItems = self:getHiddenItems()
    local items, byItemId, hiddenSeen, hiddenCount = {}, {}, {}, 0

    for h = 1, #histories do
        local history = histories[h]
        local itemsFound = history.items

        for i = 1, #itemsFound do
            local item = itemsFound[i]
            local matched, matchedQuantity = matchingLoot(self, item.lootData)

            if (#matched > 0 and hiddenItems[item.itemId] ~= nil) then
                if (not hiddenSeen[item.itemId]) then
                    hiddenSeen[item.itemId] = true
                    hiddenCount = hiddenCount + 1
                end
            elseif (#matched > 0) then
                local newItem = byItemId[item.itemId]

                if (not newItem) then
                    newItem = {
                        itemId = item.itemId,
                        itemLink = item.itemLink,
                        itemName = item.itemName,
                        itemTexture = item.itemTexture,
                        quality = item.quality,
                        lootData = {},
                        variants = {},
                        variantsByKey = {},
                        zones = {},
                        characters = {},
                        totalQuantity = 0,
                        totalValue = 0,
                        dateRange = "",
                    }

                    byItemId[item.itemId] = newItem
                    items[#items+1] = newItem
                else
                    newItem.itemLink = newItem.itemLink or item.itemLink
                    newItem.itemName = newItem.itemName or item.itemName
                    newItem.itemTexture = newItem.itemTexture or item.itemTexture
                    newItem.quality = newItem.quality or item.quality
                end

                for k = 1, #matched do
                    local entry = matched[k]

                    newItem.lootData[#newItem.lootData+1] = entry
                    addVariant(self, newItem, entry, item)
                end

                newItem.characters[#newItem.characters+1] = {
                    key = history.key,
                    name = history.name,
                    isCurrent = history.isCurrent,
                    quantity = matchedQuantity,
                }
            end
        end
    end

    return items, hiddenCount
end

local function qualityMatches(quality, active)
    if (active.exactQuality) then return quality == active.quality end

    return quality >= active.quality
end

-- The variant a row stands for: the best quality, then the most looted.
local function bestVariant(variants)
    local best = nil

    for i = 1, #variants do
        local variant = variants[i]

        if (not best or (variant.quality or 0) > (best.quality or 0)
            or ((variant.quality or 0) == (best.quality or 0) and variant.quantity > best.quantity)) then
            best = variant
        end
    end

    return best
end

-- Name and icon come from the client's item cache. Link, quality and vendor price come from the links
-- the item dropped as, since the cache only knows the base item, never an upgraded drop.
local function applyItemCache(newItem, quality)
    local cachedName, cachedLink, cachedQuality, _, _, _, _, _, _, cachedTexture, cachedSellPrice =
        C_Item.GetItemInfo(newItem.itemId)

    local best = bestVariant(newItem.variants)

    newItem.itemLink = (best and best.link) or cachedLink or newItem.itemLink
    newItem.itemName = cachedName or newItem.itemName or ("#"..newItem.itemId)
    newItem.itemTexture = cachedTexture or newItem.itemTexture
    newItem.quality = newItem.quality or cachedQuality or quality

    for i = 1, #newItem.variants do
        local variant = newItem.variants[i]
        local linkSellPrice = variant.link and select(11, C_Item.GetItemInfo(variant.link)) or nil

        variant.vendorPrice = linkSellPrice or (not variant.link and cachedSellPrice)
            or variant.sellPrice or cachedSellPrice or 0
    end
end

local function byFoundOn(l, r)
    return (l.foundOn or 0) < (r.foundOn or 0)
end

-- Fills in the totals, zones, sources, prices and labels the report shows for a kept item.
local function finalizeItem(self, newItem, priceKey)
    table.sort(newItem.lootData, byFoundOn)

    newItem.totalQuantity, newItem.zones, newItem.firstFound, newItem.lastFound =
        self:aggregateLoot(newItem.lootData, L["R_UnknownZone"])

    newItem.zoneName = newItem.zones[1] and newItem.zones[1].name or L["R_UnknownZone"]

    newItem.sources = self:aggregateSources(newItem.lootData)
    newItem.sourceName = newItem.sources[1] and newItem.sources[1].name or ""

    -- Each variant is priced by its own link: a 323 drop is worth more than the 302 one.
    local totalValue, vendorValue, vendorPriced = 0, 0, false

    for i = 1, #newItem.variants do
        local variant = newItem.variants[i]
        local price, fellBack = self:getItemPrice(newItem.itemId, variant.vendorPrice, variant.link)

        totalValue = totalValue + price * variant.quantity
        vendorValue = vendorValue + variant.vendorPrice * variant.quantity
        vendorPriced = vendorPriced or fellBack
    end

    local quantity = math.max(newItem.totalQuantity, 1)

    newItem.totalValue = totalValue
    newItem.vendorValue = vendorValue
    newItem.vendorPriced = vendorPriced
    newItem.unitPrice = totalValue / quantity
    newItem.sellPrice = vendorValue / quantity
    newItem.marketValue = (priceKey ~= "vendor" and not newItem.vendorPriced)
        and newItem.totalValue or nil
    newItem.dateRange = formatDateRange(newItem.firstFound, newItem.lastFound)

    table.sort(newItem.characters, MLH.byQuantityThenName)

    newItem.charName = #newItem.characters > 1
        and L["R_SeveralCharacters"](#newItem.characters)
        or (newItem.characters[1] and newItem.characters[1].name or "")
end

-- How much of a report item dropped at each item level, lowest first. Empty when the client cannot say.
function MLH:getItemLevelBreakdown(item)
    local byLevel, levels = {}, {}
    local getLevel = C_Item.GetDetailedItemLevelInfo

    if (not getLevel or not item.variants) then return levels end

    for i = 1, #item.variants do
        local variant = item.variants[i]
        local level = variant.link and getLevel(variant.link)

        if (level) then
            if (not byLevel[level]) then
                byLevel[level] = { level = level, quantity = 0 }
                levels[#levels+1] = byLevel[level]
            end

            byLevel[level].quantity = byLevel[level].quantity + variant.quantity
        end
    end

    table.sort(levels, function(l, r) return l.level < r.level end)

    return levels
end

function MLH:collectItems()
    local active = self:getFilters()
    local search = active.search ~= "" and active.search:lower() or nil
    local priceKey = self:getPriceSource()
    local items, hiddenCount = mergeMatchingItems(self)
    local kept = {}

    for i = 1, #items do
        local newItem = items[i]
        local quality = newItem.quality or 0 -- records written before 1.1.0 can hold a nil quality
        local keep = qualityMatches(quality, active)

        -- The search matches the cached name, so the cache is applied first.
        applyItemCache(newItem, quality)

        if (keep and search and not newItem.itemName:lower():find(search, 1, true)) then
            keep = false
        end

        if (keep) then
            finalizeItem(self, newItem, priceKey)
            kept[#kept+1] = newItem
        end
    end

    self:sortItems(kept)

    return kept, hiddenCount
end

function MLH:sortItems(items)
    local active = self:getFilters()
    local key = active.sortKey
    local descending = active.sortDescending

    local value = function(item)
        if (key == "quantity") then return item.totalQuantity end
        if (key == "quality") then return item.quality end
        if (key == "value") then return item.vendorValue or item.totalValue end
        if (key == "market") then return item.marketValue or 0 end
        if (key == "lastLooted") then return item.lastFound or 0 end
        if (key == "zone") then return item.zoneName end
        if (key == "character") then return item.charName or "" end
        if (key == "source") then return item.sourceName or "" end

        return item.itemName
    end

    table.sort(items, function(l, r)
        local lv, rv = value(l), value(r)

        if (lv == rv) then
            return l.itemName < r.itemName
        end

        if (descending) then return lv > rv end

        return lv < rv
    end)
end

function MLH:buildReport()
    local items, hiddenCount = self:collectItems()
    local report = {
        items = items,
        currencies = {},
        gold = self:getFilters().search == "" and self:calculateGoldFound() or 0,
        totalQuantity = 0,
        totalValue = 0,
        totalVendorValue = 0,
        totalMarketValue = 0,
        currencyQuantity = 0,
        topValue = 0,
        zones = {},
        hiddenCount = hiddenCount or 0,
    }

    local zoneTotals = {}

    for i = 1, #items do
        local item = items[i]

        report.totalQuantity = report.totalQuantity + item.totalQuantity
        report.totalValue = report.totalValue + item.totalValue
        report.totalVendorValue = report.totalVendorValue + (item.vendorValue or item.totalValue)
        report.totalMarketValue = report.totalMarketValue + (item.marketValue or 0)
        report.topValue = math.max(report.topValue, item.totalValue)

        for j = 1, #item.zones do
            local zone = item.zones[j]

            zoneTotals[zone.name] = (zoneTotals[zone.name] or 0) + zone.quantity
        end
    end

    for name, quantity in pairs(zoneTotals) do
        report.zones[#report.zones+1] = { name = name, quantity = quantity }
    end

    table.sort(report.zones, MLH.byQuantityThenName)

    return report
end

function MLH:getActivityBuckets(hours)
    hours = hours or 24

    local now = time()
    local bucketStart = now - hours * 3600
    local buckets = {}

    for i = 1, hours do
        buckets[i] = { value = 0, quantity = 0 }
    end

    local function bucketFor(foundOn)
        if (foundOn == nil or foundOn < bucketStart) then return nil end

        local index = math.floor((foundOn - bucketStart) / 3600) + 1

        return buckets[math.min(math.max(index, 1), hours)]
    end

    local histories = self:getHistories()

    for h = 1, #histories do
        local history = histories[h]
        local foundItems = history.items

        for i = 1, #foundItems do
            local lootData = self:isItemHidden(foundItems[i].itemId) and {} or foundItems[i].lootData

            for j = #lootData, 1, -1 do
                local entry = lootData[j]

                if (entry.foundOn == nil or entry.foundOn < bucketStart) then break end

                local bucket = bucketFor(entry.foundOn)

                if (bucket) then
                    local quantity = tonumber(entry.quantity) or 1

                    bucket.quantity = bucket.quantity + quantity
                    bucket.value = bucket.value + (entry.sellPrice or 0) * quantity
                end
            end
        end

        local foundGold = history.gold

        for i = #foundGold, 1, -1 do
            local entry = foundGold[i]

            if (entry.foundOn == nil or entry.foundOn < bucketStart) then break end

            local bucket = bucketFor(entry.foundOn)

            if (bucket) then bucket.value = bucket.value + (entry.quantity or 0) end
        end
    end

    local peak = 0

    for i = 1, hours do
        peak = math.max(peak, buckets[i].value)
    end

    return buckets, peak, bucketStart
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

function MLH:formatMoneyShort(copper)
    copper = copper or 0

    local gold = math.floor(copper / 10000)
    local silver = math.floor(copper % 10000 / 100)
    local rest = math.floor(copper % 100)

    if (gold > 0) then
        return gold.."|cFFFFD700g|r "..silver.."|cFFC7C7CFs|r"
    end

    if (silver > 0) then
        return silver.."|cFFC7C7CFs|r "..rest.."|cFFEDA55Fc|r"
    end

    return rest.."|cFFEDA55Fc|r"
end

function MLH:formatGoldCompact(copper)
    local gold = math.floor((copper or 0) / 10000)

    if (gold >= 1000000) then
        return string.format("%.1fm", gold / 1000000)
    end

    if (gold >= 10000) then
        return string.format("%.1fk", gold / 1000)
    end

    local text = tostring(gold)
    local separated = text:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")

    return separated
end

local function csvField(value)
    value = tostring(value or "")

    if (value:find('[,"\n]')) then
        return '"'..value:gsub('"', '""')..'"'
    end

    return value
end

local function csvDate(timestamp)
    return timestamp and date("%Y-%m-%d %H:%M:%S", timestamp) or ""
end

local function csvTally(entries)
    local parts = {}

    for i = 1, #entries do
        parts[i] = entries[i].name.." ("..entries[i].quantity..")"
    end

    return table.concat(parts, "; ")
end

function MLH:buildCsv(report)
    report = report or self:buildReport()

    local items = report.items
    local lines = {
        "type,name,id,quality,quantity,value,marketValue,source,character,zone,firstLooted,lastLooted",
    }

    for i = 1, #items do
        local item = items[i]
        local qualityName = _G["ITEM_QUALITY"..(item.quality or 0).."_DESC"] or tostring(item.quality or 0)

        lines[#lines+1] = table.concat({
            "item",
            csvField(item.itemName),
            csvField(item.itemId),
            csvField(qualityName),
            csvField(item.totalQuantity),
            csvField(item.vendorValue or item.totalValue),
            item.marketValue and csvField(item.marketValue) or "",
            csvField(csvTally(item.sources or {})),
            csvField(csvTally(item.characters or {})),
            csvField(csvTally(item.zones)),
            csvField(csvDate(item.firstFound)),
            csvField(csvDate(item.lastFound)),
        }, ",")
    end

    return table.concat(lines, "\n"), #items
end

function MLH:buildCurrencyCsv(report)
    report = report or self:buildCurrencyReport()

    local rows = report.rows
    local lines = {
        "name,id,earned,perHour,held,capType,capCurrent,capMax,zone,firstLooted,lastLooted",
    }

    for i = 1, #rows do
        local row = rows[i]
        local cap = row.cap

        lines[#lines+1] = table.concat({
            csvField(row.name),
            csvField(row.currencyId),
            csvField(row.quantity),
            csvField(string.format("%.2f", row.perHour or 0)),
            row.held and csvField(row.held) or "",
            cap and csvField(cap.kind) or "",
            cap and csvField(cap.current) or "",
            cap and csvField(cap.max) or "",
            csvField(csvTally(row.zones)),
            csvField(csvDate(row.firstFound)),
            csvField(csvDate(row.lastFound)),
        }, ",")
    end

    return table.concat(lines, "\n"), #rows
end
