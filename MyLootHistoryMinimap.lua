--[[
My Loot History addon
Copyright (C) 2026 RustyDaemon (https://github.com/RustyDaemon)

See License file for details.
--]]

local MLH = LibStub("AceAddon-3.0"):GetAddon("MyLootHistory")

local MLH_LDB = LibStub("LibDataBroker-1.1")
local MLH_MMIcon = LibStub("LibDBIcon-1.0")
local L = LibStub("AceLocale-3.0"):GetLocale("MyLootHistory")

local BROKER_INTERVAL = 2 -- seconds; LibDataBroker skips the callbacks when the text is unchanged

local minimapIcon = MLH_LDB:NewDataObject("MyLootHistory", {
    type = "data source",
    label = L["MM_IconTitle"],
    text = L["MM_IconTitle"],
    icon = "Interface\\Icons\\inv_misc_map09",
    OnClick = function(_, button)
        if (button == "LeftButton") then
            MLH:gui()
        elseif (button == "RightButton") then
            MLH:toggleSettings()
        end
    end,
    OnTooltipShow = function(tooltip)
        tooltip:AddLine(L["MM_Title"])
        tooltip:AddLine(L["MM_Separator"])
        tooltip:AddLine("|cFFFFD100"..MLH:getSessionLine().."|r")
        tooltip:AddLine(L["MM_Separator"])
        tooltip:AddLine(L["MM_LeftClickForReport"])
        tooltip:AddLine(L["MM_RightClickForSettings"])
    end,
})

-- Broker displays (Titan Panel, ElvUI, ChocolateBar...) show this text; the minimap button does not.
function MLH:updateBrokerText()
    local stats = self:getSessionStats()

    minimapIcon.text = self:formatGoldCompact(stats.goldPerHour)..self.UI.GOLD_ICON..L["H_GoldPerHour"]
end

function MLH:initMinimap()
    C_Timer.NewTicker(BROKER_INTERVAL, function() MLH:updateBrokerText() end)

    MLH_MMIcon:Register("MyLootHistory", minimapIcon, self.db.char.minimapData)

    if (self.db.char.minimapData.hide) then
        MLH_MMIcon:Hide("MyLootHistory")
    else
        MLH_MMIcon:Show("MyLootHistory")
    end

    AddonCompartmentFrame:RegisterAddon({
        text = "MyLootHistory",
        icon = "Interface\\Icons\\inv_misc_map09",
        notCheckable = true,
        func = function()
            MLH:gui()
        end,
    })
end
