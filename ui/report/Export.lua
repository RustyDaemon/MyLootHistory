--[[
My Loot History addon
Copyright (C) 2026 RustyDaemon (https://github.com/RustyDaemon)

See License file for details.
--]]

-- The window the report's CSV is copied out of.

local MLH = LibStub("AceAddon-3.0"):GetAddon("MyLootHistory")
local L = LibStub("AceLocale-3.0"):GetLocale("MyLootHistory")
local UI = MLH.UI
local View = MLH.reportView

local PAD = View.PAD

local exportWindow = nil

function View.showExportWindow()
    -- Avoid and/or here: both the CSV and hint return values are needed.
    local csv, count

    if (View.isCurrencyView()) then
        csv, count = MLH:buildCurrencyCsv(View.report)
    else
        csv, count = MLH:buildCsv(View.report)
    end

    if (not exportWindow) then
        local frame = CreateFrame("Frame", "MLHExportFrame", UIParent)

        frame:SetFrameStrata("FULLSCREEN_DIALOG")
        frame:SetSize(620, 440)
        frame:SetPoint("CENTER")
        frame:SetMovable(true)
        frame:EnableMouse(true)
        frame:SetClampedToScreen(true)

        UI:addShadow(frame, 6, 0.5)

        local bg = frame:CreateTexture(nil, "BACKGROUND", nil, -7)
        bg:SetAllPoints()
        bg:SetColorTexture(UI:rgb("window", 0.98))

        UI:addBorder(frame, UI:rgb("borderLight"))

        local titleBar = CreateFrame("Frame", nil, frame)
        titleBar:SetPoint("TOPLEFT", 1, -1)
        titleBar:SetPoint("TOPRIGHT", -1, -1)
        titleBar:SetHeight(36)
        titleBar:EnableMouse(true)
        titleBar:RegisterForDrag("LeftButton")
        titleBar:SetScript("OnDragStart", function() frame:StartMoving() end)
        titleBar:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)

        local titleFill = UI:gradient(titleBar, "BACKGROUND", "VERTICAL",
            0.055, 0.059, 0.070, 1, 0.114, 0.106, 0.075, 1)
        titleFill:SetAllPoints()

        local title = UI:text(titleBar, 13, "text")
        title:SetPoint("LEFT", PAD, 0)
        title:SetText(L["R_ExportTitle"])

        local close = UI:iconButton(titleBar, 26, "Interface\\Buttons\\UI-StopButton",
            function() frame:Hide() end)
        close:SetPoint("RIGHT", -5, 0)

        local hint = UI:text(frame, 11, "textFaint")
        hint:SetPoint("BOTTOMLEFT", PAD, 10)

        local box = UI:panel(frame, "panel", true)
        box:SetPoint("TOPLEFT", titleBar, "BOTTOMLEFT", PAD - 1, -PAD)
        box:SetPoint("BOTTOMRIGHT", -PAD + 1, 30)

        local scroll = CreateFrame("ScrollFrame", "MLHExportScroll", box, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 8, -8)
        scroll:SetPoint("BOTTOMRIGHT", -26, 8)

        local editBox = CreateFrame("EditBox", nil, scroll)
        editBox:SetMultiLine(true)
        editBox:SetAutoFocus(false)
        editBox:SetFont(UI.fontNumber, 12, "")
        editBox:SetTextColor(UI:rgb("textDim"))
        editBox:SetWidth(540)
        editBox:SetScript("OnEscapePressed", function() frame:Hide() end)
        editBox:SetScript("OnTextChanged", function(self, userInput)
            if (userInput) then self:SetText(self.csv or "") end
        end)

        scroll:SetScrollChild(editBox)

        frame.editBox = editBox
        frame.hint = hint

        if (not tContains(UISpecialFrames, "MLHExportFrame")) then
            tinsert(UISpecialFrames, "MLHExportFrame")
        end

        exportWindow = frame
    end

    exportWindow.editBox.csv = csv
    exportWindow.editBox:SetText(csv)
    exportWindow.hint:SetText(L["R_ExportHint"](count))
    exportWindow:Show()
    exportWindow.editBox:SetFocus()
    exportWindow.editBox:HighlightText()
end
