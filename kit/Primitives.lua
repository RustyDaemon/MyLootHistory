--[[
My Loot History addon
Copyright (C) 2026 RustyDaemon (https://github.com/RustyDaemon)

See License file for details.
--]]

-- The building blocks every control is made of: borders, panels, text, hover fades.

local MLH = LibStub("AceAddon-3.0"):GetAddon("MyLootHistory")
local UI = MLH.UI

local FONT = UI.font
local FONT_NUMBER = UI.fontNumber

local function addBorder(frame, r, g, b, a)
    local edges = {}

    for i = 1, 4 do
        local line = frame:CreateTexture(nil, "BORDER")
        line:SetColorTexture(r, g, b, a)
        edges[i] = line
    end

    edges[1]:SetPoint("TOPLEFT")
    edges[1]:SetPoint("TOPRIGHT")
    edges[1]:SetHeight(1)

    edges[2]:SetPoint("BOTTOMLEFT")
    edges[2]:SetPoint("BOTTOMRIGHT")
    edges[2]:SetHeight(1)

    edges[3]:SetPoint("TOPLEFT")
    edges[3]:SetPoint("BOTTOMLEFT")
    edges[3]:SetWidth(1)

    edges[4]:SetPoint("TOPRIGHT")
    edges[4]:SetPoint("BOTTOMRIGHT")
    edges[4]:SetWidth(1)

    frame.borderTextures = edges

    frame.SetBorderColor = function(_, br, bg, bb, ba)
        for i = 1, 4 do
            edges[i]:SetColorTexture(br, bg, bb, ba or 1)
        end
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

    fs:SetFont(FONT, size or 12, flags or "")
    fs:SetTextColor(self:rgb(colorName or "text"))
    fs:SetShadowColor(0, 0, 0, 0.9)
    fs:SetShadowOffset(1, -1)

    return fs
end

function UI:number(parent, size, colorName)
    local fs = parent:CreateFontString(nil, "OVERLAY")

    fs:SetFont(FONT_NUMBER, size or 16, "OUTLINE")
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
    rule:SetHeight(1)
    rule:SetColorTexture(UI:rgb("border"))

    frame.label = label

    return frame
end
