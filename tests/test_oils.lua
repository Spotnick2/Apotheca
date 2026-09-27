-- #29: the Weapon Oil button follows the role.

dofile("tests/wow_stubs.lua")
local H = dofile("tests/harness.lua")

local STAFF = 2042
WoW.itemClass[STAFF] = { 2, 10, "Staves" }
WoW.equipped = { [16] = STAFF }
WoW.level = 25                          -- Minor Mana Oil needs 20, Minor Wizard Oil 5
WoW.AddItem(0, 1, 20744, 3, "Minor Wizard Oil")
WoW.AddItem(0, 2, 20745, 3, "Minor Mana Oil")
H.loadAddon()

local oil = Apotheca.buttons.weaponoil
local function prof() return ApothecaDB.profiles[ApothecaDB.activeProfile] end
local function as(cls, lfg) WoW.class, WoW.lfgRoles = cls, lfg ; Apotheca.UpdateAllButtons() end

H.eq(prof().weaponOil.kind, "AUTO", "by role is the default")

as("WARLOCK", { damage = true })
H.eq(oil.itemID, 20744, "a caster (warlock) gets the wizard oil")
as("PRIEST", { healer = true })
H.eq(oil.itemID, 20745, "a healer gets the mana oil")
as("HUNTER", { damage = true })
H.eq(oil.itemID, 20745, "another class with mana (hunter) gets the mana oil")
as("WARRIOR", { damage = true })
H.check(not oil:IsShown(), "no oil for a class without mana")

-- Fallbacks: only the other kind in the bags.
WoW.bags[0][2] = nil                    -- no mana oil left
as("PRIEST", { healer = true })
H.eq(oil.itemID, 20744, "a healer with only wizard oil: wizard oil")
as("HUNTER", { damage = true })
H.check(not oil:IsShown(), "a hunter with only wizard oil: no button (mana oil only)")
WoW.AddItem(0, 2, 20745, 3, "Minor Mana Oil")
WoW.bags[0][1] = nil                    -- no wizard oil left
as("WARLOCK", { damage = true })
H.eq(oil.itemID, 20745, "a caster with only mana oil: mana oil")
WoW.AddItem(0, 1, 20744, 3, "Minor Wizard Oil")
WoW.fire("BAG_UPDATE_DELAYED")          -- the bags changed, as the client says
for _ = 1, 2 do WoW.tick(1) end

-- A role change refreshes the oil by itself, with no manual update: a
-- druid switching Spell to Physical damage (a setting), and a priest
-- whose role selector changes (the out-of-combat poll).
WoW.class, WoW.lfgRoles = "DRUID", { damage = true }
Apotheca.SetCharSetting("damageStyle", "SPELL")
for _ = 1, 4 do WoW.tick(1) end
H.eq(oil.itemID, 20744, "a spell-damage druid: wizard oil")
Apotheca.SetCharSetting("damageStyle", "PHYSICAL")
for _ = 1, 4 do WoW.tick(1) end
H.eq(oil.itemID, 20745, "switched to physical damage: mana oil, without a manual update")
WoW.class, WoW.lfgRoles = "PRIEST", { damage = true }
for _ = 1, 4 do WoW.tick(1) end
H.eq(oil.itemID, 20744, "a shadow priest (damage): wizard oil")
WoW.lfgRoles = { healer = true }
for _ = 1, 4 do WoW.tick(1) end
H.eq(oil.itemID, 20745, "the role selector changed to healer: mana oil, picked up by the poll")

-- An explicit choice overrides the role.
prof().weaponOil.kind = "MANA_ONLY"
as("WARLOCK", { damage = true })
H.eq(oil.itemID, 20745, "Mana oil only: even a caster gets the mana oil")
prof().weaponOil.kind = "WIZARD_FIRST"
as("PRIEST", { healer = true })
H.eq(oil.itemID, 20744, "Wizard oil first: even a healer gets the wizard oil")
prof().weaponOil.kind = "sausage"
as("WARLOCK", { damage = true })
H.eq(oil.itemID, 20744, "an unknown saved choice behaves as by role")
prof().weaponOil.kind = "AUTO"

-- Only an oil the player can use: the fallback reaches the other kind
-- (/code-review of #30). A level-35 warlock with Wizard Oil (level 40) and
-- Minor Mana Oil gets the mana oil, until level 40.
WoW.bags[0][1] = nil
WoW.AddItem(0, 3, 20750, 2, "Wizard Oil")
WoW.level = 35
as("WARLOCK", { damage = true })
H.eq(oil.itemID, 20745, "Wizard Oil above the level: the usable mana oil instead")
WoW.level = 40
as("WARLOCK", { damage = true })
H.eq(oil.itemID, 20750, "at level 40: the Wizard Oil")
-- An oil the client says can't be used is skipped too.
WoW.unusable[20750] = true
as("WARLOCK", { damage = true })
H.eq(oil.itemID, 20745, "an oil the client refuses: the next usable one")
WoW.unusable = {}

H.done("test_oils")
