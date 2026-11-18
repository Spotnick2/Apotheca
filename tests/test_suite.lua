-- Glass UI's suite (#101): Apotheca is a dynamic member for what it paints
-- itself, the Mage Scrolls wheel. It asks Theme("Apotheca") once, at
-- PLAYER_LOGIN, and reports what it built (Glass UI's docs/SUITE.md, "The
-- contract", API 1). The fake Suite below follows that contract.

dofile("tests/wow_stubs.lua")
local H = dofile("tests/harness.lua")

local function near(a, b) return math.abs(a - b) < 1e-6 end
local function rgba(t) return t._color or {} end

-- A fake Glass UI: Theme answers `answer` (a look, or nil and a reason),
-- every call and report is recorded.
local calls, reports = {}, {}
local answer = { { name = "pearl", preset = "pearl" } }
local smoked = { tint = { 0.05, 0.06, 0.08, 0.62 }, backing = { 0.04, 0.05, 0.07, 0.92 }, wash = 0.5 }
local body = smoked
local suite = { API = 1,
    Theme = function(addon)
        calls[#calls + 1] = { addon = addon, loggedIn = Apotheca.optionsPanel ~= nil }
        return unpack(answer)
    end,
    Report = function(addon, state) reports[#reports + 1] = { addon = addon, state = state } end,
    Body = function() return body end,
    Accent = function() return { 0.65, 0.835, 0.905 } end }
rawset(_G, "GlassUI", { Suite = suite })

WoW.class = "MAGE"
H.loadAddon()
local W = Apotheca.Wheel
local parts = W.parts
local function ownTint()
    return near(rgba(parts.g.tint)[1], W.OWN.tint[1]) and near(rgba(parts.g.tint)[4], W.OWN.tint[4])
end
local function smokedTint() return near(rgba(parts.g.tint)[4], 0.62) end

------------------------------------------------------------
-- Following (the default): asked once, at login
------------------------------------------------------------
eq(#calls, 1, "Theme is asked once")
eq(calls[1] and calls[1].addon, "Apotheca", "keyed by the folder, Apotheca")
check(calls[1] and calls[1].loggedIn, "at PLAYER_LOGIN (the options panel exists): after Glass UI's ADDON_LOADED")
eq(#reports, 1, "then one report")
local r = reports[1] and reports[1].state or {}
eq(reports[1] and reports[1].addon, "Apotheca", "reported as Apotheca")
eq(r.api, 1, "report: api 1")
eq(r.built, "pearl", "report: Pearl built")
eq(r.reason, nil, "report: no failure")
eq(r.live, true, "report: live (it repaints on LookChanged)")
eq(r.minor, select(2, LibStub("LibGlass-1.0")), "report: LibGlass's MINOR")
check(type(r.options) == "function", "report: an options function")
eq(r.options(), true, "which opens Apotheca's options")
eq(W.ownLook, false, "following: not its own look")
W.Paint()
check(smokedTint(), "following: the suite's body (Smoked)")
body = { tint = { 0.13, 0.16, 0.22, 0.24 }, backing = { 0.04, 0.05, 0.07, 0.35 }, wash = 1 }
EventRegistry:TriggerEvent("GlassUI.Suite.LookChanged", { tint = "clear" })
check(near(rgba(parts.g.tint)[4], 0.24), "and repaints live on LookChanged")

------------------------------------------------------------
-- The player's Follow switch off: its own look until /reload
------------------------------------------------------------
local function join(...)
    answer = { ... }
    calls, reports = {}, {}
    W.ownLook = false
    return W.JoinSuite()
end
body = smoked
eq(join(nil, "not-following"), "not-following", "not following: JoinSuite says so")
eq(W.ownLook, true, "its own look")
eq(#reports, 1, "still reported")
r = reports[1].state
eq(r.built, nil, "report: nothing built from the suite (its own look)")
eq(r.reason, nil, "report: not a failure")
eq(r.api, 1, "report: api 1")
W.Paint()
check(ownTint(), "painted with its own body, not the suite's Smoked")
local tr, tg = W.label:GetTextColor()
check(near(tr, W.GOLD[1]) and near(tg, W.GOLD[2]), "and its own gold accent, not the suite's")
EventRegistry:TriggerEvent("GlassUI.Suite.LookChanged", { tint = "smoked" })
check(ownTint(), "a LookChanged leaves its own look until /reload")

------------------------------------------------------------
-- Any other answer: as before (read-only following), no report
------------------------------------------------------------
eq(join(nil, "unknown"), "unknown", "a Glass UI older than Apotheca's roster entry: unknown")
eq(W.ownLook, false, "keeps following, as before")
eq(#reports, 0, "and reports nothing (Glass UI doesn't know Apotheca)")
W.Paint()
check(smokedTint(), "the suite's body, as before #101")

eq(join(nil, "not-ready"), "not-ready", "not-ready (Glass UI not set up yet)")
eq(W.ownLook, false, "keeps following")
eq(#reports, 0, "no report")

answer = {}
suite.Theme = function() error("broken") end
W.ownLook, reports = false, {}
eq(W.JoinSuite(), nil, "Theme erroring: no answer")
eq(W.ownLook, false, "keeps following")
eq(#reports, 0, "no report")

suite.Theme = nil
eq(W.JoinSuite(), nil, "a Glass UI without Theme: nothing asked")
W.Paint()
check(smokedTint(), "and the wheel follows its body, as before")

------------------------------------------------------------
-- A failed Pearl build is reported as such
------------------------------------------------------------
suite.Theme = function() return { name = "pearl", preset = "pearl" } end
W.glassFailed = "library-too-old"
reports = {}
eq(W.JoinSuite(), "following", "told to follow")
r = reports[1] and reports[1].state or {}
eq(r.built, nil, "Pearl not built")
eq(r.reason, "library-too-old", "and why")
W.glassFailed = nil

------------------------------------------------------------
-- Without Glass UI: no change
------------------------------------------------------------
rawset(_G, "GlassUI", nil)
W.ownLook = false
eq(W.JoinSuite(), nil, "no Glass UI: nothing asked")
W.Paint()
check(ownTint(), "its own look, as always")

done("test_suite")
