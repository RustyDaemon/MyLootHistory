--[[
My Loot History addon
Copyright (C) 2026 RustyDaemon (https://github.com/RustyDaemon)

See License file for details.
--]]

-- Builds the report from the histories in scope: one row per item, gold, currencies and activity.

local MLH = LibStub("AceAddon-3.0"):GetAddon("MyLootHistory")
local L = LibStub("AceLocale-3.0"):GetLocale("MyLootHistory")

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
