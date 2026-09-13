--[[
My Loot History addon
Copyright (C) 2026 RustyDaemon (https://github.com/RustyDaemon)

See License file for details.
--]]

local MLH = LibStub("AceAddon-3.0"):GetAddon("MyLootHistory")
local L = LibStub("AceLocale-3.0"):GetLocale("MyLootHistory")

local KIND_CREATURE = "creature"
local KIND_OBJECT = "object"
local KIND_CONTAINER = "container"
local KIND_PLAYER = "player"
local KIND_CRAFTED = "crafted"
local KIND_PUSHED = "pushed"

-- Reject secret client values before comparing, formatting, or saving them.
local issecret = _G.issecretvalue

local function readable(value)
    if (value == nil) then return nil end
    if (issecret and issecret(value)) then return nil end

    return value
end

local function npcIdFrom(guid)
    guid = readable(guid)

    if (not guid) then return nil end

    local kind, _, _, _, _, id = strsplit("-", guid)

    if (kind == "Creature" or kind == "Vehicle" or kind == "Pet"
        or kind == "GameObject" or kind == "Vignette") then
        return tonumber(id)
    end

    return nil
end

local function kindFrom(guid)
    guid = readable(guid)

    if (not guid) then return nil end

    local kind = strsplit("-", guid)

    if (kind == "Creature" or kind == "Vehicle" or kind == "Pet") then return KIND_CREATURE end
    if (kind == "GameObject" or kind == "Vignette") then return KIND_OBJECT end
    if (kind == "Item") then return KIND_CONTAINER end
    if (kind == "Player") then return KIND_PLAYER end

    return nil
end

function MLH:getSourceNames()
    self.db.global = self.db.global or {}
    self.db.global.sourceNames = self.db.global.sourceNames or {}

    return self.db.global.sourceNames
end

function MLH:rememberSourceName(id, name)
    name = readable(name)

    if (not id or not name or name == "") then return end

    self:getSourceNames()[id] = name
end

function MLH:getSourceName(source)
    if (not source or not source.kind) then return nil end

    if (source.id) then
        local name = self:getSourceNames()[source.id]

        if (name) then return name end
    end

    local fallbacks = {
        [KIND_CREATURE] = L["R_SourceCreature"],
        [KIND_OBJECT] = L["R_SourceObject"],
        [KIND_CONTAINER] = L["R_SourceContainer"],
        [KIND_PLAYER] = L["R_SourcePlayer"],
        [KIND_CRAFTED] = L["R_SourceCrafted"],
        [KIND_PUSHED] = L["R_SourcePushed"],
    }

    return fallbacks[source.kind] or nil
end

local openSource = nil

local function readLootWindow()
    if (not GetNumLootItems or not GetLootSourceInfo) then return nil end

    local slots = GetNumLootItems() or 0

    for slot = 1, slots do
        local guid = readable(GetLootSourceInfo(slot))
        local kind = kindFrom(guid)

        if (kind) then
            local id = npcIdFrom(guid)

            for _, unit in ipairs({ "target", "mouseover" }) do
                if (UnitGUID and readable(UnitGUID(unit)) == guid) then
                    MLH:rememberSourceName(id, UnitName(unit))
                end
            end

            return { kind = kind, id = id, guid = guid }
        end
    end

    return nil
end

-- COMBAT_LOG_EVENT_UNFILTERED is restricted; learn names from targets and mouseover instead.
function MLH:noteUnitName(unit)
    if (not self.db or not self.db.char.config.trackLootSource) then return end
    if (not UnitGUID or not UnitExists or not UnitExists(unit)) then return end

    local id = npcIdFrom(UnitGUID(unit))

    if (id) then self:rememberSourceName(id, UnitName(unit)) end
end

function MLH:LOOT_OPENED()
    if (not self.db.char.config.trackLootSource) then return end

    openSource = readLootWindow()
end

function MLH:LOOT_CLOSED()
    openSource = nil
end

function MLH:getCurrentSource(messageKind)
    if (not self.db.char.config.trackLootSource) then return nil end

    if (openSource) then return { kind = openSource.kind, id = openSource.id } end

    if (messageKind) then return { kind = messageKind } end

    return nil
end

local events = CreateFrame and CreateFrame("Frame")

if (events) then
    events:SetScript("OnEvent", function(_, event)
        if (event == "LOOT_OPENED") then
            MLH:LOOT_OPENED()
        elseif (event == "LOOT_CLOSED") then
            MLH:LOOT_CLOSED()
        elseif (event == "PLAYER_TARGET_CHANGED") then
            MLH:noteUnitName("target")
        elseif (event == "UPDATE_MOUSEOVER_UNIT") then
            MLH:noteUnitName("mouseover")
        end
    end)
end

function MLH:applySourceTracking()
    if (not events) then return end

    if (self.db.char.config.trackLootSource) then
        events:RegisterEvent("LOOT_OPENED")
        events:RegisterEvent("LOOT_CLOSED")
        events:RegisterEvent("PLAYER_TARGET_CHANGED")
        events:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
    else
        events:UnregisterAllEvents()
    end
end

function MLH:aggregateSources(entries)
    local counts, sources = {}, {}

    for i = 1, #entries do
        local entry = entries[i]
        local name = self:getSourceName(entry.source)

        if (name) then
            counts[name] = (counts[name] or 0) + (tonumber(entry.quantity) or 1)
        end
    end

    for name, quantity in pairs(counts) do
        sources[#sources+1] = { name = name, quantity = quantity }
    end

    table.sort(sources, function(l, r)
        if (l.quantity == r.quantity) then return l.name < r.name end
        return l.quantity > r.quantity
    end)

    return sources
end
