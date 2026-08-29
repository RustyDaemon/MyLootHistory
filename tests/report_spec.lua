--[[
The report window, built against the frame mock in tests/support/frames.lua and then
clicked on.

This is not a test of how the window looks - nothing here can see it. It is a test that
every path through it runs: opening, filling rows from pooled frames, scrolling past the
end, every sort column, both dropdowns, the search box, the empty state, a resize, the
export window and closing again. A missing field or a mistyped method is a Lua error in
the client and a red test here, which is the whole point - before this the report was the
one part of the addon that could only be checked by logging in.

The window keeps its state between tests on purpose: it is one long-lived frame in the
game too, and the order below is the order a player would do things in.
--]]

local wow = require("tests.support.wow")
local frames = require("tests.support.frames")

frames.install()

_G.Enum.ItemQuality = { Poor = 0, Common = 1, Uncommon = 2, Rare = 3, Epic = 4, Legendary = 5 }

for i = 0, 5 do
    _G["ITEM_QUALITY"..i.."_DESC"] = "Quality"..i
end

-- the report colours rows by quality, so this one has to answer with numbers
_G.C_Item.GetItemQualityColor = function(quality)
    assert(type(quality) == "number", "GetItemQualityColor wants a number, got "..tostring(quality))

    return 0.5, 0.6, 0.7, "ff8899aa"
end

wow.provide("AceConfigDialog-3.0", { Open = function() end })

wow.load("utils/DateUtils.lua")
wow.load("MyLootHistory.lua")
wow.load("MyLootHistoryDB.lua")
wow.load("MyLootHistoryPrices.lua")
wow.load("MyLootHistorySession.lua")
wow.load("MyLootHistoryData.lua")

local MLH = wow.addon

-- MyLootHistoryTooltip registers against TooltipDataProcessor, which is not modelled; the
-- report only ever calls this one function out of it
function MLH:setTooltipSuppressed() end

wow.load("MyLootHistoryUIKit.lua")
wow.load("MyLootHistoryUI.lua")

MLH:initDatabase()

local now = wow.now()
local char = MLH.db.char

char.thisSessionStart = now - 5400
char.config.showZone = true
char.config.showLastLooted = true
char.config.showItemID = true
char.config.resizableReportWindow = true

char.foundItems = {}

-- enough rows that the list has to scroll, and the pooled frames have to be refilled
for i = 1, 60 do
    char.foundItems[i] = {
        itemId = 1000 + i,
        itemLink = "|cffffffff|Hitem:"..(1000 + i).."|h[Item "..i.."]|h|r",
        itemName = "Item "..i,
        itemTexture = 133784,
        quality = i % 6,
        lootData = {
            { quantity = i, foundOn = now - i * 60, zoneID = (i % 3) + 1, sellPrice = i * 137 },
        },
    }
end

-- and one from a version that stored neither a link nor a timestamp
char.foundItems[61] = {
    itemId = 9999, itemName = "Undated Thing", itemTexture = 133784,
    lootData = { { quantity = 1, zoneID = 1 } },
}

char.foundGold = { { quantity = 987654, foundOn = now - 1200, zoneID = 1 } }
char.foundCurrency = {
    {
        currencyId = 3008, currencyName = "Valorstones", currencyIcon = 9, quality = 1,
        lootData = { { quantity = 40, foundOn = now - 700, zoneID = 1 } },
    },
}

local window = nil

-- Opens the window if it is not up, and puts the filters back to "everything", so a test
-- that leaves a filter behind cannot decide what the next one sees.
local function open()
    if (not window or not window:IsShown()) then
        MLH:gui()

        window = _G.MLHReportFrame

        -- an anchored frame has no computed size under the mock, so the viewport is given
        -- one by hand; without it the list would only ever ask for a single row
        window.list:SetHeight(400)
    end

    MLH:resetFilters()
    window.search:SetValue("")
    MLH:refreshReport()

    return window
end

describe("opening the report", function()
    it("builds a named frame and shows it", function()
        open()

        assert.is_not_nil(_G.MLHReportFrame)
        assert.is_true(window:IsShown())
    end)

    it("registers once for Escape", function()
        local count = 0

        for i = 1, #_G.UISpecialFrames do
            if (_G.UISpecialFrames[i] == "MLHReportFrame") then count = count + 1 end
        end

        assert.are.equal(1, count)
    end)

    it("fades in rather than popping", function()
        assert.is_true(window.fade.played > 0)
    end)

    it("fills more rows than one screenful of pooled frames", function()
        assert.is_true(#frames.rowsOfKind("item") > 5)
    end)

    it("says what the view adds up to", function()
        assert.is_not.equal("", window.footerText.text)
    end)

    it("fills all four stat cards", function()
        assert.is_not.equal("", window.cards.time.value.text)
        assert.is_not.equal("", window.cards.items.value.text)
        assert.is_not.equal("", window.cards.gold.value.text)
        assert.is_not.equal("", window.cards.filtered.value.text)
    end)

    it("draws a bar an hour on the activity graph", function()
        assert.are.equal(24, #window.graph.bars)
        assert.is_not_nil(window.graph.bars[1].hourLabel)
    end)
end)

describe("the list", function()
    before_each(open)

    it("scrolls with the wheel", function()
        assert.has_no.errors(function()
            window.list:Fire("OnMouseWheel", -1)
            window.list:Fire("OnMouseWheel", 1)
        end)
    end)

    it("clamps at both ends", function()
        assert.has_no.errors(function()
            for _ = 1, 200 do window.list:Fire("OnMouseWheel", -1) end
            for _ = 1, 400 do window.list:Fire("OnMouseWheel", 1) end
        end)
    end)

    it("drags by the scrollbar thumb", function()
        local thumb = frames.firstButton(window.scrollbar)

        assert.is_not_nil(thumb)

        assert.has_no.errors(function()
            thumb:Fire("OnMouseDown")
            thumb:Fire("OnUpdate", 0.016)
            thumb:Fire("OnMouseUp")
        end)
    end)

    it("shows an item tooltip on hover", function()
        local row = frames.rowsOfKind("item")[1]

        assert.has_no.errors(function()
            row:Fire("OnEnter")
            row:Fire("OnLeave")
        end)
    end)

    -- a record from an old version has no link, and SetHyperlink(nil) is an error
    it("falls back to the item id when a record carries no link", function()
        MLH:setFilter("search", "Undated")
        MLH:refreshReport()

        local row = frames.rowsOfKind("item")[1]

        assert.is_nil(row.entry.item.itemLink)
        assert.has_no.errors(function() row:Fire("OnEnter") end)

        MLH:setFilter("search", "")
        MLH:refreshReport()
    end)

    it("links an item to chat on shift-click", function()
        local row = frames.rowsOfKind("item")[1]

        frames.lastLink = nil
        frames.shiftDown = true
        row:Click("LeftButton")
        frames.shiftDown = false

        assert.is_not_nil(frames.lastLink)
    end)

    it("does not link without shift", function()
        local row = frames.rowsOfKind("item")[1]

        frames.lastLink = nil
        row:Click("LeftButton")

        assert.is_nil(frames.lastLink)
    end)

    it("fades a row highlight in and out", function()
        local row = frames.rowsOfKind("item")[1]

        row:Fire("OnEnter")

        for _ = 1, 20 do row:Fire("OnUpdate", 0.016) end

        assert.is_true(row.hover:GetAlpha() > 0)

        row:Fire("OnLeave")

        for _ = 1, 40 do row:Fire("OnUpdate", 0.016) end

        assert.are.equal(0, row.hover:GetAlpha())
    end)
end)

describe("the header", function()
    before_each(open)

    it("sorts by every column, both ways", function()
        for _, key in ipairs({ "quality", "name", "quantity", "value", "zone", "lastLooted" }) do
            assert.has_no.errors(function()
                window.header[key]:Fire("OnEnter")
                window.header[key]:Click()
                window.header[key]:Click()
                window.header[key]:Fire("OnLeave")
            end)
        end
    end)

    it("reverses on a second click of the same column", function()
        window.header.value:Click()

        local first = MLH:getFilters().sortDescending

        window.header.value:Click()

        assert.are_not.equal(first, MLH:getFilters().sortDescending)
    end)
end)

describe("the filter bar", function()
    before_each(open)

    it("switches to every date range", function()
        for value = 1, 6 do
            local hit = false

            for i = 1, #window.rangeControl.children do
                local button = window.rangeControl.children[i]

                if (button.value == value) then
                    button:Click()
                    hit = true
                end
            end

            assert.is_true(hit)
            assert.are.equal(value, MLH:getFilters().range)
        end

        MLH:setFilter("range", 6)
        MLH:refreshReport()
    end)

    it("opens the quality dropdown and picks from it", function()
        local button = frames.firstButton(window.qualityDropdown)

        button:Click()

        assert.is_true(window.qualityDropdown.menu:IsShown())

        for i = 1, #window.qualityDropdown.menu.children do
            local entry = window.qualityDropdown.menu.children[i]

            if (entry.value == 4) then entry:Click() end
        end

        assert.are.equal(4, MLH:getFilters().quality)
        assert.is_false(window.qualityDropdown.menu:IsShown())

        MLH:setFilter("quality", 0)
        MLH:refreshReport()
    end)

    it("lists every looted zone in the zone dropdown", function()
        local button = frames.firstButton(window.zoneDropdown)

        button:Click()

        local entries = 0

        for i = 1, #window.zoneDropdown.menu.children do
            if (window.zoneDropdown.menu.children[i].value ~= nil) then entries = entries + 1 end
        end

        assert.is_true(entries >= 4)

        for i = 1, #window.zoneDropdown.menu.children do
            local entry = window.zoneDropdown.menu.children[i]

            if (entry.value == 2) then entry:Click() end
        end

        assert.are.equal(2, MLH:getFilters().zone)

        MLH:setFilter("zone", 0)
        MLH:refreshReport()
    end)

    it("toggles exact quality", function()
        window.exactToggle:Click()

        assert.is_true(MLH:getFilters().exactQuality)

        window.exactToggle:Click()

        assert.is_false(MLH:getFilters().exactQuality)
    end)

    it("takes what is typed in the search box", function()
        window.search.editBox:SetText("Item 4")
        window.search.editBox:Fire("OnTextChanged", true)

        assert.are.equal("Item 4", MLH:getFilters().search)

        window.search.editBox:SetText("")
        window.search.editBox:Fire("OnTextChanged", true)
    end)
end)

describe("the empty state", function()
    before_each(open)

    it("appears when nothing matches, and offers to clear the filters", function()
        MLH:setFilter("search", "zzzznothing")
        MLH:refreshReport()

        assert.is_true(window.empty:IsShown())
        assert.is_true(window.emptyReset:IsShown())

        window.emptyReset:Click()

        assert.is_false(window.empty:IsShown())
        assert.are.equal("", MLH:getFilters().search)
    end)
end)

describe("the session cards", function()
    before_each(open)

    it("restarts the session when the first card is clicked", function()
        MLH.db.char.thisSessionStart = wow.now() - 9999

        window.cards.time:Fire("OnMouseUp")

        assert.is_true(MLH.db.char.thisSessionStart > wow.now() - 10)
    end)

    it("has a tooltip on each card", function()
        assert.has_no.errors(function()
            for _, card in pairs(window.cards) do
                card:Fire("OnEnter")
                card:Fire("OnLeave")
            end
        end)
    end)

    it("has a tooltip on each graph bar", function()
        assert.has_no.errors(function()
            window.graph.bars[3]:Fire("OnEnter")
            window.graph.bars[3]:Fire("OnLeave")
        end)
    end)
end)

describe("the window itself", function()
    before_each(open)

    it("re-lays out when resized", function()
        assert.has_no.errors(function()
            window.grip:Fire("OnMouseDown")
            window:SetSize(800, 500)
            window:Fire("OnSizeChanged")
            window.grip:Fire("OnMouseUp")
        end)
    end)

    it("gives the graph's space back to the cards when it gets narrow", function()
        window:SetSize(790, 470)
        window:Fire("OnSizeChanged")

        assert.is_false(window.graph:IsShown())

        window:SetSize(940, 620)
        window:Fire("OnSizeChanged")

        assert.is_true(window.graph:IsShown())
    end)

    it("follows the settings that change what it draws", function()
        local keys = { "showZone", "showLastLooted", "showItemID", "showCurrency", "showSessionBar" }

        for _, key in ipairs(keys) do
            assert.has_no.errors(function()
                char.config[key] = false
                MLH:refreshReport()
                char.config[key] = true
                MLH:refreshReport()
            end)
        end
    end)

    it("redraws at a different icon size", function()
        assert.has_no.errors(function()
            char.config.reportIconSize = 40
            MLH:refreshReport()
            char.config.reportIconSize = 24
            MLH:refreshReport()
        end)
    end)

    it("remembers where it was left", function()
        -- closing is what writes the size down, so the saved values go in after it
        window:Hide()

        MLH.db.char.ui.width = 1000
        MLH.db.char.ui.height = 700
        MLH.db.char.ui.point = "TOPLEFT"

        MLH:gui()

        assert.are.equal(1000, window:GetWidth())
        assert.are.equal(700, window:GetHeight())
    end)

    it("toggles shut when opened again", function()
        MLH:gui()

        assert.is_false(window:IsShown())
    end)

    it("refreshes harmlessly while closed", function()
        assert.has_no.errors(function() MLH:refreshReport() end)
    end)
end)

describe("the export window", function()
    it("opens with the CSV of what the report is showing", function()
        open()

        local exportButton = nil

        for i = 1, #window.titleBar.children do
            local child = window.titleBar.children[i]

            -- the three title-bar buttons are export, settings and close, right to left
            if (child.kind == "Button") then exportButton = exportButton or child end
        end

        for i = 1, #window.titleBar.children do
            local child = window.titleBar.children[i]

            if (child.kind == "Button") then child:Click() end
        end

        assert.is_not_nil(_G.MLHExportFrame)
        assert.is_true(_G.MLHExportFrame:IsShown())
        assert.is_not_nil(_G.MLHExportFrame.editBox.text:find("type,name,id"))
    end)

    it("puts an edit straight back, since it is a view and not a document", function()
        local editBox = _G.MLHExportFrame.editBox

        editBox:SetText("nonsense")
        editBox:Fire("OnTextChanged", true)

        assert.is_not_nil(editBox.text:find("type,name,id"))

        _G.MLHExportFrame:Hide()
    end)
end)

describe("a character who has looted nothing", function()
    it("opens on the empty state without a row", function()
        char.foundItems = {}
        char.foundGold = {}
        char.foundCurrency = {}

        if (window:IsShown()) then window:Hide() end

        MLH:gui()

        assert.is_true(window.empty:IsShown())

        window:Hide()
    end)
end)
