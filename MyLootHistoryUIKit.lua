--[[
My Loot History addon
Copyright (C) 2026 RustyDaemon (https://github.com/RustyDaemon)

See License file for details.
--]]

local MLH = LibStub("AceAddon-3.0"):GetAddon("MyLootHistory")

local UI = {}
MLH.UI = UI

local FONT = GameFontNormal:GetFont()
local FONT_NUMBER = (NumberFontNormal and NumberFontNormal:GetFont()) or FONT

UI.font = FONT
UI.fontNumber = FONT_NUMBER

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

    frame:EnableMouse(true)
    frame:SetScript("OnMouseDown", function() editBox:SetFocus() end)

    frame.editBox = editBox

    frame.SetValue = function(_, value)
        editBox:SetText(value or "")
        refreshChrome()
    end

    return frame
end

-- A floating list of choices, closed by picking one or clicking anywhere else. Position it, then
-- Open it with { text, value } items; `selected` is the value to mark, if any.
function UI:menu()
    -- Parent to UIParent so the menu can draw above the rows.
    local menu = self:panel(UIParent, "window", true)
    menu:SetFrameStrata("FULLSCREEN_DIALOG")
    menu:SetClampedToScreen(true)
    menu:Hide()
    menu:EnableMouse(true)

    self:addShadow(menu, 4, 0.5, -1)

    local entries = {}

    menu.Open = function(_, items, onSelect, selected, minWidth)
        local rowHeight = 22
        local widest = minWidth or 0

        for i = 1, #items do
            local entry = entries[i]

            if (not entry) then
                entry = CreateFrame("Button", nil, menu)
                entry:SetHeight(rowHeight)
                entry:SetPoint("LEFT", 1, 0)
                entry:SetPoint("RIGHT", -1, 0)
                attachHover(entry, "raised", 1, "BACKGROUND")

                -- Parent markers to entries so hiding spare entries also hides their markers.
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
            entry.check:SetShown(selected ~= nil and items[i].value == selected)
            entry:Show()

            entry:SetScript("OnClick", function(self)
                PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
                menu:Hide()
                onSelect(self.value)
            end)

            widest = math.max(widest, entry.label:GetStringWidth() + 30)
        end

        for i = #items + 1, #entries do
            entries[i]:Hide()
        end

        menu:SetWidth(math.min(widest, 320))
        menu:SetHeight(#items * rowHeight + 8)
        menu:Show()
    end

    menu:SetScript("OnShow", function(self)
        self.closer = self.closer or CreateFrame("Button", nil, UIParent)
        self.closer:SetAllPoints(UIParent)
        self.closer:SetFrameStrata("FULLSCREEN_DIALOG")
        self.closer:SetFrameLevel(math.max(self:GetFrameLevel() - 1, 1))
        self.closer:SetScript("OnClick", function() menu:Hide() end)
        self.closer:Show()
    end)

    menu:SetScript("OnHide", function(self)
        if (self.closer) then self.closer:Hide() end
        if (self.onClose) then self.onClose() end
    end)

    return menu
end

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

    local menu = self:menu()

    local function closeMenu() menu:Hide() end

    menu.onClose = function() arrow:SetVertexColor(UI:rgb("textFaint")) end

    button:SetScript("OnClick", function()
        if (menu:IsShown()) then
            closeMenu()
            return
        end

        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)

        menu:ClearAllPoints()
        menu:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 0, -2)
        menu:Open(getItems(), onSelect, getValue(), width)

        arrow:SetVertexColor(UI:rgb("accent"))
    end)

    frame.menu = menu

    frame.SetText = function(_, text) value:SetText(text) end
    frame.Close = closeMenu

    return frame
end

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

local CONFIRM_WIDTH = 400
local CONFIRM_PAD = 20

local confirmDialog = nil

local function buildConfirm()
    -- A full-screen shade that swallows clicks, so the question is answered before anything else.
    local shade = CreateFrame("Button", "MLHConfirmDialog", UIParent)
    shade:SetAllPoints(UIParent)
    shade:SetFrameStrata("FULLSCREEN_DIALOG")
    shade:EnableMouse(true)
    shade:Hide()

    local dim = shade:CreateTexture(nil, "BACKGROUND")
    dim:SetAllPoints()
    dim:SetColorTexture(0, 0, 0, 0.45)

    local box = CreateFrame("Frame", nil, shade)
    box:SetWidth(CONFIRM_WIDTH)
    box:SetPoint("CENTER", 0, 80)
    box:EnableMouse(true)

    UI:addShadow(box, 6, 0.5)

    local bg = box:CreateTexture(nil, "BACKGROUND", nil, -7)
    bg:SetAllPoints()
    bg:SetColorTexture(UI:rgb("window", 0.98))

    addBorder(box, UI:rgb("borderLight"))

    local stripe = box:CreateTexture(nil, "ARTWORK")
    stripe:SetPoint("TOPLEFT", 1, -1)
    stripe:SetPoint("TOPRIGHT", -1, -1)
    stripe:SetHeight(2)

    local title = UI:text(box, 14, "text")
    title:SetPoint("TOPLEFT", CONFIRM_PAD, -CONFIRM_PAD)
    title:SetPoint("RIGHT", -CONFIRM_PAD, 0)
    title:SetJustifyH("LEFT")

    local body = UI:text(box, 12, "textDim")
    body:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
    body:SetWidth(CONFIRM_WIDTH - CONFIRM_PAD * 2)
    body:SetJustifyH("LEFT")
    body:SetSpacing(3)

    local function answer(accepted)
        local options = shade.options

        shade.answered = true
        shade:Hide()

        if (accepted and options.onAccept) then options.onAccept() end
        if (not accepted and options.onCancel) then options.onCancel() end
    end

    local accept = UI:button(box, "", 120, 26, function() answer(true) end)
    accept:SetPoint("BOTTOMRIGHT", -CONFIRM_PAD, CONFIRM_PAD - 4)

    local cancel = UI:button(box, "", 100, 26, function() answer(false) end)
    cancel:SetPoint("RIGHT", accept, "LEFT", -8, 0)

    shade:SetScript("OnClick", function() end)

    -- Escape, or anything else that hides it unanswered, counts as No.
    shade:SetScript("OnHide", function(self)
        if (not self.answered) then answer(false) end
    end)

    if (not tContains(UISpecialFrames, "MLHConfirmDialog")) then
        tinsert(UISpecialFrames, "MLHConfirmDialog")
    end

    shade.box = box
    shade.stripe = stripe
    shade.title = title
    shade.body = body
    shade.accept = accept
    shade.cancel = cancel

    return shade
end

-- Asks before something that cannot be undone. options: title, text, acceptText, cancelText,
-- danger (paints the accept button red), onAccept, onCancel. Escape is the same as cancel.
function UI:confirm(options)
    confirmDialog = confirmDialog or buildConfirm()

    local dialog = confirmDialog

    -- A question still open is dismissed, not silently replaced.
    if (dialog:IsShown()) then dialog:Hide() end

    dialog.options = options
    dialog.answered = false

    dialog.title:SetText(options.title or "")
    dialog.body:SetText(options.text or "")

    dialog.accept:SetLabel(options.acceptText or YES)
    dialog.accept:SetWidth(math.max(dialog.accept.label:GetStringWidth() + 32, 100))
    dialog.cancel:SetLabel(options.cancelText or NO)
    dialog.cancel:SetWidth(math.max(dialog.cancel.label:GetStringWidth() + 32, 90))

    local tone = options.danger and "bad" or "accent"

    dialog.stripe:SetColorTexture(self:rgb(tone))
    dialog.accept:SetAccent(not options.danger)

    if (options.danger) then
        dialog.accept:SetBorderColor(self:rgb("bad"))
        dialog.accept.label:SetTextColor(self:rgb("bad"))
    end

    dialog.box:SetHeight(CONFIRM_PAD + dialog.title:GetStringHeight() + 10
        + dialog.body:GetStringHeight() + 24 + 26 + CONFIRM_PAD - 4)

    PlaySound(SOUNDKIT.IG_MAINMENU_OPEN)
    dialog:Show()

    return dialog
end

local function formatStep(value, step)
    if (step >= 1) then return tostring(math.floor(value + 0.5)) end

    return string.format("%.2f", value)
end

-- A single-line text field with a caption above it, like the dropdown's. A read-only field keeps
-- its text but can still be selected and copied.
function UI:inputBox(parent, width, height, label, getValue, onCommit, readOnly)
    local frame = self:panel(parent, "window", true)
    frame:SetSize(width, height or 26)

    local caption = self:text(frame, 11, "textFaint")
    caption:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 1, 4)
    caption:SetText(label or "")

    local editBox = CreateFrame("EditBox", nil, frame)
    editBox:SetPoint("LEFT", 8, 0)
    editBox:SetPoint("RIGHT", -8, 0)
    editBox:SetHeight(height or 26)
    editBox:SetAutoFocus(false)
    editBox:SetFont(FONT, 12, "")
    editBox:SetTextColor(self:rgb("text"))

    local focused = false

    local function show()
        editBox:SetText(tostring(getValue() or ""))
        editBox:SetCursorPosition(0)
    end

    editBox:SetScript("OnEditFocusGained", function()
        focused = true
        frame:SetBorderColor(UI:rgb("accentDim"))

        if (readOnly) then editBox:HighlightText() end
    end)

    editBox:SetScript("OnEditFocusLost", function()
        focused = false
        frame:SetBorderColor(UI:rgb("border"))
        editBox:HighlightText(0, 0)
        show()
    end)

    editBox:SetScript("OnTextChanged", function(_, userInput)
        if (readOnly and userInput) then show() end
    end)

    editBox:SetScript("OnEnterPressed", function()
        if (not readOnly and onCommit) then onCommit(editBox:GetText()) end

        editBox:ClearFocus()
    end)

    editBox:SetScript("OnEscapePressed", function() editBox:ClearFocus() end)

    frame:EnableMouse(true)
    frame:SetScript("OnMouseDown", function() editBox:SetFocus() end)

    frame.editBox = editBox

    frame.Refresh = function()
        if (not focused) then show() end
    end

    frame:Refresh()

    return frame
end

-- A horizontal slider over min..max in steps of `step`, with a box to type an exact value.
-- Typed values may go as far as hardMin..hardMax, past the slider's own range.
function UI:slider(parent, width, label, min, max, step, getValue, onChange, hardMin, hardMax)
    local BOX_WIDTH = 64
    local trackWidth = width - BOX_WIDTH - 14

    hardMin, hardMax = hardMin or min, hardMax or max

    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(width, 26)

    local caption = self:text(frame, 11, "textFaint")
    caption:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 1, 4)
    caption:SetText(label or "")

    local track = CreateFrame("Button", nil, frame)
    track:SetSize(trackWidth, 20)
    track:SetPoint("LEFT", 0, 0)

    local rail = self:panel(track, "window", true)
    rail:SetPoint("LEFT", 0, 0)
    rail:SetPoint("RIGHT", 0, 0)
    rail:SetHeight(6)

    local fill = rail:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("TOPLEFT", 1, -1)
    fill:SetPoint("BOTTOMLEFT", 1, 1)
    fill:SetColorTexture(self:rgb("accentDim"))

    local thumb = self:panel(track, "raised", true)
    thumb:SetSize(10, 16)

    local box = self:inputBox(frame, BOX_WIDTH, 22, nil,
        function() return formatStep(getValue() or min, step) end,
        function(text)
            local value = tonumber(text)

            if (value) then
                value = math.min(math.max(value, hardMin), hardMax)
                onChange(value)
            end

            frame:Refresh()
        end)
    box:SetPoint("RIGHT", 0, 0)
    box.editBox:SetJustifyH("RIGHT")

    local function snap(value)
        value = min + math.floor((value - min) / step + 0.5) * step

        return math.min(math.max(value, min), max)
    end

    local function place(value)
        local ratio = max > min and (math.min(math.max(value, min), max) - min) / (max - min) or 0
        local x = ratio * (trackWidth - 10)

        thumb:ClearAllPoints()
        thumb:SetPoint("LEFT", track, "LEFT", x, 0)
        fill:SetWidth(math.max(x + 4, 1))
    end

    local dragging = false

    local function setFromCursor()
        local cursorX = GetCursorPosition()
        local left = track:GetLeft()

        if (not left) then return end

        local ratio = (cursorX / track:GetEffectiveScale() - left - 5) / (trackWidth - 10)
        local value = snap(min + math.min(math.max(ratio, 0), 1) * (max - min))

        if (value ~= getValue()) then onChange(value) end

        frame:Refresh()
    end

    track:SetScript("OnMouseDown", function()
        dragging = true
        thumb:SetBorderColor(UI:rgb("accent"))
        setFromCursor()
    end)

    track:SetScript("OnMouseUp", function()
        dragging = false
        thumb:SetBorderColor(UI:rgb("border"))
    end)

    track:SetScript("OnUpdate", function()
        if (dragging) then setFromCursor() end
    end)

    track:HookScript("OnEnter", function()
        if (not dragging) then thumb:SetBorderColor(UI:rgb("borderLight")) end
    end)

    track:HookScript("OnLeave", function()
        if (not dragging) then thumb:SetBorderColor(UI:rgb("border")) end
    end)

    frame.track = track
    frame.box = box

    frame.Refresh = function()
        place(getValue() or min)
        box:Refresh()
    end

    frame:Refresh()

    return frame
end
