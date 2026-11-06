-- #42 step 1: /fp apo prof and /fp apo proftest, the dev probe that measures
-- which profession spells the client knows and what each one does from a
-- secure button, by mouse and by key.

dofile("tests/wow_stubs.lua")
local H = dofile("tests/harness.lua")

-- An enchanter with cooking and two ranks of First Aid.
for _, id in ipairs({ 7411, 13262, 2550, 3273, 3274 }) do WoW.knownSpells[id] = true end
WoW.spellNames[3274] = "First Aid"
H.loadAddon({ probe = true })

local slash = H.fp
local function has(log, prefix)
    for _, line in ipairs(log) do
        if line:sub(1, #prefix) == prefix then return line end
    end
end

-- /fp apo prof: every candidate, the rank in use, the spellbook, saved by label.
slash("prof run1")
local log = ApothecaProbeDB.profProbe and ApothecaProbeDB.profProbe.run1
check(log, "the run is kept under its label")
check(has(log, "GetProfessions = nil, nil, nil, nil, nil, nil, nil"), "GetProfessions recorded with its nils")
eq(has(log, "firstaid rank in use"), "firstaid rank in use = 3274", "two ranks known: the higher is in use")
eq(has(log, "alchemy rank in use"), "alchemy rank in use = none known", "an unknown profession: none")
check(has(log, "firstaid 3274 known = C_SpellBook.IsSpellKnown=true"), "each API's answer per candidate")
check(has(log, "line 1 slot 1"), "the spellbook is walked")
eq(has(log, "line 2"), "line 2 = nil", "walked until a line answers nothing")
eq(has(log, "GetProfessionInfo"), nil, "no professions listed: no GetProfessionInfo")
check(ApothecaProbeDB.profLoad and ApothecaProbeDB.profLoad.PLAYER_LOGIN, "the catalog known at login is recorded")
check(ApothecaProbeDB.profLoad.PLAYER_LOGIN:find("enchanting:7411"), "with each known family's rank")

-- A learned rank is recorded with the event that brought it.
WoW.knownSpells[7924] = true
WoW.fire("LEARNED_SPELL_IN_SKILL_LINE", 7924, 3)
local ev = ApothecaProbeDB.profEvents[#ApothecaProbeDB.profEvents]
check(ev:find("LEARNED_SPELL_IN_SKILL_LINE 7924") and ev:find("firstaid:7924"), "learn event with the new rank")

-- /fp apo proftest: refused in combat (secure frames and bindings).
WoW.enterCombat()
slash("proftest")
eq(H.probeMatching("out of combat only"), 1, "in combat: refused")
WoW.leaveCombat()

slash("proftest")
local f = H.probe.profFrame
check(f and f.buttons, "the test frame is built")
eq(f.buttons.firstaid:GetAttribute("type"), "spell", "a family is a spell button")
eq(f.buttons.firstaid:GetAttribute("spell"), 7924, "for the rank in use, by ID")
check(f.buttons.disenchant and f.buttons.enchanting and f.buttons.cooking, "one button per known family")
check(not f.buttons.alchemy, "none for an unknown one")
check(not f.buttons.mining, "none for a context-only family")
eq(f.buttons.hearthstone:GetAttribute("item"), "item:6948", "the Hearthstone is an item button")
local bound = 0
for _, target in pairs(WoW.overrideBindings) do
    if target:find("^ApothecaProbeProf_") then bound = bound + 1 end
end
eq(bound, 5, "each button has a CTRL-SHIFT click binding")

-- One press is both edges; only the acting one (down, ActionButtonUseKeyDown
-- = 1 in the stubs) starts an attempt.
local function press(btn, events)
    btn:GetScript("PreClick")(btn, "LeftButton", true)
    for _, e in ipairs(events or {}) do WoW.fire(e[1], e[2], e[3]) end
    btn:GetScript("PostClick")(btn, "LeftButton", true)
    btn:GetScript("PreClick")(btn, "LeftButton", false)
    btn:GetScript("PostClick")(btn, "LeftButton", false)
    ForeverProbe.lines = {}
    for _ = 1, 5 do WoW.step(1) end
    return ApothecaProbeDB.profTests[#ApothecaProbeDB.profTests]
end

local r = press(f.buttons.firstaid,
    { { "UNIT_SPELLCAST_SENT", "player" }, { "UNIT_SPELLCAST_SUCCEEDED", "player" }, { "TRADE_SKILL_SHOW" } })
eq(#ApothecaProbeDB.profTests, 1, "one press, one attempt")
eq(r.verdict, "window+succeeded (1 cast)", "a profession window opened by one cast")
eq(r.via, "key", "the cursor off the button: recorded as a key press")
eq(H.probeMatching("#1 firstaid by key"), 1, "a verdict line in chat")

-- The cursor waits for an item to be picked: no verdict while it's up.
WoW.targeting = true
local n = #ApothecaProbeDB.profTests
press(f.buttons.disenchant, { { "UNIT_SPELLCAST_SENT", "player" } })
eq(#ApothecaProbeDB.profTests, n, "no verdict while the targeting cursor is up")
WoW.targeting = false
for _ = 1, 5 do WoW.step(1) end
r = ApothecaProbeDB.profTests[#ApothecaProbeDB.profTests]
eq(r.verdict, "cursor (1 cast)", "Disenchant: a targeting cursor")

r = press(f.buttons.cooking, { { "ADDON_ACTION_BLOCKED", "Apotheca", "CastSpellByID" } })
eq(r.verdict, "BLOCKED (0 casts)", "a blocked action is called out")

-- A CTRL-SHIFT press the button never receives is recorded as SILENT.
local watcher
for _, fr in ipairs(WoW.frames) do
    if fr:GetScript("OnKeyDown") then watcher = fr end
end
if watcher then
    WoW.ctrlDown, WoW.shiftDown = true, true
    local before = #ApothecaProbeDB.profTests
    watcher:GetScript("OnKeyDown")(watcher, "1")
    ForeverProbe.lines = {}
    WoW.step(2)
    local s = ApothecaProbeDB.profTests[#ApothecaProbeDB.profTests]
    eq(#ApothecaProbeDB.profTests, before + 1, "a key that reached nothing is recorded")
    check(s.verdict:find("^SILENT: CTRL%-SHIFT%-1"), "as SILENT, with its key")
    -- A press that reaches its button is an attempt, not SILENT.
    before = #ApothecaProbeDB.profTests
    watcher:GetScript("OnKeyDown")(watcher, "1")
    r = press(f.buttons.firstaid)
    eq(#ApothecaProbeDB.profTests, before + 1, "a key that reached its button: one attempt only")
    check(not r.verdict:find("SILENT"), "and not SILENT")
    WoW.ctrlDown, WoW.shiftDown = false, false
else
    check(false, "the key watcher frame exists")
end

-- Hidden, the bindings stay and the attempt says it was hidden.
slash("proftest hide")
r = press(f.buttons.enchanting)
check(r.hidden, "an attempt on a hidden button is marked")
eq(r.verdict, "nothing (0 casts)", "nothing happened")

slash("proftest close")
eq(next(WoW.overrideBindings), nil, "close clears the bindings")
slash("proftest show")
check(WoW.overrideBindings["CTRL-SHIFT-1"], "show binds them again")

eq(H.messagesMatching("."), 0, "the probe wrote nothing to chat")
done("test_profprobe")
