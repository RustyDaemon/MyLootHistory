--[[
RustyKit UI kit 1.3.0
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

local function addBorder(frame, r, g, b, a)
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

-- Black drop shadow extending `inset` pixels past each edge of the frame.
function UI:addShadow(frame, inset, alpha, subLevel)
    local shadow = frame:CreateTexture(nil, "BACKGROUND", nil, subLevel or -8)
    shadow:SetPoint("TOPLEFT", -inset, inset)
    shadow:SetPoint("BOTTOMRIGHT", inset, -inset)
    shadow:SetColorTexture(0, 0, 0, alpha)

    return shadow
end

function UI:panel(parent, colorName, bordered, alpha)
    local frame = CreateFrame("Frame", nil, parent)
    local bg = frame:CreateTexture(nil, "BACKGROUND")

    bg:SetAllPoints()
    bg:SetColorTexture(self:rgb(colorName or "panel", alpha))

    frame.bg = bg

    frame.SetPanelColor = function(_, name, a)
        bg:SetColorTexture(UI:rgb(name, a))
    end

    if (bordered) then
        addBorder(frame, self:rgb("border"))
    end

    return frame
end

function UI:text(parent, size, colorName, flags)
    local fs = parent:CreateFontString(nil, "OVERLAY")

    fs:SetFont(self.font, self:fontSize(size or 12), flags or "")
    fs:SetTextColor(self:rgb(colorName or "text"))
    fs:SetShadowColor(0, 0, 0, 0.9)
    fs:SetShadowOffset(1, -1)

    return fs
end

function UI:number(parent, size, colorName)
    local fs = parent:CreateFontString(nil, "OVERLAY")

    fs:SetFont(self.fontNumber, self:fontSize(size or 16), "OUTLINE")
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

        if (bodyText) then
            local r, g, b = UI:rgb("textDim")

            GameTooltip:AddLine(bodyText, r, g, b, true)
        end

        GameTooltip:Show()
    end)

    frame:HookScript("OnLeave", function() GameTooltip:Hide() end)

    return frame
end

local function attachHover(frame, colorName, maxAlpha, layer)
    local hl = frame:CreateTexture(nil, layer or "ARTWORK")

    hl:SetAllPoints()
    hl:SetColorTexture(UI:rgb(colorName or "panelHover"))
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
