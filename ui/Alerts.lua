--[[
My Loot History addon
Copyright (C) 2026 RustyDaemon (https://github.com/RustyDaemon)

See License file for details.
--]]

local MLH = LibStub("AceAddon-3.0"):GetAddon("MyLootHistory")
local L = LibStub("AceLocale-3.0"):GetLocale("MyLootHistory")
local UI = MLH.UI

local MAX_TOASTS = 3
local WIDTH = 280
local HEIGHT = 44
local GAP = 6
local HOLD = 5            -- seconds a toast stays fully visible
local FADE = 1            -- seconds it takes to fade out after that
local SOUND_COOLDOWN = 1  -- a stack of drops plays one sound, not five

local PREVIEW_ITEM_ID = 6948 -- Hearthstone: every character has it cached

local GOLD_ICON = UI.GOLD_ICON

local pool = {}
local active = {}         -- the toasts on screen, newest first
local lastSoundAt = 0

-- Retail and Forever number these classes the same; the enums are read when the client has them.
local function collectibleKind(itemID, classID, subClassID)
    local itemClass = Enum.ItemClass or {}
    local miscSubclass = Enum.ItemMiscellaneousSubclass or {}

    if (classID == (itemClass.Miscellaneous or 15)) then
        if (subClassID == (miscSubclass.Mount or 5)) then return "mount" end
        if (subClassID == (miscSubclass.CompanionPet or 2)) then return "pet" end
    end

    if (classID == (itemClass.Battlepet or 17)) then return "pet" end

    if (C_ToyBox and C_ToyBox.GetToyInfo and C_ToyBox.GetToyInfo(itemID)) then return "toy" end

    return nil
end

-- Whether a mount, pet or toy is one the player already has: a duplicate is not the moment a new one is.
-- nil when the client cannot say.
local function alreadyOwned(itemID, kind)
    if (kind == "mount" and C_MountJournal and C_MountJournal.GetMountFromItem) then
        local mountID = C_MountJournal.GetMountFromItem(itemID)

        if (mountID) then return (select(11, C_MountJournal.GetMountInfoByID(mountID))) == true end
    elseif (kind == "pet" and C_PetJournal and C_PetJournal.GetPetInfoByItemID) then
        local speciesID = select(13, C_PetJournal.GetPetInfoByItemID(itemID))

        if (speciesID) then return (C_PetJournal.GetNumCollectedInfo(speciesID) or 0) > 0 end
    elseif (kind == "toy" and PlayerHasToy) then
        return PlayerHasToy(itemID) == true
    end

    return nil
end

-- Whether a piece of gear shows an appearance the player has not collected. nil when it has none.
local function isNewAppearance(itemLink)
    if (not itemLink or not C_TransmogCollection or not C_TransmogCollection.GetItemInfo) then return nil end

    local _, sourceID = C_TransmogCollection.GetItemInfo(itemLink)

    if (not sourceID) then return nil end

    local info = C_TransmogCollection.GetAppearanceInfoBySource
        and C_TransmogCollection.GetAppearanceInfoBySource(sourceID)

    if (not info) then return nil end

    return not info.appearanceIsCollected
end

-- A word on the toast about the player's collection: "New appearance" or "Already owned", or nil.
local function collectionNote(itemID, itemLink, kind)
    if (kind == "mount" or kind == "pet" or kind == "toy") then
        return alreadyOwned(itemID, kind) and "owned" or nil
    end

    return isNewAppearance(itemLink) and "appearance" or nil
end

-- Returns { kind, value, note } when the drop deserves an alert, nil otherwise. value is in copper,
-- priced by the chosen price source, for the whole stack; note is collectionNote's.
function MLH:getDropAlert(itemID, itemLink, quality, quantity, vendorPrice, classID, subClassID)
    local alerts = self.db.char.config.alerts

    if (not alerts or not alerts.enabled) then return nil end

    local value = self:getItemPrice(itemID, vendorPrice, itemLink) * (quantity or 1)
    local kind = alerts.collectibles and collectibleKind(itemID, classID, subClassID) or nil

    if (not kind and (alerts.minQuality or 0) > 0 and (quality or 0) >= alerts.minQuality) then
        kind = "quality"
    end

    if (not kind and (alerts.minValue or 0) > 0 and value >= alerts.minValue * 10000) then
        kind = "value"
    end

    if (not kind) then return nil end

    return { kind = kind, value = value, note = collectionNote(itemID, itemLink, kind) }
end

local noteTexts = {
    appearance = function() return "|cFF1EFF00"..L["A_NewAppearance"].."|r" end,
    owned = function() return "|cFF8A8A95"..L["A_AlreadyOwned"].."|r" end,
}

local reasonKeys = {
    mount = "A_Mount",
    pet = "A_Pet",
    toy = "A_Toy",
    value = "A_Valuable",
    preview = "A_Preview",
}

-- Why the drop counts, followed by what it means for the player's collection when that is known.
function MLH:getDropAlertReason(alert, quality)
    local reason = alert.kind == "quality" and self:getQualityName(quality or 0)
        or L[reasonKeys[alert.kind] or "A_Valuable"]

    local note = alert.note and noteTexts[alert.note]

    if (note) then return reason.."  |cFF656A76·|r  "..note() end

    return reason
end

function MLH:formatDropValue(copper)
    if (not copper or copper <= 0) then return nil end
    if (copper >= 10000) then return self:formatGoldCompact(copper)..GOLD_ICON end

    return self:formatMoneyShort(copper)
end

local function layoutToasts()
    local hud = _G.MLHHudFrame
    local previous = nil

    for i = 1, #active do
        local toast = active[i]

        toast:ClearAllPoints()

        if (previous) then
            toast:SetPoint("TOP", previous, "BOTTOM", 0, -GAP)
        elseif (hud and hud:IsShown()) then
            toast:SetPoint("TOP", hud, "BOTTOM", 0, -GAP)
        else
            toast:SetPoint("TOP", UIParent, "TOP", 0, -220)
        end

        previous = toast
    end
end

local function dismiss(toast)
    toast:Hide()

    for i = #active, 1, -1 do
        if (active[i] == toast) then table.remove(active, i) end
    end

    layoutToasts()
end

local function buildToast()
    local frame = CreateFrame("Button", nil, UIParent)

    frame:SetFrameStrata("HIGH")
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetClampedToScreen(true)
    frame:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    frame:Hide()

    UI:addShadow(frame, 4, 0.35)

    local bg = frame:CreateTexture(nil, "BACKGROUND", nil, -7)
    bg:SetAllPoints()
    bg:SetColorTexture(UI:rgb("window", 0.92))

    UI:addBorder(frame, UI:rgb("border"))
    UI:attachHover(frame, "panelHover", 0.5, "BORDER")

    local stripe = frame:CreateTexture(nil, "ARTWORK")
    stripe:SetPoint("TOPLEFT")
    stripe:SetPoint("BOTTOMLEFT")
    stripe:SetWidth(2)

    local iconSize = HEIGHT - 12

    local iconBorder = frame:CreateTexture(nil, "ARTWORK", nil, 1)
    iconBorder:SetPoint("LEFT", frame, "LEFT", 9, 0)
    iconBorder:SetSize(iconSize + 2, iconSize + 2)

    local icon = frame:CreateTexture(nil, "ARTWORK", nil, 2)
    icon:SetPoint("CENTER", iconBorder, "CENTER")
    icon:SetSize(iconSize, iconSize)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local name = UI:text(frame, 13)
    name:SetPoint("TOPLEFT", iconBorder, "TOPRIGHT", 8, -2)
    name:SetPoint("RIGHT", frame, "RIGHT", -8, 0)
    name:SetJustifyH("LEFT")
    name:SetWordWrap(false)

    local detail = UI:text(frame, 11, "textDim")
    detail:SetPoint("BOTTOMLEFT", iconBorder, "BOTTOMRIGHT", 8, 2)
    detail:SetPoint("RIGHT", frame, "RIGHT", -8, 0)
    detail:SetJustifyH("LEFT")
    detail:SetWordWrap(false)

    frame:HookScript("OnEnter", function(self)
        self.hovered = true
        self:SetAlpha(1)

        if (self.itemLink) then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(self.itemLink)
            GameTooltip:AddLine(L["A_ToastHint"], UI:rgb("textFaint"))
            GameTooltip:Show()
        end
    end)

    frame:HookScript("OnLeave", function(self)
        self.hovered = false
        GameTooltip:Hide()
    end)

    frame:SetScript("OnClick", function(self)
        if (self.itemLink and (IsLeftShiftKeyDown() or IsRightShiftKeyDown())) then
            ChatEdit_TryInsertChatLink(self.itemLink)
            return
        end

        GameTooltip:Hide()
        dismiss(self)
    end)

    -- A hovered toast holds still, so it never fades out from under the cursor.
    frame:HookScript("OnUpdate", function(self, elapsed)
        if (self.hovered) then
            self.age = 0
            return
        end

        self.age = (self.age or 0) + elapsed

        if (self.age <= HOLD) then return end

        local alpha = 1 - (self.age - HOLD) / FADE

        if (alpha <= 0) then
            dismiss(self)
        else
            self:SetAlpha(alpha)
        end
    end)

    frame.SetDrop = function(self, itemLink, itemTexture, quality, quantity, reason, valueText)
        local r, g, b = C_Item.GetItemQualityColor(quality or 1)

        self.itemLink = itemLink
        self.age = 0
        self:SetAlpha(1)

        stripe:SetColorTexture(r, g, b, 1)
        iconBorder:SetColorTexture(r, g, b, 1)
        icon:SetTexture(itemTexture or 134400) -- the question mark icon

        name:SetText((itemLink or "?")..((quantity or 1) > 1 and (" x"..quantity) or ""))
        detail:SetText(valueText and (reason.."  |cFF656A76·|r  "..valueText) or reason)
    end

    return frame
end

local function acquireToast()
    local toast = nil

    for i = 1, #pool do
        if (not pool[i]:IsShown()) then toast = pool[i] break end
    end

    if (not toast and #pool < MAX_TOASTS) then
        toast = buildToast()
        pool[#pool+1] = toast
    end

    -- Every toast is busy: the oldest one makes room for the newest drop.
    if (not toast) then toast = active[#active] end

    for i = #active, 1, -1 do
        if (active[i] == toast) then table.remove(active, i) end
    end

    table.insert(active, 1, toast)

    return toast
end

local function playAlertSound()
    local now = GetTime()

    if (now - lastSoundAt < SOUND_COOLDOWN) then return end

    lastSoundAt = now

    local sound = SOUNDKIT and (SOUNDKIT.UI_EPICLOOT_TOAST or SOUNDKIT.RAID_WARNING)

    if (sound) then PlaySound(sound) end
end

function MLH:alertDrop(itemLink, itemTexture, quality, quantity, alert)
    local alerts = self.db.char.config.alerts
    local reason = self:getDropAlertReason(alert, quality)
    local valueText = self:formatDropValue(alert.value)

    local toast = acquireToast()

    toast:SetDrop(itemLink, itemTexture, quality, quantity, reason, valueText)
    toast:Show()
    layoutToasts()

    if (alerts.sound) then playAlertSound() end

    if (alerts.chat) then
        print(L["A_ChatLine"](itemLink, quantity or 1, reason, valueText))
    end
end

function MLH:previewDropAlert()
    Item:CreateFromItemID(PREVIEW_ITEM_ID):ContinueOnItemLoad(function()
        local _, link, quality, _, _, _, _, _, _, texture = C_Item.GetItemInfo(PREVIEW_ITEM_ID)

        MLH:alertDrop(link, texture, quality, 1, { kind = "preview", value = 0 })
    end)
end
