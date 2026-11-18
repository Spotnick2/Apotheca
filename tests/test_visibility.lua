-- #110: the Visibility setting in combat. The bar parents secure buttons, so
-- insecure code can't show or hide it in combat, and the full update doesn't
-- run then: "In combat only" never showed the bar, "Out of combat" never hid
-- it. A secure state driver owns the frame's visibility now.

dofile("tests/wow_stubs.lua")
local H = dofile("tests/harness.lua")

WoW.AddItem(0, 1, 13444, 5, "Major Mana Potion")
H.loadAddon()
WoW.strictLockdown = true      -- no insecure Show/Hide on the bar in combat
local db = ApothecaDB.profiles[ApothecaDB.activeProfile]
local F = ApothecaFrame
local mana = Apotheca.buttons.mana
local function driver() return WoW.stateDrivers[F] and WoW.stateDrivers[F].visibility end
local function fight()
    WoW.enterCombat()
    WoW.step(0.5)
    local shown = F:IsShown()
    WoW.leaveCombat()
    WoW.step(0.5)
    return shown
end

-- Always: shown, in and out of combat.
eq(driver(), "show", "Always: the driver shows the bar")
check(F:IsShown(), "Always: shown out of combat")
check(fight(), "Always: shown in combat")
check(F:IsShown(), "Always: still shown after combat")

-- In combat only: hidden out of combat, shown in combat (it never showed).
db.visibility = "IN_COMBAT"
Apotheca.UpdateAllButtons()
eq(driver(), "[combat] show; hide", "In combat only: a combat driver")
check(not F:IsShown(), "In combat only: hidden out of combat")
eq(mana:GetAttribute("item"), "item:13444", "its buttons stay set up while hidden (#49)")
check(fight(), "In combat only: shown in combat")
check(not F:IsShown(), "In combat only: hidden again after combat")

-- Out of combat: shown out of combat, hidden in combat (it never hid).
db.visibility = "OUT_OF_COMBAT"
Apotheca.UpdateAllButtons()
eq(driver(), "[combat] hide; show", "Out of combat: the opposite driver")
check(F:IsShown(), "Out of combat: shown out of combat")
check(not fight(), "Out of combat: hidden in combat")
check(F:IsShown(), "Out of combat: shown again after combat")

-- Combat already locked down (no PLAYER_REGEN_DISABLED moment first).
WoW.enterLockdown()
check(not F:IsShown(), "Out of combat: hidden under lockdown too")
WoW.leaveCombat()
WoW.step(0.5)

-- Hidden: hidden always.
db.visibility = "HIDDEN"
Apotheca.UpdateAllButtons()
eq(driver(), "hide", "Hidden: a hide driver")
check(not F:IsShown(), "Hidden: hidden out of combat")
check(not fight(), "Hidden: hidden in combat")

-- The bar switched off: hidden, whatever the Visibility says.
db.visibility = "IN_COMBAT"
db.enabled = false
Apotheca.UpdateAllButtons()
eq(driver(), "hide", "bar off: hidden")
check(not fight(), "bar off: not shown in combat by the combat driver")
db.enabled = true
db.visibility = "ALWAYS"
Apotheca.UpdateAllButtons()
check(F:IsShown(), "back to Always: shown")

-- The setting changed in combat waits for combat's end, without touching
-- the protected bar (strictLockdown fails the test otherwise).
WoW.enterCombat()
db.visibility = "OUT_OF_COMBAT"
Apotheca.UpdateAllButtons()
check(F:IsShown(), "changed in combat: unchanged until combat ends")
eq(#WoW.blocked, 0, "nothing refused in combat")
WoW.leaveCombat()
WoW.step(0.5)
eq(driver(), "[combat] hide; show", "applied after combat")

done("test_visibility")
