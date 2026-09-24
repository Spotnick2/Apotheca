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
        buffFoodPriority = {
            PRIEST  = { "healing", "mp5", "crit", "stamina" },     -- old default
            PALADIN = { "healing", "crit", "mp5", "stamina" },     -- old default
            SHAMAN  = { "healing", "sausage", "crit", "stamina" }, -- stat that no longer exists
            DRUID   = { "spirit", "healing", "intellect", "stamina" }, -- a real custom order
        },
    } },
} })

local prio = ApothecaDB.profiles.Global.buffFoodPriority
H.eq(prio.PRIEST, nil, "the old priest default is dropped, so the role profile decides")
H.eq(prio.PALADIN, nil, "the old paladin default too")
H.eq(prio.SHAMAN, nil, "a priority naming a stat Forever food lacks is dropped")
H.eq(prio.DRUID and prio.DRUID[1], "spirit", "a real custom order survives")
H.eq(Apotheca.GetStatPriority()[1], "healing", "a priest now gets the healer profile's priority")
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
