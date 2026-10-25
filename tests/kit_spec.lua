local wow = require("tests.support.wow")
local frames = require("tests.support.frames")

frames.install()

-- The kit touches a font file through a font object of its own; remember which files it touched. A
-- file in `unloadable` is one the client cannot find, which leaves the font object without a font.
local preloaded, unloadable = {}, {}

_G.CreateFont = function(name)
    local font = { name = name }

    font.SetFont = function(_, file)
        preloaded[#preloaded + 1] = file
        font.file = (not unloadable[file]) and file or nil
    end

    font.GetFont = function() return font.file end

    return font
end

wow.loadThrough("kit/Window.lua")

local UI = wow.addon.UI

local GAME_FONT = "Fonts\\FRIZQT__.TTF"
local PIXEL_FONT = "Interface\\AddOns\\MyLootHistory\\kit\\fonts\\RustyPixel.ttf"

describe("the kit's fonts", function()
    after_each(function()
        UI:setFont("blizzard")
    end)

    it("draw in the game's own font until another is picked", function()
        assert.are.equal(GAME_FONT, UI.font)
        assert.are.equal(GAME_FONT, UI.fontNumber)
    end)

    it("draw text and numbers in Rusty Pixel once it is picked", function()
        UI:setFont("pixel")

        assert.are.equal(PIXEL_FONT, UI.font)
        assert.are.equal(PIXEL_FONT, UI.fontNumber)
    end)

    it("load Rusty Pixel's file as soon as it is picked, so text measures its real width", function()
        UI:setFont("pixel")

        assert.are.equal(PIXEL_FONT, preloaded[#preloaded])
    end)

    it("keep the game's font when Rusty Pixel's file cannot be loaded, rather than drawing no text", function()
        unloadable[PIXEL_FONT] = true
        UI:setFont("pixel")
        unloadable[PIXEL_FONT] = nil

        assert.are.equal(GAME_FONT, UI.font)
        assert.are.equal(GAME_FONT, UI.fontNumber)
    end)

    it("go back to the game's font for a key they do not know", function()
        UI:setFont("pixel")
        UI:setFont("comic")

        assert.are.equal(GAME_FONT, UI.font)
    end)

    it("find Rusty Pixel in the addon's own kit folder", function()
        local path = PIXEL_FONT:gsub("^Interface\\AddOns\\MyLootHistory\\", ""):gsub("\\", "/")
        local file = io.open((os.getenv("MLH_ROOT") or ".").."/"..path, "rb")

        assert.is_not_nil(file, path.." is missing")

        file:close()
    end)
end)

describe("the confirm dialog", function()
    it("is named after the addon, so Escape closes it", function()
        local dialog = UI:confirm({ title = "Sure?", acceptText = "Yes", cancelText = "No" })

        assert.are.equal(dialog, _G.MyLootHistoryConfirmDialog)
        assert.is_true(tContains(UISpecialFrames, "MyLootHistoryConfirmDialog"))

        dialog:Hide()
    end)
end)

describe("a window's logo", function()
    after_each(function()
        UI.logo = nil
    end)

    it("is the addon's icon from its .toc", function()
        local window = UI:window({ title = "Report" })

        assert.are.equal("Interface\\Icons\\9xp_sigil_ardenweald01", window.logo.texture)
    end)

    it("is the one the addon sets, when it sets one", function()
        UI.logo = "Interface\\Icons\\inv_misc_map09"

        local window = UI:window({ title = "Report" })

        assert.are.equal("Interface\\Icons\\inv_misc_map09", window.logo.texture)
    end)

    it("is a question mark on a client that does not give the .toc's icon", function()
        local icon = wow.metadata.IconTexture
        wow.metadata.IconTexture = nil

        local window = UI:window({ title = "Report" })

        wow.metadata.IconTexture = icon

        assert.are.equal("Interface\\Icons\\INV_Misc_QuestionMark", window.logo.texture)
    end)
end)
