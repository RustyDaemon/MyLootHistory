--[[
My Loot History addon
Copyright (C) 2026 RustyDaemon (https://github.com/RustyDaemon)

See License file for details.
--]]

local MLH = LibStub("AceAddon-3.0"):GetAddon("MyLootHistory")
local L = LibStub("AceLocale-3.0"):GetLocale("MyLootHistory")

local SECONDS_PER_HOUR = 3600

-- The shortest time a per-hour rate is measured over.
local MIN_RATE_SECONDS = 60

local MAX_SESSIONS = 40

-- Logging back in this soon after logging out (a /reload is one too) carries on with the same session.
local CONTINUE_SECONDS = 15 * 60

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
    char.sessionPauses = {}
    self:bumpRevision()

    -- A session started in a city or an inn starts out paused.
    self:updateSessionPause()
end

-- Time spent away or resting is left out of the session's clock, so gold and items per hour measure
-- the farming rather than the break. Each pause is kept as a span: a session is filed as ending at its
-- last pickup, and only the pauses before that pickup count against it.
local function openPause(pauses)
    local last = pauses and pauses[#pauses]

    if (last ~= nil and last.to == nil) then return last end

    return nil
end

local function pausedWithin(pauses, from, to)
    local paused = 0

    for i = 1, #(pauses or {}) do
        local pause = pauses[i]
        local startsAt = math.max(pause.from or from, from)
        local endsAt = math.min(pause.to or to, to)

        if (endsAt > startsAt) then paused = paused + endsAt - startsAt end
    end

    return paused
end

-- Retail hides the AFK flag behind a secret during a chat lockdown, which only comes with an
-- encounter: a player in one is not away, so a secret reads as not away.
local function isAway()
    local away = UnitIsAFK("player")

    if (_G.issecretvalue ~= nil and _G.issecretvalue(away)) then return false end

    return away == true
end

local function isResting()
    return IsResting() == true
end

function MLH:shouldPauseSession()
    if (not self.db.char.config.pauseWhenAway) then return false end

    return isAway() or isResting()
end

-- Ends the open pause, the last one, at `at`. A pause that ended in the second it began took no time;
-- it is dropped rather than kept.
local function closePause(pauses, at)
    local open = pauses[#pauses]

    if (open.from >= at) then
        pauses[#pauses] = nil
    else
        open.to = at
    end
end

-- Opens a pause when the player has just gone away or started resting, and closes it once neither
-- holds any more or the option has been turned off. Loot keeps being recorded either way.
function MLH:updateSessionPause()
    local char = self.db.char

    char.sessionPauses = char.sessionPauses or {}

    local pauses = char.sessionPauses
    local open = openPause(pauses)
    local now = time()

    -- The time logged out ends once the player is back in the world; a pause from then on is its own.
    if (open and open.offline) then
        closePause(pauses, now)
        open = nil
    end

    if (self:shouldPauseSession()) then
        if (not open) then pauses[#pauses+1] = { from = now } end
    elseif (open) then
        closePause(pauses, now)
    end
end

function MLH:isSessionPaused()
    return openPause(self.db.char.sessionPauses) ~= nil
end

-- Logging out, which a /reload does too, notes the time, so the next load can tell a reload or a quick
-- relog from a new day of play.
function MLH:noteLogout()
    self.db.char.lastSeenAt = time()
end

-- On every load: a reload, or a relog within CONTINUE_SECONDS, carries on with the session that was
-- running, and the time logged out becomes a pause of its own, marked offline: it stays out of the
-- clock even with pausing while away turned off. A pause still open at logout (resting in an inn, say)
-- ends where the time logged out begins, so no second goes uncounted or counts twice. The offline one
-- stays open until PLAYER_ENTERING_WORLD checks again, since whether the player is resting may not be
-- known yet. A longer break, no logout time or session start saved (from a version that did not save
-- them), or the option off files the session and starts a new one. Returns whether the session carried on.
-- A crash saves nothing, so the next load reads the logout before it: within CONTINUE_SECONDS that still
-- carries on, with everything since that logout paused. That keeps the rates right, as the loot of that
-- time was lost with the crash.
function MLH:continueOrBeginSession()
    local char = self.db.char
    local lastSeenAt = tonumber(char.lastSeenAt)
    local away = lastSeenAt and time() - lastSeenAt

    if (char.config.continueSession and char.thisSessionStart and away and away >= 0
        and away <= CONTINUE_SECONDS) then
        local pauses = char.sessionPauses or {}

        char.sessionPauses = pauses

        if (openPause(pauses)) then closePause(pauses, lastSeenAt) end

        pauses[#pauses+1] = { from = lastSeenAt, offline = true }

        return true
    end

    self:closeSession()
    self:beginSession()

    return false
end

-- The client says the player went away, came back, or walked into or out of a resting area. The flags
-- event fires for every group member too; only the player's own matters. A unit the client keeps
-- secret cannot be compared, so it is simply checked again, which does no harm.
function MLH:onSessionPauseEvent(event, unit)
    local secret = _G.issecretvalue ~= nil and _G.issecretvalue(unit)

    if (event == "PLAYER_FLAGS_CHANGED" and not secret and unit ~= "player") then return end

    self:updateSessionPause()

    if (self.updateHUD) then self:updateHUD() end
end

-- Whether loot picked up at foundOn came in during one of the pauses. Such loot stays in the history
-- and the totals, but not in the rates: crafting a stack in a city is not farming, and with the clock
-- stopped it would make the hour look like millions.
local function inPause(pauses, foundOn)
    if (not pauses or foundOn == nil) then return false end

    for i = #pauses, 1, -1 do
        local pause = pauses[i]

        if (foundOn >= pause.from and (pause.to == nil or foundOn <= pause.to)) then return true end
    end

    return false
end

-- The time logged out is never play: those pauses count whether pausing while away is on or not.
local function offlineOnly(pauses)
    local kept = {}

    for i = 1, #(pauses or {}) do
        if (pauses[i].offline) then kept[#kept+1] = pauses[i] end
    end

    return #kept > 0 and kept or nil
end

-- The pauses that count against a session. A filed one keeps what it was filed with; the live one's
-- all count while the option is on, and only the time logged out while it is off, so turning it off
-- counts every minute played again.
function MLH:getSessionPauses(session)
    if (session.endedOn == nil and not self.db.char.config.pauseWhenAway) then
        return offlineOnly(session.pauses)
    end

    return session.pauses
end

-- How many seconds of a session up to endsAt were paused: a filed session carries the sum.
function MLH:getSessionPausedSeconds(session, endsAt)
    if (session.endedOn ~= nil) then return tonumber(session.pausedSeconds) or 0 end

    return pausedWithin(self:getSessionPauses(session), session.startedOn or endsAt, endsAt)
end

-- The pauses the report's per-hour rates leave out: the selected session's while the range is a
-- session, and none for a calendar range, whose clock runs on regardless.
function MLH:getRangePauses()
    if (self:getFilters().range ~= MLH.RANGE_SESSION) then return nil end

    return self:getSessionPauses(self:getSelectedSession())
end

function MLH:isPausedLoot(pauses, foundOn)
    return inPause(pauses, foundOn)
end

-- The pauses a session filed now keeps: those of the session that is running, cut to its last
-- pickup. Pauses never belong to an older start, and while the option is off only the time logged out
-- is kept.
local function pausesToFile(self, startedOn, endedOn)
    local char = self.db.char
    local kept = {}

    if (startedOn ~= char.thisSessionStart) then return kept end

    local all = char.config.pauseWhenAway
    local pauses = char.sessionPauses or {}

    for i = 1, #pauses do
        local pause = pauses[i]
        local from = math.max(pause.from or startedOn, startedOn)
        local to = math.min(pause.to or endedOn, endedOn)

        if ((all or pause.offline) and to >= from) then
            kept[#kept+1] = { from = from, to = to, offline = pause.offline }
        end
    end

    return kept
end

-- Quest rewards are history, but not farming: they count toward the rates only when asked to.
function MLH:countsTowardRates(entry)
    if (entry.source == nil or entry.source.kind ~= "quest") then return true end

    return self.db.char.config.questRewardsInRates == true
end

-- History is chronological; scan backwards. Missing quantity counts as one, or zero for gold.
-- unitValue(entry), when given, prices one of the entry's units; the second return is their sum.
-- The last two returns are the same sums without what came in during a pause, for the rates.
local function inWindow(entries, startedOn, missingQuantity, session, pauses, unitValue)
    local quantity, value, rateQuantity, rateValue = 0, 0, 0, 0

    for i = #entries, 1, -1 do
        local entry = entries[i]
        local foundOn = entry.foundOn

        if (foundOn == nil or foundOn < startedOn) then break end

        if (MLH:isEntryInSession(entry, session) and MLH:countsTowardRates(entry)) then
            local entryQuantity = tonumber(entry.quantity) or missingQuantity
            local entryValue = unitValue and unitValue(entry) * entryQuantity or 0

            quantity = quantity + entryQuantity
            value = value + entryValue

            if (not inPause(pauses, foundOn)) then
                rateQuantity = rateQuantity + entryQuantity
                rateValue = rateValue + entryValue
            end
        end
    end

    return quantity, value, rateQuantity, rateValue
end

-- What a session holds: everything getSessionStats reports except the clock.
local function sessionTotals(self, session, sessionStart, pauses)
    local stats = {
        itemTypes = 0,
        quantity = 0,
        itemValue = 0,
        rawGold = 0,
        currencyQuantity = 0,
        currencyTypes = 0,
        rateQuantity = 0,
        rateValue = 0,
    }

    local foundItems = self.db.char.foundItems

    for i = 1, #foundItems do
        local item = foundItems[i]

        -- A hidden item is one the player said does not matter, so it does not count toward the rates.
        -- Each drop is priced by the link it dropped as, so an upgraded one counts at its own value.
        local lootData = self:isItemHidden(item.itemId) and {} or item.lootData
        local sessionQuantity, sessionValue, rateQuantity, rateValue = inWindow(lootData, sessionStart, 1,
            session, pauses, function(entry)
                return (self:getItemPrice(item.itemId, entry.sellPrice or 0, entry.itemLink or item.itemLink))
            end)

        stats.rateQuantity = stats.rateQuantity + rateQuantity
        stats.rateValue = stats.rateValue + rateValue

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

    local rawGold, _, rateGold = inWindow(self.db.char.foundGold, sessionStart, 0, session, pauses)

    stats.rawGold = rawGold
    stats.rateValue = stats.rateValue + rateGold

    local foundCurrency = self.db.char.foundCurrency or {}

    for i = 1, #foundCurrency do
        local sessionQuantity = inWindow(foundCurrency[i].lootData, sessionStart, 1, session, pauses)

        if (sessionQuantity > 0) then
            stats.currencyTypes = stats.currencyTypes + 1
            stats.currencyQuantity = stats.currencyQuantity + sessionQuantity
        end
    end

    stats.totalValue = stats.itemValue + stats.rawGold

    return stats
end

-- The report, the HUD and the broker each ask every second or two, and only the clock moves between
-- most of those asks: the totals are worked out again only once the history, the prices or the quest
-- setting has changed.
local totalsCache = { key = nil, bySession = {} }

local function totalsCacheKey(self)
    return tostring(self.historyRevision or 0)..":"..tostring(self.priceRevision or 0)..":"
        ..tostring(self.db.char.config.questRewardsInRates == true)
end

-- Closed pauses never change, so the count and the last one's ends tell one set of pauses from another.
local function pausesKey(pauses)
    if (not pauses or #pauses == 0) then return "-" end

    local last = pauses[#pauses]

    return #pauses..":"..tostring(last.from)..":"..tostring(last.to)
end

local function cachedTotals(self, session, sessionStart, pauses)
    local key = totalsCacheKey(self)

    if (totalsCache.key ~= key) then
        totalsCache.key = key
        totalsCache.bySession = {}
    end

    local sessionKey = tostring(session.id)..":"..sessionStart..":"..tostring(session.endedOn)..":"
        ..pausesKey(pauses)
    local totals = totalsCache.bySession[sessionKey]

    if (not totals) then
        totals = sessionTotals(self, session, sessionStart, pauses)
        totalsCache.bySession[sessionKey] = totals
    end

    return totals
end

function MLH:getSessionStats(session)
    session = session or self:getLiveSession()

    local sessionStart = session.startedOn or time()
    local endedOn = session.endedOn
    local endsAt = endedOn or time()
    local pauses = self:getSessionPauses(session)
    local pausedSeconds = self:getSessionPausedSeconds(session, endsAt)
    local duration = math.max(endsAt - sessionStart - pausedSeconds, 1)
    -- A session a few seconds old would turn its first pickup into a wild rate.
    local rateDuration = math.max(duration, MIN_RATE_SECONDS)
    local totals = cachedTotals(self, session, sessionStart, pauses)

    local stats = {
        sessionStart = sessionStart,
        endedOn = endedOn,
        isLive = endedOn == nil,
        isPaused = endedOn == nil and openPause(pauses) ~= nil,
        pausedSeconds = pausedSeconds,
        duration = duration,
        rateDuration = rateDuration,
        goldPerHour = math.floor(totals.rateValue / rateDuration * SECONDS_PER_HOUR),
        itemsPerHour = totals.rateQuantity / rateDuration * SECONDS_PER_HOUR,
    }

    for key, value in pairs(totals) do stats[key] = value end

    return stats
end

-- The time card's caption while pauses shape the time it shows: that the clock is paused now, or how
-- much paused time it leaves out. nil when nothing was paused, so the card keeps its own caption.
function MLH:getPausedCaption(stats)
    if (stats.isPaused) then return L["G_PausedNow"] end

    if ((stats.pausedSeconds or 0) > 0) then return L["G_PausedFor"](self:formatDuration(stats.pausedSeconds)) end

    return nil
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
    local char = self.db.char

    return { startedOn = char.thisSessionStart or time(), id = char.currentSessionID, pauses = char.sessionPauses }
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

-- A session ends at its last pickup rather than at logout: the time after it was not farming.
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
    -- A pause still open at logout ran on past the last pickup; only what came before it counts.
    local pauses = pausesToFile(self, startedOn, endedOn)

    session.pausedSeconds = pausedWithin(pauses, startedOn, endedOn)
    if (#pauses > 0) then session.pauses = pauses end
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
