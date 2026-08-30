--[[
The currency budget view.

Two things are worth pinning down here. The first is the window a rate is measured over:
"per hour" is a division, and the number it divides by is the only part of it the history
cannot answer on its own - every range but yesterday is still running, so it is measured up
to now rather than to its nominal end.

The second is the caps, which come out of the client rather than out of the history. A
currency can be capped weekly, capped over its lifetime, capped against everything ever
earned rather than against the balance in hand, or not capped at all, and the four have to
read differently rather than all collapsing to a full bar or an empty one.
--]]

local wow = require("tests.support.wow")

wow.load("utils/DateUtils.lua")
wow.load("MyLootHistory.lua")
wow.load("MyLootHistoryDB.lua")
wow.load("MyLootHistoryScope.lua")
wow.load("MyLootHistorySource.lua")
wow.load("MyLootHistoryPrices.lua")
wow.load("MyLootHistorySession.lua")
wow.load("MyLootHistoryData.lua")
wow.load("MyLootHistoryCurrency.lua")

local MLH = wow.addon

local now = nil

-- What the client says about each currency: 3008 has a weekly allowance, 3107 a season-long
-- cap counted against everything ever earned, and 3009 no cap at all.
local currencyInfo = {
    [3008] = {
        name = "Valorstones", iconFileID = 1, quality = 1,
        quantity = 1240, canEarnPerWeek = false, maxQuantity = 0,
    },
    [3107] = {
        name = "Runed Crest", iconFileID = 2, quality = 3,
        quantity = 36, maxQuantity = 90, useTotalEarnedForMaxQty = true, totalEarned = 90,
    },
    [3009] = {
        name = "Flightstone", iconFileID = 3, quality = 1,
        quantity = 4010, maxQuantity = 0,
    },
}

local function seed()
    MLH:initDatabase()

    wow.freeze(os.time())

    now = wow.now()

    local char = MLH.db.char

    char.thisSessionStart = now - 3600
    char.foundItems = {}
    char.foundGold = {}

    char.foundCurrency = {
        {
            currencyId = 3008, currencyName = "Valorstones", currencyIcon = 1, quality = 1,
            lootData = {
                { quantity = 300, foundOn = now - 5400, zoneID = 1 },
                { quantity = 120, foundOn = now - 900, zoneID = 2 },
            },
        },
        {
            currencyId = 3107, currencyName = "Runed Crest", currencyIcon = 2, quality = 3,
            lootData = { { quantity = 18, foundOn = now - 1800, zoneID = 1 } },
        },
        {
            currencyId = 3009, currencyName = "Flightstone", currencyIcon = 3, quality = 1,
            lootData = { { quantity = 900, foundOn = now - 600, zoneID = 1 } },
        },
    }

    MLH:setFilter("scope", "char")
    MLH:setFilter("view", "currency")
    MLH:setFilter("range", 6)
    MLH:setFilter("zone", 0)
    MLH:setFilter("search", "")
    MLH:setFilter("session", 0)
    MLH:setFilter("currencySort", "earned")
    MLH:setFilter("currencySortDescending", true)
end

local function rowFor(report, currencyId)
    for i = 1, #report.rows do
        if (report.rows[i].currencyId == currencyId) then return report.rows[i] end
    end
end

describe("the window a rate is measured over", function()
    before_each(seed)

    it("is the session's own length while the range is a session", function()
        MLH:setFilter("range", 1)

        assert.are.equal(3600, MLH:getRangeDuration())
    end)

    it("runs up to now for today, not to the end of the day", function()
        MLH:setFilter("range", 2)

        local sinceMidnight = now - time(LibStub("DateUtils-1.0"):getDate(0, true))

        assert.are.equal(sinceMidnight, MLH:getRangeDuration())
    end)

    it("is the whole day for yesterday, which is over", function()
        MLH:setFilter("range", 3)

        assert.are.equal(86400, MLH:getRangeDuration())
    end)

    it("reaches back to the oldest pickup for all the time", function()
        MLH:setFilter("range", 6)

        -- the oldest entry in the seed is the 90-minute-old valorstone pickup
        assert.are.equal(5400, MLH:getRangeDuration())
    end)

    -- a range that has only just begun would otherwise divide a rate by nothing
    it("is never zero", function()
        MLH:setFilter("range", 1)
        MLH.db.char.thisSessionStart = now

        assert.is_true(MLH:getRangeDuration() >= 1)
    end)
end)

describe("the currency report", function()
    local originalGetCurrencyInfo = nil

    before_each(function()
        seed()

        originalGetCurrencyInfo = C_CurrencyInfo.GetCurrencyInfo
        C_CurrencyInfo.GetCurrencyInfo = function(id) return currencyInfo[id] end
    end)

    after_each(function()
        C_CurrencyInfo.GetCurrencyInfo = originalGetCurrencyInfo
    end)

    it("counts what the filters select, not the balance", function()
        local report = MLH:buildCurrencyReport()

        assert.are.equal(420, rowFor(report, 3008).quantity)
        assert.are.equal(1338, report.totalEarned)
    end)

    it("turns the quantity into a rate over the range", function()
        local report = MLH:buildCurrencyReport()
        local row = rowFor(report, 3008)

        -- 420 valorstones over the 5400 seconds the history covers is 280 an hour
        assert.are.equal(280, math.floor(row.perHour + 0.5))
    end)

    it("reads the balance out of the client", function()
        local report = MLH:buildCurrencyReport()

        assert.are.equal(1240, rowFor(report, 3008).held)
    end)

    it("counts a season cap against everything ever earned", function()
        local cap = rowFor(MLH:buildCurrencyReport(), 3107).cap

        assert.are.equal("total", cap.kind)
        assert.are.equal(90, cap.current)
        assert.are.equal(90, cap.max)
    end)

    it("prefers the weekly allowance where a currency has both", function()
        currencyInfo[3008].canEarnPerWeek = true
        currencyInfo[3008].maxWeeklyQuantity = 1500
        currencyInfo[3008].quantityEarnedThisWeek = 600
        currencyInfo[3008].maxQuantity = 20000

        local cap = rowFor(MLH:buildCurrencyReport(), 3008).cap

        assert.are.equal("weekly", cap.kind)
        assert.are.equal(600, cap.current)
        assert.are.equal(1500, cap.max)

        currencyInfo[3008].canEarnPerWeek = false
        currencyInfo[3008].maxWeeklyQuantity = nil
        currencyInfo[3008].quantityEarnedThisWeek = nil
        currencyInfo[3008].maxQuantity = 0
    end)

    -- an uncapped currency has to read as "no cap" rather than as a bar at either end
    it("leaves an uncapped currency without one", function()
        assert.is_nil(rowFor(MLH:buildCurrencyReport(), 3009).cap)
    end)

    it("counts how many caps are reached, out of the ones there are", function()
        local report = MLH:buildCurrencyReport()

        assert.are.equal(1, report.cappedTotal)
        assert.are.equal(1, report.cappedCount)
    end)

    it("says the balance is one character's while the view is the account's", function()
        assert.is_true(MLH:buildCurrencyReport().heldIsCurrentCharacter)

        MLH:setFilter("scope", "account")

        assert.is_false(MLH:buildCurrencyReport().heldIsCurrentCharacter)
    end)

    it("sorts by the column asked for, both ways round", function()
        MLH:setFilter("currencySort", "earned")
        MLH:setFilter("currencySortDescending", true)

        assert.are.equal(3009, MLH:buildCurrencyReport().rows[1].currencyId)

        MLH:setFilter("currencySortDescending", false)

        assert.are.equal(3107, MLH:buildCurrencyReport().rows[1].currencyId)

        MLH:setFilter("currencySort", "held")
        MLH:setFilter("currencySortDescending", true)

        assert.are.equal(3009, MLH:buildCurrencyReport().rows[1].currencyId)
    end)

    it("follows the date range like every other view", function()
        MLH:setFilter("range", 1) --the live session, which started an hour ago

        local report = MLH:buildCurrencyReport()

        -- the 90-minute-old valorstone pickup is outside it, the 15-minute-old one is not
        assert.are.equal(120, rowFor(report, 3008).quantity)
    end)

    it("exports what it shows, with the cap and the rate", function()
        local csv, count = MLH:buildCurrencyCsv(MLH:buildCurrencyReport())

        assert.are.equal(3, count)
        assert.is_not_nil(csv:find("name,id,earned,perHour,held,capType", 1, true))
        assert.is_not_nil(csv:find("Runed Crest", 1, true))
        assert.is_not_nil(csv:find("total,90,90", 1, true))
    end)
end)
