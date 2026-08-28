-- luacheck configuration for MyLootHistory
--
-- Run with:  luacheck .
--
-- The vendored Ace3 tree in libs/ is not ours and is excluded. Everything else
-- is checked against the WoW client's global namespace, declared below: the
-- client provides these, so reading them is fine and writing them is not.

std = "lua51"          -- the WoW client runs Lua 5.1
codes = true           -- print the warning code, so it can be looked up or ignored
max_line_length = 120

exclude_files = {
    "libs",            -- vendored Ace3 / LibStub / LibDBIcon / LibUIDropDownMenu
    "dist",            -- build output
}

-- Warnings we deliberately do not want:
ignore = {
    "212",             -- unused argument: AceGUI hands every callback (widget, event, value)
                       -- whether or not the handler needs them, so this is pure noise here.
                       -- 211 (unused local) stays on: that one does catch dead code.
    "213",             -- unused loop variable (common in `for _, v in pairs`)
}

-- The addon namespace and the libraries it embeds. Read and written by us.
globals = {
    "MyLootHistoryDB",     -- SavedVariables table, written by the client
    "StaticPopupDialogs",  -- the confirm dialogs are registered by adding to this table
}

-- WoW client API. Readable, never assigned - luacheck flags a write to any of
-- these, which is what we want.
read_globals = {
    -- Ace3 / LibStub entry point
    "LibStub",

    -- namespaced client API
    "C_Container",
    "C_CurrencyInfo",
    "C_Item",
    "C_Map",
    "C_Timer",
    "Enum",

    -- tooltips
    "GameTooltip",
    "ItemRefTooltip",
    "TooltipDataProcessor",

    -- frames and UI plumbing
    "AddonCompartmentFrame",
    "ChatEdit_TryInsertChatLink",
    "CreateFrame",
    "HideUIPanel",
    "InterfaceOptionsFrame_OpenToCategory",
    "Settings",
    "SettingsPanel",
    "StaticPopup_Show",
    "UIParent",
    "UISpecialFrames",

    -- localised button labels used by the confirm dialogs
    "NO",
    "YES",

    -- formatting and misc helpers
    "GetMoneyString",
    "GetLocale",
    "IsLeftShiftKeyDown",
    "IsRightShiftKeyDown",
    "Item",

    -- global format strings the loot parser reads out of the client
    "CURRENCY_GAINED",
    "CURRENCY_GAINED_MULTIPLE",
    "CURRENCY_GAINED_MULTIPLE_BONUS",
    "LOOT_ITEM_CREATED_SELF",
    "LOOT_ITEM_CREATED_SELF_MULTIPLE",
    "LOOT_ITEM_PUSHED_SELF",
    "LOOT_ITEM_PUSHED_SELF_MULTIPLE",
    "LOOT_ITEM_SELF",
    "LOOT_ITEM_SELF_MULTIPLE",

    -- the client exposes os.date/os.time as bare globals, and there is no os table
    "date",
    "time",

    -- Lua 5.1 globals the WoW client keeps but newer stds dropped
    "tinsert",
    "tremove",
    "wipe",
    "strsplit",
    "strjoin",
    "unpack",

    -- optional dependency, absent unless the player has it installed
    "Auctionator",
}

-- The report is one file of cooperating helpers that are forward-declared at the
-- top, so `function name()` there assigns to a local rather than creating a
-- global. Nothing extra is needed for that - it is noted here only because it is
-- the pattern a future split has to preserve in each new file.

-- Locale strings are single long sentences shown to the player; wrapping them in
-- Lua would only make them harder to read and translate.
files["locales/**/*.lua"] = {
    max_line_length = false,
}

-- The suite runs under busted, not in the client: it has the real os table, and
-- tests/support/wow.lua installs the client API into _G. The busted std supplies
-- describe / it / before_each / assert.
files["tests/**/*.lua"] = {
    std = "max+busted",
    read_globals = {
        -- installed by tests/support/wow.lua
        "LibStub", "C_CurrencyInfo", "C_Item", "C_Map", "C_Timer", "Enum",
        "GameTooltip", "GetMoneyString", "Item", "MyLootHistoryDB",
        "date", "time",
    },
}

-- The stub is the file that *builds* the fake client, so unlike the specs it
-- writes to those globals rather than only reading them.
files["tests/support/*.lua"] = {
    std = "max+busted",
    globals = { "LibStub" },
}
