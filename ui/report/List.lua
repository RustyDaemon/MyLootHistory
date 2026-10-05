--[[
My Loot History addon
Copyright (C) 2026 RustyDaemon (https://github.com/RustyDaemon)

See License file for details.
--]]

-- The sortable column header, the scrolling list of rows under it and the footer totals.

local MLH = LibStub("AceAddon-3.0"):GetAddon("MyLootHistory")
local L = LibStub("AceLocale-3.0"):GetLocale("MyLootHistory")
local UI = MLH.UI
local View = MLH.reportView

local PAD = View.PAD
local HEADER_HEIGHT = View.HEADER_HEIGHT
local ROW_HEIGHT = View.ROW_HEIGHT

-- Use cropped client textures: FRIZQT__.TTF lacks arrow glyphs.
local SORT_UP = " |TInterface\\ChatFrame\\UI-ChatIcon-ScrollUp-Up:16:16:0:-2:32:32:8:24:8:24|t"
local SORT_DOWN = " |TInterface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up:16:16:0:-2:32:32:8:24:8:24|t"

local rows = {}

local function setSort(key)
    local currency = View.isCurrencyView()
    local currentKey, descending = View.sortState()

    if (currentKey == key) then
        MLH:setFilter(currency and "currencySortDescending" or "sortDescending", not descending)
        return
    end

    MLH:setFilter(currency and "currencySort" or "sortKey", key)
    MLH:setFilter(currency and "currencySortDescending" or "sortDescending",
        key ~= "name" and key ~= "zone" and key ~= "character")
end

function View.rebuildList()
    View.displayList = {}

    if (View.isCurrencyView()) then
        for i = 1, #View.report.rows do
            View.displayList[#View.displayList+1] = { kind = "budget", currency = View.report.rows[i] }
        end

        return
    end

    for i = 1, #View.report.items do
        View.displayList[#View.displayList+1] = { kind = "item", item = View.report.items[i] }
    end

    if (View.report.gold > 0) then
        View.displayList[#View.displayList+1] = { kind = "heading", text = L["R_Money"] }
        View.displayList[#View.displayList+1] = { kind = "gold", gold = View.report.gold }
    end
end

function View.layoutRows()
    if (not View.window) then return end

    local list = View.window.list
    local viewportHeight = math.max(list:GetHeight(), 1)
    local needed = math.ceil(viewportHeight / ROW_HEIGHT) + 1
    local layout = View.columnLayout()

    for i = #rows + 1, needed do
        local row = View.createRow(list)

        row:SetPoint("LEFT", 0, 0)
        row:SetPoint("RIGHT", 0, 0)
        rows[i] = row
    end

    local firstIndex = math.floor(View.scrollOffset / ROW_HEIGHT)
    local pixelOffset = View.scrollOffset - firstIndex * ROW_HEIGHT

    for i = 1, #rows do
        local row = rows[i]
        local entryIndex = firstIndex + i

        if (entryIndex <= #View.displayList and i <= needed) then
            row:ClearAllPoints()
            row:SetPoint("LEFT", 0, 0)
            row:SetPoint("RIGHT", 0, 0)
            row:SetPoint("TOP", list, "TOP", 0, -((i - 1) * ROW_HEIGHT - pixelOffset))
            row:Show()

            View.fillRow(row, View.displayList[entryIndex], entryIndex, layout)
        else
            row:Hide()
            row.entry = nil
        end
    end
end

function View.updateScroll(offset)
    if (not View.window) then return end

    local viewportHeight = View.window.list:GetHeight()
    local contentHeight = #View.displayList * ROW_HEIGHT

    View.scrollOffset = View.window.scrollbar:Update(viewportHeight, math.max(contentHeight, 1),
        offset or View.scrollOffset)

    View.layoutRows()
end

function View.createHeaderColumn(parent, key, text, justify)
    local button = CreateFrame("Button", nil, parent)

    button:SetHeight(HEADER_HEIGHT)

    local label = UI:text(button, 11, "textDim")
    label:SetAllPoints()
    label:SetJustifyH(justify or "RIGHT")
    label:SetWordWrap(false)

    local underline = button:CreateTexture(nil, "ARTWORK")
    underline:SetPoint("BOTTOMLEFT", 0, 2)
    underline:SetPoint("BOTTOMRIGHT", 0, 2)
    underline:SetHeight(1)
    underline:SetColorTexture(UI:rgb("accent"))
    underline:Hide()

    button.key = key
    button.baseText = text
    button.label = label
    button.underline = underline

    button:HookScript("OnEnter", function(self)
        if (View.sortState() ~= self.key) then self.label:SetTextColor(UI:rgb("text")) end

        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(L["R_SortBy"](self.baseText), 1, 1, 1)

        if (self.hint) then GameTooltip:AddLine(self.hint, UI:rgb("textDim")) end

        GameTooltip:Show()
    end)

    button:HookScript("OnLeave", function(self)
        if (View.sortState() ~= self.key) then self.label:SetTextColor(UI:rgb("textDim")) end

        GameTooltip:Hide()
    end)

    button:SetScript("OnClick", function(self)
        setSort(self.key)

        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        View.refreshReport()
    end)

    return button
end

function View.refreshHeader()
    local sortKey, descending = View.sortState()
    local config = MLH.db.char.config
    local layout = View.columnLayout()
    local header = View.window.header

    local function place(button, right, width, justify)
        if (not right) then
            button:Hide()
            return
        end

        button:Show()
        button:ClearAllPoints()
        button:SetPoint("RIGHT", header, "RIGHT", right, 0)
        button:SetWidth(width)
        button.label:SetJustifyH(justify or "RIGHT")
    end

    header.name:ClearAllPoints()
    header.name:SetPoint("LEFT", header, "LEFT", layout.nameLeft, 0)
    header.name:SetPoint("RIGHT", header, "RIGHT", layout.nameRight, 0)

    place(header.quantity, layout.quantityRight, layout.quantityWidth, "RIGHT")
    place(header.value, layout.valueRight, layout.valueWidth, "RIGHT")
    place(header.market, layout.marketRight, layout.marketWidth, "RIGHT")
    place(header.character, layout.characterRight, layout.characterWidth, "LEFT")
    place(header.source, layout.sourceRight, layout.sourceWidth, "LEFT")
    place(header.zone, layout.zoneRight, layout.zoneWidth, "LEFT")
    place(header.lastLooted, layout.lastLootedRight, layout.lastLootedWidth, "LEFT")
    place(header.earned, layout.earnedRight, layout.earnedWidth, "RIGHT")
    place(header.perHour, layout.perHourRight, layout.perHourWidth, "RIGHT")
    place(header.held, layout.heldRight, layout.heldWidth, "RIGHT")
    place(header.cap, layout.capRight, layout.capWidth, "RIGHT")

    header.quality:ClearAllPoints()
    header.quality:SetPoint("LEFT", header, "LEFT", PAD + 4, 0)
    header.quality:SetWidth(View.iconSize() + 4)

    header.quality:SetShown(not View.isCurrencyView())
    header.zone:SetShown(config.showZone and not View.isCurrencyView())
    header.lastLooted:SetShown(config.showLastLooted and not View.isCurrencyView())

    header.held.hint = View.report and View.report.heldIsCurrentCharacter == false
        and L["R_ColHeldAccountHint"] or nil

    for _, button in pairs({ header.quality, header.name, header.quantity, header.value,
                             header.market, header.character, header.source, header.zone,
                             header.lastLooted, header.earned, header.perHour, header.held,
                             header.cap }) do
        local isActive = sortKey == button.key
        local arrow = isActive and (descending and SORT_DOWN or SORT_UP) or ""

        button.label:SetText(button.baseText..arrow)
        button.label:SetTextColor(UI:rgbIf(isActive, "accent", "textDim"))
        button.underline:SetShown(isActive)
    end
end

function View.updateFooter()
    if (not View.window or not View.report) then return end

    if (View.isCurrencyView()) then
        local parts = {
            L["R_CurrenciesCount"].."|cFFFFFFFF"..#View.report.rows.."|r",
            L["R_CurrencyEarned"].."|cFFFFFFFF"..BreakUpLargeNumbers(View.report.totalEarned).."|r",
        }

        if (View.report.cappedTotal > 0) then
            parts[#parts+1] = L["R_CapsReached"](View.report.cappedCount, View.report.cappedTotal)
        end

        View.window.footerText:SetText(table.concat(parts, "   |cFF4A4A55|||r   "))
        View.window.footerZone:SetText(L["R_CurrencyWindow"](MLH:formatDuration(View.report.duration)))

        return
    end

    local parts = {
        L["R_Items"]..("|cFFFFFFFF"..#View.report.items.."|r"),
        L["R_Quantity"]..("|cFFFFFFFF"..View.report.totalQuantity.."|r"),
        L["R_SellPrice"]..GetMoneyString(View.report.totalVendorValue),
    }

    if (MLH:getPriceSource() ~= "vendor") then
        parts[#parts+1] = L["R_MarketPrice"]..GetMoneyString(View.report.totalMarketValue)
    end

    if ((View.report.hiddenCount or 0) > 0) then
        parts[#parts+1] = L["R_HiddenCount"](View.report.hiddenCount)
    end

    View.window.footerText:SetText(table.concat(parts, "   |cFF4A4A55|||r   "))

    local topZone = View.report.zones[1]

    View.window.footerZone:SetText(topZone and L["R_MostlyFrom"](topZone.name) or "")
end
