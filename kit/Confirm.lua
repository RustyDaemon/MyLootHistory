--[[
My Loot History addon
Copyright (C) 2026 RustyDaemon (https://github.com/RustyDaemon)

See License file for details.
--]]

-- The yes/no dialog asked before anything that cannot be undone.

local MLH = LibStub("AceAddon-3.0"):GetAddon("MyLootHistory")
local UI = MLH.UI

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

    UI:addBorder(box, UI:rgb("borderLight"))

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
