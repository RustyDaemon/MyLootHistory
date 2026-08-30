--[[
Loot source attribution.

The client never says "this item came off that mob" in one call. The loot window carries the
GUID of whatever is being looted, and the name has to come from somewhere else: whatever the
player has targeted or hovered. The combat log would name every kill, but registering
COMBAT_LOG_EVENT_UNFILTERED is an action the client only allows the Blizzard UI and it blocks
the addon outright - so the name book is filled from targeting instead, and read at draw
time, which is what lets a name learned today apply to loot recorded last week.

These specs cover that seam, and the far more common case of a drop the client says nothing
useful about - which has to end up with no source rather than a wrong one.

The GUID strings below are the real shape the client uses. The npc ID is the sixth field,
which is the whole reason a tally can be kept against a mob rather than against a corpse.
--]]

local wow = require("tests.support.wow")

-- the game runs Lua 5.1, where unpack is a global; the interpreter these specs run under
-- may be 5.4, where it only exists as table.unpack
local unpack = unpack or table.unpack

-- the client's own splitter: a plain split on a single character, empty fields included
_G.strsplit = function(delimiter, text)
    local parts = {}
    local start = 1

    text = tostring(text)

    while (true) do
        local position = text:find(delimiter, start, true)

        if (not position) then
            parts[#parts+1] = text:sub(start)
            break
        end

        parts[#parts+1] = text:sub(start, position - 1)
        start = position + 1
    end

    return unpack(parts)
end

local lootSlots = {}
local units = {}

_G.GetNumLootItems = function() return #lootSlots end
_G.GetLootSourceInfo = function(slot) return lootSlots[slot] end
_G.UnitExists = function(unit) return units[unit] ~= nil end
_G.UnitGUID = function(unit) return units[unit] and units[unit].guid end
_G.UnitName = function(unit) return units[unit] and units[unit].name end

-- the player targets something, which is where a name comes from now
local function targeting(guid, name)
    units.target = { guid = guid, name = name }
end

-- The client's secret values: something it has decided an addon may not read - the GUID and
-- the name of a delve's quest percon are the ones that got here first. The real thing errors
-- the moment it is split, concatenated or printed, and so does this, so a missing guard fails
-- the spec instead of quietly storing a value nothing can ever show.
local secrets = setmetatable({}, { __mode = "k" })

local function secret()
    local function refuse()
        error("attempt to perform string conversion on a secret string value", 2)
    end

    local value = setmetatable({}, { __tostring = refuse, __concat = refuse })

    secrets[value] = true

    return value
end

_G.issecretvalue = function(value) return secrets[value] == true end

wow.load("utils/DateUtils.lua")
wow.load("MyLootHistory.lua")
wow.load("MyLootHistoryDB.lua")
wow.load("MyLootHistoryScope.lua")
wow.load("MyLootHistorySource.lua")

local MLH = wow.addon

local RAVAGER = "Creature-0-1465-2444-31-224466-0000A1B2C3"
local CHEST = "GameObject-0-1465-2444-31-311222-0000D4E5F6"

local function seed()
    MLH:initDatabase()

    MLH.db.char.config.trackLootSource = true

    lootSlots = {}
    units = {}
end

describe("learning a name", function()
    before_each(seed)

    it("remembers the name of a creature the player targets", function()
        targeting(RAVAGER, "Void Ravager")
        MLH:noteUnitName("target")

        assert.are.equal("Void Ravager", MLH:getSourceNames()[224466])
    end)

    it("ignores a unit that is not a creature", function()
        targeting("Player-1465-0A1B2C3D", "Someone")
        MLH:noteUnitName("target")

        local learned = 0

        for _ in pairs(MLH:getSourceNames()) do learned = learned + 1 end

        assert.are.equal(0, learned)
    end)

    it("copes with a unit that is not there", function()
        assert.has_no.errors(function() MLH:noteUnitName("target") end)
    end)

    it("records nothing while the setting is off", function()
        MLH.db.char.config.trackLootSource = false

        targeting(RAVAGER, "Void Ravager")
        MLH:noteUnitName("target")

        assert.is_nil(MLH:getSourceNames()[224466])
    end)

    it("leaves a unit the client keeps secret alone", function()
        targeting(secret(), secret())

        assert.has_no.errors(function() MLH:noteUnitName("target") end)

        local learned = 0

        for _ in pairs(MLH:getSourceNames()) do learned = learned + 1 end

        assert.are.equal(0, learned)
    end)

    it("does not store a secret name for a creature it can otherwise read", function()
        targeting(RAVAGER, secret())

        assert.has_no.errors(function() MLH:noteUnitName("target") end)
        assert.is_nil(MLH:getSourceNames()[224466])
    end)

    it("names loot recorded before the name was known", function()
        -- the drop is stored with an id and no name at all
        local entries = { { quantity = 1, source = { kind = "creature", id = 224466 } } }

        assert.are.equal("R_SourceCreature", tostring(MLH:aggregateSources(entries)[1].name))

        targeting(RAVAGER, "Void Ravager")
        MLH:noteUnitName("target")

        -- and the same stored drop now answers with the name, because it is resolved on read
        assert.are.equal("Void Ravager", MLH:aggregateSources(entries)[1].name)
    end)
end)

describe("the open loot window", function()
    before_each(seed)

    it("attributes a drop to the creature being looted", function()
        targeting(RAVAGER, "Void Ravager")

        lootSlots = { RAVAGER }
        MLH:LOOT_OPENED()

        local source = MLH:getCurrentSource()

        assert.are.equal("creature", source.kind)
        assert.are.equal(224466, source.id)
        assert.are.equal("Void Ravager", MLH:getSourceName(source))
    end)

    it("attributes a chest to the object it is, name or no name", function()
        lootSlots = { CHEST }
        MLH:LOOT_OPENED()

        local source = MLH:getCurrentSource()

        assert.are.equal("object", source.kind)
        -- the locale stub answers with the key itself, so the fallback is checked by name
        assert.are.equal("R_SourceObject", tostring(MLH:getSourceName(source)))
    end)

    it("records nothing for a loot slot the client keeps secret", function()
        lootSlots = { secret() }

        assert.has_no.errors(function() MLH:LOOT_OPENED() end)
        assert.is_nil(MLH:getCurrentSource())
    end)

    it("forgets the source once the window closes", function()
        lootSlots = { CHEST }
        MLH:LOOT_OPENED()
        MLH:LOOT_CLOSED()

        assert.is_nil(MLH:getCurrentSource())
    end)

    it("falls back to what the chat message said when nothing was opened", function()
        local source = MLH:getCurrentSource("crafted")

        assert.are.equal("crafted", source.kind)
        assert.are.equal("R_SourceCrafted", tostring(MLH:getSourceName(source)))
    end)

    it("records no source at all while the setting is off", function()
        MLH.db.char.config.trackLootSource = false

        lootSlots = { RAVAGER }
        MLH:LOOT_OPENED()

        assert.is_nil(MLH:getCurrentSource("crafted"))
    end)
end)

describe("MLH:aggregateSources", function()
    before_each(seed)

    it("tallies the sources of a set of entries, busiest first", function()
        MLH:rememberSourceName(224466, "Void Ravager")
        MLH:rememberSourceName(700, "Rock Elemental")

        local sources = MLH:aggregateSources({
            { quantity = 2, source = { kind = "creature", id = 224466 } },
            { quantity = 5, source = { kind = "creature", id = 700 } },
            { quantity = 1, source = { kind = "creature", id = 224466 } },
        })

        assert.are.equal(2, #sources)
        assert.are.equal("Rock Elemental", sources[1].name)
        assert.are.equal(5, sources[1].quantity)
        assert.are.equal(3, sources[2].quantity)
    end)

    it("leaves out the entries stored before any of this existed", function()
        local sources = MLH:aggregateSources({
            { quantity = 3 },
            { quantity = 1, source = { kind = "container" } },
        })

        assert.are.equal(1, #sources)
        assert.are.equal("R_SourceContainer", tostring(sources[1].name))
    end)
end)

describe("storing a source on a loot entry", function()
    before_each(seed)

    it("stamps it on the entry the record keeps", function()
        MLH:addItem(100, 3, "|Hitem:100|h", 1, 1, "Copper Ore", 1, 400,
            { kind = "creature", id = 224466 })

        local entry = MLH.db.char.foundItems[1].lootData[1]

        assert.are.equal("creature", entry.source.kind)
        assert.are.equal(224466, entry.source.id)
    end)

    it("leaves the entry alone when there is no source to stamp", function()
        MLH:addItem(100, 3, "|Hitem:100|h", 1, 1, "Copper Ore", 1, 400, nil)

        assert.is_nil(MLH.db.char.foundItems[1].lootData[1].source)
    end)
end)
