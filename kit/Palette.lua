--[[
RustyKit UI kit 1.0.0
Copyright (C) 2026 RustyDaemon (https://github.com/RustyDaemon)

See License file for details.

Synced from RustyKit (https://github.com/RustyDaemon/RustyKit): change it there, not in this copy.
--]]

-- The kit's colors and fonts. Creates ns.UI, so it loads before the rest of kit/.

local ADDON, ns = ...

local UI = {}
ns.UI = UI

-- The game's own fonts by default, so every locale keeps its own alphabet.
local BLIZZARD_FONT = GameFontNormal:GetFont()
local BLIZZARD_NUMBER = (NumberFontNormal and NumberFontNormal:GetFont()) or BLIZZARD_FONT

local KIT_PATH = "Interface\\AddOns\\" .. ADDON .. "\\kit\\"

UI.font = BLIZZARD_FONT
UI.fontNumber = BLIZZARD_NUMBER

-- The fonts an addon can offer. Rusty Pixel, built by RustyKit's tools/font/build_font.py, has
-- Latin letters with the common accents but no Cyrillic, Korean or Chinese; its digits share one
-- width, so it serves numbers too.
UI.fonts = {
    { value = "blizzard", text = "Blizzard" },
    { value = "pixel",    text = "Rusty Pixel", file = KIT_PATH .. "fonts\\RustyPixel.ttf" },
}

local preload = nil

-- Picks the font for everything built from here on; windows already built keep theirs until a
-- reload. Called once the saved settings are loaded, before any window exists. A key it does not
-- know means the game's font.
function UI:setFont(key)
    local file = nil

    for _, preset in ipairs(self.fonts) do
        if (preset.value == key) then
            file = preset.file
            break
        end
    end

    if (file) then
        -- A font file is loaded on first use, and until then GetStringWidth() measures 0. Touch it
        -- now so it is ready before any window sizes itself around its text.
        preload = preload or CreateFont(ADDON .. "FontPreload")
        preload:SetFont(file, 12, "")

        -- A file the client cannot find (one added since the game started, until a restart) leaves the
        -- font object without a font. The game's font then draws, rather than no text at all.
        if (not preload:GetFont()) then file = nil end
    end

    self.font = file or BLIZZARD_FONT
    self.fontNumber = file or BLIZZARD_NUMBER
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
