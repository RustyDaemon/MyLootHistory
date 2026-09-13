local wow = require("tests.support.wow")
wow.load("utils/DateUtils.lua")
wow.load("MyLootHistory.lua")
wow.load("MyLootHistoryDB.lua")
wow.load("locales/enUS.lua")
local MLH = wow.addon

before_each(function()
    MLH:initDatabase()
    _G.GOLD_AMOUNT = "%d Gold"
    _G.SILVER_AMOUNT = "%d Silver"
    _G.COPPER_AMOUNT = "%d Copper"
    _G.GOLD_AMOUNT_TEXTURE = "%d|TGold:%d:%d:2:0|t"
    _G.SILVER_AMOUNT_TEXTURE = "%d|TSilver:%d:%d:2:0|t"
    _G.COPPER_AMOUNT_TEXTURE = "%d|TCopper:%d:%d:2:0|t"
end)

describe("money chat parsing", function()
    for _, case in ipairs({
        { "You loot 5 Gold.", 50000 },
        { "You loot 7 Silver.", 700 },
        { "You loot 9 Copper.", 9 },
        { "You loot 2 Gold, 3 Copper.", 20003 },
        { "You loot 2 Gold, 3 Silver.", 20300 },
        { "Your share is 2 Gold, 3 Silver, 4 Copper.", 20304 },
        { "You loot 1,234 Gold, 5 Copper.", 12340005 },
        { "You loot 2|TGold:12:12:2:0|t 3|TCopper:12:12:2:0|t", 20003 },
    }) do
        it(case[1], function()
            MLH:CHAT_MSG_MONEY(nil, case[1])
            assert.are.equal(case[2], MLH.db.char.foundGold[1].quantity)
        end)
    end

    it("uses localized formats, including positional arguments", function()
        _G.GOLD_AMOUNT = "%1$d or"
        _G.SILVER_AMOUNT = "%d argent"
        MLH:CHAT_MSG_MONEY(nil, "Vous recevez 5 or, 2 argent.")
        assert.are.equal(50200, MLH.db.char.foundGold[1].quantity)
    end)

    it("does not treat unrelated numbers as copper", function()
        MLH:CHAT_MSG_MONEY(nil, "There are 12 players nearby.")
        assert.are.equal(0, #MLH.db.char.foundGold)
    end)
end)
