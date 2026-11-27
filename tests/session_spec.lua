local wow = require("tests.support.wow")

wow.loadThrough("data/Currency.lua")

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

describe("pausing the session clock", function()
    before_each(function()
        seed()

        wow.player.afk, wow.player.resting = false, false
        MLH.db.char.sessionPauses = {}
        MLH.db.char.config.pauseWhenAway = true
    end)

    after_each(function()
        wow.player.afk, wow.player.resting = false, false
    end)

    -- Moves the clock on by seconds, then lets the addon hear the flag change.
    local function after(seconds)
        wow.freeze(wow.now() + seconds)
        MLH:onSessionPauseEvent()
    end

    it("is on unless turned off", function()
        MLH:initDatabase()

        assert.is_true(MLH.db.char.config.pauseWhenAway)
    end)

    it("stops while the player is away and goes on once they are back", function()
        wow.player.afk = true
        after(0)

        assert.is_true(MLH:isSessionPaused())

        wow.player.afk = false
        after(600)

        assert.is_false(MLH:isSessionPaused())
        assert.are.equal(3600, MLH:getSessionStats().duration)   -- 4200 on the wall clock, 600 of them away
    end)

    it("stops while the player is resting", function()
        wow.player.resting = true
        after(0)
        after(900)

        local stats = MLH:getSessionStats()

        assert.is_true(stats.isPaused)
        assert.are.equal(3600, stats.duration)
        assert.are.equal(900, stats.pausedSeconds)
    end)

    it("stays paused until neither holds", function()
        wow.player.resting = true
        after(0)
        wow.player.afk = true
        after(300)
        wow.player.resting = false
        after(300)

        assert.is_true(MLH:isSessionPaused())

        wow.player.afk = false
        after(300)

        assert.is_false(MLH:isSessionPaused())
        assert.are.equal(3600, MLH:getSessionStats().duration)
    end)

    it("leaves the paused time out of gold and items per hour", function()
        local before = MLH:getSessionStats()

        wow.player.afk = true
        after(0)
        after(3600)

        local stats = MLH:getSessionStats()

        assert.are.equal(before.goldPerHour, stats.goldPerHour)
        assert.are.equal(before.itemsPerHour, stats.itemsPerHour)
    end)

    it("leaves it out of the session range's rates too", function()
        wow.player.afk = true
        after(0)
        after(1800)

        MLH:setFilter("range", 1)

        assert.are.equal(3600, MLH:getRangeDuration())
    end)

    it("keeps recording what is looted while paused", function()
        wow.player.resting = true
        after(0)

        MLH:addItem(100, 2, nil, 1, 1, "Copper Ore", 1, 100)

        assert.are.equal(10, MLH:getSessionStats().quantity)
    end)

    it("does not pause, and lets an open pause go, once turned off", function()
        wow.player.afk = true
        after(0)
        after(600)

        MLH.db.char.config.pauseWhenAway = false
        after(0)
        after(600)

        assert.is_false(MLH:isSessionPaused())
        assert.are.equal(4800, MLH:getSessionStats().duration)   -- with it off, every minute counts
    end)

    it("starts a new session paused in a resting area, with none of the old pauses", function()
        wow.player.afk = true
        after(0)
        after(600)
        wow.player.afk = false
        wow.player.resting = true

        MLH:beginSession()

        assert.is_true(MLH:isSessionPaused())
        assert.are.equal(1, #MLH.db.char.sessionPauses)
    end)

    it("reads a secret AFK flag as not away", function()
        local original = _G.UnitIsAFK
        local secret = {}

        _G.UnitIsAFK = function() return secret end
        _G.issecretvalue = function(value) return value == secret end

        after(0)

        _G.UnitIsAFK, _G.issecretvalue = original, nil

        assert.is_false(MLH:isSessionPaused())
    end)

    it("files a session with the pauses before its last pickup only", function()
        -- Away for ten minutes in the middle, then resting from the last pickup on until logout.
        MLH.db.char.sessionPauses = {
            { from = now - 2400, to = now - 1800 },
            { from = now - 900 },
        }

        local session = MLH:closeSession()

        -- The last pickup was at now - 600: 600 from the first pause and 300 from the open one.
        assert.are.equal(900, session.pausedSeconds)
        assert.are.equal(3000 - 900, MLH:getSessionStats(session).duration)
    end)

    it("files a session that never paused with none", function()
        assert.are.equal(0, MLH:closeSession().pausedSeconds)
    end)

    it("keeps loot from a pause in the totals but out of the rates", function()
        local before = MLH:getSessionStats()

        wow.player.resting = true
        after(0)

        -- A stack crafted in town: a hundred bars at a gold each, with the clock stopped.
        MLH:addItem(200, 100, nil, 1, 1, "Bar", 1, 10000)
        MLH:addGold(50000, 1)

        local stats = MLH:getSessionStats()

        assert.are.equal(108, stats.quantity)
        assert.are.equal(55000, stats.rawGold)
        assert.are.equal(before.goldPerHour, stats.goldPerHour)
        assert.are.equal(before.itemsPerHour, stats.itemsPerHour)
    end)

    it("counts that loot in the rates again once the option is off", function()
        wow.player.resting = true
        after(0)

        MLH:addItem(200, 100, nil, 1, 1, "Bar", 1, 10000)

        MLH.db.char.config.pauseWhenAway = false
        after(0)

        assert.are.equal(108, MLH:getSessionStats().itemsPerHour)
    end)

    it("files a session's pauses so its loot from them stays out of its rates", function()
        wow.player.resting = true
        after(0)
        MLH:addItem(200, 100, nil, 1, 1, "Bar", 1, 10000)

        local session = MLH:closeSession()
        local stats = MLH:getSessionStats(session)

        assert.are.equal(108, stats.quantity)
        assert.are.equal(8, stats.itemsPerHour)   -- the 8 farmed over the hour the clock ran
    end)

    it("leaves currency from a pause out of the session range's per-hour rate", function()
        MLH.db.char.foundCurrency = {
            { currencyId = 3008, currencyName = "Valorstones", currencyIcon = 1, quality = 1,
              lootData = { { quantity = 60, foundOn = now - 900, zoneID = 1 } } },
        }

        wow.player.resting = true
        after(0)
        MLH:addCurrency(3008, 500, "Valorstones", 1, 1, 1)

        MLH:setFilter("range", 1)
        MLH:setFilter("view", "currency")

        local row = MLH:buildCurrencyReport().rows[1]

        assert.are.equal(560, row.quantity)
        assert.are.equal(60, math.floor(row.perHour + 0.5))
    end)

    it("measures a rate over a minute at the least", function()
        MLH.db.char.thisSessionStart = now - 5
        MLH.db.char.foundItems = {
            { itemId = 100, itemName = "Copper Ore", itemTexture = 1, quality = 1,
              lootData = { { quantity = 1, foundOn = now, zoneID = 1, sellPrice = 100 } } },
        }
        MLH.db.char.foundGold = {}
        MLH:bumpRevision()

        local stats = MLH:getSessionStats()

        assert.are.equal(5, stats.duration)
        assert.are.equal(60, stats.itemsPerHour)
    end)

    it("counts every minute while the option is off, pauses taken before included", function()
        wow.player.afk = true
        after(0)
        wow.player.afk = false
        after(600)

        MLH.db.char.config.pauseWhenAway = false

        assert.are.equal(4200, MLH:getSessionStats().duration)
        assert.are.equal(0, MLH:closeSession().pausedSeconds)
    end)

    it("pays no heed to another group member going away", function()
        wow.player.afk = true
        MLH:onSessionPauseEvent("PLAYER_FLAGS_CHANGED", "party1")

        assert.is_false(MLH:isSessionPaused())

        MLH:onSessionPauseEvent("PLAYER_FLAGS_CHANGED", "player")

        assert.is_true(MLH:isSessionPaused())
    end)

    it("files an older start with none of the running session's pauses", function()
        MLH.db.char.sessionPauses = { { from = now - 2400, to = now - 1800 } }

        local session = MLH:closeSession(now - 7300)

        assert.are.equal(0, session.pausedSeconds)
        assert.is_nil(session.pauses)
    end)

    it("says under the time card that the clock is paused, or how much it left out", function()
        assert.is_nil(MLH:getPausedCaption(MLH:getSessionStats()))

        wow.player.afk = true
        after(0)

        assert.are.equal("G_PausedNow", tostring(MLH:getPausedCaption(MLH:getSessionStats())))

        wow.player.afk = false
        after(600)

        assert.are.equal("G_PausedFor", tostring(MLH:getPausedCaption(MLH:getSessionStats())))
    end)
end)

describe("a reload or a relog", function()
    local id = nil

    before_each(function()
        seed()

        wow.player.afk, wow.player.resting = false, false

        local char = MLH.db.char

        char.config.pauseWhenAway = true
        char.sessionPauses = {}
        char.sessionSerial = 6
        char.currentSessionID = wow.charKey..":6"
        id = char.currentSessionID

        -- Something looted in the running session, so a session filed after it is not empty.
        MLH:addItem(100, 2, nil, 1, 1, "Copper Ore", 1, 100)
    end)

    after_each(function()
        wow.player.afk, wow.player.resting = false, false
    end)

    -- As the client goes: the logout, the addon loading again seconds later, then entering the world.
    local function relog(seconds)
        MLH:noteLogout()
        wow.freeze(wow.now() + seconds)
        MLH:continueOrBeginSession()
        MLH:onSessionPauseEvent("PLAYER_ENTERING_WORLD")
    end

    local function assertNewSession()
        local char = MLH.db.char

        assert.are_not.equal(id, char.currentSessionID)
        assert.are.equal(wow.now(), char.thisSessionStart)
        assert.are.equal(1, #char.sessions)
        assert.are.equal(id, char.sessions[1].id)
    end

    it("is on unless turned off", function()
        MLH:initDatabase()

        assert.is_true(MLH.db.char.config.continueSession)
    end)

    it("carries on with the session after a reload, the time away counted as a pause", function()
        relog(30)

        local char = MLH.db.char
        local stats = MLH:getSessionStats()

        assert.are.equal(id, char.currentSessionID)
        assert.are.equal(now - 3600, char.thisSessionStart)
        assert.are.equal(0, #char.sessions)
        assert.is_false(MLH:isSessionPaused())
        assert.are.equal(30, stats.pausedSeconds)
        assert.are.equal(3600, stats.duration)        -- 3630 on the wall clock, 30 of them logged out
        assert.are.equal(2, stats.quantity)
    end)

    it("carries on after a relog of up to 15 minutes", function()
        relog(15 * 60)

        assert.are.equal(id, MLH.db.char.currentSessionID)
        assert.are.equal(3600, MLH:getSessionStats().duration)
    end)

    it("keeps the clock stopped until the world is entered", function()
        MLH:noteLogout()
        wow.freeze(wow.now() + 30)
        MLH:continueOrBeginSession()

        assert.is_true(MLH:isSessionPaused())

        wow.freeze(wow.now() + 10)
        MLH:onSessionPauseEvent("PLAYER_ENTERING_WORLD")

        assert.is_false(MLH:isSessionPaused())
        assert.are.equal(40, MLH:getSessionStats().pausedSeconds)
    end)

    it("joins the time away to a pause still open at logout, with no second lost or counted twice", function()
        -- Resting in an inn for five minutes, logging out there, and back a minute later, still in it.
        wow.player.resting = true
        MLH:onSessionPauseEvent()
        wow.freeze(wow.now() + 300)

        relog(60)

        local pauses = MLH.db.char.sessionPauses

        assert.is_true(MLH:isSessionPaused())
        assert.are.equal(now + 300, pauses[1].to)
        assert.is_true(pauses[2].offline)

        wow.player.resting = false
        wow.freeze(wow.now() + 40)
        MLH:onSessionPauseEvent()

        assert.are.equal(400, MLH:getSessionStats().pausedSeconds)
    end)

    it("leaves the time logged out out of the clock and the rates with pausing off, live and filed", function()
        MLH.db.char.config.pauseWhenAway = false
        wow.freeze(wow.now() + 60)

        local before = MLH:getSessionStats()

        relog(600)

        local after = MLH:getSessionStats()

        assert.are.equal(3660, after.duration)          -- 4260 on the wall clock, 600 of them logged out
        assert.are.equal(before.duration, after.duration)
        assert.are.equal(before.itemsPerHour, after.itemsPerHour)
        assert.are.equal(before.goldPerHour, after.goldPerHour)

        -- Two more ores a minute after coming back, so the filed session reaches past the time logged out.
        wow.freeze(wow.now() + 60)
        MLH:addItem(100, 2, nil, 1, 1, "Copper Ore", 1, 100)

        local live = MLH:getSessionStats()
        local filed = MLH:getSessionStats(MLH:closeSession())

        assert.are.equal(3720, live.duration)
        assert.are.equal(600, filed.pausedSeconds)
        assert.are.equal(live.duration, filed.duration)
        assert.are.equal(live.itemsPerHour, filed.itemsPerHour)
        assert.are.equal(live.goldPerHour, filed.goldPerHour)
    end)

    it("still counts a pause away with pausing off, but not the time logged out", function()
        -- Five minutes away, back, then the option turned off and a ten-minute relog.
        wow.player.afk = true
        MLH:onSessionPauseEvent()
        wow.player.afk = false
        wow.freeze(wow.now() + 300)
        MLH:onSessionPauseEvent()

        MLH.db.char.config.pauseWhenAway = false
        relog(600)
        MLH:addItem(100, 2, nil, 1, 1, "Copper Ore", 1, 100)

        assert.are.equal(3900, MLH:getSessionStats().duration)   -- 4500 on the wall clock, less the 600

        local filed = MLH:getSessionStats(MLH:closeSession())

        assert.are.equal(600, filed.pausedSeconds)
        assert.are.equal(3900, filed.duration)
    end)

    it("files the session and starts a new one after a longer break", function()
        relog(15 * 60 + 1)

        assertNewSession()
        assert.are.equal(0, MLH:getSessionStats().pausedSeconds)
    end)

    it("files the session and starts a new one when no logout time was saved", function()
        MLH.db.char.lastSeenAt = nil
        wow.freeze(wow.now() + 30)
        MLH:continueOrBeginSession()

        assertNewSession()
    end)

    it("keeps the session's start and its loot through the game saving and loading them", function()
        -- A login session begun in the second the addon loaded, as one usually is.
        wow.load("data/Database.lua")
        MLH:initDatabase()
        MLH:beginSession()

        local started = MLH.db.char.currentSessionID

        wow.freeze(now + 600)
        MLH:addItem(100, 2, nil, 1, 1, "Copper Ore", 1, 100)

        -- The reload: the logout noted, the saved data written, then every file run again.
        MLH:noteLogout()
        wow.logout(MLH.db)
        wow.freeze(now + 630)
        wow.load("data/Database.lua")
        MLH:initDatabase()
        MLH:continueOrBeginSession()
        MLH:onSessionPauseEvent("PLAYER_ENTERING_WORLD")

        local stats = MLH:getSessionStats()

        assert.are.equal(started, MLH.db.char.currentSessionID)
        assert.are.equal(now, MLH.db.char.thisSessionStart)
        assert.are.equal(2, stats.quantity)
        assert.are.equal(30, stats.pausedSeconds)
        assert.are.equal(600, stats.duration)
    end)

    it("files the session and starts a new one when no session start was saved", function()
        MLH.db.char.thisSessionStart = nil

        relog(30)

        assert.are_not.equal(id, MLH.db.char.currentSessionID)
        assert.are.equal(wow.now(), MLH.db.char.thisSessionStart)
    end)

    it("starts a new session every time with the option off", function()
        MLH.db.char.config.continueSession = false

        relog(30)

        assertNewSession()
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

    -- Clear data says so in chat; the specs here look only at what it erases.
    local print = _G.print

    before_each(function() _G.print = function() end end)
    after_each(function() _G.print = print end)


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
