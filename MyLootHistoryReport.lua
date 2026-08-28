--[[
My Loot History addon
Copyright (C) 2026 RustyDaemon (https://github.com/RustyDaemon)

See License file for details.
--]]

local MLH = LibStub("AceAddon-3.0"):GetAddon("MyLootHistory")
local AGUI = LibStub("AceGUI-3.0")
local DU = LibStub("DateUtils-1.0")
local L = LibStub("AceLocale-3.0"):GetLocale("MyLootHistory")

local isWindowShown = false
local baseWindowWidth = 640
local window = nil
local itemsContainer = nil
local searchTimer = nil
local sessionLabel = nil
local sessionTicker = nil

-- how often the session bar re-reads the clock while the window is open
local sessionRefreshInterval = 5

-- forward declarations, so the helpers below stay local to this file
local addCurrencyRow, addCurrencyRows, addGoldEarnedRow, addHeaderRow, addIconRow, addItemDetailsRow,
      addItems, addLastLootedRow, addNothingIsHereLabel, addQuantityRow, addValueRow, addZoneRow,
      buildCsv, calculateGoldFound, collectCurrencies, collectItems, formatMoneyShort, getQualityList,
      getRangeList, getZoneList, insertLinkToChat, isInSelectedRange, isInSelectedZone, refreshItems,
      reportWindowWidth, showExportWindow, sortItems, updateSessionBar, updateSummary

local rowWidth = {
    itemDetails = 220,
    quantity = 60,
    value = 110,
    zone = 130,
    lastLooted = 150,
}

-- everything that is not a row: the frame border, the scroll bar and the window insets
local windowChrome = 74

local rangeValue = 2
local qualityValue = 0
local exactItemQuality = false
local zoneValue = 0
local searchText = ""
local sortKey = "quantity"
local sortDescending = true

local FrameBackdrop = {
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 8, right = 8, top = 8, bottom = 8 }
}

function MLH:gui()
    if (isWindowShown) then return end

    local params = MLH.db.char.params

    rangeValue = params.selectedRangeValue or 2
    qualityValue = params.selectedQualityValue or 0
    exactItemQuality = params.selectedExactItemQuality or false
    zoneValue = params.selectedZoneID or 0
    searchText = params.searchText or ""
    sortKey = params.sortKey or "quantity"
    sortDescending = params.sortDescending
    if (sortDescending == nil) then sortDescending = true end

    window = AGUI:Create("Frame")
    window:Hide()

    window:SetTitle("My Loot History")
    window:SetCallback("OnClose", function(widget)
        isWindowShown = false
        itemsContainer = nil
        sessionLabel = nil

        if (searchTimer) then
            searchTimer:Cancel()
            searchTimer = nil
        end

        if (sessionTicker) then
            sessionTicker:Cancel()
            sessionTicker = nil
        end

        AGUI:Release(widget)
        window = nil
    end)
    window.frame:SetBackdrop(FrameBackdrop)
    window:SetLayout("Flow")
    window:SetWidth(reportWindowWidth())
    window:EnableResize(self.db.char.config.resizableReportWindow or false)
    window:SetHeight(460)

    if (not _G["MLHReportFrame"]) then
        _G["MLHReportFrame"] = window.frame
        tinsert(UISpecialFrames, "MLHReportFrame")
    end

    local groupOptions = AGUI:Create("SimpleGroup")
    groupOptions:SetFullWidth(true)
    groupOptions:SetLayout("Flow")
    window:AddChild(groupOptions)

    -- the live half of the window: it keeps counting while the report sits open
    if (self.db.char.config.showSessionBar) then
        local groupSession = AGUI:Create("SimpleGroup")
        groupSession:SetFullWidth(true)
        groupSession:SetLayout("Flow")
        window:AddChild(groupSession)

        sessionLabel = AGUI:Create("InteractiveLabel")
        sessionLabel:SetFullWidth(true)
        sessionLabel:SetHighlight("Interface\\QuestFrame\\UI-QuestTitleHighlight")
        sessionLabel:SetCallback("OnEnter", function()
            GameTooltip:SetOwner(sessionLabel.frame, "ANCHOR_TOP")
            GameTooltip:SetText(L["S_SessionTooltip"])
            GameTooltip:Show()
        end)
        sessionLabel:SetCallback("OnLeave", function() GameTooltip:Hide() end)
        sessionLabel:SetCallback("OnClick", function()
            MLH:resetSession()
            refreshItems()
        end)
        groupSession:AddChild(sessionLabel)

        updateSessionBar()

        sessionTicker = C_Timer.NewTicker(sessionRefreshInterval, updateSessionBar)
    end

    local groupItems = AGUI:Create("SimpleGroup")
    groupItems:SetFullWidth(true)
    groupItems:SetFullHeight(true)
    groupItems:SetLayout("Fill")
    window:AddChild(groupItems)

    itemsContainer = groupItems

    local searchBox = AGUI:Create("EditBox")
    searchBox:SetLabel(L["R_Search"])
    searchBox:SetWidth(190)
    searchBox:DisableButton(true)
    -- the text goes in before the callback: SetText fires OnTextChanged too, and there is
    -- nothing to refresh yet
    searchBox:SetText(searchText)
    -- rebuilding the list on every keystroke is wasteful on a long history, so the
    -- redraw waits until the typing stops
    searchBox:SetCallback("OnTextChanged", function(_, _, value)
        searchText = value
        MLH.db.char.params.searchText = value

        if (searchTimer) then searchTimer:Cancel() end

        searchTimer = C_Timer.NewTimer(0.3, function()
            searchTimer = nil
            refreshItems()
        end)
    end)
    searchBox:SetCallback("OnEnterPressed", function(widget)
        widget:ClearFocus()

        if (searchTimer) then
            searchTimer:Cancel()
            searchTimer = nil
        end

        refreshItems()
    end)
    groupOptions:AddChild(searchBox)

    local timeRangeDropdown = AGUI:Create("Dropdown")
    timeRangeDropdown:SetLabel(L["R_ReportDateRange"])
    timeRangeDropdown:SetWidth(160)
    timeRangeDropdown:SetList(getRangeList())
    timeRangeDropdown:SetValue(rangeValue)
    timeRangeDropdown:SetCallback("OnValueChanged", function(widget, event, key)
        rangeValue = key
        MLH.db.char.params.selectedRangeValue = rangeValue
        refreshItems()
    end)
    groupOptions:AddChild(timeRangeDropdown)

    local qualityDropdown = AGUI:Create("Dropdown")
    qualityDropdown:SetLabel(L["R_MinimumItemQuality"])
    qualityDropdown:SetWidth(150)
    qualityDropdown:SetList(getQualityList())
    qualityDropdown:SetValue(qualityValue)
    qualityDropdown:SetCallback("OnValueChanged", function(widget, event, key)
        qualityValue = key
        MLH.db.char.params.selectedQualityValue = qualityValue
        refreshItems()
    end)
    groupOptions:AddChild(qualityDropdown)

    local zoneList, zoneOrder = getZoneList()
    local zoneDropdown = AGUI:Create("Dropdown")
    zoneDropdown:SetLabel(L["R_Zone"])
    zoneDropdown:SetWidth(160)
    zoneDropdown:SetList(zoneList, zoneOrder)

    -- a zone can disappear from the list when the data behind it is cleared
    if (zoneList[zoneValue] == nil) then
        zoneValue = 0
        MLH.db.char.params.selectedZoneID = 0
    end

    zoneDropdown:SetValue(zoneValue)
    zoneDropdown:SetCallback("OnValueChanged", function(widget, event, key)
        zoneValue = key
        MLH.db.char.params.selectedZoneID = zoneValue
        refreshItems()
    end)
    groupOptions:AddChild(zoneDropdown)

    local exactItemQualityCheckBox = AGUI:Create("CheckBox")
    exactItemQualityCheckBox:SetLabel(L["R_ExactItemQuality"])
    exactItemQualityCheckBox:SetValue(exactItemQuality)
    exactItemQualityCheckBox:SetWidth(150)
    exactItemQualityCheckBox:SetCallback("OnValueChanged", function(widget, event, value)
        exactItemQuality = not exactItemQuality
        MLH.db.char.params.selectedExactItemQuality = exactItemQuality
        refreshItems()
    end)
    groupOptions:AddChild(exactItemQualityCheckBox)

    local exportButton = AGUI:Create("Button")
    exportButton:SetText(L["R_Export"])
    exportButton:SetWidth(110)
    exportButton:SetCallback("OnClick", function()
        showExportWindow()
    end)
    groupOptions:AddChild(exportButton)

    local settingsButton = AGUI:Create("Icon")
    settingsButton:SetImageSize(20, 20)
    settingsButton:SetWidth(28)
    settingsButton:SetHeight(28)
    settingsButton:SetImage("Interface\\Buttons\\UI-OptionsButton")
    settingsButton:SetCallback("OnClick", function()
        window:Hide()
        LibStub("AceConfigDialog-3.0"):Open("MyLootHistory_GeneralOptions")
    end)
    groupOptions:AddChild(settingsButton)

    addItems(groupItems)

    window:Show()
    window:DoLayout()

    isWindowShown = true
end

-- the visible columns decide how wide the window has to be; never narrower than it used to be
function reportWindowWidth()
    local config = MLH.db.char.config
    local width = (config.reportIconSize or 24) + 4
        + rowWidth.itemDetails + rowWidth.quantity + rowWidth.value

    if (config.showZone) then width = width + rowWidth.zone end
    if (config.showLastLooted) then width = width + rowWidth.lastLooted end

    return math.max(baseWindowWidth, width + windowChrome)
end

function refreshItems()
    updateSessionBar()

    if (itemsContainer == nil) then return end

    -- an auction-house price can move while the window is open, so each redraw asks again
    MLH:clearPriceCache()
    addItems(itemsContainer)
end

function updateSessionBar()
    if (sessionLabel == nil) then return end

    local stats = MLH:getSessionStats()

    sessionLabel:SetText(L["S_SessionBar"](
        MLH:formatDuration(stats.duration),
        stats.quantity,
        string.format("%.0f", stats.itemsPerHour),
        GetMoneyString(stats.totalValue),
        GetMoneyString(stats.goldPerHour)
    ))
end

-- The one place the date dropdown is turned into a yes/no about a single record. Items,
-- gold and currency all ask it, so the three can never drift apart.
function isInSelectedRange(foundOn)
    if (rangeValue == 1) then --this session
        local sessionStart = MLH.db.char.thisSessionStart

        return sessionStart ~= nil and foundOn >= sessionStart
    elseif (rangeValue == 2) then --today
        return DU:dateIsToday(foundOn)
    elseif (rangeValue == 3) then --yesterday
        return DU:dateIsYesterday(foundOn, true)
    elseif (rangeValue == 4) then --this reset
        local wday = DU:getToday().wday

        if (DU:isWed(wday)) then
            return DU:dateIsToday(foundOn)
        end

        return DU:dateInRangeTillToday(foundOn, DU:getLastWed(wday))
    elseif (rangeValue == 5) then --this month
        return DU:dateIsInCurrentMonth(foundOn)
    elseif (rangeValue == 6) then --all the time
        return true
    end

    return false
end

function isInSelectedZone(zoneID)
    return zoneValue == 0 or zoneID == zoneValue
end

function calculateGoldFound()
    local gold = MLH.db.char.foundGold
    local totalGold = 0

    for i = 1, #gold do
        local item = gold[i]

        if (isInSelectedZone(item.zoneID) and isInSelectedRange(item.foundOn)) then
            totalGold = totalGold + item.quantity
        end
    end

    return totalGold
end

-- Every currency the character picked up inside the active date range and zone, busiest
-- first. The quality and search filters are about items and do not apply here.
function collectCurrencies()
    local foundCurrency = MLH.db.char.foundCurrency or {}
    local currencies = {}

    for i = 1, #foundCurrency do
        local record = foundCurrency[i]
        local lootData = record.lootData
        local quantity = 0
        local firstFound, lastFound = nil, nil
        local zoneCounts = {}
        local zones = {}

        for j = 1, #lootData do
            local entry = lootData[j]

            if (isInSelectedZone(entry.zoneID) and isInSelectedRange(entry.foundOn)) then
                local entryQuantity = tonumber(entry.quantity) or 1
                local zoneName = MLH:getZoneName(entry.zoneID) or L["R_UnknownZone"]

                quantity = quantity + entryQuantity
                zoneCounts[zoneName] = (zoneCounts[zoneName] or 0) + entryQuantity

                if (firstFound == nil or entry.foundOn < firstFound) then firstFound = entry.foundOn end
                if (lastFound == nil or entry.foundOn > lastFound) then lastFound = entry.foundOn end
            end
        end

        for zoneName, zoneQuantity in pairs(zoneCounts) do
            table.insert(zones, { name = zoneName, quantity = zoneQuantity })
        end

        table.sort(zones, function(l, r)
            if (l.quantity == r.quantity) then return l.name < r.name end
            return l.quantity > r.quantity
        end)

        if (quantity > 0) then
            -- the client wins over the record: a currency can be renamed by a patch
            local info = C_CurrencyInfo.GetCurrencyInfo(record.currencyId)

            table.insert(currencies, {
                currencyId = record.currencyId,
                name = (info and info.name) or record.currencyName or ("#"..record.currencyId),
                icon = (info and info.iconFileID) or record.currencyIcon,
                quantity = quantity,
                zones = zones,
                firstFound = firstFound,
                lastFound = lastFound,
            })
        end
    end

    table.sort(currencies, function(l, r)
        if (l.quantity == r.quantity) then return l.name < r.name end
        return l.quantity > r.quantity
    end)

    return currencies
end

-- Applies every active filter and resolves the display data, so the report window and the
-- CSV export always describe exactly the same set of items.
function collectItems()
    -- nothing below mutates the stored records, so they are read in place
    local itemsFound = MLH.db.char.foundItems
    local items = {}
    local search = searchText ~= "" and searchText:lower() or nil

    for i = 1, #itemsFound do
        local item = itemsFound[i]

        -- a fresh shell holding references to the loot entries that pass the filters
        local newItem = {
            itemId = item.itemId,
            itemLink = item.itemLink,
            itemName = item.itemName,
            itemTexture = item.itemTexture,
            quality = item.quality,
            lootData = {},
            zones = {},
            totalQuantity = 0,
            totalValue = 0,
            dateRange = "",
        }

        for j = 1, #item.lootData do
            local lootData = item.lootData[j]

            if (isInSelectedZone(lootData.zoneID) and isInSelectedRange(lootData.foundOn)) then
                table.insert(newItem.lootData, lootData)
            end
        end

        if (#newItem.lootData > 0) then
            local quality = newItem.quality or 0 -- records written before 1.1.0 can hold a nil quality
            local canBeAdded

            if (not exactItemQuality and quality >= qualityValue) then
                canBeAdded = true
            elseif (exactItemQuality and quality == qualityValue) then
                canBeAdded = true
            else
                canBeAdded = false
            end

            -- the live client data wins over the record: names and prices can change between patches
            local cachedName, cachedLink, cachedQuality, _, _, _, _, _, _, cachedTexture, cachedSellPrice =
                C_Item.GetItemInfo(newItem.itemId)

            newItem.itemLink = cachedLink or newItem.itemLink
            newItem.itemName = cachedName or newItem.itemName or ("#"..newItem.itemId)
            newItem.itemTexture = cachedTexture or newItem.itemTexture
            newItem.quality = cachedQuality or quality
            newItem.sellPrice = cachedSellPrice

            if (canBeAdded and search and not newItem.itemName:lower():find(search, 1, true)) then
                canBeAdded = false
            end

            if (canBeAdded) then
                -- oldest first, so lootData[1] is the first find and lootData[#] the last
                table.sort(newItem.lootData, function(l, r) return l.foundOn < r.foundOn end)

                -- sum the looted quantities, not the number of loot events
                local zoneCounts = {}

                for j = 1, #newItem.lootData do
                    local lootData = newItem.lootData[j]
                    local quantity = tonumber(lootData.quantity) or 1

                    newItem.totalQuantity = newItem.totalQuantity + quantity

                    local zoneName = MLH:getZoneName(lootData.zoneID) or L["R_UnknownZone"]
                    zoneCounts[zoneName] = (zoneCounts[zoneName] or 0) + quantity
                end

                for zoneName, quantity in pairs(zoneCounts) do
                    table.insert(newItem.zones, { name = zoneName, quantity = quantity })
                end

                -- busiest zone first, so zones[1] is the one worth showing in the row
                table.sort(newItem.zones, function(l, r)
                    if (l.quantity == r.quantity) then return l.name < r.name end
                    return l.quantity > r.quantity
                end)

                newItem.zoneName = newItem.zones[1] and newItem.zones[1].name or L["R_UnknownZone"]

                -- an item the client has not cached this session has no price to read, so the
                -- one stamped on the most recent loot entry stands in for it
                if (newItem.sellPrice == nil) then
                    newItem.sellPrice = newItem.lootData[#newItem.lootData].sellPrice or 0
                end

                -- with an auction-house price source switched on this is the market price,
                -- and the vendor price whenever that source has nothing for the item
                newItem.unitPrice, newItem.vendorPriced =
                    MLH:getItemPrice(newItem.itemId, newItem.sellPrice, newItem.itemLink)
                newItem.totalValue = newItem.unitPrice * newItem.totalQuantity

                --refactor this later
                newItem.firstFound = newItem.lootData[1].foundOn
                newItem.lastFound = newItem.lootData[#newItem.lootData].foundOn

                local firstFindDate = date('*t', newItem.firstFound)
                local lastFindDate = date('*t', newItem.lastFound)

                if (firstFindDate.yday ~= lastFindDate.yday) then
                    local dateFormat = "%d %b"
                    local addYearToFirstFind = firstFindDate.year ~= lastFindDate.year
                    local firstFindFormat = dateFormat..(addYearToFirstFind and ' %Y' or '')
                    local lastFindFormat = dateFormat..' %Y'

                    newItem.dateRange = date(firstFindFormat, newItem.firstFound)..' - '
                        ..date(lastFindFormat, newItem.lastFound)
                else
                    newItem.dateRange = date("%d %b %Y, %a", newItem.firstFound)
                end

                table.insert(items, newItem)
            end
        end
    end

    sortItems(items)

    return items
end

function sortItems(items)
    local descending = sortDescending

    local value = function(item)
        if (sortKey == "quantity") then return item.totalQuantity end
        if (sortKey == "quality") then return item.quality end
        if (sortKey == "value") then return item.totalValue end
        if (sortKey == "lastLooted") then return item.lastFound end
        if (sortKey == "zone") then return item.zoneName end

        return item.itemName
    end

    table.sort(items, function(l, r)
        local lv, rv = value(l), value(r)

        if (lv == rv) then
            -- the name is the tie-break, so equal rows keep a stable, readable order
            return l.itemName < r.itemName
        end

        if (descending) then return lv > rv end

        return lv < rv
    end)
end

-- add ignored items
function addItems(container)
    container:ReleaseChildren()

    local items = collectItems()
    local currencies = MLH.db.char.config.showCurrency and collectCurrencies() or {}
    local totalQuantity = 0
    local totalSellPrice = 0

    if (#items == 0 and #currencies == 0) then
        addNothingIsHereLabel(container)
    else
        local group = AGUI:Create("SimpleGroup")
        group:SetFullWidth(true)
        group:SetFullHeight(true)
        group:SetLayout("Flow")
        container:AddChild(group)

        addHeaderRow(group)

        local scrollContainer = AGUI:Create("SimpleGroup")
        scrollContainer:SetFullWidth(true)
        scrollContainer:SetFullHeight(true)
        scrollContainer:SetLayout("Fill")
        group:AddChild(scrollContainer)

        local sf = AGUI:Create("ScrollFrame")
        sf:SetLayout("Flow")
        scrollContainer:AddChild(sf)

        for i = 1, #items do
            local item = items[i]

            totalQuantity = totalQuantity + item.totalQuantity
            totalSellPrice = totalSellPrice + item.totalValue

            local itemFrame = AGUI:Create("SimpleGroup")
            itemFrame:SetLayout("Flow")
            itemFrame:SetFullWidth(true)
            itemFrame:SetHeight(40)

            addIconRow(itemFrame, item)
            addItemDetailsRow(itemFrame, item.itemName, item.itemId, item.quality)
            addQuantityRow(itemFrame, item.totalQuantity)
            addValueRow(itemFrame, item.totalValue, item.vendorPriced)

            if (MLH.db.char.config.showZone) then
                addZoneRow(itemFrame, item.zoneName)
            end

            if (MLH.db.char.config.showLastLooted) then
                addLastLootedRow(itemFrame, item.dateRange)
            end

            sf:AddChild(itemFrame)
        end

        addCurrencyRows(sf, currencies)

        local goldRow = addGoldEarnedRow()
        sf:AddChild(goldRow)

        local empty = AGUI:Create("SimpleGroup")
        empty:SetHeight(6)
        sf:AddChild(empty)

        sf:FixScroll()
        sf:SetScroll(0)
    end

    updateSummary(#items, totalQuantity, totalSellPrice, #currencies)
end

function addHeaderRow(parent)
    local header = AGUI:Create("SimpleGroup")
    header:SetLayout("Flow")
    header:SetFullWidth(true)
    header:SetHeight(24)

    local addColumn = function(key, text, width)
        local label = AGUI:Create("InteractiveLabel")
        local isActive = sortKey == key
        local arrow = isActive and (sortDescending and " v" or " ^") or ""

        label:SetText((isActive and "|cFFFFD100" or "|cFFAAAAAA")..text..arrow.."|r")
        label:SetWidth(width)
        label:SetHighlight("Interface\\QuestFrame\\UI-QuestTitleHighlight")
        label:SetCallback("OnClick", function()
            if (sortKey == key) then
                sortDescending = not sortDescending
            else
                sortKey = key
                -- names read best A-Z, everything else reads best largest-first
                sortDescending = key ~= "name" and key ~= "zone"
            end

            MLH.db.char.params.sortKey = sortKey
            MLH.db.char.params.sortDescending = sortDescending

            refreshItems()
        end)
        label:SetCallback("OnEnter", function()
            GameTooltip:SetOwner(label.frame, "ANCHOR_TOP")
            GameTooltip:SetText(L["R_SortBy"](text))
            GameTooltip:Show()
        end)
        label:SetCallback("OnLeave", function() GameTooltip:Hide() end)

        header:AddChild(label)
    end

    -- the icon column has no name of its own, so it carries the quality sort
    addColumn("quality", L["R_ColQuality"], (MLH.db.char.config.reportIconSize or 24) + 4)
    addColumn("name", L["R_ColItem"], rowWidth.itemDetails)
    addColumn("quantity", L["R_ColQuantity"], rowWidth.quantity)
    -- the column says where its numbers come from once they stop being vendor prices
    local priceSourceKey = MLH:getPriceSource()
    local valueText = priceSourceKey == "vendor" and L["R_ColValue"]
        or (L["R_ColValue"].." "..L["R_ColValueMarket"])

    addColumn("value", valueText, rowWidth.value)

    if (MLH.db.char.config.showZone) then
        addColumn("zone", L["R_ColZone"], rowWidth.zone)
    end

    if (MLH.db.char.config.showLastLooted) then
        addColumn("lastLooted", L["R_ColLooted"], rowWidth.lastLooted)
    end

    parent:AddChild(header)

    local line = AGUI:Create("Heading")
    line:SetFullWidth(true)
    parent:AddChild(line)
end

function updateSummary(totalItems, totalQuantity, totalSellPrice, totalCurrencies)
    if (window == nil) then return end

    if (totalItems == 0 and (totalCurrencies or 0) == 0) then
        window:SetStatusText(L["R_LootSomething"])
        return

    end

    local text = L["R_Items"].."|cFF00CC00"..totalItems.."|r, "..L["R_Quantity"].."|cFF00CC00"
        ..totalQuantity.."|r, "..L["R_SellPrice"]..GetMoneyString(totalSellPrice)

    if ((totalCurrencies or 0) > 0) then
        text = text..", "..L["R_CurrenciesCount"].."|cFF00CC00"..totalCurrencies.."|r"
    end

    window:SetStatusText(text)
end

-- Currencies have no vendor value and no quality to sort by, so they sit under the items as
-- their own short block rather than pretending to be rows in the table above.
function addCurrencyRows(parent, currencies)
    if (#currencies == 0) then return end

    local heading = AGUI:Create("Heading")
    heading:SetText(L["R_Currencies"])
    heading:SetFullWidth(true)
    parent:AddChild(heading)

    for i = 1, #currencies do
        parent:AddChild(addCurrencyRow(currencies[i]))
    end
end

function addCurrencyRow(currency)
    local frame = AGUI:Create("SimpleGroup")
    frame:SetLayout("Flow")
    frame:SetFullWidth(true)
    frame:SetHeight(40)

    local icon = AGUI:Create("Icon")
    local iconSize = MLH.db.char.config.reportIconSize

    icon:SetImageSize(iconSize, iconSize)
    icon:SetImage(currency.icon)
    icon:SetHeight(iconSize + 2)
    icon:SetWidth(iconSize + 4)

    if (MLH.db.char.config.showTooltip) then
        icon:SetCallback("OnEnter", function()
            GameTooltip:SetOwner(icon.frame, "ANCHOR_RIGHT")
            GameTooltip:SetCurrencyByID(currency.currencyId)
            GameTooltip:Show()
        end)
        icon:SetCallback("OnLeave", function() GameTooltip:Hide() end)
    end

    frame:AddChild(icon)

    local nameLabel = AGUI:Create("Label")
    nameLabel:SetText(currency.name)
    nameLabel:SetWidth(rowWidth.itemDetails)
    frame:AddChild(nameLabel)

    local quantityLabel = AGUI:Create("Label")
    quantityLabel:SetText(tostring(currency.quantity))
    quantityLabel:SetWidth(rowWidth.quantity)
    frame:AddChild(quantityLabel)

    return frame
end

function addGoldEarnedRow()
    local goldFrame = AGUI:Create("SimpleGroup")
    goldFrame:SetLayout("Flow")
    goldFrame:SetFullWidth(true)
    goldFrame:SetHeight(40)

    local itemIcon = AGUI:Create("Icon")
    local iconSize = MLH.db.char.config.reportIconSize

    itemIcon:SetImageSize(iconSize, iconSize)
    itemIcon:SetImage(133784)
    itemIcon:SetHeight(iconSize + 2)
    itemIcon:SetWidth(iconSize + 4)

    goldFrame:AddChild(itemIcon)

    local nameLabel = AGUI:Create("Label")

    nameLabel:SetText(L["R_GoldEarned"]..GetMoneyString(calculateGoldFound()))
    nameLabel:SetWidth(250)

    goldFrame:AddChild(nameLabel)

    return goldFrame
end

function addIconRow(frame, item)
    local itemIcon = AGUI:Create("Icon")
    local iconSize = MLH.db.char.config.reportIconSize
    local itemLink = item.itemLink

    itemIcon:SetImageSize(iconSize, iconSize)
    itemIcon:SetImage(item.itemTexture)

    if (MLH.db.char.config.showTooltip) then
        itemIcon:SetCallback("OnEnter", function(_)
            GameTooltip:SetOwner(itemIcon.frame, "ANCHOR_RIGHT")

            -- the rows below say the same thing in more detail, so the global tooltip line
            -- stays out of the report's own tooltip
            MLH:setTooltipSuppressed(true)
            GameTooltip:SetHyperlink(itemLink)
            MLH:setTooltipSuppressed(false)

            if (MLH.db.char.config.showAdditionalTooltipData) then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("|cFFDDDDDD"..L["R_TotalQuantityGathered"].."|r |cFF00BB00"
                    ..(item.totalQuantity or 0)..'|r', 1, 1, 1, true)

                local zones = {}

                for i = 1, #item.zones do
                    zones[i] = item.zones[i].name.." ("..item.zones[i].quantity..")"
                end

                if (#zones > 0) then
                    GameTooltip:AddLine("|cFFDDDDDD"..L["R_LootedIn"].."|r |cFF00BB00"
                        ..table.concat(zones, ", ")..'|r', 1, 1, 1, true)
                end
            end

            GameTooltip:Show()
        end)

        itemIcon:SetCallback("OnLeave", function(_)
            GameTooltip:Hide()
        end)
    end

    itemIcon:SetCallback("OnClick", function(_, _, button)
        if (button == "LeftButton" and (IsLeftShiftKeyDown() or IsRightShiftKeyDown())) then
            insertLinkToChat(itemLink)
        end
    end)

    itemIcon:SetHeight(iconSize + 2)
    itemIcon:SetWidth(iconSize + 4)

    frame:AddChild(itemIcon)
end

function addItemDetailsRow(frame, itemName, itemId, itemQuality)
    local nameLabel = AGUI:Create("Label")
    local _, _, _, hex = C_Item.GetItemQualityColor(itemQuality)
    local itemText = '|c'..hex..itemName..'|r'

    if (MLH.db.char.config.showItemID) then
        itemText = itemText..'\n  |cFFAAAAAAid: '..itemId..'|r'
    end

    nameLabel:SetText(itemText)
    nameLabel:SetWidth(rowWidth.itemDetails)

    frame:AddChild(nameLabel)
end

function addQuantityRow(frame, itemQuantity)
    local quantityLabel = AGUI:Create("Label")

    quantityLabel:SetText(tostring(itemQuantity))
    quantityLabel:SetWidth(rowWidth.quantity)

    frame:AddChild(quantityLabel)
end

-- `vendorPriced` means an auction-house source is selected but had no price for this item, so
-- the figure is the vendor price. It is greyed rather than hidden: the number is still real,
-- it just is not a market price, and greying is what tells the two apart at a glance.
function addValueRow(frame, totalValue, vendorPriced)
    local valueLabel = AGUI:Create("Label")
    local text = formatMoneyShort(totalValue)

    valueLabel:SetText(vendorPriced and ("|cFF999999"..text.."|r") or text)
    valueLabel:SetWidth(rowWidth.value)

    frame:AddChild(valueLabel)
end

function addZoneRow(frame, zoneName)
    local zoneLabel = AGUI:Create("Label")

    zoneLabel:SetText("|cFFCCCCCC"..zoneName.."|r")
    zoneLabel:SetWidth(rowWidth.zone)

    frame:AddChild(zoneLabel)
end

function addLastLootedRow(frame, itemFoundOn)
    local itemFoundOnLabel = AGUI:Create("Label")
    itemFoundOnLabel:SetText(itemFoundOn)
    itemFoundOnLabel:SetWidth(rowWidth.lastLooted)

    frame:AddChild(itemFoundOnLabel)
end

function addNothingIsHereLabel(frame)
    local emptyLabel = AGUI:Create("Label")

    emptyLabel:SetText(L["R_NothingIsHereYet"])
    emptyLabel:SetWidth(100)

    --add 'reset filters' button ?

    frame:AddChild(emptyLabel)
end

-- GetMoneyString spells all three units out with icons, which is far too wide for a column.
-- This keeps the two units that matter and colours them the way the game does.
function formatMoneyShort(copper)
    copper = copper or 0

    local gold = math.floor(copper / 10000)
    local silver = math.floor(copper % 10000 / 100)
    local rest = math.floor(copper % 100)

    if (gold > 0) then
        return gold.."|cFFFFD700g|r "..silver.."|cFFC7C7CFs|r"
    end

    if (silver > 0) then
        return silver.."|cFFC7C7CFs|r "..rest.."|cFFEDA55Fc|r"
    end

    return rest.."|cFFEDA55Fc|r"
end

function insertLinkToChat(itemLink)
    if (not itemLink) then return end

    ChatEdit_TryInsertChatLink(itemLink)
end

-- ── CSV export ────────────────────────────────────────────────────────────────

local function csvField(value)
    value = tostring(value or "")

    if (value:find('[,"\n]')) then
        return '"'..value:gsub('"', '""')..'"'
    end

    return value
end

local function csvZones(zones)
    local parts = {}

    for i = 1, #zones do
        parts[i] = zones[i].name.." ("..zones[i].quantity..")"
    end

    return table.concat(parts, "; ")
end

function buildCsv()
    local items = collectItems()
    local currencies = MLH.db.char.config.showCurrency and collectCurrencies() or {}
    local lines = { "type,name,id,quality,quantity,value,zone,firstLooted,lastLooted" }

    for i = 1, #items do
        local item = items[i]
        local qualityName = _G["ITEM_QUALITY"..(item.quality or 0).."_DESC"] or tostring(item.quality or 0)

        lines[#lines+1] = table.concat({
            "item",
            csvField(item.itemName),
            csvField(item.itemId),
            csvField(qualityName),
            csvField(item.totalQuantity),
            csvField(item.totalValue),
            csvField(csvZones(item.zones)),
            csvField(date("%Y-%m-%d %H:%M:%S", item.firstFound)),
            csvField(date("%Y-%m-%d %H:%M:%S", item.lastFound)),
        }, ",")
    end

    -- currencies have no quality and no value, so those two cells stay empty
    for i = 1, #currencies do
        local currency = currencies[i]

        lines[#lines+1] = table.concat({
            "currency",
            csvField(currency.name),
            csvField(currency.currencyId),
            "",
            csvField(currency.quantity),
            "",
            csvField(csvZones(currency.zones)),
            csvField(date("%Y-%m-%d %H:%M:%S", currency.firstFound)),
            csvField(date("%Y-%m-%d %H:%M:%S", currency.lastFound)),
        }, ",")
    end

    return table.concat(lines, "\n"), #items + #currencies
end

function showExportWindow()
    local csv, itemCount = buildCsv()

    local exportWindow = AGUI:Create("Frame")
    exportWindow:SetTitle(L["R_ExportTitle"])
    exportWindow:SetStatusText(L["R_ExportHint"](itemCount))
    exportWindow:SetLayout("Fill")
    exportWindow:SetWidth(600)
    exportWindow:SetHeight(420)
    exportWindow:SetCallback("OnClose", function(widget) AGUI:Release(widget) end)
    exportWindow.frame:SetBackdrop(FrameBackdrop)

    local editBox = AGUI:Create("MultiLineEditBox")
    editBox:SetLabel("")
    editBox:SetFullWidth(true)
    editBox:SetFullHeight(true)
    editBox:DisableButton(true)
    editBox:SetText(csv)
    exportWindow:AddChild(editBox)

    editBox.editBox:SetFocus()
    editBox.editBox:HighlightText()
end

function getQualityList()
    local result = {}

    -- Poor through Legendary. Artifact, Heirloom and WoW Token sit above it in the enum
    -- and are not ordinary loot, so the range is named rather than trimmed off the end.
    for i = Enum.ItemQuality.Poor, Enum.ItemQuality.Legendary do
        local _, _, _, hex = C_Item.GetItemQualityColor(i)
        local desc = _G["ITEM_QUALITY" .. i .. "_DESC"]

        if (desc) then
            result[i] = '|c'..hex..desc..'|r'
        end
     end

     return result
end

function getRangeList()
    return {
        [1] = L["RR_ThisSesion"],
        [2] = L["RR_Today"],
        [3] = L["RR_Yesterday"],
        [4] = L["RR_WedToWed"],
        [5] = L["RR_ThisMonth"],
        [6] = L["RR_AllTheTime"],
    }
end

-- Every zone the character has ever looted in, named. Built from the whole history rather
-- than the current date range, so switching the range never empties the dropdown.
function getZoneList()
    local list = { [0] = L["RR_AnyZone"] }
    local order = { 0 }
    local named = {}
    local itemsFound = MLH.db.char.foundItems

    for i = 1, #itemsFound do
        local lootData = itemsFound[i].lootData

        for j = 1, #lootData do
            local zoneID = lootData[j].zoneID

            if (zoneID and list[zoneID] == nil) then
                local zoneName = MLH:getZoneName(zoneID)

                if (zoneName) then
                    list[zoneID] = zoneName
                    named[#named+1] = { id = zoneID, name = zoneName }
                end
            end
        end
    end

    table.sort(named, function(l, r) return l.name < r.name end)

    for i = 1, #named do
        order[#order+1] = named[i].id
    end

    return list, order
end
