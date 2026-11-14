-- Grey Gold: history storage and the queries behind the stats window.
-- No frames here. Scope is "ALL" (every character) or a "Name-Realm" key.

local ADDON, ns = ...

local DAY = 86400
local EMPTY = {}
local cache = {}  -- merged "ALL" days; wiped whenever history changes

local function NewDay()
    return { c = 0, n = 0, s = 0, v = 0, items = {}, zones = {} }
end

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

ns.AddDays, ns.WeekStart = AddDays, WeekStart

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

----------------------------------------------------------------------------
-- Milestones (account lifetime gold): 10g, 25g ... 10000g, then every 10000g
----------------------------------------------------------------------------
local MILESTONES = { 10, 25, 50, 100, 250, 500, 1000, 2500, 5000, 10000 }

local function MilestoneGold(i)
    return MILESTONES[i] or (i - #MILESTONES + 1) * 10000
end

local function MilestoneLevel(copper)
    local i = 0
    while copper >= MilestoneGold(i + 1) * 10000 do i = i + 1 end
    return i
end

function ns.LifetimeCopper()
    local c = 0
    for _, char in pairs(ns.db.chars) do c = c + char.total.c end
    return c
end

function ns.SyncMilestone()
    ns.db.milestone = MilestoneLevel(ns.LifetimeCopper())
end

function ns.AnnounceMilestone(gold)
    local text = format("Junk milestone: %s earned from junk!", ns.Money(gold * 10000))
    ns.Print("|cffffd100" .. text .. "|r Ka-ching!")
    if RaidNotice_AddMessage and RaidWarningFrame and ChatTypeInfo then
        RaidNotice_AddMessage(RaidWarningFrame, text, ChatTypeInfo["RAID_WARNING"])
    end
    if SOUNDKIT and SOUNDKIT.LOOT_WINDOW_COIN_SOUND then PlaySound(SOUNDKIT.LOOT_WINDOW_COIN_SOUND) end
end

----------------------------------------------------------------------------
-- Recording
----------------------------------------------------------------------------
-- sales = { { itemID, count, value, name }, ... } from one vendor visit.
-- Returns the milestones (in gold) crossed by this haul.
function ns.RecordHaul(sales, zone)
    local db = ns.db
    local key = ns.PlayerKey()
    local char = db.chars[key]
    if not char then
        char = { total = { c = 0, n = 0, s = 0 }, best = {}, days = {} }
        db.chars[key] = char
    end
    char.class = select(2, UnitClass("player"))

    local today = ns.Today()
    local day = char.days[today]
    if not day then day = NewDay(); char.days[today] = day end
    if not zone or zone == "" then zone = UNKNOWN or "Unknown" end

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
    end

    day.c, day.n, day.s, day.v = day.c + copper, day.n + units, day.s + #sales, day.v + 1
    local z = day.zones[zone]
    if not z then z = { 0, 0 }; day.zones[zone] = z end
    z[1], z[2] = z[1] + copper, z[2] + 1

    local total = char.total
    total.c, total.n, total.s = total.c + copper, total.n + units, total.s + #sales
    local haul = char.best.haul
    if not haul or copper > haul.c then
        char.best.haul = { c = copper, n = units, day = today, zone = zone }
    end

    wipe(cache)
    local reached, level = {}, MilestoneLevel(ns.LifetimeCopper())
    for i = db.milestone + 1, level do reached[#reached + 1] = MilestoneGold(i) end
    if level > db.milestone then db.milestone = level end
    ns.Notify("data")
    return reached
end

function ns.ResetHistory(scope)
    if scope == "ALL" then wipe(ns.db.chars) else ns.db.chars[scope] = nil end
    wipe(cache)
    ns.SyncMilestone()
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

-- Contiguous buckets (empty ones included) ending with the current day/week.
function ns.Series(scope, kind, count)
    local days, today, out = ns.GetDays(scope), ns.Today(), {}
    if kind == "week" then
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

-- Every day or week that has sales, newest first.
function ns.Periods(scope, kind)
    local list, today = {}, ns.Today()
    if kind == "week" then
        local weeks, thisWeek = {}, WeekStart(today)
        for key, d in pairs(ns.GetDays(scope)) do
            local wk = WeekStart(key)
            local w = weeks[wk]
            if not w then
                w = { key = wk, to = AddDays(wk, 6), c = 0, n = 0, v = 0, active = 0, kind = "week" }
                weeks[wk] = w
                list[#list + 1] = w
            end
            w.c, w.n, w.v, w.active = w.c + d.c, w.n + d.n, w.v + d.v, w.active + 1
        end
        for _, w in ipairs(list) do
            w.length = (w.key == thisWeek) and (DaysBetween(w.key, today) + 1) or 7
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
function ns.ZoneTable(scope, from, to)
    local map, list, total = {}, {}, 0
    for key, d in pairs(ns.GetDays(scope)) do
        if InRange(key, from, to) then
            for zone, z in pairs(d.zones) do
                local e = map[zone]
                if not e then
                    e = { zone = zone, name = zone, c = 0, v = 0 }
                    map[zone] = e
                    list[#list + 1] = e
                end
                e.c, e.v = e.c + z[1], e.v + z[2]
                total = total + z[1]
            end
        end
    end
    for _, e in ipairs(list) do
        e.share = total > 0 and e.c / total or 0
        e.per = e.v > 0 and e.c / e.v or 0
    end
    sort(list, function(a, b) return a.c > b.c end)
    return list, total
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
