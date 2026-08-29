--[[
My Loot History addon
Copyright (C) 2026 RustyDaemon (https://github.com/RustyDaemon)

See License file for details.
--]]

local MLH = LibStub("AceAddon-3.0"):GetAddon("MyLootHistory")
local L = LibStub("AceLocale-3.0"):GetLocale("MyLootHistory")

local SECONDS_PER_HOUR = 3600

-- How many finished sessions a character keeps. Long enough to cover a week of play,
-- short enough that the dropdown stays a list and not an archive.
local MAX_SESSIONS = 40

-- What a single history contributed inside a session's window.
--
-- Entries are appended in time order, so the walk runs backwards and stops at the
-- first one older than the window rather than reading the whole history - which
-- is what keeps this cheap enough for the session bar's five-second tick.
--
-- `missingQuantity` is what an entry with no quantity counts as: one for items and
-- currencies, where the field means "how many", and zero for gold, where it is an
-- amount of copper and inventing one would be wrong.
local function inWindow(entries, startedOn, endedOn, missingQuantity)
    local quantity = 0

    for i = #entries, 1, -1 do
        local entry = entries[i]
        local foundOn = entry.foundOn

        -- an undated entry cannot be placed in or out of the window, and everything
        -- below it is older still, so the walk ends here
        if (foundOn == nil or foundOn < startedOn) then break end

        if (endedOn == nil or foundOn <= endedOn) then
            quantity = quantity + (tonumber(entry.quantity) or missingQuantity)
        end
    end

    return quantity
end

-- Everything the session bar, the minimap tooltip and /mlh session show is derived here, so
-- the three of them can never disagree. Walking the history costs one pass over the loot
-- entries; the report already does the same on every redraw.
function MLH:getSessionStats(session)
    session = session or self:getLiveSession()

    local sessionStart = session.startedOn or time()
    local endedOn = session.endedOn
    -- a session that started this very second must not divide by zero
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
        local sessionQuantity = inWindow(lootData, sessionStart, endedOn, 1)

        if (sessionQuantity > 0) then
            local unitPrice = self:getItemPrice(item.itemId, lootData[#lootData].sellPrice or 0, item.itemLink)

            stats.itemTypes = stats.itemTypes + 1
            stats.quantity = stats.quantity + sessionQuantity
            stats.itemValue = stats.itemValue + unitPrice * sessionQuantity
        end
    end

    -- gold's "quantity" is an amount of copper, so a missing one is nothing, not one
    stats.rawGold = inWindow(self.db.char.foundGold, sessionStart, endedOn, 0)

    local foundCurrency = self.db.char.foundCurrency or {}

    for i = 1, #foundCurrency do
        local sessionQuantity = inWindow(foundCurrency[i].lootData, sessionStart, endedOn, 1)

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

-- Elapsed time reads as "2h 14m" once there is an hour on the clock and "07:32" before it.
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

-- ── session history ───────────────────────────────────────────────────────────

-- The session in progress: a window with no end, which is what marks it as live.
function MLH:getLiveSession()
    return { startedOn = self.db.char.thisSessionStart or time() }
end

-- Finished sessions, most recent first, which is the order they are offered in.
function MLH:getSessions()
    local stored = self.db.char.sessions or {}
    local sessions = {}

    for i = #stored, 1, -1 do
        sessions[#sessions+1] = stored[i]
    end

    return sessions
end

-- The window the report is filtering by: the live session unless a finished one has been
-- picked, and the live one again whenever the pick no longer exists - a session dropped by
-- retention, or one belonging to a character that is no longer the one logged in.
function MLH:getSelectedSession()
    local selected = self:getFilters().session

    if (not selected or selected == 0) then return self:getLiveSession() end

    local stored = self.db.char.sessions or {}

    for i = 1, #stored do
        if (stored[i].startedOn == selected) then return stored[i] end
    end

    return self:getLiveSession()
end

-- The last timestamp anything was looted, or nil for a session that recorded nothing. A
-- session ends when the player stops playing, and the client cannot say when that was after
-- the fact, so the final loot entry is the honest answer.
local function lastActivity(history, startedOn)
    local latest = nil

    local function scan(records, nested)
        for i = 1, #records do
            local entries = nested and records[i].lootData or { records[i] }

            for j = 1, #entries do
                local foundOn = entries[j].foundOn

                if (foundOn and foundOn >= startedOn and (latest == nil or foundOn > latest)) then
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

-- Closes the session in progress and files it, unless it recorded nothing at all - an empty
-- window says nothing and would only push a real session out of the list.
function MLH:closeSession(startedOn)
    local char = self.db.char

    startedOn = startedOn or char.thisSessionStart

    if (not startedOn) then return nil end

    local endedOn = lastActivity(char, startedOn)

    if (not endedOn) then return nil end

    char.sessions = char.sessions or {}
    char.sessions[#char.sessions+1] = { startedOn = startedOn, endedOn = endedOn }

    -- oldest first out
    while (#char.sessions > MAX_SESSIONS) do
        table.remove(char.sessions, 1)
    end

    return char.sessions[#char.sessions]
end

function MLH:resetSession()
    self:closeSession()

    self.db.char.thisSessionStart = time()

    -- the report was filtered by a session that has just become the previous one; the player
    -- asked for a new session, so that is what they are shown
    self:setFilter("session", 0)
end

-- What the session picker shows while it is closed.
function MLH:getSelectedSessionName()
    local session = self:getSelectedSession()

    if (session.endedOn == nil) then return L["S_LiveSession"] end

    return L["S_PastSession"](date("%d %b %H:%M", session.startedOn))
end

-- One line per session for the dropdown: when it started, how long it ran, and what it made.
function MLH:getSessionList()
    local list = {
        { value = 0, text = L["S_LiveSession"], session = self:getLiveSession() },
    }

    local sessions = self:getSessions()

    for i = 1, #sessions do
        local session = sessions[i]
        local stats = self:getSessionStats(session)

        list[#list+1] = {
            value = session.startedOn,
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
