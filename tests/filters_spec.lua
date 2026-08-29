--[[
The filter state and the lists it selects.

Every number the report shows comes out of MLH:buildReport, and every filter in the window
narrows it: the date range, the zone, the quality, the search box. They are worth pinning
down because they interact - "epic items, this reset, in Hallowfall, called 'ore'" has to
mean the intersection of four things, and a mistake in any one of them looks like a report
that is merely a bit short rather than a report that is wrong.

The awkward record types are here too: one written before quality was stored, and one
written before timestamps were, which belongs to "all the time" and to no bounded range.
--]]

local wow = require("tests.support.wow")

_G.Enum.ItemQuality = { Poor = 0, Common = 1, Uncommon = 2, Rare = 3, Epic = 4, Legendary = 5 }

for i = 0, 5 do
    _G["ITEM_QUALITY"..i.."_DESC"] = "Quality"..i
end

-- the client wins over the stored record for a currency's name, so the stub has to answer
-- with the name the specs below search for
_G.C_CurrencyInfo.GetCurrencyInfo = function(id)
    return { name = "Valorstones", iconFileID = id, quality = 1 }
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
            lootData = {
                { quantity = 5, foundOn = now - 1800, zoneID = 1, sellPrice = 400 },
                { quantity = 3, foundOn = now - 600, zoneID = 2, sellPrice = 400 },
            },
        },
        {
            itemId = 200, itemName = "Bright Gem", itemTexture = 2, quality = 4,
            lootData = { { quantity = 1, foundOn = now - 300, zoneID = 1, sellPrice = 90000 } },
        },
        -- written by a version that stored neither a quality nor a timestamp
        {
            itemId = 300, itemName = "Ancient Relic", itemTexture = 3,
            lootData = { { quantity = 2, zoneID = 1 } },
        },
    }

    char.foundGold = {
        { quantity = 12345, foundOn = now - 900, zoneID = 1 },
        { quantity = 500, foundOn = now - 100, zoneID = 2 },
    }

    char.foundCurrency = {
        {
            currencyId = 3008, currencyName = "Valorstones", currencyIcon = 9, quality = 1,
            lootData = { { quantity = 40, foundOn = now - 700, zoneID = 1 } },
        },
    }

    MLH:setFilter("range", 6)
    MLH:setFilter("quality", 0)
    MLH:setFilter("exactQuality", false)
    MLH:setFilter("zone", 0)
    MLH:setFilter("search", "")
    MLH:setFilter("sortKey", "quantity")
    MLH:setFilter("sortDescending", true)
end

describe("MLH:buildReport", function()
    before_each(seed)

    it("adds up every item, coin and currency in range", function()
        local report = MLH:buildReport()

        assert.are.equal(3, #report.items)
        assert.are.equal(11, report.totalQuantity)
        assert.are.equal(5 * 400 + 3 * 400 + 90000, report.totalValue)
        assert.are.equal(12845, report.gold)
        assert.are.equal(1, #report.currencies)
        assert.are.equal(40, report.currencies[1].quantity)
    end)

    it("knows the most valuable row, which is what the row bars are scaled to", function()
        assert.are.equal(90000, MLH:buildReport().topValue)
    end)

    it("ranks the zones by how much came out of them", function()
        local zones = MLH:buildReport().zones

        assert.are.equal("Zone 1", zones[1].name)
        assert.are.equal(8, zones[1].quantity)
    end)

    it("survives every date range the filter bar offers", function()
        for range = 1, 6 do
            MLH:setFilter("range", range)

            assert.has_no.errors(function() MLH:buildReport() end)
        end
    end)

    it("does not fall over on an empty history", function()
        MLH.db.char.foundItems = {}
        MLH.db.char.foundGold = {}
        MLH.db.char.foundCurrency = {}

        assert.has_no.errors(function()
            local report = MLH:buildReport()

            MLH:buildCsv(report)
        end)
    end)
end)

describe("the filters", function()
    before_each(seed)

    it("leaves an undated record out of every bounded range", function()
        MLH:setFilter("range", 2)

        assert.are.equal(2, #MLH:collectItems())
    end)

    it("keeps an undated record under 'all the time'", function()
        assert.are.equal(3, #MLH:collectItems())
    end)

    it("narrows to the items whose name contains the search text", function()
        MLH:setFilter("search", "gem")

        assert.are.equal(1, #MLH:collectItems())
    end)

    it("applies the search to currencies too, since they have names", function()
        MLH:setFilter("search", "gem")

        assert.are.equal(0, #MLH:collectCurrencies())

        MLH:setFilter("search", "valor")

        assert.are.equal(1, #MLH:collectCurrencies())
    end)

    -- coins have no name to match, so leaving the money line under a name search would
    -- mean a search matching nothing still showed a row
    it("hides the money line while a search is active", function()
        MLH:setFilter("search", "gem")

        assert.are.equal(0, MLH:buildReport().gold)
    end)

    it("treats the quality filter as a minimum by default", function()
        MLH:setFilter("quality", 4)

        assert.are.equal(1, #MLH:collectItems())
    end)

    it("matches one quality exactly when asked to", function()
        MLH:setFilter("exactQuality", true)
        MLH:setFilter("quality", 1)

        assert.are.equal(1, #MLH:collectItems())
    end)

    it("narrows the items and the gold to one zone together", function()
        MLH:setFilter("zone", 2)

        assert.are.equal(1, #MLH:collectItems())
        assert.are.equal(500, MLH:calculateGoldFound())
    end)

    it("reports whether anything is narrowing the view", function()
        assert.is_false(MLH:hasActiveFilters())

        MLH:setFilter("range", 1)

        assert.is_true(MLH:hasActiveFilters())

        MLH:resetFilters()

        assert.is_false(MLH:hasActiveFilters())
    end)

    it("writes every change through to the saved params", function()
        MLH:setFilter("zone", 2)
        MLH:setFilter("sortKey", "value")

        assert.are.equal(2, MLH.db.char.params.selectedZoneID)
        assert.are.equal("value", MLH.db.char.params.sortKey)
    end)
end)

describe("sorting", function()
    before_each(seed)

    it("handles every column the header offers", function()
        for _, key in ipairs({ "quality", "name", "quantity", "value", "zone", "lastLooted" }) do
            MLH:setFilter("sortKey", key)

            assert.has_no.errors(function() MLH:collectItems() end)
        end
    end)

    it("puts the most valuable first when sorting by value, descending", function()
        MLH:setFilter("sortKey", "value")
        MLH:setFilter("sortDescending", true)

        assert.are.equal("Bright Gem", MLH:collectItems()[1].itemName)
    end)

    it("reverses when asked to", function()
        MLH:setFilter("sortKey", "value")
        MLH:setFilter("sortDescending", false)

        assert.are.equal("Bright Gem", MLH:collectItems()[#MLH:collectItems()].itemName)
    end)
end)

describe("the dropdown contents", function()
    before_each(seed)

    it("offers six date ranges, long and short", function()
        assert.are.equal(6, #MLH:getRangeList())
        assert.are.equal(6, #MLH:getShortRangeList())
    end)

    it("offers Poor through Legendary", function()
        assert.are.equal(6, #MLH:getQualityList())
    end)

    it("lists every zone the character has looted in, plus 'any'", function()
        assert.are.equal(3, #MLH:getZoneList())
    end)
end)

describe("the activity graph", function()
    before_each(seed)

    it("buckets the last day by the hour", function()
        local buckets, _, bucketStart = MLH:getActivityBuckets(24)

        assert.are.equal(24, #buckets)
        assert.are.equal(wow.now() - 24 * 3600, bucketStart)
    end)

    it("counts every dated find, coins included", function()
        local buckets = MLH:getActivityBuckets(24)
        local total = 0

        for i = 1, 24 do total = total + buckets[i].value end

        assert.are.equal(5 * 400 + 3 * 400 + 90000 + 12845, total)
    end)

    -- the graph ignores the filters on purpose: it is the shape of the day, not of the view
    it("is not narrowed by the date filter", function()
        MLH:setFilter("range", 1)

        local _, peak = MLH:getActivityBuckets(24)

        assert.is_true(peak > 0)
    end)
end)

describe("money formatting", function()
    before_each(seed)

    it("separates thousands below ten thousand gold", function()
        assert.are.equal("9,876", MLH:formatGoldCompact(9876 * 10000))
    end)

    it("switches to k above it", function()
        assert.are.equal("12.3k", MLH:formatGoldCompact(123456789))
    end)

    it("switches to m above a million", function()
        assert.are.equal("1.5m", MLH:formatGoldCompact(1500000 * 10000))
    end)

    it("rounds down to whole gold", function()
        assert.are.equal("4", MLH:formatGoldCompact(45000))
    end)
end)

describe("the CSV export", function()
    before_each(seed)

    it("writes a header and one line per row", function()
        local csv, count = MLH:buildCsv()
        local lines = 0

        for _ in csv:gmatch("[^\n]+") do lines = lines + 1 end

        assert.are.equal(4, count)
        assert.are.equal(count + 1, lines)
    end)

    it("describes exactly what the report is showing", function()
        MLH:setFilter("search", "gem")

        local _, count = MLH:buildCsv()

        assert.are.equal(1, count)
    end)
end)
