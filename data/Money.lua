--[[
My Loot History addon
Copyright (C) 2026 RustyDaemon (https://github.com/RustyDaemon)

See License file for details.
--]]

-- Copper amounts as short text, for the report, the HUD and the stat cards.

local MLH = LibStub("AceAddon-3.0"):GetAddon("MyLootHistory")

function MLH:formatMoneyShort(copper)
    copper = copper or 0

    local gold = math.floor(copper / 10000)
    local silver = math.floor(copper % 10000 / 100)
    local rest = math.floor(copper % 100)

    if (gold > 0) then
        return gold.."|cFFFFD700g|r "..silver.."|cFFC7C7CFs|r"
    end

    if (silver > 0) then
        return silver.."|cFFC7C7CFs|r "..rest.."|cFFEDA55Fc|r"
    end

    return rest.."|cFFEDA55Fc|r"
end

function MLH:formatGoldCompact(copper)
    local gold = math.floor((copper or 0) / 10000)

    if (gold >= 1000000) then
        return string.format("%.1fm", gold / 1000000)
    end

    if (gold >= 10000) then
        return string.format("%.1fk", gold / 1000)
    end

    local text = tostring(gold)
    local separated = text:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")

    return separated
end
