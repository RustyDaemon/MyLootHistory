--[[
My Loot History addon
Copyright (C) 2026 RustyDaemon (https://github.com/RustyDaemon)

See License file for details.
--]]

-- The kit's colors and fonts. Creates MLH.UI, so it loads before the rest of kit/.

local MLH = LibStub("AceAddon-3.0"):GetAddon("MyLootHistory")

local UI = {}
MLH.UI = UI

-- The game's own fonts by default, so every locale keeps its own alphabet.
local FONT = GameFontNormal:GetFont()
local FONT_NUMBER = (NumberFontNormal and NumberFontNormal:GetFont()) or FONT

-- The addon's own pixel font, built by tools/font/build_font.py, offered as an option. Its digits
-- share one width, so it serves numbers too. It only has ASCII glyphs.
local PIXEL_FONT = "Interface\\AddOns\\MyLootHistory\\media\\RustyPixel.ttf"

UI.font = FONT
UI.fontNumber = FONT_NUMBER

-- Picks the font for everything built from here on; windows already built keep theirs until a
-- reload. Called once the saved settings are loaded, before any window exists.
function UI:applyFont(pixel)
    if (pixel) then
        -- A font file is loaded on first use, and until then GetStringWidth() measures 0. Touch it
        -- now so it is ready before any window sizes itself around its text.
        CreateFont("MyLootHistoryFontPreload"):SetFont(PIXEL_FONT, 12, "")
    end

    self.font = pixel and PIXEL_FONT or FONT
    self.fontNumber = pixel and PIXEL_FONT or FONT_NUMBER
end

UI.GOLD_ICON = "|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:0:-1|t"

local C = {
    shadow      = { 0.00, 0.00, 0.00 },
    window      = { 0.043, 0.047, 0.055 },
    panel       = { 0.082, 0.086, 0.098 },
    panelHover  = { 0.114, 0.122, 0.141 },
    raised      = { 0.129, 0.137, 0.157 },
    border      = { 0.176, 0.188, 0.216 },
    borderLight = { 0.239, 0.255, 0.290 },

    text        = { 0.918, 0.925, 0.945 },
    textDim     = { 0.596, 0.620, 0.678 },
    textFaint   = { 0.396, 0.416, 0.463 },

    accent      = { 1.000, 0.820, 0.300 },
    accentDim   = { 0.600, 0.480, 0.160 },
    money       = { 1.000, 0.839, 0.286 },
    good        = { 0.400, 0.851, 0.482 },
    bad         = { 0.925, 0.373, 0.373 },
}

UI.color = C

function UI:rgb(name, alpha)
    local c = C[name]

    return c[1], c[2], c[3], alpha or 1
end

-- Choose the color name first: and/or truncates multiple return values.
function UI:rgbIf(condition, nameTrue, nameFalse, alpha)
    return self:rgb(condition and nameTrue or nameFalse, alpha)
end
