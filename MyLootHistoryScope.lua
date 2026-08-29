--[[
My Loot History addon
Copyright (C) 2026 RustyDaemon (https://github.com/RustyDaemon)

See License file for details.
--]]

-- Which characters the report is looking at.
--
-- Every history is stored per character, the way it always has been: AceDB keeps one table
-- per "Name - Realm" under the saved variable, and the addon writes to the one belonging to
-- whoever is logged in. Nothing about that changes here. What this file adds is a way to
-- *read* all of them at once, so the report can answer "what has this account looted" and
-- not only "what has this character looted".
--
-- No data is copied or moved between characters: the account-wide view walks the same tables
-- the per-character view walks, one after the other. The only thing it does write is the
-- shape upgrade a character stored by a very old version needs before it can be read at all.

local MLH = LibStub("AceAddon-3.0"):GetAddon("MyLootHistory")
local L = LibStub("AceLocale-3.0"):GetLocale("MyLootHistory")

-- AceDB strips a value that still equals its default before saving, so another character's
-- table can be missing the lists entirely. Reading them through here means no caller has to
-- know that.
local function historyFor(key, data, isCurrent)
    local name, realm = key:match("^(.-) %- (.+)$")

    -- A character who has not logged in since an old version can still be holding records in
    -- a shape no reader here understands. The logged-in one is brought up to date when the
    -- database opens; the rest are brought up to date the first time they are read.
    MLH:upgradeCharacterData(data)

    return {
        key = key,
        name = name or key,
        realm = realm,
        isCurrent = isCurrent,
        items = data.foundItems or {},
        gold = data.foundGold or {},
        currency = data.foundCurrency or {},
        sessions = data.sessions or {},
        sessionStart = data.thisSessionStart,
    }
end

function MLH:getCharacterKey()
    return (self.db.keys and self.db.keys.char) or UnitName("player") or "?"
end

function MLH:getScope()
    return self:getFilters().scope or "char"
end

-- Every history the current scope covers, the logged-in character first and the rest by
-- name, so the order a list is built in is stable between redraws.
function MLH:getHistories()
    local currentKey = self:getCharacterKey()
    local current = historyFor(currentKey, self.db.char, true)

    if (self:getScope() ~= "account") then return { current } end

    local stored = self.db.sv and self.db.sv.char

    if (not stored) then return { current } end

    local others = {}

    for key, data in pairs(stored) do
        -- the current character's table is `self.db.char` itself, with the defaults layered
        -- behind it, so it is taken from there rather than from the raw saved variable
        if (key ~= currentKey and type(data) == "table") then
            others[#others+1] = historyFor(key, data, false)
        end
    end

    table.sort(others, function(l, r) return l.key < r.key end)

    local histories = { current }

    for i = 1, #others do histories[#histories+1] = others[i] end

    return histories
end

-- The two choices the scope dropdown offers.
function MLH:getScopeList()
    return {
        { value = "char", text = L["R_ScopeCharacter"] },
        { value = "account", text = L["R_ScopeAccount"] },
    }
end

function MLH:getScopeName()
    return self:getScope() == "account" and L["R_ScopeAccount"] or L["R_ScopeCharacter"]
end

-- The characters the saved variable knows about, for the scope control's tooltip and for
-- deciding whether an account-wide view is worth offering at all.
function MLH:getCharacterCount()
    local stored = self.db.sv and self.db.sv.char

    if (not stored) then return 1 end

    local count = 0

    for _ in pairs(stored) do count = count + 1 end

    return math.max(count, 1)
end
