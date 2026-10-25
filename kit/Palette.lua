--[[
RustyKit UI kit 1.1.0
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

local fontScale = 1

-- Every size the kit asks for, scaled by a font size setting (a percent); like the font, it reaches
-- text built after the call. Anything but a number means 100%, and the scale stays within 50-200%, so
-- a broken saved value can neither blow text up nor shrink it away.
function UI:setFontScale(percent)
    local value = tonumber(percent)

    if (not value or value ~= value) then value = 100 end

    fontScale = math.min(math.max(value, 50), 200) / 100
end

-- Whole pixels only: a pixel font between sizes draws soft.
function UI:fontSize(size)
    return math.max(math.floor(size * fontScale + 0.5), 6)
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

    -- accent, accentDim and accentLit come from UI.accents, below.
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

-- The accents an addon can offer. Gold is the kit's own, the one every addon has until it picks
-- another; the others keep its brightness so text stays readable.
UI.accents = {
    { value = "gold",   text = "Gold",
      accent = { 1.000, 0.820, 0.300 }, dim = { 0.600, 0.480, 0.160 }, lit = { 0.240, 0.190, 0.060 } },
    { value = "rust",   text = "Rust",
      accent = { 0.945, 0.522, 0.298 }, dim = { 0.580, 0.298, 0.157 }, lit = { 0.240, 0.118, 0.059 } },
    { value = "teal",   text = "Teal",
      accent = { 0.345, 0.827, 0.784 }, dim = { 0.169, 0.471, 0.447 }, lit = { 0.059, 0.180, 0.169 } },
    { value = "violet", text = "Violet",
      accent = { 0.698, 0.565, 1.000 }, dim = { 0.400, 0.310, 0.639 }, lit = { 0.149, 0.110, 0.251 } },
    { value = "azure",  text = "Azure",
      accent = { 0.380, 0.651, 1.000 }, dim = { 0.220, 0.380, 0.600 }, lit = { 0.090, 0.157, 0.251 } },
    { value = "rose",   text = "Rose",
      accent = { 1.000, 0.502, 0.678 }, dim = { 0.600, 0.294, 0.400 }, lit = { 0.251, 0.122, 0.169 } },
    { value = "fel",    text = "Fel",
      accent = { 0.616, 0.882, 0.318 }, dim = { 0.369, 0.529, 0.188 }, lit = { 0.149, 0.212, 0.075 } },
    { value = "frost",  text = "Frost",
      accent = { 0.702, 0.855, 0.980 }, dim = { 0.420, 0.510, 0.588 }, lit = { 0.169, 0.204, 0.239 } },
}

-- Colors are handed out as copies, so code that changes one in place never reaches a preset.
local function copy(color, scale)
    scale = scale or 1

    return { color[1] * scale, color[2] * scale, color[3] * scale }
end

local NEUTRAL_BORDER, NEUTRAL_BORDER_LIGHT = copy(C.border), copy(C.borderLight)

local accentBorders = false

-- Borders in the accent instead of grey: the plain border a darker shade of it, so the light one
-- (hover, outlines) still stands out.
local function paintBorders()
    if (accentBorders) then
        C.border, C.borderLight = copy(C.accentDim, 0.7), copy(C.accentDim)
    else
        C.border, C.borderLight = copy(NEUTRAL_BORDER), copy(NEUTRAL_BORDER_LIGHT)
    end
end

-- Swaps in an accent by its key, for everything colored from here on; accent borders follow it. A
-- key it does not know keeps the current one.
function UI:setAccent(key)
    for _, preset in ipairs(self.accents) do
        if (preset.value == key) then
            C.accent, C.accentDim, C.accentLit = copy(preset.accent), copy(preset.dim), copy(preset.lit)
            paintBorders()
            return
        end
    end
end

-- Turns accent borders on or off, in whichever order it and setAccent are called.
function UI:setAccentBorders(on)
    accentBorders = on and true or false
    paintBorders()
end

-- Every addon starts on gold, the kit's own accent.
UI:setAccent("gold")
