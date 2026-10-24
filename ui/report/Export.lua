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
local SCROLLBAR_WIDTH = 8
local WHEEL_STEP = 48

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
        local frame = UI:window({
            name = "MLHExportFrame",
            strata = "FULLSCREEN_DIALOG",
            compact = true,
            title = L["R_ExportTitle"],
        })

        frame:SetSize(620, 440)
        frame:SetPoint("CENTER")

        local hint = UI:text(frame, 11, "textFaint")
        hint:SetPoint("BOTTOMLEFT", PAD, 10)

        local box = UI:panel(frame, "panel", true)
        box:SetPoint("TOPLEFT", frame.titleBar, "BOTTOMLEFT", PAD - 1, -PAD)
        box:SetPoint("BOTTOMRIGHT", -PAD + 1, 30)

        local scroll = CreateFrame("ScrollFrame", nil, box)
        scroll:SetPoint("TOPLEFT", 8, -8)
        scroll:SetPoint("BOTTOMRIGHT", -(SCROLLBAR_WIDTH + 18), 8)
        scroll:EnableMouseWheel(true)

        local scrollbar = UI:scrollbar(box, function(offset)
            frame.offset = offset
            scroll:SetVerticalScroll(offset)
        end)
        scrollbar:SetPoint("TOPRIGHT", -6, -8)
        scrollbar:SetPoint("BOTTOMRIGHT", -6, 8)

        -- The edit box grows with its text, and the scroll frame says so when it does.
        frame.UpdateScroll = function(_, offset)
            local visible = scroll:GetHeight()

            frame.offset = scrollbar:Update(visible, visible + scroll:GetVerticalScrollRange(), offset)
            scroll:SetVerticalScroll(frame.offset)
        end

        scroll:SetScript("OnScrollRangeChanged", function() frame:UpdateScroll() end)
        scroll:SetScript("OnMouseWheel", function(_, delta)
            frame:UpdateScroll((frame.offset or 0) - delta * WHEEL_STEP)
        end)

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

        exportWindow = frame
    end

    exportWindow.editBox.csv = csv
    exportWindow.editBox:SetText(csv)
    exportWindow.hint:SetText(L["R_ExportHint"](count))
    exportWindow:Show()
    exportWindow:UpdateScroll(0)
    exportWindow.editBox:SetFocus()
    exportWindow.editBox:HighlightText()
end
