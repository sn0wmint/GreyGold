-- Junk Seller: sells every junk item (grey quality, the ones that show the gold
-- coin icon at a vendor) as soon as you open any merchant, and records what it
-- sold. Hold Shift while opening a vendor to skip auto-selling that one time.

local ADDON, ns = ...

local GetMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
ns.VERSION = (GetMeta and GetMeta(ADDON, "Version")) or "?"
ns.ICON = "Interface\\Icons\\INV_Misc_Coin_02"

ns.GetItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local GetItemIcon = (C_Item and C_Item.GetItemIconByID) or GetItemIcon
local GetItemName = C_Item and C_Item.GetItemNameByID
local GetCoinText = (C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString) or GetCoinTextureString
local COPPER_ICON = "|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t"

local POOR       = (Enum and Enum.ItemQuality and Enum.ItemQuality.Poor) or 0
ns.FIRST_BAG     = BACKPACK_CONTAINER or 0
ns.LAST_BAG      = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4
local BATCH_SIZE = 12   -- sale requests sent per pass
local INTERVAL   = 0.2  -- seconds between passes
local MAX_PASSES = 50   -- hard stop (~10s) in case an item never unlocks
local RETRY_AFTER = 1   -- seconds to wait for the server before re-sending a sale
local MAX_TRIES  = 3    -- then give up on that slot (e.g. a vendor that refuses it)

----------------------------------------------------------------------------
-- Shared helpers
----------------------------------------------------------------------------
function ns.Print(msg)
    print("|cff33ff99Junk Seller|r: " .. msg)
end

-- Coin-icon money string. trimCopper drops the copper once there is gold.
function ns.Money(copper, trimCopper)
    copper = floor((copper or 0) + 0.5)
    if trimCopper and copper >= 10000 then copper = copper - copper % 100 end
    if copper <= 0 then return "0" .. COPPER_ICON end
    if GetCoinText then return GetCoinText(copper) end
    return format("%dg %ds %dc", floor(copper / 10000), floor(copper / 100) % 100, copper % 100)
end

-- Compact text money for chart labels: "1.2g", "45s", "7c".
function ns.ShortMoney(copper)
    copper = copper or 0
    if copper >= 1000000 then return format("%dg", floor(copper / 10000)) end
    if copper >= 10000 then
        local s = format("%.1f", copper / 10000):gsub("%.0$", "")
        return s .. "g"
    end
    if copper >= 100 then return format("%ds", floor(copper / 100)) end
    return format("%dc", floor(copper))
end

function ns.Num(n)
    n = floor((n or 0) + 0.5)
    return BreakUpLargeNumbers and BreakUpLargeNumbers(n) or tostring(n)
end

function ns.ItemName(id)
    local name = ns.db and ns.db.names[id]
    if not name and GetItemName then name = GetItemName(id) end
    if not name then name = ns.GetItemInfo(id) end
    return name or ("Item #" .. id)
end

function ns.ItemIcon(id)
    return (GetItemIcon and GetItemIcon(id)) or 134400
end

function ns.ItemLink(id)
    local _, link = ns.GetItemInfo(id)
    return link
end

function ns.PlayerKey()
    return (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")
end

-- Tiny callback list. kinds: "init", "login", "data", "settings".
local callbacks = {}
function ns.RegisterCallback(fn) callbacks[#callbacks + 1] = fn end
function ns.Notify(kind)
    for i = 1, #callbacks do callbacks[i](kind) end
end

----------------------------------------------------------------------------
-- Settings
----------------------------------------------------------------------------
local function InitDB()
    local db = JunkSellerDB or {}
    JunkSellerDB = db
    if db.enabled == nil then db.enabled = true end
    if db.summary == nil then db.summary = true end
    if db.milestones == nil then db.milestones = true end
    db.milestone = db.milestone or 0
    db.minimap = db.minimap or {}
    db.minimap.angle = db.minimap.angle or 200
    db.ui = db.ui or {}
    db.ui.scope = db.ui.scope or "ALL"
    db.ui.tab = db.ui.tab or 1
    db.neverSell = db.neverSell or {}
    db.names = db.names or {}
    db.chars = db.chars or {}
    db.version = 2
    ns.db = db
end

function ns.SetEnabled(on)
    ns.db.enabled = on and true or false
    ns.Print("auto-sell " .. (ns.db.enabled and "|cff00ff00on|r" or "|cffff4040off|r") .. ".")
    ns.Notify("settings")
end

function ns.SetMinimapShown(show)
    ns.db.minimap.hide = not show
    ns.Notify("settings")
end

function ns.ToggleNeverSell(id, name)
    local db = ns.db
    if name then db.names[id] = name end
    db.neverSell[id] = (not db.neverSell[id]) or nil
    local label = "|cff9d9d9d" .. ns.ItemName(id) .. "|r"
    if db.neverSell[id] then
        ns.Print(label .. " is now protected and will never be sold.")
    else
        ns.Print(label .. " is no longer protected.")
    end
    ns.Notify("settings")
end

----------------------------------------------------------------------------
-- Selling engine
----------------------------------------------------------------------------
local merchantOpen = false
local running = false
local ticker
local passes = 0
local pending = {}  -- [bag*1000+slot] = { bag, slot, itemID, count, value, name }
local haulZone

-- Same rule the default UI uses to show the coin icon, minus protected items.
local function IsJunk(info)
    return info ~= nil and info.quality == POOR and not info.hasNoValue
        and not ns.db.neverSell[info.itemID]
end
ns.IsJunk = IsJunk

local function SellPrice(info)
    return select(11, ns.GetItemInfo(info.hyperlink or info.itemID)) or 0
end

-- Junk currently in the bags: item count and total vendor value.
function ns.ScanBags()
    local n, c = 0, 0
    for bag = ns.FIRST_BAG, ns.LAST_BAG do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if IsJunk(info) then
                local count = info.stackCount or 1
                n, c = n + count, c + SellPrice(info) * count
            end
        end
    end
    return n, c
end

-- Only count sales the server confirmed (the item is gone from its slot).
local function Tally(batch)
    local sales, items, value = {}, 0, 0
    for _, p in pairs(batch) do
        if C_Container.GetContainerItemID(p.bag, p.slot) ~= p.itemID then
            sales[#sales + 1] = p
            items, value = items + p.count, value + p.value
        end
    end
    if #sales == 0 then return end

    local reached = ns.RecordHaul(sales, haulZone)
    if ns.db.summary then
        ns.Print(format("sold %s junk item%s for %s.", ns.Num(items), items == 1 and "" or "s", ns.Money(value)))
    end
    if ns.db.milestones and #reached > 0 then ns.AnnounceMilestone(reached[#reached]) end
end

local function Finish()
    if ticker then ticker:Cancel() ticker = nil end
    running = false
    local batch = pending
    pending = {}
    if merchantOpen then
        Tally(batch)
    else
        -- Vendor closed mid-run: give in-flight sales a moment to land.
        C_Timer.After(0.5, function() Tally(batch) end)
    end
end

local function Pass()
    passes = passes + 1
    if not merchantOpen or passes > MAX_PASSES then return Finish() end

    local now = GetTime()
    local sent, waiting = 0, 0
    for bag = ns.FIRST_BAG, ns.LAST_BAG do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if IsJunk(info) then
                local key = bag * 1000 + slot
                local p = pending[key]
                if p and p.itemID ~= info.itemID then p = nil end
                if info.isLocked or sent >= BATCH_SIZE or (p and now - p.sentAt < RETRY_AFTER) then
                    waiting = waiting + 1  -- sale in flight, or next batch
                elseif not p or p.tries < MAX_TRIES then
                    if not p then
                        local count = info.stackCount or 1
                        p = {
                            bag = bag, slot = slot, itemID = info.itemID, count = count,
                            value = SellPrice(info) * count, tries = 0,
                            name = info.hyperlink and info.hyperlink:match("%[(.-)%]"),
                        }
                        pending[key] = p
                    end
                    p.tries, p.sentAt = p.tries + 1, now
                    C_Container.UseContainerItem(bag, slot)  -- sells while a merchant is open
                    sent = sent + 1
                end  -- else: tried MAX_TRIES times without success; leave it alone
            end
        end
    end

    if sent == 0 and waiting == 0 then Finish() end
end

local function Start()
    if running or not merchantOpen then return end
    running, passes = true, 0
    pending = {}
    ticker = C_Timer.NewTicker(INTERVAL, Pass)
    Pass()  -- first batch goes out immediately
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("MERCHANT_SHOW")
frame:RegisterEvent("MERCHANT_CLOSED")
frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON then return end
        InitDB()
        self:UnregisterEvent("ADDON_LOADED")
        ns.Notify("init")
    elseif event == "PLAYER_LOGIN" then
        ns.Notify("login")
    elseif event == "MERCHANT_SHOW" then
        merchantOpen = true
        haulZone = (GetRealZoneText and GetRealZoneText()) or GetZoneText()
        if ns.db.enabled and not IsShiftKeyDown() then Start() end
    elseif event == "MERCHANT_CLOSED" then
        merchantOpen = false  -- stops selling so nothing gets "used" instead
    end
end)

----------------------------------------------------------------------------
-- Slash commands
----------------------------------------------------------------------------
local function Help()
    local P = ns.Print
    P("v" .. ns.VERSION .. " - auto-sell is " .. (ns.db.enabled and "|cff00ff00on|r" or "|cffff4040off|r") .. ".")
    P("/junk - open the stats window")
    P("/junk toggle - turn auto-sell on/off")
    P("/junk sell - sell junk now (vendor must be open)")
    P("/junk keep <item> - protect/unprotect an item (shift-click it in)")
    P("/junk quiet - toggle the chat summary")
    P("/junk minimap - show/hide the minimap button")
    P("Hold Shift while opening a vendor to skip selling once.")
end

SLASH_JUNKSELLER1 = "/junk"
SLASH_JUNKSELLER2 = "/junkseller"
SlashCmdList.JUNKSELLER = function(msg)
    local cmd, rest = strtrim(msg or ""):match("^(%S*)%s*(.-)$")
    cmd = strlower(cmd or "")
    if cmd == "" then
        ns.ToggleWindow()
    elseif cmd == "toggle" then
        ns.SetEnabled(not ns.db.enabled)
    elseif cmd == "sell" then
        if merchantOpen then Start() else ns.Print("open a vendor first.") end
    elseif cmd == "quiet" then
        ns.db.summary = not ns.db.summary
        ns.Print("sale summary " .. (ns.db.summary and "on" or "off") .. ".")
        ns.Notify("settings")
    elseif cmd == "minimap" then
        ns.SetMinimapShown(ns.db.minimap.hide)
        ns.Print("minimap button " .. (ns.db.minimap.hide and "hidden" or "shown") .. ".")
    elseif cmd == "keep" then
        local id = rest:match("item:(%d+)") or rest:match("^(%d+)$")
        if id then
            ns.ToggleNeverSell(tonumber(id), rest:match("%[(.-)%]"))
        else
            ns.Print("usage: /junk keep <shift-click an item>")
        end
    elseif cmd == "settings" or cmd == "options" or cmd == "config" then
        ns.ShowWindow(5)
    else
        Help()
    end
end
