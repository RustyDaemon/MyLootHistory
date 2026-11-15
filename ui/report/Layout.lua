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

-- How narrow the text columns may get when the Item column needs their room. They cut their text short
-- rather than push the item names out of sight; the numbers keep their full width.
local COLUMN_MIN_WIDTH = {
    character = 72,
    source = 84,
    zone = 84,
    lastLooted = 84,
}

-- The Item column never gets narrower than this: the text columns give way first, and the window's
-- minimum width grows so that, with every column on, the item names still have this much room.
View.NAME_MIN_WIDTH = 180

local COLUMN_GAP = 14

-- The report window's minimum width with only a few columns on.
local BASE_MIN_WIDTH = 780

-- The header and the rows span the window less its 1px border on each side.
local WINDOW_BORDER = 2

function View.iconSize()
    return MLH.db.char.config.reportIconSize or 24
end

function View.isCurrencyView()
    return MLH:getFilters().view == "currency"
end

local function nameLeft()
    return PAD + 6 + View.iconSize() + 10
end

local CURRENCY_COLUMNS = { "cap", "held", "perHour", "earned" }

-- The current table's columns from the right edge in, with the widths they want.
local function viewColumns()
    if (View.isCurrencyView()) then return CURRENCY_COLUMNS, CURRENCY_COLUMN_WIDTH end

    local config = MLH.db.char.config
    local columns = {}

    if (config.showLastLooted) then columns[#columns+1] = "lastLooted" end
    if (MLH:getScope() == "account") then columns[#columns+1] = "character" end
    if (config.showZone) then columns[#columns+1] = "zone" end
    if (config.showSource) then columns[#columns+1] = "source" end
    if (MLH:getPriceSource() ~= "vendor") then columns[#columns+1] = "market" end

    columns[#columns+1] = "value"
    columns[#columns+1] = "quantity"

    return columns, COLUMN_WIDTH
end

-- What the columns, their gaps and the margins take, at the given widths.
local function claimedWidth(columns, widths)
    local total = PAD + nameLeft()

    for i = 1, #columns do
        total = total + widths[columns[i]] + COLUMN_GAP
    end

    return total
end

-- The width each column gets, narrowed as far as the Item column needs and the text columns allow.
local function columnWidths(columns, preferred, tableWidth)
    local widths = {}
    local slack = 0

    for i = 1, #columns do
        local key = columns[i]

        widths[key] = preferred[key]
        slack = slack + (preferred[key] - (COLUMN_MIN_WIDTH[key] or preferred[key]))
    end

    local shortage = View.NAME_MIN_WIDTH - (tableWidth - claimedWidth(columns, widths))

    if (shortage <= 0 or slack <= 0) then return widths end

    -- Each text column gives up the same share of what it could spare.
    local share = math.min(shortage / slack, 1)

    for i = 1, #columns do
        local key = columns[i]
        local minimum = COLUMN_MIN_WIDTH[key]

        if (minimum) then
            widths[key] = math.floor(preferred[key] - (preferred[key] - minimum) * share)
        end
    end

    return widths
end

-- The narrowest the window can be with the current table's columns and the Item column at its minimum.
function View.minimumWidth()
    local columns, preferred = viewColumns()
    local widths = {}

    for i = 1, #columns do
        widths[columns[i]] = COLUMN_MIN_WIDTH[columns[i]] or preferred[columns[i]]
    end

    local needed = claimedWidth(columns, widths) + View.NAME_MIN_WIDTH + WINDOW_BORDER

    return math.max(BASE_MIN_WIDTH, math.ceil(needed))
end

-- The rows ask for the layout on every scroll step and every frame of a resize, so it is kept until
-- something it depends on changes.
local cachedLayout, cachedKey = nil, nil

local function layoutKey(tableWidth)
    local config = MLH.db.char.config

    return table.concat({
        tableWidth, MLH:getFilters().view, MLH:getScope(), MLH:getPriceSource(), View.iconSize(),
        tostring(config.showLastLooted), tostring(config.showZone), tostring(config.showSource),
    }, ":")
end

function View.columnLayout()
    local tableWidth = (View.window and View.window:GetWidth() or 0) - WINDOW_BORDER
    local key = layoutKey(tableWidth)

    if (cachedLayout and cachedKey == key) then return cachedLayout end

    local layout = { cursor = -PAD, nameLeft = nameLeft() }
    local columns, preferred = viewColumns()
    local widths = columnWidths(columns, preferred, tableWidth)

    for i = 1, #columns do
        local column = columns[i]
        local width = widths[column]

        layout[column.."Right"], layout[column.."Width"] = layout.cursor, width
        layout.cursor = layout.cursor - width - COLUMN_GAP
    end

    layout.nameRight = layout.cursor
    layout.nameWidth = tableWidth + layout.nameRight - layout.nameLeft

    cachedLayout, cachedKey = layout, key

    return layout
end

function View.sortState()
    local active = MLH:getFilters()

    if (active.view == "currency") then return active.currencySort, active.currencySortDescending end

    return active.sortKey, active.sortDescending
end
