--[[
My Loot History addon
Copyright (C) 2026 RustyDaemon (https://github.com/RustyDaemon)

See License file for details.
--]]

local MLH = LibStub("AceAddon-3.0"):GetAddon("MyLootHistory")
local L = LibStub("AceLocale-3.0"):GetLocale("MyLootHistory")

local isHooked = false

-- The report window builds a far more detailed tooltip of its own, so the one-line summary
-- is suppressed while it is doing that rather than shown twice.
local suppressed = false

-- itemID -> summary, thrown away for an item as soon as its record grows. A tooltip runs on
-- every mouseover in the UI, so it must not walk a long history each time.
local summaryCache = {}

local function getSummary(itemID)
    local record = MLH:getItemRecord(itemID)

    if (not record) then return nil end

    local lootData = record.lootData
    local entries = #lootData
    local cached = summaryCache[itemID]

    if (cached and cached.entries == entries) then return cached end

    local quantity = 0
    local zoneCounts = {}
    local topZone, topZoneQuantity = nil, 0

    for i = 1, entries do
        local entry = lootData[i]
        local entryQuantity = tonumber(entry.quantity) or 1
        local zoneName = MLH:getZoneName(entry.zoneID)

        quantity = quantity + entryQuantity

        if (zoneName) then
            local zoneQuantity = (zoneCounts[zoneName] or 0) + entryQuantity
            zoneCounts[zoneName] = zoneQuantity

            if (zoneQuantity > topZoneQuantity) then
                topZone, topZoneQuantity = zoneName, zoneQuantity
            end
        end
    end

    local summary = {
        entries = entries,
        quantity = quantity,
        lastFound = entries > 0 and lootData[entries].foundOn or nil,
        topZone = topZone,
    }

    summaryCache[itemID] = summary

    return summary
end

local function onItemTooltip(tooltip, data)
    if (suppressed) then return end
    if (tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip) then return end
    if (not MLH.db or not MLH.db.char.config.gameTooltipLine) then return end

    local itemID = data and data.id

    if (not itemID) then return end

    local summary = getSummary(itemID)

    if (not summary or summary.quantity == 0) then return end

    tooltip:AddLine(L["T_LootedSummary"](summary.quantity, date("%d %b", summary.lastFound)), 1, 0.82, 0)

    if (summary.topZone and MLH.db.char.config.showAdditionalTooltipData) then
        tooltip:AddLine(L["T_MostlyIn"](summary.topZone), 0.8, 0.8, 0.8)
    end
end

function MLH:initTooltip()
    if (isHooked) then return end
    if (not TooltipDataProcessor or not TooltipDataProcessor.AddTooltipPostCall) then return end

    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, onItemTooltip)
    isHooked = true
end

-- Used by the report window, which draws its own tooltip through GameTooltip:SetHyperlink.
function MLH:setTooltipSuppressed(value)
    suppressed = value and true or false
end
