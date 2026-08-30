--[[
My Loot History addon
Copyright (C) 2026 RustyDaemon (https://github.com/RustyDaemon)

See License file for details.
--]]

local MLH = LibStub("AceAddon-3.0"):GetAddon("MyLootHistory")
local L = LibStub("AceLocale-3.0"):GetLocale("MyLootHistory")

MLH.groupFaq = {
    type = 'group',
    order = 43,
    name = L["C_FAQ"],
    args = {
        headerWhat = {
            type = 'header',
            name = L["F_WhatFor"],
            order = 1,
        },
        textWhat = {
            type = 'description',
            order = 2,
            name = L["F_WhatFor_Desc"]
        },
        headerSorting = {
            type = 'header',
            order = 10,
            name = L["F_SortingFiltering"],
        },
        textSorting = {
            type = 'description',
            order = 11,
            name = L["F_SortingFiltering_Desc"]
        },
        headerSession = {
            type = 'header',
            order = 14,
            name = L["F_Session"],
        },
        textSession = {
            type = 'description',
            order = 15,
            name = L["F_Session_Desc"]
        },
        headerLinking = {
            type = 'header',
            order = 20,
            name = L["F_CanILinkToChat"],
        },
        textLinking = {
            type = 'description',
            order = 21,
            name = L["F_CanILinkToChat_Desc"]
        },
        headerRestrictions = {
            type = 'header',
            order = 40,
            name = L["F_Restrinctions"],
        },
        textRestrictions = {
            type = 'description',
            order = 41,
            name = L["F_Restrinctions_Desc"]
        },
        headerWebsite = {
            type = 'header',
            order = 50,
            name = L["F_Website"],
        },
        textWebsite = {
            type = 'description',
            order = 51,
            name = L["F_Website_Desc"]
        },
        -- an input rather than a description: description text cannot be selected, and the
        -- client opens no links, so an editbox is the only way to get the address out
        inputWebsite = {
            type = 'input',
            order = 52,
            width = 'double',
            name = L["F_WebsiteLabel"],
            get = function () return MLH.website end,
            set = function () end,
        },
    }
}
