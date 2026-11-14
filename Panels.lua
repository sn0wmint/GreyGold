-- Junk Seller: the five tabs of the stats window, plus the small entry in
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

    local title = UI.Header(p, "Gold per day", W - 150)
    title:SetPoint("TOPLEFT", 2, -76)
    p.range = UI.NewToggle(p, { "14 days", "30 days" }, function(i)
        ns.db.ui.overviewRange = i
        p:Refresh()
    end, 64)
    p.range:SetPoint("TOPRIGHT", p, "TOPRIGHT", -66, -72)
    p.chart = UI.NewChart(p, W, 136)
    p.chart:SetPoint("TOPLEFT", 0, -96)

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
                tt:AddLine("Click to open that week", 0.6, 0.6, 0.6)
            end,
            bw and function() UI.OpenHistory("week", bw.key) end)

        rec[3]:Set(haul and (ns.Money(haul.c, true) .. "  " .. DIM .. Plural(haul.n, "item") .. "|r"),
            haul and function(tt)
                tt:AddLine("Biggest single vendor visit", 1, 0.82, 0)
                tt:AddDoubleLine("Gold", ns.Money(haul.c), 1, 1, 1, 1, 1, 1)
                tt:AddDoubleLine("Items", ns.Num(haul.n), 1, 1, 1, 1, 1, 1)
                tt:AddDoubleLine("Zone", haul.zone or "?", 1, 1, 1, 1, 1, 1)
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
UI.builders[2] = function(parent)
    local p = UI.NewPanel(parent)
    p.kind = "day"

    p.mode = UI.NewToggle(p, { "Daily", "Weekly" }, function(i)
        p.kind = (i == 2) and "week" or "day"
        p.selected = nil
        p:Refresh()
    end, 70)
    p.mode:SetPoint("TOPLEFT", 0, 0)
    p.info = UI.Text(p, "GameFontDisableSmall", nil, "RIGHT")
    p.info:SetPoint("TOPRIGHT", -4, -5)

    p.chart = UI.NewChart(p, W, 110)
    p.chart:SetPoint("TOPLEFT", 0, -26)

    local leftW = 236
    p.periods = UI.NewList(p, leftW, H - 146, {
        { title = "Date", width = 96, sort = "key", fmt = function(e)
            return e.kind == "week" and ("Wk " .. ns.FormatShort(e.key)) or ns.FormatDay(e.key)
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
            tt:AddLine(e.kind == "week" and (ns.FormatWeek(e.key) .. " - " .. ns.FormatShort(e.to)) or ns.FormatDay(e.key, true), 1, 0.82, 0)
            tt:AddDoubleLine("Gold", ns.Money(e.c), 1, 1, 1, 1, 1, 1)
            tt:AddDoubleLine("Items", ns.Num(e.n), 1, 1, 1, 1, 1, 1)
            tt:AddDoubleLine("Vendor visits", ns.Num(e.v), 1, 1, 1, 1, 1, 1)
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
        local week = self.kind == "week"
        self.mode:Select(week and 2 or 1)

        local periods = ns.Periods(scope, self.kind)
        if not self.selected and periods[1] then self.selected = periods[1].key end
        self.info:SetText(Plural(#periods, week and "week" or "day") .. " with sales")
        self.chart:SetData(ns.Series(scope, self.kind, week and 12 or 30), function(s)
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
        local to = week and ns.AddDays(from, 6) or from
        local sel
        for _, e in ipairs(periods) do
            if e.key == from then sel = e; break end
        end

        self.title:SetText(week and (ns.FormatWeek(from) .. " - " .. ns.FormatShort(to)) or ns.FormatDay(from, true))
        if sel then
            local bar = "  " .. DIM .. "|||r  "
            local text = ns.Money(sel.c) .. bar .. Plural(sel.n, "item") .. bar .. Plural(sel.v, "visit")
            if week then text = text .. bar .. ns.Money(sel.c / sel.length, true) .. " / day" end
            self.summary:SetText(text)
        else
            self.summary:SetText(DIM .. "Nothing sold.|r")
        end

        local zones, parts = ns.ZoneTable(scope, from, to), {}
        for i = 1, math.min(#zones, 4) do
            parts[i] = format("%s %d%%", zones[i].zone, floor(zones[i].share * 100 + 0.5))
        end
        self.zones:SetText(#parts > 0 and ("Zones: " .. table.concat(parts, ", ")) or "")
        self.items:SetData(ns.ItemTable(scope, from, to), true)
    end

    return p
end

----------------------------------------------------------------------------
-- 3. Items: all-time leaderboard
----------------------------------------------------------------------------
UI.builders[3] = function(parent)
    local p = UI.NewPanel(parent)

    local search = UI.TryCreate("EditBox", "JunkSellerItemSearch", p, { "SearchBoxTemplate", "InputBoxTemplate" })
    search:SetSize(200, 20)
    search:SetPoint("TOPLEFT", 6, -2)
    search:SetAutoFocus(false)
    search:HookScript("OnTextChanged", function() p:Refresh() end)
    p.search = search

    p.info = UI.Text(p, "GameFontHighlightSmall", nil, "RIGHT")
    p.info:SetPoint("TOPRIGHT", -4, -6)

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
        "Click a column to sort  " .. DIM .. "|||r  Shift-click to link in chat  " .. DIM .. "|||r  Right-click to protect from selling", "LEFT")
    hint:SetPoint("BOTTOMLEFT", 4, 2)

    function p:Refresh()
        local all = ns.ItemTable(Scope())
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
-- 4. Zones: where the junk money comes from
----------------------------------------------------------------------------
UI.builders[4] = function(parent)
    local p = UI.NewPanel(parent)

    local h = UI.Header(p, "Where your junk money comes from", W - 220)
    h:SetPoint("TOPLEFT", 2, -4)
    p.info = UI.Text(p, "GameFontHighlightSmall", nil, "RIGHT")
    p.info:SetPoint("TOPRIGHT", -4, -5)

    p.list = UI.NewList(p, W, H - 30, {
        { title = "Zone", width = 230, sort = "name", defaultAsc = true, fmt = function(e) return e.zone end },
        { title = "Gold", width = 110, sort = "c", align = "RIGHT", fmt = function(e) return ns.Money(e.c, true) end },
        { title = "Visits", width = 60, sort = "v", align = "RIGHT", fmt = function(e) return ns.Num(e.v) end },
        { title = "Per visit", width = 90, sort = "per", align = "RIGHT", fmt = function(e) return ns.Money(e.per, true) end },
        { title = "Share", width = 90, sort = "share", bar = true, align = "RIGHT", fmt = function(e)
            return floor(e.share * 100 + 0.5) .. "%"
        end },
    }, {
        sortCol = 2,
        emptyText = "No zones yet. Sell some junk!",
        tooltip = function(tt, e)
            tt:AddLine(e.zone, 1, 0.82, 0)
            tt:AddDoubleLine("Gold", ns.Money(e.c), 1, 1, 1, 1, 1, 1)
            tt:AddDoubleLine("Vendor visits", ns.Num(e.v), 1, 1, 1, 1, 1, 1)
            tt:AddDoubleLine("Average per visit", ns.Money(e.per), 1, 1, 1, 1, 1, 1)
            tt:AddDoubleLine("Share of all junk gold", format("%.1f%%", e.share * 100), 1, 1, 1, 1, 1, 1)
        end,
    })
    p.list:SetPoint("TOPLEFT", 0, -30)

    function p:Refresh()
        local list, total = ns.ZoneTable(Scope())
        self.info:SetText(format("%s  %s|||r  %s", Plural(#list, "zone"), DIM, ns.Money(total, true)))
        self.list:SetData(list)
    end

    return p
end

----------------------------------------------------------------------------
-- 5. Settings: options, never-sell list, about, reset
----------------------------------------------------------------------------
StaticPopupDialogs["JUNKSELLER_RESET"] = {
    text = "Delete all Junk Seller history for %s?\n\nThis cannot be undone.",
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
    "|cffffd100Junk Seller|r v%s",
    "",
    "Every item with the coin icon (grey quality with a sell value) is sold the moment you open any vendor, in quick batches. Selling stops as soon as the vendor window closes.",
    "",
    "|cffffd100Hold Shift|r while opening a vendor to skip selling once.",
    "",
    "|cffffd100Commands|r",
    "/junk  " .. DIM .. "open this window|r",
    "/junk toggle  " .. DIM .. "auto-sell on/off|r",
    "/junk sell  " .. DIM .. "sell now (vendor open)|r",
    "/junk keep <item>  " .. DIM .. "protect / unprotect|r",
    "/junk quiet  " .. DIM .. "chat summary on/off|r",
    "/junk minimap  " .. DIM .. "show/hide the button|r",
    "/junk help  " .. DIM .. "list commands in chat|r",
}, "\n")

UI.builders[5] = function(parent)
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
        UI.NewCheck(p, "Milestone celebrations",
            "Announce (with a coin sound) when your lifetime junk gold passes 10g, 25g, 50g, 100g and beyond.",
            function() return ns.db.milestones end, function(v) ns.db.milestones = v end),
        UI.NewCheck(p, "Show minimap button",
            "Drag it around the minimap edge to move it. You can always open this window with /junk.",
            function() return not ns.db.minimap.hide end, function(v) ns.SetMinimapShown(v) end),
    }
    for i, cb in ipairs(p.checks) do cb:SetPoint("TOPLEFT", 0, -22 - (i - 1) * 28) end

    local h2 = UI.Header(p, "Never sell", lw)
    h2:SetPoint("TOPLEFT", 2, -146)
    local slot = CreateFrame("Button", nil, p)
    slot:SetSize(36, 36)
    slot:SetPoint("TOPLEFT", 2, -168)
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

    p.keep = UI.NewList(p, lw, H - 212, {
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
    p.keep:SetPoint("TOPLEFT", 0, -212)

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
        StaticPopup_Show("JUNKSELLER_RESET", ns.ScopeLabel(UI.pendingReset))
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
-- Esc > Options > AddOns > Junk Seller
----------------------------------------------------------------------------
ns.RegisterCallback(function(kind)
    if kind ~= "init" then return end
    local panel = CreateFrame("Frame")
    panel.name = "Junk Seller"
    local title = UI.Text(panel, "GameFontNormalLarge", "Junk Seller", "LEFT")
    title:SetPoint("TOPLEFT", 16, -16)
    local desc = UI.Text(panel, "GameFontHighlight",
        "Automatically sells every junk (coin-icon) item when you open a vendor, and keeps a history of what you earned.\n\nVersion " .. ns.VERSION, "LEFT")
    desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    desc:SetWidth(560)
    local open = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    open:SetSize(180, 24)
    open:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -14)
    open:SetText("Open Junk Seller")
    open:SetScript("OnClick", function()
        if SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
        ns.ShowWindow(5)
    end)

    if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
        local category = Settings.RegisterCanvasLayoutCategory(panel, "Junk Seller")
        Settings.RegisterAddOnCategory(category)
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
    end
end)
