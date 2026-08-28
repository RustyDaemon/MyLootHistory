--[[
MLH:aggregateLoot is what the report rows, the CSV export and the game tooltip all
now agree through, so a mistake here shows up in three places at once and in none
of them obviously - a quantity that is quietly wrong looks exactly like a quantity
that is right.

The stub names any zone id below 900 and refuses the rest, standing in for a zone
a patch has removed. Ids are not reused between tests: getZoneName memoises, so a
shared id would carry one test's answer into the next.
--]]

local wow = require("tests.support.wow")

wow.load("MyLootHistory.lua")

local MLH = wow.addon

local UNKNOWN = "Unknown zone"

_G.C_Map.GetMapInfo = function(id)
    if (id >= 900) then return nil end

    return { name = "Zone "..tostring(id) }
end

local function entry(quantity, zoneID, foundOn)
    return { quantity = quantity, zoneID = zoneID, foundOn = foundOn }
end

local function zoneNames(zones)
    local names = {}

    for i = 1, #zones do names[i] = zones[i].name end

    return names
end

describe("MLH:aggregateLoot quantities", function()
    it("returns zero for an empty list", function()
        local quantity, zones, firstFound, lastFound = MLH:aggregateLoot({}, UNKNOWN)

        assert.are.equal(0, quantity)
        assert.are.equal(0, #zones)
        assert.is_nil(firstFound)
        assert.is_nil(lastFound)
    end)

    it("sums the quantities looted, not the number of loot events", function()
        local quantity = MLH:aggregateLoot({
            entry(3, 1, 100), entry(7, 1, 200), entry(5, 1, 300),
        }, UNKNOWN)

        assert.are.equal(15, quantity)
    end)

    it("counts an entry with no quantity as one", function()
        -- a record written by a very old version can be missing the field
        local quantity = MLH:aggregateLoot({ entry(nil, 1, 100), entry(2, 1, 200) }, UNKNOWN)

        assert.are.equal(3, quantity)
    end)

    it("accepts a quantity stored as a string", function()
        local quantity = MLH:aggregateLoot({ entry("4", 1, 100) }, UNKNOWN)

        assert.are.equal(4, quantity)
    end)
end)

describe("MLH:aggregateLoot zones", function()
    it("groups entries by zone and orders them busiest first", function()
        local _, zones = MLH:aggregateLoot({
            entry(1, 10, 100),
            entry(5, 11, 200),
            entry(2, 10, 300),
            entry(9, 12, 400),
        }, UNKNOWN)

        assert.are.same({ "Zone 12", "Zone 11", "Zone 10" }, zoneNames(zones))
        assert.are.equal(9, zones[1].quantity)
        assert.are.equal(5, zones[2].quantity)
        assert.are.equal(3, zones[3].quantity)
    end)

    it("breaks a tie on quantity by zone name, so the order is stable", function()
        -- the report and the tooltip are redrawn constantly; two zones with the same
        -- count must not swap places between one redraw and the next
        local _, first = MLH:aggregateLoot({ entry(4, 21, 100), entry(4, 20, 200) }, UNKNOWN)
        local _, second = MLH:aggregateLoot({ entry(4, 20, 100), entry(4, 21, 200) }, UNKNOWN)

        assert.are.same({ "Zone 20", "Zone 21" }, zoneNames(first))
        assert.are.same(zoneNames(first), zoneNames(second))
    end)

    it("groups unnameable zones under the label it is given", function()
        local quantity, zones = MLH:aggregateLoot({
            entry(2, 30, 100),
            entry(6, 901, 200),
            entry(1, 902, 300),
        }, UNKNOWN)

        assert.are.equal(9, quantity)
        assert.are.same({ UNKNOWN, "Zone 30" }, zoneNames(zones))
        assert.are.equal(7, zones[1].quantity)
    end)

    it("leaves unnameable zones out of the tally when given no label", function()
        -- what the game tooltip wants: it has room for one zone, and "unknown" says
        -- less than showing no zone at all
        local quantity, zones = MLH:aggregateLoot({
            entry(2, 40, 100),
            entry(6, 903, 200),
        }, nil)

        -- the quantity still counts it: the item really was looted
        assert.are.equal(8, quantity)
        assert.are.same({ "Zone 40" }, zoneNames(zones))
    end)

    it("returns no zones at all when none of them can be named", function()
        local quantity, zones = MLH:aggregateLoot({ entry(3, 904, 100) }, nil)

        assert.are.equal(3, quantity)
        assert.are.equal(0, #zones)
    end)

    it("ignores an entry with no zone id", function()
        local quantity, zones = MLH:aggregateLoot({ entry(2, nil, 100), entry(1, 50, 200) }, nil)

        assert.are.equal(3, quantity)
        assert.are.same({ "Zone 50" }, zoneNames(zones))
    end)
end)

describe("MLH:aggregateLoot timestamps", function()
    it("finds the earliest and latest timestamps", function()
        local _, _, firstFound, lastFound = MLH:aggregateLoot({
            entry(1, 1, 500), entry(1, 1, 100), entry(1, 1, 900), entry(1, 1, 300),
        }, UNKNOWN)

        assert.are.equal(100, firstFound)
        assert.are.equal(900, lastFound)
    end)

    it("does not assume the entries are in time order", function()
        -- collectItems sorts before calling, collectCurrencies does not
        local _, _, firstFound, lastFound = MLH:aggregateLoot({
            entry(1, 1, 900), entry(1, 1, 100),
        }, UNKNOWN)

        assert.are.equal(100, firstFound)
        assert.are.equal(900, lastFound)
    end)

    it("reports the same moment for both when there is one entry", function()
        local _, _, firstFound, lastFound = MLH:aggregateLoot({ entry(1, 1, 750) }, UNKNOWN)

        assert.are.equal(750, firstFound)
        assert.are.equal(750, lastFound)
    end)

    it("skips entries with no timestamp rather than reporting nil", function()
        local quantity, _, firstFound, lastFound = MLH:aggregateLoot({
            entry(1, 1, nil), entry(1, 1, 400), entry(1, 1, nil), entry(1, 1, 800),
        }, UNKNOWN)

        assert.are.equal(4, quantity)
        assert.are.equal(400, firstFound)
        assert.are.equal(800, lastFound)
    end)

    it("returns nil timestamps when no entry has one", function()
        local _, _, firstFound, lastFound = MLH:aggregateLoot({ entry(2, 1, nil) }, UNKNOWN)

        assert.is_nil(firstFound)
        assert.is_nil(lastFound)
    end)
end)

describe("MLH:aggregateLoot does not touch what it is given", function()
    it("leaves the entries and their order alone", function()
        local entries = { entry(1, 60, 300), entry(2, 61, 100) }

        MLH:aggregateLoot(entries, UNKNOWN)

        assert.are.equal(2, #entries)
        assert.are.equal(300, entries[1].foundOn)
        assert.are.equal(60, entries[1].zoneID)
        assert.are.equal(2, entries[2].quantity)
    end)
end)
