--[[
My Loot History addon
Copyright (C) 2026 RustyDaemon (https://github.com/RustyDaemon)

See License file for details.
--]]

local MLH = LibStub("AceAddon-3.0"):GetAddon("MyLootHistory")
local ADB = LibStub("AceDB-3.0")
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
    local totalQuantity = 0

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

    for i = 1, #lootData do
        totalQuantity = totalQuantity + lootData[i].quantity
    end

    return totalQuantity
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
    local totalQuantity = 0

    -- a currency can be renamed or re-iconed by a patch, so the record follows the client
    record.currencyName = currencyName or record.currencyName
    record.currencyIcon = currencyIcon or record.currencyIcon
    record.quality = currencyQuality or record.quality

    table.insert(lootData, newLootDataObj)

    for i = 1, #lootData do
        totalQuantity = totalQuantity + lootData[i].quantity
    end

    return totalQuantity
end

function MLH:resetData()
    self.db.char.foundItems = {}
    self.db.char.foundGold = {}
    self.db.char.foundCurrency = {}
    itemIndex = nil
    currencyIndex = nil
    MLH:updateStatisticsTextData()

    if (self.db.char.config.debug.printOtherDebugInfo) then
        print(L["M_DataWasCleared"])
    end
end
