--[[
My Loot History addon
Copyright (C) 2026 RustyDaemon (https://github.com/RustyDaemon)

See License file for details.
--]]

-- A stand-in for busted, for machines where it cannot be installed - the luarocks that ships
-- with Lua for Windows is too old to parse busted's rockspec. It implements the part of the
-- API the specs in tests/ actually use, and nothing else:
--
--     lua tools/run_tests.lua              every tests/*_spec.lua
--     lua tools/run_tests.lua filters      only the specs whose name contains "filters"
--
-- `busted` remains the tool of record: it runs the same files unchanged, and CI should use
-- it. This is here so that "nothing verifies the addon" is never true again.

package.path = "./?.lua;./?/init.lua;"..package.path

local passed, failed, failures = 0, 0, {}
local stack = {}
-- level 1 is the file itself: a spec may call before_each outside any describe
local befores, afters = { {} }, { {} }

-- ── the assertion table ───────────────────────────────────────────────────────

local function describeValue(value)
    if (type(value) == "string") then return string.format("%q", value) end

    return tostring(value)
end

local function fail(message)
    error(message, 3)
end

-- Deep equality for assert.are.same. Tables compare by content, everything else by ==.
local function same(l, r)
    if (l == r) then return true end
    if (type(l) ~= "table" or type(r) ~= "table") then return false end

    for key, value in pairs(l) do
        if (not same(value, r[key])) then return false end
    end

    for key in pairs(r) do
        if (l[key] == nil) then return false end
    end

    return true
end

local assertions = {}

function assertions.equal(expected, actual, message)
    if (expected ~= actual) then
        fail((message and (message.."\n") or "").."expected "..describeValue(expected)
            .." but got "..describeValue(actual))
    end
end

function assertions.not_equal(expected, actual, message)
    if (expected == actual) then
        fail((message and (message.."\n") or "").."expected anything but "..describeValue(expected))
    end
end

function assertions.same(expected, actual, message)
    if (not same(expected, actual)) then
        fail((message and (message.."\n") or "").."tables differ")
    end
end

function assertions.is_true(value, message)
    if (value ~= true) then
        fail((message and (message.."\n") or "").."expected true, got "..describeValue(value))
    end
end

function assertions.is_false(value, message)
    if (value ~= false) then
        fail((message and (message.."\n") or "").."expected false, got "..describeValue(value))
    end
end

function assertions.is_falsy(value, message)
    if (value) then
        fail((message and (message.."\n") or "").."expected a falsy value, got "..describeValue(value))
    end
end

function assertions.is_truthy(value, message)
    if (not value) then
        fail((message and (message.."\n") or "").."expected a truthy value, got nil/false")
    end
end

function assertions.is_nil(value, message)
    if (value ~= nil) then
        fail((message and (message.."\n") or "").."expected nil, got "..describeValue(value))
    end
end

function assertions.is_not_nil(value, message)
    if (value == nil) then
        fail((message and (message.."\n") or "").."expected a value, got nil")
    end
end

function assertions.has_no_errors(fn, message)
    local ok, err = pcall(fn)

    if (not ok) then
        fail((message and (message.."\n") or "").."expected no error, got: "..tostring(err))
    end
end

function assertions.has_error(fn, message)
    if (pcall(fn)) then
        fail((message and (message.."\n") or "").."expected an error, none was raised")
    end
end

-- busted spells the same assertion several ways - assert.are.equal, assert.is_not.equal,
-- assert.are_not.equal - so each spelling is a small table pointing at the same functions.
local function namespace(map)
    return setmetatable({}, {
        __index = function(_, key)
            local fn = map[key]

            if (not fn) then
                error("this runner does not implement assert."..tostring(key)
                    .." - add it to tools/run_tests.lua or run the suite with busted", 2)
            end

            return fn
        end,
    })
end

_G.assert = setmetatable({
    are = namespace({ equal = assertions.equal, same = assertions.same,
                      equals = assertions.equal }),
    are_not = namespace({ equal = assertions.not_equal, same = function(e, a, m)
        if (same(e, a)) then fail((m and (m.."\n") or "").."expected the tables to differ") end
    end }),
    is_not = namespace({ equal = assertions.not_equal, nil_ = assertions.is_not_nil }),
    has_no = namespace({ errors = assertions.has_no_errors, error = assertions.has_no_errors }),
    has = namespace({ errors = assertions.has_error, error = assertions.has_error }),
    is_true = assertions.is_true,
    is_false = assertions.is_false,
    is_falsy = assertions.is_falsy,
    is_truthy = assertions.is_truthy,
    is_nil = assertions.is_nil,
    is_not_nil = assertions.is_not_nil,
    equal = assertions.equal,
    same = assertions.same,
    truthy = assertions.is_truthy,
    falsy = assertions.is_falsy,
}, {
    -- plain assert(value, message) still has to work: the specs and the addon both use it
    __call = function(_, value, message)
        if (not value) then error(message or "assertion failed!", 2) end

        return value
    end,
})

-- ── describe / it ─────────────────────────────────────────────────────────────

local function currentName(name)
    local parts = {}

    for i = 1, #stack do parts[#parts+1] = stack[i] end

    parts[#parts+1] = name

    return table.concat(parts, " › ")
end

function _G.describe(name, fn)
    stack[#stack+1] = name
    befores[#befores+1] = {}
    afters[#afters+1] = {}

    local ok, err = pcall(fn)

    if (not ok) then
        failed = failed + 1
        failures[#failures+1] = { name = currentName("<describe body>"), message = err }
    end

    stack[#stack] = nil
    befores[#befores] = nil
    afters[#afters] = nil
end

function _G.before_each(fn)
    local level = befores[#befores]

    level[#level+1] = fn
end

function _G.after_each(fn)
    local level = afters[#afters]

    level[#level+1] = fn
end

-- busted runs every enclosing before_each outermost-first, and the after_each hooks in the
-- reverse order; anything else and a nested spec sees its parent's setup half-applied.
local function runHooks(levels, reverse)
    for i = 1, #levels do
        local level = levels[reverse and (#levels - i + 1) or i]

        for j = 1, #level do level[j]() end
    end
end

function _G.it(name, fn)
    local fullName = currentName(name)

    local ok, err = pcall(function()
        runHooks(befores, false)
        fn()
        runHooks(afters, true)
    end)

    if (ok) then
        passed = passed + 1
    else
        failed = failed + 1
        failures[#failures+1] = { name = fullName, message = tostring(err) }
    end
end

function _G.pending(name)
    print("  pending: "..currentName(name))
end

-- ── the run ───────────────────────────────────────────────────────────────────

local filter = ...

local function specFiles()
    local files = {}
    local listing = io.popen('dir /b "tests\\*_spec.lua" 2>nul')

    if (listing) then
        for line in listing:lines() do files[#files+1] = "tests/"..line end
        listing:close()
    end

    -- not Windows, or dir found nothing: fall back to ls
    if (#files == 0) then
        listing = io.popen("ls tests/*_spec.lua 2>/dev/null")

        if (listing) then
            for line in listing:lines() do files[#files+1] = line end
            listing:close()
        end
    end

    table.sort(files)

    return files
end

local files = specFiles()

if (#files == 0) then
    print("no spec files found - run this from the repo root")
    os.exit(1)
end

for i = 1, #files do
    local file = files[i]

    if (not filter or file:find(filter, 1, true)) then
        print("── "..file)

        -- each file starts with a clean assertion stack; a load error is a failure, not a crash
        befores, afters = { {} }, { {} }

        local chunk, err = loadfile(file)

        if (not chunk) then
            failed = failed + 1
            failures[#failures+1] = { name = file, message = err }
        else
            local ok, runErr = pcall(chunk)

            if (not ok) then
                failed = failed + 1
                failures[#failures+1] = { name = file.." <file body>", message = tostring(runErr) }
            end
        end
    end
end

print("")

for i = 1, #failures do
    print("FAIL  "..failures[i].name)
    print("      "..tostring(failures[i].message):gsub("\n", "\n      "))
    print("")
end

print(string.format("%d passed, %d failed", passed, failed))

os.exit(failed == 0 and 0 or 1)
