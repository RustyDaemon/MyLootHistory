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
        -- Auctionator keys its database by item link, so anything whose link carries more than
        -- the ID - gear with an item level, anything with a bonus ID - is only found that way.
        -- The ID lookup stays as the fallback: it is all a stored record without a link has.
        getPrice = function(itemID, itemLink)
            local api = Auctionator.API.v1

            if (itemLink and api.GetAuctionPriceByItemLink) then
                local ok, price = pcall(api.GetAuctionPriceByItemLink, "MyLootHistory", itemLink)

                if (ok and price) then return price end
            end

            local ok, price = pcall(api.GetAuctionPriceByItemID, "MyLootHistory", itemID)

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
-- caller already has whenever the source has nothing to say about the item - which is the
-- common case for soulbound gear, and for anything the auction house has not seen since the
-- last scan. The second return marks that fallback, so a row showing a vendor price under an
-- auction-house source can say so rather than looking like a market price of a few silver.
function MLH:getItemPrice(itemID, vendorPrice, itemLink)
    vendorPrice = vendorPrice or 0

    local key, source = self:getPriceSource()

    if (key == "vendor") then return vendorPrice, false end

    if (priceCacheSource ~= key) then
        priceCache = {}
        priceCacheSource = key
    end

    local cached = priceCache[itemID]

    if (cached == nil) then
        cached = source.getPrice(itemID, itemLink) or false
        priceCache[itemID] = cached
    end

    if (cached and cached > 0) then return cached, false end

    return vendorPrice, true
end
