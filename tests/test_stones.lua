-- #32: weapon stones, per character and per hand (experimental).

dofile("tests/wow_stubs.lua")
local H = dofile("tests/harness.lua")

local SWORD, MACE, FIST, STAFF, POLE = 2244, 2245, 2246, 2042, 6256
WoW.itemClass[SWORD] = { 2, 7, "One-Handed Swords" }
WoW.itemClass[MACE]  = { 2, 4, "One-Handed Maces" }
WoW.itemClass[FIST]  = { 2, 13, "Fist Weapons" }
WoW.itemClass[STAFF] = { 2, 10, "Staves" }
WoW.itemClass[POLE]  = { 2, 20, "Fishing Poles" }
WoW.class, WoW.level, WoW.lfgRoles = "WARRIOR", 60, { damage = true }
WoW.equipped = { [16] = SWORD, [17] = MACE }
WoW.AddItem(0, 1, 12404, 5, "Dense Sharpening Stone")
WoW.AddItem(0, 2, 12643, 5, "Dense Weightstone")
WoW.AddItem(0, 3, 18262, 5, "Elemental Sharpening Stone")
H.loadAddon()

local D = Apotheca.DATA
local mh, oh = Apotheca.buttons.stonemh, Apotheca.buttons.stoneoh
local oil = Apotheca.buttons.weaponoil
local function prof() return ApothecaDB.profiles[ApothecaDB.activeProfile] end
local function update() Apotheca.UpdateAllButtons() end
local function settle() for _ = 1, 3 do WoW.tick(0.1) end end
local function on(b) return b:IsShown() and b.itemID ~= nil end
local function glowing(b) local o = b.__apothecaGlow return o ~= nil and not o.animOut:IsPlaying() end

------------------------------------------------------------
-- Data
------------------------------------------------------------
H.eq(#D.STONES.sharp, 5, "five sharpening stones")
H.eq(#D.STONES.blunt, 5, "five weightstones")
H.eq(#D.STONES.any, 1, "Elemental, for any melee weapon")
H.eq(D.STONES.any[1].effect, "meleeCrit", "Elemental is crit, not damage")
H.eq(D.STONES.sharp[1].id, 12404, "Dense Sharpening Stone first")
local consecrated = false
for _, list in pairs(D.STONES) do for _, e in ipairs(list) do if e.id == 23122 then consecrated = true end end end
H.check(not consecrated, "Consecrated (undead only) is left out")

------------------------------------------------------------
-- Choice per character, per hand
------------------------------------------------------------
H.check(not on(mh) and not on(oh), "None by default: nothing changes for anyone")

Apotheca.SetStoneChoice(16, "damage")
Apotheca.SetStoneChoice(17, "damage")
settle()
H.eq(mh.itemID, 12404, "a sword: the sharpening stone")
H.eq(oh.itemID, 12643, "a mace: the weightstone")
H.eq(mh:GetAttribute("target-slot"), 16, "aimed at the main hand")
H.eq(oh:GetAttribute("target-slot"), 17, "and the off hand")
H.eq(ApothecaCharDB.stoneMH, "damage", "saved per character")

Apotheca.SetStoneChoice(16, "elemental")
settle()
H.eq(mh.itemID, 18262, "Elemental first: the Elemental stone")

-- Fallback to the other stone type within the choice.
WoW.bags[0][3] = nil
update()
H.eq(mh.itemID, 12404, "no Elemental left: the damage stone")
WoW.AddItem(0, 3, 18262, 5, "Elemental Sharpening Stone")

-- Level and usability.
WoW.level = 40
Apotheca.SetStoneChoice(16, "elemental")
settle()
H.eq(mh.itemID, 12404, "Elemental needs level 50: the damage stone")
WoW.level = 60
WoW.unusable[18262] = true
update()
H.eq(mh.itemID, 12404, "an Elemental the client refuses: the damage stone")
WoW.unusable = {}

-- Weapon kinds.
WoW.equipped[16] = FIST
WoW.fire("PLAYER_EQUIPMENT_CHANGED", 16, false)
settle()
H.eq(mh.itemID, 18262, "a fist weapon: Elemental only")
Apotheca.SetStoneChoice(16, "damage")
WoW.bags[0][3] = nil
settle()
H.check(not on(mh), "a fist weapon, no Elemental: no damage stone offered (unmeasured)")
WoW.AddItem(0, 3, 18262, 5, "Elemental Sharpening Stone")
WoW.equipped[16] = STAFF
WoW.fire("PLAYER_EQUIPMENT_CHANGED", 16, false)
settle()
H.eq(mh.itemID, 12643, "a staff is blunt: the weightstone")
WoW.equipped[16] = POLE
WoW.fire("PLAYER_EQUIPMENT_CHANGED", 16, false)
settle()
H.check(not mh:IsShown(), "a fishing pole: no stone")
H.eq(mh:GetAttribute("target-slot"), nil, "and no stale target on the hidden button")
WoW.equipped[16] = SWORD
WoW.fire("PLAYER_EQUIPMENT_CHANGED", 16, false)
settle()

------------------------------------------------------------
-- One owner per hand
------------------------------------------------------------
-- A paladin with mana oil: the Weapon Oil button owns the main hand until
-- a stone is chosen for it.
WoW.class, WoW.lfgRoles = "PALADIN", { tank = true }
WoW.AddItem(0, 4, 20748, 3, "Brilliant Mana Oil")
Apotheca.SetStoneChoice(16, "none")
settle()
H.check(on(oil) and not mh:IsShown(), "no stone chosen: the Weapon Oil button, as before")
Apotheca.SetStoneChoice(16, "damage")
settle()
H.check(on(mh) and not oil:IsShown(), "a stone chosen for the main hand: it replaces the Weapon Oil button")
H.eq(oil:GetAttribute("item"), nil, "and the hidden oil button keeps no item")

-- A rogue's chosen poison keeps its hand, even out of stock; warriors are
-- not affected by the profile's poison setting.
prof().poisons.enabled = true
WoW.class, WoW.lfgRoles = "ROGUE", { damage = true }
update()
H.check(not mh:IsShown() and not oh:IsShown(), "a rogue with poisons chosen: no stones, even with no poison held")
Apotheca.SetPoisonChoice(17, "none")
settle()
H.eq(oh.itemID, 12643, "the off-hand poison set to None: the stone may take it")
Apotheca.SetPoisonChoice(17, "deadly")
WoW.class, WoW.lfgRoles = "WARRIOR", { damage = true }
settle()
H.eq(mh.itemID, 12404, "a warrior on the same profile: stones, poisons don't apply")

------------------------------------------------------------
-- Glows
------------------------------------------------------------
WoW.enchants = {}
WoW.fire("READY_CHECK")
H.check(glowing(mh) and glowing(oh), "ready check: uncoated hands glow")
WoW.enchants[16] = { true, 1800000, 0, 1 }
WoW.fire("WEAPON_ENCHANT_CHANGED")
H.check(not glowing(mh), "any coating silences the glow")
WoW.fire("READY_CHECK_FINISHED")
WoW.enchants = {}
prof().stones.remind = true
WoW.enterCombat()
H.check(not glowing(mh), "no glow in combat")
WoW.leaveCombat()
settle()
H.check(glowing(mh), "the after-combat reminder, when switched on")
WoW.tick(6)
H.check(not glowing(mh), "for a few seconds")

H.done("test_stones")
