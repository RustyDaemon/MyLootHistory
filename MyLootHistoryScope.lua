--[[
My Loot History addon
Copyright (C) 2026 RustyDaemon (https://github.com/RustyDaemon)

See License file for details.
--]]

local MLH = LibStub("AceAddon-3.0"):GetAddon("MyLootHistory")
local L = LibStub("AceLocale-3.0"):GetLocale("MyLootHistory")

-- AceDB omits saved values that equal defaults, so lists may be absent.
local function historyFor(key, data, isCurrent)
    local name, realm = key:match("^(.-) %- (.+)$")

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

function MLH:getHistories()
    local currentKey = self:getCharacterKey()
    local current = historyFor(currentKey, self.db.char, true)

    if (self:getScope() ~= "account") then return { current } end

    local stored = self.db.sv and self.db.sv.char

    if (not stored) then return { current } end

    local others = {}

    for key, data in pairs(stored) do
        -- Use db.char to include AceDB defaults missing from raw saved variables.
        if (key ~= currentKey and type(data) == "table") then
            others[#others+1] = historyFor(key, data, false)
        end
    end

    table.sort(others, function(l, r) return l.key < r.key end)

    local histories = { current }

    for i = 1, #others do histories[#histories+1] = others[i] end

    return histories
end

function MLH:getScopeList()
    return {
        { value = "char", text = L["R_ScopeCharacter"] },
        { value = "account", text = L["R_ScopeAccount"] },
    }
end

function MLH:getScopeName()
    return self:getScope() == "account" and L["R_ScopeAccount"] or L["R_ScopeCharacter"]
end

function MLH:getCharacterCount()
    local stored = self.db.sv and self.db.sv.char

    if (not stored) then return 1 end

    local count = 0

    for _ in pairs(stored) do count = count + 1 end

    return math.max(count, 1)
end
