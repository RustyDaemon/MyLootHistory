--[[
My Loot History addon
Copyright (C) 2026 RustyDaemon (https://github.com/RustyDaemon)

See License file for details.
--]]

-- The addon's page in the game's own options, drawn like the addon's windows: what the addon is, the
-- live session, the way into the settings and the report, and the slash commands.

local MLH = LibStub("AceAddon-3.0"):GetAddon("MyLootHistory")
local L = LibStub("AceLocale-3.0"):GetLocale("MyLootHistory")
local UI = MLH.UI

local PAD = 14
local GAP = 8
local CARD_HEIGHT = 86
local COMMAND_HEIGHT = 20
local COMMAND_WIDTH = 110

local GOLD_ICON = UI.GOLD_ICON

local COMMANDS = {
    { "/mlh", "C_CmdReport" },
    { "/mlh config", "C_CmdConfig" },
    { "/mlh hud", "C_CmdHud" },
    { "/mlh share", "C_CmdShare" },
    { "/mlh help", "C_CmdHelp" },
}

local function addonVersion()
    local getMetadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or _G.GetAddOnMetadata
    local version = getMetadata and getMetadata("MyLootHistory", "Version")

    return version and ("v"..version) or nil
end

local function closeGameOptions()
    if (SettingsPanel) then HideUIPanel(SettingsPanel) end
end

local function buildPage()
    local panel = CreateFrame("Frame")
    panel:Hide()

    local sheet = CreateFrame("Frame", nil, panel)
    sheet:SetPoint("TOPLEFT", 2, -2)
    sheet:SetPoint("BOTTOMRIGHT", -2, 2)

    UI:chrome(sheet, { title = L["MM_IconTitle"], subtitle = addonVersion() })

    local tagline = UI:text(sheet, 14, "accent")
    tagline:SetPoint("TOPLEFT", sheet.titleBar, "BOTTOMLEFT", PAD - 1, -18)
    tagline:SetText(L["C_GameOptionsTagline"])

    local blurb = UI:text(sheet, 12, "textDim")
    blurb:SetPoint("TOPLEFT", tagline, "BOTTOMLEFT", 0, -8)
    blurb:SetPoint("RIGHT", sheet, "RIGHT", -PAD, 0)
    blurb:SetJustifyH("LEFT")
    blurb:SetSpacing(3)
    blurb:SetText(L["C_GameOptionsBlurb"])

    local sessionHeading = UI:sectionHeading(sheet, L["C_GameOptionsSession"])
    sessionHeading:SetPoint("TOPLEFT", blurb, "BOTTOMLEFT", -2, -20)
    sessionHeading:SetPoint("RIGHT", sheet, "RIGHT", -PAD, 0)

    local cards = {
        UI:statCard(sheet, L["G_Session"], "accent"),
        UI:statCard(sheet, L["G_ItemsPerHour"], "borderLight"),
        UI:statCard(sheet, L["G_GoldPerHour"], "money"),
    }

    local openSettings = UI:button(sheet, L["C_OpenSettings"], 140, 26, function()
        closeGameOptions()
        MLH:openSettings()
    end)
    openSettings:SetAccent(true)
    openSettings:SetWidth(math.max(openSettings.label:GetStringWidth() + 32, 140))
    openSettings:SetPoint("TOPLEFT", cards[1], "BOTTOMLEFT", 0, -16)

    local openReport = UI:button(sheet, L["C_OpenReport"], 140, 26, function()
        closeGameOptions()

        -- gui() toggles, so a report already open is left open.
        local report = _G.MLHReportFrame

        if (not (report and report:IsShown())) then MLH:gui() end
    end)
    openReport:SetWidth(math.max(openReport.label:GetStringWidth() + 32, 140))
    openReport:SetPoint("LEFT", openSettings, "RIGHT", GAP, 0)

    local commandsHeading = UI:sectionHeading(sheet, L["C_GameOptionsCommands"])
    commandsHeading:SetPoint("TOPLEFT", openSettings, "BOTTOMLEFT", -2, -24)
    commandsHeading:SetPoint("RIGHT", sheet, "RIGHT", -PAD, 0)

    for i, command in ipairs(COMMANDS) do
        local y = -6 - (i - 1) * COMMAND_HEIGHT

        local name = UI:text(sheet, 12, "accent")
        name:SetPoint("TOPLEFT", commandsHeading, "BOTTOMLEFT", 2, y)
        name:SetWidth(COMMAND_WIDTH)
        name:SetJustifyH("LEFT")
        name:SetText(command[1])

        local what = UI:text(sheet, 12, "textDim")
        what:SetPoint("TOPLEFT", commandsHeading, "BOTTOMLEFT", 2 + COMMAND_WIDTH, y)
        what:SetText(L[command[2]])
    end

    local website = UI:text(sheet, 11, "textFaint")
    website:SetPoint("BOTTOMLEFT", PAD, 12)
    website:SetText(MLH.website)

    -- The cards share the width between them, so they are placed again whenever it changes.
    local function layoutCards()
        local width = math.max((sheet:GetWidth() - PAD * 2 - GAP * (#cards - 1)) / #cards, 1)

        for i, card in ipairs(cards) do
            card:ClearAllPoints()
            card:SetPoint("TOPLEFT", sessionHeading, "BOTTOMLEFT", 2 + (i - 1) * (width + GAP), -8)
            card:SetSize(width, CARD_HEIGHT)
        end
    end

    local function updateCards()
        local stats = MLH:getSessionStats()

        cards[1]:Set(MLH:formatDuration(stats.duration), L["S_LiveSession"], "text")
        cards[2]:Set(string.format("%.0f", stats.itemsPerHour), L["G_ItemsTotal"](stats.quantity), "text")
        cards[3]:Set(MLH:formatGoldCompact(stats.goldPerHour)..GOLD_ICON,
            L["G_ValueSoFar"](MLH:formatGoldCompact(stats.totalValue)), "money")
    end

    local ticker = nil

    sheet:SetScript("OnSizeChanged", layoutCards)

    panel:SetScript("OnShow", function()
        layoutCards()
        updateCards()

        ticker = ticker or C_Timer.NewTicker(1, updateCards)
    end)

    panel:SetScript("OnHide", function()
        if (ticker) then ticker:Cancel() end

        ticker = nil
    end)

    panel.cards = cards
    panel.openSettings = openSettings
    panel.openReport = openReport

    return panel
end

function MLH:addToGameOptions()
    if (not Settings or not Settings.RegisterCanvasLayoutCategory) then return end

    local panel = buildPage()

    Settings.RegisterAddOnCategory(Settings.RegisterCanvasLayoutCategory(panel, L["MM_IconTitle"]))
end
