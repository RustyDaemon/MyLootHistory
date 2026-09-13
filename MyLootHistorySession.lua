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
    self.historyRevision = (self.historyRevision or 0) + 1
end

-- History is chronological; scan backwards. Missing quantity counts as one, or zero for gold.
local function inWindow(entries, startedOn, missingQuantity, session)
    local quantity = 0

    for i = #entries, 1, -1 do
        local entry = entries[i]
        local foundOn = entry.foundOn

        if (foundOn == nil or foundOn < startedOn) then break end

        if (MLH:isEntryInSession(entry, session)) then
            quantity = quantity + (tonumber(entry.quantity) or missingQuantity)
        end
    end

    return quantity
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
        local lootData = item.lootData
        local sessionQuantity = inWindow(lootData, sessionStart, 1, session)

        if (sessionQuantity > 0) then
            local unitPrice = self:getItemPrice(item.itemId, lootData[#lootData].sellPrice or 0, item.itemLink)

            stats.itemTypes = stats.itemTypes + 1
            stats.quantity = stats.quantity + sessionQuantity
            stats.itemValue = stats.itemValue + unitPrice * sessionQuantity
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
