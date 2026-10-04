local wow = require("tests.support.wow")

wow.loadThrough("MyLootHistoryData.lua")

local MLH = wow.addon

local ORE, JUNK = 100, 200

local alerted = false

function MLH:getDropAlert() return { kind = "quality", value = 1 } end
function MLH:alertDrop() alerted = true end

local function seed()
    MLH:initDatabase()

    wow.freeze(os.time())

    local now = wow.now()
    local char = MLH.db.char

    char.thisSessionStart = now - 3600
    char.currentSessionID = nil

    char.foundItems = {
        {
            itemId = ORE, itemName = "Copper Ore", itemTexture = 1, quality = 1,
            lootData = { { quantity = 4, foundOn = now - 600, zoneID = 1, sellPrice = 100 } },
        },
        {
            itemId = JUNK, itemName = "Broken Fang", itemTexture = 1, quality = 0,
            lootData = { { quantity = 9, foundOn = now - 300, zoneID = 1, sellPrice = 5 } },
        },
    }

    char.foundGold = {}
    char.foundCurrency = {}

    MLH:setFilter("scope", "char")
    MLH:setFilter("session", 0)
    MLH:setFilter("range", MLH.RANGE_ALL)
    MLH:setFilter("quality", 0)
    MLH:setFilter("exactQuality", false)
    MLH:setFilter("zone", 0)
    MLH:setFilter("search", "")

    alerted = false
end

after_each(function() wow.unfreeze() end)

local function itemIds(items)
    local ids = {}

    for i = 1, #items do ids[i] = items[i].itemId end

    table.sort(ids)

    return ids
end

describe("hiding an item", function()
    before_each(seed)

    it("leaves it out of the report and counts it", function()
        MLH:setItemHidden(JUNK, true, "Broken Fang")

        local report = MLH:buildReport()

        assert.are.same({ ORE }, itemIds(report.items))
        assert.are.equal(1, report.hiddenCount)
        assert.are.equal(4, report.totalQuantity)
    end)

    it("does not count a hidden item the date range leaves out anyway", function()
        MLH:setItemHidden(JUNK, true)
        MLH.db.char.foundItems[2].lootData[1].foundOn = wow.now() - 90 * 86400
        MLH:setFilter("range", MLH.RANGE_TODAY)

        assert.are.equal(0, MLH:buildReport().hiddenCount)
    end)

    it("keeps its history, so unhiding brings it all back", function()
        MLH:setItemHidden(JUNK, true)
        MLH:setItemHidden(JUNK, false)

        local report = MLH:buildReport()

        assert.are.same({ ORE, JUNK }, itemIds(report.items))
        assert.are.equal(0, report.hiddenCount)
        assert.are.equal(13, report.totalQuantity)
    end)

    it("leaves it out of gold per hour and items per hour", function()
        MLH:setItemHidden(JUNK, true)

        local stats = MLH:getSessionStats()

        assert.are.equal(4, stats.quantity)
        assert.are.equal(400, stats.itemValue)
    end)

    it("leaves it out of the activity graph", function()
        MLH:setItemHidden(ORE, true)

        local _, peak = MLH:getActivityBuckets(24)

        assert.are.equal(9 * 5, peak)
    end)

    it("still records its loot, without an alert", function()
        MLH:setItemHidden(JUNK, true)

        _G.C_Item.GetItemInfo = function()
            return "Broken Fang", nil, 4, nil, nil, nil, nil, nil, nil, 1, 5, 15, 0
        end

        MLH:recordLoot(JUNK, nil, 2, 1, nil)

        _G.C_Item.GetItemInfo = function() return nil end

        assert.are.equal(2, #MLH.db.char.foundItems[2].lootData)
        assert.is_false(alerted)
    end)

    it("is shared by every character", function()
        MLH:setItemHidden(JUNK, true)

        assert.is_not_nil(MLH.db.global.hiddenItems[JUNK])
    end)

    it("lists the hidden items by name", function()
        MLH:setItemHidden(ORE, true, "Copper Ore")
        MLH:setItemHidden(JUNK, true, "Broken Fang")

        local list = MLH:getHiddenItemList()

        assert.are.equal("Broken Fang", list[1].name)
        assert.are.equal("Copper Ore", list[2].name)
    end)

    it("tells the report it has changed", function()
        local before = MLH.historyRevision

        MLH:setItemHidden(JUNK, true)

        assert.are_not.equal(before, MLH.historyRevision)
    end)
end)
