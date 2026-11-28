--[[
RustyKit UI kit 1.6.1
Copyright (C) 2026 RustyDaemon (https://github.com/RustyDaemon)

See License file for details.

Synced from RustyKit (https://github.com/RustyDaemon/RustyKit): change it there, not in this copy.
--]]

-- The frame every window of the addon is built in: shadow, border, a title bar to drag it by and a
-- close button. What goes inside is up to the window.

local ADDON, ns = ...
local UI = ns.UI

local PAD = 14

local getMetadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata

-- The title bar's logo: UI.logo when the addon sets one, otherwise the icon its .toc gives the AddOns
-- list, and a question mark on a client that does not say.
local function logoTexture()
    return UI.logo or getMetadata(ADDON, "IconTexture") or "Interface\\Icons\\INV_Misc_QuestionMark"
end

-- Dresses a frame as one of the addon's windows: background, border and a title bar with the logo,
-- the title and the subtitle. options:
--   compact       a slimmer title bar with no logo and no rule, for a window opened from another one
--   title         the title bar's text
--   subtitle      fainter text after the title, if any
-- The frame gains titleBar, title and subtitle, and logo unless compact.
function UI:chrome(frame, options)
    local compact = options.compact and true or false

    -- Its top left and bottom right corners cut on a theme that cuts them.
    local cut = self:cornerCut()
    local r, g, b, a = self:rgb("borderLight")

    self:fill(frame, "window", 0.97, "BACKGROUND", -7, cut)
    self:addBorder(frame, r, g, b, a, cut)

    local titleBar = CreateFrame("Frame", nil, frame)
    titleBar:SetPoint("TOPLEFT", 1, -1)
    titleBar:SetPoint("TOPRIGHT", -1, -1)
    titleBar:SetHeight(compact and 36 or 44)

    -- The title bar fades between the theme's two title colors, over the surface texture when the
    -- addon set one. With the corners cut it is the window's own fill: a fade could not follow the cut.
    if (cut <= 0) then
        local titleFill = titleBar:CreateTexture(nil, "BACKGROUND")

        if (self.surface) then
            titleFill:SetTexture(self.surface)
        else
            titleFill:SetColorTexture(1, 1, 1, 1)
        end

        titleFill:SetGradient("VERTICAL", CreateColor(self:rgb("titleBottom")), CreateColor(self:rgb("titleTop")))
        titleFill:SetAllPoints()
    end

    local title = self:text(titleBar, compact and 13 or 15, "text")
    title:SetText(options.title or "")

    if (compact) then
        title:SetPoint("LEFT", PAD, 0)
    else
        local titleLine = titleBar:CreateTexture(nil, "ARTWORK")
        titleLine:SetPoint("BOTTOMLEFT")
        titleLine:SetPoint("BOTTOMRIGHT")
        titleLine:SetColorTexture(self:rgb("accentDim", 0.6))
        self:pixelLine(titleBar, titleLine, "horizontal")

        local logo = titleBar:CreateTexture(nil, "ARTWORK")
        logo:SetSize(24, 24)
        logo:SetPoint("LEFT", PAD, 0)
        logo:SetTexture(logoTexture())
        logo:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        -- The logo's frame is this texture showing one pixel past the logo on every side.
        local logoBorder = titleBar:CreateTexture(nil, "BACKGROUND")
        logoBorder:SetColorTexture(self:rgb("accentDim"))
        self:crisp(logoBorder)

        self:pixelPerfect(function()
            local px = UI:pixel(titleBar)

            logoBorder:ClearAllPoints()
            logoBorder:SetPoint("TOPLEFT", logo, "TOPLEFT", -px, px)
            logoBorder:SetPoint("BOTTOMRIGHT", logo, "BOTTOMRIGHT", px, -px)
        end)

        title:SetPoint("LEFT", logo, "RIGHT", 10, 1)

        frame.logo = logo
    end

    if (options.subtitle) then
        local subtitle = self:text(titleBar, 11, "textFaint")
        subtitle:SetPoint("LEFT", title, "RIGHT", 10, 0)
        subtitle:SetText(options.subtitle)

        frame.subtitle = subtitle
    end

    frame.titleBar = titleBar
    frame.title = title

    return frame
end

-- A movable window in the addon's look. options are chrome's, and:
--   name          the frame's global name; a named window also closes on Escape
--   strata        frame strata, HIGH unless given
--   closeTooltip  the close button's tooltip, if any
--   onMoved       called once the window has been dragged somewhere new
-- The window starts hidden and unsized. It carries titleBar, title, subtitle and close.
function UI:window(options)
    local compact = options.compact and true or false

    local frame = CreateFrame("Frame", options.name, UIParent)

    frame:SetFrameStrata(options.strata or "HIGH")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:Hide()

    self:addShadow(frame, 6, 0.45, nil, self:cornerCut())
    self:chrome(frame, options)

    local titleBar = frame.titleBar

    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")

    titleBar:SetScript("OnDragStart", function() frame:StartMoving() end)
    titleBar:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()

        if (options.onMoved) then options.onMoved() end
    end)

    local close = self:iconButton(titleBar, compact and 26 or 28, "Interface\\Buttons\\UI-StopButton",
        function() frame:Hide() end)
    close:SetPoint("RIGHT", compact and -5 or -6, 0)

    if (options.closeTooltip) then self:tooltip(close, options.closeTooltip) end

    if (options.name and not tContains(UISpecialFrames, options.name)) then
        tinsert(UISpecialFrames, options.name)
    end

    frame.close = close

    return frame
end

-- Where a frame is, as a table to save: { point, relativePoint, x, y }.
function UI:savePoint(frame)
    local point, _, relativePoint, x, y = frame:GetPoint()

    return { point = point, relativePoint = relativePoint, x = x, y = y }
end

-- Puts a frame back where savePoint found it, or at the fallback point - the centre of the screen
-- unless given - when nothing was saved.
function UI:restorePoint(frame, saved, fallbackPoint, fallbackX, fallbackY)
    frame:ClearAllPoints()

    if (saved and saved.point) then
        frame:SetPoint(saved.point, UIParent, saved.relativePoint or saved.point, saved.x or 0, saved.y or 0)
    else
        frame:SetPoint(fallbackPoint or "CENTER", UIParent, fallbackPoint or "CENTER", fallbackX or 0,
            fallbackY or 0)
    end
end
