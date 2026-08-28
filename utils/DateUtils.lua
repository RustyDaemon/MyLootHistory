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

function lib:dateIsToday(source, resetToMidnight)
    local today = getDate(0, resetToMidnight)

    return date("*t", source).yday == today.yday
end

function lib:dateIsYesterday(source, resetToMidnight)
  local yesterday = getDate(-1, resetToMidnight)

  return date("*t", source).yday == yesterday.yday
end

function lib:dateIsInCurrentMonth(source, resetToMidnight)
    local today = getDate(0, resetToMidnight)

    return date("*t", source).month == today.month
end

function lib:dateInRangeTillToday(source, fromDate)
  return (source >= time(fromDate) and date("*t", source).yday <= getDate(0, false).yday)
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