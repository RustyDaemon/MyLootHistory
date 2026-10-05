--[[
My Loot History addon
Copyright (C) 2026 RustyDaemon (https://github.com/RustyDaemon)

See License file for details.
--]]

local MLH = LibStub("AceAddon-3.0"):GetAddon("MyLootHistory")

-- Items hidden from the report, shared by every character: item id -> the name it was hidden under.
-- Their loot is still recorded, so unhiding one brings its whole history back.
function MLH:getHiddenItems()
    self.db.global = self.db.global or {}
    self.db.global.hiddenItems = self.db.global.hiddenItems or {}

    return self.db.global.hiddenItems
end

function MLH:isItemHidden(itemID)
    return itemID ~= nil and self:getHiddenItems()[itemID] ~= nil
end

function MLH:setItemHidden(itemID, hidden, itemName)
    if (not itemID) then return end

    self:getHiddenItems()[itemID] = hidden and (itemName or C_Item.GetItemInfo(itemID) or ("#"..itemID)) or nil
    self:bumpRevision()
end

-- The hidden items by name, for the settings page: { itemId, name }.
function MLH:getHiddenItemList()
    local list = {}

    for itemID, name in pairs(self:getHiddenItems()) do
        list[#list+1] = { itemId = itemID, name = C_Item.GetItemInfo(itemID) or name }
    end

    table.sort(list, function(l, r) return l.name < r.name end)

    return list
end
