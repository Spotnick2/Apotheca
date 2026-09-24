-- Settings saved by earlier (TBC) builds. SavedVariables do not load back on
-- Forever yet, but when the client is fixed these profiles will arrive, and
-- InitDB must turn them into something that works here (AGENTS.md: always
-- migrate a changed setting).

dofile("tests/wow_stubs.lua")
local H = dofile("tests/harness.lua")

H.loadAddon({ savedDB = {
    activeProfile = "Global",
    profiles = {
      -- an inactive profile: cleaned too, not only the active one
      ["Realm-Alt"] = { buffFoodPriority = { PRIEST = { "healing", "mp5", "crit", "stamina" } } },
      Global = {
        showOnlyHealingSpec = true,   -- saved by every earlier profile, as the old default
        buffFoodPriority = {
            PRIEST  = { "healing", "mp5", "crit", "stamina" },     -- old default
            PALADIN = { "healing", "crit", "mp5", "stamina" },     -- old default
            SHAMAN  = { "healing", "sausage", "crit", "stamina" }, -- stat that no longer exists
            DRUID   = { "spirit", "healing", "intellect", "stamina" }, -- per CLASS: moves to HEALER
            MAGE    = { "intellect", "spellDmg", "spirit", "stamina" }, -- per CLASS: moves to CASTER
        },
    } },
} })

local prio = ApothecaDB.profiles.Global.buffFoodPriority
H.eq(prio.PRIEST, nil, "the old priest default is dropped, so the role profile decides")
H.eq(prio.PALADIN, nil, "the old paladin default too")
H.eq(prio.SHAMAN, nil, "a priority naming a stat Forever food lacks is dropped")
H.eq(prio.DRUID, nil, "the per-class key is gone: priorities are per role since #9")
H.eq(prio.HEALER and prio.HEALER[1], "spirit", "the druid's custom order moved to its role, HEALER")
H.eq(prio.CASTER and prio.CASTER[1], "intellect", "the mage's custom order moved to CASTER")
H.eq(ApothecaDB.profiles.Global.showOnlyHealingSpec, nil, "the old healer-only flag (always true by default) is dropped")
H.eq(ApothecaDB.profiles.Global.onlyWhenHealer, false, "its replacement defaults to off")
H.eq(Apotheca.GetStatPriority()[1], "spirit", "a priest (healer role) gets the healer role's saved order")
H.eq(ApothecaDB.profiles["Realm-Alt"].buffFoodPriority.PRIEST, nil, "an inactive profile is cleaned as well")

-- The flat (pre-profile) database route.
local flat = { buffFoodPriority = { PRIEST = { "healing", "mp5", "crit", "stamina" } } }
rawset(_G, "ApothecaDB", flat)
WoW.fire("ADDON_LOADED", "Apotheca")
local g = ApothecaDB.profiles and ApothecaDB.profiles.Global
H.check(g ~= nil, "a flat database is migrated into profiles")
H.eq(g and g.buffFoodPriority and g.buffFoodPriority.PRIEST, nil, "and its old priority is cleaned on that route too")

-- A malformed saved priority must not escape InitDB's guard: the database
-- resets instead of throwing out of ADDON_LOADED.
rawset(_G, "ApothecaDB", { activeProfile = "Global",
    profiles = { Global = { buffFoodPriority = { PRIEST = { false, 3 } } } } })
local okLoad = pcall(WoW.fire, "ADDON_LOADED", "Apotheca")
H.check(okLoad, "a malformed buffFoodPriority does not throw out of ADDON_LOADED")
H.eq(ApothecaDB.profiles.Global.buffFoodPriority.PRIEST, nil, "and it is dropped")

H.done("test_migration")
