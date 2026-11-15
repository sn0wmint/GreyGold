-- Grey Gold: the six tabs of the stats window, plus the small entry in
-- Esc > Options > AddOns. Each panel is built the first time it is shown.

local _, ns = ...
local UI = ns.UI
local W, H = UI.BODY_W, UI.BODY_H

local GREY = "|cff9d9d9d"
local DIM = "|cff808080"

local function Scope() return ns.db.ui.scope end

local function Plural(n, one, many)
    return ns.Num(n) .. " " .. ((n == 1) and one or (many or one .. "s"))
end

local function ItemLabel(e)
    local s = GREY .. e.name .. "|r"
    if ns.db.neverSell[e.id] then s = s .. " |cff40ff40(kept)|r" end
    return s
end

-- Date filter shared by the Items and Zones tabs. dbKey remembers the choice.
local RANGES = { "Today", "This week", "30 days", "All time" }
local function NewRangeToggle(p, dbKey)
    local t = UI.NewToggle(p, RANGES, function(i)
        ns.db.ui[dbKey] = i
        p:Refresh()
    end, 66)
    return t
end

local function RangeChoice(dbKey) return ns.db.ui[dbKey] or #RANGES end

local function ItemTooltipExtra(tt, e, canToggle)
    tt:AddLine(" ")
    tt:AddDoubleLine("Sold", ns.Num(e.n) .. "x", 1, 0.82, 0, 1, 1, 1)
    tt:AddDoubleLine("Earned", ns.Money(e.c), 1, 0.82, 0, 1, 1, 1)
    tt:AddDoubleLine("Average each", ns.Money(e.each), 1, 0.82, 0, 1, 1, 1)
    if e.last then tt:AddDoubleLine("Last sold", ns.RelativeDay(e.last), 1, 0.82, 0, 1, 1, 1) end
    if ns.db.neverSell[e.id] then tt:AddLine("Protected: never sold", 0.25, 1, 0.25) end
    if canToggle then tt:AddLine("Right-click to toggle never-sell", 0.6, 0.6, 0.6) end
end

----------------------------------------------------------------------------
-- 1. Overview
----------------------------------------------------------------------------
local function RecordEnter(self)
    if not self.tip then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    self.tip(GameTooltip)
    GameTooltip:Show()
end

local function RecordClick(self)
    if self.onClick then self.onClick() end
end

UI.builders[1] = function(parent)
    local p = UI.NewPanel(parent)

    local gap = 8
    local tw = (W - gap * 3) / 4
    p.tiles = {}
    for i, label in ipairs({ "Today", "This week", "This month", "All time" }) do
        local t = UI.NewTile(p, tw, 62, label)
        t:SetPoint("TOPLEFT", (i - 1) * (tw + gap), 0)
        p.tiles[i] = t
    end

    -- Progress to the next junk milestone (account-wide, like the announcements).
    local BAR_W = W - 112  -- room for the Achievements button at its right end
    local mb = CreateFrame("Frame", nil, p)
    mb:SetSize(BAR_W, 16)
    mb:SetPoint("TOPLEFT", 0, -68)
    local mbBg = mb:CreateTexture(nil, "BACKGROUND")
    mbBg:SetAllPoints()
    mbBg:SetColorTexture(0, 0, 0, 0.45)
    mb.fill = mb:CreateTexture(nil, "BORDER")
    mb.fill:SetPoint("TOPLEFT")
    mb.fill:SetPoint("BOTTOMLEFT")
    mb.fill:SetColorTexture(0.78, 0.58, 0.14, 0.75)
    mb.text = UI.Text(mb, "GameFontHighlightSmall", nil, "CENTER")
    mb.text:SetPoint("CENTER", 0, 0)
    mb:EnableMouse(true)
    mb:SetScript("OnEnter", function(self)
        local goal, left = ns.MilestoneProgress()
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Junk milestones", 1, 0.82, 0)
        GameTooltip:AddDoubleLine("Lifetime junk gold", ns.Money(ns.LifetimeCopper()), 1, 1, 1, 1, 1, 1)
        GameTooltip:AddDoubleLine("Next milestone", ns.Money(goal), 1, 1, 1, 1, 1, 1)
        GameTooltip:AddDoubleLine("Still to go", ns.Money(left), 1, 1, 1, 1, 1, 1)
        GameTooltip:AddLine("Every grey item you sell counts, by hand or automatically, on all your characters.", 0.6, 0.6, 0.6, true)
        GameTooltip:Show()
    end)
    mb:SetScript("OnLeave", UI.HideTooltip)
    p.milestone = mb

    local ach = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    ach:SetSize(106, 18)
    ach:SetPoint("LEFT", mb, "RIGHT", 6, 0)
    ach:SetText("Achievements")
    ach:SetScript("OnClick", function()
        UI.Sound("U_CHAT_SCROLL_BUTTON")
        UI.ToggleAchievements()
    end)

    local title = UI.Header(p, "Gold per day", W - 150)
    title:SetPoint("TOPLEFT", 2, -94)
    p.range = UI.NewToggle(p, { "14 days", "30 days" }, function(i)
        ns.db.ui.overviewRange = i
        p:Refresh()
    end, 64)
    p.range:SetPoint("TOPRIGHT", p, "TOPRIGHT", -66, -90)
    p.chart = UI.NewChart(p, W, 118)
    p.chart:SetPoint("TOPLEFT", 0, -114)

    local rh = UI.Header(p, "Records", W)
    rh:SetPoint("TOPLEFT", 2, -244)
    local labels = {
        "Best day", "Best week", "Biggest haul", "Priciest sale", "Bag slots freed",
        "Current streak", "Longest streak", "Active days", "Avg per active day", "Tracking since",
    }
    local colW = (W - 16) / 2
    p.rec = {}
    for i, label in ipairs(labels) do
        local col, rowIdx = (i <= 5) and 0 or 1, (i - 1) % 5
        local r = CreateFrame("Button", nil, p)
        r:SetSize(colW, 20)
        r:SetPoint("TOPLEFT", 2 + col * (colW + 16), -266 - rowIdx * 24)
        r.label = UI.Text(r, "GameFontNormalSmall", label, "LEFT")
        r.label:SetPoint("LEFT", 0, 0)
        r.label:SetWidth(118)
        r.value = UI.Text(r, "GameFontHighlight", nil, "LEFT")
        r.value:SetPoint("LEFT", 120, 0)
        r.value:SetWidth(colW - 122)
        r.value:SetWordWrap(false)
        r:SetScript("OnEnter", RecordEnter)
        r:SetScript("OnLeave", UI.HideTooltip)
        r:SetScript("OnClick", RecordClick)
        function r:Set(text, tip, onClick)
            self.value:SetText(text or (DIM .. "none yet|r"))
            self.tip, self.onClick = tip, onClick
        end
        p.rec[i] = r
    end

    function p:Refresh()
        local scope = Scope()
        local t = ns.Totals(scope)
        local tiles = { t.today, t.week, t.month, t.all }
        for i, v in ipairs(tiles) do self.tiles[i]:Set(ns.Money(v.c, true), Plural(v.n, "item")) end

        local goal, left, frac = ns.MilestoneProgress()
        self.milestone.fill:SetWidth(math.max(1, BAR_W * math.min(1, math.max(0, frac))))
        self.milestone.text:SetText(format("Next milestone |cffffd100%s|r:  %s to go",
            ns.Money(goal), ns.Money(left, true)))

        local range = ns.db.ui.overviewRange or 1
        self.range:Select(range)
        self.chart:SetData(ns.Series(scope, "day", range == 2 and 30 or 14), function(s)
            UI.OpenHistory("day", s.key)
        end)

        local r = ns.Records(scope)
        local rec = self.rec
        local bd, bw, haul, item = r.bestDay, r.bestWeek, r.haul, r.item

        rec[1]:Set(bd and (ns.Money(bd.c, true) .. "  " .. DIM .. ns.FormatDay(bd.key) .. "|r"),
            bd and function(tt)
                tt:AddLine(ns.FormatDay(bd.key, true), 1, 0.82, 0)
                tt:AddDoubleLine("Gold", ns.Money(bd.c), 1, 1, 1, 1, 1, 1)
                tt:AddDoubleLine("Items", ns.Num(bd.n), 1, 1, 1, 1, 1, 1)
                tt:AddLine("Click to open that day", 0.6, 0.6, 0.6)
            end,
            bd and function() UI.OpenHistory("day", bd.key) end)

        rec[2]:Set(bw and (ns.Money(bw.c, true) .. "  " .. DIM .. ns.FormatShort(bw.key) .. "|r"),
            bw and function(tt)
                tt:AddLine(ns.FormatWeek(bw.key) .. " - " .. ns.FormatShort(bw.to), 1, 0.82, 0)
                tt:AddDoubleLine("Gold", ns.Money(bw.c), 1, 1, 1, 1, 1, 1)
                tt:AddDoubleLine("Items", ns.Num(bw.n), 1, 1, 1, 1, 1, 1)
                tt:AddDoubleLine("Days with sales", bw.active, 1, 1, 1, 1, 1, 1)
                if r.bestMonth then
                    tt:AddLine(" ")
                    tt:AddDoubleLine("Best month", ns.FormatMonth(r.bestMonth.key) .. "  " .. ns.Money(r.bestMonth.c, true),
                        1, 0.82, 0, 1, 1, 1)
                end
                tt:AddLine("Click to open that week", 0.6, 0.6, 0.6)
            end,
            bw and function() UI.OpenHistory("week", bw.key) end)

        rec[3]:Set(haul and (ns.Money(haul.c, true) .. "  " .. DIM .. Plural(haul.n, "item") .. "|r"),
            haul and function(tt)
                tt:AddLine("Biggest single vendor visit", 1, 0.82, 0)
                tt:AddDoubleLine("Gold", ns.Money(haul.c), 1, 1, 1, 1, 1, 1)
                tt:AddDoubleLine("Items", ns.Num(haul.n), 1, 1, 1, 1, 1, 1)
                tt:AddDoubleLine("Sold in", haul.zone or "?", 1, 1, 1, 1, 1, 1)
                tt:AddDoubleLine("Date", ns.FormatDay(haul.day, true), 1, 1, 1, 1, 1, 1)
                if scope == "ALL" then tt:AddDoubleLine("Character", ns.CharLabel(r.haulChar), 1, 1, 1) end
            end)

        rec[4]:Set(item and (ns.Money(item.c, true) .. "  |T" .. ns.ItemIcon(item.id) .. ":14|t " .. GREY .. ns.ItemName(item.id) .. "|r"),
            item and function(tt)
                tt:SetItemByID(item.id)
                tt:AddLine(" ")
                tt:AddDoubleLine("Sold for", ns.Money(item.c) .. (item.n > 1 and ("  (x" .. item.n .. ")") or ""), 1, 0.82, 0, 1, 1, 1)
                tt:AddDoubleLine("Date", ns.FormatDay(item.day, true), 1, 0.82, 0, 1, 1, 1)
                if scope == "ALL" then tt:AddDoubleLine("Character", ns.CharLabel(r.itemChar), 1, 0.82, 0) end
            end)

        rec[5]:Set(r.activeDays > 0 and ns.Num(r.slots) or nil, function(tt)
            tt:AddLine("Bag slots freed", 1, 0.82, 0)
            tt:AddLine("Every stack sold frees up one bag slot.", 1, 1, 1, true)
        end)

        local flair = ""
        if r.streak >= 7 then flair = "  |cffff8000on fire!|r"
        elseif r.streak >= 3 then flair = "  |cffffd100nice!|r" end
        rec[6]:Set(r.activeDays > 0 and (Plural(r.streak, "day") .. flair) or nil, function(tt)
            tt:AddLine("Current streak", 1, 0.82, 0)
            tt:AddLine("Days in a row with at least one junk sale.", 1, 1, 1, true)
            if r.streak > 0 and not r.soldToday then
                tt:AddLine("Sell something today to keep it alive!", 1, 0.5, 0, true)
            end
        end)
        rec[7]:Set(r.activeDays > 0 and Plural(r.longest, "day") or nil)
        rec[8]:Set(r.activeDays > 0 and ns.Num(r.activeDays) or nil)
        rec[9]:Set(r.activeDays > 0 and ns.Money(r.avg, true) or nil)
        rec[10]:Set(r.first and ns.FormatDay(r.first, true) or nil)
    end

    return p
end

----------------------------------------------------------------------------
-- 2. History: daily / weekly periods with a per-item breakdown
----------------------------------------------------------------------------
local HISTORY_KINDS = { "day", "week", "month", "year" }
local HISTORY_BARS = { 30, 12, 12, 5 }  -- bars in the chart for each mode

UI.builders[2] = function(parent)
    local p = UI.NewPanel(parent)
    p.kind = "day"

    p.mode = UI.NewToggle(p, { "Daily", "Weekly", "Monthly", "Yearly" }, function(i)
        p.kind = HISTORY_KINDS[i]
        p.selected = nil
        p:Refresh()
    end, 62)
    p.mode:SetPoint("TOPLEFT", 0, 0)
    p.info = UI.Text(p, "GameFontDisableSmall", nil, "RIGHT")
    p.info:SetPoint("TOPRIGHT", -4, -5)

    p.chart = UI.NewChart(p, W, 110)
    p.chart:SetPoint("TOPLEFT", 0, -26)

    local leftW = 236
    p.periods = UI.NewList(p, leftW, H - 146, {
        { title = "Date", width = 96, sort = "key", fmt = function(e)
            if e.kind == "week" then return "Wk " .. ns.FormatShort(e.key) end
            if e.kind == "month" then return ns.FormatMonth(e.key) end
            if e.kind == "year" then return e.key:sub(1, 4) end
            return ns.FormatDay(e.key)
        end },
        { title = "Items", width = 38, sort = "n", align = "RIGHT", fmt = function(e) return ns.Num(e.n) end },
        { title = "Gold", width = 74, sort = "c", align = "RIGHT", fmt = function(e) return ns.Money(e.c, true) end },
    }, {
        sortCol = 1,
        emptyText = "No sales recorded yet.\nVisit a vendor!",
        isSelected = function(e) return e.key == p.selected end,
        onClick = function(e)
            p.selected = e.key
            p:Refresh()
        end,
        tooltip = function(tt, e)
            tt:AddLine(ns.FormatPeriod(e.kind, e.key), 1, 0.82, 0)
            tt:AddDoubleLine("Gold", ns.Money(e.c), 1, 1, 1, 1, 1, 1)
            tt:AddDoubleLine("Items", ns.Num(e.n), 1, 1, 1, 1, 1, 1)
            tt:AddDoubleLine("Vendor visits", ns.Num(e.v), 1, 1, 1, 1, 1, 1)
            if e.kind ~= "day" then tt:AddDoubleLine("Days with sales", ns.Num(e.active), 1, 1, 1, 1, 1, 1) end
        end,
    })
    p.periods:SetPoint("TOPLEFT", 0, -146)

    local rx = leftW + 12
    local rw = W - rx
    p.title = UI.Text(p, "GameFontNormal", nil, "LEFT")
    p.title:SetPoint("TOPLEFT", rx, -146)
    p.title:SetWidth(rw)
    p.summary = UI.Text(p, "GameFontHighlightSmall", nil, "LEFT")
    p.summary:SetPoint("TOPLEFT", rx, -164)
    p.summary:SetWidth(rw)
    p.summary:SetWordWrap(false)
    p.zones = UI.Text(p, "GameFontDisableSmall", nil, "LEFT")
    p.zones:SetPoint("TOPLEFT", rx, -179)
    p.zones:SetWidth(rw)
    p.zones:SetWordWrap(false)

    p.items = UI.NewList(p, rw, H - 196, {
        { title = "Item", width = 160, sort = "name", defaultAsc = true, icon = true, fmt = ItemLabel },
        { title = "Qty", width = 36, sort = "n", align = "RIGHT", fmt = function(e) return ns.Num(e.n) end },
        { title = "Gold", width = 70, sort = "c", align = "RIGHT", fmt = function(e) return ns.Money(e.c, true) end },
        { title = "Each", width = 66, sort = "each", align = "RIGHT", fmt = function(e) return ns.Money(e.each) end },
    }, {
        sortCol = 3,
        emptyText = "Nothing sold in this period.",
        tooltipExtra = function(tt, e) ItemTooltipExtra(tt, e, false) end,
    })
    p.items:SetPoint("TOPLEFT", rx, -196)

    function p:Refresh()
        local scope = Scope()
        if self.scope ~= scope then
            self.scope, self.selected = scope, nil  -- other character: start at its newest period
        end
        if UI.focus then
            self.kind, self.selected = UI.focus.kind, UI.focus.key
            UI.focus = nil
        end
        local kind, mode = self.kind, 1
        for i, k in ipairs(HISTORY_KINDS) do if k == kind then mode = i end end
        self.mode:Select(mode)

        local periods = ns.Periods(scope, kind)
        if not self.selected and periods[1] then self.selected = periods[1].key end
        self.info:SetText(Plural(#periods, kind) .. " with sales")
        self.chart:SetData(ns.Series(scope, kind, HISTORY_BARS[mode]), function(s)
            self.selected = s.key
            self:Refresh()
        end, self.selected)
        self.periods:SetData(periods)

        local from = self.selected
        if not from then
            self.title:SetText("")
            self.summary:SetText("")
            self.zones:SetText("")
            self.items:SetData({}, true)
            return
        end
        local _, to = ns.PeriodBounds(kind, from)
        local sel
        for _, e in ipairs(periods) do
            if e.key == from then sel = e; break end
        end

        self.title:SetText(ns.FormatPeriod(kind, from))
        if sel then
            local bar = "  " .. DIM .. "|||r  "
            local text = ns.Money(sel.c) .. bar .. Plural(sel.n, "item") .. bar .. Plural(sel.v, "visit")
            if kind ~= "day" then text = text .. bar .. ns.Money(sel.c / sel.length, true) .. " / day" end
            self.summary:SetText(text)
        else
            self.summary:SetText(DIM .. "Nothing sold.|r")
        end

        local zones, parts = ns.ZoneTable(scope, from, to), {}
        for i = 1, math.min(#zones, 4) do
            parts[i] = format("%s %d%%", zones[i].zone, floor(zones[i].share * 100 + 0.5))
        end
        self.zones:SetText(#parts > 0 and ("Sold in: " .. table.concat(parts, ", ")) or "")
        self.items:SetData(ns.ItemTable(scope, from, to), true)
    end

    return p
end

----------------------------------------------------------------------------
-- 3. Items: leaderboard for a date range (all time by default)
----------------------------------------------------------------------------
UI.builders[3] = function(parent)
    local p = UI.NewPanel(parent)

    local search = UI.TryCreate("EditBox", "GreyGoldItemSearch", p, { "SearchBoxTemplate", "InputBoxTemplate" })
    search:SetSize(200, 20)
    search:SetPoint("TOPLEFT", 6, -2)
    search:SetAutoFocus(false)
    search:HookScript("OnTextChanged", function() p:Refresh() end)
    p.search = search

    p.range = NewRangeToggle(p, "itemRange")
    p.range:SetPoint("TOPLEFT", W - 272, -2)

    p.info = UI.Text(p, "GameFontHighlightSmall", nil, "RIGHT")
    p.info:SetPoint("BOTTOMRIGHT", -4, 2)

    p.list = UI.NewList(p, W, H - 50, {
        { title = "Item", width = 250, sort = "name", defaultAsc = true, icon = true, fmt = ItemLabel },
        { title = "Sold", width = 60, sort = "n", align = "RIGHT", fmt = function(e) return ns.Num(e.n) end },
        { title = "Total", width = 100, sort = "c", align = "RIGHT", fmt = function(e) return ns.Money(e.c, true) end },
        { title = "Each", width = 80, sort = "each", align = "RIGHT", fmt = function(e) return ns.Money(e.each) end },
        { title = "Last sold", width = 86, sort = "last", align = "RIGHT", fmt = function(e) return ns.RelativeDay(e.last) end },
    }, {
        sortCol = 3,
        emptyText = "No junk sold yet. Your leaderboard will fill up here.",
        onClick = function(e, button)
            if button == "RightButton" then ns.ToggleNeverSell(e.id) end
        end,
        tooltipExtra = function(tt, e) ItemTooltipExtra(tt, e, true) end,
    })
    p.list:SetPoint("TOPLEFT", 0, -28)

    local hint = UI.Text(p, "GameFontDisableSmall",
        "Shift-click to link  " .. DIM .. "|||r  Right-click to protect", "LEFT")
    hint:SetPoint("BOTTOMLEFT", 4, 2)

    function p:Refresh()
        local range = RangeChoice("itemRange")
        self.range:Select(range)
        self.list.empty:SetText(range == #RANGES and "No junk sold yet. Your leaderboard will fill up here."
            or "No junk sold in this period.")
        local all = ns.ItemTable(Scope(), ns.RangeFor(range))
        local q = strlower(strtrim(self.search:GetText() or ""))
        local list = all
        if q ~= "" then
            list = {}
            for _, e in ipairs(all) do
                if strlower(e.name):find(q, 1, true) then list[#list + 1] = e end
            end
        end
        local copper, units = 0, 0
        for _, e in ipairs(list) do copper, units = copper + e.c, units + e.n end
        self.info:SetText(format("%s  %s|||r  %s sold  %s|||r  %s", Plural(#list, "different item"), DIM,
            ns.Num(units), DIM, ns.Money(copper, true)))
        self.list:SetData(list)
    end

    return p
end

----------------------------------------------------------------------------
-- 4. Zones: where you farmed your junk (looted) or sold it (at the vendor)
----------------------------------------------------------------------------
UI.builders[4] = function(parent)
    local p = UI.NewPanel(parent)

    p.mode = UI.NewToggle(p, { "Farmed in", "Sold in", "Dropped by" }, function(i)
        ns.db.ui.zoneMode = i
        p:Refresh()
    end, 80)
    p.mode:SetPoint("TOPLEFT", 0, -2)
    p.range = NewRangeToggle(p, "zoneRange")
    p.range:SetPoint("TOPLEFT", W - 272, -2)

    p.info = UI.Text(p, "GameFontHighlightSmall", nil, "LEFT")
    p.info:SetPoint("BOTTOMLEFT", 4, 2)
    p.info:SetWidth(W - 8)
    p.info:SetWordWrap(false)

    local function Share(e) return floor(e.share * 100 + 0.5) .. "%" end

    p.farm = UI.NewList(p, W, H - 50, {
        { title = "Zone", width = 230, sort = "name", defaultAsc = true, fmt = function(e) return e.zone end },
        { title = "Gold", width = 110, sort = "c", align = "RIGHT", fmt = function(e) return ns.Money(e.c, true) end },
        { title = "Items", width = 60, sort = "n", align = "RIGHT", fmt = function(e) return ns.Num(e.n) end },
        { title = "Per item", width = 90, sort = "per", align = "RIGHT", fmt = function(e) return ns.Money(e.per) end },
        { title = "Share", width = 90, sort = "share", bar = true, align = "RIGHT", fmt = Share },
    }, {
        sortCol = 2,
        emptyText = "No farm zones yet.\nJunk you loot from 2.1.0 on is credited to the zone you looted it in.",
        tooltip = function(tt, e)
            tt:AddLine(e.zone, 1, 0.82, 0)
            tt:AddDoubleLine("Gold", ns.Money(e.c), 1, 1, 1, 1, 1, 1)
            tt:AddDoubleLine("Items", ns.Num(e.n), 1, 1, 1, 1, 1, 1)
            tt:AddDoubleLine("Average per item", ns.Money(e.per), 1, 1, 1, 1, 1, 1)
            tt:AddDoubleLine("Share of farmed junk gold", format("%.1f%%", e.share * 100), 1, 1, 1, 1, 1, 1)
            tt:AddLine("Junk you looted here (mobs, chests, fishing, containers), counted when it was sold.", 0.6, 0.6, 0.6, true)
        end,
    })
    p.farm:SetPoint("TOPLEFT", 0, -28)

    p.sold = UI.NewList(p, W, H - 50, {
        { title = "Zone", width = 230, sort = "name", defaultAsc = true, fmt = function(e) return e.zone end },
        { title = "Gold", width = 110, sort = "c", align = "RIGHT", fmt = function(e) return ns.Money(e.c, true) end },
        { title = "Visits", width = 60, sort = "v", align = "RIGHT", fmt = function(e) return ns.Num(e.v) end },
        { title = "Per visit", width = 90, sort = "per", align = "RIGHT", fmt = function(e) return ns.Money(e.per, true) end },
        { title = "Share", width = 90, sort = "share", bar = true, align = "RIGHT", fmt = Share },
    }, {
        sortCol = 2,
        emptyText = "No zones yet. Sell some junk!",
        tooltip = function(tt, e)
            tt:AddLine(e.zone, 1, 0.82, 0)
            tt:AddDoubleLine("Gold", ns.Money(e.c), 1, 1, 1, 1, 1, 1)
            tt:AddDoubleLine("Vendor visits", ns.Num(e.v), 1, 1, 1, 1, 1, 1)
            tt:AddDoubleLine("Average per visit", ns.Money(e.per), 1, 1, 1, 1, 1, 1)
            tt:AddDoubleLine("Share of all junk gold", format("%.1f%%", e.share * 100), 1, 1, 1, 1, 1, 1)
            tt:AddLine("The zone you were in at the vendor.", 0.6, 0.6, 0.6, true)
        end,
    })
    p.sold:SetPoint("TOPLEFT", 0, -28)

    p.drops = UI.NewList(p, W, H - 50, {
        { title = "Dropped by", width = 230, sort = "name", defaultAsc = true, fmt = function(e) return e.name end },
        { title = "Gold", width = 110, sort = "c", align = "RIGHT", fmt = function(e) return ns.Money(e.c, true) end },
        { title = "Items", width = 60, sort = "n", align = "RIGHT", fmt = function(e) return ns.Num(e.n) end },
        { title = "Per item", width = 90, sort = "per", align = "RIGHT", fmt = function(e) return ns.Money(e.per) end },
        { title = "Share", width = 90, sort = "share", bar = true, align = "RIGHT", fmt = Share },
    }, {
        sortCol = 2,
        emptyText = "Nothing here yet.\nJunk you loot and sell from 2.2.0 on is counted for the mob, chest or catch it came from.",
        tooltip = function(tt, e)
            tt:AddLine(e.name, 1, 0.82, 0)
            tt:AddDoubleLine("Gold", ns.Money(e.c), 1, 1, 1, 1, 1, 1)
            tt:AddDoubleLine("Junk items", ns.Num(e.n), 1, 1, 1, 1, 1, 1)
            tt:AddDoubleLine("Average per item", ns.Money(e.per), 1, 1, 1, 1, 1, 1)
            tt:AddDoubleLine("Share of looted junk gold", format("%.1f%%", e.share * 100), 1, 1, 1, 1, 1, 1)
            tt:AddLine("Counted when the junk was sold. These totals are kept per month, forever.", 0.6, 0.6, 0.6, true)
        end,
    })
    p.drops:SetPoint("TOPLEFT", 0, -28)

    function p:Refresh()
        local scope, mode, range = Scope(), ns.db.ui.zoneMode or 1, RangeChoice("zoneRange")
        self.mode:Select(mode)
        self.range:Select(range)
        local from, to = ns.RangeFor(range)
        local farm = mode == 1
        self.farm:SetShown(farm)
        self.sold:SetShown(mode == 2)
        self.drops:SetShown(mode == 3)
        if mode == 3 then
            local list, total = ns.SourceTable(scope, from, to)
            local text = format("%s  %s|||r  %s", Plural(#list, "source"), DIM, ns.Money(total, true))
            if from then  -- name the months really shown: a week or 30 days can span two or three
                local span = ns.FormatMonth(to)
                if from:sub(1, 7) == to:sub(1, 7) then
                    span = "all of " .. span
                else
                    span = ns.FormatMonth(from) .. " to " .. span
                end
                text = text .. "  " .. DIM .. "|||r  counted per month: showing " .. span
            end
            self.drops:SetData(list)
            self.info:SetText(text)
            return
        end
        local list, total = ns.ZoneTable(scope, from, to, farm and "farm" or nil)
        local text = format("%s  %s|||r  %s", Plural(#list, "zone"), DIM, ns.Money(total, true))
        if farm then
            local other = ns.UncreditedTotal(scope, from, to)
            if other > 0 then
                text = text .. format("  %s|||r  %s not looted by you: mail, trade, bank, other (no zone credit)",
                    DIM, ns.Money(other, true))
            end
            self.farm:SetData(list)
        else
            self.sold:SetData(list)
        end
        self.info:SetText(text)
    end

    return p
end

----------------------------------------------------------------------------
-- 5. Log: every sale, with where and when the junk was found
----------------------------------------------------------------------------
local LOG_SHOWN = 500  -- rows built at most (the list has no virtual scrolling)

local function LogSource(e)
    if not e.row.k then return DIM .. e.src .. "|r" end
    return e.src
end

local NOTE_COLOR = { ["Bought back"] = "|cffff9040", ["By hand"] = "|cffb0b0b0" }

local function LogNoteText(e)
    if e.note == "" then return "" end
    return (NOTE_COLOR[e.note] or "|cff40c0ff") .. e.note .. "|r"
end

local function LogTooltip(tt, e)
    local r = e.row
    local Y, Wh = { 1, 0.82, 0 }, { 1, 1, 1 }
    local function Line(label, value)
        tt:AddDoubleLine(label, value, Y[1], Y[2], Y[3], Wh[1], Wh[2], Wh[3])
    end
    tt:AddLine(" ")
    Line("Sold", ns.FormatStamp(r.t) .. (r.m and "  (by hand)" or ""))
    Line("Sold in", r.z or "?")
    Line("Quantity", ns.Num(r.n))
    Line("Gold", ns.Money(r.c))
    tt:AddLine(" ")
    if not r.k then
        Line("Came from", DIM .. "unknown|r")
        tt:AddLine("It was already in your bags when tracking began (Grey Gold 2.1.0).", 0.6, 0.6, 0.6, true)
    elseif ns.FARM_KINDS[r.k] then
        Line("Looted from", e.src)
        if r.lz then Line("Looted in", r.lz) end
        if r.lt then Line("Looted", ns.FormatStamp(r.lt)) end
    else
        Line("Came from", e.src)
        if r.lz then Line("Received in", r.lz) end
        if r.lt then Line("Received", ns.FormatStamp(r.lt)) end
        tt:AddLine("Not looted by you, so no farm-zone credit.", 0.6, 0.6, 0.6, true)
    end
    if r.rb and r.rb > 0 then
        tt:AddLine(format("You bought it back and sold it again (%s).", Plural(r.rb, "time")), 0.25, 0.75, 1, true)
    end
    if r.bb then
        tt:AddLine("Bought back " .. ns.FormatStamp(r.bb) .. ". Not counted in your totals.", 1, 0.56, 0.25, true)
    end
    if Scope() == "ALL" then Line("Character", ns.CharLabel(e.char)) end
    tt:AddLine("Right-click to toggle never-sell", 0.6, 0.6, 0.6)
end

UI.builders[5] = function(parent)
    local p = UI.NewPanel(parent)

    local search = UI.TryCreate("EditBox", "GreyGoldLogSearch", p, { "SearchBoxTemplate", "InputBoxTemplate" })
    search:SetSize(200, 20)
    search:SetPoint("TOPLEFT", 6, -2)
    search:SetAutoFocus(false)
    search:HookScript("OnTextChanged", function() p:Refresh() end)
    p.search = search

    p.info = UI.Text(p, "GameFontHighlightSmall", nil, "RIGHT")
    p.info:SetPoint("TOPRIGHT", -4, -6)

    p.list = UI.NewList(p, W, H - 50, {
        { title = "When", width = 104, sort = "t", fmt = function(e) return ns.FormatTime(e.t) end },
        { title = "Item", width = 168, sort = "name", defaultAsc = true, icon = true, fmt = ItemLabel },
        { title = "Qty", width = 34, sort = "n", align = "RIGHT", fmt = function(e) return ns.Num(e.n) end },
        { title = "Gold", width = 72, sort = "c", align = "RIGHT", fmt = function(e)
            local m = ns.Money(e.c)
            return e.row.bb and (DIM .. m .. "|r") or m
        end },
        { title = "From", width = 144, sort = "src", defaultAsc = true, fmt = LogSource },
        { title = "Note", width = 62, sort = "note", fmt = LogNoteText },
    }, {
        sortCol = 1,
        emptyText = "No sales logged yet.\nThe log starts with Grey Gold 2.1.0: sell some junk and it shows up here.",
        onClick = function(e, button)
            if button == "RightButton" then ns.ToggleNeverSell(e.id) end
        end,
        tooltipExtra = LogTooltip,
    })
    p.list:SetPoint("TOPLEFT", 0, -28)

    local hint = UI.Text(p, "GameFontDisableSmall",
        "Search by item or source  " .. DIM .. "|||r  Hover a row for details  " .. DIM .. "|||r  Shift-click to link  "
        .. DIM .. "|||r  Right-click to protect", "LEFT")
    hint:SetPoint("BOTTOMLEFT", 4, 2)

    function p:Refresh()
        local q = strlower(strtrim(self.search:GetText() or ""))
        local list = {}
        local copper = 0
        for _, e in ipairs(ns.LogEntries(Scope())) do
            if q == "" or strlower(e.name):find(q, 1, true) or strlower(e.src):find(q, 1, true) then
                list[#list + 1] = e
                if not e.row.bb then copper = copper + e.c end
            end
        end
        local total = #list
        for i = LOG_SHOWN + 1, total do list[i] = nil end  -- newest first, so the oldest go
        local shown = total > LOG_SHOWN and format("Showing newest %s of %s", ns.Num(LOG_SHOWN), Plural(total, "sale"))
            or Plural(total, "sale")
        self.info:SetText(format("%s  %s|||r  %s", shown, DIM, ns.Money(copper, true)))
        self.list:SetData(list)
    end

    return p
end

----------------------------------------------------------------------------
-- 6. Settings: options, never-sell list, about, reset
----------------------------------------------------------------------------
StaticPopupDialogs["GREYGOLD_RESET"] = {
    text = "Delete all " .. ns.TITLE .. " history for %s?\n\nThis cannot be undone.",
    button1 = YES or "Yes",
    button2 = NO or "No",
    OnAccept = function()
        if UI.pendingReset then
            ns.ResetHistory(UI.pendingReset)
            ns.Print("history cleared.")
            UI.pendingReset = nil
        end
    end,
    OnCancel = function() UI.pendingReset = nil end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    showAlert = true,
    preferredIndex = 3,
}

local function AcceptCursorItem()
    local kind, id, link = GetCursorInfo()
    if kind ~= "item" or not id then return end
    ClearCursor()
    if not ns.db.neverSell[id] then ns.ToggleNeverSell(id, link and link:match("%[(.-)%]")) end
end

local ABOUT = table.concat({
    "|cffffd100" .. ns.TITLE .. "|r v%s",
    "",
    "Every item with the coin icon (grey quality with a sell value) is sold the moment you open any vendor, in quick batches. Selling stops as soon as the vendor window closes.",
    "",
    "|cffffd100Hold Shift|r while opening a vendor to skip selling once.",
    "",
    "|cffffd100Commands|r",
    "/greygold  " .. DIM .. "open this window|r",
    "/greygold toggle  " .. DIM .. "auto-sell on/off|r",
    "/greygold sell  " .. DIM .. "sell now (vendor open)|r",
    "/greygold keep <item>  " .. DIM .. "protect / unprotect|r",
    "/greygold quiet  " .. DIM .. "chat summary on/off|r",
    "/greygold minimap  " .. DIM .. "show/hide the button|r",
    "/greygold help  " .. DIM .. "list commands in chat|r",
    DIM .. "/junk works as a shortcut for /greygold.|r",
}, "\n")

UI.builders[ns.TAB_SETTINGS] = function(parent)
    local p = UI.NewPanel(parent)
    local lw = 290

    local h1 = UI.Header(p, "Options", lw)
    h1:SetPoint("TOPLEFT", 2, -2)
    p.checks = {
        UI.NewCheck(p, "Auto-sell junk at vendors",
            "Sell every grey item with a sell value as soon as you open a vendor. Hold Shift while opening a vendor to skip once.",
            function() return ns.db.enabled end, function(v) ns.SetEnabled(v) end),
        UI.NewCheck(p, "Chat summary after selling",
            "Print how many items were sold and for how much.",
            function() return ns.db.summary end, function(v) ns.db.summary = v; ns.Notify("settings") end),
        UI.NewCheck(p, "Achievement announcements",
            "Announce (with a coin sound) each junk milestone: 10s, 50s, 1g, 2g, 5g and on up to 200g, then every 100g. See them all with the Achievements button on the Overview.",
            function() return ns.db.milestones end, function(v) ns.db.milestones = v end),
        UI.NewCheck(p, "Show minimap button",
            "Drag it around the minimap edge to move it. You can always open this window with /greygold (or /junk).",
            function() return not ns.db.minimap.hide end, function(v) ns.SetMinimapShown(v) end),
        UI.NewCheck(p, "Bags full: suggest junk to delete",
            "When your bags fill up, a chat line names your cheapest junk stack so you can make room. Nothing is ever deleted for you.",
            function() return ns.db.suggest end, function(v) ns.db.suggest = v end),
        UI.NewCheck(p, "Junk value next to the default backpack",
            "A small label next to the default backpack shows the junk in your bags. Bag addons like Bagnon can show the same thing in their data bar instead (pick \"Grey Gold\" there).",
            function() return ns.db.bagLabel end, function(v) ns.db.bagLabel = v; ns.Notify("bags") end),
    }
    for i, cb in ipairs(p.checks) do cb:SetPoint("TOPLEFT", 0, -22 - (i - 1) * 28) end

    local h2 = UI.Header(p, "Never sell", lw)
    h2:SetPoint("TOPLEFT", 2, -202)
    local slot = CreateFrame("Button", nil, p)
    slot:SetSize(36, 36)
    slot:SetPoint("TOPLEFT", 2, -224)
    local slotTex = slot:CreateTexture(nil, "BACKGROUND")
    slotTex:SetAllPoints()
    slotTex:SetTexture("Interface\\PaperDoll\\UI-Backpack-EmptySlot")
    local slotHl = slot:CreateTexture(nil, "HIGHLIGHT")
    slotHl:SetAllPoints()
    slotHl:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
    slotHl:SetBlendMode("ADD")
    slot:SetScript("OnReceiveDrag", AcceptCursorItem)
    slot:SetScript("OnClick", AcceptCursorItem)
    slot:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Never-sell slot", 1, 0.82, 0)
        GameTooltip:AddLine("Drop an item from your bags here to protect it from auto-selling.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    slot:SetScript("OnLeave", UI.HideTooltip)
    local hint = UI.Text(p, "GameFontHighlightSmall",
        "Drag a grey item onto the slot to protect it. Right-click an item in the list (or in the Items tab) to toggle it.", "LEFT")
    hint:SetPoint("TOPLEFT", slot, "TOPRIGHT", 8, 0)
    hint:SetWidth(lw - 48)

    p.keep = UI.NewList(p, lw, H - 268, {
        { title = "Protected items", width = lw - 28, sort = "name", defaultAsc = true, icon = true,
          fmt = function(e) return GREY .. e.name .. "|r" end },
    }, {
        sortCol = 1,
        emptyText = "Nothing protected.",
        onClick = function(e, button)
            if button == "RightButton" then ns.ToggleNeverSell(e.id) end
        end,
        tooltipExtra = function(tt) tt:AddLine("Right-click to remove", 0.6, 0.6, 0.6) end,
    })
    p.keep:SetPoint("TOPLEFT", 0, -268)

    local rx, rw = lw + 24, W - lw - 24
    local h3 = UI.Header(p, "About", rw)
    h3:SetPoint("TOPLEFT", rx, -2)
    local about = UI.Text(p, "GameFontHighlightSmall", format(ABOUT, ns.VERSION), "LEFT")
    about:SetPoint("TOPLEFT", rx, -24)
    about:SetWidth(rw)
    about:SetJustifyV("TOP")
    about:SetSpacing(2)

    p.footprint = UI.Text(p, "GameFontDisableSmall", nil, "LEFT")
    p.footprint:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", rx, 34)
    p.footprint:SetWidth(rw)

    p.reset = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    p.reset:SetSize(170, 22)
    p.reset:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", rx, 4)
    p.reset:SetScript("OnClick", function()
        UI.pendingReset = Scope()
        StaticPopup_Show("GREYGOLD_RESET", ns.ScopeLabel(UI.pendingReset))
    end)

    function p:Refresh()
        for _, cb in ipairs(self.checks) do cb:Refresh() end
        local list = {}
        for id in pairs(ns.db.neverSell) do list[#list + 1] = { id = id, name = ns.ItemName(id) } end
        self.keep:SetData(list)
        local chars, days, items = ns.Footprint()
        self.footprint:SetText(format("Tracking %s, %s and %s.",
            Plural(days, "day"), Plural(chars, "character"), Plural(items, "different item")))
        self.reset:SetText(Scope() == "ALL" and "Reset all history..." or "Reset shown character...")
    end

    return p
end

----------------------------------------------------------------------------
-- Achievements window (opened from the Overview), docked to the main window
----------------------------------------------------------------------------
local PARCHMENT = "Interface\\AchievementFrame\\UI-Achievement-Parchment-Horizontal"

local function AchStatus(e)
    if e.reached then
        return e.t and ns.FormatStamp(e.t) or "Reached"
    elseif e.isNext then
        return ns.Money(math.max(0, e.goal - e.current), true) .. " to go"
    end
    return "Not yet"
end

local function AchTooltip(card)
    local e = card.item
    if not e then return end
    GameTooltip:SetOwner(card, "ANCHOR_RIGHT")
    GameTooltip:AddLine(e.name, 1, 0.82, 0)
    if e.flavor then GameTooltip:AddLine("\"" .. e.flavor .. "\"", 0.9, 0.8, 0.6, true) end
    if e.desc then GameTooltip:AddLine(e.desc, 1, 1, 1, true) end
    GameTooltip:AddLine(" ")
    if e.reached then
        GameTooltip:AddDoubleLine("Reached", e.t and ns.FormatStamp(e.t) or "before version 2.2.0", 1, 0.82, 0, 1, 1, 1)
        if e.who then GameTooltip:AddDoubleLine("By", ns.CharLabel(e.who), 1, 0.82, 0, 1, 1, 1) end
    elseif e.category == "Gold" then
        GameTooltip:AddDoubleLine("Progress", ns.Money(e.current, true) .. " of " .. ns.Money(e.goal), 1, 0.82, 0, 1, 1, 1)
    else
        GameTooltip:AddDoubleLine("Progress", ns.Num(e.current) .. " of " .. ns.Num(e.goal), 1, 0.82, 0, 1, 1, 1)
    end
    GameTooltip:Show()
end

-- One achievement card: parchment, icon, name, status line, check mark, progress strip.
local function BuildAchCard(card)
    local w = card:GetWidth()
    local bg = card:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.1, 0.08, 0.06, 0.9)  -- stays visible if the parchment art is missing
    card.paper = card:CreateTexture(nil, "BORDER")
    card.paper:SetPoint("TOPLEFT", 1, -1)
    card.paper:SetPoint("BOTTOMRIGHT", -1, 1)
    card.paper:SetTexture(PARCHMENT)
    card.paper:SetTexCoord(0, 1, 0, 0.3)

    for _, edge in ipairs({ { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true } }) do
        local line = card:CreateTexture(nil, "ARTWORK")
        line:SetColorTexture(0.55, 0.45, 0.25, 0.9)
        line:SetHeight(1)
        line:SetPoint(edge[1]); line:SetPoint(edge[2])
    end

    card.icon = card:CreateTexture(nil, "ARTWORK")
    card.icon:SetSize(30, 30)
    card.icon:SetPoint("LEFT", 6, 0)
    card.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    card.name = UI.Text(card, "GameFontNormal", nil, "LEFT")
    card.name:SetPoint("TOPLEFT", 44, -6)
    card.name:SetWidth(w - 44 - 28 - 78)
    card.name:SetWordWrap(false)
    card.amount = UI.Text(card, "GameFontHighlightSmall", nil, "RIGHT")  -- "10g" beside the title
    card.amount:SetPoint("TOPRIGHT", -30, -8)
    card.amount:SetWidth(76)
    card.amount:SetWordWrap(false)
    card.status = UI.Text(card, "GameFontHighlightSmall", nil, "LEFT")
    card.status:SetPoint("BOTTOMLEFT", 44, 8)
    card.status:SetWidth(w - 44 - 28)
    card.status:SetWordWrap(false)

    card.check = card:CreateTexture(nil, "OVERLAY")
    card.check:SetSize(20, 20)
    card.check:SetPoint("RIGHT", -6, 0)
    card.check:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")

    card.barBg = card:CreateTexture(nil, "ARTWORK")
    card.barBg:SetColorTexture(0, 0, 0, 0.6)
    card.barBg:SetHeight(3)
    card.barBg:SetPoint("BOTTOMLEFT", 44, 3)
    card.barBg:SetWidth(w - 44 - 28)
    card.bar = card:CreateTexture(nil, "OVERLAY")
    card.bar:SetColorTexture(1, 0.82, 0.1, 1)
    card.bar:SetHeight(3)
    card.bar:SetPoint("BOTTOMLEFT", card.barBg, "BOTTOMLEFT")
    card.barMax = w - 44 - 28

    card:EnableMouse(true)
    card:SetScript("OnEnter", AchTooltip)
    card:SetScript("OnLeave", UI.HideTooltip)
end

local function PaintAchCard(card, e)
    card.icon:SetTexture(e.icon or ns.ICON)
    card.name:SetText(e.name)
    card.amount:SetText(e.amount or "")
    card.amount:SetAlpha(e.reached and 1 or 0.6)
    card.status:SetText(AchStatus(e))
    card.check:SetShown(e.reached)
    card.icon:SetDesaturated(not e.reached)
    card.paper:SetDesaturated(not e.reached)
    if e.reached then
        card.paper:SetVertexColor(0.62, 0.5, 0.36)   -- warm, darkened so light text stays readable
        card.icon:SetVertexColor(1, 1, 1)
        card.name:SetTextColor(1, 0.82, 0)
        card.status:SetTextColor(1, 1, 1)
    elseif e.isNext then
        card.paper:SetVertexColor(0.34, 0.34, 0.34)
        card.icon:SetVertexColor(0.8, 0.8, 0.8)
        card.name:SetTextColor(0.9, 0.9, 0.9)
        card.status:SetTextColor(0.78, 0.63, 0.31)
    else
        card.paper:SetVertexColor(0.2, 0.2, 0.2)
        card.icon:SetVertexColor(0.5, 0.5, 0.5)
        card.name:SetTextColor(0.55, 0.55, 0.55)
        card.status:SetTextColor(0.45, 0.45, 0.45)
    end
    -- The next one shows how far along you are; the status text moves up to make room.
    local showBar = e.isNext and e.goal > 0
    card.barBg:SetShown(showBar)
    card.bar:SetShown(showBar)
    if showBar then
        card.bar:SetWidth(math.max(1, card.barMax * math.min(1, e.current / e.goal)))
    end
    card.status:ClearAllPoints()
    card.status:SetPoint("BOTTOMLEFT", 44, showBar and 10 or 8)
end

local function BuildAchievements()
    local f = UI.frame
    local w, template = UI.TryCreate("Frame", "GreyGoldAchievementsFrame", f, { "BasicFrameTemplateWithInset" })
    w:SetSize(330, 420)
    w:SetPoint("TOPLEFT", f, "TOPRIGHT", 2, -18)
    w:EnableMouse(true)
    if template then
        if w.SetTitle then
            w:SetTitle("Achievements")
        else
            local title = w.TitleText or (w.TitleContainer and w.TitleContainer.TitleText)
            if title then title:SetText("Achievements") end
        end
    else
        -- This client has no such template: draw a plain framed box with its own title and close button.
        local box = UI.Box(w, 330, 420)
        box:SetAllPoints()
        box:SetFrameLevel(w:GetFrameLevel())
        local title = UI.Text(w, "GameFontNormal", "Achievements")
        title:SetPoint("TOP", 0, -8)
        local close = UI.TryCreate("Button", nil, w, { "UIPanelCloseButton" })
        close:SetSize(24, 24)
        close:SetPoint("TOPRIGHT", -2, -2)
        close:SetScript("OnClick", function() w:Hide() end)
    end

    -- Summary: "6 of 15" over a gold progress bar.
    w.count = UI.Text(w, "GameFontNormal", nil, "LEFT")
    w.count:SetPoint("TOPLEFT", 14, -34)
    w.total = UI.Text(w, "GameFontHighlightSmall", nil, "RIGHT")
    w.total:SetPoint("TOPRIGHT", -16, -36)
    local barBg = w:CreateTexture(nil, "ARTWORK")
    barBg:SetColorTexture(0, 0, 0, 0.6)
    barBg:SetSize(300, 8)
    barBg:SetPoint("TOPLEFT", 14, -54)
    w.bar = w:CreateTexture(nil, "OVERLAY")
    w.bar:SetColorTexture(0.85, 0.65, 0.13, 1)
    w.bar:SetHeight(8)
    w.bar:SetPoint("TOPLEFT", barBg, "TOPLEFT")

    -- Category buttons only when there is more than one category to switch between.
    local cats = ns.AchievementCategories()
    w.category = cats[1]
    local top = -70
    if #cats > 1 then
        w.tabs = UI.NewToggle(w, cats, function(i)
            w.category = cats[i]
            w:Refresh()
        end, 70)
        w.tabs:SetPoint("TOPLEFT", 12, -68)
        top = -94
    end

    w.list = UI.NewCardList(w, 310, 420 + top - 12, 48, BuildAchCard, PaintAchCard)
    w.list:SetPoint("TOPLEFT", 12, top)

    function w:Refresh()
        local rows, reached = ns.AchievementList(self.category)
        for _, e in ipairs(rows) do
            if not e.reached then e.isNext = true; break end
        end
        if self.tabs then
            for i, c in ipairs(cats) do
                if c == self.category then self.tabs:Select(i) end
            end
        end
        self.count:SetText(format("%s of %s reached", ns.Num(reached), ns.Num(#rows)))
        self.total:SetText("Lifetime junk gold: " .. ns.Money(ns.LifetimeCopper(), true))
        self.bar:SetWidth(math.max(1, 300 * (#rows > 0 and reached / #rows or 0)))
        self.list:SetData(rows)
    end

    w:Hide()
    UI.achievements = w
    return w
end

function UI.ToggleAchievements()
    if not UI.frame then return end
    local w = UI.achievements or BuildAchievements()
    if w:IsShown() then
        w:Hide()
    else
        w:Show()
        w:Refresh()
    end
end

----------------------------------------------------------------------------
-- Esc > Options > AddOns > Grey Gold
----------------------------------------------------------------------------
ns.RegisterCallback(function(kind)
    if kind ~= "init" then return end
    local panel = CreateFrame("Frame")
    panel.name = ns.TITLE
    local title = UI.Text(panel, "GameFontNormalLarge", ns.TITLE, "LEFT")
    title:SetPoint("TOPLEFT", 16, -16)
    local desc = UI.Text(panel, "GameFontHighlight",
        "Automatically sells every junk (coin-icon) item when you open a vendor, and keeps a history of what you earned.\n\nVersion " .. ns.VERSION, "LEFT")
    desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    desc:SetWidth(560)
    local open = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    open:SetSize(180, 24)
    open:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -14)
    open:SetText("Open " .. ns.TITLE)
    open:SetScript("OnClick", function()
        if SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
        ns.ShowWindow(ns.TAB_SETTINGS)
    end)

    if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
        local category = Settings.RegisterCanvasLayoutCategory(panel, ns.TITLE)
        Settings.RegisterAddOnCategory(category)
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
    end
end)
