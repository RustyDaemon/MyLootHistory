--[[
My Loot History addon
Copyright (C) 2026 RustyDaemon (https://github.com/RustyDaemon)

See License file for details.
--]]

local MLH = LibStub("AceAddon-3.0"):GetAddon("MyLootHistory")
local ADB = LibStub("AceDB-3.0")
local DateUtils = LibStub("DateUtils-1.0")
local L = LibStub("AceLocale-3.0"):GetLocale("MyLootHistory")

local defaults = {
    char = {
        foundItems = {},
        foundGold = {},
        foundCurrency = {},
        thisSessionStart = time(),

        minimapData = {
            hide = false,
        },

        -- where the report window was left, and how big. Written when it is moved, resized
        -- or closed, so it comes back where the player put it.
        ui = {},

        config = {
            showLastLooted = false,
            showZone = false,
            showItemID = false,
            showTooltip = true,
            showAdditionalTooltipData = false,
            showSessionBar = true,
            showCurrency = true,
            trackCurrency = true,
            gameTooltipLine = true,
            priceSource = "vendor",
            retentionDays = 0, -- 0 is "keep everything", which is how every release before 1.4.0 behaved
            reportIconSize = 24,
            ignoreItemsWithZeroPrice = true,
            resizableReportWindow = false,
            debug = {
                printLootedSummary = false,
                printOtherDebugInfo = false,
            },
        },

        params = {
            selectedRangeValue = 2,
            selectedQualityValue = 0,
            selectedExactItemQuality = false,
            selectedZoneID = 0, -- 0 is "any zone"
            searchText = "",
            sortKey = "quantity",
            sortDescending = true,
        },

        dbVersion = 1,
    },
}

-- itemId -> index into db.char.foundItems, built once per session and kept in step with
-- inserts. Never saved: it is derived data, and the saved table is what it is derived from.
local itemIndex = nil

-- the same idea for db.char.foundCurrency, keyed by currencyId
local currencyIndex = nil

local function buildIndex(records, key)
    local index = {}

    for i = 1, #records do
        local id = records[i][key]

        -- first entry wins, matching the linear scan this replaces
        if (id ~= nil and index[id] == nil) then
            index[id] = i
        end
    end

    return index
end

-- Every loot entry a record holds, added up. Both addItem and addCurrency answer
-- with the new running total, and both were counting it out the same way.
local function totalQuantity(lootData)
    local total = 0

    for i = 1, #lootData do
        total = total + (tonumber(lootData[i].quantity) or 1)
    end

    return total
end

local function getItemIndex(foundItems)
    if (not itemIndex) then
        itemIndex = buildIndex(foundItems, "itemId")
    end

    return itemIndex
end

local function getCurrencyIndex(foundCurrency)
    if (not currencyIndex) then
        currencyIndex = buildIndex(foundCurrency, "currencyId")
    end

    return currencyIndex
end

function MLH:initDatabase()
    self.db = ADB:New("MyLootHistoryDB", defaults)
    itemIndex = nil
    currencyIndex = nil
end

-- The stored record for an item, or nil if it has never been looted. Used by the tooltip
-- hook, which runs on every item tooltip in the UI and so must not scan the history.
function MLH:getItemRecord(itemID)
    if (not itemID) then return nil end

    local foundItems = self.db.char.foundItems
    local index = getItemIndex(foundItems)[itemID]

    return index and foundItems[index] or nil
end

function MLH:addGold(quantity, zoneID)
    table.insert(self.db.char.foundGold, {
        quantity = quantity,
        foundOn = time(),
        zoneID = zoneID
    })
end

function MLH:addItem(itemID, quantity, itemLink, itemTexture, itemQuality, itemName, zoneID, sellPrice)
    local foundItems = self.db.char.foundItems
    local index = getItemIndex(foundItems)[itemID]

    local newLootDataObj = {
        quantity = quantity,
        foundOn = time(),
        zoneID = zoneID,
        sellPrice = sellPrice or 0,
    }

    if (index == nil) then
        local newItem = {
            itemId = itemID,
            itemLink = itemLink,
            itemName = itemName,
            itemTexture = itemTexture,
            quality = itemQuality,
            lootData = { newLootDataObj },
        }

        table.insert(foundItems, newItem)
        itemIndex[itemID] = #foundItems

        return quantity
    end

    local lootData = foundItems[index].lootData
    table.insert(lootData, newLootDataObj)

    return totalQuantity(lootData)
end

function MLH:addCurrency(currencyID, quantity, currencyName, currencyIcon, currencyQuality, zoneID)
    local foundCurrency = self.db.char.foundCurrency
    local index = getCurrencyIndex(foundCurrency)[currencyID]

    local newLootDataObj = {
        quantity = quantity,
        foundOn = time(),
        zoneID = zoneID,
    }

    if (index == nil) then
        table.insert(foundCurrency, {
            currencyId = currencyID,
            currencyName = currencyName,
            currencyIcon = currencyIcon,
            quality = currencyQuality,
            lootData = { newLootDataObj },
        })

        currencyIndex[currencyID] = #foundCurrency

        return quantity
    end

    local record = foundCurrency[index]
    local lootData = record.lootData

    -- a currency can be renamed or re-iconed by a patch, so the record follows the client
    record.currencyName = currencyName or record.currencyName
    record.currencyIcon = currencyIcon or record.currencyIcon
    record.quality = currencyQuality or record.quality

    table.insert(lootData, newLootDataObj)

    return totalQuantity(lootData)
end

-- Retention. `foundItems`, `foundGold` and `foundCurrency` otherwise grow for the life of the
-- install, and the only tool for that was the Clear Data button. Pruning compacts each table in
-- place - the saved variables are what the index is derived from, so it is the tables themselves
-- that have to shrink - and an entry carrying no timestamp is never dropped, since there is no
-- way to tell whether it is inside the window.
local function pruneEntries(entries, cutoff)
    local kept, removed = 0, 0

    for i = 1, #entries do
        local entry = entries[i]

        if (entry.foundOn == nil or entry.foundOn >= cutoff) then
            kept = kept + 1
            entries[kept] = entry
        else
            removed = removed + 1
        end
    end

    for i = #entries, kept + 1, -1 do
        entries[i] = nil
    end

    return removed
end

-- The same, one level down: each record's own lootData is pruned, and a record left holding
-- nothing goes with it.
local function pruneRecords(records, cutoff)
    local kept, removedEntries, removedRecords = 0, 0, 0

    for i = 1, #records do
        local record = records[i]

        removedEntries = removedEntries + pruneEntries(record.lootData, cutoff)

        if (#record.lootData > 0) then
            kept = kept + 1
            records[kept] = record
        else
            removedRecords = removedRecords + 1
        end
    end

    for i = #records, kept + 1, -1 do
        records[i] = nil
    end

    return removedEntries, removedRecords
end

-- Drops everything looted before midnight `days` days ago. Returns the number of loot entries
-- and whole records removed; 0, 0 when retention is off, which is the default.
function MLH:pruneHistory(days)
    days = days or self.db.char.config.retentionDays or 0

    if (days <= 0) then return 0, 0 end

    local char = self.db.char
    local cutoff = time(DateUtils:getDate(-days, true))

    local removedEntries, removedRecords = pruneRecords(char.foundItems, cutoff)
    local currencyEntries, currencyRecords = pruneRecords(char.foundCurrency, cutoff)

    removedEntries = removedEntries + currencyEntries + pruneEntries(char.foundGold, cutoff)
    removedRecords = removedRecords + currencyRecords

    if (removedEntries > 0) then
        itemIndex = nil
        currencyIndex = nil
    end

    return removedEntries, removedRecords
end

function MLH:resetData()
    self.db.char.foundItems = {}
    self.db.char.foundGold = {}
    self.db.char.foundCurrency = {}
    itemIndex = nil
    currencyIndex = nil

    -- the prices were cached against items that no longer exist here
    self:clearPriceCache()

    self:debugPrint(L["M_DataWasCleared"])
end
