-- Scenario tests for Grey Gold 2.1.0, run against the real addon files.
local here = arg[0]:match("^(.*)[/\\]") or "."
local print = print  -- the simulation captures the global print as game chat
local sim = dofile(here .. "/wowsim.lua")

local passed, failed = 0, 0
local function check(cond, msg)
    if cond then passed = passed + 1 else failed = failed + 1; print("FAIL: " .. msg) end
end
local function eq(a, b, msg) check(a == b, msg .. " (got " .. tostring(a) .. ", want " .. tostring(b) .. ")") end
local function section(name) print("-- " .. name) end

-- Items: id, name, quality (0 grey, 1 white, 2 green), vendor price in copper
sim.Item(100, "Broken Fang", 0, 5)
sim.Item(101, "Ripped Pants", 0, 23)
sim.Item(102, "Tattered Vest", 0, 40)
sim.Item(103, "Cracked Bone", 0, 12)
sim.Item(104, "Worn Belt", 0, 12)
sim.Item(105, "Old Shirt", 0, 30)
sim.Item(106, "Bent Spoon", 0, 7)
sim.Item(107, "Dull Knife", 0, 9)
sim.Item(108, "Chipped Claw", 0, 3)
sim.Item(200, "Linen Cloth", 1, 13)
sim.Item(201, "Green Sword", 2, 40)
sim.Item(300, "Quest Thing", 0, 0)

local KOBOLD = "Creature-0-1-0-1-299-00000A"
local THUG = "Creature-0-1-0-1-450-00000B"

local function Char(ns) return ns.db.chars["Tester-Realm"] end
local function Today(ns) return Char(ns).days[ns.Today()] end
local function Rows(ns, id)
    local out = {}
    for _, r in ipairs(Char(ns).log or {}) do if not id or r.id == id then out[#out + 1] = r end end
    return out
end
local function Queue(ns, id) return ns.db.carry["Tester-Realm"].items[id] end
local function QueueSum(ns, id)
    local s = 0
    for _, e in ipairs(Queue(ns, id) or {}) do s = s + e.n end
    return s
end
local function ChatHas(pattern)
    for _, line in ipairs(sim.chat) do if line:find(pattern) then return true end end
    return false
end
local function LogMatchesTotals(ns, label)
    local c = 0
    for _, r in ipairs(Rows(ns)) do if not r.bb and ns.DayKey(r.t) == ns.Today() then c = c + r.c end end
    eq(c, Today(ns).c, label .. ": log rows add up to today's total")
end

----------------------------------------------------------------------------
section("fresh install, with junk already in the bags")
GreyGoldDB = nil
sim.Add(100, 2)  -- 2 Broken Fang from before 2.1.0
local ns = sim.Load()
eq(ns.db.version, 4, "db version")
check(type(ns.db.carry) == "table", "carry table exists")
eq(QueueSum(ns, 100), 0, "junk from before tracking has no source")
eq(ns.junk.n, 2, "junk readout counts bags at login")
eq(ns.junk.c, 10, "junk readout value")

----------------------------------------------------------------------------
section("loot from a mob, mail, and protected items")
sim.zone = "Elwynn Forest"
sim.LootCorpse(KOBOLD, "Kobold Miner", { { 101, 1 }, { 200, 2 } })
sim.Advance(0.5)
local q = Queue(ns, 101)
check(q and q[1].k == "mob" and q[1].s == "Kobold Miner" and q[1].z == "Elwynn Forest", "Ripped Pants sourced to Kobold Miner in Elwynn")
check(Queue(ns, 200) == nil, "white items are not tracked")

sim.Mail(102, 1)
sim.Advance(0.5)
q = Queue(ns, 102)
check(q and q[1].k == "mail", "Tattered Vest came by mail")

sim.zone = "Westfall"
ns.db.neverSell[103], ns.db.neverSell[104], ns.db.neverSell[105] = true, true, true
ns.db.neverSell[106], ns.db.neverSell[107] = true, true
sim.LootCorpse(THUG, "Defias Thug", { { 103, 1 }, { 104, 1 }, { 105, 1 }, { 106, 1 }, { 107, 1 } })
sim.Advance(0.5)
eq(Queue(ns, 104)[1].s, "Defias Thug", "protected grey still gets a source")
sim.Add(201, 2)  -- two green swords
sim.Add(300, 1)  -- a grey without a sell value
sim.BagUpdate(); sim.Advance(0.5)
check(Queue(ns, 300) == nil, "grey without sell value is not tracked")

----------------------------------------------------------------------------
section("auto-sell at a vendor")
sim.zone = "Stormwind City"
sim.chat = {}
sim.OpenVendor()
sim.Advance(3)
local day = Today(ns)
eq(day.c, 10 + 23 + 40, "auto-sold copper")
eq(day.n, 4, "auto-sold items")
eq(day.v, 1, "one vendor visit")
check(ChatHas("sold 4 junk items"), "chat summary printed")
local r100, r101, r102 = Rows(ns, 100)[1], Rows(ns, 101)[1], Rows(ns, 102)[1]
check(r100 and r100.k == nil and r100.n == 2, "Broken Fang row: before tracking")
check(r101 and r101.k == "mob" and r101.s == "Kobold Miner" and r101.lz == "Elwynn Forest" and r101.z == "Stormwind City",
    "Ripped Pants row: Kobold Miner, looted Elwynn, sold Stormwind")
check(r102 and r102.k == "mail" and r102.lz == "Stormwind City" or r102.lz == "Elwynn Forest", "Tattered Vest row: mail")
for _, r in ipairs(Rows(ns)) do check(not r.m, "auto-sell rows are not 'by hand' (" .. r.id .. ")") end
eq(day.farm["Elwynn Forest"] and day.farm["Elwynn Forest"][1], 23, "farm credit only for looted junk")
eq(day.farm["Stormwind City"], nil, "mailed junk gets no farm credit")
eq(sim.Count(103), 1, "protected item not auto-sold")
LogMatchesTotals(ns, "after auto-sell")

----------------------------------------------------------------------------
section("hand sales at the same vendor")
local before = Today(ns).c
sim.RightClickSell(200)  -- white cloth
sim.Advance(4)
eq(Today(ns).c, before, "selling a white item adds nothing")
eq(#Rows(ns, 200), 0, "white item never logged")

sim.DragToVendor(103)    -- protected grey, 12c
sim.Destroy(104)         -- protected grey, also 12c, destroyed at the same moment
sim.Advance(4)
eq(Today(ns).c, before + 12, "hand sale counted once; destroyed grey not counted")
local r103 = Rows(ns, 103)[1]
check(r103 and r103.m and r103.k == "mob" and r103.s == "Defias Thug" and r103.lz == "Westfall", "hand-sold row keeps its source")
eq(#Rows(ns, 104), 0, "destroyed grey never logged")
eq(Today(ns).v, 1, "hand sales don't add a visit")
eq(QueueSum(ns, 104), 0, "destroyed grey's source forgotten")

before = Today(ns).c
sim.Equip(105)           -- grey shirt (30c) put on: leaves bags, no payment
sim.RightClickSell(201)  -- green sword (40c) sold at the same moment
sim.Advance(4)
eq(Today(ns).c, before, "equipped grey + sold green: nothing recorded")
eq(#Rows(ns, 105), 0, "equipped grey never logged")

before = Today(ns).c
sim.mergeMoney = true    -- the game reports several payments in one money update
sim.DragToVendor(106)
sim.DragToVendor(107)
sim.RightClickSell(201)  -- second green sword in the same update
sim.Advance(4)
sim.mergeMoney = false
eq(Today(ns).c, before + 7 + 9, "merged payment: both greys counted, the green's gold set aside")
eq(#Rows(ns, 201), 0, "green never logged")
LogMatchesTotals(ns, "after hand sales")

sim.moneyFirst = true
before = Today(ns).c
sim.Add(108, 2); sim.BagUpdate(); sim.Advance(0.3)
sim.RightClickSell(108)  -- payment arrives before the bag update
sim.Advance(4)
sim.moneyFirst = false
eq(Today(ns).c, before + 6, "hand sale with payment before bag update")

----------------------------------------------------------------------------
section("buyback, then sold again")
local total = Char(ns).total.c
local idx = sim.BuybackIndexOf(101)
check(idx ~= nil, "Ripped Pants is in the buyback list")
BuybackItem(idx)
sim.Advance(1)
eq(Char(ns).total.c, total - 23, "buyback cancels the sale in the totals")
check(Rows(ns, 101)[1].bb ~= nil, "row marked bought back")
eq(Today(ns).farm["Elwynn Forest"], nil, "farm credit taken back")
q = Queue(ns, 101)
check(q and q[1].k == "mob" and q[1].s == "Kobold Miner" and q[1].rb == 1, "source restored for the bought-back copy")
check(not ns.db.neverSell[101], "buyback does not protect the item")
sim.CloseVendor()
sim.Advance(4)
LogMatchesTotals(ns, "after buyback")

sim.OpenVendor()
sim.Advance(3)
local resold = Rows(ns, 101)[2]
check(resold and resold.rb == 1 and resold.s == "Kobold Miner" and not resold.bb, "re-sold row keeps the mob and is tagged")
eq(Char(ns).total.c, total, "selling again counts it once")
eq(Today(ns).farm["Elwynn Forest"][1], 23, "farm credit back on resale")
eq(Today(ns).v, 2, "second vendor visit")
sim.CloseVendor()
sim.Advance(4)

----------------------------------------------------------------------------
section("Shift-open: auto-sell skipped, sold by hand")
sim.zone = "Elwynn Forest"
sim.LootCorpse(KOBOLD, "Kobold Miner", { { 100, 3 } })
sim.Advance(0.5)
sim.shift = true
sim.OpenVendor()
sim.shift = false
sim.Advance(1)
eq(sim.Count(100), 3, "nothing auto-sold while Shift held")
before = Today(ns).c
sim.RightClickSell(100)
sim.Advance(4)
eq(Today(ns).c, before + 15, "hand sale after Shift-open")
local last = Rows(ns, 100)[#Rows(ns, 100)]
check(last.m and last.s == "Kobold Miner", "Shift-open hand sale row")
eq(Today(ns).v, 3, "Shift-open visit counted once")
sim.CloseVendor()
sim.Advance(4)

----------------------------------------------------------------------------
section("dungeon (hidden names), fishing, chest")
sim.zone = "The Deadmines"
sim.units.target = { guid = SECRET, name = SECRET, dead = true }
sim.LootCorpse(SECRET, nil, { { 100, 1 } }, false)
sim.Advance(0.5)
q = Queue(ns, 100)
check(q and q[#q].k == "mob" and q[#q].s == nil and q[#q].z == "The Deadmines", "hidden mob: unnamed creature, zone kept")
sim.units.target = nil
eq(ns.SourceLabel({ k = "mob" }), "Unknown creature", "unnamed creature label")

sim.zone = "Stormwind City"
sim.fishing = true
sim.LootCorpse("GameObject-0-1-0-1-35591-00000C", nil, { { 108, 1 } }, false)
sim.fishing = false
sim.Advance(0.5)
q = Queue(ns, 108)
check(q and q[#q].k == "fish", "fishing loot")

sim.Fire("UNIT_SPELLCAST_SENT", "player", "Battered Chest", "cast-1", 3365)
sim.LootCorpse("GameObject-0-1-0-1-2843-00000D", nil, { { 106, 1 } }, false)
sim.Advance(0.5)
q = Queue(ns, 106)
check(q and q[#q].k == "object" and q[#q].s == "Battered Chest", "chest named from the spell target")

----------------------------------------------------------------------------
section("bags full suggestion")
sim.chat = {}
local fillers = {}
while C_Container.GetContainerNumFreeSlots(0) > 0 do
    local id = 1000 + #fillers
    sim.Item(id, "Filler " .. id, 1, 1)
    sim.Add(id, 1)
    fillers[#fillers + 1] = id
end
sim.BagUpdate(); sim.Advance(0.5)
check(ChatHas("bags are full") and ChatHas("Chipped Claw"), "suggests the cheapest junk stack")
sim.chat = {}
sim.Fire("UI_ERROR_MESSAGE", 1, ERR_INV_FULL)
check(not ChatHas("bags are full"), "suggestion throttled")
sim.bags[sim.SlotOf(fillers[1])] = nil
sim.BagUpdate(); sim.Advance(0.5)
ns.db.suggest = false
sim.Add(fillers[1], 1); sim.BagUpdate(); sim.now = sim.now + 60; sim.Advance(0.5)
check(not ChatHas("bags are full"), "no suggestion when the setting is off")
ns.db.suggest = true
for _, id in ipairs(fillers) do sim.bags[sim.SlotOf(id)] = nil end
sim.BagUpdate(); sim.Advance(0.5)

----------------------------------------------------------------------------
section("milestone progress, junk readout, data feed, backpack label")
local goal, left, frac = ns.MilestoneProgress()
check(ns.LifetimeCopper() < 1000, "still below the first milestone here")
eq(goal, 1000, "first milestone is 10s")
eq(left, 1000 - ns.LifetimeCopper(), "copper still to go")
check(frac > 0 and frac < 1, "progress fraction")
local feed = sim.ldb["Grey Gold"]
check(feed ~= nil and feed.type == "data source", "data feed registered")
check(feed and feed.text:find("%(") ~= nil, "feed shows count and value: " .. tostring(feed and feed.text))
ContainerFrame1:Show()
sim.Advance(0.1)
local labelShown = false
for _, f in ipairs({ ContainerFrame1 }) do labelShown = true end
ns.FillTooltip(GameTooltip)
local hasMilestone = false
for _, l in ipairs(GameTooltip.lines) do if l:find("Next milestone") then hasMilestone = true end end
check(hasMilestone, "minimap tooltip shows the next milestone")

----------------------------------------------------------------------------
section("stats window: every tab builds and refreshes")
local UI = ns.UI
for tab = 1, 6 do
    local ok, err = pcall(ns.ShowWindow, tab)
    check(ok, "tab " .. tab .. " opens: " .. tostring(err))
end
eq(UI.frame._title, "Grey Gold v2.2.0", "window title shows the version")
ns.ShowWindow(5)
local logPanel
for _, child in pairs(UI.frame.body and {} or {}) do end
-- Exercise the Log tooltip through the panel's list rows.
local entries = ns.LogEntries("ALL")
check(#entries == #Rows(ns), "log entries for all characters")
eq(entries[1].t >= entries[#entries].t, true, "log newest first")
local found = false
for _, e in ipairs(entries) do if e.src == "Kobold Miner" then found = true end end
check(found, "log shows the mob name")
for range = 1, 4 do
    ns.db.ui.itemRange, ns.db.ui.zoneRange = range, range
    for _, tab in ipairs({ 3, 4 }) do
        local ok, err = pcall(ns.ShowWindow, tab)
        check(ok, "tab " .. tab .. " range " .. range .. ": " .. tostring(err))
    end
end
ns.db.ui.zoneMode = 2
check(pcall(ns.ShowWindow, 4), "zones sold-in mode")
local farmList = ns.ZoneTable("ALL", nil, nil, "farm")
check(#farmList >= 2, "farm zones listed")
local unc = ns.UncreditedTotal("ALL")
check(unc >= 40, "mail/before-tracking sales reported as uncredited: " .. unc)

----------------------------------------------------------------------------
section("old 2.0.0 day without farm data")
Char(ns).days["2025-01-01"] = { c = 50, n = 2, s = 1, v = 1, items = { [100] = { 2, 50 } }, zones = { ["Duskwood"] = { 50, 1 } } }
local ok, err = pcall(function()
    ns.ResetHistory("NOTHING")  -- clears the cache only
    ns.ZoneTable("ALL", nil, nil, "farm")
    ns.ZoneTable("Tester-Realm", nil, nil, "farm")
    ns.GetDays("ALL")
end)
check(ok, "old days without farm data: " .. tostring(err))

----------------------------------------------------------------------------
section("/reload keeps sources")
local session = ns.db.carry["Tester-Realm"].session
sim.zone = "Elwynn Forest"
sim.LootCorpse(KOBOLD, "Kobold Miner", { { 102, 1 } })
sim.Advance(0.5)
ns = sim.Load({ reload = true })
eq(ns.db.carry["Tester-Realm"].session, session, "session kept across reload")
sim.zone = "Stormwind City"
sim.OpenVendor()
sim.Advance(3)
local r = Rows(ns, 102)[#Rows(ns, 102)]
check(r.s == "Kobold Miner" and r.lz == "Elwynn Forest", "source survives /reload")
-- Buy back something sold before the reload (same session).
idx = sim.BuybackIndexOf(102)
BuybackItem(idx)
sim.Advance(1)
check(Rows(ns, 102)[#Rows(ns, 102)].bb ~= nil, "buyback after /reload still cancels the sale")
sim.CloseVendor()
sim.Advance(4)
LogMatchesTotals(ns, "after reload")

----------------------------------------------------------------------------
section("relog starts a new session")
sim.now = sim.now + 5
local t0 = os.time()
ns = sim.Load({ reload = false })
check(ns.db.carry["Tester-Realm"].session >= t0, "new session on login")

----------------------------------------------------------------------------
section("upgrade from 2.0.0 settings")
GreyGoldDB = { version = 2, ui = { tab = 5, scope = "ALL" }, chars = {}, neverSell = {}, names = {}, minimap = {} }
ns = sim.Load()
eq(ns.db.ui.tab, 6, "Settings tab remembered after the move")
check(ns.db.suggest == true and ns.db.bagLabel == true, "new options default on")

----------------------------------------------------------------------------
section("slash commands")
check(pcall(SlashCmdList.GREYGOLD, "settings"), "/greygold settings")
eq(ns.db.ui.tab, 6, "/greygold settings opens tab 6")
check(pcall(SlashCmdList.GREYGOLD, "help"), "/greygold help")

----------------------------------------------------------------------------
section("big auto-sell run (two batches), payments early and merged")
GreyGoldDB = nil
sim.bags = {}
sim.buyback = {}
ns = sim.Load()
sim.zone = "Duskwood"
local big = {}
for i = 1, 15 do
    local id = 2000 + i
    sim.Item(id, "Junk " .. i, 0, i)  -- prices 1..15c, all different
    big[#big + 1] = { id, 1 }
end
sim.LootCorpse("Creature-0-1-0-1-570-00000E", "Ghoul", big)
sim.Advance(0.5)
for _, mode in ipairs({ "moneyFirst", "mergeMoney" }) do
    GreyGoldDB.chars = {}
    for i = 1, 15 do if sim.Count(2000 + i) == 0 then sim.Add(2000 + i, 1) end end
    sim.BagUpdate(); sim.Advance(0.5)
    sim[mode] = true
    sim.OpenVendor()
    sim.Advance(5)
    sim[mode] = false
    eq(Today(ns).c, 120, mode .. ": whole run counted once (1+2+...+15)")
    local manual = 0
    for _, row in ipairs(Rows(ns)) do if row.m then manual = manual + 1 end end
    eq(manual, 0, mode .. ": no auto-sold item counted as a hand sale")
    sim.CloseVendor()
    sim.Advance(4)
    eq(Today(ns).c, 120, mode .. ": nothing added after the vendor closed")
end

----------------------------------------------------------------------------
section("hand sale and buyback while auto-sell is running")
-- The previous visit sold all 15 (120c); those rows and the buyback list are kept.
for i = 1, 15 do sim.Add(2000 + i, 1) end   -- slots 1-15, in order
ns.db.neverSell[103] = true
sim.Add(103, 1)
sim.BagUpdate(); sim.Advance(0.5)
sim.chat = {}
sim.OpenVendor()                -- first batch (12 items: 1c..12c = 78c) goes out
sim.Advance(0.05)
sim.DragToVendor(103)           -- by hand, during the run (12c)
BuybackItem(sim.BuybackIndexOf(2015))  -- the 15c item sold in the previous visit
sim.Advance(5)
check(ChatHas("auto%-sell stopped"), "run stops when something is bought back")
eq(sim.Count(2015), 2, "bought-back item is not sold again by the run")
eq(sim.Count(2013), 1, "the rest of the run is left unsold")
eq(#Rows(ns, 103), 1, "hand sale during the run recorded")
check(Rows(ns, 103)[1] and Rows(ns, 103)[1].m, "  ...as a hand sale")
eq(Today(ns).c, 120 + 78 + 12 - 15, "first batch + hand sale - the buyback")
local old2015 = Rows(ns, 2015)[1]
check(old2015 and old2015.bb, "the earlier sale of the bought-back item is cancelled")
for _, row in ipairs(Rows(ns)) do
    if row.id >= 2001 and row.id <= 2012 then check(not row.m, "batch item not marked by hand (" .. row.id .. ")") end
end
eq(Today(ns).v, 2, "still one visit for this vendor window")
LogMatchesTotals(ns, "buyback during a run")
SlashCmdList.GREYGOLD("sell")   -- sell the rest: 13c + 14c + 2 x 15c
sim.Advance(4)
eq(Today(ns).c, 195 + 57, "/greygold sell finishes the job")
local re = Rows(ns, 2015)
check(re[#re].rb == 1 or re[#re - 1].rb == 1, "re-sold copy is tagged")
LogMatchesTotals(ns, "after selling the rest")
sim.CloseVendor()
sim.Advance(4)

----------------------------------------------------------------------------
section("buyback then re-sale inside one vendor window keeps one visit")
GreyGoldDB.chars = {}
sim.bags = {}
sim.BagUpdate(); sim.Advance(0.5)
sim.LootCorpse("Creature-0-1-0-1-570-00000G", "Ghoul", { { 2001, 1 } })
sim.Advance(0.5)
sim.OpenVendor(); sim.Advance(3)
eq(Today(ns).v, 1, "one visit")
BuybackItem(sim.BuybackIndexOf(2001)); sim.Advance(1)
check(Today(ns) == nil, "day removed when its only sale is bought back")
SlashCmdList.GREYGOLD("sell"); sim.Advance(3)
eq(Today(ns).v, 1, "re-sale in the same window still shows one visit")
eq(Today(ns).zones["Duskwood"][2], 1, "zone visit count too")
sim.CloseVendor(); sim.Advance(4)

----------------------------------------------------------------------------
section("same price: a sold white item and an equipped grey")
sim.Item(2100, "Grey Hat", 0, 13)
sim.Add(2100, 1); sim.Add(200, 1)   -- Linen Cloth is also 13c
ns.db.neverSell[2100] = true
sim.BagUpdate(); sim.Advance(0.5)
sim.OpenVendor(); sim.Advance(1)
before = Today(ns).c
sim.Equip(2100)
sim.RightClickSell(200)
sim.Advance(4)
eq(Today(ns).c, before, "payment goes to the white item, the grey is not counted")
sim.CloseVendor(); sim.Advance(4)

----------------------------------------------------------------------------
section("an item put down long ago is not treated as destroyed")
sim.Add(2100, 1); sim.BagUpdate(); sim.Advance(0.5)
C_Container.PickupContainerItem(0, sim.SlotOf(2100))  -- pick up...
C_Container.PickupContainerItem(0, sim.SlotOf(2100))  -- ...and put back
sim.Fire("CURSOR_CHANGED")
sim.Advance(2)
DeleteCursorItem()              -- something else is deleted (nothing from the bags)
sim.OpenVendor(); sim.Advance(0.5)
before = Today(ns).c
sim.RightClickSell(2100)
sim.Advance(4)
eq(Today(ns).c, before + 13, "hand sale still counts")
sim.CloseVendor(); sim.Advance(4)

----------------------------------------------------------------------------
section("spell cast at a mob does not name a chest")
sim.units.target = { guid = "Creature-0-1-0-1-570-00000H", name = "Ghoul" }
sim.Fire("UNIT_SPELLCAST_SENT", "player", "Ghoul", "cast-2", 133)
sim.LootCorpse("GameObject-0-1-0-1-2843-00000J", nil, { { 2002, 1 } }, false)
sim.Advance(0.5)
q = Queue(ns, 2002)
check(q and q[#q].k == "object" and q[#q].s == nil, "chest is not named after the mob you cast at")
sim.units.target = nil

----------------------------------------------------------------------------
section("vendor closed in the middle of a run")
GreyGoldDB.chars = {}
for i = 1, 15 do if sim.Count(2000 + i) == 0 then sim.Add(2000 + i, 1) end end
sim.BagUpdate(); sim.Advance(0.5)
sim.OpenVendor()
sim.Advance(0.12)              -- first batch sent, answers on the way
sim.CloseVendor()
sim.Advance(5)
local sold = 0
for i = 1, 15 do if sim.Count(2000 + i) == 0 then sold = sold + i end end
eq(Today(ns) and Today(ns).c or 0, sold, "only what actually sold is counted")
for _, row in ipairs(Rows(ns)) do check(not row.m, "late answers are not hand sales (" .. row.id .. ")") end

----------------------------------------------------------------------------
section("backpack label and log tooltip")
ContainerFrame1:Hide()
ContainerFrame1:Show()
sim.Advance(0.1)
local label
for _, f in ipairs(sim.Frames()) do
    if f._kind == "FontString" and type(f._text) == "string" and f._text:find("Junk:") then label = f end
end
check(label ~= nil and label._parent._shown, "label shown next to the default backpack")
ns.db.bagLabel = false
ns.Notify("bags")
check(label and not label._parent._shown, "label hidden when turned off")
ns.db.bagLabel = true
ContainerFrame1:Hide()
sim.Advance(0.1)
check(label and not label._parent._shown, "label hidden with the backpack closed")

ns.ShowWindow(5)
local tippedSold, tippedFrom = false, false
for _, f in ipairs(sim.Frames()) do
    if f.item and f.item.row and f._shown and f._scripts.OnEnter then
        f._scripts.OnEnter(f)
        for _, l in ipairs(GameTooltip.lines) do
            if l:find("^Sold = ") then tippedSold = true end
            if l:find("^Came from = Other") then tippedFrom = true end
        end
    end
end
check(tippedSold and tippedFrom, "log row tooltip shows sale time and origin")

-- A looted item's tooltip names the mob.
GreyGoldDB.chars = {}
sim.LootCorpse("Creature-0-1-0-1-570-00000F", "Ghoul", { { 2001, 1 } })
sim.Advance(0.5)
sim.OpenVendor(); sim.Advance(3); sim.CloseVendor(); sim.Advance(4)
ns.ShowWindow(5)
local named = false
for _, f in ipairs(sim.Frames()) do
    if f.item and f.item.row and f.item.row.s == "Ghoul" and f._shown and f._scripts.OnEnter then
        f._scripts.OnEnter(f)
        for _, l in ipairs(GameTooltip.lines) do
            if l:find("^Looted from = Ghoul") then named = true end
        end
    end
end
check(named, "log row tooltip names the mob")

----------------------------------------------------------------------------
section("achievements: new milestone steps")
GreyGoldDB = nil
sim.bags = {}
sim.buyback = {}
ns = sim.Load()
sim.zone = "Elwynn Forest"
local steps = {}
for i = 1, 17 do steps[i] = ns.MilestoneCopper(i) end
eq(steps[1], 1000, "1st step 10s")
eq(steps[6], 67000, "6th step 6.7g")
eq(steps[15], 2000000, "15th step 200g")
eq(steps[16], 3000000, "after 200g: 300g")
eq(steps[17], 4000000, "then 400g")

sim.Item(3000, "Rusty Hinge", 0, 1000)      -- worth exactly 10s
sim.Item(3001, "Heavy Scrap", 0, 70000)     -- 7g: crosses 50s, 1g, 2g, 5g, 6.7g at once
sim.Add(3000, 1); sim.BagUpdate(); sim.Advance(0.5)
sim.chat = {}
sim.OpenVendor(); sim.Advance(3); sim.CloseVendor(); sim.Advance(4)
check(ChatHas("Junk milestone"), "10s milestone announced")
local a = ns.db.achieved["gold:1000"]
check(a and a.t and a.c == "Tester-Realm", "10s achievement stored with time and character")

sim.Add(3001, 1); sim.BagUpdate(); sim.Advance(0.5)
sim.chat = {}
sim.OpenVendor(); sim.Advance(3); sim.CloseVendor(); sim.Advance(4)
local announced = 0
for _, line in ipairs(sim.chat) do if line:find("Junk milestone") then announced = announced + 1 end end
eq(announced, 1, "one haul crossing several steps announces once (the highest)")
for _, c in ipairs({ 5000, 10000, 20000, 50000, 67000 }) do
    check(ns.db.achieved["gold:" .. c] and ns.db.achieved["gold:" .. c].t, "step " .. c .. " recorded")
end
check(ns.db.achieved["gold:100000"] == nil, "10g not reached yet")
local nextGoal = ns.MilestoneProgress()
eq(nextGoal, 100000, "next milestone 10g")

-- A buyback that drops below a reached step keeps it.
sim.OpenVendor(); sim.Advance(0.5)
BuybackItem(sim.BuybackIndexOf(3001)); sim.Advance(1)
check(ns.LifetimeCopper() < 67000, "buyback lowered the lifetime total")
check(ns.db.achieved["gold:67000"] ~= nil, "reached achievement kept after a buyback")
sim.CloseVendor(); sim.Advance(4)

-- The window.
ns.ShowWindow(1)
local okA, errA = pcall(ns.UI.ToggleAchievements)
check(okA, "Achievements window opens: " .. tostring(errA))
local rows, reachedCount = ns.AchievementList("Gold")
eq(#rows, 15, "15 gold steps listed below 200g")
eq(reachedCount, 6, "6 reached")
local okR = pcall(function() ns.Notify("data"); sim.Advance(0.1) end)
check(okR, "window refreshes on new data")
check(ns.UI.achievements.tabs == nil, "no category button when there is only one category")
local cardNames, cardChecks = 0, 0
for _, f in ipairs(sim.Frames()) do
    if f.item and f.item.category == "Gold" and f._shown then
        cardNames = cardNames + 1
        if f.check and f.check._shown then cardChecks = cardChecks + 1 end
    end
end
eq(cardNames, 15, "one card per achievement")
eq(cardChecks, 6, "reached cards show the check mark")
for _, f in ipairs(sim.Frames()) do
    if f.item and f.item.id == "gold:1000" and f._scripts.OnEnter then
        f._scripts.OnEnter(f)
        local sawReached = false
        for _, l in ipairs(GameTooltip.lines) do if l:find("^Reached = ") then sawReached = true end end
        check(sawReached, "card tooltip shows when it was reached")
    end
end

-- A test-only achievement in its own category: the system grows without changes.
local value = 0
ns.RegisterAchievement({ id = "test:one", category = "Test", name = "Test one",
    progress = function() return value, 5 end })
value = 5
sim.chat = {}
ns.CheckAchievements()
check(ns.db.achieved["test:one"] and ns.db.achieved["test:one"].t, "custom achievement detected and stored by id")
check(ChatHas("Achievement:") and ChatHas("Test one"), "custom achievement announced")
local trows = ns.AchievementList("Test")
eq(#trows, 1, "custom category listed")

-- History reset clears achievements whose condition no longer holds.
ns.ResetHistory("ALL")
check(ns.db.achieved["gold:1000"] == nil, "reset clears gold achievements")
check(ns.db.achieved["test:one"] ~= nil, "unrelated achievement still holds after reset")

----------------------------------------------------------------------------
section("achievements: upgrade from older steps announces nothing")
GreyGoldDB = { version = 3, milestone = 2, ui = { tab = 1, scope = "ALL" }, neverSell = {}, names = {}, minimap = {},
    chars = { ["Tester-Realm"] = { total = { c = 120000, n = 10, s = 1 }, best = {}, days = {} } } }
sim.chat = {}
ns = sim.Load()
check(not ChatHas("Junk milestone"), "no announcement on login after upgrading")
eq(ns.db.milestone, 7, "level re-counted against the new steps (12g = 7 steps)")
local old = ns.db.achieved["gold:100000"]
check(old and old.old and not old.t, "already-passed step marked reached without a date")
check(ns.db.achieved["gold:150000"] == nil, "15g not reached")
eq(ns.db.version, 4, "db version 4")

----------------------------------------------------------------------------
section("long-term history: months, years, mob totals")
GreyGoldDB = nil
sim.bags = {}
sim.buyback = {}
ns = sim.Load()
sim.zone = "Westfall"
sim.LootCorpse("Creature-0-1-0-1-450-00000K", "Defias Thug", { { 2001, 2 }, { 2002, 1 } })
sim.Advance(0.5)
sim.zone = "Stormwind City"
sim.OpenVendor(); sim.Advance(3)
local ch = ns.db.chars["Tester-Realm"]
local ym = ns.Today():sub(1, 7)
local src = ch.months and ch.months[ym] and ch.months[ym].src
check(src and src["Defias Thug"] and src["Defias Thug"][1] == 4 and src["Defias Thug"][2] == 3,
    "monthly mob total recorded (4c, 3 items)")
eq(ch.total.s, 2, "two bag slots freed")
local drops, dropTotal = ns.SourceTable("ALL")
check(drops[1] and drops[1].name == "Defias Thug" and dropTotal == 4, "Dropped by lists the mob")

BuybackItem(sim.BuybackIndexOf(2002)); sim.Advance(1)
eq(src["Defias Thug"][1], 2, "buyback lowers the mob total")
eq(ch.total.s, 1, "buyback lowers bag slots freed")
sim.CloseVendor(); sim.Advance(4)

-- Older data: two earlier months and a previous year.
local function Past(key, copper)
    ch.days[key] = { c = copper, n = 1, s = 1, v = 1, items = { [2001] = { 1, copper } },
                     zones = { ["Stormwind City"] = { copper, 1 } }, farm = {} }
end
local y = tonumber(ns.Today():sub(1, 4))
Past(format("%04d-03-10", y - 1), 500)
Past(format("%04d-03-20", y - 1), 700)
Past(format("%04d-07-01", y - 1), 100)
ns.ResetHistory("NOTHING")  -- clears the cache only

local months = ns.Periods("ALL", "month")
local march
for _, m in ipairs(months) do if m.key == format("%04d-03-01", y - 1) then march = m end end
check(march and march.c == 1200 and march.active == 2 and march.length == 31, "March of last year: 12s over 2 days, 31 days long")
eq(march and march.to, format("%04d-03-31", y - 1), "month ends on its last day")
local years = ns.Periods("ALL", "year")
eq(#years, 2, "two years with sales")
eq(years[2].c, 1300, "last year's total")
eq(years[2].length, (((y - 1) % 4 == 0 and (y - 1) % 100 ~= 0) or (y - 1) % 400 == 0) and 366 or 365, "a full year's length")
check(years[1].length <= 366 and years[1].length >= 1, "this year counts days so far")

local ms = ns.Series("ALL", "month", 12)
eq(#ms, 12, "12 monthly bars")
check(ms[12].current and ms[12].key == ns.Today():sub(1, 7) .. "-01", "last bar is this month")
local ys = ns.Series("ALL", "year", 5)
eq(ys[4].c, 1300, "yearly bar for last year")
eq(ns.Records("ALL").bestMonth.key, format("%04d-03-01", y - 1), "best month record")
eq(ns.FormatPeriod("year", years[2].key), tostring(y - 1), "year title")

for _, k in ipairs({ "day", "week", "month", "year" }) do
    local okH, errH = pcall(function()
        ns.UI.OpenHistory(k, ns.Periods("ALL", k)[1].key)
        sim.Advance(0.1)
    end)
    check(okH, "History opens in " .. k .. " mode: " .. tostring(errH))
end
for mode = 1, 3 do
    ns.db.ui.zoneMode = mode
    for range = 1, 4 do
        ns.db.ui.zoneRange = range
        local okZ, errZ = pcall(ns.ShowWindow, 4)
        check(okZ, "Zones view " .. mode .. " range " .. range .. ": " .. tostring(errZ))
    end
end
ns.FillTooltip(GameTooltip)
local junkLine = false
for _, l in ipairs(GameTooltip.lines) do if l:find("junk in your bags") or l:find("Junk in bags now") then junkLine = true end end
check(junkLine, "minimap tooltip shows the junk readout without its own scan")
check(ns.ScanBags == nil, "duplicate bag scan removed")

-- "Dropped by" is kept per month: its footer names the months really shown.
ns.db.ui.zoneMode = 3
for range, want in pairs({ [1] = "showing all of " .. date("%B %Y"), [4] = false }) do
    ns.db.ui.zoneRange = range
    ns.ShowWindow(4)
    sim.Advance(0.1)
    local found = false
    for _, f in ipairs(sim.Frames()) do
        if f._shown and tostring(f._text):find("counted per month", 1, true) then
            found = f._text:find(want or "\0", 1, true) and true or "other"
        end
    end
    eq(found, want and true or false, "Dropped by footer for range " .. range)
end

----------------------------------------------------------------------------
-- Scenarios from the November 2026 review
----------------------------------------------------------------------------
local realUse = C_Container.UseContainerItem
local function Fresh()
    GreyGoldDB = nil
    sim.bags, sim.buyback, sim.units, sim.chat = {}, {}, {}, {}
    sim.money, sim.shift, sim.mergeMoney, sim.moneyFirst = 0, false, false, false
    sim.merchantOpen, sim.fishing, sim.cursor, sim.used = false, false, nil, 0
    sim.zone = "Elwynn Forest"
    C_Container.UseContainerItem = realUse
    return sim.Load()
end
local function BySource(n, id)
    local out = {}
    for _, e in ipairs(Queue(n, id) or {}) do
        local s = e.s or e.k or "none"
        out[s] = (out[s] or 0) + e.n
    end
    return out
end
local function Hover(guid, name)
    sim.units.mouseover = { guid = guid, name = name }
    sim.Fire("UPDATE_MOUSEOVER_UNIT")
end
local WOLF, BOAR, BEAR = "Creature-0-1-0-1-111-0000AA", "Creature-0-1-0-1-222-0000BB", "Creature-0-1-0-1-333-0000CC"

section("review: a refused sale whose item moved to another slot is not a sale")
ns = Fresh()
sim.Add(100, 1)
sim.BagUpdate(); sim.Advance(0.5)
C_Container.UseContainerItem = function() end  -- the vendor refuses it
sim.OpenVendor()
do
    local slot = sim.SlotOf(100)
    sim.bags[10], sim.bags[slot] = sim.bags[slot], nil
end
sim.BagUpdate(); sim.Advance(8)
eq(sim.money, 0, "refused: no gold received")
eq(sim.Count(100), 1, "refused: item still held")
eq(ns.LifetimeCopper(), 0, "refused and moved: nothing recorded")
eq(Char(ns) and #Rows(ns) or 0, 0, "refused and moved: no log row")
check(not ChatHas("sold %d"), "refused and moved: no sale announced")
sim.CloseVendor(); sim.Advance(4)
eq(ns.LifetimeCopper(), 0, "refused and moved: still nothing after the vendor closes")
C_Container.UseContainerItem = realUse

section("review: an item that moved and then sold counts once")
ns = Fresh()
sim.Add(100, 3)
sim.BagUpdate(); sim.Advance(0.5)
sim.OpenVendor()  -- the sale of slot 1 is on its way...
do
    local slot = sim.SlotOf(100)
    local stack = sim.bags[slot]
    sim.bags[10], sim.bags[slot] = stack, nil  -- ...but the stack moves first
    stack.locked = false
end
sim.BagUpdate(); sim.Advance(5)
eq(sim.Count(100), 0, "moved: sold from its new slot")
eq(sim.money, 15, "moved: paid once")
eq(ns.LifetimeCopper(), 15, "moved then sold: recorded once")
eq(Today(ns).items[100][1], 3, "moved then sold: 3 units, not 6")
LogMatchesTotals(ns, "moved then sold")
sim.CloseVendor(); sim.Advance(4)
eq(ns.LifetimeCopper(), 15, "moved then sold: unchanged after the vendor closes")

section("review: vendor closed mid-run and opened again at once")
ns = Fresh()
for i = 1, 15 do
    sim.Item(4000 + i, "Scrap " .. i, 0, i)  -- 1c..15c: 12 go in the first batch
    sim.Add(4000 + i, 1)
end
sim.BagUpdate(); sim.Advance(0.5)
sim.OpenVendor()        -- first batch of 12 goes out
sim.Advance(0.15)       -- ...and lands
sim.CloseVendor()       -- closed before the second batch
sim.zone = "Goldshire"
sim.Advance(0.1)        -- the run notices and waits to be counted
sim.OpenVendor()        -- another vendor, before that count
sim.Advance(6)
do
    eq(sim.money, 120, "reopened: every item sold")
    eq(ns.LifetimeCopper(), 120, "reopened: every sale counted once")
    local elwynn, goldshire = Today(ns).zones["Elwynn Forest"], Today(ns).zones["Goldshire"]
    eq(elwynn and elwynn[1], 78, "reopened: first run stays with its own visit (1c..12c)")
    eq(goldshire and goldshire[1], 42, "reopened: second run in the new zone (13c..15c)")
    local manual = 0
    for _, r in ipairs(Rows(ns)) do if r.m then manual = manual + 1 end end
    eq(manual, 0, "reopened: no auto-sale mistaken for a hand sale")
end
sim.CloseVendor(); sim.Advance(4)

section("review: two stacks of one item, only one of them sells")
ns = Fresh()
sim.bags[1], sim.bags[2] = { id = 100, n = 2 }, { id = 100, n = 4 }
sim.BagUpdate(); sim.Advance(0.5)
C_Container.UseContainerItem = function(bag, slot) if slot == 1 then realUse(bag, slot) end end
sim.OpenVendor(); sim.Advance(8)
eq(sim.money, 10, "one of two stacks: paid for the stack of 2")
eq(ns.LifetimeCopper(), 10, "one of two stacks: only the sold stack recorded")
C_Container.UseContainerItem = realUse
sim.CloseVendor(); sim.Advance(4)

section("review: a price the game hasn't loaded yet is not a price of zero")
ns = Fresh()
do
    local realInfo = ns.GetItemInfo
    ns.GetItemInfo = function() return nil end
    sim.Add(100, 2)
    sim.BagUpdate(); sim.Advance(0.5)
    C_Timer.After(0.4, function() ns.GetItemInfo = realInfo end)
    sim.OpenVendor()
    eq(sim.Count(100), 2, "unknown price: nothing sold while it is unknown")
    sim.Advance(4)
    eq(sim.money, 10, "price arrived: items sold")
    eq(sim.Count(100), 0, "price arrived: bags empty")
    eq(ns.LifetimeCopper(), 10, "price arrived: sale recorded at its real value")
    LogMatchesTotals(ns, "late price")
    sim.CloseVendor(); sim.Advance(4)

    -- A price that never arrives: nothing is sold, nothing recorded, one notice.
    ns = Fresh()
    ns.GetItemInfo = function() return nil end
    sim.Add(100, 2)
    sim.BagUpdate(); sim.Advance(0.5)
    sim.chat = {}
    sim.OpenVendor(); sim.Advance(15)
    eq(sim.Count(100), 2, "price never arrives: item kept")
    eq(ns.LifetimeCopper(), 0, "price never arrives: nothing recorded")
    local notices = 0
    for _, line in ipairs(sim.chat) do if line:find("hasn't loaded its price") then notices = notices + 1 end end
    eq(notices, 1, "price never arrives: said once")
    sim.CloseVendor(); sim.Advance(1)
    eq(sim.used, 0, "price never arrives: nothing used after the vendor closed")
    sim.Advance(4)
end

section("review: the same item from two mobs keeps both sources")
ns = Fresh()
sim.LootCorpse(WOLF, "Wolf", { { 100, 1 } })
sim.LootCorpse(BOAR, "Boar", { { 100, 1 } })  -- before the bag update of the first
sim.Advance(0.5)
do
    local by = BySource(ns, 100)
    eq(by.Wolf, 1, "two corpses, one bag update: Wolf")
    eq(by.Boar, 1, "two corpses, one bag update: Boar")
    eq(QueueSum(ns, 100), 2, "two corpses: two copies tracked")
end

ns = Fresh()
sim.LootCorpse(WOLF, "Wolf", { { 100, 1 } })
sim.LootCorpse(BOAR, "Boar", { { 100, 3 } })
sim.LootCorpse(BEAR, "Bear", { { 100, 2 } })
sim.Advance(0.5)
do
    local by = BySource(ns, 100)
    check(by.Wolf == 1 and by.Boar == 3 and by.Bear == 2, "three corpses with different amounts keep their own")
end

section("review: area loot, one slot holding copies from several corpses")
ns = Fresh()
Hover(WOLF, "Wolf"); Hover(BOAR, "Boar")
sim.LootCorpse(WOLF, "Wolf", { { 100, 3, sources = { { WOLF, 1 }, { BOAR, 2 } } }, { 101, 1 } }, false)
sim.Advance(0.5)
do
    local by = BySource(ns, 100)
    eq(by.Wolf, 1, "area loot: Wolf's copy")
    eq(by.Boar, 2, "area loot: Boar's copies")
    eq(BySource(ns, 101).Wolf, 1, "area loot: single-source slot")
    sim.OpenVendor(); sim.Advance(3)
    local sold = {}
    for _, r in ipairs(Rows(ns, 100)) do sold[r.s or "none"] = (sold[r.s or "none"] or 0) + r.n end
    check(sold.Wolf == 1 and sold.Boar == 2, "area loot: the sale is logged per mob")
    eq(ns.LifetimeCopper(), 38, "area loot: 3 fangs and a pair of pants")
    sim.CloseVendor(); sim.Advance(4)
end

section("review: loot left on the corpse gives no credit")
ns = Fresh()
sim.LootCorpse(WOLF, "Wolf", { { 100, 1 } })
sim.Advance(0.5)
do  -- the Boar's fang below is offered but not taken
    Hover(BOAR, "Boar")
    local held = sim.Count(100)
    sim.LootCorpse(BOAR, "Boar", { { 100, 1 } }, false)
    sim.bags[sim.SlotOf(100)].n = held  -- bags were full: it stayed on the corpse
    sim.Advance(0.5)
    local by = BySource(ns, 100)
    check(by.Wolf == 1 and by.Boar == nil, "an untaken copy is not credited")
end

section("review: more arrives than the loot window offered")
ns = Fresh()
sim.LootCorpse(WOLF, "Wolf", { { 100, 1 } })
sim.Add(100, 2)  -- two more from somewhere else, seen in the same bag update
sim.Advance(0.5)
do
    local by = BySource(ns, 100)
    eq(by.Wolf, 1, "extra copies: the Wolf gets only what it dropped")
    eq(by.other, 2, "extra copies: the rest has no mob")
end

print(format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
