--[[
DateUtils drives every date range in the report: pick the wrong day and the
player sees the wrong loot, with nothing to hint that anything is off. The clock
is frozen for each case so these assertions mean the same thing on every day of
the year - which is the whole reason this file exists.
--]]

local wow = require("tests.support.wow")

wow.load("utils/DateUtils.lua")

local DU = LibStub("DateUtils-1.0")

-- Wednesday 17 June 2026, 14:30:00 local time. Mid-week, mid-month, mid-year:
-- far from every boundary, so a failure here is about the logic and not the date.
local WEDNESDAY = { year = 2026, month = 6, day = 17, hour = 14, min = 30, sec = 0 }

local DAY = 86400

local function at(overrides)
    local when = {}

    for key, value in pairs(WEDNESDAY) do when[key] = value end
    for key, value in pairs(overrides or {}) do when[key] = value end

    return os.time(when)
end

describe("DateUtils:getDate", function()
    before_each(function() wow.freeze(WEDNESDAY) end)
    after_each(function() wow.unfreeze() end)

    it("returns today when asked for zero days", function()
        local result = DU:getDate(0)

        assert.are.equal(2026, result.year)
        assert.are.equal(6, result.month)
        assert.are.equal(17, result.day)
    end)

    it("resets the time to midnight when asked to", function()
        local result = DU:getDate(0, true)

        assert.are.equal(0, result.hour)
        assert.are.equal(0, result.min)
        assert.are.equal(0, result.sec)
    end)

    it("keeps the current time when not asked to reset it", function()
        local result = DU:getDate(0, false)

        assert.are.equal(14, result.hour)
        assert.are.equal(30, result.min)
    end)

    it("counts backwards across a month boundary", function()
        -- 17 June minus 20 days is 28 May: the day field goes negative and has to
        -- be normalised, which is the only reason this function goes through time()
        local result = DU:getDate(-20, true)

        assert.are.equal(5, result.month)
        assert.are.equal(28, result.day)
    end)

    it("counts backwards across a year boundary", function()
        wow.freeze({ year = 2026, month = 1, day = 3, hour = 12 })

        local result = DU:getDate(-5, true)

        assert.are.equal(2025, result.year)
        assert.are.equal(12, result.month)
        assert.are.equal(29, result.day)
    end)
end)

describe("DateUtils:dateIsToday", function()
    before_each(function() wow.freeze(WEDNESDAY) end)
    after_each(function() wow.unfreeze() end)

    it("is true for a moment earlier today", function()
        assert.is_true(DU:dateIsToday(at({ hour = 9 }), true))
    end)

    it("is true for midnight today", function()
        assert.is_true(DU:dateIsToday(at({ hour = 0, min = 0, sec = 0 }), true))
    end)

    it("is false for yesterday", function()
        assert.is_falsy(DU:dateIsToday(at() - DAY, true))
    end)

    it("is false for tomorrow", function()
        assert.is_falsy(DU:dateIsToday(at() + DAY, true))
    end)

    it("is false for the same day a year ago", function()
        -- yday repeats every year, so this used to read as today for any character
        -- with more than a year of history - which retentionDays = 0 allows
        assert.is_falsy(DU:dateIsToday(at({ year = 2025 }), true))
    end)

    it("is false for the same day a year ahead", function()
        assert.is_falsy(DU:dateIsToday(at({ year = 2027 }), true))
    end)
end)

describe("DateUtils:dateIsYesterday", function()
    before_each(function() wow.freeze(WEDNESDAY) end)
    after_each(function() wow.unfreeze() end)

    it("is true for yesterday", function()
        assert.is_true(DU:dateIsYesterday(at() - DAY, true))
    end)

    it("is false for today", function()
        assert.is_falsy(DU:dateIsYesterday(at(), true))
    end)

    it("is false for two days ago", function()
        assert.is_falsy(DU:dateIsYesterday(at() - 2 * DAY, true))
    end)

    it("handles yesterday being in the previous month", function()
        wow.freeze({ year = 2026, month = 7, day = 1, hour = 10 })

        assert.is_true(DU:dateIsYesterday(os.time({ year = 2026, month = 6, day = 30, hour = 10 }), true))
    end)

    it("handles yesterday being in the previous year", function()
        wow.freeze({ year = 2026, month = 1, day = 1, hour = 10 })

        assert.is_true(DU:dateIsYesterday(os.time({ year = 2025, month = 12, day = 31, hour = 10 }), true))
    end)

    it("is false for the same day of the year, a year ago", function()
        -- 16 June 2025 and 16 June 2026 share a yday, so this read as yesterday
        assert.is_falsy(DU:dateIsYesterday(at({ year = 2025, day = 16 }), true))
    end)
end)

describe("DateUtils:dateIsInCurrentMonth", function()
    before_each(function() wow.freeze(WEDNESDAY) end)
    after_each(function() wow.unfreeze() end)

    it("is true for another day this month", function()
        assert.is_true(DU:dateIsInCurrentMonth(at({ day = 2 }), true))
    end)

    it("is false for last month", function()
        assert.is_falsy(DU:dateIsInCurrentMonth(at({ month = 5 }), true))
    end)

    it("is false for the same month a year ago", function()
        -- month was compared without the year, so June 2025 was "this month" in
        -- June 2026. Same root cause as the dateIsToday case above.
        assert.is_falsy(DU:dateIsInCurrentMonth(at({ year = 2025 }), true))
    end)

    it("is true for the first and last moment of this month", function()
        assert.is_true(DU:dateIsInCurrentMonth(at({ day = 1, hour = 0, min = 0, sec = 0 }), true))
        assert.is_true(DU:dateIsInCurrentMonth(at({ day = 30, hour = 23, min = 59, sec = 59 }), true))
    end)
end)

describe("DateUtils:isWed", function()
    after_each(function() wow.unfreeze() end)

    it("is true only for Wednesday", function()
        -- Lua numbers weekdays from Sunday = 1, so Wednesday is 4
        assert.is_true(DU:isWed(4))

        for wday = 1, 7 do
            if (wday ~= 4) then assert.is_falsy(DU:isWed(wday)) end
        end
    end)

    it("agrees with the frozen clock on a known Wednesday", function()
        wow.freeze(WEDNESDAY)

        assert.is_true(DU:isWed(DU:getToday().wday))
    end)
end)

describe("DateUtils:getLastWed", function()
    after_each(function() wow.unfreeze() end)

    it("lands on a Wednesday whatever day it is asked about", function()
        -- Sunday 14 June 2026 through Saturday 20 June 2026
        for offset = 0, 6 do
            wow.freeze({ year = 2026, month = 6, day = 14 + offset, hour = 12 })

            local lastWed = DU:getLastWed(DU:getToday().wday)

            assert.are.equal(4, lastWed.wday)
        end
    end)

    it("returns midnight, not the current time", function()
        wow.freeze(WEDNESDAY)

        local lastWed = DU:getLastWed(DU:getToday().wday)

        assert.are.equal(0, lastWed.hour)
        assert.are.equal(0, lastWed.min)
    end)

    it("returns a full week back when today is Wednesday", function()
        wow.freeze(WEDNESDAY)

        local lastWed = DU:getLastWed(4)

        -- 17 June is a Wednesday, so the previous reset was 10 June
        assert.are.equal(10, lastWed.day)
        assert.are.equal(6, lastWed.month)
    end)

    it("returns yesterday when today is Thursday", function()
        wow.freeze({ year = 2026, month = 6, day = 18, hour = 12 })

        assert.are.equal(17, DU:getLastWed(DU:getToday().wday).day)
    end)

    it("crosses a month boundary correctly", function()
        -- Tuesday 7 July 2026: the previous Wednesday is 1 July
        wow.freeze({ year = 2026, month = 7, day = 7, hour = 12 })

        local lastWed = DU:getLastWed(DU:getToday().wday)

        assert.are.equal(7, lastWed.month)
        assert.are.equal(1, lastWed.day)
    end)
end)

describe("DateUtils:dateInRangeTillToday", function()
    before_each(function() wow.freeze(WEDNESDAY) end)
    after_each(function() wow.unfreeze() end)

    it("includes a timestamp inside the range", function()
        assert.is_true(DU:dateInRangeTillToday(at() - DAY, DU:getDate(-3, true)))
    end)

    it("includes a timestamp from today", function()
        assert.is_true(DU:dateInRangeTillToday(at(), DU:getDate(-3, true)))
    end)

    it("excludes a timestamp before the range starts", function()
        assert.is_falsy(DU:dateInRangeTillToday(at() - 10 * DAY, DU:getDate(-3, true)))
    end)

    it("includes last year's loot when the range spans New Year", function()
        -- The upper bound used to be `yday <= today.yday`, comparing day-of-year
        -- without the year. In early January the previous Wednesday is still in
        -- December, whose yday is ~360 - far greater than today's - so everything
        -- from last year was excluded and the reset range looked nearly empty.
        wow.freeze({ year = 2026, month = 1, day = 2, hour = 12 })

        local from = DU:getLastWed(DU:getToday().wday)

        -- the sample is taken from inside the range rather than guessed at, so the
        -- test cannot fail for the uninteresting reason of falling before its start
        assert.are.equal(2025, from.year)

        local lastYear = os.time(from) + 12 * 3600

        assert.is_true(DU:dateInRangeTillToday(lastYear, from))
    end)

    it("excludes a timestamp from the future", function()
        assert.is_falsy(DU:dateInRangeTillToday(at() + DAY, DU:getDate(-3, true)))
    end)

    it("includes the last second of today", function()
        local endOfToday = at({ hour = 23, min = 59, sec = 59 })

        assert.is_true(DU:dateInRangeTillToday(endOfToday, DU:getDate(-3, true)))
    end)

    it("excludes the same day a year earlier", function()
        -- inside the yday window the old comparison allowed, but a year out
        assert.is_falsy(DU:dateInRangeTillToday(at({ year = 2025 }), DU:getDate(-3, true)))
    end)
end)
