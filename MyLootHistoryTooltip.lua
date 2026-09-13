--[[
My Loot History addon
Copyright (C) 2026 RustyDaemon (https://github.com/RustyDaemon)

See License file for details.
--]]

local MLH = LibStub("AceAddon-3.0"):GetAddon("MyLootHistory")
local L = LibStub("AceLocale-3.0"):GetLocale("MyLootHistory")

local isHooked = false

local suppressed = false

local summaryCache = {}

local function getSummary(itemID)
    local record = MLH:getItemRecord(itemID)

    if (not record) then return nil end

    local lootData = record.lootData
    local entries = #lootData
    local cached = summaryCache[itemID]

    if (cached and cached.entries == entries) then return cached end

    local quantity, zones, _, lastFound = MLH:aggregateLoot(lootData, nil)

    local summary = {
        entries = entries,
        quantity = quantity,
        lastFound = lastFound,
        topZone = zones[1] and zones[1].name or nil,
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

function MLH:setTooltipSuppressed(value)
    suppressed = value and true or false
end
