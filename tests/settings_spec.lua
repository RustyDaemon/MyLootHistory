-- The settings window draws the real options table from MyLootHistoryConfig.lua.

local wow = require("tests.support.wow")
local frames = require("tests.support.frames")

frames.install()

_G.Enum.ItemQuality = { Poor = 0, Common = 1, Uncommon = 2, Rare = 3, Epic = 4, Legendary = 5 }

for i = 0, 5 do
    _G["ITEM_QUALITY"..i.."_DESC"] = "Quality"..i
end

_G.GetTime = function() return 0 end

wow.provide("AceConfig-3.0", { RegisterOptionsTable = function() end })
wow.provide("AceConfigDialog-3.0", { AddToBlizOptions = function() end, Open = function() end })
wow.provide("LibDBIcon-1.0", { Show = function() end, Hide = function() end })

wow.loadThrough("MyLootHistoryCurrency.lua")

local MLH = wow.addon

function MLH:setTooltipSuppressed() end

wow.load("config/statisticsConfig.lua")
wow.load("config/faqConfig.lua")
wow.loadThrough("MyLootHistoryAlerts.lua")
wow.load("MyLootHistoryConfig.lua")
wow.load("MyLootHistorySettings.lua")

MLH:initDatabase()

local config = MLH.db.char.config

local function window()
    return _G.MLHSettingsFrame
end

local function page(index)
    MLH:openSettings(index)

    return window().pages[index]
end

local function rowFor(pageIndex, key)
    for _, row in ipairs(page(pageIndex).frame.rows) do
        if (row.info[1] == key) then return row end
    end

    error("no row for "..key)
end

local function pageIndex(name)
    MLH:openSettings()

    for i, p in ipairs(window().pages) do
        if (tostring(p.name) == name) then return i end
    end

    error("no page "..name)
end

describe("pages", function()
    it("puts the loose options on General and gives every group a page, in order", function()
        MLH:openSettings()

        local names = {}

        for i, p in ipairs(window().pages) do names[i] = tostring(p.name) end

        assert.same({ "C_General", "C_Report", "C_Alerts", "C_HiddenItems", "C_Data", "C_Debug",
            "C_Statistics", "C_FAQ" }, names)
    end)

    it("drops the heading that only introduced the groups", function()
        local rows = page(1).frame.rows

        assert.equal("toggle", rows[#rows].option.type)
    end)

    it("remembers the last page", function()
        local report = pageIndex("C_Report")

        MLH:openSettings(report)
        window():Hide()
        MLH:openSettings()

        assert.equal(report, window().current)
    end)
end)

describe("toggles", function()
    it("write through the option's set", function()
        config.showZone = false

        local row = rowFor(pageIndex("C_Report"), "showZoneColumnCheckBox")

        row.children[1]:Click()

        assert.is_true(config.showZone)
    end)

    it("are covered and dimmed while disabled, and come back when the option allows them", function()
        config.showHUD = false

        local lock = rowFor(1, "lockHUDCheckBox")

        assert.equal(0.4, lock:GetAlpha())

        rowFor(1, "showHUDCheckBox").children[1]:Click()

        assert.is_true(config.showHUD)
        assert.equal(1, lock:GetAlpha())

        MLH:hideHUD()
    end)
end)

describe("selects", function()
    it("show the current value and set the picked one", function()
        config.alerts.minQuality = 4

        local row = rowFor(pageIndex("C_Alerts"), "alertsMinQualitySelect")
        local dropdown = row.children[1]

        frames.firstButton(dropdown):Click()

        local picked = nil

        for _, entry in ipairs(dropdown.menu.children) do
            if (entry.kind == "Button" and entry.value == 3 and entry:IsShown()) then picked = entry end
        end

        picked:Click()

        assert.equal(3, config.alerts.minQuality)
    end)
end)

describe("ranges", function()
    it("take a typed value past the slider's soft range, within the hard one", function()
        local row = rowFor(pageIndex("C_Alerts"), "alertsMinValueRange")
        local editBox = row.children[1].box.editBox

        config.alerts.enabled = true
        editBox:SetText("25000")
        editBox:Fire("OnEnterPressed")

        assert.equal(25000, config.alerts.minValue)

        editBox:SetText("99999999")
        editBox:Fire("OnEnterPressed")

        assert.equal(1000000, config.alerts.minValue)
    end)

    it("ignore text that is not a number", function()
        config.alerts.minValue = 10

        local editBox = rowFor(pageIndex("C_Alerts"), "alertsMinValueRange").children[1].box.editBox

        editBox:SetText("lots")
        editBox:Fire("OnEnterPressed")

        assert.equal(10, config.alerts.minValue)
        assert.equal("10", editBox:GetText())
    end)
end)

describe("read-only inputs", function()
    it("put the text back when it is typed over", function()
        MLH.website = "https://example.test"

        local row = rowFor(pageIndex("C_FAQ"), "inputWebsite")
        local editBox = row.children[1].editBox

        assert.equal("https://example.test", editBox:GetText())

        editBox:SetText("oops")
        editBox:Fire("OnTextChanged", true)

        assert.equal("https://example.test", editBox:GetText())
    end)
end)

describe("confirmations", function()
    local function pickRetention(days)
        local dropdown = rowFor(pageIndex("C_Data"), "retentionSelect").children[1]

        frames.firstButton(dropdown):Click()

        for _, entry in ipairs(dropdown.menu.children) do
            if (entry.kind == "Button" and entry.value == days and entry:IsShown()) then entry:Click() end
        end

        return _G.MLHConfirmDialog
    end

    it("ask before removing older loot, and keep the old setting on cancel", function()
        config.retentionDays = 0

        local dialog = pickRetention(90)

        assert.is_true(dialog:IsShown())
        assert.equal(90, config.retentionDays)

        dialog.cancel:Click()

        assert.is_false(dialog:IsShown())
        assert.equal(0, config.retentionDays)
    end)

    it("count Escape as cancel", function()
        config.retentionDays = 30

        local dialog = pickRetention(365)

        dialog:Hide()

        assert.equal(30, config.retentionDays)
    end)

    it("prune when accepted", function()
        config.retentionDays = 0

        local pruned = nil
        local original = MLH.pruneHistory

        MLH.pruneHistory = function() pruned = true return 0, 0 end

        pickRetention(180).accept:Click()

        MLH.pruneHistory = original

        assert.is_true(pruned)
        assert.equal(180, config.retentionDays)
    end)

    it("clear the data only once accepted", function()
        MLH.db.char.foundGold = { { quantity = 5, foundOn = 1 } }

        local clear = rowFor(pageIndex("C_Data"), "clearData").children[1]

        clear:Click()
        _G.MLHConfirmDialog.cancel:Click()

        assert.equal(1, #MLH.db.char.foundGold)

        clear:Click()
        _G.MLHConfirmDialog.accept:Click()

        assert.equal(0, #MLH.db.char.foundGold)
    end)
end)

describe("hidden items", function()
    it("lists each one with a button that unhides it", function()
        MLH:setItemHidden(100, true, "Copper Ore")
        MLH:setItemHidden(200, true, "Broken Fang")

        local row = rowFor(pageIndex("C_HiddenItems"), "hiddenItemsList")

        row.Refresh()

        local lines = {}

        for _, child in ipairs(row.children) do
            if (child.kind == "Frame" and child.shown) then lines[#lines+1] = child end
        end

        assert.equal(2, #lines)
        assert.equal("Broken Fang", lines[1].label:GetText())

        frames.firstButton(lines[1]):Click()

        assert.is_false(MLH:isItemHidden(200))
        assert.is_true(MLH:isItemHidden(100))

        MLH:setItemHidden(100, false)
    end)

    it("says so when nothing is hidden", function()
        local row = rowFor(pageIndex("C_HiddenItems"), "hiddenItemsList")

        row.Refresh()

        local said = false

        for _, child in ipairs(row.children) do
            if (child.kind == "Frame") then assert.is_false(child.shown) end
            if (child.shown and tostring(child.text) == "C_NoHiddenItems") then said = true end
        end

        assert.is_true(said)
    end)
end)

describe("descriptions", function()
    it("render text worked out when the page is shown", function()
        local row = rowFor(pageIndex("C_Statistics"), "statisticsText")
        local text = row.children[1]

        assert.is_truthy(text:GetText():find("M_TotalDifferentItemsGathered", 1, true))
    end)
end)
