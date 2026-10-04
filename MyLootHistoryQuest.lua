--[[
My Loot History addon
Copyright (C) 2026 RustyDaemon (https://github.com/RustyDaemon)

See License file for details.
--]]

local MLH = LibStub("AceAddon-3.0"):GetAddon("MyLootHistory")

-- A quest's rewards arrive as ordinary chat lines, a moment before or after the quest is turned in.
-- Loot that lands within LOOKBACK seconds before a turn-in, or WINDOW seconds after it, is the quest's.
local LOOKBACK = 1
local WINDOW = 2

local KIND_QUEST = "quest"

-- The turn-in being attributed: { id, expires, money, moneyClaimed }.
local window = nil

-- Entries recorded in the last moment, which a turn-in may yet claim: { entry, at, money }.
local candidates = {}

local function now()
    return (GetTime and GetTime()) or time()
end

local function questSource(questID)
    return { kind = KIND_QUEST, id = questID }
end

local function isOpen()
    return window ~= nil and now() <= window.expires
end

-- An entry already traced to a creature, an object or a container is left alone.
local function isClaimable(entry)
    return entry.source == nil or entry.source.kind == "pushed"
end

function MLH:getQuestSource()
    if (not isOpen()) then return nil end

    return questSource(window.id)
end

function MLH:rememberQuestName(questID, name)
    if (not questID) then return end

    name = name
        or (C_QuestLog and C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(questID))
        or (QuestUtils_GetQuestName and QuestUtils_GetQuestName(questID))

    if (name and name ~= "") then
        self:rememberSourceName(self:questNameKey(questID), name)
    end
end

-- Quest ids and creature ids overlap, so a quest's name is filed under a key of its own.
function MLH:questNameKey(questID)
    return "q"..tostring(questID)
end

-- money is set for a gold entry: the amount it holds, which a turn-in's reward may match.
function MLH:noteQuestCandidate(entry, money)
    if (not entry) then return end

    local at = now()

    -- An item still loading when the quest was turned in arrives here after it.
    if (isOpen() and not money and isClaimable(entry)) then
        entry.source = questSource(window.id)
        self:bumpRevision()
        return
    end

    local kept = {}

    for i = 1, #candidates do
        if (candidates[i].at >= at - LOOKBACK) then kept[#kept+1] = candidates[i] end
    end

    kept[#kept+1] = { entry = entry, at = at, money = money }
    candidates = kept
end

-- A money chat line for exactly the coins a quest just paid is that reward, already counted.
function MLH:claimQuestMoney(money)
    if (not isOpen() or window.moneyClaimed or window.money ~= money) then return false end

    window.moneyClaimed = true

    return true
end

-- Opens the window for questID and claims what arrived just before it.
-- Returns true when a gold entry that came first already holds `money`.
function MLH:attributeToQuest(questID, money)
    if (not questID or questID == 0) then return false end

    local at = now()
    local source = questSource(questID)
    local moneyFound = false

    if (not window or window.id ~= questID or not isOpen()) then
        window = { id = questID }
    end

    window.expires = at + WINDOW

    for i = 1, #candidates do
        local candidate = candidates[i]
        local entry = candidate.entry

        if (candidate.at >= at - LOOKBACK and isClaimable(entry)) then
            if (candidate.money == nil) then
                entry.source = source
            elseif (money and not moneyFound and candidate.money == money) then
                entry.source = source
                moneyFound = true
            end
        end
    end

    candidates = {}
    self:bumpRevision()

    return moneyFound
end

function MLH:QUEST_TURNED_IN(questID, _, money)
    money = tonumber(money) or 0

    self:rememberQuestName(questID)

    local alreadyCounted = self:attributeToQuest(questID, money > 0 and money or nil)

    if (money > 0 and not alreadyCounted and window) then
        self:addGold(money, self:getZoneID(), questSource(questID))

        -- A money chat line that follows for these coins is the same reward.
        window.money = money
        window.moneyClaimed = false
    end
end

-- World quests and bonus objectives announce their rewards without a quest frame.
function MLH:QUEST_LOOT_RECEIVED(questID)
    self:rememberQuestName(questID)
    self:attributeToQuest(questID)
end

local events = CreateFrame and CreateFrame("Frame")
local hooked = false

if (events) then
    events:SetScript("OnEvent", function(_, event, ...)
        if (event == "QUEST_TURNED_IN") then
            MLH:QUEST_TURNED_IN(...)
        else
            MLH:QUEST_LOOT_RECEIVED(...)
        end
    end)
end

-- Clicking Complete Quest names the quest and opens the window before any reward line arrives.
local function onQuestReward()
    local questID = GetQuestID and GetQuestID()

    if (not questID or questID == 0) then return end

    MLH:rememberQuestName(questID, GetTitleText and GetTitleText() or nil)
    MLH:attributeToQuest(questID)
end

function MLH:applyQuestTracking()
    if (not events) then return end

    events:RegisterEvent("QUEST_TURNED_IN")

    -- Not every client has these; registering an unknown event is an error.
    pcall(events.RegisterEvent, events, "QUEST_LOOT_RECEIVED")
    pcall(events.RegisterEvent, events, "QUEST_CURRENCY_LOOT_RECEIVED")

    if (not hooked and hooksecurefunc and GetQuestReward) then
        hooksecurefunc("GetQuestReward", onQuestReward)
        hooked = true
    end
end

-- Forgets the open window and the pending entries. For tests.
function MLH:resetQuestTracking()
    window = nil
    candidates = {}
end
