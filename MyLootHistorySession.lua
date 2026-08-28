--[[
My Loot History addon
Copyright (C) 2026 RustyDaemon (https://github.com/RustyDaemon)

See License file for details.
--]]

local MLH = LibStub("AceAddon-3.0"):GetAddon("MyLootHistory")
local L = LibStub("AceLocale-3.0"):GetLocale("MyLootHistory")

local SECONDS_PER_HOUR = 3600

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
        local sessionQuantity = 0

        for j = #lootData, 1, -1 do
            local entry = lootData[j]

            -- the entries are appended in time order, so the walk can stop at the first
            -- one older than the session instead of reading the whole history
            if (entry.foundOn < sessionStart) then break end

            sessionQuantity = sessionQuantity + (tonumber(entry.quantity) or 1)
        end

        if (sessionQuantity > 0) then
            local unitPrice = self:getItemPrice(item.itemId, lootData[#lootData].sellPrice or 0, item.itemLink)

            stats.itemTypes = stats.itemTypes + 1
            stats.quantity = stats.quantity + sessionQuantity
            stats.itemValue = stats.itemValue + unitPrice * sessionQuantity
        end
    end

    local foundGold = self.db.char.foundGold

    for i = #foundGold, 1, -1 do
        if (foundGold[i].foundOn < sessionStart) then break end

        stats.rawGold = stats.rawGold + (foundGold[i].quantity or 0)
    end

    local foundCurrency = self.db.char.foundCurrency or {}

    for i = 1, #foundCurrency do
        local lootData = foundCurrency[i].lootData
        local sessionQuantity = 0

        for j = #lootData, 1, -1 do
            if (lootData[j].foundOn < sessionStart) then break end

            sessionQuantity = sessionQuantity + (tonumber(lootData[j].quantity) or 1)
        end

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
