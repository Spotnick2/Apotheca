-- #19: the optional XP food button and its reminder glow.

dofile("tests/wow_stubs.lua")
local H = dofile("tests/harness.lua")

local D = nil
local function btn() return Apotheca.buttons.xpfood end
local function shown() return btn():IsShown() and btn().itemID ~= nil end
-- A glow is on while its overlay exists and is not being faded out.
local function glowing()
    local o = btn().__apothecaGlow
    return o ~= nil and not o.animOut:IsPlaying()
end
local function setXP(on) ApothecaDB.profiles[ApothecaDB.activeProfile].xpFood.enabled = on end
local function update() Apotheca.UpdateAllButtons() end

WoW.AddItem(0, 1, 2888, 5, "Beer Basted Boar Ribs")   -- L1, Strength
WoW.AddItem(0, 2, 12224, 5, "Crispy Bat Wing")        -- L1, Intellect
WoW.AddItem(0, 3, 1082, 5, "Redridge Goulash")        -- L5, Intellect
H.loadAddon()
D = Apotheca.DATA

------------------------------------------------------------
-- Data (generated from the 70009 scans)
------------------------------------------------------------
H.check(#D.XP_FOOD > 100, "every XP food is in the data")
local sorted = true
for i = 2, #D.XP_FOOD do if D.XP_FOOD[i].level > D.XP_FOOD[i - 1].level then sorted = false end end
H.check(sorted, "XP food is ordered highest level first")
local xpSet, known = {}, {}
for _, id in ipairs(D.XP_WELL_FED_SPELLS) do xpSet[id] = true end
for _, id in ipairs(D.WELL_FED_SPELLS) do known[id] = true end
H.check(xpSet[1248422], "the XP aura measured in game is an XP Well Fed")
local allKnown = true
for id in pairs(xpSet) do if not known[id] then allKnown = false end end
H.check(allKnown, "every XP Well Fed is a known Well Fed")
H.check(not xpSet[19705] and not xpSet[1225779], "Vanilla and ordinary Forever Well Fed are not XP")

------------------------------------------------------------
-- The button
------------------------------------------------------------
H.check(not shown(), "the button is off by default")

setXP(true)
WoW.class, WoW.lfgRoles, WoW.level = "PRIEST", { healer = true }, 3
update()
H.check(shown(), "switched on, it shows while levelling")
H.check(btn().itemID == 2888 or btn().itemID == 12224, "at level 3 it offers level-1 food, not the level-5 one")

-- Among equal levels, the role's buff food stat decides: a healer's
-- priority has Intellect, not Strength.
H.eq(btn().itemID, 12224, "a healer gets the Intellect one (Crispy Bat Wing)")
WoW.class, WoW.lfgRoles = "WARRIOR", { damage = true }
update()
H.eq(btn().itemID, 2888, "a melee warrior gets the Strength one (Beer Basted Boar Ribs)")

-- Level beats stat: at level 5 the level-5 food wins, whatever its stat.
WoW.level = 5
update()
H.eq(btn().itemID, 1082, "at level 5 the level-5 food (Redridge Goulash) wins over a level-1 Strength food")

-- No XP to gain: hidden.
WoW.level = 60
update()
H.check(not btn():IsShown(), "hidden at the level cap")
-- Turning XP gain off and on updates the button through its events, not
-- only on some unrelated update (Codex review of #21).
WoW.level = 5
update()
H.check(btn():IsShown(), "back below the cap: shown")
WoW.xpDisabled = true
WoW.fire("DISABLE_XP_GAIN")
for _ = 1, 3 do WoW.tick(0.1) end
H.check(not btn():IsShown(), "DISABLE_XP_GAIN hides it")
WoW.xpDisabled = false
WoW.fire("ENABLE_XP_GAIN")
for _ = 1, 3 do WoW.tick(0.1) end
H.check(btn():IsShown(), "ENABLE_XP_GAIN shows it again")

-- A stat listed twice ranks where it first appears (the options allow
-- repeats): Intellect first, Healing second, Intellect again.
WoW.level = 3
WoW.class, WoW.lfgRoles = "PRIEST", { healer = true }
WoW.AddItem(0, 4, 249865, 5, "Peace Tea")               -- L1, Healing Power
ApothecaDB.profiles[ApothecaDB.activeProfile].buffFoodPriority =
    { HEALER = { "intellect", "healing", "intellect", "spirit" } }
update()
H.eq(btn().itemID, 12224, "a repeated stat keeps its first rank: Intellect (Crispy Bat Wing) over Healing")
ApothecaDB.profiles[ApothecaDB.activeProfile].buffFoodPriority = nil
WoW.level = 5
update()

------------------------------------------------------------
-- Is the XP buff up?
------------------------------------------------------------
H.eq(Apotheca.HasXPFoodBuff(), false, "no Well Fed: the XP buff is missing")
WoW.SetAura("HELPFUL", "Well Fed", 19705)
WoW.spellNames[19705] = "Well Fed"
H.eq(Apotheca.HasXPFoodBuff(), false, "an ordinary Well Fed is not the XP buff")
WoW.auras.HELPFUL = {}
WoW.SetAura("HELPFUL", "Well Fed", 1248422)
H.eq(Apotheca.HasXPFoodBuff(), true, "the XP Well Fed (1248422) is recognised by ID")
WoW.auras.HELPFUL = {}
WoW.SetAura("HELPFUL", "Well Fed", 1399999)
H.eq(Apotheca.HasXPFoodBuff(), nil, "a Well Fed the scan did not know is unknown, not missing")
WoW.auras.HELPFUL = {}
WoW.aurasThrow = true
H.eq(Apotheca.HasXPFoodBuff(), nil, "unreadable auras (combat) are unknown")
WoW.aurasThrow = false

------------------------------------------------------------
-- The reminder glow after combat
------------------------------------------------------------
local function settle() for _ = 1, 3 do WoW.tick(0.1) end end   -- the deferred update runs
WoW.enterCombat()
H.check(not glowing(), "no glow in combat")
WoW.leaveCombat()
settle()
H.check(glowing(), "leaving combat without the XP buff glows the button")
WoW.tick(3)
H.check(glowing(), "still glowing a few seconds later")
WoW.tick(3)
H.check(not glowing(), "the reminder ends after about 5 seconds")

-- With the buff up: no reminder.
WoW.SetAura("HELPFUL", "Well Fed", 1248422)
WoW.enterCombat() ; WoW.leaveCombat() ; settle()
H.check(not glowing(), "no reminder while the XP buff is up")
WoW.auras.HELPFUL = {}

-- Eating during the reminder ends it (UNIT_AURA).
WoW.enterCombat() ; WoW.leaveCombat() ; settle()
H.check(glowing(), "reminder on")
WoW.SetAura("HELPFUL", "Well Fed", 1248422)
WoW.fire("UNIT_AURA", "player")
H.check(not glowing(), "eating the food ends the reminder")
WoW.auras.HELPFUL = {}

-- Re-entering combat ends it.
WoW.enterCombat() ; WoW.leaveCombat() ; settle()
WoW.enterCombat()
H.check(not glowing(), "re-entering combat ends the reminder")
WoW.leaveCombat() ; settle() ; WoW.tick(6)

-- Unknown Well Fed: no nagging.
WoW.SetAura("HELPFUL", "Well Fed", 1399999)
WoW.enterCombat() ; WoW.leaveCombat() ; settle()
H.check(not glowing(), "an unknown Well Fed never triggers the reminder")
WoW.auras.HELPFUL = {}

-- The button off: no reminder, even with XP food in the bags.
setXP(false)
WoW.enterCombat() ; WoW.leaveCombat() ; settle()
H.check(not glowing(), "no reminder when the button is off")
setXP(true)
update()

------------------------------------------------------------
-- One owner for the glow: a ready check and the reminder
------------------------------------------------------------
WoW.fire("READY_CHECK")
H.check(glowing(), "a ready check glows the button when the XP buff is missing")
WoW.enterCombat() ; WoW.leaveCombat() ; settle()
WoW.tick(6)                                   -- the reminder expires...
H.check(glowing(), "...but the ready check still wants the glow: it stays")
WoW.fire("READY_CHECK_FINISHED")
H.check(not glowing(), "the ready check ends: the glow goes")

-- A reminder armed while the bar is hidden must not fire later.
ApothecaDB.profiles[ApothecaDB.activeProfile].enabled = false
WoW.enterCombat() ; WoW.leaveCombat() ; settle()
ApothecaDB.profiles[ApothecaDB.activeProfile].enabled = true
WoW.tick(10)
update()
H.check(not glowing(), "a reminder from a hidden bar does not fire when it shows again")

-- A level-up to the cap hides the button.
WoW.level = 60
WoW.fire("PLAYER_LEVEL_UP", 60)
settle()
H.check(not btn():IsShown(), "levelling to the cap hides the button (PLAYER_LEVEL_UP)")

H.done("test_xpfood")
