--[[
My Loot History addon
Copyright (C) 2026 RustyDaemon (https://github.com/RustyDaemon)

See License file for details.
--]]

local MLH = LibStub("AceAddon-3.0"):GetAddon("MyLootHistory")
local L = LibStub("AceLocale-3.0"):GetLocale("MyLootHistory")

local SECONDS_PER_HOUR = 3600

-- What a single history contributed since the session began.
--
-- Entries are appended in time order, so the walk runs backwards and stops at the
-- first one older than the session rather than reading the whole history - which
-- is what keeps this cheap enough for the session bar's five-second tick.
--
-- `missingQuantity` is what an entry with no quantity counts as: one for items and
-- currencies, where the field means "how many", and zero for gold, where it is an
-- amount of copper and inventing one would be wrong.
local function sinceSessionStart(entries, sessionStart, missingQuantity)
    local quantity = 0

    for i = #entries, 1, -1 do
        local entry = entries[i]

        -- an undated entry cannot be placed in or out of the session, and everything
        -- below it is older still, so the walk ends here
        if (entry.foundOn == nil or entry.foundOn < sessionStart) then break end

        quantity = quantity + (tonumber(entry.quantity) or missingQuantity)
    end

    return quantity
end

-- Everything the session bar, the minimap tooltip and /mlh session show is derived here, so
-- the three of them can never disagree. Walking the history costs one pass over the loot
-- entries; the report already does the same on every redraw.
function MLH:getSessionStats()
    local sessionStart = self.db.char.thisSessionStart or time()
    -- a session that started this very second must not divide by zero
    local duration = math.max(time() - sessionStart, 1)

    local stats = {
        sessionStart = sessionStart,
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
        local sessionQuantity = sinceSessionStart(lootData, sessionStart, 1)

        if (sessionQuantity > 0) then
            local unitPrice = self:getItemPrice(item.itemId, lootData[#lootData].sellPrice or 0, item.itemLink)

            stats.itemTypes = stats.itemTypes + 1
            stats.quantity = stats.quantity + sessionQuantity
            stats.itemValue = stats.itemValue + unitPrice * sessionQuantity
        end
    end

    -- gold's "quantity" is an amount of copper, so a missing one is nothing, not one
    stats.rawGold = sinceSessionStart(self.db.char.foundGold, sessionStart, 0)

    local foundCurrency = self.db.char.foundCurrency or {}

    for i = 1, #foundCurrency do
        local sessionQuantity = sinceSessionStart(foundCurrency[i].lootData, sessionStart, 1)

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

function MLH:resetSession()
    self.db.char.thisSessionStart = time()
end
