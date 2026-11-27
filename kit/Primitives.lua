--[[
RustyKit UI kit 1.5.0
Copyright (C) 2026 RustyDaemon (https://github.com/RustyDaemon)

See License file for details.

Synced from RustyKit (https://github.com/RustyDaemon/RustyKit): change it there, not in this copy.
--]]

-- The building blocks every control is made of: borders, panels, text, hover fades.

local _, ns = ...
local UI = ns.UI

-- One physical screen pixel in a region's own units. The UI is 768 units tall at scale 1, so a line
-- one unit thick lands between pixels at most UI scales.
function UI:pixel(region)
    local height = GetPhysicalScreenSize and select(2, GetPhysicalScreenSize())
    local scale = region and region:GetEffectiveScale()

    if (not height or height <= 0 or not scale or scale <= 0) then return 1 end

    return 768 / height / scale
end

local measures = {}

-- Runs measure now, and again whenever the UI scale or the screen size changes.
function UI:pixelPerfect(measure)
    measures[#measures + 1] = measure
    measure()
end

local scaleWatcher = CreateFrame("Frame")

-- The UI scale is only known for sure once the player is in the world, and Edit Mode scales the
-- frames it lays out (an addon may border one of them). A client that lacks one of the events
-- refuses to register it, and the others still count.
for _, event in ipairs({ "UI_SCALE_CHANGED", "DISPLAY_SIZE_CHANGED", "PLAYER_ENTERING_WORLD",
    "EDIT_MODE_LAYOUTS_UPDATED" }) do
    pcall(scaleWatcher.RegisterEvent, scaleWatcher, event)
end

local measurePending = false

-- A frame's effective scale has caught up with the change only by the next frame. Events that come
-- together, as a new resolution's do, measure once.
scaleWatcher:SetScript("OnEvent", function()
    if (measurePending) then return end

    measurePending = true

    C_Timer.After(0, function()
        measurePending = false

        for _, measure in ipairs(measures) do pcall(measure) end
    end)
end)

-- Snapping rounds each side of a texture to the pixel grid on its own, so a one-pixel line whose
-- edge falls on a half pixel rounds to nothing and that side of a border goes missing. Unsnapped,
-- a line exactly a pixel thick always covers exactly one pixel.
function UI:crisp(texture)
    if (texture.SetSnapToPixelGrid) then
        texture:SetSnapToPixelGrid(false)
        texture:SetTexelSnappingBias(0)
    end
end

-- Makes texture, already anchored along two corners, a line one physical pixel thick on owner:
-- tall for "horizontal", wide otherwise.
function UI:pixelLine(owner, texture, orientation)
    self:crisp(texture)

    self:pixelPerfect(function()
        if (orientation == "horizontal") then
            texture:SetHeight(UI:pixel(owner))
        else
            texture:SetWidth(UI:pixel(owner))
        end
    end)

    return texture
end

-- Which way each of a border's four lines (top, bottom, left, right) runs.
local BORDER_SIDES = { "horizontal", "horizontal", "vertical", "vertical" }

-- A corner piece `size` units square at `spot`, moved by x, y. The textures are drawn for the top left
-- corner; the bottom right's is the same turned half round.
local function cornerPiece(owner, file, size, spot, x, y, layer, subLevel)
    local piece = owner:CreateTexture(nil, layer, nil, subLevel)

    piece:SetTexture(UI.MEDIA .. file)
    piece:SetSize(size, size)
    piece:SetPoint(spot, x, y)

    if (spot == "BOTTOMRIGHT") then piece:SetTexCoord(1, 0, 1, 0) end

    return piece
end

-- A fill with two corners cut, standing in for a texture: what is asked of it reaches every piece. The
-- corners keep their own shape, so a color reaches them as a tint, and a surface texture stops short
-- of them. It takes only the calls below, the ones that paint, fade or show: under a cut theme a
-- control's bg and hover are one of these, not a texture, and are placed once, here.
local CutFill = {}
CutFill.__index = CutFill

function CutFill:SetColorTexture(r, g, b, a)
    for _, strip in ipairs(self.strips) do strip:SetColorTexture(r, g, b, a) end
    for _, piece in ipairs(self.corners) do piece:SetVertexColor(r, g, b, a) end
end

function CutFill:SetTexture(file)
    for _, strip in ipairs(self.strips) do strip:SetTexture(file) end
end

-- A method that reaches every piece or, `answers`, one that asks: the first piece answers for them all.
local function forwardAll(name, answers)
    CutFill[name] = function(self, ...)
        if (answers) then return self.pieces[1][name](self.pieces[1], ...) end

        for _, piece in ipairs(self.pieces) do piece[name](piece, ...) end
    end
end

for _, name in ipairs({ "SetVertexColor", "SetAlpha", "Show", "Hide", "SetShown", "SetDrawLayer" }) do
    forwardAll(name)
end

for _, name in ipairs({ "GetAlpha", "IsShown" }) do forwardAll(name, true) end

-- Fills `frame` with its top left and bottom right corners cut `cut` units in, reaching `outset` units
-- past its edges (a shadow). Pieced so nothing overlaps, which would show darker through an alpha: a
-- band the whole width, a strip above it right of the top-left cut, one below it left of the
-- bottom-right cut, and the two corners' inner halves.
local function cutFill(frame, layer, subLevel, cut, outset)
    local o = outset or 0
    local strips = {}

    for i = 1, 3 do strips[i] = frame:CreateTexture(nil, layer, nil, subLevel) end

    strips[1]:SetPoint("TOPLEFT", -o, o - cut)
    strips[1]:SetPoint("BOTTOMRIGHT", o, cut - o)

    strips[2]:SetPoint("TOPLEFT", cut - o, o)
    strips[2]:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", o, o - cut)

    strips[3]:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", -o, cut - o)
    strips[3]:SetPoint("BOTTOMRIGHT", o - cut, -o)

    local corners = {
        cornerPiece(frame, "cut", cut, "TOPLEFT", -o, o, layer, subLevel),
        cornerPiece(frame, "cut", cut, "BOTTOMRIGHT", o, -o, layer, subLevel),
    }

    local pieces = { strips[1], strips[2], strips[3], corners[1], corners[2] }

    return setmetatable({ strips = strips, corners = corners, pieces = pieces }, CutFill)
end

-- A fill for `frame` in a palette color: one texture over all of it, or, `cut` above 0, pieced with its
-- top left and bottom right corners cut that far in (UI:cornerCut). Answers it, to paint again.
function UI:fill(frame, colorName, alpha, layer, subLevel, cut)
    local fill

    if (cut and cut > 0) then
        fill = cutFill(frame, layer or "BACKGROUND", subLevel, cut)
    else
        fill = frame:CreateTexture(nil, layer or "BACKGROUND", nil, subLevel)
        fill:SetAllPoints()
    end

    return self:paint(fill, colorName, alpha)
end

-- The four sides of a border whose top left and bottom right corners are cut `cut` units in, each
-- stopping where a cut begins, and the cuts drawn across the corners in the accent, over a hover fill.
-- Its sides are always the kit's own one-pixel lines: UI.onBorder sizes square borders only.
local function addCutBorder(frame, r, g, b, a, cut)
    local sides = {}

    for i = 1, 4 do
        local line = frame:CreateTexture(nil, "BORDER")
        line:SetColorTexture(r, g, b, a)
        sides[i] = line
    end

    sides[1]:SetPoint("TOPLEFT", cut, 0)
    sides[1]:SetPoint("TOPRIGHT")

    sides[2]:SetPoint("BOTTOMLEFT")
    sides[2]:SetPoint("BOTTOMRIGHT", -cut, 0)

    sides[3]:SetPoint("TOPLEFT", 0, -cut)
    sides[3]:SetPoint("BOTTOMLEFT")

    sides[4]:SetPoint("TOPRIGHT")
    sides[4]:SetPoint("BOTTOMRIGHT", 0, cut)

    for i = 1, 4 do UI:pixelLine(frame, sides[i], BORDER_SIDES[i]) end

    local cuts = {
        cornerPiece(frame, "cut-edge", cut, "TOPLEFT", 0, 0, "OVERLAY", -8),
        cornerPiece(frame, "cut-edge", cut, "BOTTOMRIGHT", 0, 0, "OVERLAY", -8),
    }

    for _, piece in ipairs(cuts) do piece:SetVertexColor(UI:rgb("accent")) end

    frame.borderTextures = sides
    frame.cutEdges = cuts

    frame.SetBorderColor = function(_, br, bg, bb, ba)
        for i = 1, 4 do
            sides[i]:SetColorTexture(br, bg, bb, ba or 1)
        end
    end

    return frame
end

local function addBorder(frame, r, g, b, a, cut)
    if (cut and cut > 0) then return addCutBorder(frame, r, g, b, a, cut) end

    local edges = {}

    for i = 1, 4 do
        local line = frame:CreateTexture(nil, "BORDER")
        line:SetColorTexture(r, g, b, a)
        edges[i] = line
    end

    edges[1]:SetPoint("TOPLEFT")
    edges[1]:SetPoint("TOPRIGHT")

    edges[2]:SetPoint("BOTTOMLEFT")
    edges[2]:SetPoint("BOTTOMRIGHT")

    edges[3]:SetPoint("TOPLEFT")
    edges[3]:SetPoint("BOTTOMLEFT")

    edges[4]:SetPoint("TOPRIGHT")
    edges[4]:SetPoint("BOTTOMRIGHT")

    frame.borderTextures = edges

    frame.SetBorderColor = function(_, br, bg, bb, ba)
        for i = 1, 4 do
            edges[i]:SetColorTexture(br, bg, bb, ba or 1)
        end
    end

    -- An addon that draws the kit's borders its own way sets UI.onBorder, which gets the finished
    -- border's four lines one unit thick and sizes them as it likes: the kit never measures them.
    if (UI.onBorder) then
        for i = 1, 4 do
            if (BORDER_SIDES[i] == "horizontal") then edges[i]:SetHeight(1) else edges[i]:SetWidth(1) end
        end

        UI.onBorder(frame, edges)
    else
        for i = 1, 4 do UI:pixelLine(frame, edges[i], BORDER_SIDES[i]) end
    end

    return frame
end

UI.addBorder = function(_, frame, ...) return addBorder(frame, ...) end

-- Fills a texture with a palette color: flat, or over the addon's surface texture (UI:setSurface)
-- tinted by the color when it set one.
function UI:paint(texture, colorName, alpha)
    if (self.surface) then
        texture:SetTexture(self.surface)
        texture:SetVertexColor(self:rgb(colorName, alpha))
    else
        texture:SetColorTexture(self:rgb(colorName, alpha))
    end

    return texture
end

-- A drop shadow in the theme's shadow color (black on dark) extending `inset` pixels past each edge
-- of the frame, its corners cut as the frame's are when given `cut`.
function UI:addShadow(frame, inset, alpha, subLevel, cut)
    if (cut and cut > 0) then
        -- Pushed out by `inset`, a 45-degree cut reaches about 0.6 of that further along each side.
        return self:paint(cutFill(frame, "BACKGROUND", subLevel or -8, cut + inset * 0.6, inset), "shadow", alpha)
    end

    local shadow = frame:CreateTexture(nil, "BACKGROUND", nil, subLevel or -8)
    shadow:SetPoint("TOPLEFT", -inset, inset)
    shadow:SetPoint("BOTTOMRIGHT", inset, -inset)
    shadow:SetColorTexture(self:rgb("shadow", alpha))

    return shadow
end

-- A panel in a palette color, bordered or not; `cut` above 0 cuts its top left and bottom right
-- corners that far in (UI:cornerCut, which is 0 on a theme without cuts).
function UI:panel(parent, colorName, bordered, alpha, cut)
    local frame = CreateFrame("Frame", nil, parent)
    local bg = self:fill(frame, colorName or "panel", alpha, "BACKGROUND", nil, cut)

    frame.bg = bg

    frame.SetPanelColor = function(_, name, a)
        UI:paint(bg, name, a)
    end

    if (bordered) then
        local r, g, b, a = self:rgb("border")

        addBorder(frame, r, g, b, a, cut)
    end

    return frame
end

function UI:text(parent, size, colorName, flags)
    local fs = parent:CreateFontString(nil, "OVERLAY")

    fs:SetFont(self.font, self:fontSize(size or 12), flags or "")
    fs:SetTextColor(self:rgb(colorName or "text"))
    fs:SetShadowColor(self:rgb("textShadow"))
    fs:SetShadowOffset(1, -1)

    return fs
end

-- Numbers draw outlined on the dark theme; the theme says how.
function UI:number(parent, size, colorName)
    local fs = parent:CreateFontString(nil, "OVERLAY")

    fs:SetFont(self.fontNumber, self:fontSize(size or 16), self.numberFlags)
    fs:SetTextColor(self:rgb(colorName or "text"))

    return fs
end

function UI:gradient(parent, layer, orientation, r1, g1, b1, a1, r2, g2, b2, a2)
    local tex = parent:CreateTexture(nil, layer or "ARTWORK")

    tex:SetColorTexture(1, 1, 1, 1)
    tex:SetGradient(orientation,
        CreateColor(r1, g1, b1, a1),
        CreateColor(r2, g2, b2, a2))

    return tex
end

function UI:tooltip(frame, title, body, anchor)
    frame.tooltipTitle = title
    frame.tooltipBody = body

    frame:HookScript("OnEnter", function(self)
        if (not self.tooltipTitle) then return end

        local titleText = type(self.tooltipTitle) == "function" and self.tooltipTitle() or self.tooltipTitle

        if (not titleText) then return end

        GameTooltip:SetOwner(self, anchor or "ANCHOR_TOP")
        GameTooltip:SetText(titleText, 1, 1, 1)

        local bodyText = type(self.tooltipBody) == "function" and self.tooltipBody() or self.tooltipBody

        -- The game's tooltip stays dark whatever the theme, so its body has a color of its own.
        if (bodyText) then
            local r, g, b = UI:rgb("tooltipBody")

            GameTooltip:AddLine(bodyText, r, g, b, true)
        end

        GameTooltip:Show()
    end)

    frame:HookScript("OnLeave", function() GameTooltip:Hide() end)

    return frame
end

-- A fill that fades in under the mouse, its corners cut `cut` in when the frame's are.
local function attachHover(frame, colorName, maxAlpha, layer, cut)
    local hl = UI:fill(frame, colorName or "panelHover", nil, layer or "ARTWORK", nil, cut)

    hl:SetAlpha(0)

    frame.hover = hl
    frame.hoverTarget = 0
    frame.hoverMax = maxAlpha or 1

    frame:HookScript("OnEnter", function(self) self.hoverTarget = self.hoverMax end)
    frame:HookScript("OnLeave", function(self) self.hoverTarget = 0 end)

    frame:HookScript("OnUpdate", function(self, elapsed)
        local current = hl:GetAlpha()
        local target = self.hoverTarget or 0

        if (math.abs(current - target) < 0.01) then
            if (current ~= target) then hl:SetAlpha(target) end
            return
        end

        hl:SetAlpha(current + (target - current) * math.min(elapsed * 12, 1))
    end)

    return hl
end

UI.attachHover = function(_, frame, ...) return attachHover(frame, ...) end

function UI:sectionHeading(parent, text)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetHeight(20)

    local label = self:text(frame, 11, "textFaint")
    label:SetPoint("LEFT", 2, 0)
    label:SetText(text)

    local rule = frame:CreateTexture(nil, "ARTWORK")
    rule:SetPoint("LEFT", label, "RIGHT", 8, 0)
    rule:SetPoint("RIGHT", -2, 0)
    rule:SetColorTexture(UI:rgb("border"))
    self:pixelLine(frame, rule, "horizontal")

    frame.label = label

    return frame
end
