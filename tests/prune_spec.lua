--[[
Retention is the only code in the addon that deletes a player's history, and it
deletes it in place - compacting the same tables the saved variables are written
from. A mistake here is unrecoverable for the player, and invisible until they
notice loot missing, so this is the file most worth having.

The index tests at the bottom are the subtle ones: pruning shifts every record's
position in foundItems, and the itemId -> index map has to be dropped when that
happens, or the tooltip starts reporting one item's history under another's name.
--]]

local wow = require("tests.support.wow")

wow.load("utils/DateUtils.lua")
wow.load("MyLootHistory.lua")     -- the core, for MLH:debugPrint
wow.load("MyLootHistoryDB.lua")

local MLH = wow.addon

local DAY = 86400
local NOW = os.time({ year = 2026, month = 6, day = 17, hour = 14, min = 30, sec = 0 })

-- A loot entry `daysAgo` days before the frozen clock. Fractional days are
-- allowed so an entry can be placed just inside or just outside a cutoff.
local function entry(daysAgo, quantity, zoneID)
    return {
        quantity = quantity or 1,
        foundOn = NOW - math.floor(daysAgo * DAY),
        zoneID = zoneID or 1,
        sellPrice = 100,
    }
end

local function record(itemId, entries)
    return { itemId = itemId, itemName = "Item "..itemId, lootData = entries }
end

-- Rebuilds the database from scratch, so no test can leak state into the next.
local function withHistory(history)
    MLH:initDatabase()

    local char = MLH.db.char

    char.foundItems = history.foundItems or {}
    char.foundGold = history.foundGold or {}
    char.foundCurrency = history.foundCurrency or {}
    char.config.retentionDays = history.retentionDays or 0

    return char
end

local function itemIds(foundItems)
    local ids = {}

    for i = 1, #foundItems do ids[i] = foundItems[i].itemId end

    return ids
end

before_each(function() wow.freeze(NOW) end)
after_each(function() wow.unfreeze() end)

describe("MLH:pruneHistory with retention off", function()
    it("removes nothing when retentionDays is 0", function()
        local char = withHistory({
            retentionDays = 0,
            foundItems = { record(1, { entry(400), entry(1) }) },
            foundGold = { entry(400, 500) },
        })

        local removedEntries, removedRecords = MLH:pruneHistory()

        assert.are.equal(0, removedEntries)
        assert.are.equal(0, removedRecords)
        assert.are.equal(2, #char.foundItems[1].lootData)
        assert.are.equal(1, #char.foundGold)
    end)

    it("removes nothing when retentionDays is negative", function()
        local char = withHistory({
            retentionDays = -5,
            foundItems = { record(1, { entry(400) }) },
        })

        assert.are.equal(0, MLH:pruneHistory())
        assert.are.equal(1, #char.foundItems)
    end)
end)

describe("MLH:pruneHistory entry pruning", function()
    it("drops entries older than the cutoff and keeps the rest", function()
        local char = withHistory({
            retentionDays = 30,
            foundItems = { record(1, { entry(90), entry(60), entry(5), entry(0) }) },
        })

        local removedEntries, removedRecords = MLH:pruneHistory()

        assert.are.equal(2, removedEntries)
        assert.are.equal(0, removedRecords)
        assert.are.equal(2, #char.foundItems[1].lootData)
    end)

    it("keeps an entry from earlier today", function()
        -- the cutoff is midnight `days` days ago, so today is always inside a
        -- retention window of one day or more
        local char = withHistory({
            retentionDays = 1,
            foundItems = { record(1, { entry(0) }) },
        })

        MLH:pruneHistory()

        assert.are.equal(1, #char.foundItems[1].lootData)
    end)

    it("never drops an entry that has no timestamp", function()
        -- there is no way to tell whether an undated entry is inside the window,
        -- so it stays; a record written by a very old version can look like this
        local char = withHistory({
            retentionDays = 30,
            foundItems = { record(1, { { quantity = 3, zoneID = 1 }, entry(90) }) },
        })

        assert.are.equal(1, MLH:pruneHistory())
        assert.are.equal(1, #char.foundItems[1].lootData)
        assert.are.equal(3, char.foundItems[1].lootData[1].quantity)
    end)

    it("leaves no holes in the compacted lootData", function()
        -- the entries are compacted in place, so every index from 1 to # has to be
        -- occupied; a hole would make # unreliable and silently truncate the table
        local char = withHistory({
            retentionDays = 30,
            foundItems = { record(1, { entry(90), entry(5), entry(90), entry(4), entry(90) }) },
        })

        MLH:pruneHistory()

        local lootData = char.foundItems[1].lootData

        assert.are.equal(2, #lootData)
        assert.is_not_nil(lootData[1])
        assert.is_not_nil(lootData[2])
        assert.is_nil(lootData[3])
    end)
end)

describe("MLH:pruneHistory record pruning", function()
    it("removes a record whose every entry aged out", function()
        local char = withHistory({
            retentionDays = 30,
            foundItems = {
                record(1, { entry(90), entry(80) }),
                record(2, { entry(2) }),
                record(3, { entry(200) }),
            },
        })

        local removedEntries, removedRecords = MLH:pruneHistory()

        assert.are.equal(3, removedEntries)
        assert.are.equal(2, removedRecords)
        assert.are.same({ 2 }, itemIds(char.foundItems))
    end)

    it("compacts the surviving records without holes", function()
        local char = withHistory({
            retentionDays = 30,
            foundItems = {
                record(1, { entry(90) }),
                record(2, { entry(1) }),
                record(3, { entry(90) }),
                record(4, { entry(1) }),
                record(5, { entry(90) }),
            },
        })

        MLH:pruneHistory()

        assert.are.same({ 2, 4 }, itemIds(char.foundItems))
        assert.is_nil(char.foundItems[3])
    end)

    it("can empty the history entirely", function()
        local char = withHistory({
            retentionDays = 7,
            foundItems = { record(1, { entry(90) }), record(2, { entry(30) }) },
        })

        MLH:pruneHistory()

        assert.are.equal(0, #char.foundItems)
    end)
end)

describe("MLH:pruneHistory across the three histories", function()
    it("prunes gold, which is a flat list rather than records", function()
        local char = withHistory({
            retentionDays = 30,
            foundGold = { entry(90, 500), entry(3, 250), entry(1, 125) },
        })

        local removedEntries, removedRecords = MLH:pruneHistory()

        assert.are.equal(1, removedEntries)
        assert.are.equal(0, removedRecords)
        assert.are.equal(2, #char.foundGold)
        assert.are.equal(250, char.foundGold[1].quantity)
    end)

    it("prunes currency records the same way as items", function()
        local char = withHistory({
            retentionDays = 30,
            foundCurrency = {
                { currencyId = 3008, lootData = { entry(90), entry(2) } },
                { currencyId = 3009, lootData = { entry(60) } },
            },
        })

        local removedEntries, removedRecords = MLH:pruneHistory()

        assert.are.equal(2, removedEntries)
        assert.are.equal(1, removedRecords)
        assert.are.equal(1, #char.foundCurrency)
        assert.are.equal(3008, char.foundCurrency[1].currencyId)
    end)

    it("totals removals across items, currency and gold", function()
        withHistory({
            retentionDays = 30,
            foundItems = { record(1, { entry(90) }) },
            foundGold = { entry(90, 100), entry(90, 100) },
            foundCurrency = { { currencyId = 3008, lootData = { entry(90) } } },
        })

        local removedEntries, removedRecords = MLH:pruneHistory()

        assert.are.equal(4, removedEntries)
        assert.are.equal(2, removedRecords)
    end)

    it("honours an explicit days argument over the stored setting", function()
        local char = withHistory({
            retentionDays = 0,
            foundItems = { record(1, { entry(90) }), record(2, { entry(1) }) },
        })

        MLH:pruneHistory(30)

        assert.are.same({ 2 }, itemIds(char.foundItems))
    end)
end)

describe("MLH:getItemRecord after pruning", function()
    it("still finds the right record once positions have shifted", function()
        -- The index maps itemId -> position in foundItems. Pruning moves records
        -- to lower positions, so an index built before the prune points at the
        -- wrong record afterwards: ask for item 4 and get item 2's history.
        local char = withHistory({
            retentionDays = 30,
            foundItems = {
                record(1, { entry(90) }),
                record(2, { entry(1) }),
                record(3, { entry(90) }),
                record(4, { entry(1) }),
            },
        })

        -- force the index to be built while the old positions are still in place
        assert.are.equal(4, MLH:getItemRecord(4).itemId)

        MLH:pruneHistory()

        assert.are.equal(4, MLH:getItemRecord(4).itemId)
        assert.are.equal(2, MLH:getItemRecord(2).itemId)
        assert.are.equal(4, char.foundItems[2].itemId)
    end)

    it("returns nil for a record that was pruned away", function()
        withHistory({
            retentionDays = 30,
            foundItems = { record(1, { entry(90) }), record(2, { entry(1) }) },
        })

        assert.are.equal(1, MLH:getItemRecord(1).itemId)

        MLH:pruneHistory()

        assert.is_nil(MLH:getItemRecord(1))
    end)

    it("returns nil for an item that was never looted", function()
        withHistory({ foundItems = { record(1, { entry(1) }) } })

        assert.is_nil(MLH:getItemRecord(99))
    end)

    it("returns nil when asked for no item at all", function()
        withHistory({ foundItems = { record(1, { entry(1) }) } })

        assert.is_nil(MLH:getItemRecord(nil))
    end)
end)

describe("MLH:resetData", function()
    it("clears all three histories and the index with them", function()
        withHistory({
            foundItems = { record(1, { entry(1) }) },
            foundGold = { entry(1, 100) },
            foundCurrency = { { currencyId = 3008, lootData = { entry(1) } } },
        })

        assert.are.equal(1, MLH:getItemRecord(1).itemId)

        MLH:resetData()

        assert.are.equal(0, #MLH.db.char.foundItems)
        assert.are.equal(0, #MLH.db.char.foundGold)
        assert.are.equal(0, #MLH.db.char.foundCurrency)
        assert.is_nil(MLH:getItemRecord(1))
    end)
end)
