--[[
My Loot History addon
Copyright (C) 2026 RustyDaemon (https://github.com/RustyDaemon)

See License file for details.
--]]

local MLH = LibStub("AceAddon-3.0"):GetAddon("MyLootHistory")
local L = LibStub("AceLocale-3.0"):GetLocale("MyLootHistory")
local UI = MLH.UI

local PAD = 14
local TITLE_HEIGHT = 44
local STATS_HEIGHT = 86
local FILTER_HEIGHT = 58
local FILTER_ROW = 48
local FILTER_GAP = 10
local HEADER_HEIGHT = 24
local FOOTER_HEIGHT = 30
local ROW_HEIGHT = 40
local GRAPH_WIDTH = 232
local CARD_GAP = 8

local COLUMN_WIDTH = {
    quantity = 54,
    value = 104,
    market = 104,
    character = 104,
    source = 132,
    zone = 132,
    lastLooted = 124,
}

local CURRENCY_COLUMN_WIDTH = {
    earned = 68,
    perHour = 78,
    held = 82,
    cap = 168,
}

local COLUMN_GAP = 14

local MIN_WIDTH = 780
local MIN_HEIGHT = 460
local DEFAULT_WIDTH = 940
local DEFAULT_HEIGHT = 620

local ACTIVITY_HOURS = 24

local GOLD_ICON = "|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:0:-1|t"

-- Use cropped client textures: FRIZQT__.TTF lacks arrow glyphs.
local SORT_UP = " |TInterface\\ChatFrame\\UI-ChatIcon-ScrollUp-Up:16:16:0:-2:32:32:8:24:8:24|t"
local SORT_DOWN = " |TInterface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up:16:16:0:-2:32:32:8:24:8:24|t"

local window = nil
local rows = {}
local displayList = {}
local report = nil
local searchTimer = nil
local ticker = nil
local scrollOffset = 0

local refreshReport, rebuildList, layoutRows, updateScroll, updateSession, updateActivity,
      updateFooter, buildWindow, saveWindowPosition, showExportWindow, columnLayout

local function iconSize()
    return MLH.db.char.config.reportIconSize or 24
end

local function qualityColor(quality)
    local r, g, b = C_Item.GetItemQualityColor(quality or 0)

    return r, g, b
end

local function isCurrencyView()
    return MLH:getFilters().view == "currency"
end

function columnLayout()
    local config = MLH.db.char.config
    local layout = { cursor = -PAD }

    local function claim(width)
        local right = layout.cursor

        layout.cursor = layout.cursor - width - COLUMN_GAP

        return right, width
    end

    if (isCurrencyView()) then
        layout.capRight, layout.capWidth = claim(CURRENCY_COLUMN_WIDTH.cap)
        layout.heldRight, layout.heldWidth = claim(CURRENCY_COLUMN_WIDTH.held)
        layout.perHourRight, layout.perHourWidth = claim(CURRENCY_COLUMN_WIDTH.perHour)
        layout.earnedRight, layout.earnedWidth = claim(CURRENCY_COLUMN_WIDTH.earned)

        layout.nameLeft = PAD + 6 + iconSize() + 10
        layout.nameRight = layout.cursor

        return layout
    end

    if (config.showLastLooted) then
        layout.lastLootedRight, layout.lastLootedWidth = claim(COLUMN_WIDTH.lastLooted)
    end

    if (MLH:getScope() == "account") then
        layout.characterRight, layout.characterWidth = claim(COLUMN_WIDTH.character)
    end

    if (config.showZone) then
        layout.zoneRight, layout.zoneWidth = claim(COLUMN_WIDTH.zone)
    end

    if (config.showSource) then
        layout.sourceRight, layout.sourceWidth = claim(COLUMN_WIDTH.source)
    end

    if (MLH:getPriceSource() ~= "vendor") then
        layout.marketRight, layout.marketWidth = claim(COLUMN_WIDTH.market)
    end

    layout.valueRight, layout.valueWidth = claim(COLUMN_WIDTH.value)
    layout.quantityRight, layout.quantityWidth = claim(COLUMN_WIDTH.quantity)

    layout.nameLeft = PAD + 6 + iconSize() + 10
    layout.nameRight = layout.cursor

    return layout
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

local function sortState()
    local active = MLH:getFilters()

    if (active.view == "currency") then return active.currencySort, active.currencySortDescending end

    return active.sortKey, active.sortDescending
end

local function setSort(key)
    local currency = isCurrencyView()
    local currentKey, descending = sortState()

    if (currentKey == key) then
        MLH:setFilter(currency and "currencySortDescending" or "sortDescending", not descending)
        return
    end

    MLH:setFilter(currency and "currencySort" or "sortKey", key)
    MLH:setFilter(currency and "currencySortDescending" or "sortDescending",
        key ~= "name" and key ~= "zone" and key ~= "character")
end

local function createCard(parent, caption, accentColorName)
    local card = UI:panel(parent, "panel", true)

    card:EnableMouse(true)

    UI:attachHover(card, "panelHover", 0.6, "BORDER")

    local stripe = card:CreateTexture(nil, "ARTWORK")
    stripe:SetPoint("TOPLEFT")
    stripe:SetPoint("BOTTOMLEFT")
    stripe:SetWidth(2)
    stripe:SetColorTexture(UI:rgb(accentColorName or "accentDim"))

    local title = UI:text(card, 10, "textFaint")
    title:SetPoint("TOPLEFT", 12, -10)
    title:SetText(caption)

    local value = UI:number(card, 22, "text")
    value:SetPoint("TOPLEFT", 11, -25)

    local footnote = UI:text(card, 10, "textDim")
    footnote:SetPoint("BOTTOMLEFT", 12, 9)
    footnote:SetPoint("BOTTOMRIGHT", -8, 9)
    footnote:SetJustifyH("LEFT")
    footnote:SetWordWrap(false)

    card.value = value
    card.footnote = footnote
    card.stripe = stripe

    card.Set = function(_, text, note, colorName)
        value:SetText(text)
        value:SetTextColor(UI:rgb(colorName or "text"))
        footnote:SetText(note or "")
    end

    return card
end

local function createActivityGraph(parent)
    local graph = UI:panel(parent, "panel", true)

    local title = UI:text(graph, 10, "textFaint")
    title:SetPoint("TOPLEFT", 12, -10)
    title:SetText(L["G_Last24h"])

    local peakLabel = UI:text(graph, 10, "textDim")
    peakLabel:SetPoint("TOPRIGHT", -10, -10)
    peakLabel:SetJustifyH("RIGHT")

    local baseline = graph:CreateTexture(nil, "ARTWORK")
    baseline:SetPoint("BOTTOMLEFT", 10, 15)
    baseline:SetPoint("BOTTOMRIGHT", -10, 15)
    baseline:SetHeight(1)
    baseline:SetColorTexture(UI:rgb("border"))

    local bars = {}

    for i = 1, ACTIVITY_HOURS do
        local bar = CreateFrame("Button", nil, graph)

        bar:SetPoint("BOTTOM", graph, "BOTTOMLEFT", 0, 16)

        local fill = bar:CreateTexture(nil, "ARTWORK")
        fill:SetPoint("BOTTOMLEFT")
        fill:SetPoint("BOTTOMRIGHT")
        fill:SetPoint("TOP")
        fill:SetColorTexture(UI:rgb("accentDim"))

        bar.fill = fill

        bar:SetScript("OnEnter", function(self)
            fill:SetColorTexture(UI:rgb("accent"))

            if (not self.hourLabel) then return end

            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(self.hourLabel, 1, 1, 1)
            GameTooltip:AddLine(L["G_BarTooltip"](self.quantity or 0, self.valueText or "0"),
                UI:rgb("textDim"))
            GameTooltip:Show()
        end)

        bar:SetScript("OnLeave", function()
            fill:SetColorTexture(UI:rgb("accentDim"))
            GameTooltip:Hide()
        end)

        bars[i] = bar
    end

    graph.bars = bars
    graph.peakLabel = peakLabel

    return graph
end

function updateActivity()
    if (not window or not window.graph or not window.graph:IsShown()) then return end

    local graph = window.graph
    local buckets, peak, bucketStart = MLH:getActivityBuckets(ACTIVITY_HOURS)
    local usable = graph:GetWidth() - 20
    local barWidth = math.max(usable / ACTIVITY_HOURS - 2, 2)
    local maxHeight = graph:GetHeight() - 44

    graph.peakLabel:SetText(peak > 0 and (L["G_Peak"]..MLH:formatGoldCompact(peak)..GOLD_ICON) or "")

    for i = 1, ACTIVITY_HOURS do
        local bar = graph.bars[i]
        local bucket = buckets[i]
        local ratio = peak > 0 and (bucket.value / peak) or 0

        bar:SetWidth(barWidth)
        bar:SetPoint("BOTTOM", graph, "BOTTOMLEFT", 10 + (i - 0.5) * (usable / ACTIVITY_HOURS), 16)
        bar:SetHeight(math.max(ratio * maxHeight, bucket.value > 0 and 2 or 1))

        bar.fill:SetAlpha(bucket.value > 0 and 1 or 0.25)
        bar.hourLabel = date("%H:00", bucketStart + (i - 1) * 3600)
        bar.quantity = bucket.quantity
        bar.valueText = MLH:formatGoldCompact(bucket.value)
    end
end

local function createRow(parent)
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
            GameTooltip:SetPoint("TOPLEFT", window, "TOPRIGHT", 6, 0)

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
            GameTooltip:Show()
        elseif (entry.kind == "currency" or entry.kind == "budget") then
            GameTooltip:SetOwner(self, "ANCHOR_NONE")
            GameTooltip:SetPoint("TOPLEFT", window, "TOPRIGHT", 6, 0)
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
            end

            GameTooltip:Show()
        end
    end)

    row:HookScript("OnLeave", function() GameTooltip:Hide() end)

    row:SetScript("OnClick", function(self)
        local entry = self.entry

        if (not entry) then return end

        if (IsLeftShiftKeyDown() or IsRightShiftKeyDown()) then
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

local function fillRow(row, entry, index, layout)
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

    local size = iconSize()

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

        local ratio = (report and report.topValue > 0) and (item.totalValue / report.topValue) or 0
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

function rebuildList()
    displayList = {}

    if (isCurrencyView()) then
        for i = 1, #report.rows do
            displayList[#displayList+1] = { kind = "budget", currency = report.rows[i] }
        end

        return
    end

    for i = 1, #report.items do
        displayList[#displayList+1] = { kind = "item", item = report.items[i] }
    end

    if (report.gold > 0) then
        displayList[#displayList+1] = { kind = "heading", text = L["R_Money"] }
        displayList[#displayList+1] = { kind = "gold", gold = report.gold }
    end
end

function layoutRows()
    if (not window) then return end

    local list = window.list
    local viewportHeight = math.max(list:GetHeight(), 1)
    local needed = math.ceil(viewportHeight / ROW_HEIGHT) + 1
    local layout = columnLayout()

    for i = #rows + 1, needed do
        local row = createRow(list)

        row:SetPoint("LEFT", 0, 0)
        row:SetPoint("RIGHT", 0, 0)
        rows[i] = row
    end

    local firstIndex = math.floor(scrollOffset / ROW_HEIGHT)
    local pixelOffset = scrollOffset - firstIndex * ROW_HEIGHT

    for i = 1, #rows do
        local row = rows[i]
        local entryIndex = firstIndex + i

        if (entryIndex <= #displayList and i <= needed) then
            row:ClearAllPoints()
            row:SetPoint("LEFT", 0, 0)
            row:SetPoint("RIGHT", 0, 0)
            row:SetPoint("TOP", list, "TOP", 0, -((i - 1) * ROW_HEIGHT - pixelOffset))
            row:Show()

            fillRow(row, displayList[entryIndex], entryIndex, layout)
        else
            row:Hide()
            row.entry = nil
        end
    end
end

function updateScroll(offset)
    if (not window) then return end

    local viewportHeight = window.list:GetHeight()
    local contentHeight = #displayList * ROW_HEIGHT

    scrollOffset = window.scrollbar:Update(viewportHeight, math.max(contentHeight, 1), offset or scrollOffset)

    layoutRows()
end

local function createHeaderColumn(parent, key, text, justify)
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
        if (sortState() ~= self.key) then self.label:SetTextColor(UI:rgb("text")) end

        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(L["R_SortBy"](self.baseText), 1, 1, 1)

        if (self.hint) then GameTooltip:AddLine(self.hint, UI:rgb("textDim")) end

        GameTooltip:Show()
    end)

    button:HookScript("OnLeave", function(self)
        if (sortState() ~= self.key) then self.label:SetTextColor(UI:rgb("textDim")) end

        GameTooltip:Hide()
    end)

    button:SetScript("OnClick", function(self)
        setSort(self.key)

        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        refreshReport()
    end)

    return button
end

local function refreshHeader()
    local sortKey, descending = sortState()
    local config = MLH.db.char.config
    local layout = columnLayout()
    local header = window.header

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
    header.quality:SetWidth(iconSize() + 4)

    header.quality:SetShown(not isCurrencyView())
    header.zone:SetShown(config.showZone and not isCurrencyView())
    header.lastLooted:SetShown(config.showLastLooted and not isCurrencyView())

    header.held.hint = report and report.heldIsCurrentCharacter == false
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

function updateSession()
    if (not window or not window.cards) then return end

    local viewing = MLH:getFilters().range == 1 and MLH:getSelectedSession() or nil
    local stats = MLH:getSessionStats(viewing)
    local cards = window.cards

    cards.time:Set(MLH:formatDuration(stats.duration),
        stats.isLive and L["G_SinceLogin"] or L["S_PastSession"](date("%d %b %H:%M", stats.sessionStart)),
        "text")
    cards.items:Set(string.format("%.0f", stats.itemsPerHour), L["G_ItemsTotal"](stats.quantity), "text")
    cards.gold:Set(MLH:formatGoldCompact(stats.goldPerHour)..GOLD_ICON,
        L["G_ValueSoFar"](MLH:formatGoldCompact(stats.totalValue)), "money")

    if (not report) then return end

    if (isCurrencyView()) then
        cards.filtered:Set(BreakUpLargeNumbers(report.totalEarned),
            MLH:getRangeName(MLH:getFilters().range), "accent")
    else
        cards.filtered:Set(MLH:formatGoldCompact(report.totalValue + report.gold)..GOLD_ICON,
            MLH:getRangeName(MLH:getFilters().range), "accent")
    end
end

function updateFooter()
    if (not window or not report) then return end

    if (isCurrencyView()) then
        local parts = {
            L["R_CurrenciesCount"].."|cFFFFFFFF"..#report.rows.."|r",
            L["R_CurrencyEarned"].."|cFFFFFFFF"..BreakUpLargeNumbers(report.totalEarned).."|r",
        }

        if (report.cappedTotal > 0) then
            parts[#parts+1] = L["R_CapsReached"](report.cappedCount, report.cappedTotal)
        end

        window.footerText:SetText(table.concat(parts, "   |cFF4A4A55|||r   "))
        window.footerZone:SetText(L["R_CurrencyWindow"](MLH:formatDuration(report.duration)))

        return
    end

    local parts = {
        L["R_Items"]..("|cFFFFFFFF"..#report.items.."|r"),
        L["R_Quantity"]..("|cFFFFFFFF"..report.totalQuantity.."|r"),
        L["R_SellPrice"]..GetMoneyString(report.totalVendorValue),
    }

    if (MLH:getPriceSource() ~= "vendor") then
        parts[#parts+1] = L["R_MarketPrice"]..GetMoneyString(report.totalMarketValue)
    end

    window.footerText:SetText(table.concat(parts, "   |cFF4A4A55|||r   "))

    local topZone = report.zones[1]

    window.footerZone:SetText(topZone and L["R_MostlyFrom"](topZone.name) or "")
end

local renderedRevision

function refreshReport(keepScroll)
    if (not window) then return end

    MLH:clearPriceCache()

    report = isCurrencyView() and MLH:buildCurrencyReport() or MLH:buildReport()
    renderedRevision = MLH.historyRevision

    rebuildList()
    refreshHeader()

    if (not keepScroll) then scrollOffset = 0 end

    local isEmpty = #displayList == 0

    window.emptyText:SetText(isCurrencyView() and L["R_NoCurrenciesHere"] or L["R_NothingIsHereYet"])
    window.empty:SetShown(isEmpty)
    window.emptyReset:SetShown(isEmpty and MLH:hasActiveFilters())
    window.header:SetShown(not isEmpty)

    updateScroll(scrollOffset)
    updateSession()
    updateFooter()

    window.zoneDropdown:SetText(MLH:getZoneFilterName())
    window.qualityDropdown:SetText(MLH:getQualityName(MLH:getFilters().quality))
    window.sessionDropdown:SetText(MLH:getSelectedSessionName())
    window.scopeDropdown:SetText(MLH:getScopeName())
    window.rangeControl:Refresh()
    window.exactToggle:Refresh()
    window.viewControl:Refresh()

    window:UpdateLayout()
end

function MLH:refreshReport()
    if (not window or not window:IsShown()) then return end

    window.statsRow:SetShown(self.db.char.config.showSessionBar and true or false)
    window:UpdateLayout()
    refreshReport(true)
end

function saveWindowPosition()
    if (not window) then return end

    local point, _, relativePoint, x, y = window:GetPoint()

    MLH.db.char.ui = MLH.db.char.ui or {}
    MLH.db.char.ui.point = point
    MLH.db.char.ui.relativePoint = relativePoint
    MLH.db.char.ui.x = x
    MLH.db.char.ui.y = y
    MLH.db.char.ui.width = window:GetWidth()
    MLH.db.char.ui.height = window:GetHeight()
end

function buildWindow()
    local frame = CreateFrame("Frame", "MLHReportFrame", UIParent)

    frame:SetFrameStrata("HIGH")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:SetResizable(true)
    frame:EnableMouse(true)
    frame:Hide()

    if (frame.SetResizeBounds) then
        frame:SetResizeBounds(MIN_WIDTH, MIN_HEIGHT)
    end

    local shadow = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    shadow:SetPoint("TOPLEFT", -6, 6)
    shadow:SetPoint("BOTTOMRIGHT", 6, -6)
    shadow:SetColorTexture(0, 0, 0, 0.45)

    local bg = frame:CreateTexture(nil, "BACKGROUND", nil, -7)
    bg:SetAllPoints()
    bg:SetColorTexture(UI:rgb("window", 0.97))

    UI:addBorder(frame, UI:rgb("borderLight"))

    local titleBar = CreateFrame("Frame", nil, frame)
    titleBar:SetPoint("TOPLEFT", 1, -1)
    titleBar:SetPoint("TOPRIGHT", -1, -1)
    titleBar:SetHeight(TITLE_HEIGHT)
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")

    local titleFill = UI:gradient(titleBar, "BACKGROUND", "VERTICAL",
        0.055, 0.059, 0.070, 1, 0.114, 0.106, 0.075, 1)
    titleFill:SetAllPoints()

    local titleLine = titleBar:CreateTexture(nil, "ARTWORK")
    titleLine:SetPoint("BOTTOMLEFT")
    titleLine:SetPoint("BOTTOMRIGHT")
    titleLine:SetHeight(1)
    titleLine:SetColorTexture(UI:rgb("accentDim", 0.6))

    titleBar:SetScript("OnDragStart", function() frame:StartMoving() end)
    titleBar:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        saveWindowPosition()
    end)

    local logo = titleBar:CreateTexture(nil, "ARTWORK")
    logo:SetSize(24, 24)
    logo:SetPoint("LEFT", PAD, 0)
    logo:SetTexture("Interface\\Icons\\inv_misc_map09")
    logo:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local logoBorder = titleBar:CreateTexture(nil, "BACKGROUND")
    logoBorder:SetPoint("TOPLEFT", logo, "TOPLEFT", -1, 1)
    logoBorder:SetPoint("BOTTOMRIGHT", logo, "BOTTOMRIGHT", 1, -1)
    logoBorder:SetColorTexture(UI:rgb("accentDim"))

    local title = UI:text(titleBar, 15, "text")
    title:SetPoint("LEFT", logo, "RIGHT", 10, 1)
    title:SetText(L["MM_IconTitle"])

    local subtitle = UI:text(titleBar, 11, "textFaint")
    subtitle:SetPoint("LEFT", title, "RIGHT", 10, 0)
    subtitle:SetText(UnitName("player").." · "..(GetRealmName() or ""))

    local viewControl = UI:segmented(titleBar, 26, {
        { value = "items", text = L["R_ViewItems"] },
        { value = "currency", text = L["R_ViewCurrencies"] },
    },
        function() return MLH:getFilters().view end,
        function(value)
            MLH:setFilter("view", value)
            refreshReport()
        end)
    viewControl:SetPoint("LEFT", subtitle, "RIGHT", 20, 0)

    local close = UI:iconButton(titleBar, 28, "Interface\\Buttons\\UI-StopButton",
        function() frame:Hide() end)
    close:SetPoint("RIGHT", -6, 0)
    UI:tooltip(close, L["R_Close"])

    local settings = UI:iconButton(titleBar, 28, "Interface\\Buttons\\UI-OptionsButton", function()
        LibStub("AceConfigDialog-3.0"):Open("MyLootHistory_GeneralOptions")
    end)
    settings:SetPoint("RIGHT", close, "LEFT", -2, 0)
    UI:tooltip(settings, L["R_Settings"])

    local export = UI:iconButton(titleBar, 28, "Interface\\Buttons\\UI-GuildButton-PublicNote-Up",
        function() showExportWindow() end)
    export:SetPoint("RIGHT", settings, "LEFT", -2, 0)
    UI:tooltip(export, L["R_Export"], L["R_ExportTooltip"])

    local statsRow = CreateFrame("Frame", nil, frame)
    statsRow:SetPoint("TOPLEFT", titleBar, "BOTTOMLEFT", PAD, -PAD)
    statsRow:SetPoint("TOPRIGHT", titleBar, "BOTTOMRIGHT", -PAD, -PAD)
    statsRow:SetHeight(STATS_HEIGHT)

    local cards = {
        time = createCard(statsRow, L["G_Session"], "accent"),
        items = createCard(statsRow, L["G_ItemsPerHour"], "borderLight"),
        gold = createCard(statsRow, L["G_GoldPerHour"], "money"),
        filtered = createCard(statsRow, L["G_InView"], "borderLight"),
    }

    cards.time:EnableMouse(true)
    cards.time:SetScript("OnMouseUp", function()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        MLH:resetSession()
        refreshReport(true)
    end)
    UI:tooltip(cards.time, L["G_Session"], L["S_SessionTooltip"])
    UI:tooltip(cards.items, L["G_ItemsPerHour"], L["G_ItemsPerHourTooltip"])
    UI:tooltip(cards.gold, L["G_GoldPerHour"], L["G_GoldPerHourTooltip"])
    UI:tooltip(cards.filtered, L["G_InView"], L["G_InViewTooltip"])

    local graph = createActivityGraph(statsRow)
    graph:SetPoint("TOPRIGHT")
    graph:SetPoint("BOTTOMRIGHT")
    graph:SetWidth(GRAPH_WIDTH)

    local filterBar = CreateFrame("Frame", nil, frame)
    filterBar:SetPoint("TOPLEFT", statsRow, "BOTTOMLEFT", 0, -PAD)
    filterBar:SetPoint("TOPRIGHT", statsRow, "BOTTOMRIGHT", 0, -PAD)
    filterBar:SetHeight(FILTER_HEIGHT)

    local search = UI:searchBox(filterBar, 190, 26, L["R_SearchPlaceholder"], function(text, userInput)
        if (not userInput) then return end

        MLH:setFilter("search", text)

        if (searchTimer) then searchTimer:Cancel() end

        searchTimer = C_Timer.NewTimer(0.25, function()
            searchTimer = nil
            refreshReport()
        end)
    end)
    local searchCaption = UI:text(filterBar, 11, "textFaint")
    searchCaption:SetPoint("BOTTOMLEFT", search, "TOPLEFT", 1, 4)
    searchCaption:SetText(L["R_Search"])

    local rangeControl = UI:segmented(filterBar, 26, MLH:getShortRangeList(),
        function() return MLH:getFilters().range end,
        function(value)
            MLH:setFilter("range", value)
            refreshReport()
        end)
    local rangeCaption = UI:text(filterBar, 11, "textFaint")
    rangeCaption:SetPoint("BOTTOMLEFT", rangeControl, "TOPLEFT", 1, 4)
    rangeCaption:SetText(L["R_ReportDateRange"])

    local qualityDropdown = UI:dropdown(filterBar, 118, 26, L["R_MinimumItemQuality"],
        function() return MLH:getQualityList() end,
        function() return MLH:getFilters().quality end,
        function(value)
            MLH:setFilter("quality", value)
            refreshReport()
        end)
    local zoneDropdown = UI:dropdown(filterBar, 150, 26, L["R_Zone"],
        function() return MLH:getZoneList() end,
        function() return MLH:getFilters().zone end,
        function(value)
            MLH:setFilter("zone", value)
            refreshReport()
        end)
    local sessionDropdown = UI:dropdown(filterBar, 190, 26, L["S_SessionPicker"],
        function() return MLH:getSessionList() end,
        function() return MLH:getFilters().session or 0 end,
        function(value)
            MLH:setFilter("session", value)
            refreshReport()
        end)
    local scopeDropdown = UI:dropdown(filterBar, 140, 26, L["R_Scope"],
        function() return MLH:getScopeList() end,
        function() return MLH:getFilters().scope or "char" end,
        function(value)
            MLH:setFilter("scope", value)
            refreshReport()
        end)
    local exactToggle = UI:toggle(filterBar, L["R_ExactItemQuality"],
        function() return MLH:getFilters().exactQuality end,
        function(value)
            MLH:setFilter("exactQuality", value)
            refreshReport()
        end)

    local function layoutFilters()
        local available = math.max(filterBar:GetWidth(), 1)
        local flow = {
            search, rangeControl, sessionDropdown, qualityDropdown, zoneDropdown,
            scopeDropdown, exactToggle,
        }

        sessionDropdown:SetShown(MLH:getFilters().range == 1)
        scopeDropdown:SetShown(MLH:getCharacterCount() > 1)

        qualityDropdown:SetShown(not isCurrencyView())
        exactToggle:SetShown(not isCurrencyView())

        local placements = {}
        local rows, x = 1, 0

        for i = 1, #flow do
            local control = flow[i]

            if (control:IsShown()) then
                local width = control:GetWidth()

                if (x > 0 and x + width > available) then
                    rows = rows + 1
                    x = 0
                end

                placements[#placements+1] = { control = control, row = rows, x = x }

                x = x + width + FILTER_GAP
            end
        end

        for i = 1, #placements do
            local placement = placements[i]
            local control = placement.control
            local y = (rows - placement.row) * FILTER_ROW
            local nudge = control == exactToggle and 3 or 0

            control:ClearAllPoints()
            control:SetPoint("BOTTOMLEFT", filterBar, "BOTTOMLEFT", placement.x, y + nudge)
        end

        filterBar:SetHeight(FILTER_HEIGHT + (rows - 1) * FILTER_ROW)
    end

    layoutFilters()

    local header = CreateFrame("Frame", nil, frame)
    header:SetPoint("TOPLEFT", filterBar, "BOTTOMLEFT", -PAD + 1, -4)
    header:SetPoint("TOPRIGHT", filterBar, "BOTTOMRIGHT", PAD - 1, -4)
    header:SetHeight(HEADER_HEIGHT)

    local headerRule = header:CreateTexture(nil, "ARTWORK")
    headerRule:SetPoint("BOTTOMLEFT", PAD, 0)
    headerRule:SetPoint("BOTTOMRIGHT", -PAD, 0)
    headerRule:SetHeight(1)
    headerRule:SetColorTexture(UI:rgb("border"))

    header.quality = createHeaderColumn(header, "quality", L["R_ColQuality"], "LEFT")
    header.name = createHeaderColumn(header, "name", L["R_ColItem"], "LEFT")
    header.quantity = createHeaderColumn(header, "quantity", L["R_ColQuantity"], "RIGHT")
    header.value = createHeaderColumn(header, "value", L["R_ColValue"], "RIGHT")
    header.market = createHeaderColumn(header, "market", L["R_ColValueMarket"], "RIGHT")
    header.character = createHeaderColumn(header, "character", L["R_ColCharacter"], "LEFT")
    header.source = createHeaderColumn(header, "source", L["R_ColSource"], "LEFT")
    header.zone = createHeaderColumn(header, "zone", L["R_ColZone"], "LEFT")
    header.lastLooted = createHeaderColumn(header, "lastLooted", L["R_ColLooted"], "LEFT")

    header.earned = createHeaderColumn(header, "earned", L["R_ColEarned"], "RIGHT")
    header.perHour = createHeaderColumn(header, "perHour", L["R_ColPerHour"], "RIGHT")
    header.held = createHeaderColumn(header, "held", L["R_ColHeld"], "RIGHT")
    header.cap = createHeaderColumn(header, "cap", L["R_ColCap"], "RIGHT")

    local list = CreateFrame("Frame", nil, frame)
    list:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -2)
    list:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, FOOTER_HEIGHT + 1)
    list:SetClipsChildren(true)
    list:EnableMouseWheel(true)

    list:SetScript("OnMouseWheel", function(_, delta)
        updateScroll(scrollOffset - delta * ROW_HEIGHT * 2)
    end)

    local scrollbar = UI:scrollbar(list, function(offset)
        scrollOffset = offset
        layoutRows()
    end)
    scrollbar:SetPoint("TOPRIGHT", -3, -2)
    scrollbar:SetPoint("BOTTOMRIGHT", -3, 2)

    local empty = CreateFrame("Frame", nil, list)
    empty:SetAllPoints()

    local emptyIcon = empty:CreateTexture(nil, "ARTWORK")
    emptyIcon:SetSize(52, 52)
    emptyIcon:SetPoint("CENTER", 0, 40)
    emptyIcon:SetTexture("Interface\\Icons\\inv_misc_bag_10")
    emptyIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    emptyIcon:SetDesaturated(true)
    emptyIcon:SetAlpha(0.35)

    local emptyText = UI:text(empty, 13, "textDim")
    emptyText:SetPoint("TOP", emptyIcon, "BOTTOM", 0, -14)
    emptyText:SetJustifyH("CENTER")
    emptyText:SetText(L["R_NothingIsHereYet"])

    local emptyReset = UI:button(empty, L["R_ResetFilters"], 130, 26, function()
        MLH:resetFilters()
        window.search:SetValue("")
        refreshReport()
    end)
    emptyReset:SetPoint("TOP", emptyText, "BOTTOM", 0, -16)

    local footer = UI:panel(frame, "panel", false)
    footer:SetPoint("BOTTOMLEFT", 1, 1)
    footer:SetPoint("BOTTOMRIGHT", -1, 1)
    footer:SetHeight(FOOTER_HEIGHT)

    local footerRule = footer:CreateTexture(nil, "ARTWORK")
    footerRule:SetPoint("TOPLEFT")
    footerRule:SetPoint("TOPRIGHT")
    footerRule:SetHeight(1)
    footerRule:SetColorTexture(UI:rgb("border"))

    local footerText = UI:text(footer, 12, "textDim")
    footerText:SetPoint("LEFT", PAD, 0)

    local footerZone = UI:text(footer, 11, "textFaint")
    footerZone:SetPoint("RIGHT", -PAD - 14, 0)
    footerZone:SetJustifyH("RIGHT")

    local grip = CreateFrame("Button", nil, frame)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -2, 2)

    for i = 1, 3 do
        local pip = grip:CreateTexture(nil, "OVERLAY")
        pip:SetSize(2, 2)
        pip:SetPoint("BOTTOMRIGHT", -2 - (i - 1) * 4, 2)
        pip:SetColorTexture(UI:rgb("borderLight"))
    end

    grip:SetScript("OnMouseDown", function()
        if (not MLH.db.char.config.resizableReportWindow) then return end

        frame:StartSizing("BOTTOMRIGHT")
    end)

    grip:SetScript("OnMouseUp", function()
        frame:StopMovingOrSizing()
        saveWindowPosition()
        frame:UpdateLayout()
        refreshReport(true)
    end)

    UI:tooltip(grip, L["R_ResizeHint"])

    frame.titleBar = titleBar
    frame.statsRow = statsRow
    frame.cards = cards
    frame.graph = graph
    frame.filterBar = filterBar
    frame.viewControl = viewControl
    frame.search = search
    frame.rangeControl = rangeControl
    frame.qualityDropdown = qualityDropdown
    frame.zoneDropdown = zoneDropdown
    frame.sessionDropdown = sessionDropdown
    frame.scopeDropdown = scopeDropdown
    frame.exactToggle = exactToggle
    frame.header = header
    frame.list = list
    frame.scrollbar = scrollbar
    frame.empty = empty
    frame.emptyText = emptyText
    frame.emptyReset = emptyReset
    frame.footerText = footerText
    frame.footerZone = footerZone
    frame.grip = grip

    frame.UpdateLayout = function(self)
        local showSession = MLH.db.char.config.showSessionBar and true or false

        statsRow:SetShown(showSession)
        graph:SetShown(showSession and self:GetWidth() >= 860)

        if (showSession) then
            filterBar:SetPoint("TOPLEFT", statsRow, "BOTTOMLEFT", 0, -PAD)
            filterBar:SetPoint("TOPRIGHT", statsRow, "BOTTOMRIGHT", 0, -PAD)
        else
            filterBar:SetPoint("TOPLEFT", titleBar, "BOTTOMLEFT", PAD, -PAD)
            filterBar:SetPoint("TOPRIGHT", titleBar, "BOTTOMRIGHT", -PAD, -PAD)
        end

        local available = statsRow:GetWidth() - (graph:IsShown() and (GRAPH_WIDTH + CARD_GAP) or 0)
        local cardWidth = (available - CARD_GAP * 3) / 4
        local order = { cards.time, cards.items, cards.gold, cards.filtered }

        for i = 1, #order do
            local card = order[i]

            card:ClearAllPoints()
            card:SetPoint("TOPLEFT", statsRow, "TOPLEFT", (i - 1) * (cardWidth + CARD_GAP), 0)
            card:SetSize(cardWidth, STATS_HEIGHT)
        end

        layoutFilters()

        grip:SetShown(MLH.db.char.config.resizableReportWindow and true or false)

        updateActivity()
    end

    frame:SetScript("OnSizeChanged", function(self)
        if (not self:IsShown()) then return end

        self:UpdateLayout()
        updateScroll(scrollOffset)
    end)

    frame:SetScript("OnHide", function(self)
        saveWindowPosition()

        if (searchTimer) then
            searchTimer:Cancel()
            searchTimer = nil
        end

        if (ticker) then
            ticker:Cancel()
            ticker = nil
        end

        self.qualityDropdown:Close()
        self.zoneDropdown:Close()
        self.sessionDropdown:Close()
        self.scopeDropdown:Close()
    end)

    local fade = frame:CreateAnimationGroup()
    local alpha = fade:CreateAnimation("Alpha")
    alpha:SetFromAlpha(0)
    alpha:SetToAlpha(1)
    alpha:SetDuration(0.14)
    alpha:SetSmoothing("OUT")

    frame.fade = fade

    if (not tContains(UISpecialFrames, "MLHReportFrame")) then
        tinsert(UISpecialFrames, "MLHReportFrame")
    end

    return frame
end

local exportWindow = nil

function showExportWindow()
    -- Avoid and/or here: both the CSV and hint return values are needed.
    local csv, count

    if (isCurrencyView()) then
        csv, count = MLH:buildCurrencyCsv(report)
    else
        csv, count = MLH:buildCsv(report)
    end

    if (not exportWindow) then
        local frame = CreateFrame("Frame", "MLHExportFrame", UIParent)

        frame:SetFrameStrata("FULLSCREEN_DIALOG")
        frame:SetSize(620, 440)
        frame:SetPoint("CENTER")
        frame:SetMovable(true)
        frame:EnableMouse(true)
        frame:SetClampedToScreen(true)

        local shadow = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
        shadow:SetPoint("TOPLEFT", -6, 6)
        shadow:SetPoint("BOTTOMRIGHT", 6, -6)
        shadow:SetColorTexture(0, 0, 0, 0.5)

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

function MLH:gui()
    if (not window) then
        window = buildWindow()
    end

    if (window:IsShown()) then
        window:Hide()
        return
    end

    local saved = self.db.char.ui or {}

    window:SetSize(saved.width or DEFAULT_WIDTH, saved.height or DEFAULT_HEIGHT)
    window:ClearAllPoints()

    if (saved.point) then
        window:SetPoint(saved.point, UIParent, saved.relativePoint or saved.point, saved.x or 0, saved.y or 0)
    else
        window:SetPoint("CENTER")
    end

    window.search:SetValue(self:getFilters().search)
    window:Show()
    window:UpdateLayout()

    refreshReport()

    window.fade:Play()

    -- Fill again next frame, after anchored viewport dimensions settle.
    C_Timer.After(0, function()
        if (window and window:IsShown()) then updateScroll(scrollOffset) end
    end)

    -- Coalesce loot bursts into one refresh per tick, preserving scroll position.
    ticker = C_Timer.NewTicker(1, function()
        if (renderedRevision ~= MLH.historyRevision) then
            refreshReport(true)
            updateActivity()
        else
            updateSession()
        end

        if (time() % 30 == 0) then updateActivity() end
    end)
end
