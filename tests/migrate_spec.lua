--[[
The upgrade from the pre-lootData shape.

A record written by one of the first versions is one pickup, flat: a quantity, the zone table
the client handed back and the date as a string. Everything since reads `record.lootData`, so
one such record left in the saved variables took the whole report down - which is how it was
found: the account scope walked an alt who had not logged in for two years and errored on
`attempt to get length of field 'lootData' (a nil value)`.

What matters here is that nothing is lost in the process: the quantity, the date and the zone
all have to come out the other side, because this rewrites the player's history in place and
there is no second copy of it.
--]]

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

-- 28 Dec 2023, 13:05:44 local time - the stamp the string below has to parse back to
local LEGACY_TIME = os.time({ year = 2023, month = 12, day = 28, hour = 13, min = 5, sec = 44 })
local LEGACY_DATE = os.date("%a %b %d %H:%M:%S %Y", LEGACY_TIME)

local function legacyItem()
    return {
        itemId = 172013,
        itemLink = "[Festive Firework]",
        itemTexture = 134284,
        quantity = 3,
        zone = { mapID = 2023, name = "Ohn'ahran Plains" },
        foundOn = LEGACY_DATE,
    }
end

before_each(function() MLH:initDatabase() end)

describe("MLH:upgradeCharacterData", function()
    it("turns a flat record into one holding a single loot entry", function()
        local data = { foundItems = { legacyItem() } }

        assert.is_true(MLH:upgradeCharacterData(data))

        local record = data.foundItems[1]
        local entry = record.lootData[1]

        assert.are.equal(1, #record.lootData)
        assert.are.equal(3, entry.quantity)
        assert.are.equal(LEGACY_TIME, entry.foundOn)
        assert.are.equal(2023, entry.zoneID)

        -- and the record itself no longer claims to be a loot entry as well
        assert.is_nil(record.quantity)
        assert.is_nil(record.foundOn)
        assert.is_nil(record.zone)
        assert.are.equal(172013, record.itemId)
    end)

    it("keeps a record whose date cannot be read, without inventing one", function()
        local item = legacyItem()
        item.foundOn = "some time last winter"

        local data = { foundItems = { item } }
        MLH:upgradeCharacterData(data)

        assert.are.equal(1, #data.foundItems[1].lootData)
        assert.is_nil(data.foundItems[1].lootData[1].foundOn)
    end)

    it("upgrades gold and currency the same way", function()
        local data = {
            foundGold = { { quantity = 1200, zone = { mapID = 84 }, foundOn = LEGACY_DATE } },
            foundCurrency = {
                { currencyId = 3008, currencyName = "Valorstones", quantity = 40,
                  zone = { mapID = 84 }, foundOn = LEGACY_DATE },
            },
        }

        MLH:upgradeCharacterData(data)

        assert.are.equal(84, data.foundGold[1].zoneID)
        assert.are.equal(LEGACY_TIME, data.foundGold[1].foundOn)
        assert.is_nil(data.foundGold[1].zone)

        local entry = data.foundCurrency[1].lootData[1]
        assert.are.equal(40, entry.quantity)
        assert.are.equal(84, entry.zoneID)
    end)

    it("leaves a current record alone and does the work only once", function()
        local data = {
            foundItems = {
                { itemId = 100, lootData = { { quantity = 5, foundOn = LEGACY_TIME, zoneID = 1,
                                               sellPrice = 400 } } },
            },
        }

        assert.is_true(MLH:upgradeCharacterData(data))

        local entry = data.foundItems[1].lootData[1]
        assert.are.equal(5, entry.quantity)
        assert.are.equal(LEGACY_TIME, entry.foundOn)
        assert.are.equal(1, entry.zoneID)
        assert.are.equal(400, entry.sellPrice)

        -- stamped, so the next read is a comparison and not another walk
        assert.is_false(MLH:upgradeCharacterData(data))
    end)

    it("survives a character missing the lists entirely", function()
        local data = {}

        assert.is_true(MLH:upgradeCharacterData(data))
        assert.is_false(MLH:upgradeCharacterData(data))
    end)
end)

describe("reading a character stored by an old version", function()
    it("does not error when the account scope walks it", function()
        wow.addCharacter(MLH.db, "Alt - Testrealm", {
            foundItems = { legacyItem() },
            foundGold = { { quantity = 500, zone = { mapID = 84 }, foundOn = LEGACY_DATE } },
        })

        MLH:setFilter("scope", "account")

        local histories = MLH:getHistories()
        local alt = histories[2]

        assert.are.equal(2, #histories)
        assert.are.equal(3, alt.items[1].lootData[1].quantity)
        assert.are.equal(LEGACY_TIME, alt.gold[1].foundOn)
    end)
end)
