-- Grey Gold: history storage and the queries behind the stats window.
-- No frames here. Scope is "ALL" (every character) or a "Name-Realm" key.

local ADDON, ns = ...

local DAY = 86400
local EMPTY = {}
local LOG_MAX = 5000   -- sales-log rows kept per character (daily and monthly totals are kept forever)
local LOG_TRIM = 100   -- dropped at once when the log is full
local cache = {}  -- merged "ALL" days; wiped whenever history changes

-- zones = where it was sold; farm = where it was looted (2.1.0+, loot only).
local function NewDay()
    return { c = 0, n = 0, s = 0, v = 0, items = {}, zones = {}, farm = {} }
end

-- Sources that earn farm-zone credit: things you looted yourself.
-- Mail, trade, bank, "other" and unknown origin still count as sales, just not for a farm zone.
local FARM_KINDS = { mob = true, object = true, fish = true, item = true }
ns.FARM_KINDS = FARM_KINDS

----------------------------------------------------------------------------
-- Dates: keys are local-time "YYYY-MM-DD", weeks start on Monday.
-- Arithmetic is done at noon so DST changes can never skip or repeat a day.
----------------------------------------------------------------------------
local function KeyToTime(key)
    local y, m, d = key:match("^(%d+)-(%d+)-(%d+)$")
    return time({ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 12 })
end

local function DayKey(t) return date("%Y-%m-%d", t) end
local function AddDays(key, n) return DayKey(KeyToTime(key) + n * DAY) end

local function WeekStart(key)
    local t = KeyToTime(key)
    return DayKey(t - ((date("*t", t).wday + 5) % 7) * DAY)  -- wday: 1 = Sunday
end

local function DaysBetween(a, b)
    return floor((KeyToTime(b) - KeyToTime(a)) / DAY + 0.5)
end

-- Months and years: keyed by their first day ("2026-11-01", "2026-01-01").
local function MonthStart(key) return key:sub(1, 7) .. "-01" end
local function MonthEnd(key)
    local y, m = tonumber(key:sub(1, 4)), tonumber(key:sub(6, 7))
    if m == 12 then y, m = y + 1, 1 else m = m + 1 end
    return AddDays(format("%04d-%02d-01", y, m), -1)
end
local function AddMonths(key, n)
    local total = tonumber(key:sub(1, 4)) * 12 + tonumber(key:sub(6, 7)) - 1 + n
    return format("%04d-%02d-01", floor(total / 12), total % 12 + 1)
end
local function YearStart(key) return key:sub(1, 4) .. "-01-01" end
local function YearEnd(key) return key:sub(1, 4) .. "-12-31" end

-- First and last day of the day/week/month/year that contains key.
local function PeriodBounds(kind, key)
    if kind == "week" then local s = WeekStart(key); return s, AddDays(s, 6) end
    if kind == "month" then return MonthStart(key), MonthEnd(key) end
    if kind == "year" then return YearStart(key), YearEnd(key) end
    return key, key
end

ns.AddDays, ns.WeekStart, ns.PeriodBounds = AddDays, WeekStart, PeriodBounds

function ns.FormatMonth(key) return date("%B %Y", KeyToTime(key)) end

-- Title for a period: "Sat 14 Nov 2026", "Week of 9 Nov - 15 Nov", "November 2026", "2026".
function ns.FormatPeriod(kind, key)
    if kind == "week" then return ns.FormatWeek(key) .. " - " .. ns.FormatShort(AddDays(key, 6)) end
    if kind == "month" then return ns.FormatMonth(key) end
    if kind == "year" then return key:sub(1, 4) end
    return ns.FormatDay(key, true)
end

function ns.Today() return DayKey(time()) end

function ns.FormatDay(key, withYear)
    local s = date(withYear and "%a %d %b %Y" or "%a %d %b", KeyToTime(key))
    return (s:gsub(" 0(%d)", " %1"))
end

function ns.FormatShort(key)
    return (date("%d %b", KeyToTime(key)):gsub("^0", ""))
end

function ns.FormatWeek(key) return "Week of " .. ns.FormatShort(key) end

function ns.RelativeDay(key)
    local d = DaysBetween(key, ns.Today())
    if d <= 0 then return "today" end
    if d == 1 then return "yesterday" end
    if d < 7 then return d .. " days ago" end
    return ns.FormatShort(key)
end

ns.DayKey = DayKey

-- Log times: "Today 14:32", "Yesterday 09:10", "14 Nov 14:32".
function ns.FormatTime(t)
    local key, today = DayKey(t), ns.Today()
    local clock = date("%H:%M", t)
    if key == today then return "Today " .. clock end
    if key == AddDays(today, -1) then return "Yesterday " .. clock end
    return ns.FormatShort(key) .. " " .. clock
end

-- Full date and time for tooltips: "Sat 14 Nov 2026, 14:32".
function ns.FormatStamp(t)
    return ns.FormatDay(DayKey(t), true) .. ", " .. date("%H:%M", t)
end

-- Date filter buttons: 1 Today, 2 This week, 3 Last 30 days, 4 All time (nil, nil).
function ns.RangeFor(i)
    local today = ns.Today()
    if i == 1 then return today, today end
    if i == 2 then return WeekStart(today), today end
    if i == 3 then return AddDays(today, -29), today end
    return nil, nil
end

----------------------------------------------------------------------------
-- Milestones (account lifetime junk gold), in copper:
-- 10s, 50s, 1g, 2g, 5g, 6.7g, 10g, 15g, 20g, 30g, 45g, 50g, 80g, 140g, 200g,
-- then every 100g (300g, 400g, ...).
----------------------------------------------------------------------------
local MILESTONES = {
    1000, 5000, 10000, 20000, 50000, 67000, 100000, 150000,
    200000, 300000, 450000, 500000, 800000, 1400000, 2000000,
}
local STEP_AFTER = 1000000  -- 100g

local function MilestoneCopper(i)
    return MILESTONES[i] or MILESTONES[#MILESTONES] + (i - #MILESTONES) * STEP_AFTER
end

local function MilestoneLevel(copper)
    local i = 0
    while copper >= MilestoneCopper(i + 1) do i = i + 1 end
    return i
end

ns.MILESTONE_COUNT = #MILESTONES
ns.MilestoneCopper, ns.MilestoneLevel = MilestoneCopper, MilestoneLevel

function ns.LifetimeCopper()
    local c = 0
    for _, char in pairs(ns.db.chars) do c = c + char.total.c end
    return c
end

function ns.SyncMilestone()
    ns.db.milestone = MilestoneLevel(ns.LifetimeCopper())
end

-- Next milestone (copper), copper still needed, and progress (0-1) since the last one.
function ns.MilestoneProgress()
    local copper = ns.LifetimeCopper()
    local level = MilestoneLevel(copper)
    local prev = level > 0 and MilestoneCopper(level) or 0
    local goal = MilestoneCopper(level + 1)
    return goal, goal - copper, (copper - prev) / (goal - prev)
end

function ns.AnnounceMilestone(copper)
    local title = ns.MilestoneTitle and ns.MilestoneTitle(copper)
    local text = title and format("Junk milestone: %s! %s earned from junk.", title, ns.Money(copper))
        or format("Junk milestone: %s earned from junk!", ns.Money(copper))
    ns.Print("|cffffd100" .. text .. "|r Ka-ching!")
    if RaidNotice_AddMessage and RaidWarningFrame and ChatTypeInfo then
        RaidNotice_AddMessage(RaidWarningFrame, text, ChatTypeInfo["RAID_WARNING"])
    end
    if SOUNDKIT and SOUNDKIT.LOOT_WINDOW_COIN_SOUND then PlaySound(SOUNDKIT.LOOT_WINDOW_COIN_SOUND) end
end

----------------------------------------------------------------------------
-- Recording
----------------------------------------------------------------------------
local lastVisit  -- "visit#day#char" of the last recorded sale, so each vendor visit counts once

-- char.months["YYYY-MM"].src[label] = { copper, items }: what each mob or other
-- looted source earned that month.
local function MonthSources(char, dayKey, create)
    local ym = dayKey:sub(1, 7)
    local months = char.months
    if not months then
        if not create then return nil end
        months = {}; char.months = months
    end
    local m = months[ym]
    if not m then
        if not create then return nil end
        m = { src = {} }; months[ym] = m
    end
    return m.src
end

local function AddLog(char, row)
    local log = char.log
    if not log then log = {}; char.log = log end
    log[#log + 1] = row
    if #log > LOG_MAX then
        local keep = #log - LOG_TRIM
        for i = 1, keep do log[i] = log[i + LOG_TRIM] end
        for i = keep + 1, #log do log[i] = nil end
    end
end

-- sales = { { itemID, count, value, name }, ... } from one vendor visit (junk only).
-- opts.visit: vendor-window number (ns.visit); a visit is counted once however many calls it takes.
-- opts.manual: the player sold these by hand (no "biggest haul" record).
-- Each sale is matched to where the items came from (Sources.lua) and written to the
-- sales log, one row per source. Returns the milestones (in gold) crossed by this haul.
function ns.RecordHaul(sales, zone, opts)
    opts = opts or EMPTY
    local db = ns.db
    local key = ns.PlayerKey()
    local char = db.chars[key]
    if not char then
        char = { total = { c = 0, n = 0, s = 0 }, best = {}, days = {} }
        db.chars[key] = char
    end
    char.class = select(2, UnitClass("player"))

    local now = time()
    local today = DayKey(now)
    local day = char.days[today]
    if not day then day = NewDay(); char.days[today] = day end
    day.farm = day.farm or {}
    if not zone or zone == "" then zone = UNKNOWN or "Unknown" end

    local visitKey = opts.visit and (opts.visit .. "#" .. today .. "#" .. key)
    local newVisit = not visitKey or visitKey ~= lastVisit
    lastVisit = visitKey or lastVisit

    local copper, units = 0, 0
    for _, s in ipairs(sales) do
        local it = day.items[s.itemID]
        if not it then it = { 0, 0 }; day.items[s.itemID] = it end
        it[1], it[2] = it[1] + s.count, it[2] + s.value
        copper, units = copper + s.value, units + s.count
        if s.name then db.names[s.itemID] = s.name end
        local best = char.best.item
        if s.value > 0 and (not best or s.value > best.c) then
            char.best.item = { id = s.itemID, c = s.value, n = s.count, day = today }
        end

        local unit = s.count > 0 and s.value / s.count or 0
        local parts = ns.TakeSources and ns.TakeSources(s.itemID, s.count) or { { n = s.count } }
        for pi, p in ipairs(parts) do
            local c = floor(unit * p.n + 0.5)
            local row = {
                t = now, id = s.itemID, n = p.n, c = c, z = zone,
                k = p.k, s = p.s, lz = p.z, lt = p.t, rb = p.rb, m = opts.manual or nil,
                st = (pi == 1) and 1 or nil,  -- this row stands for the sold stack (one bag slot)
            }
            AddLog(char, row)
            if p.k and FARM_KINDS[p.k] then
                if p.z then
                    local f = day.farm[p.z]
                    if not f then f = { 0, 0 }; day.farm[p.z] = f end
                    f[1], f[2] = f[1] + c, f[2] + p.n
                end
                -- Per-month totals by mob/source: kept forever, unlike the log.
                local src = MonthSources(char, today, true)
                local label = ns.SourceLabel(row)
                local e = src[label]
                if not e then e = { 0, 0 }; src[label] = e end
                e[1], e[2] = e[1] + c, e[2] + p.n
            end
        end
    end

    day.c, day.n, day.s = day.c + copper, day.n + units, day.s + #sales
    local z = day.zones[zone]
    if not z then z = { 0, 0 }; day.zones[zone] = z end
    z[1] = z[1] + copper
    -- Count the visit once. A buyback can remove the day or zone entry mid-visit;
    -- a later sale in that same visit must not leave it at zero visits.
    if newVisit or day.v == 0 then day.v = day.v + 1 end
    if newVisit or z[2] == 0 then z[2] = z[2] + 1 end

    local total = char.total
    total.c, total.n, total.s = total.c + copper, total.n + units, total.s + #sales
    local haul = char.best.haul
    if not opts.manual and (not haul or copper > haul.c) then
        char.best.haul = { c = copper, n = units, day = today, zone = zone }
    end

    wipe(cache)
    local reached, level = {}, MilestoneLevel(ns.LifetimeCopper())
    for i = db.milestone + 1, level do reached[#reached + 1] = MilestoneCopper(i) end
    if level > db.milestone then db.milestone = level end
    ns.Notify("data")
    return reached
end

-- Take one log row's sale back out of the daily, item, zone and character totals.
local function Subtract(char, r)
    local function Down(t, i, v) t[i] = math.max(0, t[i] - v) end
    local dk = DayKey(r.t)
    local day = char.days[dk]
    if day then
        local it = day.items[r.id]
        if it then
            Down(it, 1, r.n); Down(it, 2, r.c)
            if it[1] == 0 then day.items[r.id] = nil end
        end
        Down(day, "c", r.c); Down(day, "n", r.n)
        local z = r.z and day.zones[r.z]
        if z then
            Down(z, 1, r.c)
            if z[1] == 0 then day.zones[r.z] = nil end
        end
        local f = r.lz and day.farm and day.farm[r.lz]
        if f and r.k and FARM_KINDS[r.k] then
            Down(f, 1, r.c); Down(f, 2, r.n)
            if f[2] == 0 then day.farm[r.lz] = nil end
        end
        if r.st then Down(day, "s", 1) end  -- the bag slot is taken again
        if day.n == 0 then char.days[dk] = nil end  -- every sale that day was bought back
    end
    Down(char.total, "c", r.c); Down(char.total, "n", r.n)
    if r.st then Down(char.total, "s", 1) end
    if r.k and FARM_KINDS[r.k] then
        local src = MonthSources(char, dk, false)
        local label = ns.SourceLabel(r)
        local e = src and src[label]
        if e then
            Down(e, 1, r.c); Down(e, 2, r.n)
            if e[2] == 0 then src[label] = nil end
        end
    end
end

-- A buyback of n units of itemID: cancel the newest matching sales made since
-- `since` (the game's buyback list only lasts one session). Rows are kept in the
-- log, marked "bought back". Returns the undone rows so their sources can be restored.
-- Milestones already announced and the best haul/priciest sale records stay as they are.
function ns.UndoSale(itemID, n, since)
    local out = {}
    local char = ns.db.chars[ns.PlayerKey()]
    local log = char and char.log
    if not log then return out end
    local now = time()
    for i = #log, 1, -1 do
        if n <= 0 then break end
        local r = log[i]
        if since and r.t < since then break end
        if r.id == itemID and not r.bb then
            if r.n > n then
                -- Only part of this row came back: split it so the rest stays a sale.
                local part = {}
                for k, v in pairs(r) do part[k] = v end
                part.n, part.c, part.st = n, floor(r.c / r.n * n + 0.5), nil
                r.n, r.c = r.n - n, r.c - part.c
                table.insert(log, i + 1, part)
                r = part
            end
            r.bb = now
            Subtract(char, r)
            n = n - r.n
            out[#out + 1] = r
        end
    end
    if #out > 0 then
        wipe(cache)
        ns.Notify("data")
    end
    return out
end

function ns.ResetHistory(scope)
    if scope == "ALL" then wipe(ns.db.chars) else ns.db.chars[scope] = nil end
    wipe(cache)
    ns.SyncMilestone()
    if ns.PruneAchievements then ns.PruneAchievements() end  -- a reset starts them over
    ns.Notify("data")
end

----------------------------------------------------------------------------
-- Queries
----------------------------------------------------------------------------
local function MergeDay(dst, src)
    dst.c, dst.n, dst.s, dst.v = dst.c + src.c, dst.n + src.n, dst.s + src.s, dst.v + src.v
    for id, it in pairs(src.items) do
        local d = dst.items[id]
        if not d then d = { 0, 0 }; dst.items[id] = d end
        d[1], d[2] = d[1] + it[1], d[2] + it[2]
    end
    for zone, z in pairs(src.zones) do
        local d = dst.zones[zone]
        if not d then d = { 0, 0 }; dst.zones[zone] = d end
        d[1], d[2] = d[1] + z[1], d[2] + z[2]
    end
    for zone, f in pairs(src.farm or EMPTY) do
        local d = dst.farm[zone]
        if not d then d = { 0, 0 }; dst.farm[zone] = d end
        d[1], d[2] = d[1] + f[1], d[2] + f[2]
    end
end

-- dayKey -> day. Treat the result as read-only.
function ns.GetDays(scope)
    if scope ~= "ALL" then
        local char = ns.db.chars[scope]
        return char and char.days or EMPTY
    end
    if not cache.all then
        local all = {}
        for _, char in pairs(ns.db.chars) do
            for key, day in pairs(char.days) do
                all[key] = all[key] or NewDay()
                MergeDay(all[key], day)
            end
        end
        cache.all = all
    end
    return cache.all
end

local function InRange(key, from, to)
    return (not from or key >= from) and (not to or key <= to)
end

function ns.Totals(scope)
    local today = ns.Today()
    local week, month = WeekStart(today), today:sub(1, 7)
    local r = {
        today = { c = 0, n = 0 }, week = { c = 0, n = 0 },
        month = { c = 0, n = 0 }, all = { c = 0, n = 0 },
    }
    local function add(t, d) t.c, t.n = t.c + d.c, t.n + d.n end
    for key, d in pairs(ns.GetDays(scope)) do
        add(r.all, d)
        if key == today then add(r.today, d) end
        if key >= week and key <= today then add(r.week, d) end
        if key:sub(1, 7) == month then add(r.month, d) end
    end
    return r
end

-- Contiguous buckets (empty ones included) ending with the current day/week/month/year.
function ns.Series(scope, kind, count)
    local days, today, out = ns.GetDays(scope), ns.Today(), {}
    if kind == "month" or kind == "year" then
        local month = kind == "month"
        local len = month and 7 or 4  -- key prefix that names the bucket
        local byPrefix = {}
        for i = 1, count do
            local from = month and AddMonths(MonthStart(today), i - count)
                or format("%04d-01-01", tonumber(today:sub(1, 4)) + i - count)
            local _, to = PeriodBounds(kind, from)
            local p = { key = from, to = to, c = 0, n = 0, current = i == count, kind = kind,
                        label = month and date("%b", KeyToTime(from)) or from:sub(1, 4) }
            out[i] = p
            byPrefix[from:sub(1, len)] = p
        end
        for key, d in pairs(days) do
            local p = byPrefix[key:sub(1, len)]
            if p then p.c, p.n = p.c + d.c, p.n + d.n end
        end
    elseif kind == "week" then
        local first = AddDays(WeekStart(today), -7 * (count - 1))
        for i = 1, count do
            local from = AddDays(first, (i - 1) * 7)
            local p = { key = from, to = AddDays(from, 6), label = ns.FormatShort(from),
                        c = 0, n = 0, current = i == count, kind = "week" }
            for j = 0, 6 do
                local d = days[AddDays(from, j)]
                if d then p.c, p.n = p.c + d.c, p.n + d.n end
            end
            out[i] = p
        end
    else
        for i = 1, count do
            local key = AddDays(today, i - count)
            local d = days[key]
            out[i] = { key = key, to = key, label = tostring(tonumber(key:sub(9, 10))),
                       c = d and d.c or 0, n = d and d.n or 0, current = i == count, kind = "day" }
        end
    end
    return out
end

-- Every day, week, month or year that has sales, newest first.
function ns.Periods(scope, kind)
    local list, today = {}, ns.Today()
    if kind == "week" or kind == "month" or kind == "year" then
        local groups = {}
        for key, d in pairs(ns.GetDays(scope)) do
            local from, to = PeriodBounds(kind, key)
            local w = groups[from]
            if not w then
                w = { key = from, to = to, c = 0, n = 0, v = 0, active = 0, kind = kind }
                groups[from] = w
                list[#list + 1] = w
            end
            w.c, w.n, w.v, w.active = w.c + d.c, w.n + d.n, w.v + d.v, w.active + 1
        end
        for _, w in ipairs(list) do
            -- Days so far for the period we are in, the full length otherwise.
            w.length = DaysBetween(w.key, (today < w.to) and today or w.to) + 1
        end
    else
        for key, d in pairs(ns.GetDays(scope)) do
            list[#list + 1] = { key = key, to = key, c = d.c, n = d.n, v = d.v,
                                active = 1, length = 1, kind = "day" }
        end
    end
    sort(list, function(a, b) return a.key > b.key end)
    return list
end

-- Per-item totals for a date range (nil = all time).
function ns.ItemTable(scope, from, to)
    local map, list = {}, {}
    for key, d in pairs(ns.GetDays(scope)) do
        if InRange(key, from, to) then
            for id, it in pairs(d.items) do
                local e = map[id]
                if not e then
                    e = { id = id, name = ns.ItemName(id), n = 0, c = 0, last = key }
                    map[id] = e
                    list[#list + 1] = e
                end
                e.n, e.c = e.n + it[1], e.c + it[2]
                if key > e.last then e.last = key end
            end
        end
    end
    for _, e in ipairs(list) do e.each = e.n > 0 and e.c / e.n or 0 end
    return list
end

-- Per-zone totals for a date range (nil = all time), biggest first.
-- mode "farm": where the junk was looted (z[2] = items), otherwise where it was sold (z[2] = visits).
function ns.ZoneTable(scope, from, to, mode)
    local farm = mode == "farm"
    local map, list, total = {}, {}, 0
    for key, d in pairs(ns.GetDays(scope)) do
        if InRange(key, from, to) then
            for zone, z in pairs((farm and d.farm or d.zones) or EMPTY) do
                local e = map[zone]
                if not e then
                    e = { zone = zone, name = zone, c = 0, v = 0, n = 0 }
                    map[zone] = e
                    list[#list + 1] = e
                end
                e.c = e.c + z[1]
                if farm then e.n = e.n + z[2] else e.v = e.v + z[2] end
                total = total + z[1]
            end
        end
    end
    for _, e in ipairs(list) do
        e.share = total > 0 and e.c / total or 0
        if farm then
            e.per = e.n > 0 and e.c / e.n or 0
        else
            e.per = e.v > 0 and e.c / e.v or 0
        end
    end
    sort(list, function(a, b) return a.c > b.c end)
    return list, total
end

-- What each mob (or chest, fishing, container) earned, for the months that
-- overlap a date range (nil = all time). Kept per month, so it covers whole months.
function ns.SourceTable(scope, from, to)
    local map, list, total = {}, {}, 0
    local fromYM, toYM = from and from:sub(1, 7), to and to:sub(1, 7)
    for key, char in pairs(ns.db.chars) do
        if scope == "ALL" or scope == key then
            for ym, m in pairs(char.months or EMPTY) do
                if (not fromYM or ym >= fromYM) and (not toYM or ym <= toYM) then
                    for label, s in pairs(m.src or EMPTY) do
                        local e = map[label]
                        if not e then
                            e = { name = label, zone = label, c = 0, n = 0 }
                            map[label] = e
                            list[#list + 1] = e
                        end
                        e.c, e.n = e.c + s[1], e.n + s[2]
                        total = total + s[1]
                    end
                end
            end
        end
    end
    for _, e in ipairs(list) do
        e.share = total > 0 and e.c / total or 0
        e.per = e.n > 0 and e.c / e.n or 0
    end
    sort(list, function(a, b) return a.c > b.c end)
    return list, total
end

local function EachLogRow(scope, fn)
    for key, char in pairs(ns.db.chars) do
        if (scope == "ALL" or scope == key) and char.log then
            for _, r in ipairs(char.log) do fn(r, key) end
        end
    end
end

-- Sales in a date range (from 2.1.0 on) that earned no farm-zone credit:
-- mailed, traded, banked, "other" and unknown origin. Returns copper, items.
function ns.UncreditedTotal(scope, from, to)
    local c, n = 0, 0
    EachLogRow(scope, function(r)
        if not r.bb and not (r.k and FARM_KINDS[r.k] and r.lz) and InRange(DayKey(r.t), from, to) then
            c, n = c + r.c, n + r.n
        end
    end)
    return c, n
end

local KIND_LABEL = { fish = "Fishing", mail = "Mail", trade = "Trade", bank = "Bank", other = "Other" }

-- Where a log row's junk came from, as plain text.
function ns.SourceLabel(r)
    local k = r.k
    if not k then return "Before tracking" end
    if k == "mob" then return r.s or "Unknown creature" end
    if k == "object" then return r.s or "Object" end
    if k == "item" then return r.s or "Container" end
    return KIND_LABEL[k] or "Other"
end

local function LogNote(r)
    if r.bb then return "Bought back" end
    if r.rb and r.rb > 0 then return r.rb > 1 and ("Re-sold x" .. r.rb) or "Re-sold" end
    if r.m then return "By hand" end
    return ""
end

-- Every sales-log row in scope, newest first.
function ns.LogEntries(scope)
    local list = {}
    EachLogRow(scope, function(r, key)
        list[#list + 1] = {
            id = r.id, name = ns.ItemName(r.id), t = r.t, n = r.n, c = r.c,
            src = ns.SourceLabel(r), note = LogNote(r), char = key, row = r,
        }
    end)
    sort(list, function(a, b) return a.t > b.t end)
    return list
end

function ns.Records(scope)
    local days = ns.GetDays(scope)
    local keys = {}
    for key, d in pairs(days) do
        if d.n > 0 then keys[#keys + 1] = key end
    end
    sort(keys)

    local r = { activeDays = #keys, first = keys[1], slots = 0, total = 0, streak = 0, longest = 0 }
    local run, prev = 0, nil
    for _, key in ipairs(keys) do
        local d = days[key]
        r.total, r.slots = r.total + d.c, r.slots + d.s
        if not r.bestDay or d.c > r.bestDay.c then r.bestDay = { key = key, c = d.c, n = d.n } end
        run = (prev and AddDays(prev, 1) == key) and run + 1 or 1
        if run > r.longest then r.longest = run end
        prev = key
    end
    r.avg = #keys > 0 and r.total / #keys or 0

    for _, w in ipairs(ns.Periods(scope, "week")) do
        if not r.bestWeek or w.c > r.bestWeek.c then r.bestWeek = w end
    end
    for _, m in ipairs(ns.Periods(scope, "month")) do
        if not r.bestMonth or m.c > r.bestMonth.c then r.bestMonth = m end
    end

    -- Current streak stays alive until a full day passes without a sale.
    local today = ns.Today()
    r.soldToday = days[today] ~= nil and days[today].n > 0
    local k = r.soldToday and today or AddDays(today, -1)
    while days[k] and days[k].n > 0 do
        r.streak = r.streak + 1
        k = AddDays(k, -1)
    end

    for key, char in pairs(ns.db.chars) do
        if scope == "ALL" or scope == key then
            local h, i = char.best.haul, char.best.item
            if h and (not r.haul or h.c > r.haul.c) then r.haul, r.haulChar = h, key end
            if i and (not r.item or i.c > r.item.c) then r.item, r.itemChar = i, key end
        end
    end
    return r
end

----------------------------------------------------------------------------
-- Characters & bookkeeping
----------------------------------------------------------------------------
function ns.CharList()
    local list = {}
    for key, char in pairs(ns.db.chars) do
        list[#list + 1] = { key = key, class = char.class, c = char.total.c }
    end
    sort(list, function(a, b) return a.c > b.c end)
    return list
end

function ns.CharLabel(key)
    local char = ns.db.chars[key]
    local name, realm = key:match("^(.-)%-(.+)$")
    name = name or key
    local color = char and char.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[char.class]
    if color and color.colorStr then name = "|c" .. color.colorStr .. name .. "|r" end
    return realm and (name .. " |cff808080- " .. realm .. "|r") or name
end

function ns.ScopeLabel(scope)
    return scope == "ALL" and "All characters" or ns.CharLabel(scope)
end

-- characters, distinct days, distinct items tracked
function ns.Footprint()
    local chars, days, items, nd, ni = 0, {}, {}, 0, 0
    for _, char in pairs(ns.db.chars) do
        chars = chars + 1
        for key, d in pairs(char.days) do
            if not days[key] then days[key] = true; nd = nd + 1 end
            for id in pairs(d.items) do
                if not items[id] then items[id] = true; ni = ni + 1 end
            end
        end
    end
    return chars, nd, ni
end
