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
--
-- `kind` is what the form itself says about where the item came from, for the drops that
-- never open a loot window: something crafted or gathered, and something pushed straight
-- into the bags by a quest turn-in or a container opening in place. A plain "you receive
-- loot" says nothing, and its source comes from the loot window instead.
local lootMessageForms = {
    { global = "LOOT_ITEM_SELF_MULTIPLE",         hasQuantity = true  },
    { global = "LOOT_ITEM_PUSHED_SELF_MULTIPLE",  hasQuantity = true,  kind = "pushed"  },
    { global = "LOOT_ITEM_CREATED_SELF_MULTIPLE", hasQuantity = true,  kind = "crafted" },
    { global = "LOOT_ITEM_SELF",                  hasQuantity = false },
    { global = "LOOT_ITEM_PUSHED_SELF",           hasQuantity = false, kind = "pushed"  },
    { global = "LOOT_ITEM_CREATED_SELF",          hasQuantity = false, kind = "crafted" },
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

-- Walks a set of patterns and returns the quantity the matching one carries - and what the
-- form says about where the item came from - or nil when the message is not one of them.
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

    -- retention is applied once, here, so nothing else in the session has to think about it
    local removedEntries, removedRecords = self:pruneHistory()

    if (removedEntries > 0) then
        print(L["M_HistoryPruned"](removedEntries, removedRecords, self.db.char.config.retentionDays))
    end

    self:initConfig()
    self:initMinimap()
    self:RegisterChatCommand("mlh", "SlashCommandListener")

    -- the session from the last time this character played ends where its last loot entry
    -- does: the client cannot say when the player logged out, and guessing would inflate it
    self:closeSession()
    self.db.char.thisSessionStart = time()

    print(L["_IntroMessage"](addonName))
end

function MLH:OnEnable()
    self:RegisterEvent("CHAT_MSG_LOOT")
    self:RegisterEvent("CHAT_MSG_MONEY")
    self:RegisterEvent("CHAT_MSG_CURRENCY")

    -- the loot-source events live on their own frame, in MyLootHistorySource.lua
    self:applySourceTracking()
    self:initTooltip()
end

-- Debug output is off by default, and its two switches were read at every call
-- site. The guard lives here instead, so a caller only says what it wants to say.
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

    -- the zone has to be captured now: the item data may only arrive a few frames later
    local zoneID = self:getZoneID()
    -- and so does the source: the loot window can be shut by the time the item loads
    local source = self:getCurrentSource(messageKind)

    -- ContinueOnItemLoad fires immediately when the item is already cached, and after
    -- the client has loaded it otherwise - so a cold cache no longer stores nil data
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
    local moneyTable = {}
    _ = message:gsub(L["_MoneyPattern"], function(n) moneyTable[#moneyTable+1] = tonumber(n) end)

    local amount = #moneyTable

    if (amount == 0) then
        self:debugPrint(L["D_NoMoneyMatched"])
        return
    end

    local money = moneyTable[amount] + (moneyTable[amount-1] or 0)*100 + (moneyTable[amount-2] or 0)*10000

    self:addGold(money, self:getZoneID())
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
    -- probably, there might be something that is missing, will see
    -- for example itemID=76298 has cID=0 and scID=8 and it IS QUEST ITEM
    -- so see the second clause, hope it will work
    return (classID == Enum.ItemClass.Questitem) or (classID == Enum.ItemClass.Consumable and subClassID == 8)
end

-- Returns nil unless the message is one of the six "you looted this" forms.
-- Parsing only: everything here works without the item being cached.
function MLH:getLootDetails(message)
    local quantity, kind = matchQuantity(message, getLootPatterns())

    if (not quantity) then return nil end

    local itemLink = message:match("|c.-|h|r")

    if (not itemLink) then return nil end

    -- GetItemInfoInstant returns the ID without needing the item cached, and yields nil for
    -- non-item links (battle pets, keystones), which is exactly what the caller wants
    return itemLink, quantity, C_Item.GetItemInfoInstant(itemLink), kind
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

-- Rolls a list of loot entries up into the four numbers every view wants: how many
-- were looted, which zones they came from busiest-first, and when the first and
-- last one was. The report rows, the tooltip line and the CSV export all used to
-- work this out for themselves; doing it in one pass in one place is why they can
-- no longer disagree about what a history adds up to.
--
-- `unknownZoneName` decides what happens to an entry whose zone the client can no
-- longer name - a zone removed by a patch. Pass a label to group them under it, or
-- nil to leave them out of the zone tally; either way they still count towards the
-- quantity, because the item really was looted.
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

        -- an entry written by a very old version can carry no timestamp at all
        if (foundOn) then
            if (firstFound == nil or foundOn < firstFound) then firstFound = foundOn end
            if (lastFound == nil or foundOn > lastFound) then lastFound = foundOn end
        end
    end

    for zoneName, zoneQuantity in pairs(zoneCounts) do
        zones[#zones+1] = { name = zoneName, quantity = zoneQuantity }
    end

    -- busiest first, so zones[1] is the one worth showing where there is room for one
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
    elseif (input == "gui") then
        self:gui()
    else
        self:gui()
    end
end
