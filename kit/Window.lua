--[[
RustyKit UI kit
Copyright (C) 2026 RustyDaemon (https://github.com/RustyDaemon)

See License file for details.
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

    local bg = frame:CreateTexture(nil, "BACKGROUND", nil, -7)
    bg:SetAllPoints()
    bg:SetColorTexture(self:rgb("window", 0.97))

    self:addBorder(frame, self:rgb("borderLight"))

    local titleBar = CreateFrame("Frame", nil, frame)
    titleBar:SetPoint("TOPLEFT", 1, -1)
    titleBar:SetPoint("TOPRIGHT", -1, -1)
    titleBar:SetHeight(compact and 36 or 44)

    local titleFill = self:gradient(titleBar, "BACKGROUND", "VERTICAL",
        0.055, 0.059, 0.070, 1, 0.114, 0.106, 0.075, 1)
    titleFill:SetAllPoints()

    local title = self:text(titleBar, compact and 13 or 15, "text")
    title:SetText(options.title or "")

    if (compact) then
        title:SetPoint("LEFT", PAD, 0)
    else
        local titleLine = titleBar:CreateTexture(nil, "ARTWORK")
        titleLine:SetPoint("BOTTOMLEFT")
        titleLine:SetPoint("BOTTOMRIGHT")
        titleLine:SetHeight(1)
        titleLine:SetColorTexture(self:rgb("accentDim", 0.6))

        local logo = titleBar:CreateTexture(nil, "ARTWORK")
        logo:SetSize(24, 24)
        logo:SetPoint("LEFT", PAD, 0)
        logo:SetTexture(logoTexture())
        logo:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        local logoBorder = titleBar:CreateTexture(nil, "BACKGROUND")
        logoBorder:SetPoint("TOPLEFT", logo, "TOPLEFT", -1, 1)
        logoBorder:SetPoint("BOTTOMRIGHT", logo, "BOTTOMRIGHT", 1, -1)
        logoBorder:SetColorTexture(self:rgb("accentDim"))

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

    self:addShadow(frame, 6, 0.45)
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
