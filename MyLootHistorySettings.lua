--[[
My Loot History addon
Copyright (C) 2026 RustyDaemon (https://github.com/RustyDaemon)

See License file for details.
--]]

-- The settings window: the AceConfig options table from MyLootHistoryConfig.lua, drawn with the
-- same kit as the report. The table stays the one place a setting is defined; this file only reads
-- it, so a new option there shows up here without any change.

local MLH = LibStub("AceAddon-3.0"):GetAddon("MyLootHistory")
local L = LibStub("AceLocale-3.0"):GetLocale("MyLootHistory")
local UI = MLH.UI

local WIDTH = 780
local HEIGHT = 580
local PAD = 14
local TITLE_HEIGHT = 44
local SIDEBAR_WIDTH = 176
local NAV_HEIGHT = 30
local SCROLLBAR_WIDTH = 8
local CONTENT_WIDTH = WIDTH - SIDEBAR_WIDTH - PAD * 4 - SCROLLBAR_WIDTH
local CONTROL_WIDTH = 320
local GAP = 10
local WHEEL_STEP = 48

local FONT_SIZES = { small = 11, medium = 13, large = 15 }

local window = nil
local ticker = nil

-- AceConfig hands an info table to every callback; the options here ignore it, but keep the shape.
local function infoFor(key, option)
    return { key, option = option, type = option.type }
end

local function resolve(value, info)
    if (type(value) == "function") then return value(info) end

    return value
end

local function sortedArgs(args)
    local list = {}

    for key, option in pairs(args or {}) do
        list[#list+1] = { key = key, option = option }
    end

    table.sort(list, function(l, r)
        local lo, ro = l.option.order or 100, r.option.order or 100

        if (lo == ro) then return l.key < r.key end

        return lo < ro
    end)

    return list
end

-- The top level's loose options are the General page; every group is a page of its own.
local function collectPages(options)
    local general = { name = L["C_General"], entries = {} }
    local pages = { general }

    for _, arg in ipairs(sortedArgs(options.args)) do
        if (arg.option.type == "group") then
            pages[#pages+1] = { name = arg.option.name, entries = sortedArgs(arg.option.args) }
        else
            general.entries[#general.entries+1] = arg
        end
    end

    -- A heading with nothing under it introduced the groups, which the sidebar now lists.
    while (#general.entries > 0 and general.entries[#general.entries].option.type == "header") do
        general.entries[#general.entries] = nil
    end

    return pages
end

local function selectItems(option, info)
    local values = resolve(option.values, info) or {}
    local items = {}

    if (option.sorting) then
        for _, value in ipairs(option.sorting) do
            if (values[value] ~= nil) then items[#items+1] = { value = value, text = values[value] } end
        end
    else
        for value, text in pairs(values) do items[#items+1] = { value = value, text = text } end

        table.sort(items, function(l, r) return tostring(l.text) < tostring(r.text) end)
    end

    return items
end

-- Each builder returns a row: a frame holding one control, with Refresh() and its height.
local builders = {}

function builders.header(parent, option)
    local row = UI:sectionHeading(parent, option.name)

    row.topGap = 8
    row.Refresh = function() end

    return row
end

function builders.description(parent, option, info)
    local row = CreateFrame("Frame", nil, parent)
    local text = UI:text(row, FONT_SIZES[option.fontSize] or 12, "textDim")

    text:SetPoint("TOPLEFT", 2, 0)
    text:SetWidth(CONTENT_WIDTH - 4)
    text:SetJustifyH("LEFT")
    text:SetSpacing(3)

    row.Refresh = function()
        text:SetText(resolve(option.name, info) or "")
        row:SetHeight(text:GetStringHeight() + 4)
    end

    return row
end

function builders.toggle(parent, option, info, changed)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(22)

    local toggle = UI:toggle(row, option.name,
        function() return resolve(option.get, info) and true or false end,
        function(value)
            option.set(info, value)
            changed()
        end)
    toggle:SetPoint("LEFT", 0, 0)

    UI:tooltip(toggle, option.name, option.desc, "ANCHOR_RIGHT")

    row.Refresh = function() toggle:Refresh() end

    return row
end

function builders.select(parent, option, info, changed)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(44)

    local dropdown = UI:dropdown(row, CONTROL_WIDTH, 26, option.name,
        function() return selectItems(option, info) end,
        function() return resolve(option.get, info) end,
        function(value)
            option.set(info, value)
            changed()
        end)
    dropdown:SetPoint("BOTTOMLEFT", 0, 0)

    UI:tooltip(dropdown, option.name, option.desc, "ANCHOR_RIGHT")

    row.Refresh = function()
        local values = resolve(option.values, info) or {}

        dropdown:SetText(values[resolve(option.get, info)] or "")
    end

    return row
end

function builders.range(parent, option, info, changed)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(44)

    local slider = UI:slider(row, CONTROL_WIDTH, option.name,
        option.softMin or option.min, option.softMax or option.max, option.bigStep or option.step or 1,
        function() return resolve(option.get, info) end,
        function(value)
            option.set(info, value)
            changed()
        end,
        option.min, option.max)
    slider:SetPoint("BOTTOMLEFT", 0, 0)

    UI:tooltip(slider.track, option.name, option.desc, "ANCHOR_RIGHT")

    row.Refresh = function() slider:Refresh() end

    return row
end

function builders.execute(parent, option, info, changed)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(28)

    local button = UI:button(row, option.name, 120, 26, function()
        option.func(info)
        changed()
    end)
    button:SetWidth(math.max(button.label:GetStringWidth() + 32, 120))
    button:SetPoint("LEFT", 0, 0)

    UI:tooltip(button, option.name, option.desc, "ANCHOR_RIGHT")

    row.Refresh = function() end

    return row
end

function builders.input(parent, option, info, changed)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(44)

    -- readOnly is not an AceConfig key: it marks a field meant only for copying, like the website.
    local box = UI:inputBox(row, CONTROL_WIDTH, 26, option.name,
        function() return resolve(option.get, info) end,
        function(text)
            option.set(info, text)
            changed()
        end,
        option.readOnly)
    box:SetPoint("BOTTOMLEFT", 0, 0)

    row.Refresh = function() box:Refresh() end

    return row
end

local LIST_LINE_HEIGHT = 30

-- list is not an AceConfig type: lines that come and go, each with a button acting on its value.
-- values() returns { text, value }; func(info, value) is what the button does.
function builders.list(parent, option, info, changed)
    local row = CreateFrame("Frame", nil, parent)
    local lines = {}

    local empty = UI:text(row, 12, "textFaint")
    empty:SetPoint("TOPLEFT", 2, -6)

    local function line(i)
        if (lines[i]) then return lines[i] end

        local frame = CreateFrame("Frame", nil, row)
        frame:SetHeight(LIST_LINE_HEIGHT)
        frame:SetPoint("LEFT", 0, 0)
        frame:SetPoint("RIGHT", 0, 0)
        frame:SetPoint("TOP", 0, -(i - 1) * LIST_LINE_HEIGHT)

        frame.button = UI:button(frame, option.actionText, 90, 24, function()
            option.func(info, frame.value)
            changed()
        end)
        frame.button:SetPoint("RIGHT", -2, 0)

        frame.label = UI:text(frame, 12, "text")
        frame.label:SetPoint("LEFT", 2, 0)
        frame.label:SetPoint("RIGHT", frame.button, "LEFT", -GAP, 0)
        frame.label:SetJustifyH("LEFT")
        frame.label:SetWordWrap(false)

        lines[i] = frame

        return frame
    end

    row.Refresh = function()
        local values = resolve(option.values, info) or {}

        for i = 1, #values do
            local frame = line(i)

            frame.value = values[i].value
            frame.label:SetText(values[i].text)
            frame:Show()
        end

        for i = #values + 1, #lines do
            lines[i]:Hide()
        end

        empty:SetText(resolve(option.emptyText, info) or "")
        empty:SetShown(#values == 0)

        row:SetHeight(math.max(#values, 1) * LIST_LINE_HEIGHT)
    end

    return row
end

-- Dims a row and stops it taking clicks while its option is disabled.
local function addDisabledCover(row, option, info)
    if (option.disabled == nil) then return end

    local cover = CreateFrame("Frame", nil, row)
    cover:SetAllPoints()
    cover:SetFrameLevel(row:GetFrameLevel() + 20)
    cover:EnableMouse(true)
    cover:Hide()

    local refresh = row.Refresh

    row.Refresh = function()
        local disabled = resolve(option.disabled, info) and true or false

        cover:SetShown(disabled)
        row:SetAlpha(disabled and 0.4 or 1)
        refresh()
    end
end

local function buildPage(page, changed)
    local frame = CreateFrame("Frame", nil, window.scroll)
    frame:SetWidth(CONTENT_WIDTH)
    frame:Hide()

    local title = UI:text(frame, 15, "text")
    title:SetPoint("TOPLEFT", 2, -2)
    title:SetText(page.name)

    local rows = {}

    for _, arg in ipairs(page.entries) do
        local option = arg.option
        local build = builders[option.type]

        if (build) then
            local info = infoFor(arg.key, option)
            local row = build(frame, option, info, changed)

            row:SetWidth(CONTENT_WIDTH)
            addDisabledCover(row, option, info)

            row.option = option
            row.info = info
            rows[#rows+1] = row
        end
    end

    frame.rows = rows

    -- Hidden options drop out of the stack; descriptions change height as their text changes.
    frame.Layout = function()
        local y = 34

        for _, row in ipairs(rows) do
            local hidden = resolve(row.option.hidden, row.info)

            row:SetShown(not hidden)

            if (not hidden) then
                row.Refresh()

                y = y + (row.topGap or 0)

                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -y)

                y = y + row:GetHeight() + GAP
            end
        end

        frame:SetHeight(y + PAD)
    end

    return frame
end

local function updateScroll(offset)
    local page = window.pages[window.current]
    local visible = window.scroll:GetHeight()

    window.offset = window.scrollbar:Update(visible, page.frame:GetHeight(), offset)
    window.scroll:SetVerticalScroll(window.offset)
end

local function refreshPage()
    if (not window or not window:IsShown()) then return end

    window.pages[window.current].frame.Layout()
    updateScroll(window.offset)
end

local function selectPage(index)
    local previous = window.pages[window.current]

    if (previous and previous.frame) then previous.frame:Hide() end

    window.current = index
    window.offset = 0

    local page = window.pages[index]

    page.frame = page.frame or buildPage(page, refreshPage)
    page.frame:Show()
    window.scroll:SetScrollChild(page.frame)

    for i, nav in ipairs(window.nav) do nav:SetActive(i == index) end

    MLH.db.char.ui = MLH.db.char.ui or {}
    MLH.db.char.ui.settingsPage = index

    refreshPage()
end

local function createNavButton(parent, text, onClick)
    local button = CreateFrame("Button", nil, parent)
    button:SetHeight(NAV_HEIGHT)

    UI:attachHover(button, "raised", 1, "BACKGROUND")

    local lit = button:CreateTexture(nil, "BORDER")
    lit:SetAllPoints()
    lit:SetColorTexture(0.24, 0.19, 0.06, 1)
    lit:Hide()

    local stripe = button:CreateTexture(nil, "OVERLAY")
    stripe:SetPoint("TOPLEFT")
    stripe:SetPoint("BOTTOMLEFT")
    stripe:SetWidth(2)
    stripe:SetColorTexture(UI:rgb("accent"))
    stripe:Hide()

    local label = UI:text(button, 12, "textDim")
    label:SetPoint("LEFT", 14, 0)
    label:SetPoint("RIGHT", -8, 0)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    label:SetText(text)

    button:SetScript("OnClick", function()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        onClick()
    end)

    button.SetActive = function(_, active)
        lit:SetShown(active)
        stripe:SetShown(active)
        label:SetTextColor(UI:rgbIf(active, "accent", "textDim"))
    end

    return button
end

local function savePosition()
    local point, _, relativePoint, x, y = window:GetPoint()

    MLH.db.char.ui = MLH.db.char.ui or {}
    MLH.db.char.ui.settings = { point = point, relativePoint = relativePoint, x = x, y = y }
end

local function buildWindow()
    local frame = CreateFrame("Frame", "MLHSettingsFrame", UIParent)

    frame:SetFrameStrata("HIGH")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetSize(WIDTH, HEIGHT)
    frame:Hide()

    UI:addShadow(frame, 6, 0.45)

    local bg = frame:CreateTexture(nil, "BACKGROUND", nil, -7)
    bg:SetAllPoints()
    bg:SetColorTexture(UI:rgb("window", 0.97))

    UI:addBorder(frame, UI:rgb("borderLight"))

    local titleBar = CreateFrame("Frame", nil, frame)
    titleBar:SetPoint("TOPLEFT", 1, -1)
    titleBar:SetPoint("TOPRIGHT", -1, -1)
    titleBar:SetHeight(TITLE_HEIGHT)
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")

    local titleFill = UI:gradient(titleBar, "BACKGROUND", "VERTICAL",
        0.055, 0.059, 0.070, 1, 0.114, 0.106, 0.075, 1)
    titleFill:SetAllPoints()

    local titleLine = titleBar:CreateTexture(nil, "ARTWORK")
    titleLine:SetPoint("BOTTOMLEFT")
    titleLine:SetPoint("BOTTOMRIGHT")
    titleLine:SetHeight(1)
    titleLine:SetColorTexture(UI:rgb("accentDim", 0.6))

    titleBar:SetScript("OnDragStart", function() frame:StartMoving() end)
    titleBar:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        savePosition()
    end)

    local logo = titleBar:CreateTexture(nil, "ARTWORK")
    logo:SetSize(24, 24)
    logo:SetPoint("LEFT", PAD, 0)
    logo:SetTexture("Interface\\Icons\\inv_misc_map09")
    logo:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local logoBorder = titleBar:CreateTexture(nil, "BACKGROUND")
    logoBorder:SetPoint("TOPLEFT", logo, "TOPLEFT", -1, 1)
    logoBorder:SetPoint("BOTTOMRIGHT", logo, "BOTTOMRIGHT", 1, -1)
    logoBorder:SetColorTexture(UI:rgb("accentDim"))

    local title = UI:text(titleBar, 15, "text")
    title:SetPoint("LEFT", logo, "RIGHT", 10, 1)
    title:SetText(L["MM_IconTitle"])

    local subtitle = UI:text(titleBar, 11, "textFaint")
    subtitle:SetPoint("LEFT", title, "RIGHT", 10, 0)
    subtitle:SetText(L["R_Settings"])

    local close = UI:iconButton(titleBar, 28, "Interface\\Buttons\\UI-StopButton",
        function() frame:Hide() end)
    close:SetPoint("RIGHT", -6, 0)
    UI:tooltip(close, L["R_Close"])

    local sidebar = UI:panel(frame, "panel", true)
    sidebar:SetPoint("TOPLEFT", titleBar, "BOTTOMLEFT", PAD - 1, -PAD)
    sidebar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", PAD, PAD)
    sidebar:SetWidth(SIDEBAR_WIDTH)

    local content = CreateFrame("Frame", nil, frame)
    content:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", PAD, 0)
    content:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PAD, PAD)

    local scroll = CreateFrame("ScrollFrame", nil, content)
    scroll:SetPoint("TOPLEFT", 0, 0)
    scroll:SetPoint("BOTTOMRIGHT", -(SCROLLBAR_WIDTH + PAD), 0)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(_, delta)
        updateScroll((window.offset or 0) - delta * WHEEL_STEP)
    end)

    local scrollbar = UI:scrollbar(content, function(offset)
        window.offset = offset
        scroll:SetVerticalScroll(offset)
    end)
    scrollbar:SetPoint("TOPRIGHT", 0, 0)
    scrollbar:SetPoint("BOTTOMRIGHT", 0, 0)

    frame.scroll = scroll
    frame.scrollbar = scrollbar
    frame.pages = collectPages(MLH.settingsOptions)
    frame.nav = {}

    for i, page in ipairs(frame.pages) do
        local nav = createNavButton(sidebar, page.name, function() selectPage(i) end)

        nav:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 1, -(6 + (i - 1) * NAV_HEIGHT))
        nav:SetPoint("RIGHT", sidebar, "RIGHT", -1, 0)

        frame.nav[i] = nav
    end

    frame:SetScript("OnShow", function()
        ticker = ticker or C_Timer.NewTicker(1, refreshPage)
    end)

    frame:SetScript("OnHide", function()
        if (ticker) then ticker:Cancel() end

        ticker = nil
    end)

    if (not tContains(UISpecialFrames, "MLHSettingsFrame")) then
        tinsert(UISpecialFrames, "MLHSettingsFrame")
    end

    return frame
end

function MLH:openSettings(pageIndex)
    if (not window) then window = buildWindow() end

    local ui = self.db.char.ui or {}
    local saved = ui.settings or {}

    window:ClearAllPoints()

    if (saved.point) then
        window:SetPoint(saved.point, UIParent, saved.relativePoint or saved.point, saved.x or 0, saved.y or 0)
    else
        window:SetPoint("CENTER")
    end

    window:Show()
    window:Raise()

    local page = pageIndex or ui.settingsPage or 1

    selectPage(window.pages[page] and page or 1)

    -- Lay out again next frame, once the scroll frame has its size.
    C_Timer.After(0, refreshPage)
end

-- For changes made outside a control's own set, such as a confirmation being answered.
function MLH:refreshSettings()
    refreshPage()
end

function MLH:toggleSettings()
    if (window and window:IsShown()) then
        window:Hide()
    else
        self:openSettings()
    end
end
