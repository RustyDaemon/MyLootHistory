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
        scope = params.selectedScope or "char",
        session = params.selectedSession or 0,
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
        scope = "selectedScope",
        session = "selectedSession",
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

    if (range == 1) then --the selected session, live or finished
        local session = self:getSelectedSession()

        if (session.startedOn == nil or foundOn < session.startedOn) then return false end

        return session.endedOn == nil or foundOn <= session.endedOn
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
    local histories = self:getHistories()
    local total = 0

    for h = 1, #histories do
        local history = histories[h]
        local gold = history.gold

        for i = 1, #gold do
            local entry = gold[i]

            if (self:isInSelectedZone(entry.zoneID) and self:isInSelectedRange(entry.foundOn)) then
                total = total + entry.quantity
            end
        end
    end

    return total
end

-- Every currency the character picked up inside the active date range and zone, busiest
-- first. The quality filter is about items and does not apply here, but the search box is a
-- name filter and a currency has a name, so that one does.
function MLH:collectCurrencies()
    local search = self:getFilters().search
    local currencies = {}
    local histories = self:getHistories()
    local matchedById = {}
    local recordById = {}
    local order = {}

    search = search ~= "" and search:lower() or nil

    -- the same merge the items get: one row per currency, however many characters earned it
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

                if (self:isInSelectedZone(entry.zoneID) and self:isInSelectedRange(entry.foundOn)) then
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

        -- the client wins over the record: a currency can be renamed by a patch
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
    local active = self:getFilters()
    local items = {}
    local search = active.search ~= "" and active.search:lower() or nil
    local priceKey = self:getPriceSource()

    -- One character or every character on the account, depending on the scope. An item
    -- looted by three of them is one row: the history is about the item, and which
    -- characters found it is something the row says, not something that splits it.
    local histories = self:getHistories()
    local byItemId = {}

    for h = 1, #histories do
        local history = histories[h]
        local itemsFound = history.items

        for i = 1, #itemsFound do
            local item = itemsFound[i]
            -- nothing below mutates the stored records, so they are read in place
            local matched = {}
            local matchedQuantity = 0

            for j = 1, #item.lootData do
                local lootData = item.lootData[j]

                if (self:isInSelectedZone(lootData.zoneID)
                    and self:isInSelectedRange(lootData.foundOn)) then
                    matched[#matched+1] = lootData
                    matchedQuantity = matchedQuantity + (tonumber(lootData.quantity) or 1)
                end
            end

            if (#matched > 0) then
                local newItem = byItemId[item.itemId]

                if (not newItem) then
                    -- a fresh shell holding references to the loot entries that pass the filters
                    newItem = {
                        itemId = item.itemId,
                        itemLink = item.itemLink,
                        itemName = item.itemName,
                        itemTexture = item.itemTexture,
                        quality = item.quality,
                        lootData = {},
                        zones = {},
                        characters = {},
                        totalQuantity = 0,
                        totalValue = 0,
                        dateRange = "",
                    }

                    byItemId[item.itemId] = newItem
                    items[#items+1] = newItem
                else
                    -- a record written by a character who saw the item when the client had
                    -- more to say about it fills in what an emptier record is missing
                    newItem.itemLink = newItem.itemLink or item.itemLink
                    newItem.itemName = newItem.itemName or item.itemName
                    newItem.itemTexture = newItem.itemTexture or item.itemTexture
                    newItem.quality = newItem.quality or item.quality
                end

                for k = 1, #matched do
                    newItem.lootData[#newItem.lootData+1] = matched[k]
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

    -- Resolving the display data and applying the filters that read it - quality, and the
    -- search box, which matches the name the client hands back rather than the stored one -
    -- happens once per merged item rather than once per record.
    local kept = {}

    for i = 1, #items do
        local newItem = items[i]

        do
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

                -- what it dropped from, for the entries that were recorded with a source;
                -- everything looted before source tracking existed simply has none
                newItem.sources = self:aggregateSources(newItem.lootData)
                newItem.sourceName = newItem.sources[1] and newItem.sources[1].name or ""

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

                -- who found it, most prolific first, so characters[1] is the one the row
                -- names where there is only room for one
                table.sort(newItem.characters, function(l, r)
                    if (l.quantity == r.quantity) then return l.name < r.name end
                    return l.quantity > r.quantity
                end)

                newItem.charName = #newItem.characters > 1
                    and L["R_SeveralCharacters"](#newItem.characters)
                    or (newItem.characters[1] and newItem.characters[1].name or "")

                kept[#kept+1] = newItem
            end
        end
    end

    self:sortItems(kept)

    return kept
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
        if (key == "character") then return item.charName or "" end
        if (key == "source") then return item.sourceName or "" end

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

    local histories = self:getHistories()

    for h = 1, #histories do
        local history = histories[h]
        local foundItems = history.items

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

-- "Hallowfall (12); Azj-Kahet (3)" - the shape the zone, source and character breakdowns
-- all share, so all three export the same way.
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
    local currencies = report.currencies
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
            -- empty, not zero, when the auction house had no price for the item
            item.marketValue and csvField(item.marketValue) or "",
            csvField(csvTally(item.sources or {})),
            csvField(csvTally(item.characters or {})),
            csvField(csvTally(item.zones)),
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
            "",
            "",
            csvField(csvTally(currency.zones)),
            csvField(csvDate(currency.firstFound)),
            csvField(csvDate(currency.lastFound)),
        }, ",")
    end

    return table.concat(lines, "\n"), #items + #currencies
end
