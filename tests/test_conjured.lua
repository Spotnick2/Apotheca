-- #96: offer the conjured food and drink too when a bought one is picked
-- (offerConjuredToo, off by default).

dofile("tests/wow_stubs.lua")
local H = dofile("tests/harness.lua")

WoW.class, WoW.level, WoW.lfgRoles = "PRIEST", 60, { healer = true }
WoW.AddItem(0, 1, 1645, 5, "Moonberry Juice")             -- 1915 mana, bought
WoW.AddItem(0, 2, 2136, 20, "Conjured Purified Water")    -- 803 mana, conjured
WoW.AddItem(0, 3, 4599, 5, "Cured Ham Steak")             -- 1338 health, bought
WoW.AddItem(0, 4, 1114, 20, "Conjured Rye")               -- 530 health, conjured
H.loadAddon()

local B = Apotheca.buttons
local function prof() return ApothecaDB.profiles[ApothecaDB.activeProfile] end
local function update() Apotheca.UpdateAllButtons() end
local function on(b) return b:IsShown() and b.itemID ~= nil end

eq(prof().offerConjuredToo, false, "off by default")
update()
eq(B.drink.itemID, 1645, "the bought water is 1.5x better: Drink offers it")
eq(B.food.itemID, 4599, "and Food the bought food")
check(not on(B.conjdrink) and not on(B.conjfood), "off: no conjured buttons")
eq(B.conjdrink:GetAttribute("item"), nil, "and the hidden button has no item (its key does nothing)")

prof().offerConjuredToo = true
update()
eq(B.drink.itemID, 1645, "on: Drink still offers the bought water")
eq(B.conjdrink.itemID, 2136, "and Conjured Drink the conjured one")
eq(B.conjfood.itemID, 1114, "Conjured Food the conjured food")
check(on(B.conjdrink) and on(B.conjfood), "both shown")
local pos = {}
for i, k in ipairs(Apotheca.GetButtonOrder()) do pos[k] = i end
check(pos.conjfood == pos.food + 1 and pos.conjdrink == pos.drink + 1,
    "each next to its twin in the default order")
eq(_G["BINDING_NAME_" .. Apotheca.BindingAction("conjdrink")], "Conjured Drink", "a key binding label")

-- The conjured one wins already (within the threshold): nothing extra.
prof().conjuredThreshold = 3.0
update()
eq(B.drink.itemID, 2136, "the conjured water wins: Drink offers it")
check(not on(B.conjdrink), "and no Conjured Drink button repeats it")
prof().conjuredThreshold = 1.5

-- No conjured item held: nothing extra.
WoW.bags[0][2] = nil
update()
eq(B.drink.itemID, 1645, "no conjured water: the bought one")
check(not on(B.conjdrink), "no Conjured Drink button")
check(on(B.conjfood), "the food's twin is unaffected")

-- Only conjured held: Drink offers it, no twin.
WoW.AddItem(0, 2, 2136, 20, "Conjured Purified Water")
WoW.bags[0][1] = nil
update()
eq(B.drink.itemID, 2136, "only conjured water: Drink offers it")
check(not on(B.conjdrink), "and no twin")

-- Switched off again: gone, item cleared.
WoW.AddItem(0, 1, 1645, 5, "Moonberry Juice")
prof().offerConjuredToo = false
update()
check(not on(B.conjfood) and not on(B.conjdrink), "off again: gone")
eq(B.conjfood:GetAttribute("item"), nil, "and no item left on the button")

done("test_conjured")
