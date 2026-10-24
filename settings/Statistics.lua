--[[
My Loot History addon
Copyright (C) 2026 RustyDaemon (https://github.com/RustyDaemon)

See License file for details.
--]]

local MLH = LibStub("AceAddon-3.0"):GetAddon("MyLootHistory")
local L = LibStub("AceLocale-3.0"):GetLocale("MyLootHistory")

function MLH:getStatisticsText()
    local itemsFound = self.db.char.foundItems
    local itemTypesAmount = #itemsFound
    local totalAmount = 0
    local seenZones, zonesAmount = {}, 0

    for i = 1, itemTypesAmount do
        local lootData = itemsFound[i].lootData

        for j = 1, #lootData do
            local entry = lootData[j]

            totalAmount = totalAmount + (tonumber(entry.quantity) or 1)

            -- Loot with no zone is counted as one zone of its own.
            local zoneID = entry.zoneID or false

            if (not seenZones[zoneID]) then
                seenZones[zoneID] = true
                zonesAmount = zonesAmount + 1
            end
        end
    end

    local currencyTypesAmount = #(self.db.char.foundCurrency or {})

    return L["M_TotalDifferentItemsGathered"]..itemTypesAmount
        ..'\n'..L["M_TotalQuantityGathered"]..totalAmount..'\n'..L["M_TotalZonesLooted"]..zonesAmount
        ..'\n'..L["M_TotalCurrenciesGathered"]..currencyTypesAmount
    ..'\n\n'..self:getSessionLine()
end

MLH.groupStatistics = {
    type = 'group',
    order = 32,
    name = L["C_Statistics"],
    args = {
        statisticsText = {
            type = 'description',
            fontSize = 'medium',
            name = function() return MLH:getStatisticsText() end,
        }
    }
}
