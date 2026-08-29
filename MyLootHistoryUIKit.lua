--[[
My Loot History addon
Copyright (C) 2026 RustyDaemon (https://github.com/RustyDaemon)

See License file for details.
--]]

-- The look of the addon, and every control the report is built out of.
--
-- Nothing here knows what loot is. It is a small widget kit: panels, buttons, a search box,
-- a dropdown, a toggle, a segmented control and a scrollbar, all drawn from plain textures
-- rather than the Blizzard templates, so the report can look like one designed thing instead
-- of a stack of default frames. Every widget is a frame with the handful of methods the
-- report actually calls on it.

local MLH = LibStub("AceAddon-3.0"):GetAddon("MyLootHistory")

local UI = {}
MLH.UI = UI

-- ── theme ─────────────────────────────────────────────────────────────────────

-- Read out of the client rather than hard-coded, so every locale keeps a font that can
-- draw its own alphabet.
local FONT = GameFontNormal:GetFont()
local FONT_NUMBER = (NumberFontNormal and NumberFontNormal:GetFont()) or FONT

UI.font = FONT
UI.fontNumber = FONT_NUMBER

-- A deep neutral ground with a single warm accent. Gold is the addon's subject, so it is
-- the only saturated colour in the window; everything else is a step on one grey ramp,
-- which is what keeps the quality colours of the items readable.
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

-- Choosing between two colours has to happen on the name. Writing
-- `cond and self:rgb(a) or self:rgb(b)` inline truncates the four return values down to
-- the red channel alone, which the setters reject.
function UI:rgbIf(condition, nameTrue, nameFalse, alpha)
    return self:rgb(condition and nameTrue or nameFalse, alpha)
end

-- ── primitives ────────────────────────────────────────────────────────────────

-- A 1px hairline on each edge. Four textures rather than a backdrop: backdrops carry an
-- 8px inset and a tiling edge file, neither of which can draw a crisp single-pixel line.
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

-- A flat filled rectangle with an optional hairline border. The building block of
-- everything below.
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

-- Digits in the condensed number font, which is what lets a six-figure gold total sit in
-- a column that a proportional font would overflow.
function UI:number(parent, size, colorName)
    local fs = parent:CreateFontString(nil, "OVERLAY")

    fs:SetFont(FONT_NUMBER, size or 16, "OUTLINE")
    fs:SetTextColor(self:rgb(colorName or "text"))

    return fs
end

-- A vertical or horizontal fade. Used for the title bar, the stat cards and the value
-- bars behind the rows: a flat fill reads as a box, a gradient reads as a surface.
function UI:gradient(parent, layer, orientation, r1, g1, b1, a1, r2, g2, b2, a2)
    local tex = parent:CreateTexture(nil, layer or "ARTWORK")

    tex:SetColorTexture(1, 1, 1, 1)
    tex:SetGradient(orientation,
        CreateColor(r1, g1, b1, a1),
        CreateColor(r2, g2, b2, a2))

    return tex
end

-- ── tooltips ──────────────────────────────────────────────────────────────────

-- Every widget takes its tooltip the same way: a title and an optional second line, both
-- optional, both allowed to be functions when the text changes with the state.
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

-- ── hover highlight ───────────────────────────────────────────────────────────

-- One highlight texture, faded in and out over a few frames. Widgets that snap between
-- two colours feel like a web page from 2003; the fade is most of why this kit feels
-- like part of a modern client.
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

        -- framerate-independent easing: the same feel at 30fps and at 200
        hl:SetAlpha(current + (target - current) * math.min(elapsed * 12, 1))
    end)

    return hl
end

UI.attachHover = function(_, frame, ...) return attachHover(frame, ...) end

-- ── button ────────────────────────────────────────────────────────────────────

function UI:button(parent, text, width, height, onClick)
    local button = CreateFrame("Button", nil, parent)

    button:SetSize(width or 100, height or 24)

    local bg = button:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(self:rgb("raised"))

    addBorder(button, self:rgb("border"))
    attachHover(button, "borderLight", 0.55)

    local label = self:text(button, 12, "text")
    label:SetPoint("CENTER", 0, 0)
    label:SetText(text)

    button.label = label
    button.bg = bg

    button:SetScript("OnMouseDown", function(self) label:SetPoint("CENTER", 0, -1) end)
    button:SetScript("OnMouseUp", function(self) label:SetPoint("CENTER", 0, 0) end)

    button:SetScript("OnClick", function(self, ...)
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)

        if (onClick) then onClick(self, ...) end
    end)

    button.SetLabel = function(_, value) label:SetText(value) end

    -- an accented button: one per screen at most, for the action the window is about
    button.SetAccent = function(_, on)
        if (on) then
            bg:SetColorTexture(0.24, 0.19, 0.06, 1)
            button:SetBorderColor(UI:rgb("accentDim"))
            label:SetTextColor(UI:rgb("accent"))
        else
            bg:SetColorTexture(UI:rgb("raised"))
            button:SetBorderColor(UI:rgb("border"))
            label:SetTextColor(UI:rgb("text"))
        end
    end

    return button
end

-- A square button carrying a texture instead of a label: the close cross, the gear.
function UI:iconButton(parent, size, texture, onClick, texCoord)
    local button = CreateFrame("Button", nil, parent)

    button:SetSize(size, size)
    attachHover(button, "raised", 0.9, "BACKGROUND")

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("CENTER")
    icon:SetSize(size * 0.5, size * 0.5)
    icon:SetTexture(texture)
    icon:SetVertexColor(self:rgb("textDim"))

    if (texCoord) then icon:SetTexCoord(unpack(texCoord)) end

    button.icon = icon

    button:HookScript("OnEnter", function() icon:SetVertexColor(UI:rgb("text")) end)
    button:HookScript("OnLeave", function() icon:SetVertexColor(UI:rgb("textDim")) end)

    button:SetScript("OnClick", function(self, ...)
        if (onClick) then onClick(self, ...) end
    end)

    return button
end

-- ── search box ────────────────────────────────────────────────────────────────

-- An edit box that looks like a search field: a magnifier, placeholder text while it is
-- empty, and a clear button that only exists while there is something to clear.
function UI:searchBox(parent, width, height, placeholder, onChange)
    local frame = self:panel(parent, "window", true)
    frame:SetSize(width, height or 26)

    local glass = frame:CreateTexture(nil, "ARTWORK")
    glass:SetTexture("Interface\\Common\\UI-Searchbox-Icon")
    glass:SetSize(14, 14)
    glass:SetPoint("LEFT", 7, 0)
    glass:SetVertexColor(self:rgb("textFaint"))

    local editBox = CreateFrame("EditBox", nil, frame)
    editBox:SetPoint("LEFT", 25, 0)
    editBox:SetPoint("RIGHT", -22, 0)
    editBox:SetHeight(height or 26)
    editBox:SetAutoFocus(false)
    editBox:SetFont(FONT, 12, "")
    editBox:SetTextColor(self:rgb("text"))

    local hint = self:text(frame, 12, "textFaint")
    hint:SetPoint("LEFT", 25, 0)
    hint:SetText(placeholder or "")

    local clear = self:iconButton(frame, 16, "Interface\\Buttons\\UI-StopButton")
    clear:SetPoint("RIGHT", -4, 0)
    clear:Hide()

    local function refreshChrome()
        local hasText = editBox:GetText() ~= ""

        hint:SetShown(not hasText)
        clear:SetShown(hasText)
    end

    editBox:SetScript("OnTextChanged", function(self, userInput)
        refreshChrome()

        if (onChange) then onChange(self:GetText(), userInput) end
    end)

    editBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    editBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

    editBox:SetScript("OnEditFocusGained", function() frame:SetBorderColor(UI:rgb("accentDim")) end)
    editBox:SetScript("OnEditFocusLost", function() frame:SetBorderColor(UI:rgb("border")) end)

    clear:SetScript("OnClick", function()
        editBox:SetText("")
        editBox:ClearFocus()
    end)

    -- clicking anywhere in the field, not only on the 12px of text, starts typing
    frame:EnableMouse(true)
    frame:SetScript("OnMouseDown", function() editBox:SetFocus() end)

    frame.editBox = editBox

    frame.SetValue = function(_, value)
        editBox:SetText(value or "")
        refreshChrome()
    end

    return frame
end

-- ── dropdown ──────────────────────────────────────────────────────────────────

-- The client's own dropdown carries three decades of chrome and cannot be restyled, so
-- this is a plain button that opens a list of plain buttons. `items` is a list of
-- { value, text } pairs, resolved every time it opens - the zone list grows while the
-- player plays.
function UI:dropdown(parent, width, height, label, getItems, getValue, onSelect)
    local frame = self:panel(parent, "raised", true)
    frame:SetSize(width, height or 26)

    local button = CreateFrame("Button", nil, frame)
    button:SetAllPoints()
    attachHover(button, "panelHover", 0.7, "BACKGROUND")

    local caption = self:text(frame, 11, "textFaint")
    caption:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 1, 4)
    caption:SetText(label)

    local value = self:text(frame, 12, "text")
    value:SetPoint("LEFT", 8, 0)
    value:SetPoint("RIGHT", -20, 0)
    value:SetJustifyH("LEFT")
    value:SetWordWrap(false)

    local arrow = frame:CreateTexture(nil, "OVERLAY")
    arrow:SetTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up")
    arrow:SetSize(14, 14)
    arrow:SetPoint("RIGHT", -4, 0)
    arrow:SetVertexColor(self:rgb("textFaint"))

    -- The menu is a child of UIParent, not of the dropdown: it has to be able to draw
    -- over the rows below it, and a child is clipped by its parent's strata.
    local menu = self:panel(UIParent, "window", true)
    menu:SetFrameStrata("FULLSCREEN_DIALOG")
    menu:Hide()
    menu:EnableMouse(true)

    local shadow = menu:CreateTexture(nil, "BACKGROUND", nil, -1)
    shadow:SetPoint("TOPLEFT", -4, 4)
    shadow:SetPoint("BOTTOMRIGHT", 4, -4)
    shadow:SetColorTexture(0, 0, 0, 0.5)

    local entries = {}

    local function closeMenu()
        menu:Hide()
        arrow:SetVertexColor(UI:rgb("textFaint"))
    end

    local function buildMenu()
        local items = getItems()
        local rowHeight = 22
        local widest = width

        for i = 1, #items do
            local entry = entries[i]

            if (not entry) then
                entry = CreateFrame("Button", nil, menu)
                entry:SetHeight(rowHeight)
                entry:SetPoint("LEFT", 1, 0)
                entry:SetPoint("RIGHT", -1, 0)
                attachHover(entry, "raised", 1, "BACKGROUND")

                -- a child of the entry, not of the menu: a shorter list hides its spare
                -- entries, and a marker parented to the menu would stay lit under nothing
                entry.check = entry:CreateTexture(nil, "OVERLAY")
                entry.check:SetSize(3, 12)
                entry.check:SetColorTexture(UI:rgb("accent"))
                entry.check:SetPoint("LEFT", 6, 0)

                entry.label = UI:text(entry, 12, "text")
                entry.label:SetPoint("LEFT", 14, 0)
                entry.label:SetPoint("RIGHT", -8, 0)
                entry.label:SetJustifyH("LEFT")
                entry.label:SetWordWrap(false)

                entries[i] = entry
            end

            entry:SetPoint("TOPLEFT", menu, "TOPLEFT", 1, -(4 + (i - 1) * rowHeight))
            entry.label:SetText(items[i].text)
            entry.value = items[i].value
            entry.check:SetShown(items[i].value == getValue())
            entry:Show()

            entry:SetScript("OnClick", function(self)
                PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
                closeMenu()
                onSelect(self.value)
            end)

            widest = math.max(widest, entry.label:GetStringWidth() + 30)
        end

        for i = #items + 1, #entries do
            entries[i]:Hide()
        end

        menu:SetWidth(math.min(widest, 320))
        menu:SetHeight(#items * rowHeight + 8)
    end

    button:SetScript("OnClick", function()
        if (menu:IsShown()) then
            closeMenu()
            return
        end

        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        buildMenu()

        menu:ClearAllPoints()
        menu:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 0, -2)
        menu:Show()

        arrow:SetVertexColor(UI:rgb("accent"))
    end)

    -- clicking anywhere else closes it, which is what every other menu in the client does
    menu:SetScript("OnShow", function(self)
        self.closer = self.closer or CreateFrame("Button", nil, UIParent)
        self.closer:SetAllPoints(UIParent)
        self.closer:SetFrameStrata("FULLSCREEN_DIALOG")
        self.closer:SetFrameLevel(math.max(self:GetFrameLevel() - 1, 1))
        self.closer:SetScript("OnClick", function() closeMenu() end)
        self.closer:Show()
    end)

    menu:SetScript("OnHide", function(self)
        if (self.closer) then self.closer:Hide() end
    end)

    frame.menu = menu

    frame.SetText = function(_, text) value:SetText(text) end
    frame.Close = closeMenu

    return frame
end

-- ── segmented control ─────────────────────────────────────────────────────────

-- A row of joined buttons where exactly one is lit. The date range is six mutually
-- exclusive choices that the player changes constantly, so it is worth the width: a
-- dropdown would cost two clicks and hide the other five options.
function UI:segmented(parent, height, options, getValue, onSelect)
    local frame = self:panel(parent, "window", true)
    frame:SetHeight(height or 26)

    local buttons = {}
    local totalWidth = 2

    for i = 1, #options do
        local option = options[i]
        local button = CreateFrame("Button", nil, frame)

        button:SetHeight((height or 26) - 2)
        attachHover(button, "raised", 1, "BACKGROUND")

        local label = self:text(button, 12, "textDim")
        label:SetPoint("CENTER")
        label:SetText(option.text)

        local lit = button:CreateTexture(nil, "BORDER")
        lit:SetAllPoints()
        lit:SetColorTexture(0.24, 0.19, 0.06, 1)
        lit:Hide()

        local underline = button:CreateTexture(nil, "OVERLAY")
        underline:SetPoint("BOTTOMLEFT", 0, 0)
        underline:SetPoint("BOTTOMRIGHT", 0, 0)
        underline:SetHeight(2)
        underline:SetColorTexture(self:rgb("accent"))
        underline:Hide()

        local width = math.max(label:GetStringWidth() + 22, 44)

        button:SetWidth(width)
        button:SetPoint("TOPLEFT", frame, "TOPLEFT", totalWidth - 1, -1)

        button.value = option.value
        button.label = label
        button.lit = lit
        button.underline = underline

        button:SetScript("OnClick", function(self)
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
            onSelect(self.value)
        end)

        if (i > 1) then
            local divider = frame:CreateTexture(nil, "OVERLAY")
            divider:SetPoint("TOPLEFT", button, "TOPLEFT", -1, -4)
            divider:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", -1, 4)
            divider:SetWidth(1)
            divider:SetColorTexture(self:rgb("border"))
        end

        totalWidth = totalWidth + width
        buttons[i] = button
    end

    frame:SetWidth(totalWidth)

    frame.Refresh = function()
        local current = getValue()

        for i = 1, #buttons do
            local button = buttons[i]
            local active = button.value == current

            button.lit:SetShown(active)
            button.underline:SetShown(active)
            button.label:SetTextColor(UI:rgbIf(active, "accent", "textDim"))
        end
    end

    frame:Refresh()

    return frame
end

-- ── toggle ────────────────────────────────────────────────────────────────────

-- A checkbox drawn as a small square that fills with the accent colour, plus its label,
-- with the whole thing clickable rather than only the 14px box.
function UI:toggle(parent, text, getValue, onToggle)
    local button = CreateFrame("Button", nil, parent)
    local box = self:panel(button, "window", true)

    box:SetSize(15, 15)
    box:SetPoint("LEFT", 0, 0)

    local fill = box:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("TOPLEFT", 3, -3)
    fill:SetPoint("BOTTOMRIGHT", -3, 3)
    fill:SetColorTexture(self:rgb("accent"))
    fill:Hide()

    local label = self:text(button, 12, "textDim")
    label:SetPoint("LEFT", 21, 0)
    label:SetText(text)

    button:SetHeight(20)
    button:SetWidth(label:GetStringWidth() + 24)

    button:HookScript("OnEnter", function()
        box:SetBorderColor(UI:rgb("borderLight"))
        label:SetTextColor(UI:rgb("text"))
    end)

    button:HookScript("OnLeave", function()
        box:SetBorderColor(UI:rgb("border"))
        label:SetTextColor(UI:rgbIf(getValue(), "accent", "textDim"))
    end)

    button:SetScript("OnClick", function()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        onToggle(not getValue())
    end)

    button.Refresh = function()
        local on = getValue()

        fill:SetShown(on)
        label:SetTextColor(UI:rgbIf(on, "accent", "textDim"))
    end

    button:Refresh()

    return button
end

-- ── scrollbar ─────────────────────────────────────────────────────────────────

-- A thin track and a draggable thumb, sized to how much of the list is on screen. It
-- hides itself when everything fits, which the client's own scroll frames do not.
function UI:scrollbar(parent, onScroll)
    local bar = self:panel(parent, "window", false)
    bar:SetWidth(8)

    local thumb = CreateFrame("Button", nil, bar)
    thumb:SetWidth(8)
    thumb:SetPoint("TOP")

    local thumbTex = thumb:CreateTexture(nil, "ARTWORK")
    thumbTex:SetAllPoints()
    thumbTex:SetColorTexture(self:rgb("borderLight"))

    thumb:HookScript("OnEnter", function() thumbTex:SetColorTexture(UI:rgb("accentDim")) end)
    thumb:HookScript("OnLeave", function() thumbTex:SetColorTexture(UI:rgb("borderLight")) end)

    bar.offset = 0
    bar.range = 0

    local dragging = false
    local dragOffset = 0

    local function applyFromThumb()
        local trackHeight = bar:GetHeight() - thumb:GetHeight()

        if (trackHeight <= 0) then return end

        local _, _, _, _, y = thumb:GetPoint()
        local ratio = math.min(math.max(-y / trackHeight, 0), 1)

        bar.offset = ratio * bar.range

        if (onScroll) then onScroll(bar.offset) end
    end

    thumb:SetScript("OnMouseDown", function(self)
        dragging = true

        local _, cursorY = GetCursorPosition()
        local scale = self:GetEffectiveScale()
        local _, _, _, _, y = self:GetPoint()

        dragOffset = cursorY / scale - y
    end)

    thumb:SetScript("OnMouseUp", function() dragging = false end)

    thumb:SetScript("OnUpdate", function(self)
        if (not dragging) then return end

        local _, cursorY = GetCursorPosition()
        local scale = self:GetEffectiveScale()
        local trackHeight = bar:GetHeight() - self:GetHeight()
        local y = math.min(math.max(cursorY / scale - dragOffset, -trackHeight), 0)

        self:SetPoint("TOP", 0, y)
        applyFromThumb()
    end)

    -- `visible` and `total` are in pixels: how tall the viewport is and how tall the
    -- content is. The thumb is the ratio of the two, never smaller than a grabbable 24px.
    bar.Update = function(_, visible, total, offset)
        bar.range = math.max(total - visible, 0)
        bar.offset = math.min(math.max(offset or bar.offset, 0), bar.range)

        if (bar.range <= 0) then
            bar:Hide()
            return bar.offset
        end

        bar:Show()

        local height = bar:GetHeight()
        local thumbHeight = math.max(height * (visible / total), 24)
        local ratio = bar.range > 0 and (bar.offset / bar.range) or 0

        thumb:SetHeight(thumbHeight)
        thumb:SetPoint("TOP", 0, -(height - thumbHeight) * ratio)

        return bar.offset
    end

    return bar
end

-- ── section heading ───────────────────────────────────────────────────────────

-- A small caps label with a rule running off to the right of it, for the blocks inside
-- the list that are not items.
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
