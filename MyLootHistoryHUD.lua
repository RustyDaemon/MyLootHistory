--[[
My Loot History addon
Copyright (C) 2026 RustyDaemon (https://github.com/RustyDaemon)

See License file for details.
--]]

-- The session HUD.
--
-- The three live numbers - how long you have been at it, items an hour and gold an hour -
-- already exist as stat cards at the top of the report, but the report is a window you open
-- to read and then close again. The question those three answer ("is this spot still worth
-- farming?") is one the player wants answered *while* farming, without a 940px window over
-- the middle of the screen.
--
-- So this is the same three numbers and nothing else: a small bar that can sit anywhere,
-- reading from MLH:getSessionStats like the cards do, so the two can never disagree.

local MLH = LibStub("AceAddon-3.0"):GetAddon("MyLootHistory")
local L = LibStub("AceLocale-3.0"):GetLocale("MyLootHistory")
local UI = MLH.UI

local CELL_COUNT = 3
local WIDTH = 246
local HEIGHT = 30

-- The client's own coin, inline: a trailing "g" after a rounded figure reads as part of the
-- number ("12.3kg"), the coin reads as a unit. The report uses the same one.
local GOLD_ICON = "|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:0:-1|t"

local hud = nil
local ticker = nil

local function isLocked()
    return MLH.db.char.config.hudLocked and true or false
end

local function savePosition()
    if (not hud) then return end

    local point, _, relativePoint, x, y = hud:GetPoint()

    MLH.db.char.ui = MLH.db.char.ui or {}
    MLH.db.char.ui.hud = { point = point, relativePoint = relativePoint, x = x, y = y }
end

local function buildHud()
    local frame = CreateFrame("Frame", "MLHHudFrame", UIParent)

    frame:SetFrameStrata("MEDIUM")
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:Hide()

    local shadow = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    shadow:SetPoint("TOPLEFT", -4, 4)
    shadow:SetPoint("BOTTOMRIGHT", 4, -4)
    shadow:SetColorTexture(0, 0, 0, 0.35)

    local bg = frame:CreateTexture(nil, "BACKGROUND", nil, -7)
    bg:SetAllPoints()
    bg:SetColorTexture(UI:rgb("window", 0.85))

    UI:addBorder(frame, UI:rgb("border"))
    UI:attachHover(frame, "panelHover", 0.5, "BORDER")

    -- the same warm stripe the session card carries, so the bar reads as part of the addon
    local stripe = frame:CreateTexture(nil, "ARTWORK")
    stripe:SetPoint("TOPLEFT")
    stripe:SetPoint("BOTTOMLEFT")
    stripe:SetWidth(2)
    stripe:SetColorTexture(UI:rgb("accent"))

    local cells = {}

    for i = 1, CELL_COUNT do
        local value = UI:number(frame, 13, i == CELL_COUNT and "money" or "text")

        value:SetJustifyH("CENTER")
        value:SetWordWrap(false)
        cells[i] = value

        if (i > 1) then
            local divider = frame:CreateTexture(nil, "ARTWORK")
            divider:SetPoint("TOP", frame, "TOPLEFT", 0, -7)
            divider:SetPoint("BOTTOM", frame, "BOTTOMLEFT", 0, 7)
            divider:SetWidth(1)
            divider:SetColorTexture(UI:rgb("border"))

            cells[i].divider = divider
        end
    end

    -- the cells share the width left of the stripe, and are laid out from here rather than
    -- at a fixed pitch so a change to WIDTH needs no second edit
    frame.LayoutCells = function(self)
        local usable = self:GetWidth() - 4
        local cellWidth = usable / CELL_COUNT

        for i = 1, CELL_COUNT do
            local cell = cells[i]

            cell:ClearAllPoints()
            cell:SetPoint("LEFT", self, "LEFT", 4 + (i - 1) * cellWidth, 0)
            cell:SetWidth(cellWidth)

            if (cell.divider) then
                cell.divider:ClearAllPoints()
                cell.divider:SetPoint("TOP", self, "TOPLEFT", 4 + (i - 1) * cellWidth, -7)
                cell.divider:SetPoint("BOTTOM", self, "BOTTOMLEFT", 4 + (i - 1) * cellWidth, 7)
            end
        end
    end

    frame:SetScript("OnDragStart", function(self)
        if (isLocked()) then return end

        self.dragging = true
        self:StartMoving()
    end)

    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        savePosition()
    end)

    frame:SetScript("OnMouseUp", function(self, button)
        -- letting go at the end of a drag is a mouse-up too, and it must not also count as
        -- the click that opens the report
        if (self.dragging) then
            self.dragging = nil
            return
        end

        if (button == "LeftButton") then
            MLH:gui()
        elseif (button == "RightButton") then
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
            MLH:resetSession()
            MLH:updateHUD()
            MLH:refreshReport()
        end
    end)

    UI:tooltip(frame, L["H_Title"], function()
        return L["H_Tooltip"](isLocked() and L["H_Locked"] or L["H_Unlocked"])
    end)

    frame.cells = cells

    return frame
end

-- The numbers themselves. One call, so the ticker and every other caller show the same
-- thing at the same moment.
function MLH:updateHUD()
    if (not hud or not hud:IsShown()) then return end

    local stats = self:getSessionStats()

    hud.cells[1]:SetText(self:formatDuration(stats.duration))
    hud.cells[2]:SetText(string.format("%.0f", stats.itemsPerHour)..L["H_ItemsPerHour"])
    hud.cells[3]:SetText(self:formatGoldCompact(stats.goldPerHour)..GOLD_ICON..L["H_GoldPerHour"])
end

function MLH:showHUD()
    if (not hud) then hud = buildHud() end

    local saved = (self.db.char.ui or {}).hud or {}

    hud:ClearAllPoints()

    if (saved.point) then
        hud:SetPoint(saved.point, UIParent, saved.relativePoint or saved.point, saved.x or 0, saved.y or 0)
    else
        -- above the centre of the screen, clear of the action bars and of the minimap
        hud:SetPoint("TOP", UIParent, "TOP", 0, -180)
    end

    hud:Show()
    hud:LayoutCells()

    self:updateHUD()

    if (not ticker) then
        ticker = C_Timer.NewTicker(1, function() MLH:updateHUD() end)
    end
end

function MLH:hideHUD()
    if (ticker) then
        ticker:Cancel()
        ticker = nil
    end

    if (hud) then hud:Hide() end
end

-- Puts the HUD in whatever state the settings ask for. Called on login and whenever one of
-- the two switches moves, so nothing else has to know how it is shown.
function MLH:applyHUD()
    if (self.db.char.config.showHUD) then
        self:showHUD()
    else
        self:hideHUD()
    end
end

function MLH:toggleHUD()
    self.db.char.config.showHUD = not self.db.char.config.showHUD

    self:applyHUD()

    return self.db.char.config.showHUD
end

function MLH:toggleHUDLock()
    self.db.char.config.hudLocked = not isLocked()

    return self.db.char.config.hudLocked
end
