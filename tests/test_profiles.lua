-- Which profile a character uses (#115). Since the 2026-11-20 hotfix the
-- client hides the realm (GetRealmName() is ""), so a character's own key
-- can no longer be built from it, and the choice itself moves from the
-- account-wide ApothecaDB.activeProfile to ApothecaCharDB.profile.

dofile("tests/wow_stubs.lua")
local H = dofile("tests/harness.lua")

-- Before #115: the account-wide choice was "Stonebrow-Testcase", made on
-- Testcase. The realm is hidden now (the stub's default).
local saved = {
    activeProfile = "Stonebrow-Testcase",
    profiles = {
        Global = { iconSize = 30 },
        ["Stonebrow-Testcase"] = { iconSize = 44 },
    },
}
H.loadAddon({ savedDB = saved, savedCharDB = {} })

eq(ApothecaDB.activeProfile, "Stonebrow-Testcase", "the character that chose it keeps its profile")
eq(ApothecaCharDB.profile, "Stonebrow-Testcase", "now saved per character")
eq(ApothecaCharDB.profileKey, "Stonebrow-Testcase", "and remembered as its own key")
eq(Apotheca.GetDB().iconSize, 44, "its settings are the ones in use")
eq(ApothecaDB.legacyActiveProfile, "Stonebrow-Testcase", "the old account-wide choice is kept for the others")
eq(Apotheca.GetCharProfileKey(), "Stonebrow-Testcase", "its own key no longer needs the realm")
local testcaseChar = ApothecaCharDB

-- Another character's first login since: the old choice wasn't its own.
local function login(name, charDB)
    WoW.playerName = name
    rawset(_G, "ApothecaCharDB", charDB)
    WoW.fire("ADDON_LOADED", "Apotheca")
    Apotheca._ResolveCharProfile()
end
login("Other", {})
eq(ApothecaDB.activeProfile, "Global", "another character goes back to Global")
eq(ApothecaCharDB.profile, "Global", "and that is saved for it")
eq(ApothecaCharDB.profileKey, nil, "Global is no character's own key")
eq(ApothecaDB.legacyActiveProfile, "Stonebrow-Testcase", "the legacy choice is never overwritten")

-- Its own key with the realm hidden and no saved profile of its name: the
-- name and the GUID's serial; the options show only the name.
eq(Apotheca.GetCharProfileKey(), "Other-#0A1B2C3D", "a new key without the realm")
eq(Apotheca.ProfileLabel("Other-#0A1B2C3D"), "Other", "the label hides the serial")
eq(Apotheca.ProfileLabel("Stonebrow-Testcase"), "Stonebrow-Testcase", "a realm key reads as before")
Apotheca.SetProfile(Apotheca.GetCharProfileKey())
eq(ApothecaCharDB.profile, "Other-#0A1B2C3D", "ticking the box saves the choice per character")
eq(ApothecaCharDB.profileKey, "Other-#0A1B2C3D", "and its key")
eq(ApothecaDB.profiles["Stonebrow-Testcase"].iconSize, 44, "Testcase's profile is untouched")
Apotheca.SetProfile("Global")
eq(ApothecaCharDB.profile, "Global", "unticking goes back to Global")
eq(Apotheca.GetCharProfileKey(), "Other-#0A1B2C3D", "and the key is kept for next time")
local otherChar = ApothecaCharDB

-- Testcase again, after Other's session left activeProfile on Global.
login("Testcase", testcaseChar)
eq(ApothecaDB.activeProfile, "Stonebrow-Testcase", "Testcase's choice doesn't follow the last character")
login("Other", otherChar)
eq(ApothecaDB.activeProfile, "Global", "nor Other's")

-- The realm hidden, a saved "Realm-Name" of the same name: adopted, unless
-- two realms have one (then they can't be told apart).
ApothecaDB.profiles["Ravencrest-Solo"] = { iconSize = 38 }
login("Solo", {})
eq(Apotheca.GetCharProfileKey(), "Ravencrest-Solo", "the one profile of this name is its own")
ApothecaDB.profiles["Ravencrest-Dup"] = {}
ApothecaDB.profiles["Stonebrow-Dup"] = {}
login("Dup", {})
eq(Apotheca.GetCharProfileKey(), "Dup-#0A1B2C3D", "two of the same name: neither is taken")

-- The realm readable again: "Realm-Name", compared exactly.
WoW.realm = "Kirtonos"
login("Fresh", {})
eq(Apotheca.GetCharProfileKey(), "Kirtonos-Fresh", "a readable realm builds the old key")
rawset(_G, "ApothecaDB", { activeProfile = "Stonebrow-Fresh",
    profiles = { Global = {}, ["Stonebrow-Fresh"] = {} } })
login("Fresh", {})
eq(ApothecaDB.activeProfile, "Global", "with the realm readable, another realm's key isn't this character's")

-- A secret or blank realm reads as hidden, never as a key.
WoW.realm = WoW.Secret("Kirtonos")
login("Hush", {})
eq(Apotheca.GetCharProfileKey(), "Hush-#0A1B2C3D", "a secret realm is not used")
WoW.realm = "   "
eq(Apotheca.GetCharProfileKey(), "Hush-#0A1B2C3D", "nor a blank one")
WoW.realm = ""

-- Without a GUID either, still a key no character name can take.
WoW.playerGUID = nil
login("Ghost", {})
eq(Apotheca.GetCharProfileKey(), "Unknown-Ghost", "no realm, no GUID")

-- A per-character file that isn't a table: Global, and a fresh table.
login("Broken", "junk")
eq(ApothecaDB.activeProfile, "Global", "a broken per-character file means Global")
eq(type(ApothecaCharDB), "table", "and it is replaced")

done("test_profiles")
