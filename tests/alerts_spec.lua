local wow = require("tests.support.wow")
local frames = require("tests.support.frames")

frames.install()

_G.Enum.ItemQuality = { Poor = 0, Common = 1, Uncommon = 2, Rare = 3, Epic = 4, Legendary = 5 }
_G.Enum.ItemClass.Miscellaneous = 15
_G.Enum.ItemMiscellaneousSubclass = { CompanionPet = 2, Mount = 5 }

for i = 0, 5 do
    _G["ITEM_QUALITY"..i.."_DESC"] = "Quality"..i
end

_G.C_Item.GetItemQualityColor = function() return 0.5, 0.6, 0.7, "ff8899aa" end

local clock = 0
_G.GetTime = function() return clock end

local toys = {}
_G.C_ToyBox = { GetToyInfo = function(itemID) return toys[itemID] and itemID or nil end }

wow.loadThrough("ui/Alerts.lua")
wow.load("locales/enUS.lua")

local MLH = wow.addon

local ARMOR, MISC, MOUNT = 4, 15, 5

local printed = {}

local function toasts()
    local found = {}

    for i = 1, #frames.all do
        -- rawget: the fake widget answers any capitalised method name with a stub
        if (rawget(frames.all[i], "SetDrop")) then found[#found + 1] = frames.all[i] end
    end

    return found
end

local function shownToasts()
    local shown = {}

    for _, toast in ipairs(toasts()) do
        if (toast:IsShown()) then shown[#shown + 1] = toast end
    end

    return shown
end

before_each(function()
    MLH:initDatabase()
    printed = {}
    _G.print = function(line) printed[#printed + 1] = line end

    for _, toast in ipairs(toasts()) do toast:Click() end
end)

describe("getDropAlert", function()
    it("alerts on the configured quality and better, not below it", function()
        assert.are.equal("quality", MLH:getDropAlert(1, nil, 4, 1, 100, ARMOR, 0).kind)
        assert.are.equal("quality", MLH:getDropAlert(1, nil, 5, 1, 100, ARMOR, 0).kind)
        assert.is_nil(MLH:getDropAlert(1, nil, 3, 1, 100, ARMOR, 0))
    end)

    it("ignores quality when it is off", function()
        MLH.db.char.config.alerts.minQuality = 0

        assert.is_nil(MLH:getDropAlert(1, nil, 5, 1, 100, ARMOR, 0))
    end)

    it("prices the whole stack against the gold threshold", function()
        MLH.db.char.config.alerts.minValue = 1

        local alert = MLH:getDropAlert(1, nil, 1, 5, 2500, ARMOR, 0)

        assert.are.equal("value", alert.kind)
        assert.are.equal(12500, alert.value)
        assert.is_nil(MLH:getDropAlert(1, nil, 1, 3, 2500, ARMOR, 0))
    end)

    it("alerts on mounts, pets and toys whatever their quality", function()
        toys[42] = true

        assert.are.equal("mount", MLH:getDropAlert(1, nil, 1, 1, 0, MISC, MOUNT).kind)
        assert.are.equal("pet", MLH:getDropAlert(1, nil, 1, 1, 0, MISC, 2).kind)
        assert.are.equal("pet", MLH:getDropAlert(1, nil, 1, 1, 0, 17, 0).kind)
        assert.are.equal("toy", MLH:getDropAlert(42, nil, 1, 1, 0, MISC, 0).kind)

        MLH.db.char.config.alerts.collectibles = false

        assert.is_nil(MLH:getDropAlert(1, nil, 1, 1, 0, MISC, MOUNT))
    end)

    it("stays quiet when alerts are off", function()
        MLH.db.char.config.alerts.enabled = false

        assert.is_nil(MLH:getDropAlert(1, nil, 5, 1, 100, MISC, MOUNT))
    end)
end)

describe("the collection note", function()
    local GEAR = "|cffa335ee|Hitem:500|h[Shiny Helm]|h|r"

    after_each(function()
        _G.C_MountJournal, _G.C_PetJournal, _G.C_TransmogCollection, _G.PlayerHasToy = nil, nil, nil, nil
    end)

    it("calls a mount the player already has owned, and a new one nothing", function()
        local collected = true

        _G.C_MountJournal = {
            GetMountFromItem = function() return 77 end,
            GetMountInfoByID = function()
                return "Swift Thing", 1, 1, false, true, 0, false, false, nil, false, collected
            end,
        }

        assert.are.equal("owned", MLH:getDropAlert(1, nil, 4, 1, 0, MISC, MOUNT).note)

        collected = false

        assert.is_nil(MLH:getDropAlert(1, nil, 4, 1, 0, MISC, MOUNT).note)
    end)

    it("calls a pet owned once one of its species is caught", function()
        local caught = 0

        _G.C_PetJournal = {
            GetPetInfoByItemID = function()
                return "Pup", 1, 1, 1, "", "", false, true, true, false, true, 1, 1234
            end,
            GetNumCollectedInfo = function() return caught, 3 end,
        }

        assert.is_nil(MLH:getDropAlert(1, nil, 1, 1, 0, MISC, 2).note)

        caught = 1

        assert.are.equal("owned", MLH:getDropAlert(1, nil, 1, 1, 0, MISC, 2).note)
    end)

    it("calls a toy owned once it is in the toy box", function()
        toys[42] = true
        _G.PlayerHasToy = function(itemID) return itemID == 42 end

        assert.are.equal("owned", MLH:getDropAlert(42, nil, 1, 1, 0, MISC, 0).note)
    end)

    it("calls gear with an uncollected look a new appearance", function()
        local known = false

        _G.C_TransmogCollection = {
            GetItemInfo = function(link) return link == GEAR and 10 or nil, link == GEAR and 20 or nil end,
            GetAppearanceInfoBySource = function() return { appearanceIsCollected = known } end,
        }

        assert.are.equal("appearance", MLH:getDropAlert(500, GEAR, 4, 1, 0, ARMOR, 0).note)

        known = true

        assert.is_nil(MLH:getDropAlert(500, GEAR, 4, 1, 0, ARMOR, 0).note)
    end)

    it("says nothing when the client cannot tell", function()
        assert.is_nil(MLH:getDropAlert(1, nil, 4, 1, 0, MISC, MOUNT).note)
        assert.is_nil(MLH:getDropAlert(500, GEAR, 4, 1, 0, ARMOR, 0).note)
    end)

    it("is shown after the reason, on the toast and in chat", function()
        MLH.db.char.config.alerts.chat = true

        MLH:alertDrop(GEAR, 1, 4, 1, { kind = "mount", value = 0, note = "owned" })

        assert.is_truthy(printed[1]:find("Already owned", 1, true))
        assert.is_truthy(MLH:getDropAlertReason({ kind = "quality", note = "appearance" }, 4)
            :find("New appearance", 1, true))
    end)
end)

describe("recordLoot", function()
    it("alerts on a zero-price mount even though it is not recorded", function()
        MLH.db.char.config.alerts.chat = true

        _G.C_Item.GetItemInfo = function()
            return "Swift Thing", "|cffa335ee|Hitem:7|h[Swift Thing]|h|r", 4,
                nil, nil, nil, nil, nil, nil, 132261, 0, MISC, MOUNT
        end

        MLH:recordLoot(7, nil, 1, 1, nil)

        assert.are.equal(0, #MLH.db.char.foundItems)
        assert.are.equal(1, #shownToasts())
        assert.are.equal(1, #printed)
        assert.truthy(printed[1]:find("[Swift Thing]", 1, true))
    end)
end)

describe("toasts", function()
    local alert = { kind = "quality", value = 123456 }

    it("keeps at most three on screen, reusing the oldest", function()
        for i = 1, 5 do
            MLH:alertDrop("|cffa335ee|Hitem:"..i.."|h[Thing "..i.."]|h|r", 1, 4, 1, alert)
        end

        assert.are.equal(3, #toasts())
        assert.are.equal(3, #shownToasts())
    end)

    it("fades out after a while, but not while hovered", function()
        MLH:alertDrop("|cffa335ee|Hitem:1|h[Thing]|h|r", 1, 4, 1, alert)

        local toast = shownToasts()[1]

        toast:Fire("OnEnter")
        toast:Fire("OnUpdate", 30)
        assert.is_true(toast:IsShown())

        toast:Fire("OnLeave")
        toast:Fire("OnUpdate", 5.5)
        assert.is_true(toast:IsShown())
        assert.is_true(toast:GetAlpha() < 1)

        toast:Fire("OnUpdate", 1)
        assert.is_false(toast:IsShown())
    end)

    it("links on shift+click instead of dismissing", function()
        MLH:alertDrop("|cffa335ee|Hitem:1|h[Thing]|h|r", 1, 4, 1, alert)

        local toast = shownToasts()[1]

        frames.shiftDown = true
        toast:Click()
        frames.shiftDown = false

        assert.are.equal("|cffa335ee|Hitem:1|h[Thing]|h|r", frames.lastLink)
        assert.is_true(toast:IsShown())
    end)

    it("plays one sound for a burst of drops", function()
        local played = 0
        _G.PlaySound = function() played = played + 1 end

        clock = 100
        MLH:alertDrop("|cffa335ee|Hitem:1|h[A]|h|r", 1, 4, 1, alert)
        MLH:alertDrop("|cffa335ee|Hitem:2|h[B]|h|r", 1, 4, 1, alert)
        assert.are.equal(1, played)

        clock = 102
        MLH:alertDrop("|cffa335ee|Hitem:3|h[C]|h|r", 1, 4, 1, alert)
        assert.are.equal(2, played)
    end)
end)
