--[[
My Loot History addon
Copyright (C) 2026 RustyDaemon (https://github.com/RustyDaemon)

See License file for details.
--]]

local MLH = LibStub("AceAddon-3.0"):GetAddon("MyLootHistory")
local L = LibStub("AceLocale-3.0"):GetLocale("MyLootHistory")

-- Auction-house prices are optional: Auctionator is not a dependency, and the vendor price
-- is always the fallback, so a character without it behaves exactly as it did before.
local sources = {
    vendor = {
        label = "S_PriceVendor",
        isAvailable = function() return true end,
        getPrice = function(_, vendorPrice) return vendorPrice end,
    },
    auctionator = {
        label = "S_PriceAuctionator",
        isAvailable = function()
            return Auctionator ~= nil and Auctionator.API ~= nil and Auctionator.API.v1 ~= nil
                and Auctionator.API.v1.GetAuctionPriceByItemID ~= nil
        end,
        getPrice = function(itemID)
            local ok, price = pcall(Auctionator.API.v1.GetAuctionPriceByItemID, "MyLootHistory", itemID)

            return ok and price or nil
        end,
    },
}

-- One price per item per redraw. An auction-house lookup is far more expensive than reading
-- a cached vendor price, and the report asks for the same items over and over.
local priceCache = {}
local priceCacheSource = nil

function MLH:getPriceSources()
    local list = {}

    for key, source in pairs(sources) do
        local name = L[source.label]

        list[key] = source.isAvailable() and name or (name.." "..L["S_PriceUnavailable"])
    end

    return list
end

function MLH:getPriceSource()
    local key = self.db.char.config.priceSource or "vendor"
    local source = sources[key]

    if (not source or not source.isAvailable()) then
        return "vendor", sources.vendor
    end

    return key, source
end

-- Drops the cached prices. Called when the source changes and whenever the report is
-- redrawn, so a price that moved between two openings of the window is picked up.
function MLH:clearPriceCache()
    priceCache = {}
    priceCacheSource = nil
end

-- The unit price of an item under the active source, falling back to the vendor price the
-- caller already has whenever the source has nothing to say about the item.
function MLH:getItemPrice(itemID, vendorPrice)
    vendorPrice = vendorPrice or 0

    local key, source = self:getPriceSource()

    if (key == "vendor") then return vendorPrice end

    if (priceCacheSource ~= key) then
        priceCache = {}
        priceCacheSource = key
    end

    local cached = priceCache[itemID]

    if (cached == nil) then
        cached = source.getPrice(itemID) or false
        priceCache[itemID] = cached
    end

    if (cached and cached > 0) then return cached end

    return vendorPrice
end
