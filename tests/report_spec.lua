-- Tests share one persistent window, matching the client lifecycle.

local wow = require("tests.support.wow")
local frames = require("tests.support.frames")

frames.install()

_G.Enum.ItemQuality = { Poor = 0, Common = 1, Uncommon = 2, Rare = 3, Epic = 4, Legendary = 5 }

for i = 0, 5 do
    _G["ITEM_QUALITY"..i.."_DESC"] = "Quality"..i
end

_G.C_Item.GetItemQualityColor = function(quality)
    assert(type(quality) == "number", "GetItemQualityColor wants a number, got "..tostring(quality))

    return 0.5, 0.6, 0.7, "ff8899aa"
end

wow.loadThrough("data/Currency.lua")

local MLH = wow.addon

function MLH:setTooltipSuppressed() end
function MLH:toggleSettings() end

wow.loadThrough("ui/HUD.lua")

MLH:initDatabase()

local now = wow.now()
local char = MLH.db.char

char.thisSessionStart = now - 5400
char.config.showZone = true
char.config.showLastLooted = true
char.config.showItemID = true

char.foundItems = {}

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

local function open()
    if (not window or not window:IsShown()) then
        MLH:gui()

        window = _G.MLHReportFrame

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

    it("adds the totals, zones and sources to the tooltip when asked to", function()
        local lines = {}
        local tooltip = _G.GameTooltip
        local addLine = tooltip.AddLine

        tooltip.AddLine = function(self, text, ...)
            lines[#lines+1] = tostring(text)
            return addLine(self, text, ...)
        end

        char.config.showAdditionalTooltipData = true

        local row = frames.rowsOfKind("item")[1]
        local item = row.entry.item

        item.sources = { { name = "Kobold", quantity = 3 }, { name = "Crate", quantity = 1 } }
        row:Fire("OnEnter")

        char.config.showAdditionalTooltipData = false
        tooltip.AddLine = addLine

        local text = table.concat(lines, "\n")

        assert.is_truthy(text:find("R_TotalQuantityGathered|r |cFF00BB00"..item.totalQuantity.."|r", 1, true))
        assert.is_truthy(text:find(item.zones[1].name.." ("..item.zones[1].quantity..")", 1, true))
        assert.is_truthy(text:find("R_DroppedBy|r |cFF00BB00Kobold (3), Crate (1)|r", 1, true))
    end)

    it("hints at hiding the item in the tooltip", function()
        local lines = {}
        local tooltip = _G.GameTooltip
        local addLine = tooltip.AddLine

        tooltip.AddLine = function(self, text, ...)
            lines[#lines+1] = tostring(text)
            return addLine(self, text, ...)
        end

        frames.rowsOfKind("item")[1]:Fire("OnEnter")

        tooltip.AddLine = addLine

        assert.is_truthy(table.concat(lines, "\n"):find("R_RightClickForZoneOrHide", 1, true))
    end)

    it("puts the tooltip on the side of the window with room for it", function()
        local tooltip = _G.GameTooltip
        local row = frames.rowsOfKind("item")[1]

        window.left = 100
        row:Fire("OnEnter")

        assert.are.equal("TOPLEFT", tooltip.points[1][1])
        assert.are.equal("TOPRIGHT", tooltip.points[1][3])

        -- Pushed against the right edge of the screen, the window leaves no room on its right.
        window.left = _G.UIParent:GetWidth() - window:GetWidth() + 20
        row:Fire("OnEnter")

        assert.are.equal(1, #tooltip.points)
        assert.are.equal("TOPRIGHT", tooltip.points[1][1])
        assert.are.equal("TOPLEFT", tooltip.points[1][3])

        window.left = nil
        row:Fire("OnLeave")
    end)

    it("splits the gold row's tooltip into picked-up coins and quest rewards", function()
        local lines = {}
        local tooltip = _G.GameTooltip
        local addLine, addDoubleLine = tooltip.AddLine, tooltip.AddDoubleLine

        tooltip.AddLine = function(self, text, ...)
            lines[#lines+1] = tostring(text)
            return addLine(self, text, ...)
        end

        tooltip.AddDoubleLine = function(self, left, right)
            lines[#lines+1] = tostring(left).." = "..tostring(right)
            return self
        end

        char.foundGold[2] = { quantity = 50000, foundOn = now - 600, zoneID = 1, source = { kind = "quest", id = 7 } }
        MLH:refreshReport()

        -- The gold row is the last one, so the list is scrolled to its end.
        MLH.reportView.updateScroll(math.huge)

        local gold = frames.rowsOfKind("gold")[1]

        gold:Fire("OnEnter")

        local text = table.concat(lines, "\n")

        assert.is_falsy(text:find("R_GoldInZone", 1, true))

        -- With a zone picked, the tooltip names it too.
        lines = {}
        MLH:setFilter("zone", 1)
        MLH:refreshReport()
        MLH.reportView.updateScroll(math.huge)
        frames.rowsOfKind("gold")[1]:Fire("OnEnter")

        assert.is_truthy(table.concat(lines, "\n"):find("R_GoldInZone", 1, true))

        MLH:setFilter("zone", 0)
        tooltip.AddLine, tooltip.AddDoubleLine = addLine, addDoubleLine
        char.foundGold[2] = nil

        assert.is_truthy(text:find("R_GoldInView", 1, true))
        assert.is_truthy(text:find("R_GoldFromLoot = "..MLH:formatMoneyShort(987654), 1, true))
        assert.is_truthy(text:find("R_GoldFromQuests = "..MLH:formatMoneyShort(50000), 1, true))
        assert.is_truthy(text:find("R_GoldTotal = "..MLH:formatMoneyShort(1037654), 1, true))
    end)

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

    local function rowMenu()
        for i = #frames.all, 1, -1 do
            local frame = frames.all[i]

            -- rawget: the mock answers any capitalised method, so only a real Open counts.
            if (rawget(frame, "Open") and frame.parent == _G.UIParent and frame.shown) then
                return frame
            end
        end
    end

    local function pick(menu, value)
        for i = 1, #menu.children do
            local entry = menu.children[i]

            if (entry.kind == "Button" and entry.shown and entry.value == value) then
                entry:Click()
                return true
            end
        end
    end

    it("shares the session from the title bar", function()
        local share = nil

        for _, child in ipairs(window.titleBar.children) do
            if (tostring(child.tooltipTitle) == "R_Share") then share = child end
        end

        assert.is_not_nil(share)

        local said = nil
        local print = _G.print

        _G.print = function(message) said = message end

        share:Click()
        assert.is_true(pick(rowMenu(), "self"))

        _G.print = print

        assert.is_not_nil(said)
    end)

    it("hides an item from the right-click menu", function()
        local row = frames.rowsOfKind("item")[1]
        local itemId = row.entry.item.itemId

        local said = nil
        local print = _G.print

        _G.print = function(message) said = message end

        row:Click("RightButton")
        assert.is_true(pick(rowMenu(), "hide"))

        _G.print = print

        assert.is_true(MLH:isItemHidden(itemId))
        assert.are.equal("M_ItemHidden", tostring(said))

        for _, shown in ipairs(frames.rowsOfKind("item")) do
            if (shown:IsShown()) then assert.are_not.equal(itemId, shown.entry.item.itemId) end
        end

        assert.is_truthy(window.footerText.text:find("R_HiddenCount", 1, true))

        MLH:setItemHidden(itemId, false)
        MLH:refreshReport()

        assert.is_falsy(window.footerText.text:find("R_HiddenCount", 1, true))
    end)

    it("offers no hiding on a currency row", function()
        MLH:setFilter("view", "currency")
        MLH:refreshReport()

        local row = frames.rowsOfKind("budget")[1]

        row:Click("RightButton")

        assert.is_nil(pick(rowMenu(), "hide"))

        rowMenu():Hide()
        MLH:setFilter("view", "items")
        MLH:refreshReport()
    end)

    it("filters to a zone from the right-click menu, and back", function()
        local row = frames.rowsOfKind("item")[1]
        local zoneID = row.entry.item.zones[1].id

        assert.is_not_nil(zoneID)

        row:Click("RightButton")

        local menu = rowMenu()

        assert.is_not_nil(menu)
        assert.is_true(pick(menu, zoneID))
        assert.are.equal(zoneID, MLH:getFilters().zone)
        assert.is_false(menu:IsShown())

        row = frames.rowsOfKind("item")[1]
        row:Click("RightButton")

        assert.is_true(pick(rowMenu(), 0))
        assert.are.equal(0, MLH:getFilters().zone)
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
        for _, key in ipairs({ "quality", "name", "quantity", "value", "market", "character",
                               "source", "zone", "lastLooted" }) do
            assert.has_no.errors(function()
                window.header[key]:Fire("OnEnter")
                window.header[key]:Click()
                window.header[key]:Click()
                window.header[key]:Fire("OnLeave")
            end)
        end
    end)

    it("starts every text column A to Z, and the numbers biggest first", function()
        for _, key in ipairs({ "name", "character", "source", "zone" }) do
            window.header.quantity:Click()
            window.header[key]:Click()

            assert.are.equal(key, MLH:getFilters().sortKey)
            assert.is_false(MLH:getFilters().sortDescending)
        end

        window.header.value:Click()

        assert.is_true(MLH:getFilters().sortDescending)
    end)

    it("spells out the quality column's name in its tooltip", function()
        local named = nil
        local L = LibStub("AceLocale-3.0"):GetLocale("MyLootHistory")

        -- The stub locale answers with the key alone, so the sentence is made to keep its argument.
        rawset(L, "R_SortBy", function(name) named = name return "R_SortBy" end)

        window.header.quality:Fire("OnEnter")
        window.header.quality:Fire("OnLeave")

        rawset(L, "R_SortBy", nil)

        assert.are.equal("R_ColQualityName", tostring(named))
        assert.are.equal("R_ColQuality", tostring(window.header.quality.baseText))
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

    it("only offers the session picker while the range is a session", function()
        MLH:setFilter("range", 6)
        MLH:refreshReport()
        assert.is_false(window.sessionDropdown:IsShown())

        MLH:setFilter("range", 1)
        MLH:refreshReport()
        assert.is_true(window.sessionDropdown:IsShown())

        MLH:setFilter("range", 6)
        MLH:refreshReport()
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
        assert.are.equal("R_NothingMatchesFilters", window.emptyText.text)

        window.emptyReset:Click()

        assert.is_false(window.empty:IsShown())
        assert.are.equal("", MLH:getFilters().search)
    end)

    it("points at the hidden items when they are all the view holds", function()
        -- Zone 2 has items but no coins, so hiding its items leaves the list empty.
        local hidden = {}

        for _, item in ipairs(char.foundItems) do
            if (item.lootData[1].zoneID == 2) then
                MLH:setItemHidden(item.itemId, true, item.itemName)
                hidden[#hidden+1] = item.itemId
            end
        end

        MLH:setFilter("zone", 2)
        MLH:refreshReport()

        assert.is_true(window.empty:IsShown())
        assert.are.equal("R_EverythingHidden", window.emptyText.text)

        for _, itemId in ipairs(hidden) do MLH:setItemHidden(itemId, false) end

        MLH:setFilter("zone", 0)
        MLH:refreshReport()
    end)
end)

describe("the session cards", function()
    before_each(open)

    it("asks before restarting the session when the first card is clicked", function()
        local startedOn = wow.now() - 9999

        MLH.db.char.thisSessionStart = startedOn

        window.cards.time:Fire("OnMouseUp")

        assert.is_true(_G.MyLootHistoryConfirmDialog:IsShown())
        assert.are.equal(startedOn, MLH.db.char.thisSessionStart)

        _G.MyLootHistoryConfirmDialog.accept:Click()

        assert.is_true(MLH.db.char.thisSessionStart > wow.now() - 10)
    end)

    it("keeps the session when the question is turned down", function()
        local startedOn = wow.now() - 9999

        MLH.db.char.thisSessionStart = startedOn

        window.cards.time:Fire("OnMouseUp")
        _G.MyLootHistoryConfirmDialog.cancel:Click()

        assert.are.equal(startedOn, MLH.db.char.thisSessionStart)
        assert.is_false(_G.MyLootHistoryConfirmDialog:IsShown())
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

    it("can be resized by a character who never changed the setting", function()
        assert.is_true(char.config.resizableReportWindow)
        assert.is_true(window.grip:IsShown())

        local before = window.calls.StartSizing or 0

        window.grip:Fire("OnMouseDown")
        window.grip:Fire("OnMouseUp")

        assert.are.equal(before + 1, window.calls.StartSizing)
    end)

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
        local keys = { "showZone", "showLastLooted", "showItemID", "showCurrency",
                       "showSessionBar", "showSource" }

        for _, key in ipairs(keys) do
            assert.has_no.errors(function()
                char.config[key] = false
                MLH:refreshReport()
                char.config[key] = true
                MLH:refreshReport()
            end)
        end
    end)

    it("shows the character column once the view covers the account", function()
        assert.is_false(window.header.character:IsShown())

        MLH:setFilter("scope", "account")
        MLH:refreshReport()

        assert.is_true(window.header.character:IsShown())

        MLH:setFilter("scope", "char")
        MLH:refreshReport()

        assert.is_false(window.header.character:IsShown())
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

describe("the Item column", function()
    local View = MLH.reportView

    local function everyColumnOn()
        char.config.showZone = true
        char.config.showLastLooted = true
        char.config.showSource = true
        MLH:setFilter("scope", "account")

        -- An auction price source adds the AH column.
        _G.Auctionator = { API = { v1 = { GetAuctionPriceByItemID = function() return 500 end } } }
        char.config.priceSource = "auctionator"

        MLH:refreshReport()
    end

    before_each(open)

    after_each(function()
        _G.Auctionator = nil
        char.config.priceSource = "vendor"
        char.config.showSource = false
        MLH:setFilter("scope", "char")
        window:SetSize(940, 620)
        MLH:refreshReport()
    end)

    it("keeps its minimum width at the default size with every column on", function()
        window:SetSize(940, 620)
        everyColumnOn()

        local layout = View.columnLayout()

        assert.is_true(layout.marketWidth ~= nil and layout.characterWidth ~= nil)
        assert.is_true(layout.nameWidth >= View.NAME_MIN_WIDTH)
        assert.is_true(layout.sourceWidth < 132)
        assert.are.equal(104, layout.valueWidth)
    end)

    it("leaves the other columns their full width when there is room", function()
        window:SetSize(1400, 620)
        everyColumnOn()

        local layout = View.columnLayout()

        assert.are.equal(132, layout.sourceWidth)
        assert.are.equal(124, layout.lastLootedWidth)
        assert.is_true(layout.nameWidth > View.NAME_MIN_WIDTH)
    end)

    it("widens a window left narrower than every column needs", function()
        everyColumnOn()

        window:SetSize(780, 620)
        window:Fire("OnSizeChanged")

        assert.are.equal(View.minimumWidth(), window:GetWidth())
        assert.is_true(View.minimumWidth() > 780)
        assert.is_true(View.columnLayout().nameWidth >= View.NAME_MIN_WIDTH)
    end)

    it("keeps the usual minimum when only a few columns are on", function()
        char.config.showZone = false
        char.config.showLastLooted = false

        assert.are.equal(780, View.minimumWidth())

        char.config.showZone = true
        char.config.showLastLooted = true
    end)

    it("lets the currency table, which is narrower, keep the usual minimum", function()
        everyColumnOn()
        MLH:setFilter("view", "currency")
        window:SetSize(790, 620)
        window:Fire("OnSizeChanged")

        assert.are.equal(780, View.minimumWidth())
        assert.are.equal(790, window:GetWidth())

        MLH:setFilter("view", "items")
    end)

    it("moves the header with the rows while the window is dragged narrower", function()
        everyColumnOn()

        window:SetSize(1400, 620)
        window:Fire("OnSizeChanged")

        assert.are.equal(132, window.header.source:GetWidth())

        window:SetSize(View.minimumWidth(), 620)
        window:Fire("OnSizeChanged")

        assert.are.equal(View.columnLayout().sourceWidth, window.header.source:GetWidth())
        assert.is_true(window.header.source:GetWidth() < 132)
    end)

    it("leaves the width to the player's hand during a drag, and settles it after", function()
        everyColumnOn()

        window.grip:Fire("OnMouseDown")
        window:SetSize(700, 620)
        window:Fire("OnSizeChanged")

        assert.are.equal(700, window:GetWidth())

        window.grip:Fire("OnMouseUp")

        assert.are.equal(View.minimumWidth(), window:GetWidth())
    end)

    it("works the layout out once for a width, not on every scroll step", function()
        local layout = View.columnLayout()

        window.list:Fire("OnMouseWheel", -1)

        assert.are.equal(layout, View.columnLayout())

        window:SetSize(window:GetWidth() + 40, 620)

        assert.are_not.equal(layout, View.columnLayout())
    end)
end)

describe("the export window", function()
    it("opens with the CSV of what the report is showing", function()
        open()

        local exportButton = nil

        for i = 1, #window.titleBar.children do
            local child = window.titleBar.children[i]

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

    it("scrolls a long CSV with the kit's own scrollbar", function()
        local frame = _G.MLHExportFrame
        local scroll = frame.editBox:GetParent()

        scroll.verticalScrollRange = 500
        scroll:Fire("OnScrollRangeChanged")
        scroll:Fire("OnMouseWheel", -1)

        assert.are.equal(48, frame.offset)

        scroll:Fire("OnMouseWheel", 5)

        assert.are.equal(0, frame.offset)
    end)
end)

describe("the session HUD", function()
    teardown(function()
        char.config.showHUD = false
        char.config.hudLocked = false
        MLH:applyHUD()
    end)

    it("stays off until it is asked for", function()
        char.config.showHUD = false
        MLH:applyHUD()

        assert.is_true(_G.MLHHudFrame == nil or not _G.MLHHudFrame:IsShown())
    end)

    it("comes up with the three live numbers on it", function()
        assert.is_true(MLH:toggleHUD())

        local hud = _G.MLHHudFrame

        assert.is_not_nil(hud)
        assert.is_true(hud:IsShown())

        for i = 1, 3 do
            assert.is_not.equal("", hud.cells[i].text)
        end
    end)

    it("says the same thing the session card does", function()
        local stats = MLH:getSessionStats()

        assert.are.equal(MLH:formatDuration(stats.duration), _G.MLHHudFrame.cells[1].text)
    end)

    it("marks its time while the session clock is paused, and drops the mark once it runs again", function()
        char.config.pauseWhenAway = true
        wow.player.afk = true
        MLH:onSessionPauseEvent()

        local text = _G.MLHHudFrame.cells[1].text
        local elapsed = MLH:formatDuration(MLH:getSessionStats().duration)

        -- A small mark and the time, not a word that would not fit the cell.
        assert.is_not_nil(text:find("^|TInterface\\TimeManager\\PauseButton:"))
        assert.are.equal(elapsed, text:match("|t (.*)$"))

        wow.player.afk = false
        MLH:onSessionPauseEvent()

        assert.are.equal(MLH:formatDuration(MLH:getSessionStats().duration), _G.MLHHudFrame.cells[1].text)
    end)

    it("says in its tooltip why the time stands still", function()
        char.config.pauseWhenAway = true
        wow.player.afk = true
        MLH:onSessionPauseEvent()

        assert.is_not_nil(tostring(_G.MLHHudFrame.tooltipBody()):find("H_Paused", 1, true))

        wow.player.afk = false
        MLH:onSessionPauseEvent()

        assert.is_nil(tostring(_G.MLHHudFrame.tooltipBody()):find("H_Paused", 1, true))

        wow.player.afk = false
        MLH:onSessionPauseEvent()
    end)

    it("puts the paused state under the time card", function()
        char.config.pauseWhenAway = true
        wow.player.afk = true
        MLH:onSessionPauseEvent()
        open()

        assert.are.equal("G_PausedNow", window.cards.time.footnote.text)

        wow.player.afk = false
        MLH:onSessionPauseEvent()
        MLH:refreshReport()
    end)

    it("refuses to be dragged while it is locked", function()
        local hud = _G.MLHHudFrame

        char.config.hudLocked = true
        hud:Fire("OnDragStart")

        assert.is_nil(hud.calls.StartMoving)

        char.config.hudLocked = false
        hud:Fire("OnDragStart")

        assert.are.equal(1, hud.calls.StartMoving)

        hud:Fire("OnDragStop")

        assert.is_not_nil(MLH.db.char.ui.hud.point)
    end)

    it("does not count the end of a drag as a click", function()
        local wasShown = window:IsShown()

        _G.MLHHudFrame:Fire("OnMouseUp", "LeftButton")

        assert.are.equal(wasShown, window:IsShown())
    end)

    it("asks before starting a new session on a right click", function()
        local startedOn = wow.now() - 9999

        MLH.db.char.thisSessionStart = startedOn

        _G.MLHHudFrame:Fire("OnMouseUp", "RightButton")

        assert.is_true(_G.MyLootHistoryConfirmDialog:IsShown())
        assert.are.equal(startedOn, MLH.db.char.thisSessionStart)

        _G.MyLootHistoryConfirmDialog.cancel:Click()

        assert.are.equal(startedOn, MLH.db.char.thisSessionStart)

        _G.MLHHudFrame:Fire("OnMouseUp", "RightButton")
        _G.MyLootHistoryConfirmDialog.accept:Click()

        assert.is_true(MLH.db.char.thisSessionStart > wow.now() - 10)
    end)

    it("goes away again, and takes its ticker with it", function()
        assert.is_false(MLH:toggleHUD())
        assert.is_false(_G.MLHHudFrame:IsShown())

        assert.has_no.errors(function() MLH:updateHUD() end)
    end)
end)

describe("the currency tab", function()
    local originalGetCurrencyInfo = nil

    setup(function()
        originalGetCurrencyInfo = _G.C_CurrencyInfo.GetCurrencyInfo

        _G.C_CurrencyInfo.GetCurrencyInfo = function(id)
            return {
                name = "Valorstones", iconFileID = 9, quality = 1, quantity = 1240,
                canEarnPerWeek = true, maxWeeklyQuantity = 1500, quantityEarnedThisWeek = 600,
            }
        end
    end)

    teardown(function()
        _G.C_CurrencyInfo.GetCurrencyInfo = originalGetCurrencyInfo

        MLH:setFilter("view", "items")
        MLH:refreshReport()
    end)

    it("puts its tabs in the title bar, not among the filters", function()
        open()

        assert.are.equal(window.titleBar, window.viewControl:GetParent())
    end)

    it("switches the whole table over, header and all", function()
        open()

        MLH:setFilter("view", "currency")
        MLH:refreshReport()

        assert.is_true(window.header.earned:IsShown())
        assert.is_true(window.header.cap:IsShown())
        assert.is_false(window.header.value:IsShown())
        assert.is_false(window.header.quality:IsShown())
    end)

    it("draws a row per currency with a cap bar", function()
        local rows = frames.rowsOfKind("budget")

        assert.is_true(#rows > 0)
        assert.is_true(rows[1].capBar:IsShown())
        assert.is_not.equal("", rows[1].earned.text)
    end)

    it("keeps a sort of its own rather than the item table's", function()
        MLH:setFilter("sortKey", "quantity")

        for _, key in ipairs({ "earned", "perHour", "held", "cap", "name" }) do
            MLH:setFilter("currencySort", key)

            assert.has_no.errors(function() MLH:refreshReport() end)
        end

        assert.are.equal("quantity", MLH:getFilters().sortKey)
    end)

    it("hides the filters that only mean something for items", function()
        assert.is_false(window.qualityDropdown:IsShown())
        assert.is_true(window.rangeControl:IsShown())
    end)

    it("shows a currency tooltip and links one on shift+click", function()
        local row = frames.rowsOfKind("budget")[1]

        assert.has_no.errors(function()
            row:Fire("OnEnter")
            row:Fire("OnLeave")
        end)

        frames.shiftDown = true
        row:Click()
        frames.shiftDown = false

        assert.is_not_nil(frames.lastLink)
    end)

    it("exports its own table rather than the item one", function()
        for i = 1, #window.titleBar.children do
            local child = window.titleBar.children[i]

            if (child.kind == "Button") then child:Click() end
        end

        assert.is_not_nil(_G.MLHExportFrame.editBox.text:find("name,id,earned,perHour", 1, true))

        _G.MLHExportFrame:Hide()
    end)

    it("goes back to the items without leaving a currency column behind", function()
        open()

        MLH:setFilter("view", "items")
        MLH:refreshReport()

        assert.is_false(window.header.earned:IsShown())
        assert.is_true(window.header.value:IsShown())
        assert.are.equal(0, #frames.rowsOfKind("budget"))
    end)
end)

describe("a character who has looted nothing", function()
    it("opens on the empty state without a row", function()
        char.foundItems = {}
        char.foundGold = {}
        char.foundCurrency = {}

        if (window:IsShown()) then window:Hide() end

        -- The default range, Today, is not a filter hiding anything when there is nothing to hide.
        MLH:setFilter("range", MLH.RANGE_TODAY)
        MLH:gui()

        assert.is_true(window.empty:IsShown())
        assert.is_false(window.emptyReset:IsShown())
        assert.are.equal("R_NothingIsHereYet", window.emptyText.text)

        window:Hide()
    end)

    it("says no currency was earned yet, whatever the item quality filter holds", function()
        MLH:setFilter("range", MLH.RANGE_ALL)
        MLH:setFilter("quality", 3)
        MLH:setFilter("view", "currency")
        MLH:gui()

        assert.is_true(window.empty:IsShown())
        assert.is_false(window.emptyReset:IsShown())
        assert.are.equal("R_NoCurrenciesHere", window.emptyText.text)

        MLH:setFilter("quality", 0)
        MLH:setFilter("view", "items")
        window:Hide()
    end)
end)

describe("live loot updates", function()
    it("refreshes items and currencies on the next tick without mixing the tabs", function()
        if (window) then window:Hide() end
        MLH:initDatabase()
        MLH:setFilter("view", "items")
        open()
        MLH:addItem(4242, 2, nil, 1, 1, "Live Ore", 1, 100)
        MLH:addCurrency(3008, 3, "Valorstones", 9, 1, 1)
        MLH:addGold(123, 1)
        wow.tick()
        assert.are.equal(1, #frames.rowsOfKind("item"))
        assert.are.equal(1, #frames.rowsOfKind("gold"))
        assert.are.equal(0, #frames.rowsOfKind("currency"))
        assert.is_false(window.empty:IsShown())
        local csv = MLH:buildCsv()
        assert.is_nil(csv:find("\ncurrency,", 1, true))
        MLH:setFilter("view", "currency")
        MLH:refreshReport()
        MLH:addCurrency(3008, 4, "Valorstones", 9, 1, 1)
        wow.tick()
        local rows = frames.rowsOfKind("budget")
        assert.are.equal(1, #rows)
        assert.are.equal("+7", tostring(rows[1].earned.text))
        MLH:setFilter("range", 1)
        MLH:resetSession()
        wow.tick()
        assert.is_true(window.empty:IsShown())
        window:Hide()
    end)
end)
