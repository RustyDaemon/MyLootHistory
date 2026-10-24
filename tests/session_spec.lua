local wow = require("tests.support.wow")

wow.loadThrough("data/Export.lua")

local MLH = wow.addon

local now = nil

local function seed()
    MLH:initDatabase()

    wow.freeze(os.time())

    now = wow.now()

    local char = MLH.db.char

    char.thisSessionStart = now - 3600

    char.foundItems = {
        {
            itemId = 100, itemName = "Copper Ore", itemTexture = 1, quality = 1,
            lootData = {
                { quantity = 4, foundOn = now - 7200, zoneID = 1, sellPrice = 100 },
                { quantity = 5, foundOn = now - 1800, zoneID = 1, sellPrice = 100 },
                { quantity = 3, foundOn = now - 600, zoneID = 1, sellPrice = 100 },
            },
        },
    }

    char.foundGold = { { quantity = 5000, foundOn = now - 1200, zoneID = 1 } }
    char.foundCurrency = {}

    MLH:setFilter("scope", "char")
    MLH:setFilter("session", 0)
    MLH:setFilter("range", 6)
    MLH:setFilter("quality", 0)
    MLH:setFilter("exactQuality", false)
    MLH:setFilter("zone", 0)
    MLH:setFilter("search", "")
end

after_each(function() wow.unfreeze() end)

describe("MLH:closeSession", function()
    before_each(seed)

    it("files the session, ending it at the last thing looted", function()
        local session = MLH:closeSession()

        assert.is_not_nil(session)
        assert.are.equal(now - 3600, session.startedOn)
        assert.are.equal(now - 600, session.endedOn)
        assert.are.equal(1, #MLH.db.char.sessions)
    end)

    it("files nothing for a session that recorded nothing", function()
        MLH.db.char.thisSessionStart = now - 60

        assert.is_nil(MLH:closeSession())
        assert.are.equal(0, #MLH.db.char.sessions)
    end)

    it("keeps the newest sessions and drops the oldest", function()
        for i = 1, 45 do
            MLH.db.char.sessions[i] = { startedOn = now - 100000 + i, endedOn = now - 99000 + i }
        end

        MLH:closeSession()

        assert.are.equal(40, #MLH.db.char.sessions)
        assert.are.equal(now - 3600, MLH.db.char.sessions[40].startedOn)
    end)
end)

describe("MLH:resetSession", function()
    before_each(seed)

    it("files the one that was running and starts a new one", function()
        MLH:resetSession()

        assert.are.equal(1, #MLH.db.char.sessions)
        assert.are.equal(wow.now(), MLH.db.char.thisSessionStart)
    end)

    it("puts the report back on the live session", function()
        MLH:setFilter("session", now - 3600)
        MLH:resetSession()

        assert.are.equal(0, MLH:getFilters().session)
    end)
end)

describe("MLH:getSessionStats", function()
    before_each(seed)

    it("covers the live session from its start until now", function()
        local stats = MLH:getSessionStats()

        assert.is_true(stats.isLive)
        assert.are.equal(8, stats.quantity)          -- 5 + 3, not the 4 from before it began
        assert.are.equal(5000, stats.rawGold)
        assert.are.equal(3600, stats.duration)
    end)

    it("stops a finished session at its end", function()
        local session = { startedOn = now - 7300, endedOn = now - 1000 }
        local stats = MLH:getSessionStats(session)

        assert.is_false(stats.isLive)
        assert.are.equal(9, stats.quantity)          -- the 4 and the 5, but not the 3 after it ended
        assert.are.equal(6300, stats.duration)
    end)
end)

describe("the session totals", function()
    local priced = 0
    local original = nil

    before_each(function()
        seed()

        priced = 0
        original = MLH.getItemPrice

        MLH.getItemPrice = function(self, ...)
            priced = priced + 1
            return original(self, ...)
        end
    end)

    after_each(function() MLH.getItemPrice = original end)

    it("are worked out once while only the clock moves", function()
        local first = MLH:getSessionStats()
        local scans = priced

        wow.freeze(now + 60)

        local second = MLH:getSessionStats()

        assert.are.equal(scans, priced)
        assert.are.equal(first.quantity, second.quantity)
        assert.are.equal(3660, second.duration)
        assert.is_true(second.goldPerHour < first.goldPerHour)
    end)

    it("are worked out again once something is looted", function()
        MLH:getSessionStats()
        MLH:addItem(100, 2, nil, 1, 1, "Copper Ore", 1, 100)

        assert.are.equal(10, MLH:getSessionStats().quantity)
    end)

    it("are worked out again once the prices are cleared", function()
        MLH:getSessionStats()

        local scans = priced

        MLH:clearPriceCache()
        MLH:getSessionStats()

        assert.is_true(priced > scans)
    end)

    it("are kept apart for each session", function()
        local session = { startedOn = now - 7300, endedOn = now - 1000 }

        assert.are.equal(8, MLH:getSessionStats().quantity)
        assert.are.equal(9, MLH:getSessionStats(session).quantity)
        assert.are.equal(8, MLH:getSessionStats().quantity)
    end)
end)

describe("the session date range", function()
    it("looks the picked session up once per pass, not once per entry", function()
        seed()

        local lootData = MLH.db.char.foundItems[1].lootData

        for i = 1, 20 do
            lootData[#lootData+1] = { quantity = 1, foundOn = now - 500 + i, zoneID = 1, sellPrice = 100 }
        end

        MLH:setFilter("range", 1)

        local lookups = 0
        local original = MLH.getSelectedSession

        MLH.getSelectedSession = function(self)
            lookups = lookups + 1
            return original(self)
        end

        local report = MLH:buildReport()

        MLH.getSelectedSession = original

        assert.are.equal(28, report.totalQuantity)
        assert.is_true(lookups <= 2, "looked the session up "..lookups.." times")
    end)
end)

describe("the session date range", function()
    before_each(seed)

    it("selects the live session by default", function()
        MLH:setFilter("range", 1)

        local report = MLH:buildReport()

        assert.are.equal(8, report.totalQuantity)
    end)

    it("selects a finished session once one is picked", function()
        MLH:closeSession()

        MLH.db.char.thisSessionStart = wow.now()
        MLH:setFilter("range", 1)
        MLH:setFilter("session", now - 3600)

        assert.are.equal(8, MLH:buildReport().totalQuantity)
    end)

    it("falls back to the live session when the pick no longer exists", function()
        MLH:setFilter("range", 1)
        MLH:setFilter("session", now - 99999)

        assert.are.equal(8, MLH:buildReport().totalQuantity)
    end)

    it("lists the live session first and the finished ones after it", function()
        MLH:closeSession()

        local list = MLH:getSessionList()

        assert.are.equal(2, #list)
        assert.are.equal(0, list[1].value)
        assert.are.equal(now - 3600, list[2].value)
    end)
end)

describe("retention", function()
    before_each(seed)

    it("drops sessions whose loot has been pruned away", function()
        local day = 24 * 60 * 60

        MLH.db.char.sessions = {
            { startedOn = now - 40 * day, endedOn = now - 40 * day + 3600 },
            { startedOn = now - day, endedOn = now - day + 3600 },
        }

        MLH:pruneHistory(30)

        assert.are.equal(1, #MLH.db.char.sessions)
        assert.are.equal(now - day, MLH.db.char.sessions[1].startedOn)
    end)
end)

describe("pickups at a session boundary", function()
    before_each(seed)

    it("keeps all three loot types in exactly one session during same-second resets", function()
        MLH:resetData()
        MLH:beginSession()
        MLH:addGold(10000, 1)
        MLH:addItem(42, 2, nil, 1, 1, "Ore", 1, 100)
        MLH:addCurrency(50, 3, "Currency", 1, 1, 1)
        MLH:resetSession()
        local first = MLH:getSessions()[1]
        assert.are.equal(0, MLH:getSessionStats().rawGold)
        assert.are.equal(0, MLH:getSessionStats().quantity)
        assert.are.equal(0, MLH:getSessionStats().currencyQuantity)
        MLH:addGold(20000, 1)
        MLH:addItem(42, 4, nil, 1, 1, "Ore", 1, 100)
        MLH:addCurrency(50, 6, "Currency", 1, 1, 1)
        MLH:resetSession()
        local second = MLH:getSessions()[1]
        assert.are_not.equal(first.id, second.id)
        assert.are.equal(10000, MLH:getSessionStats(first).rawGold)
        assert.are.equal(2, MLH:getSessionStats(first).quantity)
        assert.are.equal(3, MLH:getSessionStats(first).currencyQuantity)
        assert.are.equal(20000, MLH:getSessionStats(second).rawGold)
        MLH:setFilter("range", 1)
        MLH:setFilter("session", first.id)
        assert.are.equal(first, MLH:getSelectedSession())
        assert.are.equal(10000, MLH:calculateGoldFound())
        MLH:setFilter("session", second.id)
        assert.are.equal(20000, MLH:calculateGoldFound())
    end)

    it("separates a legacy session from new pickups at the same timestamp", function()
        MLH:addGold(10000, 1)
        MLH:resetSession()
        local previous = MLH:getSessions()[1]
        MLH:addGold(20000, 1)
        assert.are.equal(15000, MLH:getSessionStats(previous).rawGold)
        assert.are.equal(20000, MLH:getSessionStats().rawGold)
    end)
end)
