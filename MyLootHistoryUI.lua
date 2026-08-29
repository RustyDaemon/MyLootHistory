--[[
My Loot History addon
Copyright (C) 2026 RustyDaemon (https://github.com/RustyDaemon)

See License file for details.
--]]

-- The report window.
--
-- It is one frame, built by hand out of the kit in MyLootHistoryUIKit and fed by
-- MyLootHistoryData, laid out as a dashboard rather than a table: the live session across
-- the top as four stat cards next to a graph of the last day, the filters under them, and
-- the loot itself in a virtualised list where every row carries a bar showing what share of
-- the session's value it is.
--
-- The list is virtualised on purpose. A character with a few thousand distinct items used to
-- get a frame per row on every redraw; here the number of frames is however many fit on
-- screen, and scrolling re-fills the same dozen.

local MLH = LibStub("AceAddon-3.0"):GetAddon("MyLootHistory")
local L = LibStub("AceLocale-3.0"):GetLocale("MyLootHistory")
local UI = MLH.UI

-- ── layout constants ──────────────────────────────────────────────────────────

local PAD = 14
local TITLE_HEIGHT = 44
local STATS_HEIGHT = 86
local FILTER_HEIGHT = 58
-- what a second line of filters adds: the control, its caption, and the gap between rows
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
    zone = 132,
    lastLooted = 124,
}

-- Every column is packed against the one to its right, and a right-aligned number followed
-- by a left-aligned word would otherwise run straight into it ("1g 0sCollegiate Calamity").
local COLUMN_GAP = 14

local MIN_WIDTH = 780
local MIN_HEIGHT = 460
local DEFAULT_WIDTH = 940
local DEFAULT_HEIGHT = 620

local ACTIVITY_HOURS = 24

-- The client's own coin, inline. A trailing "g" after a rounded figure reads as part of the
-- number ("12.3kg"); the coin reads as a unit.
local GOLD_ICON = "|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:0:-1|t"

-- The sort direction on the active column. FRIZQT__.TTF has no glyph for ▲/▼ - they come
-- out as an empty box - so these are the client's own scroll arrows, inline.
-- The arrow sits in the middle of its file with a wide transparent margin, so the last four
-- numbers crop that margin away: without them the visible arrow is a third of the size asked
-- for. (path:height:width:xoff:yoff:fileW:fileH:left:right:top:bottom)
local SORT_UP = " |TInterface\\ChatFrame\\UI-ChatIcon-ScrollUp-Up:16:16:0:-2:32:32:8:24:8:24|t"
local SORT_DOWN = " |TInterface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up:16:16:0:-2:32:32:8:24:8:24|t"

-- ── state ─────────────────────────────────────────────────────────────────────

local window = nil
local rows = {}
local displayList = {}
local report = nil
local searchTimer = nil
local ticker = nil
local scrollOffset = 0

local refreshReport, rebuildList, layoutRows, updateScroll, updateSession, updateActivity,
      updateFooter, buildWindow, saveWindowPosition, showExportWindow, columnLayout

-- ── helpers ───────────────────────────────────────────────────────────────────

local function iconSize()
    -- read five different ways once, two of them without a fallback, so a saved variable
    -- written before the setting existed left them doing arithmetic on nil
    return MLH.db.char.config.reportIconSize or 24
end

local function qualityColor(quality)
    local r, g, b = C_Item.GetItemQualityColor(quality or 0)

    return r, g, b
end

-- Where every column sits, given the width the window currently has. The header labels and
-- the row cells both lay themselves out from this, which is why they cannot drift apart
-- when a column is switched off or the window is dragged wider.
function columnLayout()
    local config = MLH.db.char.config
    local layout = { cursor = -PAD }

    local function claim(width)
        local right = layout.cursor

        layout.cursor = layout.cursor - width - COLUMN_GAP

        return right, width
    end

    if (config.showLastLooted) then
        layout.lastLootedRight, layout.lastLootedWidth = claim(COLUMN_WIDTH.lastLooted)
    end

    if (config.showZone) then
        layout.zoneRight, layout.zoneWidth = claim(COLUMN_WIDTH.zone)
    end

    -- an auction-house price source earns its own column: the vendor price is what the item
    -- is guaranteed to be worth, and replacing it would throw that number away
    if (MLH:getPriceSource() ~= "vendor") then
        layout.marketRight, layout.marketWidth = claim(COLUMN_WIDTH.market)
    end

    layout.valueRight, layout.valueWidth = claim(COLUMN_WIDTH.value)
    layout.quantityRight, layout.quantityWidth = claim(COLUMN_WIDTH.quantity)

    layout.nameLeft = PAD + 6 + iconSize() + 10
    -- the cursor already carries a gap from the last column claimed
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

-- ── stat cards ────────────────────────────────────────────────────────────────

-- A card is a label, a big number and a small footnote. Four of them carry everything the
-- old one-line session bar said, at a size that can be read from across the room - which is
-- the point, since the player is usually looking at the game and not at the report.
local function createCard(parent, caption, accentColorName)
    local card = UI:panel(parent, "panel", true)

    -- a plain frame takes no mouse input, and without it neither the hover nor the tooltip
    -- would ever fire
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

-- ── activity graph ────────────────────────────────────────────────────────────

-- One bar an hour for the last day, scaled to the busiest hour in the window. It answers
-- the question the numbers cannot: not how much you made, but when.
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
        -- an hour that earned something never draws as nothing: a 1px stub says "you were
        -- here", which is a different statement from an empty column
        bar:SetHeight(math.max(ratio * maxHeight, bucket.value > 0 and 2 or 1))

        bar.fill:SetAlpha(bucket.value > 0 and 1 or 0.25)
        bar.hourLabel = date("%H:00", bucketStart + (i - 1) * 3600)
        bar.quantity = bucket.quantity
        bar.valueText = MLH:formatGoldCompact(bucket.value)
    end
end

-- ── list rows ─────────────────────────────────────────────────────────────────

local function createRow(parent)
    local row = CreateFrame("Button", nil, parent)

    row:SetHeight(ROW_HEIGHT)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    local stripe = row:CreateTexture(nil, "BACKGROUND")
    stripe:SetAllPoints()
    stripe:SetColorTexture(1, 1, 1, 0.022)
    row.stripe = stripe

    -- how much of the filtered value this one row is, drawn as a fading bar under it.
    -- It is the fastest way to see which three things are actually paying for the session.
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
    -- the stock icon art has a 4px transparent margin baked into it; trimming it is what
    -- lets the quality border sit tight against the artwork
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
    row.zone = UI:text(row, 11, "textDim")
    row.lastLooted = UI:text(row, 11, "textDim")

    row.zone:SetWordWrap(false)
    row.lastLooted:SetWordWrap(false)

    -- the heading rows inside the list - "Currencies" and the like - reuse the same frame
    row.heading = UI:text(row, 11, "textFaint")
    row.heading:SetPoint("LEFT", PAD + 4, 0)

    row.headingRule = row:CreateTexture(nil, "ARTWORK")
    row.headingRule:SetPoint("LEFT", row.heading, "RIGHT", 8, 0)
    row.headingRule:SetPoint("RIGHT", row, "RIGHT", -PAD, 0)
    row.headingRule:SetHeight(1)
    row.headingRule:SetColorTexture(UI:rgb("border"))

    -- hooked rather than set: the hover fade above registered an OnEnter of its own, and
    -- SetScript would replace it rather than run alongside it
    row:HookScript("OnEnter", function(self)
        if (not self.entry or not MLH.db.char.config.showTooltip) then return end

        local entry = self.entry

        if (entry.kind == "item") then
            GameTooltip:SetOwner(self, "ANCHOR_NONE")
            GameTooltip:SetPoint("TOPLEFT", window, "TOPRIGHT", 6, 0)

            -- the rows below say the same thing in more detail, so the global tooltip line
            -- stays out of the report's own tooltip
            MLH:setTooltipSuppressed(true)

            -- A record written by an old version can carry no link, and the client only
            -- hands one back for an item it has cached. SetHyperlink(nil) errors, so the ID
            -- is the fallback: it says the same thing and every record has one.
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
            end

            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(L["R_ShiftClickToLink"], UI:rgb("textFaint"))
            GameTooltip:Show()
        elseif (entry.kind == "currency") then
            GameTooltip:SetOwner(self, "ANCHOR_NONE")
            GameTooltip:SetPoint("TOPLEFT", window, "TOPRIGHT", 6, 0)
            GameTooltip:SetCurrencyByID(entry.currency.currencyId)
            GameTooltip:Show()
        end
    end)

    row:HookScript("OnLeave", function() GameTooltip:Hide() end)

    row:SetScript("OnClick", function(self)
        local entry = self.entry

        if (not entry) then return end

        if (IsLeftShiftKeyDown() or IsRightShiftKeyDown()) then
            local link = entry.kind == "item" and entry.item.itemLink
                or (entry.kind == "currency"
                    and C_CurrencyInfo.GetCurrencyLink(entry.currency.currencyId, entry.currency.quantity))

            if (link) then ChatEdit_TryInsertChatLink(link) end
        end
    end)

    return row
end

-- Fills one pooled row from one display entry. Everything a row can be - an item, a
-- currency, the gold line, a section heading - is set up here, because a pooled frame that
-- was something else last frame has to be fully re-dressed rather than patched.
local function fillRow(row, entry, index, layout)
    row.entry = entry

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
        row.zone:Hide()
        row.lastLooted:Hide()
        row.heat:SetWidth(1)
        row.heat:Hide()

        return
    end

    row.heat:Show()

    local size = iconSize()

    row.iconBorder:SetSize(size + 2, size + 2)
    row.icon:SetSize(size, size)

    -- name and subtitle: one centred line when there is nothing to say underneath, two
    -- stacked lines when there is
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
        -- a dash rather than a zero: the auction house having no price for an item is not
        -- the same as the item being worthless
        row.market:SetText(item.marketValue and MLH:formatMoneyShort(item.marketValue) or "-")
        row.market:SetAlpha(item.marketValue and 1 or 0.35)
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
        -- currencies have no vendor value and no auction price, so the column stays empty
        -- rather than claiming they are worth nothing
        row.value:SetText("")
        row.value:SetAlpha(1)
        row.market:SetText("")
        row.zone:SetText(currency.zoneName)
        row.lastLooted:SetText("")

        if (not config.showZone) then subtitleParts[#subtitleParts+1] = currency.zoneName end

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
    applyCell(row.zone, layout.zoneRight, layout.zoneWidth, "LEFT")
    applyCell(row.lastLooted, layout.lastLootedRight, layout.lastLootedWidth, "LEFT")
end

-- ── the list ──────────────────────────────────────────────────────────────────

-- Flattens the report into the sequence of rows the list scrolls through. Items first,
-- then the currencies under their own heading, then the gold the range earned.
function rebuildList()
    displayList = {}

    for i = 1, #report.items do
        displayList[#displayList+1] = { kind = "item", item = report.items[i] }
    end

    if (#report.currencies > 0) then
        displayList[#displayList+1] = { kind = "heading", text = L["R_Currencies"] }

        for i = 1, #report.currencies do
            displayList[#displayList+1] = { kind = "currency", currency = report.currencies[i] }
        end
    end

    if (report.gold > 0) then
        displayList[#displayList+1] = { kind = "heading", text = L["R_Money"] }
        displayList[#displayList+1] = { kind = "gold", gold = report.gold }
    end
end

-- Draws whatever is under the current scroll offset. The pool is as tall as the viewport
-- plus one row, and grows only when the window is dragged taller.
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

-- ── header ────────────────────────────────────────────────────────────────────

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
        if (MLH:getFilters().sortKey ~= self.key) then self.label:SetTextColor(UI:rgb("text")) end

        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(L["R_SortBy"](self.baseText), 1, 1, 1)
        GameTooltip:Show()
    end)

    button:HookScript("OnLeave", function(self)
        if (MLH:getFilters().sortKey ~= self.key) then self.label:SetTextColor(UI:rgb("textDim")) end

        GameTooltip:Hide()
    end)

    button:SetScript("OnClick", function(self)
        local active = MLH:getFilters()

        if (active.sortKey == self.key) then
            MLH:setFilter("sortDescending", not active.sortDescending)
        else
            MLH:setFilter("sortKey", self.key)
            -- names and places read best A-Z, everything else reads best largest-first
            MLH:setFilter("sortDescending", self.key ~= "name" and self.key ~= "zone")
        end

        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        refreshReport()
    end)

    return button
end

local function refreshHeader()
    local active = MLH:getFilters()
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
    place(header.zone, layout.zoneRight, layout.zoneWidth, "LEFT")
    place(header.lastLooted, layout.lastLootedRight, layout.lastLootedWidth, "LEFT")

    header.quality:ClearAllPoints()
    header.quality:SetPoint("LEFT", header, "LEFT", PAD + 4, 0)
    header.quality:SetWidth(iconSize() + 4)

    header.zone:SetShown(config.showZone and true or false)
    header.lastLooted:SetShown(config.showLastLooted and true or false)

    for _, button in pairs({ header.quality, header.name, header.quantity, header.value,
                             header.market, header.zone, header.lastLooted }) do
        local isActive = active.sortKey == button.key
        local arrow = isActive and (active.sortDescending and SORT_DOWN or SORT_UP) or ""

        button.label:SetText(button.baseText..arrow)
        button.label:SetTextColor(UI:rgbIf(isActive, "accent", "textDim"))
        button.underline:SetShown(isActive)
    end
end

-- ── session and footer ────────────────────────────────────────────────────────

function updateSession()
    if (not window or not window.cards) then return end

    local stats = MLH:getSessionStats()
    local cards = window.cards

    cards.time:Set(MLH:formatDuration(stats.duration), L["G_SinceLogin"], "text")
    cards.items:Set(string.format("%.0f", stats.itemsPerHour), L["G_ItemsTotal"](stats.quantity), "text")
    cards.gold:Set(MLH:formatGoldCompact(stats.goldPerHour)..GOLD_ICON,
        L["G_ValueSoFar"](MLH:formatGoldCompact(stats.totalValue)), "money")

    if (report) then
        cards.filtered:Set(MLH:formatGoldCompact(report.totalValue + report.gold)..GOLD_ICON,
            MLH:getRangeName(MLH:getFilters().range), "accent")
    end
end

function updateFooter()
    if (not window or not report) then return end

    local parts = {
        L["R_Items"]..("|cFFFFFFFF"..#report.items.."|r"),
        L["R_Quantity"]..("|cFFFFFFFF"..report.totalQuantity.."|r"),
        L["R_SellPrice"]..GetMoneyString(report.totalVendorValue),
    }

    -- with an auction-house source on, the two value columns get a total each: the vendor
    -- one covers every row, the market one only the rows that had a price
    if (MLH:getPriceSource() ~= "vendor") then
        parts[#parts+1] = L["R_MarketPrice"]..GetMoneyString(report.totalMarketValue)
    end

    if (#report.currencies > 0) then
        parts[#parts+1] = L["R_CurrenciesCount"].."|cFFFFFFFF"..#report.currencies.."|r"
    end

    window.footerText:SetText(table.concat(parts, "   |cFF4A4A55|||r   "))

    local topZone = report.zones[1]

    window.footerZone:SetText(topZone and L["R_MostlyFrom"](topZone.name) or "")
end

-- ── refresh ───────────────────────────────────────────────────────────────────

function refreshReport(keepScroll)
    if (not window) then return end

    -- an auction-house price can move while the window is open, so each redraw asks again
    MLH:clearPriceCache()

    report = MLH:buildReport()

    rebuildList()
    refreshHeader()

    if (not keepScroll) then scrollOffset = 0 end

    local isEmpty = #displayList == 0

    window.empty:SetShown(isEmpty)
    window.emptyReset:SetShown(isEmpty and MLH:hasActiveFilters())
    window.header:SetShown(not isEmpty)

    updateScroll(scrollOffset)
    updateSession()
    updateFooter()

    window.zoneDropdown:SetText(MLH:getZoneFilterName())
    window.qualityDropdown:SetText(MLH:getQualityName(MLH:getFilters().quality))
    window.rangeControl:Refresh()
    window.exactToggle:Refresh()
end

-- The window rebuilds itself when a setting it draws from changes, so the options panel
-- does not have to be closed and the report reopened to see the effect.
function MLH:refreshReport()
    if (not window or not window:IsShown()) then return end

    window.statsRow:SetShown(self.db.char.config.showSessionBar and true or false)
    window:UpdateLayout()
    refreshReport(true)
end

-- ── window ────────────────────────────────────────────────────────────────────

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

    -- a soft drop shadow, so the window sits on top of the game world rather than in it
    local shadow = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    shadow:SetPoint("TOPLEFT", -6, 6)
    shadow:SetPoint("BOTTOMRIGHT", 6, -6)
    shadow:SetColorTexture(0, 0, 0, 0.45)

    local bg = frame:CreateTexture(nil, "BACKGROUND", nil, -7)
    bg:SetAllPoints()
    bg:SetColorTexture(UI:rgb("window", 0.97))

    UI:addBorder(frame, UI:rgb("borderLight"))

    -- title bar ---------------------------------------------------------------
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

    -- stat cards ---------------------------------------------------------------
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

    -- the session card is also the reset button: the number it shows is the thing being
    -- reset, so there is nowhere better to put it
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

    -- filters ------------------------------------------------------------------
    local filterBar = CreateFrame("Frame", nil, frame)
    filterBar:SetPoint("TOPLEFT", statsRow, "BOTTOMLEFT", 0, -PAD)
    filterBar:SetPoint("TOPRIGHT", statsRow, "BOTTOMRIGHT", 0, -PAD)
    filterBar:SetHeight(FILTER_HEIGHT)

    local search = UI:searchBox(filterBar, 190, 26, L["R_SearchPlaceholder"], function(text, userInput)
        if (not userInput) then return end

        MLH:setFilter("search", text)

        -- rebuilding the list on every keystroke is wasteful on a long history, so the
        -- redraw waits until the typing stops
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
    local exactToggle = UI:toggle(filterBar, L["R_ExactItemQuality"],
        function() return MLH:getFilters().exactQuality end,
        function(value)
            MLH:setFilter("exactQuality", value)
            refreshReport()
        end)

    -- The five filters are sized by their own text - the date range alone is six buttons -
    -- and at the narrow end of the window they do not fit on one line. Rather than let the
    -- tail of the row hang outside the frame, the quality/zone/exact group drops to a
    -- second line and the bar grows to hold it.
    local function layoutFilters()
        local available = filterBar:GetWidth()
        local left = search:GetWidth() + FILTER_GAP + rangeControl:GetWidth()
        local right = qualityDropdown:GetWidth() + FILTER_GAP + zoneDropdown:GetWidth()
            + FILTER_GAP + 2 + exactToggle:GetWidth()
        local oneRow = left + FILTER_GAP + right <= available

        search:ClearAllPoints()
        rangeControl:ClearAllPoints()
        qualityDropdown:ClearAllPoints()
        zoneDropdown:ClearAllPoints()
        exactToggle:ClearAllPoints()

        search:SetPoint("BOTTOMLEFT", filterBar, "BOTTOMLEFT", 0, oneRow and 0 or FILTER_ROW)
        rangeControl:SetPoint("BOTTOMLEFT", search, "BOTTOMRIGHT", FILTER_GAP, 0)

        if (oneRow) then
            qualityDropdown:SetPoint("BOTTOMLEFT", rangeControl, "BOTTOMRIGHT", FILTER_GAP, 0)
        else
            qualityDropdown:SetPoint("BOTTOMLEFT", filterBar, "BOTTOMLEFT", 0, 0)
        end

        zoneDropdown:SetPoint("BOTTOMLEFT", qualityDropdown, "BOTTOMRIGHT", FILTER_GAP, 0)
        exactToggle:SetPoint("BOTTOMLEFT", zoneDropdown, "BOTTOMRIGHT", FILTER_GAP + 2, 3)

        filterBar:SetHeight(oneRow and FILTER_HEIGHT or (FILTER_HEIGHT + FILTER_ROW))
    end

    layoutFilters()

    -- column header ------------------------------------------------------------
    local header = CreateFrame("Frame", nil, frame)
    header:SetPoint("TOPLEFT", filterBar, "BOTTOMLEFT", -PAD + 1, -4)
    header:SetPoint("TOPRIGHT", filterBar, "BOTTOMRIGHT", PAD - 1, -4)
    header:SetHeight(HEADER_HEIGHT)

    local headerRule = header:CreateTexture(nil, "ARTWORK")
    headerRule:SetPoint("BOTTOMLEFT", PAD, 0)
    headerRule:SetPoint("BOTTOMRIGHT", -PAD, 0)
    headerRule:SetHeight(1)
    headerRule:SetColorTexture(UI:rgb("border"))

    -- the icon column has no name of its own, so it carries the quality sort
    header.quality = createHeaderColumn(header, "quality", L["R_ColQuality"], "LEFT")
    header.name = createHeaderColumn(header, "name", L["R_ColItem"], "LEFT")
    header.quantity = createHeaderColumn(header, "quantity", L["R_ColQuantity"], "RIGHT")
    header.value = createHeaderColumn(header, "value", L["R_ColValue"], "RIGHT")
    header.market = createHeaderColumn(header, "market", L["R_ColValueMarket"], "RIGHT")
    header.zone = createHeaderColumn(header, "zone", L["R_ColZone"], "LEFT")
    header.lastLooted = createHeaderColumn(header, "lastLooted", L["R_ColLooted"], "LEFT")

    -- list ---------------------------------------------------------------------
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

    -- empty state --------------------------------------------------------------
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

    -- footer -------------------------------------------------------------------
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

    -- resize grip --------------------------------------------------------------
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

    -- assembly -----------------------------------------------------------------
    frame.titleBar = titleBar
    frame.statsRow = statsRow
    frame.cards = cards
    frame.graph = graph
    frame.filterBar = filterBar
    frame.search = search
    frame.rangeControl = rangeControl
    frame.qualityDropdown = qualityDropdown
    frame.zoneDropdown = zoneDropdown
    frame.exactToggle = exactToggle
    frame.header = header
    frame.list = list
    frame.scrollbar = scrollbar
    frame.empty = empty
    frame.emptyReset = emptyReset
    frame.footerText = footerText
    frame.footerZone = footerZone
    frame.grip = grip

    -- The card row is the only part whose geometry depends on the window width, since the
    -- cards share whatever the graph does not take. Everything else is anchored to two
    -- edges and follows the frame on its own.
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
    end)

    -- a short fade rather than a hard pop, which is what makes the window feel attached to
    -- the click that opened it
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

-- ── export ────────────────────────────────────────────────────────────────────

local exportWindow = nil

function showExportWindow()
    local csv, count = MLH:buildCsv(report)

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
        -- the text is a read-only view of the report: typing in it would only make the
        -- copy wrong, so every edit puts it straight back
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

-- ── entry point ───────────────────────────────────────────────────────────────

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

    -- The list is sized by its anchors, and on the very first frame after Show that height
    -- can still be the one it was created with, which would fill the viewport with a single
    -- row. One more pass next frame, once the layout has settled, costs nothing.
    C_Timer.After(0, function()
        if (window and window:IsShown()) then updateScroll(scrollOffset) end
    end)

    -- the session numbers and the graph keep moving while the window sits open
    ticker = C_Timer.NewTicker(1, function()
        updateSession()

        -- the graph only changes shape once a minute at most, and redrawing 24 bars every
        -- second for an hour is a waste of the frame budget
        if (time() % 30 == 0) then updateActivity() end
    end)
end
