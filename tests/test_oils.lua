-- #29: the Weapon Oil button follows the role.

dofile("tests/wow_stubs.lua")
local H = dofile("tests/harness.lua")

local STAFF = 2042
WoW.itemClass[STAFF] = { 2, 10, "Staves" }
WoW.equipped = { [16] = STAFF }
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

H.done("test_oils")
