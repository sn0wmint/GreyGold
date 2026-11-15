-- Grey Gold: achievements.
--
-- A small registry: each achievement is one entry with a progress function
-- that returns (current, goal). It is reached when current >= goal, and the
-- time and character are saved under its id in GreyGoldDB.achieved. Adding a new
-- kind of achievement (zones, items, mobs...) only means registering more
-- entries with their own category; storage and the window stay the same.
--
-- This version has one category: the gold milestones (10s, 50s, 1g ... 200g,
-- then every 100g). Their chat announcement still comes from Stats.lua.

local ADDON, ns = ...

local list, byId, categories = {}, {}, {}

-- def = { id, category, name, desc, progress = function() return current, goal end, silent }
-- silent: don't print "Achievement: ..." (gold milestones have their own announcement).
function ns.RegisterAchievement(def)
    if byId[def.id] then return byId[def.id] end
    def.order = #list + 1
    list[#list + 1] = def
    byId[def.id] = def
    local known = false
    for _, c in ipairs(categories) do if c == def.category then known = true end end
    if not known then categories[#categories + 1] = def.category end
    return def
end

function ns.AchievementCategories() return categories end

----------------------------------------------------------------------------
-- Gold milestones
----------------------------------------------------------------------------
-- Coin icon that grows with the milestone: copper, silver, gold, a pile of gold.
local function CoinIcon(copper)
    if copper < 10000 then return "Interface\\Icons\\INV_Misc_Coin_05" end
    if copper < 100000 then return "Interface\\Icons\\INV_Misc_Coin_03" end
    if copper < 1000000 then return "Interface\\Icons\\INV_Misc_Coin_01" end
    return "Interface\\Icons\\INV_Misc_Coin_02"
end

-- A title and a line of flavour for each fixed step, in order.
local TITLES = {
    { "Pocket Change",        "Everyone starts with a handful of broken fangs." },
    { "Silver Lining",        "Somebody's trash is your silver." },
    { "First Gold",           "A whole gold coin, and all of it from junk." },
    { "Junk Dealer",          "The vendors are starting to recognise you." },
    { "Rag Trader",           "Torn cloaks and cracked bones add up." },
    { "Oddly Specific",       "Six gold and seventy silver. Not a copper less." },
    { "Scrap Merchant",       "Ten gold from things nobody wanted." },
    { "Vendor's Favourite",   "They smile when they see your bags." },
    { "Grey Market",          "You deal only in the finest rubbish." },
    { "Bag Emptier",          "Your bags have never been lighter, or your purse heavier." },
    { "Trash Baron",          "A small fortune, built one bent spoon at a time." },
    { "Half a Hundred",       "Fifty gold. The junk pile salutes you." },
    { "Junk Tycoon",          "Others walk past grey items. You know better." },
    { "Lord of Leftovers",    "What the world throws away, you turn into gold." },
    { "Grey Gold Magnate",    "Two hundred gold from junk. You are what this addon is named for." },
}
local BEYOND = { "Mountain of Junk", "And still the junk keeps coming." }

local function GoldStep(i)
    local copper = ns.MilestoneCopper(i)
    local t = TITLES[i] or BEYOND
    return ns.RegisterAchievement({
        id = "gold:" .. copper,
        category = "Gold",
        icon = CoinIcon(copper),
        name = t[1],
        amount = ns.Money(copper),
        flavor = t[2],
        desc = "Earn " .. ns.Money(copper) .. " from junk, on all your characters together.",
        progress = function() return ns.LifetimeCopper(), copper end,
        silent = true,
    })
end

-- "Pocket Change" for 1000 copper; nil if that step has no achievement yet.
function ns.MilestoneTitle(copper)
    local def = byId["gold:" .. copper]
    return def and def.name
end

-- The fixed steps up front; after 200g, steps are added as you get there,
-- always one beyond what you have reached.
for i = 1, ns.MILESTONE_COUNT do GoldStep(i) end

local function EnsureGoldSteps()
    local level = ns.MilestoneLevel(ns.LifetimeCopper())
    for i = ns.MILESTONE_COUNT + 1, level + 1 do GoldStep(i) end
end

----------------------------------------------------------------------------
-- Checking and storage
----------------------------------------------------------------------------
-- silent: record without a time and without announcing (upgrade from older versions).
function ns.CheckAchievements(silent)
    local db = ns.db
    if not db or not db.achieved then return end
    EnsureGoldSteps()
    for _, def in ipairs(list) do
        if not db.achieved[def.id] then
            local current, goal = def.progress()
            if current and goal and current >= goal then
                if silent then
                    db.achieved[def.id] = { old = true }
                else
                    db.achieved[def.id] = { t = time(), c = ns.PlayerKey() }
                    if not def.silent and db.milestones then
                        ns.Print("|cffffd100Achievement:|r " .. def.name)
                    end
                end
            end
        end
    end
end

-- After a history reset: forget achievements whose condition no longer holds.
function ns.PruneAchievements()
    for id in pairs(ns.db.achieved) do
        local def = byId[id]
        local current, goal
        if def then
            current, goal = def.progress()
        else
            goal = tonumber(id:match("^gold:(%d+)$"))  -- a 100g step not registered this session
            current = goal and ns.LifetimeCopper()
        end
        if current and goal and current < goal then ns.db.achieved[id] = nil end
    end
end

-- Rows for the Achievements window, in their natural order.
function ns.AchievementList(category)
    EnsureGoldSteps()
    local rows, reached = {}, 0
    for _, def in ipairs(list) do
        if def.category == category then
            local current, goal = def.progress()
            local a = ns.db.achieved[def.id]
            rows[#rows + 1] = {
                id = def.id, order = def.order, name = def.name, desc = def.desc, category = def.category,
                icon = def.icon, amount = def.amount, flavor = def.flavor,
                reached = a ~= nil, t = a and a.t, who = a and a.c,
                current = current or 0, goal = goal or 0, t0 = a and a.t or 0,
            }
            if a then reached = reached + 1 end
        end
    end
    return rows, reached
end

ns.RegisterCallback(function(kind)
    if kind == "init" then
        if ns.upgradeAchievements then ns.CheckAchievements(true) end
    elseif kind == "data" then
        ns.CheckAchievements(false)
    end
end)
