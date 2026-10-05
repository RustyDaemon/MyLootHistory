--[[
My Loot History addon
Copyright (C) 2026 RustyDaemon (https://github.com/RustyDaemon)

See License file for details.
--]]

-- One row of the list: an item, a currency, a heading or the gold earned, with its tooltip and menu.

local MLH = LibStub("AceAddon-3.0"):GetAddon("MyLootHistory")
local L = LibStub("AceLocale-3.0"):GetLocale("MyLootHistory")
local UI = MLH.UI
local View = MLH.reportView

local PAD = View.PAD
local ROW_HEIGHT = View.ROW_HEIGHT

local function qualityColor(quality)
    local r, g, b = C_Item.GetItemQualityColor(quality or 0)

    return r, g, b
end

local function applyCell(fontString, right, width, justify)
    if (not right) then
        fontString:Hide()
        return
    end

    fontString:Show()
    fontString:ClearAllPoints()
    fontString:SetPoint("RIGHT", fontString:GetParent(), "RIGHT", right, 0)
    fontString:SetWidth(width)
    fontString:SetJustifyH(justify or "RIGHT")
end

local rowMenu = nil

local MAX_ROW_MENU_ZONES = 5

-- Menu values are zone ids, so the one action that is not a zone gets a value no zone can have.
local HIDE_ITEM = "hide"

-- A zone filter in force is undone from any row; otherwise a row offers the zones it was looted in.
-- An item row can also be hidden.
local function rowMenuItems(entry)
    local items = {}

    if (MLH:getFilters().zone ~= 0) then
        items[1] = { text = L["R_ShowAllZones"], value = 0 }
    else
        local zones = (entry.kind == "item" and entry.item.zones)
            or ((entry.kind == "currency" or entry.kind == "budget") and entry.currency.zones)
            or {}

        for i = 1, #zones do
            if (zones[i].id) then
                items[#items+1] = { text = L["R_FilterToZone"](zones[i].name), value = zones[i].id }

                if (#items == MAX_ROW_MENU_ZONES) then break end
            end
        end
    end

    if (entry.kind == "item") then
        items[#items+1] = { text = L["R_HideItem"], value = HIDE_ITEM }
    end

    return items
end

local function hideItem(item)
    MLH:setItemHidden(item.itemId, true, item.itemName)

    print(L["M_ItemHidden"](item.itemLink or item.itemName))
end

local function showRowMenu(entry)
    local items = rowMenuItems(entry)

    if (#items == 0) then return end

    rowMenu = rowMenu or UI:menu()

    local x, y = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()

    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)

    rowMenu:ClearAllPoints()
    rowMenu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / scale, y / scale)
    rowMenu:Open(items, function(value)
        if (value == HIDE_ITEM) then
            hideItem(entry.item)
            View.refreshReport(true)
            View.updateActivity()
            return
        end

        MLH:setFilter("zone", value)
        View.refreshReport()
    end)
end

function View.closeRowMenu()
    if (rowMenu) then rowMenu:Hide() end
end

function View.createRow(parent)
    local row = CreateFrame("Button", nil, parent)

    row:SetHeight(ROW_HEIGHT)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    local stripe = row:CreateTexture(nil, "BACKGROUND")
    stripe:SetAllPoints()
    stripe:SetColorTexture(1, 1, 1, 0.022)
    row.stripe = stripe

    local heat = UI:gradient(row, "BORDER", "HORIZONTAL", 1, 0.82, 0.30, 0.16, 1, 0.82, 0.30, 0)
    heat:SetPoint("TOPLEFT")
    heat:SetPoint("BOTTOMLEFT")
    heat:SetWidth(1)
    row.heat = heat

    UI:attachHover(row, "panelHover", 0.85, "BORDER")

    local accent = row:CreateTexture(nil, "ARTWORK")
    accent:SetPoint("TOPLEFT", PAD - 8, -4)
    accent:SetPoint("BOTTOMLEFT", PAD - 8, 4)
    accent:SetWidth(2)
    row.accent = accent

    local iconBorder = row:CreateTexture(nil, "ARTWORK")
    iconBorder:SetPoint("LEFT", PAD + 5, 0)
    row.iconBorder = iconBorder

    local icon = row:CreateTexture(nil, "OVERLAY")
    icon:SetPoint("CENTER", iconBorder, "CENTER")
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    row.icon = icon

    local name = UI:text(row, 13, "text")
    name:SetJustifyH("LEFT")
    name:SetWordWrap(false)
    row.name = name

    local subtitle = UI:text(row, 10, "textFaint")
    subtitle:SetJustifyH("LEFT")
    subtitle:SetWordWrap(false)
    row.subtitle = subtitle

    row.quantity = UI:number(row, 14, "text")
    row.value = UI:text(row, 12, "text")
    row.market = UI:text(row, 12, "money")
    row.character = UI:text(row, 11, "textDim")
    row.source = UI:text(row, 11, "textDim")
    row.zone = UI:text(row, 11, "textDim")
    row.lastLooted = UI:text(row, 11, "textDim")

    row.character:SetWordWrap(false)
    row.source:SetWordWrap(false)
    row.zone:SetWordWrap(false)
    row.lastLooted:SetWordWrap(false)

    row.earned = UI:number(row, 14, "text")
    row.perHour = UI:text(row, 12, "textDim")
    row.held = UI:number(row, 12, "text")
    row.capText = UI:text(row, 10, "textDim")

    row.perHour:SetWordWrap(false)
    row.capText:SetWordWrap(false)

    local capBar = UI:panel(row, "raised", true)
    capBar:SetHeight(7)
    capBar:Hide()

    local capFill = capBar:CreateTexture(nil, "ARTWORK")
    capFill:SetPoint("TOPLEFT", 1, -1)
    capFill:SetPoint("BOTTOMLEFT", 1, 1)
    capFill:SetColorTexture(UI:rgb("accentDim"))

    capBar.fill = capFill
    row.capBar = capBar

    row.heading = UI:text(row, 11, "textFaint")
    row.heading:SetPoint("LEFT", PAD + 4, 0)

    row.headingRule = row:CreateTexture(nil, "ARTWORK")
    row.headingRule:SetPoint("LEFT", row.heading, "RIGHT", 8, 0)
    row.headingRule:SetPoint("RIGHT", row, "RIGHT", -PAD, 0)
    row.headingRule:SetHeight(1)
    row.headingRule:SetColorTexture(UI:rgb("border"))

    row:HookScript("OnEnter", function(self)
        if (not self.entry or not MLH.db.char.config.showTooltip) then return end

        local entry = self.entry

        if (entry.kind == "item") then
            GameTooltip:SetOwner(self, "ANCHOR_NONE")
            GameTooltip:SetPoint("TOPLEFT", View.window, "TOPRIGHT", 6, 0)

            MLH:setTooltipSuppressed(true)

            if (entry.item.itemLink) then
                GameTooltip:SetHyperlink(entry.item.itemLink)
            else
                GameTooltip:SetItemByID(entry.item.itemId)
            end

            MLH:setTooltipSuppressed(false)

            if (MLH.db.char.config.showAdditionalTooltipData) then
                local item = entry.item
                local zones = {}

                for i = 1, #item.zones do
                    zones[i] = item.zones[i].name.." ("..item.zones[i].quantity..")"
                end

                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("|cFFDDDDDD"..L["R_TotalQuantityGathered"].."|r |cFF00BB00"
                    ..item.totalQuantity.."|r", 1, 1, 1, true)

                if (#zones > 0) then
                    GameTooltip:AddLine("|cFFDDDDDD"..L["R_LootedIn"].."|r |cFF00BB00"
                        ..table.concat(zones, ", ").."|r", 1, 1, 1, true)
                end

                local levels = MLH:getItemLevelBreakdown(item)

                if (#levels > 1) then
                    local parts = {}

                    for i = 1, #levels do
                        parts[i] = levels[i].level.." ("..levels[i].quantity..")"
                    end

                    GameTooltip:AddLine("|cFFDDDDDD"..L["R_ItemLevels"].."|r |cFF00BB00"
                        ..table.concat(parts, ", ").."|r", 1, 1, 1, true)
                end

                if (item.sources and #item.sources > 0) then
                    local sources = {}

                    for i = 1, math.min(#item.sources, 5) do
                        sources[i] = item.sources[i].name.." ("..item.sources[i].quantity..")"
                    end

                    GameTooltip:AddLine("|cFFDDDDDD"..L["R_DroppedBy"].."|r |cFF00BB00"
                        ..table.concat(sources, ", ").."|r", 1, 1, 1, true)
                end

                if (item.characters and #item.characters > 1) then
                    local names = {}

                    for i = 1, #item.characters do
                        names[i] = item.characters[i].name.." ("..item.characters[i].quantity..")"
                    end

                    GameTooltip:AddLine("|cFFDDDDDD"..L["R_LootedBy"].."|r |cFF00BB00"
                        ..table.concat(names, ", ").."|r", 1, 1, 1, true)
                end
            end

            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(L["R_ShiftClickToLink"], UI:rgb("textFaint"))
            GameTooltip:AddLine(L["R_RightClickForZone"], UI:rgb("textFaint"))
            GameTooltip:Show()
        elseif (entry.kind == "currency" or entry.kind == "budget") then
            GameTooltip:SetOwner(self, "ANCHOR_NONE")
            GameTooltip:SetPoint("TOPLEFT", View.window, "TOPRIGHT", 6, 0)
            GameTooltip:SetCurrencyByID(entry.currency.currencyId)

            if (entry.kind == "budget") then
                local currency = entry.currency
                local dimR, dimG, dimB = UI:rgb("textDim")
                local zones = {}

                for i = 1, math.min(#currency.zones, 5) do
                    zones[i] = currency.zones[i].name.." ("..currency.zones[i].quantity..")"
                end

                GameTooltip:AddLine(" ")
                GameTooltip:AddLine(L["R_CurrencyEarnedInView"](currency.quantity,
                    MLH:getRangeName(MLH:getFilters().range)), 1, 1, 1)
                GameTooltip:AddLine(L["R_CurrencyRate"](string.format("%.1f", currency.perHour or 0)),
                    dimR, dimG, dimB)

                if (#zones > 0) then
                    GameTooltip:AddLine(L["R_LootedIn"].." "..table.concat(zones, ", "),
                        dimR, dimG, dimB, true)
                end

                GameTooltip:AddLine(" ")
                GameTooltip:AddLine(L["R_RightClickForZone"], UI:rgb("textFaint"))
            end

            GameTooltip:Show()
        end
    end)

    row:HookScript("OnLeave", function() GameTooltip:Hide() end)

    row:SetScript("OnClick", function(self, button)
        local entry = self.entry

        if (not entry) then return end

        if (button == "RightButton") then
            showRowMenu(entry)
        elseif (IsLeftShiftKeyDown() or IsRightShiftKeyDown()) then
            local link = entry.kind == "item" and entry.item.itemLink
                or ((entry.kind == "currency" or entry.kind == "budget")
                    and C_CurrencyInfo.GetCurrencyLink(entry.currency.currencyId, entry.currency.quantity))

            if (link) then ChatEdit_TryInsertChatLink(link) end
        end
    end)

    return row
end

local function applyCapCell(row, layout)
    local bar = row.capBar
    local text = row.capText

    if (not layout.capRight) then
        text:Hide()
        bar:Hide()
        return
    end

    text:Show()
    text:ClearAllPoints()
    text:SetWidth(layout.capWidth)
    text:SetJustifyH("RIGHT")

    if (not row.hasCap) then
        bar:Hide()
        text:SetPoint("RIGHT", row, "RIGHT", layout.capRight, 0)

        return
    end

    text:SetPoint("RIGHT", row, "RIGHT", layout.capRight, 7)

    bar:Show()
    bar:ClearAllPoints()
    bar:SetPoint("RIGHT", row, "RIGHT", layout.capRight, -8)
    bar:SetWidth(layout.capWidth)
    bar.fill:SetWidth(math.max((layout.capWidth - 2) * (row.capRatio or 0), 1))
end

function View.fillRow(row, entry, index, layout)
    row.entry = entry
    row.hasCap = false
    row.capRatio = 0

    local isHeading = entry.kind == "heading"

    row.heading:SetShown(isHeading)
    row.headingRule:SetShown(isHeading)
    row.icon:SetShown(not isHeading)
    row.iconBorder:SetShown(not isHeading)
    row.name:SetShown(not isHeading)
    row.accent:SetShown(not isHeading)
    row.stripe:SetShown(not isHeading and index % 2 == 0)
    row:EnableMouse(not isHeading)

    if (isHeading) then
        row.heading:SetText(entry.text)
        row.subtitle:Hide()
        row.quantity:Hide()
        row.value:Hide()
        row.market:Hide()
        row.character:Hide()
        row.source:Hide()
        row.zone:Hide()
        row.lastLooted:Hide()
        row.earned:Hide()
        row.perHour:Hide()
        row.held:Hide()
        row.capText:Hide()
        row.capBar:Hide()
        row.heat:SetWidth(1)
        row.heat:Hide()

        return
    end

    row.heat:Show()

    local size = View.iconSize()

    row.iconBorder:SetSize(size + 2, size + 2)
    row.icon:SetSize(size, size)

    local subtitleParts = {}
    local config = MLH.db.char.config

    if (entry.kind == "item") then
        local item = entry.item
        local r, g, b = qualityColor(item.quality)

        row.icon:SetTexture(item.itemTexture)
        row.iconBorder:SetColorTexture(r, g, b, 0.9)
        row.accent:SetColorTexture(r, g, b, 0.55)
        row.name:SetText(item.itemName)
        row.name:SetTextColor(r, g, b)

        row.quantity:SetText(item.totalQuantity)
        row.quantity:SetTextColor(UI:rgb("text"))
        row.value:SetText(MLH:formatMoneyShort(item.vendorValue or item.totalValue))
        row.value:SetAlpha(1)
        row.market:SetText(item.marketValue and MLH:formatMoneyShort(item.marketValue) or "-")
        row.market:SetAlpha(item.marketValue and 1 or 0.35)
        row.character:SetText(item.charName or "")
        row.source:SetText(item.sourceName or "")
        row.zone:SetText(item.zoneName)
        row.lastLooted:SetText(item.dateRange)

        if (config.showItemID) then subtitleParts[#subtitleParts+1] = "#"..item.itemId end
        if (not config.showZone) then subtitleParts[#subtitleParts+1] = item.zoneName end
        if (not config.showLastLooted and item.dateRange ~= "") then
            subtitleParts[#subtitleParts+1] = item.dateRange
        end

        local ratio = (View.report and View.report.topValue > 0) and (item.totalValue / View.report.topValue) or 0
        row.heat:SetWidth(math.max(ratio * row:GetWidth(), 1))
        row.heat:SetAlpha(ratio > 0.02 and 1 or 0)
    elseif (entry.kind == "currency") then
        local currency = entry.currency
        local r, g, b = qualityColor(currency.quality)

        row.icon:SetTexture(currency.icon)
        row.iconBorder:SetColorTexture(r, g, b, 0.9)
        row.accent:SetColorTexture(r, g, b, 0.55)
        row.name:SetText(currency.name)
        row.name:SetTextColor(r, g, b)

        row.quantity:SetText(currency.quantity)
        row.quantity:SetTextColor(UI:rgb("text"))
        row.value:SetText("")
        row.value:SetAlpha(1)
        row.market:SetText("")
        row.character:SetText("")
        row.source:SetText("")
        row.zone:SetText(currency.zoneName)
        row.lastLooted:SetText("")

        if (not config.showZone) then subtitleParts[#subtitleParts+1] = currency.zoneName end

        row.heat:SetAlpha(0)
        row.heat:SetWidth(1)
    elseif (entry.kind == "budget") then
        local currency = entry.currency
        local r, g, b = qualityColor(currency.quality)
        local cap = currency.cap

        row.icon:SetTexture(currency.icon)
        row.iconBorder:SetColorTexture(r, g, b, 0.9)
        row.accent:SetColorTexture(r, g, b, 0.55)
        row.name:SetText(currency.name)
        row.name:SetTextColor(r, g, b)

        row.earned:SetText("+"..currency.quantity)
        row.perHour:SetText(L["R_PerHourValue"](string.format("%.1f", currency.perHour or 0)))

        row.held:SetText(currency.held and BreakUpLargeNumbers(currency.held) or "-")
        row.held:SetAlpha(currency.held and 1 or 0.35)

        if (cap) then
            local complete = cap.current >= cap.max

            row.hasCap = true
            row.capRatio = currency.capRatio or 0

            row.capText:SetText(cap.kind == "weekly"
                and L["R_CapWeekly"](cap.current, cap.max)
                or L["R_CapTotal"](cap.current, cap.max))
            row.capText:SetTextColor(UI:rgbIf(complete, "good", "textDim"))
            row.capBar.fill:SetColorTexture(UI:rgbIf(complete, "good", "accent"))
        else
            row.capText:SetText(L["R_NoCap"])
            row.capText:SetTextColor(UI:rgb("textFaint"))
        end

        subtitleParts[#subtitleParts+1] = currency.zoneName

        row.heat:SetAlpha(0)
        row.heat:SetWidth(1)
    else --gold
        row.icon:SetTexture(133784)
        row.iconBorder:SetColorTexture(UI:rgb("money", 0.9))
        row.accent:SetColorTexture(UI:rgb("money", 0.55))
        row.name:SetText(L["R_GoldEarnedShort"])
        row.name:SetTextColor(UI:rgb("money"))

        row.quantity:SetText("")
        row.value:SetText(MLH:formatMoneyShort(entry.gold))
        row.value:SetAlpha(1)
        row.market:SetText("")
        row.character:SetText("")
        row.source:SetText("")
        row.zone:SetText("")
        row.lastLooted:SetText("")

        row.heat:SetAlpha(0)
        row.heat:SetWidth(1)
    end

    local subtitle = table.concat(subtitleParts, "  ·  ")

    row.name:ClearAllPoints()
    row.subtitle:ClearAllPoints()

    if (subtitle ~= "") then
        row.subtitle:Show()
        row.subtitle:SetText(subtitle)
        row.name:SetPoint("TOPLEFT", layout.nameLeft, -8)
        row.name:SetPoint("TOPRIGHT", layout.nameRight, -8)
        row.subtitle:SetPoint("TOPLEFT", layout.nameLeft, -25)
        row.subtitle:SetPoint("TOPRIGHT", layout.nameRight, -25)
    else
        row.subtitle:Hide()
        row.name:SetPoint("LEFT", layout.nameLeft, 0)
        row.name:SetPoint("RIGHT", layout.nameRight, 0)
    end

    applyCell(row.quantity, layout.quantityRight, layout.quantityWidth, "RIGHT")
    applyCell(row.value, layout.valueRight, layout.valueWidth, "RIGHT")
    applyCell(row.market, layout.marketRight, layout.marketWidth, "RIGHT")
    applyCell(row.character, layout.characterRight, layout.characterWidth, "LEFT")
    applyCell(row.source, layout.sourceRight, layout.sourceWidth, "LEFT")
    applyCell(row.zone, layout.zoneRight, layout.zoneWidth, "LEFT")
    applyCell(row.lastLooted, layout.lastLootedRight, layout.lastLootedWidth, "LEFT")
    applyCell(row.earned, layout.earnedRight, layout.earnedWidth, "RIGHT")
    applyCell(row.perHour, layout.perHourRight, layout.perHourWidth, "RIGHT")
    applyCell(row.held, layout.heldRight, layout.heldWidth, "RIGHT")

    applyCapCell(row, layout)
end
