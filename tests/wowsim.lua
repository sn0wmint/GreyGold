-- Minimal World of Warcraft simulation for running Grey Gold outside the game.
-- Models: bags, a vendor (sales, payments, buyback list), money, loot windows,
-- mail, units/GUIDs, the cursor, timers and events. Frames are inert stubs that
-- accept every method the addon's UI uses.

local sim = {}
sim.ADDON_DIR = arg and arg[1] or error("pass the addon folder")

----------------------------------------------------------------------------
-- Lua 5.1 / WoW global helpers
----------------------------------------------------------------------------
format, floor, strlower, strupper = string.format, math.floor, string.lower, string.upper
sort, tinsert, tremove = table.sort, table.insert, table.remove
date, time = os.date, os.time
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function strsplit(sep, s)
    local out = {}
    for piece in (s .. sep):gmatch("(.-)" .. sep:gsub("%-", "%%-")) do out[#out + 1] = piece end
    return table.unpack(out)
end

----------------------------------------------------------------------------
-- Clock and timers
----------------------------------------------------------------------------
sim.now = 1000
local timers = {}
function GetTime() return sim.now end
local function Schedule(delay, fn) timers[#timers + 1] = { at = sim.now + delay, fn = fn } end
sim.Schedule = Schedule
C_Timer = {
    After = function(delay, fn) Schedule(delay, fn) end,
    NewTicker = function(interval, fn)
        local t = { cancelled = false }
        function t:Cancel() self.cancelled = true end
        local function tick()
            if t.cancelled then return end
            fn(t)
            if not t.cancelled then Schedule(interval, tick) end
        end
        Schedule(interval, tick)
        return t
    end,
}
function sim.Advance(seconds)
    local stop = sim.now + seconds
    while true do
        local nextI, nextAt
        for i, t in ipairs(timers) do
            if t.at <= stop and (not nextAt or t.at < nextAt) then nextI, nextAt = i, t.at end
        end
        if not nextI then break end
        local t = table.remove(timers, nextI)
        if t.at > sim.now then sim.now = t.at end
        t.fn()
    end
    sim.now = stop
end

----------------------------------------------------------------------------
-- Frames and events
----------------------------------------------------------------------------
local frames = {}
local Frame = {}
Frame.__index = Frame
local function NewFrame(kind, name, parent)
    local f = setmetatable({ _kind = kind, _shown = true, _scripts = {}, _events = {}, _text = "", _id = 0, _w = 100, _h = 20 }, Frame)
    frames[#frames + 1] = f
    if name then _G[name] = f end
    return f
end
function Frame:RegisterEvent(e)
    if type(e) ~= "string" then error("bad event") end
    self._events[e] = true
end
function Frame:UnregisterEvent(e) self._events[e] = nil end
function Frame:SetScript(k, fn) self._scripts[k] = fn end
function Frame:HookScript(k, fn)
    local old = self._scripts[k]
    self._scripts[k] = function(...) if old then old(...) end fn(...) end
end
function Frame:GetScript(k) return self._scripts[k] end
function Frame:Show() local was = self._shown; self._shown = true; if not was and self._scripts.OnShow then self._scripts.OnShow(self) end end
function Frame:Hide() local was = self._shown; self._shown = false; if was and self._scripts.OnHide then self._scripts.OnHide(self) end end
function Frame:SetShown(v) if v then self:Show() else self:Hide() end end
function Frame:IsShown() return self._shown end
function Frame:SetText(t) self._text = t or "" end
function Frame:GetText() return self._text end
function Frame:SetTitle(t) self._title = t end
function Frame:GetStringWidth() return #(self._text or "") * 5 end
function Frame:GetID() return self._id end
function Frame:SetID(id) self._id = id end
function Frame:GetWidth() return self._w end
function Frame:GetHeight() return self._h end
function Frame:SetWidth(w) self._w = w end
function Frame:SetHeight(h) self._h = h end
function Frame:SetSize(w, h) self._w, self._h = w, h end
function Frame:GetCenter() return 0, 0 end
function Frame:GetEffectiveScale() return 1 end
function Frame:GetFrameStrata() return "MEDIUM" end
function Frame:GetFrameLevel() return 1 end
function Frame:GetPoint() return "CENTER", nil, "CENTER", 0, 0 end
function Frame:GetParent() return self._parent end
function Frame:GetChecked() return self._checked end
function Frame:SetChecked(v) self._checked = v end
function Frame:CreateTexture() local t = NewFrame("Texture"); t._parent = self; return t end
function Frame:CreateFontString() local t = NewFrame("FontString"); t._parent = self; return t end
function sim.Frames() return frames end
function Frame:IsOwned() return false end
for _, m in ipairs({
    "ClearAllPoints", "EnableMouse", "LockHighlight", "UnlockHighlight", "RegisterForClicks", "RegisterForDrag",
    "SetAllPoints", "SetAutoFocus", "SetBackdrop", "SetBackdropBorderColor", "SetBackdropColor", "SetBlendMode",
    "SetClampedToScreen", "SetColorTexture", "SetDesaturated", "SetFontObject", "SetFrameLevel", "SetFrameStrata",
    "SetHighlightTexture", "SetJustifyH", "SetJustifyV", "SetMovable", "SetPoint", "SetPortraitToAsset",
    "SetScrollChild", "SetSpacing", "SetTexCoord", "SetTexture", "SetTextColor", "SetToplevel", "SetVerticalScroll",
    "SetWordWrap", "SetupMenu", "GenerateMenu", "StartMoving", "StopMovingOrSizing", "EnableMouseWheel",
    "SetNormalFontObject", "SetHighlightFontObject", "SetFrameStrata", "SetVertexColor", "SetAlpha",
}) do Frame[m] = Frame[m] or function() end end

function CreateFrame(kind, name, parent)
    local f = NewFrame(kind, name, parent)
    f._parent = parent
    return f
end
UIParent = NewFrame("Frame", "UIParent")
Minimap = NewFrame("Frame", "Minimap")
BackdropTemplateMixin = {}
UISpecialFrames = {}

-- Default bag windows: ContainerFrame1 shows the backpack (bag 0).
NUM_CONTAINER_FRAMES = 13
for i = 1, NUM_CONTAINER_FRAMES do
    local f = NewFrame("Frame", "ContainerFrame" .. i)
    f._shown = false
    f._id = (i == 1) and 0 or i
end

function sim.Fire(event, ...)
    local list = {}
    for _, f in ipairs(frames) do if f._events[event] then list[#list + 1] = f end end
    for _, f in ipairs(list) do
        local h = f._scripts.OnEvent
        if h then h(f, event, ...) end
    end
end

-- Tooltip that records its lines.
GameTooltip = NewFrame("GameTooltip", "GameTooltip")
GameTooltip.lines = {}
function GameTooltip:SetOwner() wipe(self.lines) end
function GameTooltip:AddLine(t) self.lines[#self.lines + 1] = tostring(t) end
function GameTooltip:AddDoubleLine(a, b) self.lines[#self.lines + 1] = tostring(a) .. " = " .. tostring(b) end
function GameTooltip:SetItemByID(id) self.lines[#self.lines + 1] = "item:" .. id end

----------------------------------------------------------------------------
-- Items, bags, money
----------------------------------------------------------------------------
sim.ITEMS = {}
function sim.Item(id, name, quality, price)
    sim.ITEMS[id] = { name = name, q = quality, price = price }
end
local function Link(id) return "|cff9d9d9d|Hitem:" .. id .. "::::::::|h[" .. sim.ITEMS[id].name .. "]|h|r" end
sim.Link = Link

function GetItemInfo(x)
    local id = type(x) == "number" and x or tonumber(tostring(x):match("item:(%d+)"))
    local it = id and sim.ITEMS[id]
    if not it then return nil end
    return it.name, Link(id), it.q, 1, 1, "Misc", "Junk", 20, "", 134400, it.price
end
C_Item = {
    GetItemInfo = GetItemInfo,
    GetItemNameByID = function(id) return sim.ITEMS[id] and sim.ITEMS[id].name end,
    GetItemIconByID = function() return 134400 end,
}

sim.SLOTS = 16
sim.bags = {}
sim.money = 0
sim.chat = {}
function print(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
    sim.chat[#sim.chat + 1] = table.concat(parts, " ")
end
function GetMoney() return sim.money end

function sim.Add(id, n)
    for slot = 1, sim.SLOTS do
        local s = sim.bags[slot]
        if s and s.id == id then s.n = s.n + n; return slot end
    end
    for slot = 1, sim.SLOTS do
        if not sim.bags[slot] then sim.bags[slot] = { id = id, n = n }; return slot end
    end
    error("bags full")
end
function sim.SlotOf(id)
    for slot = 1, sim.SLOTS do if sim.bags[slot] and sim.bags[slot].id == id then return slot end end
end
function sim.Count(id)
    local c = 0
    for slot = 1, sim.SLOTS do if sim.bags[slot] and sim.bags[slot].id == id then c = c + sim.bags[slot].n end end
    return c
end
function sim.BagUpdate() Schedule(0.05, function() sim.Fire("BAG_UPDATE_DELAYED") end) end

C_Container = {}
function C_Container.GetContainerNumSlots(bag) return bag == 0 and sim.SLOTS or 0 end
function C_Container.GetContainerNumFreeSlots(bag)
    if bag ~= 0 then return 0, 0 end
    local free = 0
    for slot = 1, sim.SLOTS do if not sim.bags[slot] then free = free + 1 end end
    return free, 0
end
function C_Container.GetContainerItemInfo(bag, slot)
    local s = bag == 0 and sim.bags[slot]
    if not s then return nil end
    local it = sim.ITEMS[s.id]
    return { itemID = s.id, stackCount = s.n, quality = it.q, hasNoValue = it.price == 0,
             hyperlink = Link(s.id), isLocked = s.locked or false }
end
function C_Container.GetContainerItemID(bag, slot)
    local s = bag == 0 and sim.bags[slot]
    return s and s.id or nil
end

-- Vendor
sim.merchantOpen = false
sim.buyback = {}
sim.moneyFirst = false      -- payment event before the bag event
sim.mergeMoney = false      -- several payments reported by one PLAYER_MONEY
local pendingPay = 0

local function Pay(amount)
    sim.money = sim.money + amount
    if sim.mergeMoney then
        pendingPay = pendingPay + 1
        if pendingPay == 1 then Schedule(0.12, function() pendingPay = 0; sim.Fire("PLAYER_MONEY") end) end
    else
        sim.Fire("PLAYER_MONEY")
    end
end

-- The server answers a sale: the item leaves the bags and the vendor pays.
local function ServerSell(slot)
    local s = sim.bags[slot]
    if not s then return end
    s.locked = true
    Schedule(0.1, function()
        if sim.bags[slot] ~= s then return end
        sim.bags[slot] = nil
        local it = sim.ITEMS[s.id]
        local paid = it.price * s.n
        table.insert(sim.buyback, { id = s.id, n = s.n, price = paid })
        if #sim.buyback > 12 then table.remove(sim.buyback, 1) end
        if sim.moneyFirst then Pay(paid); sim.BagUpdate() else sim.BagUpdate(); Pay(paid) end
    end)
end

function C_Container.UseContainerItem(bag, slot)
    if bag ~= 0 or not sim.bags[slot] then return end
    if sim.merchantOpen then ServerSell(slot) else sim.used = (sim.used or 0) + 1 end
end
sim.cursor = nil
function C_Container.PickupContainerItem(bag, slot)
    if sim.cursor then sim.cursor = nil; return end
    local s = sim.bags[slot]
    if s then sim.cursor = { slot = slot, id = s.id } end
end
function GetCursorInfo()
    if sim.cursor then return "item", sim.cursor.id, Link(sim.cursor.id) end
end
function ClearCursor() sim.cursor = nil end
function DeleteCursorItem()
    local c = sim.cursor
    if not c then return end
    sim.cursor = nil
    sim.bags[c.slot] = nil
    sim.BagUpdate()
end
function BuybackItem(index)
    local b = table.remove(sim.buyback, index)
    if not b then return end
    Schedule(0.1, function()
        sim.Add(b.id, b.n)
        sim.money = sim.money - b.price
        sim.BagUpdate()
        sim.Fire("PLAYER_MONEY")
    end)
end
function sim.BuybackIndexOf(id)
    for i = #sim.buyback, 1, -1 do if sim.buyback[i].id == id then return i end end
end

-- Hand actions
function sim.RightClickSell(id) C_Container.UseContainerItem(0, sim.SlotOf(id)) end
function sim.DragToVendor(id)
    C_Container.PickupContainerItem(0, sim.SlotOf(id))
    local c = sim.cursor
    sim.cursor = nil
    ServerSell(c.slot)
end
function sim.Destroy(id)
    C_Container.PickupContainerItem(0, sim.SlotOf(id))
    DeleteCursorItem()
end
function sim.Equip(id)  -- leaves the bags without any payment
    local slot = sim.SlotOf(id)
    sim.bags[slot] = nil
    sim.BagUpdate()
end

sim.shift = false
function IsShiftKeyDown() return sim.shift end
function sim.OpenVendor()
    sim.merchantOpen = true
    sim.Fire("MERCHANT_SHOW")
end
function sim.CloseVendor()
    sim.merchantOpen = false
    sim.Fire("MERCHANT_CLOSED")
end

----------------------------------------------------------------------------
-- World: zone, units, loot, mail
----------------------------------------------------------------------------
sim.zone = "Elwynn Forest"
function GetRealZoneText() return sim.zone end
function GetZoneText() return sim.zone end
function UnitName(unit) if unit == "player" then return "Tester" end; local u = sim.units[unit]; return u and u.name end
function GetRealmName() return "Realm" end
function UnitClass() return "Warrior", "WARRIOR" end
sim.units = {}
function UnitGUID(unit) local u = sim.units[unit]; return u and u.guid end
function UnitIsDead(unit) local u = sim.units[unit]; return u and u.dead or false end
function UnitExists(unit) return sim.units[unit] ~= nil end

SECRET = setmetatable({}, { __tostring = function() return "<secret>" end })
function issecretvalue(v) return v == SECRET end

local loot
function GetNumLootItems() return loot and #loot or 0 end
function GetLootSlotLink(slot) local l = loot and loot[slot]; return l and Link(l.id) end
function GetLootSourceInfo(slot) local l = loot and loot[slot]; if l then return l.guid, l.n end end
sim.fishing = false
function IsFishingLoot() return sim.fishing end

-- Hover the corpse (names it), open loot, auto-loot everything, close.
function sim.LootCorpse(guid, name, items, hover)
    if hover ~= false then
        sim.units.mouseover = { guid = guid, name = name }
        sim.Fire("UPDATE_MOUSEOVER_UNIT")
    end
    loot = {}
    for _, it in ipairs(items) do loot[#loot + 1] = { id = it[1], n = it[2], guid = it.guid or guid } end
    sim.Fire("LOOT_READY", true)
    sim.Fire("LOOT_OPENED", true)
    for _, l in ipairs(loot) do sim.Add(l.id, l.n) end
    loot = nil
    sim.Fire("LOOT_CLOSED")
    sim.units.mouseover = nil
    sim.BagUpdate()
end

function sim.Mail(id, n)
    sim.Fire("MAIL_SHOW")
    sim.Add(id, n)
    sim.BagUpdate()
    sim.Advance(0.2)
    sim.Fire("MAIL_CLOSED")
end

----------------------------------------------------------------------------
-- Misc globals the addon touches
----------------------------------------------------------------------------
Enum = { ItemQuality = { Poor = 0 } }
BACKPACK_CONTAINER, NUM_TOTAL_EQUIPPED_BAG_SLOTS = 0, 4
ERR_INV_FULL = "Inventory is full."
UNKNOWN = "Unknown"
YES, NO = "Yes", "No"
SOUNDKIT = {}
function PlaySound() end
RAID_CLASS_COLORS = {}
StaticPopupDialogs = {}
SlashCmdList = {}
function StaticPopup_Show() end
function PanelTemplates_SetNumTabs() end
function PanelTemplates_SetTab() end
function GetCursorPosition() return 0, 0 end
function GetMinimapShape() return "ROUND" end
C_AddOns = { GetAddOnMetadata = function(_, field)
    if field == "Version" then return sim.version or "2.2.0" end
    if field == "Title" then return "Grey Gold" end
end }

function hooksecurefunc(a, b, c)
    local tbl, name, fn
    if type(a) == "table" then tbl, name, fn = a, b, c else tbl, name, fn = _G, a, b end
    local orig = tbl[name]
    tbl[name] = function(...)
        local r = table.pack(orig(...))
        fn(...)
        return table.unpack(r, 1, r.n)
    end
end

-- LibDataBroker, as provided by Bagnon's BagBrother.
sim.ldb = {}
LibStub = function(name, silent)
    if name == "LibDataBroker-1.1" then
        return { NewDataObject = function(_, n, t) sim.ldb[n] = t; return t end }
    end
end

----------------------------------------------------------------------------
-- Loading the addon (and /reload)
----------------------------------------------------------------------------
local FILES = { "GreyGold.lua", "Stats.lua", "Sources.lua", "Achievements.lua", "Minimap.lua", "Broker.lua", "UI.lua", "Panels.lua" }
local ORIGINALS = { BuybackItem = BuybackItem, DeleteCursorItem = DeleteCursorItem }
local ORIGINAL_PICKUP = C_Container.PickupContainerItem

function sim.Load(opts)
    opts = opts or {}
    -- A /reload starts a fresh UI: earlier hooks are gone.
    for k, v in pairs(ORIGINALS) do _G[k] = v end
    C_Container.PickupContainerItem = ORIGINAL_PICKUP
    SlashCmdList = {}
    sim.ldb = {}
    wipe(frames)
    wipe(timers)
    GameTooltip = NewFrame("GameTooltip", "GameTooltip")
    GameTooltip.lines = {}
    function GameTooltip:SetOwner() wipe(self.lines) end
    function GameTooltip:AddLine(t) self.lines[#self.lines + 1] = tostring(t) end
    function GameTooltip:AddDoubleLine(a, b) self.lines[#self.lines + 1] = tostring(a) .. " = " .. tostring(b) end
    function GameTooltip:SetItemByID(id) self.lines[#self.lines + 1] = "item:" .. id end
    for i = 1, NUM_CONTAINER_FRAMES do
        local f = NewFrame("Frame", "ContainerFrame" .. i)
        f._shown = false
        f._id = (i == 1) and 0 or i
    end
    local ns = {}
    for _, file in ipairs(FILES) do
        local chunk, err = loadfile(sim.ADDON_DIR .. "/" .. file)
        if not chunk then error(err) end
        chunk("GreyGold", ns)
    end
    sim.ns = ns
    sim.Fire("ADDON_LOADED", "GreyGold")
    sim.Fire("PLAYER_LOGIN")
    sim.Fire("PLAYER_ENTERING_WORLD", opts.reload ~= true, opts.reload == true)
    sim.Advance(1.5)
    return ns
end

return sim
