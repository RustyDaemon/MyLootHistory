--[[
My Loot History addon
Copyright (C) 2026 RustyDaemon (https://github.com/RustyDaemon)

See License file for details.
--]]

-- The report as CSV, for the export window.

local MLH = LibStub("AceAddon-3.0"):GetAddon("MyLootHistory")

local function csvField(value)
    value = tostring(value or "")

    if (value:find('[,"\n]')) then
        return '"'..value:gsub('"', '""')..'"'
    end

    return value
end

local function csvDate(timestamp)
    return timestamp and date("%Y-%m-%d %H:%M:%S", timestamp) or ""
end

local function csvTally(entries)
    local parts = {}

    for i = 1, #entries do
        parts[i] = entries[i].name.." ("..entries[i].quantity..")"
    end

    return table.concat(parts, "; ")
end

function MLH:buildCsv(report)
    report = report or self:buildReport()

    local items = report.items
    local lines = {
        "type,name,id,quality,quantity,value,marketValue,source,character,zone,firstLooted,lastLooted",
    }

    for i = 1, #items do
        local item = items[i]
        local qualityName = _G["ITEM_QUALITY"..(item.quality or 0).."_DESC"] or tostring(item.quality or 0)

        lines[#lines+1] = table.concat({
            "item",
            csvField(item.itemName),
            csvField(item.itemId),
            csvField(qualityName),
            csvField(item.totalQuantity),
            csvField(item.vendorValue or item.totalValue),
            item.marketValue and csvField(item.marketValue) or "",
            csvField(csvTally(item.sources or {})),
            csvField(csvTally(item.characters or {})),
            csvField(csvTally(item.zones)),
            csvField(csvDate(item.firstFound)),
            csvField(csvDate(item.lastFound)),
        }, ",")
    end

    return table.concat(lines, "\n"), #items
end

function MLH:buildCurrencyCsv(report)
    report = report or self:buildCurrencyReport()

    local rows = report.rows
    local lines = {
        "name,id,earned,perHour,held,capType,capCurrent,capMax,zone,firstLooted,lastLooted",
    }

    for i = 1, #rows do
        local row = rows[i]
        local cap = row.cap

        lines[#lines+1] = table.concat({
            csvField(row.name),
            csvField(row.currencyId),
            csvField(row.quantity),
            csvField(string.format("%.2f", row.perHour or 0)),
            row.held and csvField(row.held) or "",
            cap and csvField(cap.kind) or "",
            cap and csvField(cap.current) or "",
            cap and csvField(cap.max) or "",
            csvField(csvTally(row.zones)),
            csvField(csvDate(row.firstFound)),
            csvField(csvDate(row.lastFound)),
        }, ",")
    end

    return table.concat(lines, "\n"), #rows
end
