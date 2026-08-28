--[[
My Loot History addon
Copyright (C) 2024 Rustam (https://github.com/RustamIrzaev)

See License file for details.
--]]

local addonName, addon = ...

MLH = LibStub("AceAddon-3.0"):NewAddon(addonName, "AceConsole-3.0", "AceEvent-3.0")
local L = LibStub("AceLocale-3.0"):GetLocale(addonName)

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
end

function MLH:Disable()
end

function MLH:CHAT_MSG_LOOT(_, message, ...)
    local message = message

    if (not self:isMyLoot(message)) then
        if (self.db.char.config.debug.printOtherDebugInfo) then
            print(L["D_NotMyItem"])
        end
        return
    end

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

function MLH:isMyLoot(message)
    local lootString = LOOT_ITEM_SELF:gsub("%%s", ""):gsub("%.$", "")

    if (string.sub(message, 1, #lootString) == lootString) then
        return true
    end

    return false
end

function MLH:isQuestItem(classID, subClassID)
    -- probably, there might be something that is missing, will see
    -- for example itemID=76298 has cID=0 and scID=8 and it IS QUEST ITEM
    -- so see the second clause, hope it will work
    return (classID == Enum.ItemClass.Questitem) or (classID == Enum.ItemClass.Consumable and subClassID == 8)
end

-- parsing only: everything here works without the item being cached
function MLH:getLootDetails(message)
    local itemLink = string.match(message, "|c.-|h|r")

    if (not itemLink) then return nil, 1, nil end

    local quantity = tonumber(string.match(message, "x(%d+)%.*$")) or 1
    local itemID = C_Item.GetItemInfoFromHyperlink(itemLink)

    return itemLink, quantity, itemID
end

function MLH:getZoneID()
    local zoneID = C_Map.GetBestMapForUnit("player")
    -- local zoneInfo = C_Map.GetMapInfo(zoneID)

    return zoneID
end

function MLH:SlashCommandListener(input)
    if (input == "config") then
        LibStub("AceConfigDialog-3.0"):Open("MyLootHistory_GeneralOptions")
    elseif (input == "gui") then
        self:gui()
    else
        self:gui()
    end
end