--[[
My Loot History addon
Copyright (C) 2026 RustyDaemon (https://github.com/RustyDaemon)

See License file for details.
--]]

local MLH = LibStub("AceAddon-3.0"):GetAddon("MyLootHistory")
local L = LibStub("AceLocale-3.0"):GetLocale("MyLootHistory")

MLH.groupStatistics = {
    type = 'group',
    order = 32,
    name = L["C_Statistics"],
    args = {
        statisticsText = {
            type = 'description',
            fontSize = 'medium',
            -- read when the page is drawn, so looting never pays for it
            name = function() return MLH:getStatisticsText() end,
        }
    }
}
