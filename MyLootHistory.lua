--[[
My Loot History addon
Copyright (C) 2026 RustyDaemon (https://github.com/RustyDaemon)

See License file for details.
--]]

local addonName, addon = ...

local MLH = LibStub("AceAddon-3.0"):NewAddon(addonName, "AceConsole-3.0", "AceEvent-3.0")
local L = LibStub("AceLocale-3.0"):GetLocale(addonName)

addon.MLH = MLH

-- The message forms the client uses when *you* pick something up. The _MULTIPLE variants
-- have to be tested first: their single-item counterpart matches a multi-item message too.
local lootMessageForms = {
    { global = "LOOT_ITEM_SELF_MULTIPLE",         hasQuantity = true  },
    { global = "LOOT_ITEM_PUSHED_SELF_MULTIPLE",  hasQuantity = true  },
    { global = "LOOT_ITEM_CREATED_SELF_MULTIPLE", hasQuantity = true  },
    { global = "LOOT_ITEM_SELF",                  hasQuantity = false },
    { global = "LOOT_ITEM_PUSHED_SELF",           hasQuantity = false },
    { global = "LOOT_ITEM_CREATED_SELF",          hasQuantity = false },
}

-- The same idea for currency. CURRENCY_GAINED carries no amount, so it means one.
local currencyMessageForms = {
    { global = "CURRENCY_GAINED_MULTIPLE_BONUS", hasQuantity = true  },
    { global = "CURRENCY_GAINED_MULTIPLE",       hasQuantity = true  },
    { global = "CURRENCY_GAINED",                hasQuantity = false },
}

local lootPatterns = nil
local currencyPatterns = nil

-- Turns a client format string ("You receive loot: %sx%d.") into a Lua pattern.
-- The item name is deliberately not captured - the link is pulled straight out of the
-- message instead - so the quantity stays the only capture whatever order a locale
-- puts the arguments in.
local function toLootPattern(fmt, hasQuantity)
    local pattern = fmt:gsub("%%%d%$", "%%")                        -- %1$s -> %s
    pattern = pattern:gsub("([%^%$%(%)%.%[%]%*%+%-%?])", "%%%1")    -- escape pattern magic
    pattern = pattern:gsub("%%s", ".+")
    pattern = pattern:gsub("%%d", hasQuantity and "(%%d+)" or "%%d+")

    return "^"..pattern
end

local function buildPatterns(forms)
    local patterns = {}

    for i = 1, #forms do
        local form = forms[i]
        local fmt = _G[form.global]

        if (fmt) then
            patterns[#patterns+1] = {
                pattern = toLootPattern(fmt, form.hasQuantity),
                hasQuantity = form.hasQuantity,
            }
        end
    end

    return patterns
end

local function getLootPatterns()
    if (not lootPatterns) then
        lootPatterns = buildPatterns(lootMessageForms)
    end

    return lootPatterns
end

local function getCurrencyPatterns()
    if (not currencyPatterns) then
        currencyPatterns = buildPatterns(currencyMessageForms)
    end

    return currencyPatterns
end

-- Walks a set of patterns and returns the quantity the matching one carries, or nil when
-- the message is not one of them.
local function matchQuantity(message, patterns)
    for i = 1, #patterns do
        local form = patterns[i]
        local match = message:match(form.pattern)

        if (match) then
            return form.hasQuantity and (tonumber(match) or 1) or 1
        end
    end

    return nil
end

function MLH:OnInitialize()
    self:initDatabase()
    self:initConfig()
    self:initMinimap()
    self:RegisterChatCommand("mlh", "SlashCommandListener")

    self.db.char.thisSessionStart = time()
    print(L["_IntroMessage"](addonName))
end

function MLH:OnEnable()
    self:RegisterEvent("CHAT_MSG_LOOT")
    self:RegisterEvent("CHAT_MSG_MONEY")
    self:RegisterEvent("CHAT_MSG_CURRENCY")
    self:initTooltip()
end

function MLH:Disable()
end

function MLH:CHAT_MSG_LOOT(_, message, ...)
    local itemLink, quantity, itemID = self:getLootDetails(message)

    if (not itemID) then
        if (self.db.char.config.debug.printOtherDebugInfo) then
            print(L["D_NotMyItem"])
        end
        return
    end

    -- the zone has to be captured now: the item data may only arrive a few frames later
    local zoneID = self:getZoneID()

    -- ContinueOnItemLoad fires immediately when the item is already cached, and after
    -- the client has loaded it otherwise - so a cold cache no longer stores nil data
    Item:CreateFromItemID(itemID):ContinueOnItemLoad(function()
        self:recordLoot(itemID, itemLink, quantity, zoneID)
    end)
end

function MLH:recordLoot(itemID, itemLink, quantity, zoneID)
    local itemName, cachedLink, itemQuality, _, _, _, _, _, _, itemTexture, sellPrice, classID, subClassID =
        C_Item.GetItemInfo(itemID)

    if (self:isQuestItem(classID, subClassID)) then
        if (self.db.char.config.debug.printOtherDebugInfo) then
            print(L["D_QuestItem"])
        end
        return
    end

    sellPrice = sellPrice or 0

    if (sellPrice == 0 and self.db.char.config.ignoreItemsWithZeroPrice) then
        if (self.db.char.config.debug.printOtherDebugInfo) then
            print(L["D_ZeroSellPrice"])
        end
        return
    end

    itemLink = itemLink or cachedLink
    local totalAmount = self:addItem(itemID, quantity, itemLink, itemTexture, itemQuality, itemName, zoneID, sellPrice)

    if (self.db.char.config.debug.printLootedSummary) then
        print(L["D_AddedAndTotal"](itemLink, totalAmount))
    end

    self:updateStatisticsTextData()
end

function MLH:CHAT_MSG_MONEY(_, message, ...)
    local message = message
    local moneyTable = {}
    _ = message:gsub(L["_MoneyPattern"], function(n) moneyTable[#moneyTable+1] = tonumber(n) end)

    local amount = #moneyTable

    if (amount == 0) then
        if (self.db.char.config.debug.printOtherDebugInfo) then
            print(L["D_NoMoneyMatched"])
        end
        return
    end

    local money = moneyTable[amount] + (moneyTable[amount-1] or 0)*100 + (moneyTable[amount-2] or 0)*10000

    self:addGold(money, self:getZoneID())
end

function MLH:CHAT_MSG_CURRENCY(_, message, ...)
    if (not self.db.char.config.trackCurrency) then return end

    local currencyID, quantity = self:getCurrencyDetails(message)

    if (not currencyID) then
        if (self.db.char.config.debug.printOtherDebugInfo) then
            print(L["D_NotMyCurrency"])
        end
        return
    end

    local info = C_CurrencyInfo.GetCurrencyInfo(currencyID)
    local totalAmount = self:addCurrency(currencyID, quantity, info and info.name,
        info and info.iconFileID, info and info.quality, self:getZoneID())

    if (self.db.char.config.debug.printLootedSummary) then
        local link = C_CurrencyInfo.GetCurrencyLink(currencyID, quantity)
        print(L["D_AddedAndTotal"](link or (info and info.name) or currencyID, totalAmount))
    end

    self:updateStatisticsTextData()
end

function MLH:isQuestItem(classID, subClassID)
    -- probably, there might be something that is missing, will see
    -- for example itemID=76298 has cID=0 and scID=8 and it IS QUEST ITEM
    -- so see the second clause, hope it will work
    return (classID == Enum.ItemClass.Questitem) or (classID == Enum.ItemClass.Consumable and subClassID == 8)
end

-- Returns nil unless the message is one of the six "you looted this" forms.
-- Parsing only: everything here works without the item being cached.
function MLH:getLootDetails(message)
    local quantity = matchQuantity(message, getLootPatterns())

    if (not quantity) then return nil end

    local itemLink = message:match("|c.-|h|r")

    if (not itemLink) then return nil end

    return itemLink, quantity, C_Item.GetItemInfoFromHyperlink(itemLink)
end

-- Returns nil unless the message is one of the "you receive currency" forms. The currency
-- ID comes out of the link, so no locale ever has to be read.
function MLH:getCurrencyDetails(message)
    local quantity = matchQuantity(message, getCurrencyPatterns())

    if (not quantity) then return nil end

    local currencyID = tonumber(message:match("|Hcurrency:(%d+)"))

    if (not currencyID) then return nil end

    return currencyID, quantity
end

function MLH:getZoneID()
    return C_Map.GetBestMapForUnit("player")
end

-- Map IDs never change name within a session, and the report resolves the same handful of
-- them on every redraw, so the lookup is memoised. `false` marks an ID the client no longer
-- knows about - a zone removed by a patch - so it is not looked up again either.
local zoneNameCache = {}

function MLH:getZoneName(zoneID)
    if (not zoneID) then return nil end

    local cached = zoneNameCache[zoneID]

    if (cached ~= nil) then
        return cached or nil
    end

    local zoneInfo = C_Map.GetMapInfo(zoneID)
    local zoneName = zoneInfo and zoneInfo.name

    zoneNameCache[zoneID] = zoneName or false

    return zoneName
end

function MLH:SlashCommandListener(input)
    if (input == "config") then
        LibStub("AceConfigDialog-3.0"):Open("MyLootHistory_GeneralOptions")
    elseif (input == "session") then
        print(self:getSessionLine())
    elseif (input == "session reset") then
        self:resetSession()
        print(self:getSessionLine())
    elseif (input == "gui") then
        self:gui()
    else
        self:gui()
    end
end
