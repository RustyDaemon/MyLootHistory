--[[
My Loot History addon
Copyright (C) 2026 RustyDaemon (https://github.com/RustyDaemon)

See License file for details.
--]]

local lib = LibStub:NewLibrary("DateUtils-1.0", 1)

if (not lib) then return end

local function getDate(addDays, resetToMidnight)
    local curDate = date('*t')
    curDate.day = curDate.day + addDays
    curDate.isdst = nil

    if (resetToMidnight) then
        curDate.hour = 0
        curDate.min = 0
        curDate.sec = 0
    end

    local newDate = date("*t", time(curDate))

    return newDate
end

function lib:getDate(addDays, resetToMidnight)
    return getDate(addDays, resetToMidnight)
end

-- Day-of-year repeats every year, so it only identifies a day together with the
-- year. Comparing yday on its own made a find from exactly one year ago read as
-- today - which no one notices until they have a year of history.
local function isSameDay(source, target)
    local sourceDate = date("*t", source)

    return sourceDate.yday == target.yday and sourceDate.year == target.year
end

function lib:dateIsToday(source, resetToMidnight)
    return isSameDay(source, getDate(0, resetToMidnight))
end

function lib:dateIsYesterday(source, resetToMidnight)
    return isSameDay(source, getDate(-1, resetToMidnight))
end

function lib:dateIsInCurrentMonth(source, resetToMidnight)
    local today = getDate(0, resetToMidnight)
    local sourceDate = date("*t", source)

    -- the year again: without it, June 2025 is "this month" in June 2026
    return sourceDate.month == today.month and sourceDate.year == today.year
end

-- Everything from `fromDate` up to the end of today. The upper bound is the
-- timestamp of tomorrow's midnight rather than a day-of-year comparison: across
-- New Year, last December's yday is larger than January's, so a range that spans
-- the turn used to exclude everything before it.
function lib:dateInRangeTillToday(source, fromDate)
    return source >= time(fromDate) and source < time(getDate(1, true))
end

function lib:getToday()
  return getDate(0)
end

function lib:getLastWed(todayWday)
  local wday = todayWday or lib:getToday().wday
  local lastWed = (wday > 4) and (wday - 4) or (wday + 3)
  local lastWedDate = getDate(-lastWed, true)

  return lastWedDate
end

function lib:isWed(wday)
  return wday == 4
end