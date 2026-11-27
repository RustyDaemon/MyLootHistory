--[[
RustyKit UI kit 1.6.0
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

-- A font object per font file, so what one reports is about its own file and not one loaded before.
local preloads, preloadCount = {}, 0

-- The font file, loaded, or nil when there is none or the client cannot find it.
local function preloaded(file)
    if (type(file) ~= "string" or file == "") then return nil end

    -- A font file is loaded on first use, and until then GetStringWidth() measures 0. Touch it now so
    -- it is ready before any window sizes itself around its text.
    local preload = preloads[file]

    if (not preload) then
        preloadCount = preloadCount + 1
        preload = CreateFont(ADDON .. "FontPreload" .. preloadCount)
        preloads[file] = preload
    end

    preload:SetFont(file, 12, "")

    -- A file the client cannot find (one added since the game started, until a restart) leaves the
    -- font object without a font. The game's font then draws, rather than no text at all.
    if (not preload:GetFont()) then return nil end

    return file
end

-- Draws everything built from here on in a font file of the addon's own, and numbers in numberFile
-- when it gives one (else in the same file). A file the client cannot find, or none, means the game's
-- font for that part. Like setFont, it reaches what is built after the call.
function UI:setFontFile(file, numberFile)
    local text = preloaded(file)
    local number = text

    if (numberFile ~= nil) then number = preloaded(numberFile) end

    self.font = text or BLIZZARD_FONT
    self.fontNumber = number or BLIZZARD_NUMBER
end

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

    self:setFontFile(file)
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

-- The colors in use, filled in from the theme and the accent below. A color with a fourth value
-- carries its own alpha, used when the caller asks for none.
local C = {}

UI.color = C

function UI:rgb(name, alpha)
    local c = C[name]

    return c[1], c[2], c[3], alpha or c[4] or 1
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

-- The looks an addon can pick. Dark is the kit's own, the one every addon has until it picks another.
-- Each theme gives every color but the accent, which comes from its own accent preset until the
-- addon picks one of UI.accents, and those every theme shares (below). A color given as another's
-- name follows that one, accent borders included. fadeTo is what a shade of the accent recedes toward
-- (the plain accent border), and numberFlags the outline numbers draw with. cut, when a theme has one,
-- is how far windows and the controls that ask (UI:cornerCut) cut their top left and bottom right
-- corners in, in UI units; a theme without one keeps every corner square.

-- Dark's colors, which Tactical shares: it differs in its corners, not its colors.
local DARK_COLORS = {
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
    textShadow  = { 0.00, 0.00, 0.00, 0.9 },

    money       = { 1.000, 0.839, 0.286 },
    good        = { 0.400, 0.851, 0.482 },
    bad         = { 0.925, 0.373, 0.373 },

    -- A window's title bar fades from its bottom color up to its top one.
    titleBottom = { 0.055, 0.059, 0.070 },
    titleTop    = { 0.114, 0.106, 0.075 },

    -- A button lit up under the mouse.
    buttonHover = "borderLight",
}

UI.themes = {
    {
        value = "dark", text = "Dark",
        accent = UI.accents[1],
        fadeTo = { 0, 0, 0 },
        numberFlags = "OUTLINE",
        colors = DARK_COLORS,
    },
    {
        -- Cream paper, brown ink, borders in faded ink and rubric red for the accent. Text carries no
        -- drop shadow and numbers no outline: both are black, and smudge ink on paper.
        value = "paper", text = "Paper",
        accent = { value = "rubric", text = "Rubric",
            accent = { 0.561, 0.169, 0.110 }, dim = { 0.647, 0.341, 0.263 }, lit = { 0.859, 0.749, 0.631 } },
        fadeTo = { 0.910, 0.851, 0.722 },
        numberFlags = "",
        colors = {
            shadow      = { 0.165, 0.110, 0.071 },
            window      = { 0.910, 0.851, 0.722 },
            panel       = { 0.839, 0.765, 0.596 },
            panelHover  = { 0.855, 0.784, 0.627 },
            raised      = { 0.875, 0.808, 0.659 },
            border      = { 0.549, 0.463, 0.376 },
            borderLight = { 0.369, 0.290, 0.220 },

            text        = { 0.165, 0.110, 0.071 },
            textDim     = { 0.369, 0.290, 0.220 },
            textFaint   = { 0.549, 0.463, 0.376 },
            textShadow  = { 0.165, 0.110, 0.071, 0 },

            money       = { 0.463, 0.322, 0.031 },
            good        = { 0.165, 0.388, 0.149 },
            bad         = { 0.627, 0.110, 0.110 },

            titleBottom = { 0.839, 0.765, 0.596 },
            titleTop    = { 0.875, 0.808, 0.659 },

            buttonHover = { 0.769, 0.678, 0.502 },
        },
    },
    {
        -- Dark with its corners cut: a window's and a control's top left and bottom right corners cut
        -- in on the diagonal, the cuts drawn in the accent. Its title bar is flat, the window's own
        -- dark, as a fade could not follow the cut.
        value = "tactical", text = "Tactical",
        accent = UI.accents[1],
        fadeTo = { 0, 0, 0 },
        numberFlags = "OUTLINE",
        cut = 10,
        colors = DARK_COLORS,
    },
}

-- Colors every theme shares: they paint something of the game's own, whose look no theme changes.
-- A theme's color may name one of them.
local SHARED_COLORS = {
    -- Body text in the game's own tooltip, which stays dark whatever the theme.
    tooltipBody = { 0.596, 0.620, 0.678 },
}

-- Colors are handed out as copies, so code that changes one in place never reaches a preset. A
-- color's own alpha goes with it.
local function copy(color, scale)
    scale = scale or 1

    return { color[1] * scale, color[2] * scale, color[3] * scale, color[4] }
end

local theme = UI.themes[1]
local chosenAccent = nil
local accentBorders = false

-- The accent, the borders and the colors that follow another, from the theme and the addon's picks.
-- Accent borders draw the light border (hover, outlines) in the accent's dim shade and the plain one
-- a shade of it faded toward the theme's ground, so the light one still stands out.
local function paintAccent()
    local preset = chosenAccent or theme.accent

    C.accent, C.accentDim, C.accentLit = copy(preset.accent), copy(preset.dim), copy(preset.lit)

    if (accentBorders) then
        local dim, fade = C.accentDim, theme.fadeTo

        C.border = { dim[1] * 0.7 + fade[1] * 0.3, dim[2] * 0.7 + fade[2] * 0.3, dim[3] * 0.7 + fade[3] * 0.3 }
        C.borderLight = copy(dim)
    else
        C.border, C.borderLight = copy(theme.colors.border), copy(theme.colors.borderLight)
    end

    -- A color named after another follows the name to a color of its own, however many names deep,
    -- so the order the colors are visited in never matters.
    for name, value in pairs(theme.colors) do
        if (type(value) == "string") then
            local target = value

            while (type(theme.colors[target]) == "string") do target = theme.colors[target] end

            C[name] = copy(C[target])
        end
    end
end

-- Swaps in a theme by its key, for everything built from here on; windows already built keep their
-- colors until a reload. The theme's own accent comes with it unless the addon has picked one, in
-- whichever order the two are called. A key it does not know keeps the current theme.
function UI:setTheme(key)
    for _, preset in ipairs(self.themes) do
        if (preset.value == key) then
            theme = preset

            for name, value in pairs(SHARED_COLORS) do C[name] = copy(value) end

            for name, value in pairs(theme.colors) do
                if (type(value) == "table") then C[name] = copy(value) end
            end

            self.theme = theme.value
            self.numberFlags = theme.numberFlags
            self.cut = theme.cut or 0
            paintAccent()
            return
        end
    end
end

-- Swaps in an accent by its key, for everything colored from here on, over the theme's own; accent
-- borders follow it. nil goes back to the theme's own accent; any other key it does not know keeps the
-- current one. The presets are made for the dark theme: their lit shade is a dark one, so on another
-- theme its own accent is the one that fits.
function UI:setAccent(key)
    if (key == nil) then
        chosenAccent = nil
        paintAccent()
        return
    end

    for _, preset in ipairs(self.accents) do
        if (preset.value == key) then
            chosenAccent = preset
            paintAccent()
            return
        end
    end
end

-- Turns accent borders on or off, in whichever order it and setAccent are called.
function UI:setAccentBorders(on)
    accentBorders = on and true or false
    paintAccent()
end

-- A texture file of the addon's own (paper grain, say) that window backgrounds and the controls'
-- filled surfaces draw tinted by their color, from here on; nil, or anything but a path, means flat
-- color as before. The texture is stretched over each surface and multiplied by its color, so a light,
-- near-white one keeps the theme's colors. The client cannot say whether the file exists, so there is
-- no falling back to flat color for a missing one: the addon has to ship it. A panel built before the
-- call takes the surface the next time its color changes (SetPanelColor, say), not before.
function UI:setSurface(file)
    self.surface = (type(file) == "string" and file ~= "") and file or nil
end

-- The kit's own textures: the corner pieces a cut theme draws, 64x64 white TGAs the game tints (the
-- same as RustyUI's HUD corners, drawn by its tools/make-hud-textures.py).
UI.MEDIA = KIT_PATH .. "media\\"

-- How far a corner `size` units across (a control's height, say) is cut in under the current theme: 0
-- on a theme without cuts, else the theme's cut, held to a quarter of the size so a small control
-- keeps most of its edge. With no size, the theme's whole cut, for a window or a panel.
function UI:cornerCut(size)
    if (self.cut <= 0) then return 0 end

    if (size == nil) then return self.cut end

    return math.max(math.min(self.cut, math.floor(size / 4)), 0)
end

-- Every addon starts dark, on gold, the kit's own look.
UI:setTheme("dark")
