local wow = require("tests.support.wow")

wow.loadThrough("data/Export.lua")

local MLH = wow.addon

-- Drop alerts are tested on their own and need frames; recording only asks whether to raise one.
MLH.getDropAlert = MLH.getDropAlert or function() return nil end

-- item:id:enchant:gem1:gem2:gem3:gem4:suffix:unique:level:spec:modifiers:context:bonusCount:bonuses...
local function link(bonus, level, spec)
    return "|cffa335ee|Hitem:212000::::::::"..(level or 80)..":"..(spec or 250)
        .."::1:1:"..bonus.."|h[Void Blade]|h|r"
end

local BASE = link(10390)
local UPGRADED = link(10391)

local getItemInfo = _G.C_Item.GetItemInfo

local function seed()
    MLH:initDatabase()

    wow.freeze(os.time())

    MLH.db.char.thisSessionStart = wow.now() - 3600
    MLH.db.char.currentSessionID = nil

    MLH:setFilter("scope", "char")
    MLH:setFilter("session", 0)
    MLH:setFilter("range", MLH.RANGE_ALL)
    MLH:setFilter("quality", 0)
    MLH:setFilter("exactQuality", false)
    MLH:setFilter("zone", 0)
    MLH:setFilter("search", "")
end

after_each(function()
    _G.C_Item.GetItemInfo = getItemInfo
    _G.C_Item.GetDetailedItemLevelInfo = nil
    wow.unfreeze()
end)

describe("MLH:itemVariantKey", function()
    it("is the same for one drop seen at another level or spec", function()
        assert.are.equal(MLH:itemVariantKey(link(10390, 80, 250)), MLH:itemVariantKey(link(10390, 78, 105)))
    end)

    it("tells an upgraded drop apart from the base one", function()
        assert.are_not.equal(MLH:itemVariantKey(BASE), MLH:itemVariantKey(UPGRADED))
    end)

    it("has nothing to say about a missing link", function()
        assert.is_nil(MLH:itemVariantKey(nil))
        assert.is_nil(MLH:itemVariantKey("not a link"))
    end)
end)

describe("storing a drop's own link", function()
    before_each(seed)

    it("keeps the first link on the record and leaves a matching drop without one", function()
        MLH:addItem(212000, 1, BASE, 1, 3, "Void Blade", 1, 1000)
        MLH:addItem(212000, 1, link(10390, 79, 105), 1, 3, "Void Blade", 1, 1000)

        local record = MLH.db.char.foundItems[1]

        assert.are.equal(BASE, record.itemLink)
        assert.is_nil(record.lootData[2].itemLink)
    end)

    it("stamps an upgraded drop with its link and quality", function()
        MLH:addItem(212000, 1, BASE, 1, 3, "Void Blade", 1, 1000)

        local _, entry = MLH:addItem(212000, 1, UPGRADED, 1, 4, "Void Blade", 1, 2500)

        assert.are.equal(UPGRADED, entry.itemLink)
        assert.are.equal(4, entry.quality)
        assert.are.equal(2500, entry.sellPrice)
    end)

    it("gives an old record without a link the first link it sees", function()
        MLH.db.char.foundItems = {
            { itemId = 212000, itemName = "Void Blade", quality = 3, lootData = { { quantity = 1 } } },
        }

        MLH:addItem(212000, 1, UPGRADED, 1, 4, "Void Blade", 1, 2500)

        local record = MLH.db.char.foundItems[1]

        assert.are.equal(UPGRADED, record.itemLink)
        assert.is_nil(record.lootData[2].itemLink)
    end)
end)

describe("recording a drop", function()
    before_each(seed)

    it("reads quality and price from the link, not the base item", function()
        _G.C_Item.GetItemInfo = function(item)
            if (item == UPGRADED) then
                return "Void Blade", UPGRADED, 4, nil, nil, nil, nil, nil, nil, 1, 2500, 2, 7
            end

            return "Void Blade", BASE, 3, nil, nil, nil, nil, nil, nil, 1, 1000, 2, 7
        end

        MLH:recordLoot(212000, UPGRADED, 1, 1, nil)

        local record = MLH.db.char.foundItems[1]

        assert.are.equal(4, record.quality)
        assert.are.equal(2500, record.lootData[1].sellPrice)
    end)

    it("falls back to the item id when the link is not cached yet", function()
        _G.C_Item.GetItemInfo = function(item)
            if (item == 212000) then
                return "Void Blade", BASE, 3, nil, nil, nil, nil, nil, nil, 1, 1000, 2, 7
            end

            return nil
        end

        MLH:recordLoot(212000, UPGRADED, 1, 1, nil)

        assert.are.equal(1000, MLH.db.char.foundItems[1].lootData[1].sellPrice)
    end)
end)

describe("the report", function()
    before_each(function()
        seed()

        local now = wow.now()

        MLH.db.char.foundItems = {
            {
                itemId = 212000, itemLink = BASE, itemName = "Void Blade", itemTexture = 1, quality = 3,
                lootData = {
                    { quantity = 2, foundOn = now - 600, zoneID = 1, sellPrice = 1000 },
                    { quantity = 1, foundOn = now - 300, zoneID = 1, sellPrice = 2500,
                      itemLink = UPGRADED, quality = 4 },
                },
            },
        }
    end)

    it("prices each drop by the link it dropped as", function()
        local item = MLH:collectItems()[1]

        assert.are.equal(2 * 1000 + 2500, item.totalValue)
        assert.are.equal(2 * 1000 + 2500, item.vendorValue)
        assert.are.equal(3, item.totalQuantity)
    end)

    it("shows the row as its best drop", function()
        local item = MLH:collectItems()[1]

        assert.are.equal(4, item.quality)
        assert.are.equal(UPGRADED, item.itemLink)
    end)

    it("lets the quality filter find an item by its best drop", function()
        MLH:setFilter("quality", 4)

        assert.are.equal(1, #MLH:collectItems())
    end)

    it("does not let the base item in the cache overwrite a drop's link or quality", function()
        _G.C_Item.GetItemInfo = function(item)
            if (item == 212000) then
                return "Void Blade", "|cff0070dd|Hitem:212000|h[Void Blade]|h|r", 3,
                    nil, nil, nil, nil, nil, nil, 1, 900
            end

            return nil
        end

        local item = MLH:collectItems()[1]

        assert.are.equal(UPGRADED, item.itemLink)
        assert.are.equal(4, item.quality)
        assert.are.equal(2 * 1000 + 2500, item.vendorValue)
    end)

    it("breaks the quantity down by item level", function()
        _G.C_Item.GetDetailedItemLevelInfo = function(itemLink)
            return itemLink == UPGRADED and 323 or 302
        end

        local levels = MLH:getItemLevelBreakdown(MLH:collectItems()[1])

        assert.are.same({ { level = 302, quantity = 2 }, { level = 323, quantity = 1 } }, levels)
    end)

    it("counts each drop at its own value in the session", function()
        local stats = MLH:getSessionStats()

        assert.are.equal(2 * 1000 + 2500, stats.itemValue)
        assert.are.equal(3, stats.quantity)
    end)
end)

describe("auction prices", function()
    before_each(function()
        seed()

        _G.Auctionator = { API = { v1 = {
            GetAuctionPriceByItemID = function() return 5 end,
            GetAuctionPriceByItemLink = function(_, itemLink)
                return itemLink == UPGRADED and 900000 or 300000
            end,
        } } }

        MLH.db.char.config.priceSource = "auctionator"
        MLH:clearPriceCache()
    end)

    after_each(function()
        _G.Auctionator = nil
        MLH:clearPriceCache()
    end)

    it("are looked up once per link, not once per item", function()
        assert.are.equal(300000, (MLH:getItemPrice(212000, 1000, BASE)))
        assert.are.equal(900000, (MLH:getItemPrice(212000, 2500, UPGRADED)))
    end)
end)

describe("Auction Bourse prices", function()
    local asked

    before_each(function()
        seed()

        asked = {}
        _G.AuctionBourseAPI = { v1 = {
            GetPriceByItemLink = function(itemLink)
                asked[#asked + 1] = itemLink

                if (itemLink == UPGRADED) then return 900000, 1000 end
                if (itemLink == BASE) then return 300000, 1000 end

                return nil
            end,
            GetPriceByItemID = function(itemID) return itemID == 2589 and 120 or nil end,
        } }

        MLH.db.char.config.priceSource = "auctionbourse"
        MLH:clearPriceCache()
    end)

    after_each(function()
        _G.AuctionBourseAPI = nil
        MLH.db.char.config.priceSource = "vendor"
        MLH:clearPriceCache()
    end)

    it("are a price source of their own, offered while Auction Bourse is loaded", function()
        assert.are.equal("auctionbourse", (MLH:getPriceSource()))
        assert.is_not_nil(MLH:getPriceSources().auctionbourse)
    end)

    it("price each drop by its link, so gear is valued at its own item level", function()
        assert.are.same({ 300000, false }, { MLH:getItemPrice(212000, 1000, BASE) })
        assert.are.same({ 900000, false }, { MLH:getItemPrice(212000, 2500, UPGRADED) })
    end)

    it("are asked once per link", function()
        MLH:getItemPrice(212000, 1000, BASE)
        MLH:getItemPrice(212000, 1000, BASE)

        assert.are.equal(1, #asked)
    end)

    it("fall back to the item ID when the link has no price, and to the vendor price when that has none", function()
        assert.are.same({ 120, false }, { MLH:getItemPrice(2589, 25, "|cffffffff|Hitem:2589::::::::5|h[Linen]|h|r") })
        assert.are.same({ 40, true }, { MLH:getItemPrice(4306, 40, "|cffffffff|Hitem:4306::::::::5|h[Silk]|h|r") })
    end)

    it("leave the vendor price in use when Auction Bourse is not loaded", function()
        local installed = MLH:getPriceSources().auctionbourse

        _G.AuctionBourseAPI = nil
        MLH:clearPriceCache()

        assert.are.equal("vendor", (MLH:getPriceSource()))
        assert.are.same({ 1000, false }, { MLH:getItemPrice(212000, 1000, BASE) })
        assert.are_not.equal(installed, MLH:getPriceSources().auctionbourse)
    end)
end)
