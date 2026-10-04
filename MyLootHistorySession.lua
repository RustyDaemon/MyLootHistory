--[[
My Loot History addon
Copyright (C) 2026 RustyDaemon (https://github.com/RustyDaemon)

See License file for details.
--]]

local MLH = LibStub("AceAddon-3.0"):GetAddon("MyLootHistory")
local L = LibStub("AceLocale-3.0"):GetLocale("MyLootHistory")

local SECONDS_PER_HOUR = 3600

local MAX_SESSIONS = 40

-- New entries use session IDs; legacy entries fall back to timestamp windows.
function MLH:isEntryInSession(entry, session)
    if (entry.sessionID ~= nil or session.id ~= nil) then
        return entry.sessionID == session.id
    end
    return entry.foundOn ~= nil and entry.foundOn >= session.startedOn
        and (session.endedOn == nil or entry.foundOn <= session.endedOn)
end

function MLH:beginSession()
    local char = self.db.char
    char.sessionSerial = (char.sessionSerial or 0) + 1
    char.currentSessionID = self:getCharacterKey()..":"..char.sessionSerial
    char.thisSessionStart = time()
    self:bumpRevision()
end

-- Quest rewards are history, but not farming: they count toward the rates only when asked to.
function MLH:countsTowardRates(entry)
    if (entry.source == nil or entry.source.kind ~= "quest") then return true end

    return self.db.char.config.questRewardsInRates == true
end

-- History is chronological; scan backwards. Missing quantity counts as one, or zero for gold.
-- unitValue(entry), when given, prices one of the entry's units; the second return is their sum.
local function inWindow(entries, startedOn, missingQuantity, session, unitValue)
    local quantity, value = 0, 0

    for i = #entries, 1, -1 do
        local entry = entries[i]
        local foundOn = entry.foundOn

        if (foundOn == nil or foundOn < startedOn) then break end

        if (MLH:isEntryInSession(entry, session) and MLH:countsTowardRates(entry)) then
            local entryQuantity = tonumber(entry.quantity) or missingQuantity

            quantity = quantity + entryQuantity

            if (unitValue) then value = value + unitValue(entry) * entryQuantity end
        end
    end

    return quantity, value
end

function MLH:getSessionStats(session)
    session = session or self:getLiveSession()

    local sessionStart = session.startedOn or time()
    local endedOn = session.endedOn
    local duration = math.max((endedOn or time()) - sessionStart, 1)

    local stats = {
        sessionStart = sessionStart,
        endedOn = endedOn,
        isLive = endedOn == nil,
        duration = duration,
        itemTypes = 0,
        quantity = 0,
        itemValue = 0,
        rawGold = 0,
        currencyQuantity = 0,
        currencyTypes = 0,
    }

    local foundItems = self.db.char.foundItems

    for i = 1, #foundItems do
        local item = foundItems[i]

        -- A hidden item is one the player said does not matter, so it does not count toward the rates.
        -- Each drop is priced by the link it dropped as, so an upgraded one counts at its own value.
        local lootData = self:isItemHidden(item.itemId) and {} or item.lootData
        local sessionQuantity, sessionValue = inWindow(lootData, sessionStart, 1, session, function(entry)
            return (self:getItemPrice(item.itemId, entry.sellPrice or 0, entry.itemLink or item.itemLink))
        end)

        if (sessionQuantity > 0) then
            stats.itemTypes = stats.itemTypes + 1
            stats.quantity = stats.quantity + sessionQuantity
            stats.itemValue = stats.itemValue + sessionValue

            -- The item paying most for the session; ties go to the larger pile.
            local top = stats.topItem

            if (not top or sessionValue > top.value
                or (sessionValue == top.value and sessionQuantity > top.quantity)) then
                stats.topItem = {
                    itemId = item.itemId, link = item.itemLink, name = item.itemName,
                    quantity = sessionQuantity, value = sessionValue,
                }
            end
        end
    end

    stats.rawGold = inWindow(self.db.char.foundGold, sessionStart, 0, session)

    local foundCurrency = self.db.char.foundCurrency or {}

    for i = 1, #foundCurrency do
        local sessionQuantity = inWindow(foundCurrency[i].lootData, sessionStart, 1, session)

        if (sessionQuantity > 0) then
            stats.currencyTypes = stats.currencyTypes + 1
            stats.currencyQuantity = stats.currencyQuantity + sessionQuantity
        end
    end

    stats.totalValue = stats.itemValue + stats.rawGold
    stats.goldPerHour = math.floor(stats.totalValue / duration * SECONDS_PER_HOUR)
    stats.itemsPerHour = stats.quantity / duration * SECONDS_PER_HOUR

    return stats
end

function MLH:formatDuration(seconds)
    seconds = math.max(math.floor(seconds or 0), 0)

    local hours = math.floor(seconds / 3600)
    local minutes = math.floor(seconds % 3600 / 60)

    if (hours > 0) then
        return hours.."h "..minutes.."m"
    end

    return string.format("%02d:%02d", minutes, seconds % 60)
end

function MLH:getSessionLine()
    local stats = self:getSessionStats()

    return L["S_SessionLine"](
        self:formatDuration(stats.duration),
        stats.quantity,
        string.format("%.0f", stats.itemsPerHour),
        GetMoneyString(stats.totalValue),
        GetMoneyString(stats.goldPerHour),
        stats.currencyQuantity
    )
end

-- One chat line for the session: time, items, gold and the item that paid most. Plain text and an
-- item link only, since chat refuses the coin textures the report uses.
function MLH:getShareLine(session)
    local stats = self:getSessionStats(session)
    local top = stats.topItem
    local topText = top and L["S_ShareTop"](top.link or top.name or ("#"..top.itemId), top.quantity) or ""

    return L["S_ShareLine"](
        self:formatDuration(stats.duration),
        stats.quantity,
        self:formatGoldCompact(stats.totalValue),
        self:formatGoldCompact(stats.goldPerHour),
        topText
    )
end

local SHARE_CHANNELS = {
    { channel = "INSTANCE_CHAT", label = "S_ShareInstance",
      available = function() return IsInGroup and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) end },
    { channel = "RAID", label = "S_ShareRaid", available = function() return IsInRaid and IsInRaid() end },
    { channel = "PARTY", label = "S_ShareParty", available = function() return IsInGroup and IsInGroup() end },
    { channel = "GUILD", label = "S_ShareGuild", available = function() return IsInGuild and IsInGuild() end },
    { channel = "SAY", label = "S_ShareSay", available = function() return true end },
}

local SHARE_ALIASES = {
    instance = "INSTANCE_CHAT", i = "INSTANCE_CHAT",
    raid = "RAID", r = "RAID",
    party = "PARTY", p = "PARTY",
    guild = "GUILD", g = "GUILD",
    say = "SAY", s = "SAY",
}

-- The channels the player can share to right now, the group they are in first: { channel, text }.
function MLH:getShareChannels()
    local list = {}

    for i = 1, #SHARE_CHANNELS do
        local entry = SHARE_CHANNELS[i]

        if (entry.available()) then
            list[#list+1] = { channel = entry.channel, text = L[entry.label] }
        end
    end

    return list
end

-- The channel a word from the slash command names, or the group's channel when it names none.
-- nil when it names none and there is no group: the line is then only shown to the player.
function MLH:resolveShareChannel(word)
    word = word and word:lower() or ""

    if (word ~= "") then return SHARE_ALIASES[word], SHARE_ALIASES[word] == nil end

    local channels = self:getShareChannels()
    local first = channels[1]

    if (first and first.channel ~= "GUILD" and first.channel ~= "SAY") then return first.channel end

    return nil
end

-- Sends the session line to a chat channel, or prints it for the player alone when channel is nil.
function MLH:shareSession(channel, session)
    local line = self:getShareLine(session)

    if (not channel) then
        print(line)
        return line
    end

    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage

    send(line, channel)

    return line
end

function MLH:getLiveSession()
    return { startedOn = self.db.char.thisSessionStart or time(), id = self.db.char.currentSessionID }
end

function MLH:getSessions()
    local stored = self.db.char.sessions or {}
    local sessions = {}

    for i = #stored, 1, -1 do
        sessions[#sessions+1] = stored[i]
    end

    return sessions
end

function MLH:getSelectedSession()
    local selected = self:getFilters().session

    if (not selected or selected == 0) then return self:getLiveSession() end

    local stored = self.db.char.sessions or {}

    for i = 1, #stored do
        if ((stored[i].id or stored[i].startedOn) == selected) then return stored[i] end
    end

    return self:getLiveSession()
end

-- Use the last pickup as the session end because logout time is unavailable.
local function lastActivity(history, startedOn, session)
    local latest = nil

    local function scan(records, nested)
        for i = 1, #records do
            local entries = nested and records[i].lootData or { records[i] }

            for j = 1, #entries do
                local foundOn = entries[j].foundOn

                if (foundOn and foundOn >= startedOn and MLH:isEntryInSession(entries[j], session)
                    and (latest == nil or foundOn > latest)) then
                    latest = foundOn
                end
            end
        end
    end

    scan(history.foundItems or {}, true)
    scan(history.foundCurrency or {}, true)
    scan(history.foundGold or {}, false)

    return latest
end

function MLH:closeSession(startedOn)
    local char = self.db.char

    startedOn = startedOn or char.thisSessionStart

    if (not startedOn) then return nil end

    local session = { startedOn = startedOn, id = char.currentSessionID }
    local endedOn = lastActivity(char, startedOn, session)

    if (not endedOn) then return nil end

    char.sessions = char.sessions or {}
    session.endedOn = endedOn
    char.sessions[#char.sessions+1] = session

    while (#char.sessions > MAX_SESSIONS) do
        table.remove(char.sessions, 1)
    end

    return char.sessions[#char.sessions]
end

function MLH:resetSession()
    self:closeSession()

    self:beginSession()

    self:setFilter("session", 0)
end

function MLH:getSelectedSessionName()
    local session = self:getSelectedSession()

    if (session.endedOn == nil) then return L["S_LiveSession"] end

    return L["S_PastSession"](date("%d %b %H:%M", session.startedOn))
end

function MLH:getSessionList()
    local list = {
        { value = 0, text = L["S_LiveSession"], session = self:getLiveSession() },
    }

    local sessions = self:getSessions()

    for i = 1, #sessions do
        local session = sessions[i]
        local stats = self:getSessionStats(session)

        list[#list+1] = {
            value = session.id or session.startedOn,
            text = L["S_SessionEntry"](
                date("%d %b %H:%M", session.startedOn),
                self:formatDuration(stats.duration),
                self:formatGoldCompact(stats.totalValue)
            ),
            session = session,
        }
    end

    return list
end
