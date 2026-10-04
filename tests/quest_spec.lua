local wow = require("tests.support.wow")

wow.loadThrough("MyLootHistoryData.lua")
wow.load("locales/enUS.lua")

local MLH = wow.addon

local clock = 1000

_G.GetTime = function() return clock end

_G.C_QuestLog = {
    GetTitleForQuestID = function(questID)
        return questID == 81000 and "Supplies for the Front" or nil
    end,
}

_G.GOLD_AMOUNT = "%d Gold"
_G.SILVER_AMOUNT = "%d Silver"
_G.COPPER_AMOUNT = "%d Copper"

local QUEST = 81000

local function seed()
    MLH:initDatabase()
    MLH:resetQuestTracking()

    wow.freeze(os.time())

    clock = 1000

    MLH.db.char.thisSessionStart = wow.now() - 3600
    MLH.db.char.currentSessionID = nil
end

after_each(function() wow.unfreeze() end)

local function pushedItem(quantity, sellPrice)
    local _, entry = MLH:addItem(100, quantity, nil, 1, 1, "Supply Crate", 1, sellPrice or 0,
        MLH:getQuestSource() or { kind = "pushed" })

    MLH:noteQuestCandidate(entry)

    return entry
end

describe("quest gold", function()
    before_each(seed)

    it("is recorded from the turn-in, as the quest's", function()
        MLH:QUEST_TURNED_IN(QUEST, 0, 120000)

        local gold = MLH.db.char.foundGold

        assert.are.equal(1, #gold)
        assert.are.equal(120000, gold[1].quantity)
        assert.are.equal("quest", gold[1].source.kind)
        assert.are.equal(QUEST, gold[1].source.id)
    end)

    it("is not counted twice when a money line for the same coins follows", function()
        MLH:QUEST_TURNED_IN(QUEST, 0, 120000)
        clock = clock + 0.5
        MLH:CHAT_MSG_MONEY(nil, "You receive 12 Gold.")

        assert.are.equal(1, #MLH.db.char.foundGold)
    end)

    it("is not counted twice when the money line came first", function()
        MLH:CHAT_MSG_MONEY(nil, "You receive 12 Gold.")
        clock = clock + 0.5
        MLH:QUEST_TURNED_IN(QUEST, 0, 120000)

        local gold = MLH.db.char.foundGold

        assert.are.equal(1, #gold)
        assert.are.equal("quest", gold[1].source.kind)
    end)

    it("leaves coins looted just before alone when the amount differs", function()
        MLH:CHAT_MSG_MONEY(nil, "You loot 3 Gold.")
        clock = clock + 0.5
        MLH:QUEST_TURNED_IN(QUEST, 0, 120000)

        local gold = MLH.db.char.foundGold

        assert.are.equal(2, #gold)
        assert.is_nil(gold[1].source)
    end)

    it("still counts coins looted after the window has closed", function()
        MLH:QUEST_TURNED_IN(QUEST, 0, 120000)
        clock = clock + 5
        MLH:CHAT_MSG_MONEY(nil, "You loot 12 Gold.")

        local gold = MLH.db.char.foundGold

        assert.are.equal(2, #gold)
        assert.is_nil(gold[2].source)
    end)
end)

describe("quest items and currencies", function()
    before_each(seed)

    it("claims an item pushed just before the turn-in", function()
        local entry = pushedItem(1)

        clock = clock + 0.5
        MLH:QUEST_TURNED_IN(QUEST, 0, 0)

        assert.are.equal("quest", entry.source.kind)
        assert.are.equal(QUEST, entry.source.id)
    end)

    it("claims an item arriving just after the turn-in", function()
        MLH:QUEST_TURNED_IN(QUEST, 0, 0)
        clock = clock + 1

        assert.are.equal("quest", pushedItem(1).source.kind)
    end)

    it("claims an item still loading when the turn-in happened", function()
        local _, entry = MLH:addItem(100, 1, nil, 1, 1, "Supply Crate", 1, 0, { kind = "pushed" })

        MLH:QUEST_TURNED_IN(QUEST, 0, 0)
        MLH:noteQuestCandidate(entry)

        assert.are.equal("quest", entry.source.kind)
    end)

    it("leaves an item pushed well before the turn-in alone", function()
        local entry = pushedItem(1)

        clock = clock + 3
        MLH:QUEST_TURNED_IN(QUEST, 0, 0)

        assert.are.equal("pushed", entry.source.kind)
    end)

    it("leaves loot traced to a creature alone", function()
        local _, entry = MLH:addItem(100, 1, nil, 1, 1, "Supply Crate", 1, 0, { kind = "creature", id = 5 })

        MLH:noteQuestCandidate(entry)
        MLH:QUEST_TURNED_IN(QUEST, 0, 0)

        assert.are.equal("creature", entry.source.kind)
    end)

    it("claims currency arriving with the reward", function()
        MLH:QUEST_TURNED_IN(QUEST, 0, 0)

        local _, entry = MLH:addCurrency(3008, 10, "Valorstones", 1, 1, 1, MLH:getQuestSource())

        assert.are.equal("quest", entry.source.kind)
    end)

    it("works for a world quest that only announces its loot", function()
        local entry = pushedItem(1)

        MLH:QUEST_LOOT_RECEIVED(QUEST)

        assert.are.equal("quest", entry.source.kind)
    end)
end)

describe("quest names", function()
    before_each(seed)

    it("are learned at turn-in and shown as the source", function()
        MLH:QUEST_TURNED_IN(QUEST, 0, 120000)

        assert.are.equal("Supplies for the Front", MLH:getSourceName(MLH.db.char.foundGold[1].source))
    end)

    it("do not collide with a creature of the same id", function()
        MLH:rememberSourceName(QUEST, "Some Creature")
        MLH:QUEST_TURNED_IN(QUEST, 0, 120000)

        assert.are.equal("Some Creature", MLH:getSourceName({ kind = "creature", id = QUEST }))
        assert.are.equal("Supplies for the Front", MLH:getSourceName({ kind = "quest", id = QUEST }))
    end)

    it("fall back to a generic name when the quest cannot be named", function()
        assert.are.equal("A quest", MLH:getSourceName({ kind = "quest", id = 99 }))
    end)
end)

describe("gold per hour", function()
    before_each(function()
        seed()

        pushedItem(2, 500)
        MLH:CHAT_MSG_MONEY(nil, "You loot 1 Gold.")

        clock = clock + 10
        MLH:QUEST_TURNED_IN(QUEST, 0, 120000)
        pushedItem(1, 7000)
    end)

    it("leaves quest rewards out by default", function()
        local stats = MLH:getSessionStats()

        assert.are.equal(2, stats.quantity)
        assert.are.equal(2 * 500, stats.itemValue)
        assert.are.equal(10000, stats.rawGold)
    end)

    it("counts them when asked to", function()
        MLH.db.char.config.questRewardsInRates = true

        local stats = MLH:getSessionStats()

        assert.are.equal(3, stats.quantity)
        assert.are.equal(2 * 500 + 7000, stats.itemValue)
        assert.are.equal(130000, stats.rawGold)
    end)

    it("still shows them in the report", function()
        MLH:setFilter("scope", "char")
        MLH:setFilter("range", MLH.RANGE_ALL)
        MLH:setFilter("zone", 0)
        MLH:setFilter("search", "")

        assert.are.equal(130000, MLH:calculateGoldFound())
    end)
end)
