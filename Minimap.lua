-- Grey Gold: minimap button (drag it around the edge) and addon-compartment entry.

local ADDON, ns = ...

-- Which quadrants of each minimap shape are round, so the button hugs the edge
-- on square (e.g. ClassicUIForever) and partly-square minimaps too.
-- Quadrant order: bottom-right, bottom-left, top-right, top-left.
local SHAPES = {
    ["ROUND"]                 = { true,  true,  true,  true  },
    ["SQUARE"]                = { false, false, false, false },
    ["CORNER-TOPLEFT"]        = { false, false, false, true  },
    ["CORNER-TOPRIGHT"]       = { false, false, true,  false },
    ["CORNER-BOTTOMLEFT"]     = { false, true,  false, false },
    ["CORNER-BOTTOMRIGHT"]    = { true,  false, false, false },
    ["SIDE-LEFT"]             = { false, true,  false, true  },
    ["SIDE-RIGHT"]            = { true,  false, true,  false },
    ["SIDE-TOP"]              = { false, false, true,  true  },
    ["SIDE-BOTTOM"]           = { true,  true,  false, false },
    ["TRICORNER-TOPLEFT"]     = { false, true,  true,  true  },
    ["TRICORNER-TOPRIGHT"]    = { true,  false, true,  true  },
    ["TRICORNER-BOTTOMLEFT"]  = { true,  true,  false, true  },
    ["TRICORNER-BOTTOMRIGHT"] = { true,  true,  true,  false },
}

local button

local function UpdatePosition()
    -- A button collector (e.g. ClassicUIForever's) may have moved the button
    -- into its own drawer; leave it there.
    if not button or button:GetParent() ~= Minimap then return end
    local angle = math.rad(ns.db.minimap.angle or 200)
    local x, y = math.cos(angle), math.sin(angle)
    local q = 1
    if x < 0 then q = q + 1 end
    if y > 0 then q = q + 2 end
    local shape = GetMinimapShape and GetMinimapShape() or "ROUND"
    local round = (SHAPES[shape] or SHAPES.ROUND)[q]
    local w = Minimap:GetWidth() / 2 + 5
    local h = Minimap:GetHeight() / 2 + 5
    if round then
        x, y = x * w, y * h
    else
        x = math.max(-w, math.min(x * (math.sqrt(2 * w * w) - 10), w))
        y = math.max(-h, math.min(y * (math.sqrt(2 * h * h) - 10), h))
    end
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local function OnDragUpdate()
    local mx, my = Minimap:GetCenter()
    local px, py = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    ns.db.minimap.angle = math.deg(math.atan2(py / scale - my, px / scale - mx)) % 360
    UpdatePosition()
end

----------------------------------------------------------------------------
-- Tooltip & clicks (shared with the addon compartment)
----------------------------------------------------------------------------
function ns.FillTooltip(tt)
    local db = ns.db
    tt:AddDoubleLine(ns.TITLE, db.enabled and "|cff00ff00Auto-sell on|r" or "|cffff4040Auto-sell off|r", 1, 0.82, 0)
    local t = ns.Totals("ALL")
    tt:AddLine(" ")
    tt:AddDoubleLine("Today", ns.Money(t.today.c, true), 1, 1, 1, 1, 1, 1)
    tt:AddDoubleLine("This week", ns.Money(t.week.c, true), 1, 1, 1, 1, 1, 1)
    tt:AddDoubleLine("All time", ns.Money(t.all.c, true), 1, 1, 1, 1, 1, 1)
    local n, c = ns.ScanBags()
    tt:AddLine(" ")
    if n > 0 then
        tt:AddDoubleLine("Junk in bags now", format("%s  (%s)", ns.Num(n), ns.Money(c)), 0.62, 0.62, 0.62, 1, 1, 1)
    else
        tt:AddLine("No junk in your bags.", 0.62, 0.62, 0.62)
    end
    tt:AddLine(" ")
    tt:AddLine("|cffffd100Left-click|r  open stats", 0.85, 0.85, 0.85)
    tt:AddLine("|cffffd100Right-click|r  settings", 0.85, 0.85, 0.85)
    tt:AddLine("|cffffd100Shift-click|r  toggle auto-sell", 0.85, 0.85, 0.85)
    if button and button:IsShown() then tt:AddLine("|cffffd100Drag|r  move this button", 0.85, 0.85, 0.85) end
end

function ns.HandleClick(mouseButton)
    local frame = ns.UI and ns.UI.frame
    local open = frame and frame:IsShown()
    if IsShiftKeyDown() then
        ns.SetEnabled(not ns.db.enabled)
    elseif mouseButton == "RightButton" then
        if open and ns.db.ui.tab == 5 then frame:Hide() else ns.ShowWindow(5) end
    else
        if open then frame:Hide() else ns.ShowWindow(1) end
    end
end

local function ShowTooltip(owner)
    GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
    ns.FillTooltip(GameTooltip)
    GameTooltip:Show()
end

function GreyGold_OnAddonCompartmentClick(_, mouseButton) ns.HandleClick(mouseButton) end
function GreyGold_OnAddonCompartmentEnter(_, owner) ShowTooltip(owner) end
function GreyGold_OnAddonCompartmentLeave() GameTooltip:Hide() end

----------------------------------------------------------------------------
-- The button itself (same look as standard minimap buttons)
----------------------------------------------------------------------------
local function Create()
    button = CreateFrame("Button", "GreyGoldMinimapButton", Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:RegisterForClicks("AnyUp")
    button:RegisterForDrag("LeftButton")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local modern = AddonCompartmentFrame ~= nil
    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(modern and 50 or 53, modern and 50 or 53)
    border:SetPoint("TOPLEFT")

    local bg = button:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(ns.ICON)
    icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
    if modern then
        bg:SetSize(24, 24); bg:SetPoint("CENTER")
        icon:SetSize(18, 18); icon:SetPoint("CENTER")
    else
        bg:SetSize(20, 20); bg:SetPoint("TOPLEFT", 7, -5)
        icon:SetSize(17, 17); icon:SetPoint("TOPLEFT", 7, -6)
    end
    button.icon = icon

    button:SetScript("OnClick", function(_, mouseButton) ns.HandleClick(mouseButton) end)
    button:SetScript("OnEnter", function(self) if not self.dragging then ShowTooltip(self) end end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    button:SetScript("OnDragStart", function(self)
        self.dragging = true
        self:LockHighlight()
        GameTooltip:Hide()
        self:SetScript("OnUpdate", OnDragUpdate)
    end)
    button:SetScript("OnDragStop", function(self)
        self.dragging = nil
        self:UnlockHighlight()
        self:SetScript("OnUpdate", nil)
    end)

    Minimap:HookScript("OnSizeChanged", UpdatePosition)
end

local function Refresh()
    if not button then return end
    button.icon:SetDesaturated(not ns.db.enabled)
    if ns.db.minimap.hide then
        button:Hide()
    else
        button:Show()
        UpdatePosition()
    end
    if GameTooltip:IsOwned(button) then ShowTooltip(button) end
end

ns.RegisterCallback(function(kind)
    if kind == "init" then
        Create()
        Refresh()
    elseif kind == "login" then
        UpdatePosition()  -- other addons may have resized/reshaped the minimap by now
    elseif kind == "settings" then
        Refresh()
    end
end)
