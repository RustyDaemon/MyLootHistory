--[[
My Loot History addon
Copyright (C) 2026 RustyDaemon (https://github.com/RustyDaemon)

See License file for details.
--]]

local MLH = LibStub("AceAddon-3.0"):GetAddon("MyLootHistory")
local DU = LibStub("DateUtils-1.0")
local L = LibStub("AceLocale-3.0"):GetLocale("MyLootHistory")

local filters = nil

local rangeKeys = {
    [1] = "RR_ThisSesion",
    [2] = "RR_Today",
    [3] = "RR_Yesterday",
    [4] = "RR_WedToWed",
    [5] = "RR_ThisMonth",
    [6] = "RR_AllTheTime",
}

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
    local currencyDescending = params.currencySortDescending

    if (descending == nil) then descending = true end
    if (currencyDescending == nil) then currencyDescending = true end

    filters = {
        view = params.selectedView or "items",
        scope = params.selectedScope or "char",
        session = params.selectedSession or 0,
        range = params.selectedRangeValue or 2,
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

    local params = self.db.char.params
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

    params[paramKeys[key]] = value
end

function MLH:resetFilters()
    self:setFilter("range", 6)
    self:setFilter("quality", 0)
    self:setFilter("exactQuality", false)
    self:setFilter("zone", 0)
    self:setFilter("search", "")
end

function MLH:hasActiveFilters()
    local active = self:getFilters()

    return active.range ~= 6 or active.quality ~= 0 or active.exactQuality
        or active.zone ~= 0 or active.search ~= ""
end

function MLH:isInSelectedRange(foundOn, entry)
    local range = self:getFilters().range

    -- Undated legacy entries belong only to the unbounded date range.
    if (foundOn == nil) then return range == 6 end

    if (range == 1) then --the selected session, live or finished
        local session = self:getSelectedSession()

        if (entry) then return self:isEntryInSession(entry, session) end

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

    table.sort(currencies, function(l, r)
        if (l.quantity == r.quantity) then return l.name < r.name end
        return l.quantity > r.quantity
    end)

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

function MLH:collectItems()
    local active = self:getFilters()
    local items = {}
    local search = active.search ~= "" and active.search:lower() or nil
    local priceKey = self:getPriceSource()

    local histories = self:getHistories()
    local byItemId = {}

    for h = 1, #histories do
        local history = histories[h]
        local itemsFound = history.items

        for i = 1, #itemsFound do
            local item = itemsFound[i]
            local matched = {}
            local matchedQuantity = 0

            for j = 1, #item.lootData do
                local lootData = item.lootData[j]

                if (self:isInSelectedZone(lootData.zoneID)
                    and self:isInSelectedRange(lootData.foundOn, lootData)) then
                    matched[#matched+1] = lootData
                    matchedQuantity = matchedQuantity + (tonumber(lootData.quantity) or 1)
                end
            end

            if (#matched > 0) then
                local newItem = byItemId[item.itemId]

                if (not newItem) then
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
                table.sort(newItem.lootData, function(l, r) return (l.foundOn or 0) < (r.foundOn or 0) end)

                newItem.totalQuantity, newItem.zones, newItem.firstFound, newItem.lastFound =
                    self:aggregateLoot(newItem.lootData, L["R_UnknownZone"])

                newItem.zoneName = newItem.zones[1] and newItem.zones[1].name or L["R_UnknownZone"]

                newItem.sources = self:aggregateSources(newItem.lootData)
                newItem.sourceName = newItem.sources[1] and newItem.sources[1].name or ""

                if (newItem.sellPrice == nil) then
                    newItem.sellPrice = newItem.lootData[#newItem.lootData].sellPrice or 0
                end

                newItem.unitPrice, newItem.vendorPriced =
                    self:getItemPrice(newItem.itemId, newItem.sellPrice, newItem.itemLink)
                newItem.totalValue = newItem.unitPrice * newItem.totalQuantity

                newItem.vendorValue = newItem.sellPrice * newItem.totalQuantity
                newItem.marketValue = (priceKey ~= "vendor" and not newItem.vendorPriced)
                    and newItem.totalValue or nil
                newItem.dateRange = formatDateRange(newItem.firstFound, newItem.lastFound)

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
    local items = self:collectItems()
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

    table.sort(report.zones, function(l, r)
        if (l.quantity == r.quantity) then return l.name < r.name end
        return l.quantity > r.quantity
    end)

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
            local lootData = foundItems[i].lootData

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
