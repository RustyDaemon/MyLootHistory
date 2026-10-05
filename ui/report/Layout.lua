--[[
My Loot History addon
Copyright (C) 2026 RustyDaemon (https://github.com/RustyDaemon)

See License file for details.
--]]

local MLH = LibStub("AceAddon-3.0"):GetAddon("MyLootHistory")

-- The report window is split over ui/report/. The files share the window's state and helpers
-- through this table, which no other part of the addon touches.
local View = {}
MLH.reportView = View

View.window = nil
View.report = nil
View.displayList = {}
View.scrollOffset = 0

View.PAD = 14
View.HEADER_HEIGHT = 24
View.ROW_HEIGHT = 40

local PAD = View.PAD

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

function View.iconSize()
    return MLH.db.char.config.reportIconSize or 24
end

function View.isCurrencyView()
    return MLH:getFilters().view == "currency"
end

function View.columnLayout()
    local config = MLH.db.char.config
    local layout = { cursor = -PAD }

    local function claim(width)
        local right = layout.cursor

        layout.cursor = layout.cursor - width - COLUMN_GAP

        return right, width
    end

    if (View.isCurrencyView()) then
        layout.capRight, layout.capWidth = claim(CURRENCY_COLUMN_WIDTH.cap)
        layout.heldRight, layout.heldWidth = claim(CURRENCY_COLUMN_WIDTH.held)
        layout.perHourRight, layout.perHourWidth = claim(CURRENCY_COLUMN_WIDTH.perHour)
        layout.earnedRight, layout.earnedWidth = claim(CURRENCY_COLUMN_WIDTH.earned)

        layout.nameLeft = PAD + 6 + View.iconSize() + 10
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

    layout.nameLeft = PAD + 6 + View.iconSize() + 10
    layout.nameRight = layout.cursor

    return layout
end

function View.sortState()
    local active = MLH:getFilters()

    if (active.view == "currency") then return active.currencySort, active.currencySortDescending end

    return active.sortKey, active.sortDescending
end
