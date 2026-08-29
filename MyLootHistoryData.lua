--[[
My Loot History addon
Copyright (C) 2026 RustyDaemon (https://github.com/RustyDaemon)

See License file for details.
--]]

-- Everything the report shows, worked out from the stored history: the active filters, the
-- item and currency lists they select, the gold total, the dropdown contents, the last-24h
-- activity graph and the CSV export.
--
-- This used to live inside the report window, which meant the export and the rows could in
-- principle disagree about what "the current filters" selected. Here there is one filter
-- state and one list builder, and the window is only a way of looking at them.

local MLH = LibStub("AceAddon-3.0"):GetAddon("MyLootHistory")
local DU = LibStub("DateUtils-1.0")
local L = LibStub("AceLocale-3.0"):GetLocale("MyLootHistory")

-- The live filter state. Seeded from the saved params on first use, and written back to
-- them on every change, so it survives a reload and a UI recycle alike.
local filters = nil

local rangeKeys = {
    [1] = "RR_ThisSesion",
    [2] = "RR_Today",
    [3] = "RR_Yesterday",
    [4] = "RR_WedToWed",
    [5] = "RR_ThisMonth",
    [6] = "RR_AllTheTime",
}

-- The compact labels the segmented control uses. The full names are still what the
-- tooltips and the footer say.
local rangeShortKeys = {
    [1] = "RS_Session",
    [2] = "RS_Today",
    [3] = "RS_Yesterday",
    [4] = "RS_Reset",
    [5] = "RS_Month",
    [6] = "RS_All",
}

function MLH:getFilters()
    if (filters) then return filters end

    local params = self.db.char.params
    local descending = params.sortDescending

    if (descending == nil) then descending = true end

    filters = {
        range = params.selectedRangeValue or 2,
        quality = params.selectedQualityValue or 0,
        exactQuality = params.selectedExactItemQuality or false,
        zone = params.selectedZoneID or 0,
        search = params.searchText or "",
        sortKey = params.sortKey or "quantity",
        sortDescending = descending,
    }

    return filters
end

-- One place that writes a filter, so nothing can change the state without persisting it.
function MLH:setFilter(key, value)
    local active = self:getFilters()

    active[key] = value

    local params = self.db.char.params
    local paramKeys = {
        range = "selectedRangeValue",
        quality = "selectedQualityValue",
        exactQuality = "selectedExactItemQuality",
        zone = "selectedZoneID",
        search = "searchText",
        sortKey = "sortKey",
        sortDescending = "sortDescending",
    }

    params[paramKeys[key]] = value
end

function MLH:resetFilters()
    self:setFilter("range", 6)
    self:setFilter("quality", 0)
    self:setFilter("exactQuality", false)
    self:setFilter("zone", 0)
    self:setFilter("search", "")
end

-- True when the view is showing something narrower than the whole history, which is what
-- decides whether the empty state offers to clear the filters.
function MLH:hasActiveFilters()
    local active = self:getFilters()

    return active.range ~= 6 or active.quality ~= 0 or active.exactQuality
        or active.zone ~= 0 or active.search ~= ""
end

-- The one place the date range is turned into a yes/no about a single record. Items,
-- gold and currency all ask it, so the three can never drift apart.
function MLH:isInSelectedRange(foundOn)
    local range = self:getFilters().range

    -- An entry written by a very old version can carry no timestamp, and there is no way to
    -- place it in or out of a bounded range: comparing it against the session start errored,
    -- and date("*t", nil) reads the clock, which made it look like it was looted today. It
    -- belongs to "all the time" alone, which is the only range that asks nothing of the date.
    if (foundOn == nil) then return range == 6 end

    if (range == 1) then --this session
        local sessionStart = self.db.char.thisSessionStart

        return sessionStart ~= nil and foundOn >= sessionStart
    elseif (range == 2) then --today
        return DU:dateIsToday(foundOn)
    elseif (range == 3) then --yesterday
        return DU:dateIsYesterday(foundOn, true)
    elseif (range == 4) then --this reset
        local wday = DU:getToday().wday

        if (DU:isWed(wday)) then
            return DU:dateIsToday(foundOn)
        end

        return DU:dateInRangeTillToday(foundOn, DU:getLastWed(wday))
    elseif (range == 5) then --this month
        return DU:dateIsInCurrentMonth(foundOn)
    elseif (range == 6) then --all the time
        return true
    end

    return false
end

function MLH:isInSelectedZone(zoneID)
    local zone = self:getFilters().zone

    return zone == 0 or zoneID == zone
end

function MLH:calculateGoldFound()
    local gold = self.db.char.foundGold
    local total = 0

    for i = 1, #gold do
        local entry = gold[i]

        if (self:isInSelectedZone(entry.zoneID) and self:isInSelectedRange(entry.foundOn)) then
            total = total + entry.quantity
        end
    end

    return total
end

-- Every currency the character picked up inside the active date range and zone, busiest
-- first. The quality filter is about items and does not apply here, but the search box is a
-- name filter and a currency has a name, so that one does.
function MLH:collectCurrencies()
    local foundCurrency = self.db.char.foundCurrency or {}
    local search = self:getFilters().search
    local currencies = {}

    search = search ~= "" and search:lower() or nil

    for i = 1, #foundCurrency do
        local record = foundCurrency[i]
        local lootData = record.lootData
        local matched = {}

        for j = 1, #lootData do
            local entry = lootData[j]

            if (self:isInSelectedZone(entry.zoneID) and self:isInSelectedRange(entry.foundOn)) then
                matched[#matched+1] = entry
            end
        end

        local quantity, zones, firstFound, lastFound = self:aggregateLoot(matched, L["R_UnknownZone"])

        -- the client wins over the record: a currency can be renamed by a patch
        local info = C_CurrencyInfo.GetCurrencyInfo(record.currencyId)
        local name = (info and info.name) or record.currencyName or ("#"..record.currencyId)

        if (quantity > 0 and (not search or name:lower():find(search, 1, true))) then
            currencies[#currencies+1] = {
                currencyId = record.currencyId,
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

    table.sort(currencies, function(l, r)
        if (l.quantity == r.quantity) then return l.name < r.name end
        return l.quantity > r.quantity
    end)

    return currencies
end

-- Turns two timestamps into the "Looted" cell: one date when everything came from a single
-- day, a range when it did not, and nothing at all when no entry carries a date.
local function formatDateRange(firstFound, lastFound)
    -- With no dated entry at all there is nothing honest to show: date() reads the clock
    -- when it is handed a nil, which claimed the item was looted today.
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

-- Applies every active filter and resolves the display data, so the report window and the
-- CSV export always describe exactly the same set of items.
function MLH:collectItems()
    -- nothing below mutates the stored records, so they are read in place
    local itemsFound = self.db.char.foundItems
    local active = self:getFilters()
    local items = {}
    local search = active.search ~= "" and active.search:lower() or nil
    local priceKey = self:getPriceSource()

    for i = 1, #itemsFound do
        local item = itemsFound[i]

        -- a fresh shell holding references to the loot entries that pass the filters
        local newItem = {
            itemId = item.itemId,
            itemLink = item.itemLink,
            itemName = item.itemName,
            itemTexture = item.itemTexture,
            quality = item.quality,
            lootData = {},
            zones = {},
            totalQuantity = 0,
            totalValue = 0,
            dateRange = "",
        }

        for j = 1, #item.lootData do
            local lootData = item.lootData[j]

            if (self:isInSelectedZone(lootData.zoneID) and self:isInSelectedRange(lootData.foundOn)) then
                newItem.lootData[#newItem.lootData+1] = lootData
            end
        end

        if (#newItem.lootData > 0) then
            local quality = newItem.quality or 0 -- records written before 1.1.0 can hold a nil quality
            local canBeAdded

            if (not active.exactQuality and quality >= active.quality) then
                canBeAdded = true
            elseif (active.exactQuality and quality == active.quality) then
                canBeAdded = true
            else
                canBeAdded = false
            end

            -- the live client data wins over the record: names and prices can change between patches
            local cachedName, cachedLink, cachedQuality, _, _, _, _, _, _, cachedTexture, cachedSellPrice =
                C_Item.GetItemInfo(newItem.itemId)

            newItem.itemLink = cachedLink or newItem.itemLink
            newItem.itemName = cachedName or newItem.itemName or ("#"..newItem.itemId)
            newItem.itemTexture = cachedTexture or newItem.itemTexture
            newItem.quality = cachedQuality or quality
            newItem.sellPrice = cachedSellPrice

            if (canBeAdded and search and not newItem.itemName:lower():find(search, 1, true)) then
                canBeAdded = false
            end

            if (canBeAdded) then
                -- oldest first, so lootData[#] is the most recent find - which is the
                -- entry the fallback sell price below is read from
                table.sort(newItem.lootData, function(l, r) return (l.foundOn or 0) < (r.foundOn or 0) end)

                -- the quantities looted, not the number of loot events
                newItem.totalQuantity, newItem.zones, newItem.firstFound, newItem.lastFound =
                    self:aggregateLoot(newItem.lootData, L["R_UnknownZone"])

                newItem.zoneName = newItem.zones[1] and newItem.zones[1].name or L["R_UnknownZone"]

                -- an item the client has not cached this session has no price to read, so the
                -- one stamped on the most recent loot entry stands in for it
                if (newItem.sellPrice == nil) then
                    newItem.sellPrice = newItem.lootData[#newItem.lootData].sellPrice or 0
                end

                -- with an auction-house price source switched on this is the market price,
                -- and the vendor price whenever that source has nothing for the item
                newItem.unitPrice, newItem.vendorPriced =
                    self:getItemPrice(newItem.itemId, newItem.sellPrice, newItem.itemLink)
                newItem.totalValue = newItem.unitPrice * newItem.totalQuantity

                -- The vendor price is what the item is always worth, so it keeps its column
                -- whatever the source is; a market price sits beside it, and stays nil for
                -- the items the auction house had nothing to say about.
                newItem.vendorValue = newItem.sellPrice * newItem.totalQuantity
                newItem.marketValue = (priceKey ~= "vendor" and not newItem.vendorPriced)
                    and newItem.totalValue or nil
                newItem.dateRange = formatDateRange(newItem.firstFound, newItem.lastFound)

                items[#items+1] = newItem
            end
        end
    end

    self:sortItems(items)

    return items
end

function MLH:sortItems(items)
    local active = self:getFilters()
    local key = active.sortKey
    local descending = active.sortDescending

    local value = function(item)
        if (key == "quantity") then return item.totalQuantity end
        if (key == "quality") then return item.quality end
        if (key == "value") then return item.vendorValue or item.totalValue end
        -- items with no market price sort as worthless rather than as a nil
        if (key == "market") then return item.marketValue or 0 end
        -- an item whose entries are all undated sorts as the oldest there is, rather than
        -- putting a nil in front of table.sort's comparator
        if (key == "lastLooted") then return item.lastFound or 0 end
        if (key == "zone") then return item.zoneName end

        return item.itemName
    end

    table.sort(items, function(l, r)
        local lv, rv = value(l), value(r)

        if (lv == rv) then
            -- the name is the tie-break, so equal rows keep a stable, readable order
            return l.itemName < r.itemName
        end

        if (descending) then return lv > rv end

        return lv < rv
    end)
end

-- The whole view in one call: the rows, the totals and the headline numbers the summary
-- panel reads. Built once per redraw and handed around, so nothing walks the history twice.
function MLH:buildReport()
    local config = self.db.char.config
    local items = self:collectItems()
    local currencies = config.showCurrency and self:collectCurrencies() or {}
    local report = {
        items = items,
        currencies = currencies,
        -- The search box filters by name, and coins have none, so a search hides the money
        -- line rather than leaving it sitting under a list it has nothing to do with -
        -- which also means a search that matches nothing empties the window, as it should.
        gold = self:getFilters().search == "" and self:calculateGoldFound() or 0,
        totalQuantity = 0,
        totalValue = 0,
        -- the two columns totalled separately: vendor for every item, market for the ones
        -- the auction house actually had a price for
        totalVendorValue = 0,
        totalMarketValue = 0,
        currencyQuantity = 0,
        topValue = 0,
        zones = {},
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

    for i = 1, #currencies do
        report.currencyQuantity = report.currencyQuantity + currencies[i].quantity
    end

    for name, quantity in pairs(zoneTotals) do
        report.zones[#report.zones+1] = { name = name, quantity = quantity }
    end

    table.sort(report.zones, function(l, r)
        if (l.quantity == r.quantity) then return l.name < r.name end
        return l.quantity > r.quantity
    end)

    return report
end

-- ── activity graph ────────────────────────────────────────────────────────────

-- What the last `hours` hours were worth, one bucket an hour, newest last. Loot is stamped
-- with a time and nothing ever looked at it; a farming addon that cannot show you when you
-- were earning is missing the most interesting thing it knows.
--
-- Item value uses the price stamped on the entry rather than the live one: the buckets are
-- a shape, and asking the auction house for a price per entry would cost far more than the
-- graph is worth.
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

    local foundItems = self.db.char.foundItems

    for i = 1, #foundItems do
        local lootData = foundItems[i].lootData

        -- entries are appended in time order, so the walk runs backwards and stops as soon
        -- as it falls out of the window
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

    local foundGold = self.db.char.foundGold

    for i = #foundGold, 1, -1 do
        local entry = foundGold[i]

        if (entry.foundOn == nil or entry.foundOn < bucketStart) then break end

        local bucket = bucketFor(entry.foundOn)

        if (bucket) then bucket.value = bucket.value + (entry.quantity or 0) end
    end

    local peak = 0

    for i = 1, hours do
        peak = math.max(peak, buckets[i].value)
    end

    return buckets, peak, bucketStart
end

-- ── dropdown contents ─────────────────────────────────────────────────────────

-- Poor through Legendary. Artifact, Heirloom and WoW Token sit above it in the enum
-- and are not ordinary loot, so the range is named rather than trimmed off the end.
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

function MLH:getRangeList()
    local list = {}

    for i = 1, 6 do
        list[i] = { value = i, text = L[rangeKeys[i]] }
    end

    return list
end

function MLH:getRangeName(index)
    return L[rangeKeys[index or 2]]
end

function MLH:getShortRangeList()
    local list = {}

    for i = 1, 6 do
        list[i] = { value = i, text = L[rangeShortKeys[i]] }
    end

    return list
end

-- Every zone the character has ever looted in, named. Built from the whole history rather
-- than the current date range, so switching the range never empties the dropdown.
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

    collect(self.db.char.foundItems)
    collect(self.db.char.foundCurrency or {})

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

-- ── formatting ────────────────────────────────────────────────────────────────

-- GetMoneyString spells all three units out with icons, which is far too wide for a column.
-- This keeps the two units that matter and colours them the way the game does.
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

-- Gold alone, thousands-separated, for the places that have room for one number and no
-- room for three units - the stat cards and the graph tooltip.
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

-- ── CSV export ────────────────────────────────────────────────────────────────

local function csvField(value)
    value = tostring(value or "")

    if (value:find('[,"\n]')) then
        return '"'..value:gsub('"', '""')..'"'
    end

    return value
end

-- date() reads the clock when it is handed a nil, so an entry that carries no timestamp
-- would export as "looted right now". An empty cell is the truthful answer.
local function csvDate(timestamp)
    return timestamp and date("%Y-%m-%d %H:%M:%S", timestamp) or ""
end

local function csvZones(zones)
    local parts = {}

    for i = 1, #zones do
        parts[i] = zones[i].name.." ("..zones[i].quantity..")"
    end

    return table.concat(parts, "; ")
end

function MLH:buildCsv(report)
    report = report or self:buildReport()

    local items = report.items
    local currencies = report.currencies
    local lines = { "type,name,id,quality,quantity,value,marketValue,zone,firstLooted,lastLooted" }

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
            -- empty, not zero, when the auction house had no price for the item
            item.marketValue and csvField(item.marketValue) or "",
            csvField(csvZones(item.zones)),
            csvField(csvDate(item.firstFound)),
            csvField(csvDate(item.lastFound)),
        }, ",")
    end

    -- currencies have no quality and no value of either kind, so those cells stay empty
    for i = 1, #currencies do
        local currency = currencies[i]

        lines[#lines+1] = table.concat({
            "currency",
            csvField(currency.name),
            csvField(currency.currencyId),
            "",
            csvField(currency.quantity),
            "",
            "",
            csvField(csvZones(currency.zones)),
            csvField(csvDate(currency.firstFound)),
            csvField(csvDate(currency.lastFound)),
        }, ",")
    end

    return table.concat(lines, "\n"), #items + #currencies
end
