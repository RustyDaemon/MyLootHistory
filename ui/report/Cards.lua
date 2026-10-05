--[[
My Loot History addon
Copyright (C) 2026 RustyDaemon (https://github.com/RustyDaemon)

See License file for details.
--]]

-- The stat cards and the activity graph above the filters.

local MLH = LibStub("AceAddon-3.0"):GetAddon("MyLootHistory")
local L = LibStub("AceLocale-3.0"):GetLocale("MyLootHistory")
local UI = MLH.UI
local View = MLH.reportView

local ACTIVITY_HOURS = 24

local GOLD_ICON = UI.GOLD_ICON

function View.createCard(parent, caption, accentColorName)
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

function View.createActivityGraph(parent)
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

function View.updateActivity()
    if (not View.window or not View.window.graph or not View.window.graph:IsShown()) then return end

    local graph = View.window.graph
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

function View.updateSession()
    if (not View.window or not View.window.cards) then return end

    local viewing = MLH:getFilters().range == MLH.RANGE_SESSION and MLH:getSelectedSession() or nil
    local stats = MLH:getSessionStats(viewing)
    local cards = View.window.cards

    cards.time:Set(MLH:formatDuration(stats.duration),
        stats.isLive and L["G_SinceLogin"] or L["S_PastSession"](date("%d %b %H:%M", stats.sessionStart)),
        "text")
    cards.items:Set(string.format("%.0f", stats.itemsPerHour), L["G_ItemsTotal"](stats.quantity), "text")
    cards.gold:Set(MLH:formatGoldCompact(stats.goldPerHour)..GOLD_ICON,
        L["G_ValueSoFar"](MLH:formatGoldCompact(stats.totalValue)), "money")

    if (not View.report) then return end

    if (View.isCurrencyView()) then
        cards.filtered:Set(BreakUpLargeNumbers(View.report.totalEarned),
            MLH:getRangeName(MLH:getFilters().range), "accent")
    else
        cards.filtered:Set(MLH:formatGoldCompact(View.report.totalValue + View.report.gold)..GOLD_ICON,
            MLH:getRangeName(MLH:getFilters().range), "accent")
    end
end
