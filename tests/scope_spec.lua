local wow = require("tests.support.wow")

_G.Enum.ItemQuality = { Poor = 0, Common = 1, Uncommon = 2, Rare = 3, Epic = 4, Legendary = 5 }

for i = 0, 5 do
    _G["ITEM_QUALITY"..i.."_DESC"] = "Quality"..i
end

wow.load("utils/DateUtils.lua")
wow.load("MyLootHistory.lua")
wow.load("MyLootHistoryDB.lua")
wow.load("MyLootHistoryScope.lua")
wow.load("MyLootHistorySource.lua")
wow.load("MyLootHistoryPrices.lua")
wow.load("MyLootHistorySession.lua")
wow.load("MyLootHistoryData.lua")

local MLH = wow.addon

local now = nil

local function seed()
    MLH:initDatabase()

    now = wow.now()

    local char = MLH.db.char

    char.thisSessionStart = now - 3600

    char.foundItems = {
        {
            itemId = 100, itemName = "Copper Ore", itemTexture = 1, quality = 1,
            lootData = { { quantity = 5, foundOn = now - 1800, zoneID = 1, sellPrice = 400 } },
        },
        {
            itemId = 200, itemName = "Bright Gem", itemTexture = 2, quality = 4,
            lootData = { { quantity = 1, foundOn = now - 300, zoneID = 1, sellPrice = 90000 } },
        },
    }

    char.foundGold = { { quantity = 10000, foundOn = now - 900, zoneID = 1 } }
    char.foundCurrency = {
        {
            currencyId = 3008, currencyName = "Valorstones", currencyIcon = 9, quality = 1,
            lootData = { { quantity = 40, foundOn = now - 700, zoneID = 1 } },
        },
    }

    wow.addCharacter(MLH.db, "Alt - Testrealm", {
        foundItems = {
            {
                itemId = 100, itemName = "Copper Ore", itemTexture = 1, quality = 1,
                lootData = { { quantity = 7, foundOn = now - 1200, zoneID = 2, sellPrice = 400 } },
            },
            {
                itemId = 300, itemName = "Silk Cloth", itemTexture = 3, quality = 1,
                lootData = { { quantity = 2, foundOn = now - 1100, zoneID = 2, sellPrice = 100 } },
            },
        },
        foundGold = { { quantity = 2500, foundOn = now - 1000, zoneID = 2 } },
    })

    MLH:setFilter("scope", "char")
    MLH:setFilter("session", 0)
    MLH:setFilter("range", 6)
    MLH:setFilter("quality", 0)
    MLH:setFilter("exactQuality", false)
    MLH:setFilter("zone", 0)
    MLH:setFilter("search", "")
    MLH:setFilter("sortKey", "quantity")
    MLH:setFilter("sortDescending", true)
end

local function itemById(report, id)
    for i = 1, #report.items do
        if (report.items[i].itemId == id) then return report.items[i] end
    end

    return nil
end

describe("MLH:getHistories", function()
    before_each(seed)

    it("is the logged-in character alone by default", function()
        local histories = MLH:getHistories()

        assert.are.equal(1, #histories)
        assert.is_true(histories[1].isCurrent)
        assert.are.equal("Tester", histories[1].name)
        assert.are.equal("Testrealm", histories[1].realm)
    end)

    it("covers every character in the account scope, the current one first", function()
        MLH:setFilter("scope", "account")

        local histories = MLH:getHistories()

        assert.are.equal(2, #histories)
        assert.is_true(histories[1].isCurrent)
        assert.are.equal("Alt", histories[2].name)
    end)

    it("hands back empty lists for whatever a sparse character is missing", function()
        MLH:setFilter("scope", "account")

        local alt = MLH:getHistories()[2]

        assert.are.equal(0, #alt.currency)
        assert.are.equal(0, #alt.sessions)
    end)
end)

describe("the account-wide report", function()
    before_each(seed)

    it("shows only this character until the scope is widened", function()
        local report = MLH:buildReport()

        assert.are.equal(2, #report.items)
        assert.are.equal(10000, report.gold)
        assert.are.equal(5, itemById(report, 100).totalQuantity)
    end)

    it("merges an item both characters looted into one row", function()
        MLH:setFilter("scope", "account")

        local report = MLH:buildReport()
        local ore = itemById(report, 100)

        assert.are.equal(3, #report.items)
        assert.are.equal(12, ore.totalQuantity)
        assert.are.equal(2, #ore.characters)
    end)

    it("names the character who found most of it, and counts them when there are several", function()
        MLH:setFilter("scope", "account")

        local report = MLH:buildReport()

        assert.are.equal("Alt", itemById(report, 100).characters[1].name)
        assert.are.equal(7, itemById(report, 100).characters[1].quantity)
        assert.are.equal("Tester", itemById(report, 200).charName)
    end)

    it("adds the coin up across characters too", function()
        MLH:setFilter("scope", "account")

        assert.are.equal(12500, MLH:buildReport().gold)
    end)

    it("keeps the zone filter working across characters", function()
        MLH:setFilter("scope", "account")
        MLH:setFilter("zone", 2)

        local report = MLH:buildReport()

        assert.are.equal(7, itemById(report, 100).totalQuantity)
        assert.are.equal(1, #itemById(report, 100).characters)
        assert.is_nil(itemById(report, 200))
    end)

    it("offers the zones every character has been to", function()
        MLH:setFilter("scope", "account")

        local zones = MLH:getZoneList()
        local names = {}

        for i = 1, #zones do names[zones[i].text] = true end

        assert.is_true(names["Zone 1"])
        assert.is_true(names["Zone 2"])
    end)

    it("narrows again when the scope goes back to this character", function()
        MLH:setFilter("scope", "account")
        assert.are.equal(3, #MLH:buildReport().items)

        MLH:setFilter("scope", "char")
        assert.are.equal(2, #MLH:buildReport().items)
    end)
end)
