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
WoW.playerGUID = "Player-5826-000000AA"
H.loadAddon({ savedDB = saved, savedCharDB = {} })

eq(ApothecaDB.activeProfile, "Stonebrow-Testcase", "the character that chose it keeps its profile")
eq(ApothecaCharDB.profile, "Stonebrow-Testcase", "now saved per character")
eq(ApothecaCharDB.profileKey, "Stonebrow-Testcase", "and remembered as its own key")
eq(ApothecaDB.profileOwners["Stonebrow-Testcase"], "Player-5826-000000AA", "owned by its GUID")
eq(Apotheca.GetDB().iconSize, 44, "its settings are the ones in use")
eq(ApothecaDB.legacyActiveProfile, "Stonebrow-Testcase", "the old account-wide choice is kept for the others")
eq(Apotheca.GetCharProfileKey(), "Stonebrow-Testcase", "its own key no longer needs the realm")
local testcaseChar = ApothecaCharDB

-- A character's login: its name, GUID and per-character file, then the
-- client's ADDON_LOADED and Apotheca's PLAYER_LOGIN step.
local function login(name, guid, charDB, surname)
    WoW.playerName, WoW.playerSurname, WoW.playerGUID = name, surname, guid
    rawset(_G, "ApothecaCharDB", charDB)
    WoW.fire("ADDON_LOADED", "Apotheca")
    Apotheca._ResolveCharProfile()
end

-- Another character's first login since: the old choice wasn't its own.
login("Other", "Player-5826-000000BB", {})
eq(ApothecaDB.activeProfile, "Global", "another character goes back to Global")
eq(ApothecaCharDB.profile, "Global", "and that is saved for it")
eq(ApothecaCharDB.profileKey, nil, "Global is no character's own key")
eq(ApothecaDB.legacyActiveProfile, "Stonebrow-Testcase", "the legacy choice is never overwritten")

-- Its own key with no saved profile of its name: the full name and the
-- GUID's serial; the options show only the name.
eq(Apotheca.GetCharProfileKey(), "Other-#000000BB", "a new key without the realm")
eq(Apotheca.ProfileLabel("Other-#000000BB"), "Other", "the label hides the serial")
eq(Apotheca.ProfileLabel("Second Surname-#0A"), "Second Surname", "a surname too")
eq(Apotheca.ProfileLabel("Stonebrow-Testcase"), "Stonebrow-Testcase", "a realm key reads as before")
Apotheca.SetProfile(Apotheca.GetCharProfileKey())
eq(ApothecaCharDB.profile, "Other-#000000BB", "ticking the box saves the choice per character")
eq(ApothecaCharDB.profileKey, "Other-#000000BB", "and its key")
eq(ApothecaDB.profiles["Stonebrow-Testcase"].iconSize, 44, "Testcase's profile is untouched")
Apotheca.SetProfile("Global")
eq(ApothecaCharDB.profile, "Global", "unticking goes back to Global")
eq(Apotheca.GetCharProfileKey(), "Other-#000000BB", "and the key is kept for next time")
local otherChar = ApothecaCharDB

-- Testcase again, after Other's session left activeProfile on Global.
login("Testcase", "Player-5826-000000AA", testcaseChar)
eq(ApothecaDB.activeProfile, "Stonebrow-Testcase", "Testcase's choice doesn't follow the last character")
login("Other", "Player-5826-000000BB", otherChar)
eq(ApothecaDB.activeProfile, "Global", "nor Other's")

-- A Testcase on another realm, after the first one took the profile: the
-- name fits, but the profile is someone else's now.
login("Testcase", "Player-5826-000000CC", {})
eq(ApothecaDB.activeProfile, "Global", "a namesake doesn't share the taken profile")
eq(Apotheca.GetCharProfileKey(), "Testcase-#000000CC", "and gets its own key")

-- The realm hidden, a saved "Realm-Name" of the same name: adopted, unless
-- two realms have one (then they can't be told apart).
ApothecaDB.profiles["Ravencrest-Solo"] = { iconSize = 38 }
login("Solo", "Player-5826-000000DD", {})
eq(Apotheca.GetCharProfileKey(), "Ravencrest-Solo", "the one profile of this name is its own")
ApothecaDB.profiles["Ravencrest-Dup"] = {}
ApothecaDB.profiles["Stonebrow-Dup"] = {}
login("Dup", "Player-5826-000000EE", {})
eq(Apotheca.GetCharProfileKey(), "Dup-#000000EE", "two of the same name: neither is taken")

-- The same test decides the migration: with two realms' profiles of its
-- name, the account-wide choice isn't adopted either (Codex on #116).
rawset(_G, "ApothecaDB", { activeProfile = "Ravencrest-Dup",
    profiles = { Global = {}, ["Ravencrest-Dup"] = { iconSize = 40 }, ["Stonebrow-Dup"] = {} } })
login("Dup", "Player-5826-000000EE", {})
eq(ApothecaDB.activeProfile, "Global", "an ambiguous legacy choice is not adopted")

-- v2.11.1 after the hotfix: ticking the box made "-Name" (Codex on #116).
-- Its settings are the character's, and it keeps them.
rawset(_G, "ApothecaDB", { activeProfile = "-Testcase",
    profiles = { Global = {}, ["-Testcase"] = { iconSize = 50 } } })
login("Testcase", "Player-5826-000000AA", {})
eq(ApothecaDB.activeProfile, "-Testcase", "the hotfix-day profile is adopted at login")
eq(Apotheca.GetDB().iconSize, 50, "with its settings")
eq(Apotheca.GetCharProfileKey(), "-Testcase", "and is the character's own key")
rawset(_G, "ApothecaDB", { activeProfile = "Global",
    profiles = { Global = {}, ["-Testcase"] = { iconSize = 50 } } })
login("Testcase", "Player-5826-000000AA", {})
eq(Apotheca.GetCharProfileKey(), "-Testcase", "unticked since: ticking again finds it")

-- Both: the pre-hotfix "Stonebrow-Testcase", then "-Testcase" made and
-- customised on v2.11.1 after the hotfix (Codex on #116). The hotfix one is
-- what the character has used since: kept at login and found when ticked.
rawset(_G, "ApothecaDB", { activeProfile = "-Testcase",
    profiles = { Global = {}, ["Stonebrow-Testcase"] = { iconSize = 44 }, ["-Testcase"] = { iconSize = 50 } } })
login("Testcase", "Player-5826-000000AA", {})
eq(ApothecaDB.activeProfile, "-Testcase", "with both formats, the hotfix profile in use is kept")
eq(Apotheca.GetDB().iconSize, 50, "with its settings")
eq(ApothecaDB.profiles["Stonebrow-Testcase"].iconSize, 44, "the older one is left as it was")
rawset(_G, "ApothecaDB", { activeProfile = "Global",
    profiles = { Global = {}, ["Stonebrow-Testcase"] = { iconSize = 44 }, ["-Testcase"] = { iconSize = 50 } } })
login("Testcase", "Player-5826-000000AA", {})
eq(Apotheca.GetCharProfileKey(), "-Testcase", "unticked: ticking again finds the hotfix one, not a third")
rawset(_G, "ApothecaDB", { activeProfile = "Global", profileOwners = { ["-Testcase"] = "Player-5826-000000CC" },
    profiles = { Global = {}, ["Stonebrow-Testcase"] = {}, ["-Testcase"] = {} } })
login("Testcase", "Player-5826-000000AA", {})
eq(Apotheca.GetCharProfileKey(), "Stonebrow-Testcase", "a hotfix profile another character took isn't preferred")

-- Surnames (PORTING-TBC-TO-FOREVER.md): "Second Surname" and "Second
-- Othername" are two characters. An old key built from the first name alone
-- can't say whose it is; one naming the full name can (Codex on #116).
rawset(_G, "ApothecaDB", { activeProfile = "Stonebrow-Second",
    profiles = { Global = {}, ["Stonebrow-Second"] = { iconSize = 33 } } })
login("Second", "Player-5826-00000011", {}, "Surname")
eq(ApothecaDB.activeProfile, "Global", "a first-name key is nobody's: Second Surname")
eq(Apotheca.GetCharProfileKey(), "Second Surname-#00000011", "its own key has the surname")
Apotheca.SetProfile(Apotheca.GetCharProfileKey())
local surnameChar = ApothecaCharDB
login("Second", "Player-5826-00000022", {}, "Othername")
eq(ApothecaDB.activeProfile, "Global", "nor Second Othername's")
eq(Apotheca.GetCharProfileKey(), "Second Othername-#00000022", "a key of its own")
check(Apotheca.GetCharProfileKey() ~= surnameChar.profileKey, "the two never share one")
rawset(_G, "ApothecaDB", { activeProfile = "Stonebrow-Second Surname",
    profiles = { Global = {}, ["Stonebrow-Second Surname"] = { iconSize = 34 } } })
login("Second", "Player-5826-00000022", {}, "Othername")
eq(ApothecaDB.activeProfile, "Global", "a full-name key isn't the other Second's")
login("Second", "Player-5826-00000011", {}, "Surname")
eq(ApothecaDB.activeProfile, "Stonebrow-Second Surname", "and is its owner's")

-- The realm readable again: an old key must name this realm; a new key is
-- the GUID one.
WoW.realm = "Kirtonos"
rawset(_G, "ApothecaDB", { activeProfile = "Stonebrow-Fresh",
    profiles = { Global = {}, ["Stonebrow-Fresh"] = {} } })
login("Fresh", "Player-5826-00000033", {})
eq(ApothecaDB.activeProfile, "Global", "with the realm readable, another realm's key isn't this character's")
eq(Apotheca.GetCharProfileKey(), "Fresh-#00000033", "a new key needs no realm even when it reads")
ApothecaDB.profiles["Kirtonos-Fresh"] = {}
eq(Apotheca.GetCharProfileKey(), "Kirtonos-Fresh", "this realm's old key is its own")

-- A secret or blank realm reads as hidden, never as a key.
WoW.realm = WoW.Secret("Kirtonos")
login("Hush", "Player-5826-00000044", {})
eq(Apotheca.GetCharProfileKey(), "Hush-#00000044", "a secret realm is not used")
WoW.realm = "   "
eq(Apotheca.GetCharProfileKey(), "Hush-#00000044", "nor a blank one")
WoW.realm = ""

-- Without a GUID either, still a key no character name can take.
login("Ghost", nil, {})
eq(Apotheca.GetCharProfileKey(), "Unknown-Ghost", "no realm, no GUID")

-- A broken saved profile never stops the login (Codex on #116): InitDB
-- validated only the active entry, and that is Global now.
rawset(_G, "ApothecaDB", { activeProfile = "Stonebrow-Testcase",
    profiles = { Global = {}, ["Stonebrow-Testcase"] = 1 } })
local okLogin = pcall(login, "Testcase", "Player-5826-000000AA", {})
check(okLogin, "a legacy profile that isn't a table doesn't throw at login")
eq(ApothecaDB.activeProfile, "Global", "and isn't adopted")
local okSaved = pcall(login, "Testcase", "Player-5826-000000AA", { profile = "Stonebrow-Testcase" })
check(okSaved, "nor does a character's saved choice pointing at one")
eq(type(ApothecaDB.profiles["Stonebrow-Testcase"]), "table", "it is rebuilt from defaults")

-- A per-character file that isn't a table: Global, and a fresh table.
login("Broken", "Player-5826-00000055", "junk")
eq(ApothecaDB.activeProfile, "Global", "a broken per-character file means Global")
eq(type(ApothecaCharDB), "table", "and it is replaced")

done("test_profiles")
