-- Grey Gold: where your junk comes from, and what happens to it.
--
-- Watches the bags for junk arriving (looted, mailed, traded, taken from the
-- bank...) and leaving (sold, bought back, destroyed). Each item keeps a
-- first-in-first-out list of where its copies came from, so every sale can say
-- which mob dropped it. Also spots junk you sell by hand.
--
-- Only junk is ever recorded: grey (Poor) quality with a sell value. A grey item
-- only counts as sold by hand when the merchant actually paid for it; one that
-- is destroyed, equipped or used never counts, even with the vendor open.

local ADDON, ns = ...
local Plain = ns.Plain

local LOOT_WINDOW    = 3    -- seconds after a loot window closes that new junk is still its loot
local LOOT_KEEP      = 3    -- loot windows remembered (fast auto-looting)
local FRAME_GRACE    = 2    -- seconds after mail/trade/bank closes that new junk still came from it
local CAST_WINDOW    = 10   -- seconds a spell target ("Opening" a chest) names the next object loot
local BUYBACK_WINDOW = 2    -- seconds after BuybackItem() that new junk is a buyback
local HAND_WINDOW    = 3    -- seconds a hand-sale loss and its payment wait for each other
local POOL_DELAY     = 1    -- seconds before merged payments are shared out (all updates in by then)
local OWED_WINDOW    = 6    -- seconds auto-sell gold may lag behind its tally
local SUGGEST_EVERY  = 30   -- seconds between "bags full" suggestions
local MAX_NAMES      = 300  -- creature names remembered by GUID

local carry            -- ns.db.carry[Name-Realm] = { items = { [itemID] = { entry, ... } }, session }
local snap             -- [itemID] = grey items with a sell value in the bags at the last scan
local otherSnap        -- [itemID] = every other item, only while a vendor is (or just was) open
local prices = {}      -- [itemID] = vendor price of one
local names, nameCount = {}, 0
local lastCast         -- { name, at }: the player's last spell target
local loots = {}       -- recent loot windows, newest last
local openAt, closeAt = {}, {}  -- mail / trade / bank windows
local merchantOpen, merchantClosedAt = false, -100
local buybackAt = -100
local deferred = {}    -- buybacks seen while auto-sell was busy
local cursorItem       -- item last picked up onto the cursor
local destroyed = {}   -- [itemID] = GetTime() it was deleted
local losses = {}      -- items that left the bags at a vendor, waiting for their payment
local golds = {}       -- payments received at a vendor, waiting for their item
local owed = {}        -- auto-sell sales whose payment hasn't been matched yet
local claims = {}      -- [itemID] = auto-sold units whose bag loss hasn't been seen yet
local lastMoney
local freeSlots
local lastSuggest = -100
local sessionSet = false
local retrying = false
local Settle, Buyback

ns.junk = { n = 0, c = 0, free = 0 }  -- junk in the bags right now (unprotected only)

local function Carry()
    if carry then return carry end
    if not ns.db then return nil end
    local key = ns.PlayerKey()
    carry = ns.db.carry[key] or {}
    ns.db.carry[key] = carry
    carry.items = carry.items or {}
    carry.session = carry.session or time()
    return carry
end

local function InMerchantWindow()
    return merchantOpen or GetTime() - merchantClosedAt < HAND_WINDOW
end

----------------------------------------------------------------------------
-- Source lists: oldest copy first
----------------------------------------------------------------------------
local function Push(id, e, front)
    local q = carry.items[id]
    if not q then q = {}; carry.items[id] = q end
    if front then table.insert(q, 1, e) else q[#q + 1] = e end
end

-- Forget n copies, oldest first (destroyed, banked, mailed away...).
local function Trim(id, n)
    local q = carry and carry.items[id]
    while q and n > 0 and q[1] do
        local e = q[1]
        if e.n > n then
            e.n, n = e.n - n, 0
        else
            n = n - e.n
            table.remove(q, 1)
        end
    end
    if q and not q[1] then carry.items[id] = nil end
end

-- Where n sold copies came from: { { n, k, s, z, t, rb }, ... }. Copies the
-- addon never saw arrive come back as one part without a source.
function ns.TakeSources(id, n)
    local parts = {}
    local q = carry and carry.items[id]
    while q and n > 0 and q[1] do
        local e = q[1]
        local take = math.min(e.n, n)
        parts[#parts + 1] = { n = take, k = e.k, s = e.s, z = e.z, t = e.t, rb = e.rb }
        if take == e.n then table.remove(q, 1) else e.n = e.n - take end
        n = n - take
    end
    if q and not q[1] then carry.items[id] = nil end
    if n > 0 then parts[#parts + 1] = { n = n } end
    return parts
end

-- The lists never hold more copies than the bags do.
local function Reconcile()
    if not carry or not snap or #losses > 0 or ns.IsSelling() then return end
    for id, q in pairs(carry.items) do
        local sum = 0
        for _, e in ipairs(q) do sum = sum + e.n end
        local have = snap[id] or 0
        if sum > have then Trim(id, sum - have) end
    end
end

----------------------------------------------------------------------------
-- Names of what you looted
----------------------------------------------------------------------------
local function UnitInfo(unit)
    local okG, guid = pcall(UnitGUID, unit)
    guid = okG and Plain(guid)
    if type(guid) ~= "string" then return nil end
    local okN, name = pcall(UnitName, unit)
    name = okN and Plain(name)
    if type(name) ~= "string" or name == "" then name = nil end
    return guid, name
end

local function Remember(unit)
    if type(unit) ~= "string" then return end
    local guid, name = UnitInfo(unit)
    if not guid or not name then return end
    if not (guid:find("^Creature") or guid:find("^Vehicle")) then return end
    if not names[guid] then
        nameCount = nameCount + 1
        if nameCount > MAX_NAMES then wipe(names); nameCount = 1 end
    end
    names[guid] = name
end

local function CreatureName(guid)
    if names[guid] then return names[guid] end
    for _, unit in ipairs({ "mouseover", "target" }) do
        local g, name = UnitInfo(unit)
        if g == guid and name then return name end
    end
end

local function RecentCast()
    if lastCast and GetTime() - lastCast.at < CAST_WINDOW then return lastCast.name end
end

local function Fishing()
    return IsFishingLoot and Plain(IsFishingLoot()) and true or false
end

-- kind, name for a loot source GUID.
local function FromGUID(guid)
    local kind = guid:match("^(%a+)")
    if kind == "Creature" or kind == "Vehicle" then
        return "mob", CreatureName(guid)
    elseif kind == "GameObject" then
        if Fishing() then return "fish" end
        return "object", RecentCast()
    elseif kind == "Item" then
        local name
        if C_Item and C_Item.GetItemLinkByGUID then
            local ok, link = pcall(C_Item.GetItemLinkByGUID, guid)
            link = ok and Plain(link)
            name = type(link) == "string" and link:match("%[(.-)%]") or nil
        end
        return "item", name
    end
end

-- No usable GUID (hidden inside dungeons, or an old client).
local function Fallback()
    if Fishing() then return "fish" end
    local okD, dead = pcall(UnitIsDead, "target")
    if okD and Plain(dead) then
        local _, name = UnitInfo("target")
        return "mob", name
    end
    local cast = RecentCast()
    if cast then return "object", cast end
    return "mob"
end

local function OnLootWindow()
    if not carry or not GetNumLootItems then return end
    local okN, num = pcall(GetNumLootItems)
    num = okN and Plain(num)
    if type(num) ~= "number" then return end
    local ctx = loots[#loots]
    if not ctx or ctx.closedAt then  -- LOOT_READY and LOOT_OPENED both fire for one window
        ctx = { items = {}, zone = ns.Zone(), t = time() }
        loots[#loots + 1] = ctx
        if #loots > LOOT_KEEP then table.remove(loots, 1) end
    end
    for slot = 1, num do
        local okL, link = pcall(GetLootSlotLink, slot)
        link = okL and Plain(link)
        local id = type(link) == "string" and tonumber(link:match("item:(%d+)"))
        if not id then
            -- No readable item link: money, or an item the game hides from addons.
            local okT, slotType = true, nil
            if GetLootSlotType then okT, slotType = pcall(GetLootSlotType, slot) end
            slotType = okT and Plain(slotType)
            if slotType == nil or slotType == 1 then ctx.unknown = true end  -- 1 = item
        end
        if id and not ctx.items[id] then
            local k, s
            if GetLootSourceInfo then
                local okS, guid = pcall(GetLootSourceInfo, slot)
                guid = okS and Plain(guid)
                if type(guid) == "string" then k, s = FromGUID(guid) end
            end
            if not k then k, s = Fallback() end
            local src = { k = k, s = s }
            ctx.items[id] = src
            ctx.first = ctx.first or src
        end
    end
end

local function OnLootClosed()
    local ctx = loots[#loots]
    if ctx and not ctx.closedAt then ctx.closedAt = GetTime() end
end

-- The recent loot window that held this item. With guess, also accept a recent
-- window that had items the game wouldn't name (they may include this one).
local function LootSource(id, guess)
    local now = GetTime()
    for i = #loots, 1, -1 do
        local ctx = loots[i]
        if not ctx.closedAt or now - ctx.closedAt < LOOT_WINDOW then
            if ctx.items[id] then return ctx, ctx.items[id] end
            if guess and ctx.unknown then return ctx, ctx.first or { k = "mob" } end
        end
    end
end

local function WindowActive(k)
    return openAt[k] or (closeAt[k] and GetTime() - closeAt[k] < FRAME_GRACE)
end

----------------------------------------------------------------------------
-- Junk arriving and leaving
----------------------------------------------------------------------------
-- Bought back: cancel that sale in the totals and give the copies their sources back.
function Buyback(id, n)
    local rows = ns.UndoSale(id, n, carry.session)
    local back = 0
    for _, r in ipairs(rows) do
        Push(id, { n = r.n, k = r.k, s = r.s, z = r.lz, t = r.lt, rb = (r.rb or 0) + 1 }, true)
        back = back + r.n
    end
    if n > back then Push(id, { n = n - back, rb = 1 }, true) end  -- sold before 2.1.0, or before a relog
end

local function OnGain(id, n)
    if merchantOpen and GetTime() - buybackAt < BUYBACK_WINDOW then
        if ns.IsSelling() then
            deferred[#deferred + 1] = { id = id, n = n }
        else
            Buyback(id, n)
        end
        return
    end
    local window = (WindowActive("mail") and "mail") or (WindowActive("trade") and "trade")
        or (WindowActive("bank") and "bank")
    local ctx, src = LootSource(id, false)
    if not ctx and not window then ctx, src = LootSource(id, true) end
    local e
    if ctx then
        e = { k = src.k, s = src.s, z = ctx.zone, t = ctx.t }
    else
        e = { k = window or "other", z = ns.Zone(), t = time() }
    end
    e.n = n
    Push(id, e)
end

local function OnLoss(id, n, junk)
    if InMerchantWindow() then
        if junk and claims[id] then  -- already recorded by auto-sell
            local use = math.min(claims[id], n)
            n = n - use
            claims[id] = (claims[id] > use) and (claims[id] - use) or nil
        end
        if n > 0 then
            losses[#losses + 1] = { id = id, n = n, value = (prices[id] or 0) * n, junk = junk, at = GetTime() }
            C_Timer.After(POOL_DELAY + 0.1, Settle)
            C_Timer.After(HAND_WINDOW + 0.1, Settle)
        end
    elseif junk and not ns.IsSelling() then
        Trim(id, n)
    end
end

----------------------------------------------------------------------------
-- Hand sales: an item that left the bags at a vendor counts as sold only when
-- a payment for it arrives. Only grey items are ever recorded; other items are
-- tracked only so their payments are never credited to junk.
----------------------------------------------------------------------------
local function DropLoss(i)
    local l = table.remove(losses, i)
    if l.junk then Trim(l.id, l.n) end
end

function Settle()
    if not carry or ns.IsSelling() then return end
    local now, sales = GetTime(), {}

    -- Destroyed items never count as sold.
    for i = #losses, 1, -1 do
        local d = destroyed[losses[i].id]
        if d and math.abs(losses[i].at - d) <= HAND_WINDOW then DropLoss(i) end
    end

    local function FindLoss(amount, junk)
        for i, l in ipairs(losses) do
            if l.junk == junk and l.value > 0 and l.value == amount then return i end
        end
    end
    local function Sell(i)
        local l = table.remove(losses, i)
        sales[#sales + 1] = { itemID = l.id, count = l.n, value = l.value }
    end

    -- 1. A payment that exactly matches one auto-sale, one grey item, or one other item.
    local i = 1
    while i <= #golds do
        local amount, matched = golds[i].amount, false
        for j, o in ipairs(owed) do
            if o.amount == amount then table.remove(owed, j); matched = true; break end
        end
        if not matched then
            local li = FindLoss(amount, true)
            if li then
                Sell(li); matched = true
            else
                li = FindLoss(amount, false)
                if li then table.remove(losses, li); matched = true end
            end
        end
        if matched then table.remove(golds, i) else i = i + 1 end
    end

    -- 2. Payments that arrived merged: pay auto-sales first, set aside everything
    --    other items could have earned, and only credit grey items from the rest.
    --    Waits POOL_DELAY so every bag change from that moment has been seen.
    local young, pool, newest = {}, 0, nil
    for _, g in ipairs(golds) do
        if now - g.at >= POOL_DELAY then
            pool, newest = pool + g.amount, g.at
        else
            young[#young + 1] = g
        end
    end
    if newest then
        local k = 1
        while k <= #owed and pool > 0 do
            local o = owed[k]
            if o.amount <= pool then
                pool = pool - o.amount
                table.remove(owed, k)
            else
                o.amount, pool = o.amount - pool, 0
            end
        end
        local reserve = 0
        for _, l in ipairs(losses) do
            if not l.junk then reserve = reserve + l.value end
        end
        local spend = pool - reserve
        local j = 1
        while j <= #losses do
            local l = losses[j]
            if l.junk and l.value > 0 and l.value <= spend and now - l.at >= POOL_DELAY then
                spend, pool = spend - l.value, pool - l.value
                Sell(j)
            else
                j = j + 1
            end
        end
        wipe(golds)
        if pool > 0 then golds[1] = { amount = pool, at = newest } end
        for _, g in ipairs(young) do golds[#golds + 1] = g end
    end

    -- 3. Whatever waited too long was not a sale (destroyed, equipped, used, moved).
    for j = #losses, 1, -1 do
        if now - losses[j].at > HAND_WINDOW then DropLoss(j) end
    end
    for j = #golds, 1, -1 do
        if now - golds[j].at > HAND_WINDOW then table.remove(golds, j) end
    end
    for j = #owed, 1, -1 do
        if now - owed[j].at > OWED_WINDOW then table.remove(owed, j) end
    end
    if not InMerchantWindow() then wipe(claims) end

    if #sales > 0 then
        local reached = ns.RecordHaul(sales, ns.vendorZone, { visit = ns.visit, manual = true })
        if ns.db.milestones and #reached > 0 then ns.AnnounceMilestone(reached[#reached]) end
    end
    if #losses == 0 then Reconcile() end
end

----------------------------------------------------------------------------
-- Bag scan
----------------------------------------------------------------------------
local function SellPrice(id, link)
    local p = prices[id]
    if p == nil then
        p = select(11, ns.GetItemInfo(link or id))
        if p then prices[id] = p end
    end
    return p or 0
end

local function Suggest()
    if not ns.db.suggest or merchantOpen then return end
    local c, now = ns.junk.cheapest, GetTime()
    if not c or now - lastSuggest < SUGGEST_EVERY then return end
    lastSuggest = now
    ns.Print(format("your bags are full. Cheapest junk to delete: %s%s (worth %s).",
        c.link or ns.ItemName(c.id), c.n > 1 and (" x" .. c.n) or "", ns.Money(c.c)))
end

-- grey counts, other counts (vendor open only), junk count, junk value, free slots,
-- cheapest unprotected junk stack. Returns nothing if the bags aren't loaded yet.
local function ReadBags()
    if (C_Container.GetContainerNumSlots(ns.FIRST_BAG) or 0) == 0 then return end
    local grey, other = {}, InMerchantWindow() and {} or nil
    local n, c, free, cheapest = 0, 0, 0, nil
    for bag = ns.FIRST_BAG, ns.LAST_BAG do
        if C_Container.GetContainerNumFreeSlots then
            local nfree, family = C_Container.GetContainerNumFreeSlots(bag)
            if (family or 0) == 0 then free = free + (nfree or 0) end  -- normal bags only
        end
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info then
                local id, count = info.itemID, info.stackCount or 1
                if not id or info.quality == nil then return end  -- item data not loaded yet
                if info.quality == ns.POOR and not info.hasNoValue then
                    grey[id] = (grey[id] or 0) + count
                    local price = SellPrice(id, info.hyperlink)
                    if not ns.db.neverSell[id] then
                        local value = price * count
                        n, c = n + count, c + value
                        if price > 0 and (not cheapest or value < cheapest.c) then
                            cheapest = { id = id, n = count, c = value, link = info.hyperlink }
                        end
                    end
                elseif other then
                    other[id] = (other[id] or 0) + count
                    SellPrice(id, info.hyperlink)
                end
            end
        end
    end
    return grey, other, n, c, free, cheapest
end

-- noSettle: the caller settles hand sales itself (after claiming auto-sales).
local function Scan(noSettle)
    if not carry then return end
    local grey, other, n, c, free, cheapest = ReadBags()
    if not grey then
        if not retrying then
            retrying = true
            C_Timer.After(1, function() retrying = false; Scan() end)
        end
        return
    end

    local j = ns.junk
    local changed = j.n ~= n or j.c ~= c
    j.n, j.c, j.free, j.cheapest = n, c, free, cheapest
    if changed then ns.Notify("bags") end
    if freeSlots and freeSlots > 0 and free == 0 then Suggest() end
    freeSlots = free

    if not snap then  -- first look after login or /reload: nothing to compare with yet
        snap, otherSnap = grey, other
        Reconcile()
        return
    end
    for id, count in pairs(grey) do
        local old = snap[id] or 0
        if count > old then OnGain(id, count - old) end
    end
    for id, old in pairs(snap) do
        local count = grey[id] or 0
        if count < old then OnLoss(id, old - count, true) end
    end
    if other and otherSnap then
        for id, old in pairs(otherSnap) do
            local count = other[id] or 0
            if count < old then OnLoss(id, old - count, false) end
        end
    end
    snap, otherSnap = grey, other
    if not noSettle then Settle() end
end

-- Called by the selling engine once an auto-sell run has been counted.
function ns.AfterTally(sales)
    if not carry then return end
    Scan(true)  -- the sold items are gone now; see those losses before claiming them
    local now = GetTime()
    for _, s in ipairs(sales) do
        local left, i = s.count, 1
        while left > 0 and i <= #losses do
            local l = losses[i]
            if l.junk and l.id == s.itemID then
                local use = math.min(l.n, left)
                l.n, left = l.n - use, left - use
                l.value = (prices[l.id] or 0) * l.n
                if l.n == 0 then table.remove(losses, i) else i = i + 1 end
            else
                i = i + 1
            end
        end
        if left > 0 then claims[s.itemID] = (claims[s.itemID] or 0) + left end
        owed[#owed + 1] = { amount = s.value, at = now }
    end
    for _, b in ipairs(deferred) do Buyback(b.id, b.n) end
    wipe(deferred)
    Settle()
end

----------------------------------------------------------------------------
-- Hooks and events
----------------------------------------------------------------------------
if BuybackItem then
    hooksecurefunc("BuybackItem", function() buybackAt = GetTime() end)
end

local function NoteCursor()
    local ok, kind, id = pcall(GetCursorInfo)
    if ok and kind == "item" and id then cursorItem = id end
end
if C_Container and C_Container.PickupContainerItem then
    hooksecurefunc(C_Container, "PickupContainerItem", NoteCursor)
end
if DeleteCursorItem then
    hooksecurefunc("DeleteCursorItem", function()
        if cursorItem then
            destroyed[cursorItem] = GetTime()
            C_Timer.After(0.2, Settle)
        end
    end)
end

local frame = CreateFrame("Frame")
for _, e in ipairs({
    "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "BAG_UPDATE_DELAYED", "PLAYER_MONEY",
    "MERCHANT_SHOW", "MERCHANT_CLOSED", "LOOT_READY", "LOOT_OPENED", "LOOT_CLOSED",
    "MAIL_SHOW", "MAIL_CLOSED", "TRADE_SHOW", "TRADE_CLOSED", "BANKFRAME_OPENED", "BANKFRAME_CLOSED",
    "UPDATE_MOUSEOVER_UNIT", "PLAYER_TARGET_CHANGED", "NAME_PLATE_UNIT_ADDED", "UNIT_SPELLCAST_SENT",
    "CURSOR_CHANGED", "UI_ERROR_MESSAGE",
}) do
    pcall(frame.RegisterEvent, frame, e)
end

local WINDOWS = {
    MAIL_SHOW = "mail", MAIL_CLOSED = "mail", TRADE_SHOW = "trade", TRADE_CLOSED = "trade",
    BANKFRAME_OPENED = "bank", BANKFRAME_CLOSED = "bank",
}

frame:SetScript("OnEvent", function(_, event, a1, a2)
    if event == "PLAYER_LOGIN" then
        Carry()
        lastMoney = GetMoney()
        return
    end
    if not carry then return end

    if event == "BAG_UPDATE_DELAYED" then
        Scan()
    elseif event == "PLAYER_MONEY" then
        local m = GetMoney()
        if lastMoney and m > lastMoney and InMerchantWindow() then
            golds[#golds + 1] = { amount = m - lastMoney, at = GetTime() }
            C_Timer.After(POOL_DELAY + 0.1, Settle)
            C_Timer.After(HAND_WINDOW + 0.1, Settle)
        end
        lastMoney = m
        Settle()
    elseif event == "MERCHANT_SHOW" then
        merchantOpen = true
        lastMoney = GetMoney()
        Scan()  -- start counting every item, so other items' payments can be set aside
    elseif event == "MERCHANT_CLOSED" then
        if merchantOpen then merchantClosedAt = GetTime() end
        merchantOpen = false
        C_Timer.After(HAND_WINDOW + 0.2, Settle)
    elseif event == "LOOT_READY" or event == "LOOT_OPENED" then
        OnLootWindow()
    elseif event == "LOOT_CLOSED" then
        OnLootClosed()
    elseif WINDOWS[event] then
        local k = WINDOWS[event]
        if event:find("CLOSED") then
            openAt[k], closeAt[k] = nil, GetTime()
        else
            openAt[k] = true
        end
    elseif event == "UPDATE_MOUSEOVER_UNIT" then
        Remember("mouseover")
    elseif event == "PLAYER_TARGET_CHANGED" then
        Remember("target")
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        Remember(a1)
    elseif event == "UNIT_SPELLCAST_SENT" then
        local target = Plain(a2)
        if a1 == "player" and type(target) == "string" and target ~= "" then
            lastCast = { name = target, at = GetTime() }
        end
    elseif event == "CURSOR_CHANGED" then
        NoteCursor()
    elseif event == "UI_ERROR_MESSAGE" then
        if ERR_INV_FULL and Plain(a2) == ERR_INV_FULL then Suggest() end
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- A new session clears the game's buyback list, so older sales can't come back.
        if a1 or (a1 == nil and not sessionSet) then carry.session = time() end
        sessionSet = true
        lastMoney = GetMoney()
        C_Timer.After(1, function() Scan() end)
    end
end)
