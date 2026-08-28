--[[
Just enough of the WoW client to load the addon's pure-logic modules outside the
game. Only what the modules under test actually reach for - this is not an
emulator, and it should stay small enough to read in one sitting.

Two things matter for correctness of the tests:

  * `date` and `time` are globals in WoW (there is no `os` table), and they can
    be frozen here, so every date-range assertion is against a fixed clock
    instead of whatever day the suite happens to run on.
  * `LibStub` is real enough to let the modules register and find each other.
--]]

local wow = {}

-- ── clock ────────────────────────────────────────────────────────────────────

local frozenNow = nil

-- Freeze the clock. Accepts an epoch number, or a table as os.time() takes one.
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

-- ── LibStub ──────────────────────────────────────────────────────────────────

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

-- Register a stub library by hand.
function wow.provide(name, lib)
    libraries[name] = lib
    revisions[name] = math.huge   -- a real NewLibrary call must not clobber a stub

    return lib
end

-- ── Ace3 stubs ───────────────────────────────────────────────────────────────

-- Locale table that answers with the key itself, or a function returning it, so
-- a module can do L["X"] or L["X"](a, b) without the test caring which.
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

-- AceDB, reduced to the part the addon uses: a `char` table seeded from defaults.
-- The real library layers defaults behind a metatable; a copy is equivalent for
-- everything the tests do and far easier to reason about.
wow.provide("AceDB-3.0", {
    New = function(_, _, defaults)
        return { char = deepCopy(defaults and defaults.char or {}) }
    end,
})

-- The addon object. Modules after the first do
-- LibStub("AceAddon-3.0"):GetAddon("MyLootHistory"), so both calls hand back the
-- same table the test can then poke at.
local addon = {}

wow.provide("AceAddon-3.0", {
    NewAddon = function() return addon end,
    GetAddon = function() return addon end,
})

wow.addon = addon

-- Called by MLH:resetData; the options panel does not exist here.
function addon:updateStatisticsTextData() end

-- ── client API ───────────────────────────────────────────────────────────────

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

_G.C_Timer = {
    NewTimer = function() return { Cancel = function() end } end,
    NewTicker = function() return { Cancel = function() end } end,
}

_G.GetMoneyString = function(copper) return tostring(copper or 0).."c" end

_G.Enum = {
    ItemClass = { Questitem = 12, Consumable = 0 },
    ItemQuality = { Poor = 0, Legendary = 5 },
    TooltipDataType = { Item = 0 },
}

-- Loads one of the addon's files, relative to the repo root.
function wow.load(path)
    local root = os.getenv("MLH_ROOT") or "."
    local chunk, err = loadfile(root.."/"..path)

    if (not chunk) then error("could not load "..path..": "..tostring(err)) end

    return chunk(path, addon)
end

return wow
