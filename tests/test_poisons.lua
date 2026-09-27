-- #24: rogue poisons, one button per hand (experimental).

dofile("tests/wow_stubs.lua")
local H = dofile("tests/harness.lua")

local MH_WEAPON, OH_WEAPON, SHIELD = 2169, 2209, 2129
WoW.itemClass[MH_WEAPON] = { 2, 15 }     -- daggers
WoW.itemClass[OH_WEAPON] = { 2, 15 }
WoW.itemClass[SHIELD]    = { 4, 6 }
WoW.class, WoW.level = "ROGUE", 25
WoW.lfgRoles = { damage = true }
WoW.equipped = { [16] = MH_WEAPON, [17] = OH_WEAPON }
WoW.AddItem(0, 1, 6947, 10, "Instant Poison")         -- L20
WoW.AddItem(0, 2, 6949, 10, "Instant Poison II")      -- L28
WoW.AddItem(0, 3, 2892, 10, "Deadly Poison")          -- L30
WoW.AddItem(0, 4, 3775, 10, "Crippling Poison")       -- L20
H.loadAddon()

local D = Apotheca.DATA
local mh, oh = Apotheca.buttons.poisonmh, Apotheca.buttons.poisonoh
local function prof() return ApothecaDB.profiles[ApothecaDB.activeProfile] end
local function update() Apotheca.UpdateAllButtons() end
local function on(b) return b:IsShown() and b.itemID ~= nil end
local function glowing(b) local o = b.__apothecaGlow return o ~= nil and not o.animOut:IsPlaying() end

------------------------------------------------------------
-- Data (generated from the 70009 scan)
------------------------------------------------------------
local families, items = 0, 0
for _, list in pairs(D.POISONS) do
    families = families + 1
    items = items + #list
    for i = 2, #list do
        if list[i].rank > list[i - 1].rank then H.check(false, "poisons are ordered highest rank first") end
    end
end
H.eq(families, 9, "nine poison families")
H.eq(items, 25, "25 poisons")
local testItem = false
for _, list in pairs(D.POISONS) do for _, e in ipairs(list) do if e.id == 202316 then testItem = true end end end
H.check(not testItem, "the Runecarving Test poison is left out")
H.eq(D.POISONS.instant[1].id, 8928, "Instant Poison VI first")
H.eq(D.POISON_FAMILIES[1].key .. "," .. D.POISON_FAMILIES[2].key, "instant,deadly", "Instant and Deadly listed first")

------------------------------------------------------------
-- The buttons
------------------------------------------------------------
H.check(not on(mh) and not on(oh), "off by default: experimental, opt-in")

prof().poisons.enabled = true
update()
H.eq(mh.itemID, 6947, "main hand: Instant Poison, the strongest Instant usable at level 25")
H.eq(mh:GetAttribute("target-slot"), 16, "aimed at the main hand")
H.eq(mh:GetAttribute("item"), "item:6947", "for that item")
H.check(not on(oh), "off hand: Deadly needs level 30, and no other family is offered")

WoW.level = 30
update()
H.eq(mh.itemID, 6949, "at level 30: Instant Poison II")
H.eq(oh.itemID, 2892, "and Deadly Poison on the off hand")
H.eq(oh:GetAttribute("target-slot"), 17, "aimed at the off hand")

-- The choice is per character, and changing it updates the button.
Apotheca.SetPoisonChoice(16, "crippling")
for _ = 1, 3 do WoW.tick(0.1) end
H.eq(mh.itemID, 3775, "choosing Crippling updates the main hand button")
H.eq(ApothecaCharDB.poisonMH, "crippling", "saved per character")
Apotheca.SetPoisonChoice(16, "none")
for _ = 1, 3 do WoW.tick(0.1) end
H.check(not mh:IsShown(), "None: no main hand button")
ApothecaCharDB.poisonMH = "sausage"
update()
H.eq(mh.itemID, 6949, "an unknown saved family falls back to Instant")
ApothecaCharDB.poisonMH = nil

-- Not a rogue: nothing.
WoW.class = "WARRIOR"
update()
H.check(not mh:IsShown() and not oh:IsShown(), "not for other classes")
WoW.class = "ROGUE"
update()

-- A shield or no weapon in the off hand: no off-hand button; a weapon
-- swap updates it through PLAYER_EQUIPMENT_CHANGED.
WoW.equipped[17] = SHIELD
WoW.fire("PLAYER_EQUIPMENT_CHANGED", 17, false)
for _ = 1, 3 do WoW.tick(0.1) end
H.check(not oh:IsShown(), "a shield in the off hand: no off-hand poison")
WoW.equipped[17] = OH_WEAPON
WoW.fire("PLAYER_EQUIPMENT_CHANGED", 17, false)
for _ = 1, 3 do WoW.tick(0.1) end
H.eq(oh.itemID, 2892, "a weapon back: the off-hand poison returns")

-- The target is cleared with the item.
WoW.bags[0][1], WoW.bags[0][2] = nil, nil
update()
H.eq(mh:GetAttribute("target-slot"), nil, "no poison left: target-slot cleared with the item")
WoW.AddItem(0, 1, 6947, 10, "Instant Poison")
WoW.AddItem(0, 2, 6949, 10, "Instant Poison II")
update()

------------------------------------------------------------
-- Glows
------------------------------------------------------------
WoW.enchants = {}
WoW.fire("READY_CHECK")
H.check(glowing(mh) and glowing(oh), "ready check: both uncoated hands glow")
WoW.enchants[16] = { true, 1800000, 40, 323 }
WoW.fire("WEAPON_ENCHANT_CHANGED")
H.check(not glowing(mh) and glowing(oh), "the main hand coated: its glow goes (WEAPON_ENCHANT_CHANGED)")
WoW.enchants[17] = { WoW.Secret(false), nil, nil, nil }
WoW.fire("WEAPON_ENCHANT_CHANGED")
H.check(not glowing(oh), "unreadable: no glow")
WoW.fire("READY_CHECK_FINISHED")
WoW.enchants = {}

-- After combat: only when the reminder is switched on.
local function combat() WoW.enterCombat() ; WoW.leaveCombat() ; for _ = 1, 3 do WoW.tick(0.1) end end
combat()
H.check(not glowing(mh), "no reminder after combat by default")
prof().poisons.remind = true
combat()
H.check(glowing(mh) and glowing(oh), "with the reminder on: both glow after combat")
WoW.tick(6)
H.check(not glowing(mh), "for a few seconds")
prof().poisons.remind = false

-- Ready-check glow switched off.
prof().poisons.glowOnMissingBuff = false
WoW.fire("READY_CHECK")
H.check(not glowing(mh), "ready-check glow switched off")
WoW.fire("READY_CHECK_FINISHED")

H.done("test_poisons")
