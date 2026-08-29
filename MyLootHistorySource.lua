--[[
My Loot History addon
Copyright (C) 2026 RustyDaemon (https://github.com/RustyDaemon)

See License file for details.
--]]

-- Where a drop came from.
--
-- The client never tells an addon "this item came off that mob" in one call. What it does
-- give is a loot window whose slots carry the GUID of whatever is being looted, and a combat
-- log that names things as they die. Putting those together is what turns "3x Arcane Dust,
-- Hallowfall" into "3x Arcane Dust, off Void Ravagers".
--
-- Everything here degrades rather than guesses: a source that cannot be named is stored as
-- its kind alone ("a creature", "a container"), and a drop with no loot window at all - a
-- gathering node's contents, a crafted item, something pushed into the bags by a quest - is
-- marked by the chat message form that announced it. A wrong attribution would be worse
-- than none, so nothing is attributed on a guess.

local MLH = LibStub("AceAddon-3.0"):GetAddon("MyLootHistory")
local L = LibStub("AceLocale-3.0"):GetLocale("MyLootHistory")

-- The kinds a source can have. Stored as these short strings rather than as numbers so a
-- saved variable stays readable, and so an unknown kind from a future version is harmless.
local KIND_CREATURE = "creature"
local KIND_OBJECT = "object"
local KIND_CONTAINER = "container"
local KIND_PLAYER = "player"
local KIND_CRAFTED = "crafted"
local KIND_PUSHED = "pushed"

-- "Creature-0-1234-2444-31-224466-000012ABCD" -> 224466, the npc ID, which is the same for
-- every copy of a mob and so is what a tally has to be kept against.
local function npcIdFrom(guid)
    if (not guid) then return nil end

    local kind, _, _, _, _, id = strsplit("-", guid)

    if (kind == "Creature" or kind == "Vehicle" or kind == "Pet"
        or kind == "GameObject" or kind == "Vignette") then
        return tonumber(id)
    end

    return nil
end

local function kindFrom(guid)
    if (not guid) then return nil end

    local kind = strsplit("-", guid)

    if (kind == "Creature" or kind == "Vehicle" or kind == "Pet") then return KIND_CREATURE end
    if (kind == "GameObject" or kind == "Vignette") then return KIND_OBJECT end
    if (kind == "Item") then return KIND_CONTAINER end
    if (kind == "Player") then return KIND_PLAYER end

    return nil
end

-- ── the name book ─────────────────────────────────────────────────────────────

-- npc ID -> name, shared by every character on the account: a mob's name does not depend on
-- who killed it, and one character learning it saves the rest the lookup.
--
-- Names are resolved when a row is *drawn*, not when the loot is recorded, so a name learned
-- later fills itself in backwards: target the same kind of mob once and every drop it ever
-- gave you is named, including the ones stored before it was known.
function MLH:getSourceNames()
    -- AceDB hands back the defaults for the current character, but `global` is only there
    -- once something has been written to it
    self.db.global = self.db.global or {}
    self.db.global.sourceNames = self.db.global.sourceNames or {}

    return self.db.global.sourceNames
end

function MLH:rememberSourceName(id, name)
    if (not id or not name or name == "") then return end

    self:getSourceNames()[id] = name
end

-- What a stored source should be called. A name that was learned once is used forever; a
-- source that was never named falls back to what kind of thing it was.
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

-- ── the open loot window ──────────────────────────────────────────────────────

-- What is being looted right now, set when the loot window opens and cleared when it
-- closes. A loot message arrives while the window is open, which is what lets the two be
-- tied together at all.
local openSource = nil

local function readLootWindow()
    if (not GetNumLootItems or not GetLootSourceInfo) then return nil end

    local slots = GetNumLootItems() or 0

    for slot = 1, slots do
        local guid = GetLootSourceInfo(slot)
        local kind = kindFrom(guid)

        if (kind) then
            local id = npcIdFrom(guid)

            -- what you are looting is usually still what you are targeting, which names it
            for _, unit in ipairs({ "target", "mouseover" }) do
                if (UnitGUID and UnitGUID(unit) == guid) then
                    MLH:rememberSourceName(id, UnitName(unit))
                end
            end

            return { kind = kind, id = id, guid = guid }
        end
    end

    return nil
end

-- Every unit the player looks at is a chance to learn a name. This is deliberately not the
-- combat log: registering COMBAT_LOG_EVENT_UNFILTERED is an action the client only allows
-- the Blizzard UI, and it blocks the addon outright. Targeting and mouseover cover the same
-- ground for anything you kill yourself, and a name learned once is kept for good.
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

-- The source to stamp on a loot entry being written now. `messageKind` is what the chat
-- message form said about the drop - crafted, or pushed straight into the bags - which is
-- all there is to go on when nothing was opened.
function MLH:getCurrentSource(messageKind)
    if (not self.db.char.config.trackLootSource) then return nil end

    if (openSource) then return { kind = openSource.kind, id = openSource.id } end

    if (messageKind) then return { kind = messageKind } end

    return nil
end

-- ── the events ────────────────────────────────────────────────────────────────

-- A frame of our own rather than AceEvent's shared one. Source tracking is a feature that
-- switches off, and unregistering here cannot disturb the events the rest of the addon
-- depends on.
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

-- ── reading it back ───────────────────────────────────────────────────────────

-- The sources a set of loot entries came from, busiest first - the same shape as the zone
-- tally, and read by the report the same way. Entries stored before source tracking existed
-- carry none, and are counted under "unknown" rather than being dropped from the count.
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
