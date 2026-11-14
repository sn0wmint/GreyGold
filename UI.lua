-- Junk Seller: main window shell plus small reusable widgets
-- (stat tile, bar chart, sortable list, checkbox, toggle buttons).
-- Nothing here is built until the window is first opened.

local _, ns = ...

local UI = {}
ns.UI = UI

local W, H = 640, 480
UI.BODY_W, UI.BODY_H = 608, 392
UI.TABS = { "Overview", "History", "Items", "Zones", "Settings" }
UI.builders = {}  -- [tab] = function(parent) -> panel with :Refresh(); filled by Panels.lua
local panels = {}

local GOLD_R, GOLD_G, GOLD_B = 1, 0.82, 0

function UI.Sound(key)
    if SOUNDKIT and SOUNDKIT[key] then PlaySound(SOUNDKIT[key]) end
end

function UI.HideTooltip() GameTooltip:Hide() end

-- CreateFrame with the first template this client knows.
function UI.TryCreate(frameType, name, parent, templates)
    for _, template in ipairs(templates) do
        local ok, frame = pcall(CreateFrame, frameType, name, parent, template)
        if ok and frame then return frame, template end
    end
    return CreateFrame(frameType, name, parent), nil
end

function UI.Text(parent, font, text, justify)
    local fs = parent:CreateFontString(nil, "ARTWORK", font or "GameFontHighlight")
    if justify then fs:SetJustifyH(justify) end
    if text then fs:SetText(text) end
    return fs
end

function UI.NewPanel(parent)
    local p = CreateFrame("Frame", nil, parent)
    p:SetAllPoints()
    return p
end

-- Gold section title with a faint underline.
function UI.Header(parent, text, width)
    local fs = UI.Text(parent, "GameFontNormal", text, "LEFT")
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(GOLD_R, GOLD_G, GOLD_B, 0.25)
    line:SetHeight(1)
    line:SetWidth(width or 200)
    line:SetPoint("TOPLEFT", fs, "BOTTOMLEFT", 0, -3)
    return fs
end

local BOX = {
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

function UI.Box(parent, w, h)
    local f = CreateFrame("Frame", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    f:SetSize(w, h)
    if f.SetBackdrop then
        f:SetBackdrop(BOX)
        f:SetBackdropColor(0, 0, 0, 0.35)
        f:SetBackdropBorderColor(0.55, 0.45, 0.25, 0.9)
    end
    return f
end

----------------------------------------------------------------------------
-- Stat tile: label / big value / sub-line
----------------------------------------------------------------------------
function UI.NewTile(parent, w, h, label)
    local t = UI.Box(parent, w, h)
    t.label = UI.Text(t, "GameFontNormalSmall", label)
    t.label:SetPoint("TOP", 0, -8)
    t.value = UI.Text(t, "GameFontHighlightLarge")
    t.value:SetPoint("CENTER", 0, -1)
    t.sub = UI.Text(t, "GameFontDisableSmall")
    t.sub:SetPoint("BOTTOM", 0, 8)
    function t:Set(value, sub)
        self.value:SetText(value)
        self.sub:SetText(sub or "")
    end
    return t
end

----------------------------------------------------------------------------
-- Toggle group: a row of buttons where one is "selected" (highlight locked)
----------------------------------------------------------------------------
function UI.NewToggle(parent, labels, onSelect, width)
    local group = { buttons = {} }
    for i, label in ipairs(labels) do
        local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
        b:SetSize(width or 70, 20)
        b:SetText(label)
        if i > 1 then b:SetPoint("LEFT", group.buttons[i - 1], "RIGHT", 2, 0) end
        b:SetScript("OnClick", function()
            UI.Sound("U_CHAT_SCROLL_BUTTON")
            group:Select(i)
            onSelect(i)
        end)
        group.buttons[i] = b
    end
    function group:Select(i)
        self.selected = i
        for j, b in ipairs(self.buttons) do
            if j == i then b:LockHighlight() else b:UnlockHighlight() end
        end
    end
    function group:SetPoint(...) self.buttons[1]:SetPoint(...) end
    return group
end

----------------------------------------------------------------------------
-- Checkbox bound to a getter/setter
----------------------------------------------------------------------------
function UI.NewCheck(parent, label, tip, get, set)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(26, 26)
    local fs = cb.Text or cb.text
    if not fs then
        fs = UI.Text(cb, "GameFontHighlight")
        fs:SetPoint("LEFT", cb, "RIGHT", 2, 1)
    end
    fs:SetFontObject("GameFontHighlight")
    fs:SetText(label)
    cb:SetScript("OnClick", function(self)
        local on = self:GetChecked() and true or false
        UI.Sound(on and "IG_MAINMENU_OPTION_CHECKBOX_ON" or "IG_MAINMENU_OPTION_CHECKBOX_OFF")
        set(on)
    end)
    if tip then
        cb:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(label, 1, 1, 1)
            GameTooltip:AddLine(tip, GOLD_R, GOLD_G, GOLD_B, true)
            GameTooltip:Show()
        end)
        cb:SetScript("OnLeave", UI.HideTooltip)
    end
    function cb:Refresh() self:SetChecked(get() and true or false) end
    return cb
end

----------------------------------------------------------------------------
-- Bar chart. series = { { key, label, c, n, current, kind }, ... }
----------------------------------------------------------------------------
local PAD_TOP, PAD_BOTTOM, PAD_X = 18, 18, 8

local function BarEnter(self)
    local s = self.data
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    if s.kind == "week" then
        GameTooltip:AddLine(ns.FormatWeek(s.key) .. " - " .. ns.FormatShort(s.to), GOLD_R, GOLD_G, GOLD_B)
    else
        GameTooltip:AddLine(ns.FormatDay(s.key, true), GOLD_R, GOLD_G, GOLD_B)
    end
    GameTooltip:AddDoubleLine("Gold", ns.Money(s.c), 1, 1, 1, 1, 1, 1)
    GameTooltip:AddDoubleLine("Items sold", ns.Num(s.n), 1, 1, 1, 1, 1, 1)
    if self.chart.onClick then GameTooltip:AddLine("Click for details", 0.6, 0.6, 0.6) end
    GameTooltip:Show()
end

local function BarClick(self)
    if self.chart.onClick then
        UI.Sound("U_CHAT_SCROLL_BUTTON")
        self.chart.onClick(self.data)
    end
end

local function NewBar(chart)
    local b = CreateFrame("Button", nil, chart)
    b.chart = chart
    b.fill = b:CreateTexture(nil, "ARTWORK")
    b.fill:SetPoint("BOTTOMLEFT")
    b.fill:SetPoint("BOTTOMRIGHT")
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.08)
    b.label = UI.Text(chart, "GameFontDisableSmall")
    b.label:SetPoint("TOP", b, "BOTTOM", 0, -4)
    b:SetScript("OnEnter", BarEnter)
    b:SetScript("OnLeave", UI.HideTooltip)
    b:SetScript("OnClick", BarClick)
    return b
end

function UI.NewChart(parent, w, h)
    local c = UI.Box(parent, w, h)
    c.bars = {}
    local plotH = h - PAD_TOP - PAD_BOTTOM

    for _, frac in ipairs({ 1, 0.5 }) do  -- faint guide lines at peak and half
        local line = c:CreateTexture(nil, "BORDER")
        line:SetColorTexture(1, 1, 1, 0.06)
        line:SetHeight(1)
        line:SetPoint("BOTTOMLEFT", PAD_X, PAD_BOTTOM + plotH * frac)
        line:SetPoint("BOTTOMRIGHT", -PAD_X, PAD_BOTTOM + plotH * frac)
    end
    local base = c:CreateTexture(nil, "BORDER")
    base:SetColorTexture(GOLD_R, GOLD_G, GOLD_B, 0.3)
    base:SetHeight(1)
    base:SetPoint("BOTTOMLEFT", PAD_X, PAD_BOTTOM)
    base:SetPoint("BOTTOMRIGHT", -PAD_X, PAD_BOTTOM)

    c.peak = UI.Text(c, "GameFontDisableSmall", nil, "LEFT")
    c.peak:SetPoint("TOPLEFT", PAD_X + 2, -5)
    c.empty = UI.Text(c, "GameFontDisable", "Nothing sold in this period yet.")
    c.empty:SetPoint("CENTER", 0, 6)

    function c:SetData(series, onClick, selectedKey)
        self.onClick = onClick
        local n = #series
        local slot = (w - PAD_X * 2) / math.max(n, 1)
        local barW = math.max(2, floor(slot * 0.68))
        local labelEvery = slot < 15 and 2 or 1
        local peak = 0
        for i = 1, n do peak = math.max(peak, series[i].c) end

        for i = 1, math.max(n, #self.bars) do
            local b = self.bars[i]
            if i <= n then
                if not b then b = NewBar(self); self.bars[i] = b end
                local s = series[i]
                b.data = s
                b:ClearAllPoints()
                b:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", PAD_X + (i - 1) * slot + (slot - barW) / 2, PAD_BOTTOM)
                b:SetSize(barW, plotH)
                b.fill:SetHeight(peak > 0 and math.max(1, plotH * s.c / peak) or 1)
                if selectedKey and s.key == selectedKey then
                    b.fill:SetColorTexture(0.45, 0.8, 1, 1)
                elseif s.c == 0 then
                    b.fill:SetColorTexture(0.5, 0.5, 0.5, 0.35)
                elseif s.current then
                    b.fill:SetColorTexture(1, 0.82, 0.1, 1)
                else
                    b.fill:SetColorTexture(0.78, 0.58, 0.14, 0.95)
                end
                b.label:SetText(((n - i) % labelEvery == 0) and s.label or "")
                b:Show()
                b.label:Show()
            elseif b then
                b:Hide()
                b.label:Hide()
            end
        end
        self.peak:SetText(peak > 0 and ("peak " .. ns.ShortMoney(peak)) or "")
        self.empty:SetShown(peak == 0)
    end
    return c
end

----------------------------------------------------------------------------
-- Sortable scrolling list
-- columns = { { title, width, sort = field, defaultAsc, align, icon, bar, fmt = fn(item) } }
-- opts = { sortCol, sortAsc, emptyText, onClick(item, button), isSelected(item),
--          tooltip(tt, item), tooltipExtra(tt, item) }
----------------------------------------------------------------------------
local ROW_H = 18
local listCount = 0

local function RowEnter(self)
    local L, item = self.list, self.item
    if L.opts.tooltip then
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        L.opts.tooltip(GameTooltip, item)
        GameTooltip:Show()
    elseif item.id then
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetItemByID(item.id)
        if L.opts.tooltipExtra then L.opts.tooltipExtra(GameTooltip, item) end
        GameTooltip:Show()
    end
end

local function RowClick(self, button)
    local L, item = self.list, self.item
    if item.id and IsModifiedClick and IsModifiedClick("CHATLINK") then
        local link = ns.ItemLink(item.id)
        if link and HandleModifiedItemClick then HandleModifiedItemClick(link) end
        return
    end
    if L.opts.onClick then L.opts.onClick(item, button) end
end

local function CreateRow(L, i)
    local row = CreateFrame("Button", nil, L.content)
    row.list = L
    row:SetSize(L.innerW, ROW_H)
    row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    if i % 2 == 0 then
        local stripe = row:CreateTexture(nil, "BACKGROUND")
        stripe:SetAllPoints()
        stripe:SetColorTexture(1, 1, 1, 0.03)
    end
    row.sel = row:CreateTexture(nil, "BACKGROUND", nil, 1)
    row.sel:SetAllPoints()
    row.sel:SetColorTexture(0.45, 0.8, 1, 0.18)
    row.sel:Hide()
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.08)

    row.cells = {}
    for c, col in ipairs(L.columns) do
        local pad = 0
        if col.icon then
            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetSize(16, 16)
            row.icon:SetPoint("LEFT", col.x, 0)
            pad = 20
        end
        if col.bar then
            row.bar = row:CreateTexture(nil, "ARTWORK")
            row.bar:SetHeight(10)
            row.bar:SetPoint("LEFT", col.x, 0)
            row.bar:SetColorTexture(0.78, 0.58, 0.14, 0.9)
            row.barMax = col.width - 44
        end
        local fs = UI.Text(row, col.font or "GameFontHighlightSmall", nil, col.align or "LEFT")
        fs:SetPoint("LEFT", col.x + pad, 0)
        fs:SetWidth(col.width - pad - 6)
        fs:SetWordWrap(false)
        row.cells[c] = fs
    end

    row:SetScript("OnEnter", RowEnter)
    row:SetScript("OnLeave", UI.HideTooltip)
    row:SetScript("OnClick", RowClick)
    return row
end

function UI.NewList(parent, w, h, columns, opts)
    opts = opts or {}
    listCount = listCount + 1
    local L = CreateFrame("Frame", nil, parent)
    L:SetSize(w, h)
    L.columns, L.opts, L.rows, L.data = columns, opts, {}, {}
    L.sortCol, L.sortAsc = opts.sortCol, opts.sortAsc
    if L.sortAsc == nil then
        local first = columns[opts.sortCol or 0]
        L.sortAsc = (first and first.defaultAsc) or false
    end
    L.innerW = w - 24
    L.headers = {}

    local x = 4
    for i, col in ipairs(columns) do
        col.x = x
        local hb = CreateFrame("Button", nil, L)
        hb:SetSize(col.width, 18)
        hb:SetPoint("TOPLEFT", x, 0)
        hb.text = UI.Text(hb, "GameFontNormalSmall", col.title, col.align or "LEFT")
        hb.text:SetPoint("LEFT", col.icon and 20 or 0, 0)
        hb.text:SetWidth(col.width - (col.icon and 20 or 0) - 6)
        if col.sort then
            hb:SetScript("OnClick", function()
                if L.sortCol == i then
                    L.sortAsc = not L.sortAsc
                else
                    L.sortCol, L.sortAsc = i, col.defaultAsc or false
                end
                UI.Sound("U_CHAT_SCROLL_BUTTON")
                L:Render()
            end)
            local hl = hb:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints()
            hl:SetColorTexture(1, 1, 1, 0.06)
        end
        L.headers[i] = hb
        x = x + col.width
    end

    local line = L:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(GOLD_R, GOLD_G, GOLD_B, 0.2)
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", 0, -19)
    line:SetPoint("TOPRIGHT", -24, -19)

    local sf = CreateFrame("ScrollFrame", "JunkSellerList" .. listCount, L, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 0, -21)
    sf:SetPoint("BOTTOMRIGHT", -24, 0)
    sf.scrollBarHideable = true
    local content = CreateFrame("Frame", nil, sf)
    content:SetSize(L.innerW, 1)
    sf:SetScrollChild(content)
    L.scroll, L.content = sf, content

    L.empty = UI.Text(L, "GameFontDisable", opts.emptyText or "Nothing here yet.")
    L.empty:SetPoint("TOP", sf, "TOP", 0, -30)
    L.empty:SetWidth(L.innerW - 20)

    function L:Render()
        local data = self.data
        local col = self.columns[self.sortCol]
        if col and col.sort then
            local field, asc = col.sort, self.sortAsc
            sort(data, function(a, b)
                local p, q = a[field], b[field]
                if type(p) == "string" then p, q = p:lower(), q:lower() end
                if p == q then return (a.name or "") < (b.name or "") end
                if asc then return p < q end
                return p > q
            end)
        end
        for i, hb in ipairs(self.headers) do
            if i == self.sortCol then hb.text:SetTextColor(1, 1, 1) else hb.text:SetTextColor(GOLD_R, GOLD_G, GOLD_B) end
        end

        for i, item in ipairs(data) do
            local row = self.rows[i]
            if not row then row = CreateRow(self, i); self.rows[i] = row end
            row.item = item
            for c, def in ipairs(self.columns) do
                local v = def.fmt(item)
                row.cells[c]:SetText(v ~= nil and tostring(v) or "")
            end
            if row.icon then row.icon:SetTexture(item.icon or (item.id and ns.ItemIcon(item.id)) or 134400) end
            if row.bar then row.bar:SetWidth(math.max(1, (item.share or 0) * row.barMax)) end
            row.sel:SetShown(self.opts.isSelected and self.opts.isSelected(item) and true or false)
            row:Show()
        end
        for i = #data + 1, #self.rows do self.rows[i]:Hide() end
        self.content:SetHeight(math.max(1, #data * ROW_H))
        self.empty:SetShown(#data == 0)
    end

    function L:SetData(data, resetScroll)
        self.data = data or {}
        if resetScroll then self.scroll:SetVerticalScroll(0) end
        self:Render()
    end

    return L
end

----------------------------------------------------------------------------
-- Main window
----------------------------------------------------------------------------
local function SavePosition(f)
    local point, _, relPoint, x, y = f:GetPoint()
    ns.db.ui.point = { point, relPoint, x, y }
end

local function BuildScopePicker(f)
    local ok, dd = pcall(CreateFrame, "DropdownButton", nil, f, "WowStyle1DropdownTemplate")
    if ok and dd and dd.SetupMenu then
        dd:SetWidth(190)
        dd:SetPoint("TOPRIGHT", -12, -29)
        local function IsSelected(key) return ns.db.ui.scope == key end
        local function SetSelected(key)
            UI.pickingScope = true  -- the dropdown updates its own text after a pick
            UI.SetScope(key)
            UI.pickingScope = nil
        end
        dd:SetupMenu(function(_, root)
            root:CreateRadio("All characters", IsSelected, SetSelected, "ALL")
            for _, c in ipairs(ns.CharList()) do
                root:CreateRadio(ns.CharLabel(c.key), IsSelected, SetSelected, c.key)
            end
        end)
        f.scopeDropdown = dd
        return dd
    end
    -- Fallback for clients without the new menu system: click to cycle.
    local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    b:SetSize(190, 22)
    b:SetPoint("TOPRIGHT", -12, -30)
    b:SetScript("OnClick", function()
        local keys = { "ALL" }
        for _, c in ipairs(ns.CharList()) do keys[#keys + 1] = c.key end
        local idx = 1
        for i, k in ipairs(keys) do if k == ns.db.ui.scope then idx = i end end
        UI.SetScope(keys[idx % #keys + 1])
    end)
    f.scopeButton = b
    return b
end

function UI.Build()
    if UI.frame then return UI.frame end
    local f, template = UI.TryCreate("Frame", "JunkSellerFrame", UIParent,
        { "ButtonFrameTemplate", "PortraitFrameTemplate", "BasicFrameTemplateWithInset" })
    UI.frame = f
    f:Hide()
    f:SetSize(W, H)
    f:SetFrameStrata("HIGH")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePosition(self)
    end)
    local p = ns.db.ui.point
    f:ClearAllPoints()
    if p then f:SetPoint(p[1], UIParent, p[2], p[3], p[4]) else f:SetPoint("CENTER") end

    if f.SetTitle then
        f:SetTitle("Junk Seller")
    else
        local title = f.TitleText or (f.TitleContainer and f.TitleContainer.TitleText)
        if title then title:SetText("Junk Seller") end
    end
    if f.SetPortraitToAsset then
        f:SetPortraitToAsset(ns.ICON)
    elseif f.PortraitContainer and f.PortraitContainer.portrait then
        f.PortraitContainer.portrait:SetTexture(ns.ICON)
    elseif f.portrait and SetPortraitToTexture then
        SetPortraitToTexture(f.portrait, ns.ICON)
    end
    if template == "ButtonFrameTemplate" and ButtonFrameTemplate_HideButtonBar then
        pcall(ButtonFrameTemplate_HideButtonBar, f)
    end
    if UISpecialFrames then tinsert(UISpecialFrames, "JunkSellerFrame") end  -- Esc closes it
    f:HookScript("OnShow", function() UI.Sound("IG_CHARACTER_INFO_OPEN") end)
    f:HookScript("OnHide", function() UI.Sound("IG_CHARACTER_INFO_CLOSE") end)

    -- Header strip: status line + "Showing: <scope>" picker
    f.subtitle = UI.Text(f, "GameFontHighlightSmall", nil, "LEFT")
    f.subtitle:SetPoint("TOPLEFT", 66, -37)
    f.subtitle:SetWidth(300)  -- stops short of the "Showing:" picker
    f.subtitle:SetWordWrap(false)
    local picker = BuildScopePicker(f)
    local showing = UI.Text(f, "GameFontNormalSmall", "Showing:", "RIGHT")
    showing:SetPoint("RIGHT", picker, "LEFT", -6, 0)

    f.body = CreateFrame("Frame", nil, f)
    f.body:SetSize(UI.BODY_W, UI.BODY_H)
    f.body:SetPoint("TOPLEFT", 16, -70)

    f.Tabs = {}
    for i, name in ipairs(UI.TABS) do
        local tab = UI.TryCreate("Button", "JunkSellerFrameTab" .. i, f,
            { "PanelTabButtonTemplate", "CharacterFrameTabButtonTemplate" })
        tab:SetID(i)
        tab:SetText(name)
        if i == 1 then
            tab:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 11, 2)
        else
            tab:SetPoint("TOPLEFT", f.Tabs[i - 1], "TOPRIGHT", 1, 0)
        end
        tab:SetScript("OnClick", function(self)
            UI.Sound("IG_CHARACTER_INFO_TAB")
            UI.SelectTab(self:GetID())
        end)
        f.Tabs[i] = tab
    end
    if PanelTemplates_SetNumTabs then PanelTemplates_SetNumTabs(f, #UI.TABS) end
    return f
end

function UI.SelectTab(id)
    local f = UI.Build()
    if not (id and UI.builders[id]) then id = 1 end
    ns.db.ui.tab = id
    if PanelTemplates_SetTab then PanelTemplates_SetTab(f, id) end
    for i, panel in pairs(panels) do
        if i ~= id then panel:Hide() end
    end
    if not panels[id] then panels[id] = UI.builders[id](f.body) end
    panels[id]:Show()
    UI.Refresh()
end

function UI.SetScope(key)
    ns.db.ui.scope = key
    UI.Refresh()
end

function UI.Refresh()
    local f = UI.frame
    if not f or not f:IsShown() then return end
    local db = ns.db
    if db.ui.scope ~= "ALL" and not db.chars[db.ui.scope] then db.ui.scope = "ALL" end

    f.subtitle:SetText(format("Auto-sell %s     |cffffd100Account lifetime|r  %s",
        db.enabled and "|cff00ff00ON|r" or "|cffff4040OFF|r", ns.Money(ns.LifetimeCopper(), true)))

    -- Re-sync the picker only when the scope or the character list changed.
    local chars = 0
    for _ in pairs(db.chars) do chars = chars + 1 end
    local sig = db.ui.scope .. "#" .. chars
    if f.scopeSig ~= sig then
        f.scopeSig = sig
        if f.scopeButton then
            f.scopeButton:SetText(ns.ScopeLabel(db.ui.scope))
        elseif f.scopeDropdown and f.scopeDropdown.GenerateMenu and not UI.pickingScope then
            f.scopeDropdown:GenerateMenu()
        end
    end

    local panel = panels[db.ui.tab]
    if panel and panel:IsShown() and panel.Refresh then panel:Refresh() end
end

-- Jump from a chart/record to a specific day or week in History.
function UI.OpenHistory(kind, key)
    UI.focus = { kind = kind, key = key }
    ns.ShowWindow(2)
end

function ns.ShowWindow(tab)
    local f = UI.Build()
    f:Show()
    UI.SelectTab(tab or ns.db.ui.tab)
end

function ns.ToggleWindow(tab)
    if UI.frame and UI.frame:IsShown() then UI.frame:Hide() else ns.ShowWindow(tab) end
end

ns.RegisterCallback(function(kind)
    if kind == "data" or kind == "settings" then UI.Refresh() end
end)
