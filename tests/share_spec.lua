local wow = require("tests.support.wow")

wow.loadThrough("MyLootHistoryData.lua")
wow.load("locales/enUS.lua")

local MLH = wow.addon

local group = { instance = false, raid = false, party = false, guild = false }

_G.LE_PARTY_CATEGORY_INSTANCE = 2
_G.IsInGroup = function(category)
    if (category == 2) then return group.instance end

    return group.party or group.raid or group.instance
end
_G.IsInRaid = function() return group.raid end
_G.IsInGuild = function() return group.guild end

local sent, printed = {}, {}

_G.SendChatMessage = function(text, channel) sent[#sent+1] = { text = text, channel = channel } end

local ORE_LINK = "|cffffffff|Hitem:100|h[Copper Ore]|h|r"

local function seed()
    MLH:initDatabase()

    wow.freeze(os.time())

    local now = wow.now()
    local char = MLH.db.char

    char.thisSessionStart = now - 3600
    char.currentSessionID = nil

    char.foundItems = {
        {
            itemId = 100, itemLink = ORE_LINK, itemName = "Copper Ore", quality = 1,
            lootData = { { quantity = 40, foundOn = now - 600, sellPrice = 2500 } },
        },
        {
            itemId = 200, itemName = "Broken Fang", quality = 0,
            lootData = { { quantity = 90, foundOn = now - 300, sellPrice = 5 } },
        },
    }

    char.foundGold = { { quantity = 50000, foundOn = now - 100 } }
    char.foundCurrency = {}

    group = { instance = false, raid = false, party = false, guild = false }
    sent, printed = {}, {}

    _G.print = function(line) printed[#printed+1] = line end
end

after_each(function() wow.unfreeze() end)

describe("the share line", function()
    before_each(seed)

    it("sums up the session in plain text with the best item linked", function()
        local line = MLH:getShareLine()

        assert.is_truthy(line:find("130 items", 1, true))
        assert.is_truthy(line:find("15g", 1, true))       -- 40 x 25s + 90 x 5c + 5g
        assert.is_truthy(line:find(ORE_LINK.." x40", 1, true))
        assert.is_falsy(line:find("|T", 1, true))         -- chat refuses textures
    end)

    it("names the item paying most, not the one looted most", function()
        assert.are.equal(100, MLH:getSessionStats().topItem.itemId)
    end)

    it("leaves the best item out of an empty session", function()
        MLH.db.char.foundItems = {}

        assert.is_falsy(MLH:getShareLine():find("best", 1, true))
    end)
end)

describe("/mlh share", function()
    before_each(seed)

    it("only prints it for the player when there is no group", function()
        MLH:SlashCommandListener("share")

        assert.are.equal(0, #sent)
        assert.are.equal(2, #printed)
    end)

    it("posts to the group when there is one", function()
        group.party = true

        MLH:SlashCommandListener("share")

        assert.are.equal("PARTY", sent[1].channel)
    end)

    it("prefers the instance group, then the raid", function()
        group.raid = true

        MLH:SlashCommandListener("share")
        assert.are.equal("RAID", sent[1].channel)

        group.instance = true

        MLH:SlashCommandListener("share")
        assert.are.equal("INSTANCE_CHAT", sent[2].channel)
    end)

    it("never posts to the guild unless asked to", function()
        group.guild = true

        MLH:SlashCommandListener("share")
        assert.are.equal(0, #sent)

        MLH:SlashCommandListener("share guild")
        assert.are.equal("GUILD", sent[1].channel)
    end)

    it("takes a channel by name or first letter", function()
        MLH:SlashCommandListener("share say")
        MLH:SlashCommandListener("share P")

        assert.are.equal("SAY", sent[1].channel)
        assert.are.equal("PARTY", sent[2].channel)
    end)

    it("says so when it does not know the channel", function()
        MLH:SlashCommandListener("share trade")

        assert.are.equal(0, #sent)
        assert.is_truthy(printed[1]:find("trade", 1, true))
    end)
end)

describe("the share menu's channels", function()
    before_each(seed)

    it("lists only what the player can post to, the group first", function()
        group.party = true
        group.guild = true

        local channels = {}

        for i, entry in ipairs(MLH:getShareChannels()) do channels[i] = entry.channel end

        assert.are.same({ "PARTY", "GUILD", "SAY" }, channels)
    end)
end)
