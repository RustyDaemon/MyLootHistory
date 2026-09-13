--[[
My Loot History addon
Copyright (C) 2026 RustyDaemon (https://github.com/RustyDaemon)

See License file for details.
--]]

local addonName, addon = ...

local MLH = LibStub("AceAddon-3.0"):NewAddon(addonName, "AceConsole-3.0", "AceEvent-3.0")
local L = LibStub("AceLocale-3.0"):GetLocale(addonName)

addon.MLH = MLH

MLH.website = "https://mlh.rustydaemon.com"

-- Test MULTIPLE forms first: single-item patterns also match multi-item messages.
local lootMessageForms = {
    { global = "LOOT_ITEM_SELF_MULTIPLE",         hasQuantity = true  },
    { global = "LOOT_ITEM_PUSHED_SELF_MULTIPLE",  hasQuantity = true,  kind = "pushed"  },
    { global = "LOOT_ITEM_CREATED_SELF_MULTIPLE", hasQuantity = true,  kind = "crafted" },
    { global = "LOOT_ITEM_SELF",                  hasQuantity = false },
    { global = "LOOT_ITEM_PUSHED_SELF",           hasQuantity = false, kind = "pushed"  },
    { global = "LOOT_ITEM_CREATED_SELF",          hasQuantity = false, kind = "crafted" },
}

local currencyMessageForms = {
    { global = "CURRENCY_GAINED_MULTIPLE_BONUS", hasQuantity = true  },
    { global = "CURRENCY_GAINED_MULTIPLE",       hasQuantity = true  },
    { global = "CURRENCY_GAINED",                hasQuantity = false },
}

local lootPatterns = nil
local currencyPatterns = nil

-- Capture only quantity so localized argument order does not affect parsing.
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
                kind = form.kind,
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

local function matchQuantity(message, patterns)
    for i = 1, #patterns do
        local form = patterns[i]
        local match = message:match(form.pattern)

        if (match) then
            return form.hasQuantity and (tonumber(match) or 1) or 1, form.kind
        end
    end

    return nil
end

function MLH:OnInitialize()
    self:initDatabase()

    local removedEntries, removedRecords = self:pruneHistory()

    if (removedEntries > 0) then
        print(L["M_HistoryPruned"](removedEntries, removedRecords, self.db.char.config.retentionDays))
    end

    self:initConfig()
    self:initMinimap()
    self:RegisterChatCommand("mlh", "SlashCommandListener")

    self:closeSession()
    self:beginSession()

    print(L["_IntroMessage"](addonName))
end

function MLH:OnEnable()
    self:RegisterEvent("CHAT_MSG_LOOT")
    self:RegisterEvent("CHAT_MSG_MONEY")
    self:RegisterEvent("CHAT_MSG_CURRENCY")

    self:applySourceTracking()
    self:initTooltip()

    self:applyHUD()
end

function MLH:debugPrint(message)
    if (self.db.char.config.debug.printOtherDebugInfo) then
        print(message)
    end
end

function MLH:debugSummary(message)
    if (self.db.char.config.debug.printLootedSummary) then
        print(message)
    end
end

function MLH:CHAT_MSG_LOOT(_, message, ...)
    local itemLink, quantity, itemID, messageKind = self:getLootDetails(message)

    if (not itemID) then
        self:debugPrint(L["D_NotMyItem"])
        return
    end

    -- Capture zone and source before asynchronous item loading.
    local zoneID = self:getZoneID()
    local source = self:getCurrentSource(messageKind)

    Item:CreateFromItemID(itemID):ContinueOnItemLoad(function()
        self:recordLoot(itemID, itemLink, quantity, zoneID, source)
    end)
end

function MLH:recordLoot(itemID, itemLink, quantity, zoneID, source)
    local itemName, cachedLink, itemQuality, _, _, _, _, _, _, itemTexture, sellPrice, classID, subClassID =
        C_Item.GetItemInfo(itemID)

    if (self:isQuestItem(classID, subClassID)) then
        self:debugPrint(L["D_QuestItem"])
        return
    end

    sellPrice = sellPrice or 0

    if (sellPrice == 0 and self.db.char.config.ignoreItemsWithZeroPrice) then
        self:debugPrint(L["D_ZeroSellPrice"])
        return
    end

    itemLink = itemLink or cachedLink
    local totalAmount = self:addItem(itemID, quantity, itemLink, itemTexture, itemQuality,
        itemName, zoneID, sellPrice, source)

    self:debugSummary(L["D_AddedAndTotal"](itemLink, totalAmount))
end

function MLH:CHAT_MSG_MONEY(_, message, ...)
    local money = 0
    local denominations = { { "GOLD_AMOUNT", 10000 }, { "SILVER_AMOUNT", 100 }, { "COPPER_AMOUNT", 1 } }
    for _, denomination in ipairs(denominations) do
        -- Only the first texture format argument is the coin amount; the rest are dimensions.
        for _, suffix in ipairs({ "", "_TEXTURE" }) do
            local fmt = _G[denomination[1]..suffix]
            if (fmt) then
                local pattern = fmt:gsub("%%%d%$", "%%")
                pattern = pattern:gsub("%%[ds]", "MLHQUANTITY", 1)
                pattern = pattern:gsub("([%^%$%(%)%.%[%]%*%+%-%?])", "%%%1")
                pattern = pattern:gsub("%%d", "%%d+"):gsub("%%s", ".-")
                pattern = pattern:gsub("MLHQUANTITY", "([%%d%%s,%%.]+)")
                local amount = message:match(pattern)
                if (amount) then
                    money = money + (tonumber((amount:gsub("%D", ""))) or 0) * denomination[2]
                    break
                end
            end
        end
    end
    if (money > 0) then
        self:addGold(money, self:getZoneID())
    else
        self:debugPrint(L["D_NoMoneyMatched"])
    end
end

function MLH:CHAT_MSG_CURRENCY(_, message, ...)
    if (not self.db.char.config.trackCurrency) then return end

    local currencyID, quantity = self:getCurrencyDetails(message)

    if (not currencyID) then
        self:debugPrint(L["D_NotMyCurrency"])
        return
    end

    local info = C_CurrencyInfo.GetCurrencyInfo(currencyID)
    local totalAmount = self:addCurrency(currencyID, quantity, info and info.name,
        info and info.iconFileID, info and info.quality, self:getZoneID())

    local link = C_CurrencyInfo.GetCurrencyLink(currencyID, quantity)

    self:debugSummary(L["D_AddedAndTotal"](link or (info and info.name) or currencyID, totalAmount))
end

function MLH:isQuestItem(classID, subClassID)
    return (classID == Enum.ItemClass.Questitem) or (classID == Enum.ItemClass.Consumable and subClassID == 8)
end

function MLH:getLootDetails(message)
    local quantity, kind = matchQuantity(message, getLootPatterns())

    if (not quantity) then return nil end

    local itemLink = message:match("|c.-|h|r")

    if (not itemLink) then return nil end

    return itemLink, quantity, C_Item.GetItemInfoInstant(itemLink), kind
end

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

-- Cache unknown map IDs as false to avoid repeated lookups.
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

function MLH:aggregateLoot(entries, unknownZoneName)
    local quantity, firstFound, lastFound = 0, nil, nil
    local zoneCounts, zones = {}, {}

    for i = 1, #entries do
        local entry = entries[i]
        local entryQuantity = tonumber(entry.quantity) or 1
        local zoneName = self:getZoneName(entry.zoneID) or unknownZoneName
        local foundOn = entry.foundOn

        quantity = quantity + entryQuantity

        if (zoneName) then
            zoneCounts[zoneName] = (zoneCounts[zoneName] or 0) + entryQuantity
        end

        if (foundOn) then
            if (firstFound == nil or foundOn < firstFound) then firstFound = foundOn end
            if (lastFound == nil or foundOn > lastFound) then lastFound = foundOn end
        end
    end

    for zoneName, zoneQuantity in pairs(zoneCounts) do
        zones[#zones+1] = { name = zoneName, quantity = zoneQuantity }
    end

    table.sort(zones, function(l, r)
        if (l.quantity == r.quantity) then return l.name < r.name end
        return l.quantity > r.quantity
    end)

    return quantity, zones, firstFound, lastFound
end

function MLH:SlashCommandListener(input)
    if (input == "config") then
        LibStub("AceConfigDialog-3.0"):Open("MyLootHistory_GeneralOptions")
    elseif (input == "session") then
        print(self:getSessionLine())
    elseif (input == "session reset") then
        self:resetSession()
        print(self:getSessionLine())
    elseif (input == "hud") then
        print(self:toggleHUD() and L["M_HudShown"] or L["M_HudHidden"])
    elseif (input == "hud lock") then
        print(self:toggleHUDLock() and L["M_HudLocked"] or L["M_HudUnlocked"])
    elseif (input == "gui") then
        self:gui()
    elseif (input == "help") then
        print(L["M_Help"](self.website))
    elseif (input == "web" or input == "website") then
        print(L["M_Website"](self.website))
    else
        self:gui()
    end
end
