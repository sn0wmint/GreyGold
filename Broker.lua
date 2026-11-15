-- Grey Gold: "junk in your bags right now" readout.
-- 1. A LibDataBroker feed, shown by bag addons like Bagnon (in the data bar at
--    the bottom of the bag window) and by any broker display. The library is not
--    bundled: the feed only appears when another addon provides it.
-- 2. A small label next to the default Blizzard backpack (Settings can hide it).
--    It stays hidden when a bag addon replaces the default bags.

local ADDON, ns = ...

local feed, label

local function JunkText()
    local j = ns.junk
    if not j or j.n == 0 then return "None" end
    return format("%s (%s)", ns.Num(j.n), ns.Money(j.c, true))
end

local function OnClick(_, mouseButton) ns.HandleClick(mouseButton) end

----------------------------------------------------------------------------
-- Broker feed
----------------------------------------------------------------------------
local function CreateFeed()
    local LDB = LibStub and LibStub("LibDataBroker-1.1", true)
    if not LDB then return end
    feed = LDB:NewDataObject(ns.TITLE, {
        type = "data source",
        icon = ns.ICON,
        label = "Junk",
        text = JunkText(),
        OnClick = OnClick,
        OnTooltipShow = function(tt) ns.FillTooltip(tt) end,
    })
end

----------------------------------------------------------------------------
-- Default backpack label
----------------------------------------------------------------------------
local function BackpackFrame()
    local combined = ContainerFrameCombinedBags
    if combined and combined:IsShown() then return combined end
    for i = 1, NUM_CONTAINER_FRAMES or 13 do
        local f = _G["ContainerFrame" .. i]
        if f and f:IsShown() and f:GetID() == (ns.FIRST_BAG or 0) then return f end
    end
end

local function UpdateLabel()
    if not label then return end
    local bag = ns.db.bagLabel and BackpackFrame()
    if not bag then
        label:Hide()
        return
    end
    label.text:SetText("|cff9d9d9dJunk:|r " .. JunkText())
    label:SetWidth(label.text:GetStringWidth() + 16)
    label:ClearAllPoints()
    label:SetPoint("BOTTOMRIGHT", bag, "BOTTOMLEFT", -2, 8)  -- left of the backpack, bottom-aligned
    label:SetFrameStrata(bag:GetFrameStrata())
    label:SetFrameLevel(bag:GetFrameLevel() + 5)
    label:Show()
end

local function CreateLabel()
    label = ns.UI.Box(UIParent, 80, 22)
    label.text = ns.UI.Text(label, "GameFontHighlightSmall", nil, "CENTER")
    label.text:SetPoint("CENTER", 0, 0)
    label:EnableMouse(true)
    label:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        ns.FillTooltip(GameTooltip)
        GameTooltip:Show()
    end)
    label:SetScript("OnLeave", function() GameTooltip:Hide() end)
    label:SetScript("OnMouseUp", function(_, mouseButton) ns.HandleClick(mouseButton) end)
    label:Hide()

    -- Re-check whenever any default bag window opens or closes (next frame, once it knows its bag).
    local function Later() C_Timer.After(0, UpdateLabel) end
    local frames = {}
    if ContainerFrameCombinedBags then frames[#frames + 1] = ContainerFrameCombinedBags end
    for i = 1, NUM_CONTAINER_FRAMES or 13 do
        local f = _G["ContainerFrame" .. i]
        if f then frames[#frames + 1] = f end
    end
    for _, f in ipairs(frames) do
        f:HookScript("OnShow", Later)
        f:HookScript("OnHide", Later)
    end
end

ns.RegisterCallback(function(kind)
    if kind == "login" then
        CreateFeed()
        CreateLabel()
        UpdateLabel()
    elseif kind == "bags" or kind == "settings" then
        if feed then feed.text = JunkText() end
        UpdateLabel()
    end
end)
