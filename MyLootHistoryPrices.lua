--[[
My Loot History addon
Copyright (C) 2026 RustyDaemon (https://github.com/RustyDaemon)

See License file for details.
--]]

local MLH = LibStub("AceAddon-3.0"):GetAddon("MyLootHistory")
local L = LibStub("AceLocale-3.0"):GetLocale("MyLootHistory")

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
        -- Query the full item link first to preserve bonus IDs and item levels.
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

function MLH:clearPriceCache()
    priceCache = {}
    priceCacheSource = nil
end

-- The second return value indicates fallback to the vendor price.
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
