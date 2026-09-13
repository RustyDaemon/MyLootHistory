local wow = {}

local frozenNow = nil

function wow.freeze(when)
    frozenNow = type(when) == "table" and os.time(when) or when
end

function wow.unfreeze()
    frozenNow = nil
end

function wow.now()
    return frozenNow or os.time()
end

_G.time = function(t)
    if (t ~= nil) then return os.time(t) end

    return wow.now()
end

_G.date = function(format, t)
    return os.date(format or "%c", t or wow.now())
end

local libraries = {}
local revisions = {}

_G.LibStub = setmetatable({}, {
    __call = function(_, name, silent)
        local lib = libraries[name]

        if (not lib and not silent) then
            error("LibStub: library not stubbed: "..tostring(name), 2)
        end

        return lib
    end,
})

function LibStub:NewLibrary(name, revision)
    revision = tonumber(revision) or 1

    if (revisions[name] and revisions[name] >= revision) then return nil end

    libraries[name] = libraries[name] or {}
    revisions[name] = revision

    return libraries[name]
end

function LibStub:GetLibrary(name, silent)
    return LibStub(name, silent)
end

function wow.provide(name, lib)
    libraries[name] = lib
    revisions[name] = math.huge   -- a real NewLibrary call must not clobber a stub

    return lib
end

local locale = setmetatable({}, {
    __index = function(_, key)
        return setmetatable({}, {
            __call = function() return key end,
            __concat = function(_, other) return key..tostring(other) end,
            __tostring = function() return key end,
        })
    end,
})

wow.provide("AceLocale-3.0", {
    GetLocale = function() return locale end,
    NewLocale = function() return locale end,
})

local function deepCopy(source)
    if (type(source) ~= "table") then return source end

    local copy = {}

    for key, value in pairs(source) do
        copy[key] = deepCopy(value)
    end

    return copy
end

wow.deepCopy = deepCopy

wow.charKey = "Tester - Testrealm"

wow.provide("AceDB-3.0", {
    New = function(_, _, defaults)
        local char = deepCopy(defaults and defaults.char or {})

        return {
            char = char,
            keys = { char = wow.charKey },
            sv = { char = { [wow.charKey] = char } },
        }
    end,
})

function wow.addCharacter(db, key, data)
    db.sv.char[key] = data

    return data
end

local addon = {}

wow.provide("AceAddon-3.0", {
    NewAddon = function() return addon end,
    GetAddon = function() return addon end,
})

wow.addon = addon

function addon:clearPriceCache() end

_G.print = _G.print

_G.C_Map = {
    GetBestMapForUnit = function() return 1 end,
    GetMapInfo = function(id) return { name = "Zone "..tostring(id) } end,
}

_G.C_CurrencyInfo = {
    GetCurrencyInfo = function(id)
        return { name = "Currency "..tostring(id), iconFileID = id, quality = 1 }
    end,
    GetCurrencyLink = function(id) return "|Hcurrency:"..tostring(id).."|h" end,
}

_G.C_Item = {
    GetItemInfo = function() return nil end,             -- "not cached", the honest default
    GetItemInfoInstant = function() return nil end,
    GetItemQualityColor = function() return 1, 1, 1, "ffffffff" end,
}

wow.tickers = {}

function wow.tick()
    for _, ticker in ipairs(wow.tickers) do
        if (not ticker.cancelled) then ticker.callback() end
    end
end

_G.C_Timer = {
    NewTimer = function() return { Cancel = function() end } end,
    NewTicker = function(_, callback)
        local ticker = { callback = callback, Cancel = function(self) self.cancelled = true end }
        wow.tickers[#wow.tickers+1] = ticker
        return ticker
    end,
}

_G.GetMoneyString = function(copper) return tostring(copper or 0).."c" end

_G.BreakUpLargeNumbers = function(value) return tostring(value or 0) end

_G.Enum = {
    ItemClass = { Questitem = 12, Consumable = 0 },
    ItemQuality = { Poor = 0, Legendary = 5 },
    TooltipDataType = { Item = 0 },
}

function wow.load(path)
    local root = os.getenv("MLH_ROOT") or "."
    local chunk, err = loadfile(root.."/"..path)

    if (not chunk) then error("could not load "..path..": "..tostring(err)) end

    return chunk(path, addon)
end

return wow
