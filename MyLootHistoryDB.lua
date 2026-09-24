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
    global = {
        sourceNames = {},
    },

    char = {
        foundItems = {},
        foundGold = {},
        foundCurrency = {},
        thisSessionStart = time(),

        minimapData = {
            hide = false,
        },

        ui = {},

        config = {
            showLastLooted = false,
            showZone = false,
            trackLootSource = true,
            showSource = false,
            showItemID = false,
            showTooltip = true,
            showAdditionalTooltipData = false,
            showSessionBar = true,
            showHUD = false,
            hudLocked = false,
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

        sessions = {},

        params = {
            selectedView = "items", -- "items" or "currency", the two tabs of the report
            selectedScope = "char", -- "char" or "account"
            selectedSession = 0,    -- live, a session ID, or a legacy startedOn stamp
            selectedRangeValue = 2,
            selectedQualityValue = 0,
            selectedExactItemQuality = false,
            selectedZoneID = 0, -- 0 is "any zone"
            searchText = "",
            sortKey = "quantity",
            sortDescending = true,
            currencySortKey = "earned",
            currencySortDescending = true,
        },

        dbVersion = 1,
    },
}

local DB_VERSION = 2

local legacyMonths = {
    Jan = 1, Feb = 2, Mar = 3, Apr = 4,  May = 5,  Jun = 6,
    Jul = 7, Aug = 8, Sep = 9, Oct = 10, Nov = 11, Dec = 12,
}

local function parseLegacyDate(value)
    if (type(value) == "number") then return value end
    if (type(value) ~= "string") then return nil end

    local month, day, hour, min, sec, year =
        value:match("^%a+%s+(%a+)%s+(%d+)%s+(%d+):(%d+):(%d+)%s+(%d+)$")

    month = month and legacyMonths[month]

    if (not month) then return nil end

    return time({
        year = tonumber(year), month = month, day = tonumber(day),
        hour = tonumber(hour), min = tonumber(min), sec = tonumber(sec),
    })
end

local function legacyZoneID(source)
    local zone = source.zoneID or source.zone

    if (type(zone) == "number") then return zone end
    if (type(zone) == "table") then return zone.mapID or zone.uiMapID or zone.id or zone.zoneID end

    return nil
end

local function upgradeEntry(entry)
    entry.foundOn = parseLegacyDate(entry.foundOn)
    entry.zoneID = legacyZoneID(entry)
    entry.zone = nil
    entry.quantity = tonumber(entry.quantity) or 1
end

local function upgradeEntries(entries)
    for i = 1, #entries do upgradeEntry(entries[i]) end
end

local function upgradeRecords(records)
    for i = 1, #records do
        local record = records[i]

        if (type(record.lootData) == "table") then
            upgradeEntries(record.lootData)
        else
            record.lootData = { {
                quantity = tonumber(record.quantity) or 1,
                foundOn = parseLegacyDate(record.foundOn),
                zoneID = legacyZoneID(record),
                sellPrice = tonumber(record.sellPrice) or 0,
            } }

            record.quantity, record.foundOn, record.zone, record.sellPrice = nil, nil, nil, nil
        end
    end
end

function MLH:upgradeCharacterData(data)
    if (type(data) ~= "table" or data.dbVersion == DB_VERSION) then return false end

    upgradeRecords(data.foundItems or {})
    upgradeRecords(data.foundCurrency or {})
    upgradeEntries(data.foundGold or {})

    data.dbVersion = DB_VERSION

    return true
end

-- id -> position in foundItems/foundCurrency, keyed by the record's id field; built lazily.
local indexes = {}

local function buildIndex(records, key)
    local index = {}

    for i = 1, #records do
        local id = records[i][key]

        if (id ~= nil and index[id] == nil) then
            index[id] = i
        end
    end

    return index
end

local function totalQuantity(lootData)
    local total = 0

    for i = 1, #lootData do
        total = total + (tonumber(lootData[i].quantity) or 1)
    end

    return total
end

local function getIndex(records, key)
    if (not indexes[key]) then
        indexes[key] = buildIndex(records, key)
    end

    return indexes[key]
end

local function resetIndexes()
    indexes = {}
end

-- Report caches compare against this to know the history changed.
function MLH:bumpRevision()
    self.historyRevision = (self.historyRevision or 0) + 1
end

local function newLootEntry(self, quantity, zoneID)
    return {
        quantity = quantity,
        foundOn = time(),
        sessionID = self.db.char.currentSessionID,
        zoneID = zoneID,
    }
end

function MLH:initDatabase()
    self.db = ADB:New("MyLootHistoryDB", defaults)
    self:upgradeCharacterData(self.db.char)
    resetIndexes()
end

function MLH:getItemRecord(itemID)
    if (not itemID) then return nil end

    local foundItems = self.db.char.foundItems
    local index = getIndex(foundItems, "itemId")[itemID]

    return index and foundItems[index] or nil
end

function MLH:addGold(quantity, zoneID)
    self:bumpRevision()
    table.insert(self.db.char.foundGold, newLootEntry(self, quantity, zoneID))
end

function MLH:addItem(itemID, quantity, itemLink, itemTexture, itemQuality, itemName, zoneID, sellPrice, source)
    local foundItems = self.db.char.foundItems
    local index = getIndex(foundItems, "itemId")[itemID]

    self:bumpRevision()
    local newLootDataObj = newLootEntry(self, quantity, zoneID)
    newLootDataObj.sellPrice = sellPrice or 0
    newLootDataObj.source = source

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
        indexes.itemId[itemID] = #foundItems

        return quantity
    end

    local lootData = foundItems[index].lootData
    table.insert(lootData, newLootDataObj)

    return totalQuantity(lootData)
end

function MLH:addCurrency(currencyID, quantity, currencyName, currencyIcon, currencyQuality, zoneID)
    local foundCurrency = self.db.char.foundCurrency
    local index = getIndex(foundCurrency, "currencyId")[currencyID]

    self:bumpRevision()
    local newLootDataObj = newLootEntry(self, quantity, zoneID)

    if (index == nil) then
        table.insert(foundCurrency, {
            currencyId = currencyID,
            currencyName = currencyName,
            currencyIcon = currencyIcon,
            quality = currencyQuality,
            lootData = { newLootDataObj },
        })

        indexes.currencyId[currencyID] = #foundCurrency

        return quantity
    end

    local record = foundCurrency[index]
    local lootData = record.lootData

    record.currencyName = currencyName or record.currencyName
    record.currencyIcon = currencyIcon or record.currencyIcon
    record.quality = currencyQuality or record.quality

    table.insert(lootData, newLootDataObj)

    return totalQuantity(lootData)
end

-- Drops the elements failing keep(), in place, preserving order. keep() runs once per element,
-- first to last, so it may have side effects. Returns how many were dropped.
local function compact(list, keep)
    local kept = 0

    for i = 1, #list do
        local value = list[i]

        if (keep(value)) then
            kept = kept + 1
            list[kept] = value
        end
    end

    local removed = #list - kept

    for i = #list, kept + 1, -1 do
        list[i] = nil
    end

    return removed
end

local function pruneEntries(entries, cutoff)
    return compact(entries, function(entry)
        return entry.foundOn == nil or entry.foundOn >= cutoff
    end)
end

local function pruneRecords(records, cutoff)
    local removedEntries = 0

    local removedRecords = compact(records, function(record)
        removedEntries = removedEntries + pruneEntries(record.lootData, cutoff)

        return #record.lootData > 0
    end)

    return removedEntries, removedRecords
end

function MLH:pruneHistory(days)
    days = days or self.db.char.config.retentionDays or 0

    if (days <= 0) then return 0, 0 end

    local char = self.db.char
    local cutoff = time(DateUtils:getDate(-days, true))

    local removedEntries, removedRecords = pruneRecords(char.foundItems, cutoff)
    local currencyEntries, currencyRecords = pruneRecords(char.foundCurrency, cutoff)

    if (char.sessions) then
        compact(char.sessions, function(session)
            return (session.endedOn or session.startedOn or 0) >= cutoff
        end)
    end

    removedEntries = removedEntries + currencyEntries + pruneEntries(char.foundGold, cutoff)
    removedRecords = removedRecords + currencyRecords

    if (removedEntries > 0) then
        resetIndexes()
    end

    return removedEntries, removedRecords
end

function MLH:resetData()
    self:bumpRevision()
    self.db.char.foundItems = {}
    self.db.char.foundGold = {}
    self.db.char.foundCurrency = {}
    resetIndexes()

    self:clearPriceCache()

    self:debugPrint(L["M_DataWasCleared"])
end
