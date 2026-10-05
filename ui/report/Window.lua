--[[
My Loot History addon
Copyright (C) 2026 RustyDaemon (https://github.com/RustyDaemon)

See License file for details.
--]]

-- The report window itself: title bar, filters and the frame the other ui/report/ files fill.

local MLH = LibStub("AceAddon-3.0"):GetAddon("MyLootHistory")
local L = LibStub("AceLocale-3.0"):GetLocale("MyLootHistory")
local UI = MLH.UI
local View = MLH.reportView

local PAD = View.PAD
local HEADER_HEIGHT = View.HEADER_HEIGHT
local ROW_HEIGHT = View.ROW_HEIGHT

local TITLE_HEIGHT = 44
local STATS_HEIGHT = 86
local FILTER_HEIGHT = 58
local FILTER_ROW = 48
local FILTER_GAP = 10

local FOOTER_HEIGHT = 30

local GRAPH_WIDTH = 232
local CARD_GAP = 8

local MIN_WIDTH = 780
local MIN_HEIGHT = 460
local DEFAULT_WIDTH = 940
local DEFAULT_HEIGHT = 620

local searchTimer = nil
local ticker = nil
local renderedRevision = nil
local shareMenu = nil

-- Menu values are channels, so printing for the player alone gets a value no channel can have.
local SHARE_TO_SELF = "self"

-- Shares the session the stat cards show: the picked one while the range is a session, else the live one.
local function showShareMenu(anchor)
    local items = {}

    for _, entry in ipairs(MLH:getShareChannels()) do
        items[#items+1] = { text = entry.text, value = entry.channel }
    end

    items[#items+1] = { text = L["S_ShareSelf"], value = SHARE_TO_SELF }

    shareMenu = shareMenu or UI:menu()

    shareMenu:ClearAllPoints()
    shareMenu:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -2)
    shareMenu:Open(items, function(channel)
        local viewing = MLH:getFilters().range == MLH.RANGE_SESSION and MLH:getSelectedSession() or nil

        MLH:shareSession(channel ~= SHARE_TO_SELF and channel or nil, viewing)
    end, nil, 140)
end


function View.refreshReport(keepScroll)
    if (not View.window) then return end

    MLH:clearPriceCache()

    View.report = View.isCurrencyView() and MLH:buildCurrencyReport() or MLH:buildReport()
    renderedRevision = MLH.historyRevision

    View.rebuildList()
    View.refreshHeader()

    if (not keepScroll) then View.scrollOffset = 0 end

    local isEmpty = #View.displayList == 0

    View.window.emptyText:SetText(View.isCurrencyView() and L["R_NoCurrenciesHere"] or L["R_NothingIsHereYet"])
    View.window.empty:SetShown(isEmpty)
    View.window.emptyReset:SetShown(isEmpty and MLH:hasActiveFilters())
    View.window.header:SetShown(not isEmpty)

    View.updateScroll(View.scrollOffset)
    View.updateSession()
    View.updateFooter()

    View.window.zoneDropdown:SetText(MLH:getZoneFilterName())
    View.window.qualityDropdown:SetText(MLH:getQualityName(MLH:getFilters().quality))
    View.window.sessionDropdown:SetText(MLH:getSelectedSessionName())
    View.window.scopeDropdown:SetText(MLH:getScopeName())
    View.window.rangeControl:Refresh()
    View.window.exactToggle:Refresh()
    View.window.viewControl:Refresh()

    View.window:UpdateLayout()
end

function MLH:refreshReport()
    if (not View.window or not View.window:IsShown()) then return end

    View.window.statsRow:SetShown(self.db.char.config.showSessionBar and true or false)
    View.window:UpdateLayout()
    View.refreshReport(true)
end

local function saveWindowPosition()
    if (not View.window) then return end

    local point, _, relativePoint, x, y = View.window:GetPoint()

    MLH.db.char.ui = MLH.db.char.ui or {}
    MLH.db.char.ui.point = point
    MLH.db.char.ui.relativePoint = relativePoint
    MLH.db.char.ui.x = x
    MLH.db.char.ui.y = y
    MLH.db.char.ui.width = View.window:GetWidth()
    MLH.db.char.ui.height = View.window:GetHeight()
end

local function buildWindow()
    local frame = CreateFrame("Frame", "MLHReportFrame", UIParent)

    frame:SetFrameStrata("HIGH")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:SetResizable(true)
    frame:EnableMouse(true)
    frame:Hide()

    if (frame.SetResizeBounds) then
        frame:SetResizeBounds(MIN_WIDTH, MIN_HEIGHT)
    end

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
        saveWindowPosition()
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
    subtitle:SetText(UnitName("player").." · "..(GetRealmName() or ""))

    local viewControl = UI:segmented(titleBar, 26, {
        { value = "items", text = L["R_ViewItems"] },
        { value = "currency", text = L["R_ViewCurrencies"] },
    },
        function() return MLH:getFilters().view end,
        function(value)
            MLH:setFilter("view", value)
            View.refreshReport()
        end)
    viewControl:SetPoint("LEFT", subtitle, "RIGHT", 20, 0)

    local close = UI:iconButton(titleBar, 28, "Interface\\Buttons\\UI-StopButton",
        function() frame:Hide() end)
    close:SetPoint("RIGHT", -6, 0)
    UI:tooltip(close, L["R_Close"])

    local settings = UI:iconButton(titleBar, 28, "Interface\\Buttons\\UI-OptionsButton", function()
        MLH:toggleSettings()
    end)
    settings:SetPoint("RIGHT", close, "LEFT", -2, 0)
    UI:tooltip(settings, L["R_Settings"])

    local export = UI:iconButton(titleBar, 28, "Interface\\Buttons\\UI-GuildButton-PublicNote-Up",
        function() View.showExportWindow() end)
    export:SetPoint("RIGHT", settings, "LEFT", -2, 0)
    UI:tooltip(export, L["R_Export"], L["R_ExportTooltip"])

    local share = nil

    share = UI:iconButton(titleBar, 28, "Interface\\ChatFrame\\UI-ChatIcon-Chat-Up", function()
        showShareMenu(share)
    end)
    share:SetPoint("RIGHT", export, "LEFT", -2, 0)
    UI:tooltip(share, L["R_Share"], L["R_ShareTooltip"])

    local statsRow = CreateFrame("Frame", nil, frame)
    statsRow:SetPoint("TOPLEFT", titleBar, "BOTTOMLEFT", PAD, -PAD)
    statsRow:SetPoint("TOPRIGHT", titleBar, "BOTTOMRIGHT", -PAD, -PAD)
    statsRow:SetHeight(STATS_HEIGHT)

    local cards = {
        time = View.createCard(statsRow, L["G_Session"], "accent"),
        items = View.createCard(statsRow, L["G_ItemsPerHour"], "borderLight"),
        gold = View.createCard(statsRow, L["G_GoldPerHour"], "money"),
        filtered = View.createCard(statsRow, L["G_InView"], "borderLight"),
    }

    cards.time:EnableMouse(true)
    cards.time:SetScript("OnMouseUp", function()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        MLH:resetSession()
        View.refreshReport(true)
    end)
    UI:tooltip(cards.time, L["G_Session"], L["S_SessionTooltip"])
    UI:tooltip(cards.items, L["G_ItemsPerHour"], L["G_ItemsPerHourTooltip"])
    UI:tooltip(cards.gold, L["G_GoldPerHour"], L["G_GoldPerHourTooltip"])
    UI:tooltip(cards.filtered, L["G_InView"], L["G_InViewTooltip"])

    local graph = View.createActivityGraph(statsRow)
    graph:SetPoint("TOPRIGHT")
    graph:SetPoint("BOTTOMRIGHT")
    graph:SetWidth(GRAPH_WIDTH)

    local filterBar = CreateFrame("Frame", nil, frame)
    filterBar:SetPoint("TOPLEFT", statsRow, "BOTTOMLEFT", 0, -PAD)
    filterBar:SetPoint("TOPRIGHT", statsRow, "BOTTOMRIGHT", 0, -PAD)
    filterBar:SetHeight(FILTER_HEIGHT)

    local search = UI:searchBox(filterBar, 190, 26, L["R_SearchPlaceholder"], function(text, userInput)
        if (not userInput) then return end

        MLH:setFilter("search", text)

        if (searchTimer) then searchTimer:Cancel() end

        searchTimer = C_Timer.NewTimer(0.25, function()
            searchTimer = nil
            View.refreshReport()
        end)
    end)
    local searchCaption = UI:text(filterBar, 11, "textFaint")
    searchCaption:SetPoint("BOTTOMLEFT", search, "TOPLEFT", 1, 4)
    searchCaption:SetText(L["R_Search"])

    local rangeControl = UI:segmented(filterBar, 26, MLH:getShortRangeList(),
        function() return MLH:getFilters().range end,
        function(value)
            MLH:setFilter("range", value)
            View.refreshReport()
        end)
    local rangeCaption = UI:text(filterBar, 11, "textFaint")
    rangeCaption:SetPoint("BOTTOMLEFT", rangeControl, "TOPLEFT", 1, 4)
    rangeCaption:SetText(L["R_ReportDateRange"])

    local qualityDropdown = UI:dropdown(filterBar, 118, 26, L["R_MinimumItemQuality"],
        function() return MLH:getQualityList() end,
        function() return MLH:getFilters().quality end,
        function(value)
            MLH:setFilter("quality", value)
            View.refreshReport()
        end)
    local zoneDropdown = UI:dropdown(filterBar, 150, 26, L["R_Zone"],
        function() return MLH:getZoneList() end,
        function() return MLH:getFilters().zone end,
        function(value)
            MLH:setFilter("zone", value)
            View.refreshReport()
        end)
    local sessionDropdown = UI:dropdown(filterBar, 190, 26, L["S_SessionPicker"],
        function() return MLH:getSessionList() end,
        function() return MLH:getFilters().session or 0 end,
        function(value)
            MLH:setFilter("session", value)
            View.refreshReport()
        end)
    local scopeDropdown = UI:dropdown(filterBar, 140, 26, L["R_Scope"],
        function() return MLH:getScopeList() end,
        function() return MLH:getFilters().scope or "char" end,
        function(value)
            MLH:setFilter("scope", value)
            View.refreshReport()
        end)
    local exactToggle = UI:toggle(filterBar, L["R_ExactItemQuality"],
        function() return MLH:getFilters().exactQuality end,
        function(value)
            MLH:setFilter("exactQuality", value)
            View.refreshReport()
        end)

    local function layoutFilters()
        local available = math.max(filterBar:GetWidth(), 1)
        local flow = {
            search, rangeControl, sessionDropdown, qualityDropdown, zoneDropdown,
            scopeDropdown, exactToggle,
        }

        sessionDropdown:SetShown(MLH:getFilters().range == MLH.RANGE_SESSION)
        scopeDropdown:SetShown(MLH:getCharacterCount() > 1)

        qualityDropdown:SetShown(not View.isCurrencyView())
        exactToggle:SetShown(not View.isCurrencyView())

        local placements = {}
        local lineCount, x = 1, 0

        for i = 1, #flow do
            local control = flow[i]

            if (control:IsShown()) then
                local width = control:GetWidth()

                if (x > 0 and x + width > available) then
                    lineCount = lineCount + 1
                    x = 0
                end

                placements[#placements+1] = { control = control, row = lineCount, x = x }

                x = x + width + FILTER_GAP
            end
        end

        for i = 1, #placements do
            local placement = placements[i]
            local control = placement.control
            local y = (lineCount - placement.row) * FILTER_ROW
            local nudge = control == exactToggle and 3 or 0

            control:ClearAllPoints()
            control:SetPoint("BOTTOMLEFT", filterBar, "BOTTOMLEFT", placement.x, y + nudge)
        end

        filterBar:SetHeight(FILTER_HEIGHT + (lineCount - 1) * FILTER_ROW)
    end

    layoutFilters()

    local header = CreateFrame("Frame", nil, frame)
    header:SetPoint("TOPLEFT", filterBar, "BOTTOMLEFT", -PAD + 1, -4)
    header:SetPoint("TOPRIGHT", filterBar, "BOTTOMRIGHT", PAD - 1, -4)
    header:SetHeight(HEADER_HEIGHT)

    local headerRule = header:CreateTexture(nil, "ARTWORK")
    headerRule:SetPoint("BOTTOMLEFT", PAD, 0)
    headerRule:SetPoint("BOTTOMRIGHT", -PAD, 0)
    headerRule:SetHeight(1)
    headerRule:SetColorTexture(UI:rgb("border"))

    header.quality = View.createHeaderColumn(header, "quality", L["R_ColQuality"], "LEFT")
    header.name = View.createHeaderColumn(header, "name", L["R_ColItem"], "LEFT")
    header.quantity = View.createHeaderColumn(header, "quantity", L["R_ColQuantity"], "RIGHT")
    header.value = View.createHeaderColumn(header, "value", L["R_ColValue"], "RIGHT")
    header.market = View.createHeaderColumn(header, "market", L["R_ColValueMarket"], "RIGHT")
    header.character = View.createHeaderColumn(header, "character", L["R_ColCharacter"], "LEFT")
    header.source = View.createHeaderColumn(header, "source", L["R_ColSource"], "LEFT")
    header.zone = View.createHeaderColumn(header, "zone", L["R_ColZone"], "LEFT")
    header.lastLooted = View.createHeaderColumn(header, "lastLooted", L["R_ColLooted"], "LEFT")

    header.earned = View.createHeaderColumn(header, "earned", L["R_ColEarned"], "RIGHT")
    header.perHour = View.createHeaderColumn(header, "perHour", L["R_ColPerHour"], "RIGHT")
    header.held = View.createHeaderColumn(header, "held", L["R_ColHeld"], "RIGHT")
    header.cap = View.createHeaderColumn(header, "cap", L["R_ColCap"], "RIGHT")

    local list = CreateFrame("Frame", nil, frame)
    list:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -2)
    list:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, FOOTER_HEIGHT + 1)
    list:SetClipsChildren(true)
    list:EnableMouseWheel(true)

    list:SetScript("OnMouseWheel", function(_, delta)
        View.updateScroll(View.scrollOffset - delta * ROW_HEIGHT * 2)
    end)

    local scrollbar = UI:scrollbar(list, function(offset)
        View.scrollOffset = offset
        View.layoutRows()
    end)
    scrollbar:SetPoint("TOPRIGHT", -3, -2)
    scrollbar:SetPoint("BOTTOMRIGHT", -3, 2)

    local empty = CreateFrame("Frame", nil, list)
    empty:SetAllPoints()

    local emptyIcon = empty:CreateTexture(nil, "ARTWORK")
    emptyIcon:SetSize(52, 52)
    emptyIcon:SetPoint("CENTER", 0, 40)
    emptyIcon:SetTexture("Interface\\Icons\\inv_misc_bag_10")
    emptyIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    emptyIcon:SetDesaturated(true)
    emptyIcon:SetAlpha(0.35)

    local emptyText = UI:text(empty, 13, "textDim")
    emptyText:SetPoint("TOP", emptyIcon, "BOTTOM", 0, -14)
    emptyText:SetJustifyH("CENTER")
    emptyText:SetText(L["R_NothingIsHereYet"])

    local emptyReset = UI:button(empty, L["R_ResetFilters"], 130, 26, function()
        MLH:resetFilters()
        View.window.search:SetValue("")
        View.refreshReport()
    end)
    emptyReset:SetPoint("TOP", emptyText, "BOTTOM", 0, -16)

    local footer = UI:panel(frame, "panel", false)
    footer:SetPoint("BOTTOMLEFT", 1, 1)
    footer:SetPoint("BOTTOMRIGHT", -1, 1)
    footer:SetHeight(FOOTER_HEIGHT)

    local footerRule = footer:CreateTexture(nil, "ARTWORK")
    footerRule:SetPoint("TOPLEFT")
    footerRule:SetPoint("TOPRIGHT")
    footerRule:SetHeight(1)
    footerRule:SetColorTexture(UI:rgb("border"))

    local footerText = UI:text(footer, 12, "textDim")
    footerText:SetPoint("LEFT", PAD, 0)

    local footerZone = UI:text(footer, 11, "textFaint")
    footerZone:SetPoint("RIGHT", -PAD - 14, 0)
    footerZone:SetJustifyH("RIGHT")

    local grip = CreateFrame("Button", nil, frame)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -2, 2)

    for i = 1, 3 do
        local pip = grip:CreateTexture(nil, "OVERLAY")
        pip:SetSize(2, 2)
        pip:SetPoint("BOTTOMRIGHT", -2 - (i - 1) * 4, 2)
        pip:SetColorTexture(UI:rgb("borderLight"))
    end

    grip:SetScript("OnMouseDown", function()
        if (not MLH.db.char.config.resizableReportWindow) then return end

        frame:StartSizing("BOTTOMRIGHT")
    end)

    grip:SetScript("OnMouseUp", function()
        frame:StopMovingOrSizing()
        saveWindowPosition()
        frame:UpdateLayout()
        View.refreshReport(true)
    end)

    UI:tooltip(grip, L["R_ResizeHint"])

    frame.titleBar = titleBar
    frame.statsRow = statsRow
    frame.cards = cards
    frame.graph = graph
    frame.filterBar = filterBar
    frame.viewControl = viewControl
    frame.search = search
    frame.rangeControl = rangeControl
    frame.qualityDropdown = qualityDropdown
    frame.zoneDropdown = zoneDropdown
    frame.sessionDropdown = sessionDropdown
    frame.scopeDropdown = scopeDropdown
    frame.exactToggle = exactToggle
    frame.header = header
    frame.list = list
    frame.scrollbar = scrollbar
    frame.empty = empty
    frame.emptyText = emptyText
    frame.emptyReset = emptyReset
    frame.footerText = footerText
    frame.footerZone = footerZone
    frame.grip = grip

    frame.UpdateLayout = function(self)
        local showSession = MLH.db.char.config.showSessionBar and true or false

        statsRow:SetShown(showSession)
        graph:SetShown(showSession and self:GetWidth() >= 860)

        if (showSession) then
            filterBar:SetPoint("TOPLEFT", statsRow, "BOTTOMLEFT", 0, -PAD)
            filterBar:SetPoint("TOPRIGHT", statsRow, "BOTTOMRIGHT", 0, -PAD)
        else
            filterBar:SetPoint("TOPLEFT", titleBar, "BOTTOMLEFT", PAD, -PAD)
            filterBar:SetPoint("TOPRIGHT", titleBar, "BOTTOMRIGHT", -PAD, -PAD)
        end

        local available = statsRow:GetWidth() - (graph:IsShown() and (GRAPH_WIDTH + CARD_GAP) or 0)
        local cardWidth = (available - CARD_GAP * 3) / 4
        local order = { cards.time, cards.items, cards.gold, cards.filtered }

        for i = 1, #order do
            local card = order[i]

            card:ClearAllPoints()
            card:SetPoint("TOPLEFT", statsRow, "TOPLEFT", (i - 1) * (cardWidth + CARD_GAP), 0)
            card:SetSize(cardWidth, STATS_HEIGHT)
        end

        layoutFilters()

        grip:SetShown(MLH.db.char.config.resizableReportWindow and true or false)

        View.updateActivity()
    end

    frame:SetScript("OnSizeChanged", function(self)
        if (not self:IsShown()) then return end

        self:UpdateLayout()
        View.updateScroll(View.scrollOffset)
    end)

    frame:SetScript("OnHide", function(self)
        saveWindowPosition()

        if (searchTimer) then
            searchTimer:Cancel()
            searchTimer = nil
        end

        if (ticker) then
            ticker:Cancel()
            ticker = nil
        end

        self.qualityDropdown:Close()
        self.zoneDropdown:Close()
        self.sessionDropdown:Close()
        self.scopeDropdown:Close()

        View.closeRowMenu()
        if (shareMenu) then shareMenu:Hide() end
    end)

    local fade = frame:CreateAnimationGroup()
    local alpha = fade:CreateAnimation("Alpha")
    alpha:SetFromAlpha(0)
    alpha:SetToAlpha(1)
    alpha:SetDuration(0.14)
    alpha:SetSmoothing("OUT")

    frame.fade = fade

    if (not tContains(UISpecialFrames, "MLHReportFrame")) then
        tinsert(UISpecialFrames, "MLHReportFrame")
    end

    return frame
end

function MLH:gui()
    if (not View.window) then
        View.window = buildWindow()
    end

    if (View.window:IsShown()) then
        View.window:Hide()
        return
    end

    local saved = self.db.char.ui or {}

    View.window:SetSize(saved.width or DEFAULT_WIDTH, saved.height or DEFAULT_HEIGHT)
    View.window:ClearAllPoints()

    if (saved.point) then
        View.window:SetPoint(saved.point, UIParent, saved.relativePoint or saved.point, saved.x or 0, saved.y or 0)
    else
        View.window:SetPoint("CENTER")
    end

    View.window.search:SetValue(self:getFilters().search)
    View.window:Show()
    View.window:UpdateLayout()

    View.refreshReport()

    View.window.fade:Play()

    -- Fill again next frame, after anchored viewport dimensions settle.
    C_Timer.After(0, function()
        if (View.window and View.window:IsShown()) then View.updateScroll(View.scrollOffset) end
    end)

    -- Coalesce loot bursts into one refresh per tick, preserving scroll position.
    ticker = C_Timer.NewTicker(1, function()
        if (renderedRevision ~= MLH.historyRevision) then
            View.refreshReport(true)
            View.updateActivity()
        else
            View.updateSession()
        end

        if (time() % 30 == 0) then View.updateActivity() end
    end)
end
