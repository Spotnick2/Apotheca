-- #24 phase 1: /apo applytest, the dev probe that measures how a secure
-- button applies a weapon coating to a chosen hand.

dofile("tests/wow_stubs.lua")
local H = dofile("tests/harness.lua")

WoW.class = "ROGUE"
WoW.equipped = { [16] = 2169, [17] = 2209 }     -- dual wielding
WoW.AddItem(0, 1, 6947, 10, "Instant Poison")
H.loadAddon({ probe = true })

local function slash(s) WoW.messages = {} ; SlashCmdList["APOTHECA"](s) end
local function last() return ApothecaProbeDB.applyTests[#ApothecaProbeDB.applyTests] end

slash("applytest")
H.eq(H.messagesMatching("usage"), 1, "no item: the usage line")

WoW.enterCombat()
slash("applytest 6947")
H.eq(H.messagesMatching("out of combat only"), 1, "in combat: refused, the buttons are secure frames")
WoW.leaveCombat()

slash("applytest 6947")
local f = Apotheca._applyTestFrame
H.check(f and f.buttons, "out of combat: the test buttons are shown")
local A16, A17, B16, B17 = f.buttons.A16, f.buttons.A17, f.buttons.B16, f.buttons.B17
H.eq(A16:GetAttribute("type"), "item", "method A is an item button")
H.eq(A16:GetAttribute("item"), "item:6947", "for the item by ID")
H.eq(A17:GetAttribute("target-slot"), 17, "aimed at its hand through target-slot")
H.eq(B16:GetAttribute("type"), "macro", "method B is a macro button")
H.eq(B17:GetAttribute("macrotext"), "/use item:6947\n/use 17", "using the item, then the hand's slot")

-- One click: PreClick snapshot, the client applies (or not), PostClick,
-- then the verdict once things settle.
-- A physical click is both edges: press, then release.
local function click(btn, apply, events)
    btn:GetScript("PreClick")(btn, "LeftButton", true)
    if apply then apply() end
    for _, e in ipairs(events or {}) do WoW.fire(e[1], e[2], e[3]) end
    btn:GetScript("PostClick")(btn, "LeftButton", true)
    btn:GetScript("PreClick")(btn, "LeftButton", false)
    btn:GetScript("PostClick")(btn, "LeftButton", false)
    WoW.messages = {}
    for _ = 1, 8 do WoW.tick(1) end
    return last()
end

-- Applied to the intended hand only.
local r = click(A16, function() WoW.enchants[16] = { true, 1800000, 40, 323 } end,
    { { "UNIT_SPELLCAST_SUCCEEDED", "player" }, { "WEAPON_ENCHANT_CHANGED" } })
H.eq(r.verdict:match("^applied") , "applied", "a new coating on the main hand: applied")
H.eq(r.method .. r.slot, "A16", "recorded as method A, main hand")
H.eq(#r.events, 2, "with the events that fired in between")
H.eq(H.messagesMatching("#1 A main hand: applied"), 1, "and a verdict line in chat")

-- The other hand changed: wrong hand.
r = click(A17, function() WoW.enchants[16] = { true, 1800000 + 60000, 40, 323 } end)
H.check(r.verdict:find("WRONG HAND"), "the main hand renewed when the off hand was aimed at: wrong hand")

-- Nothing changed, an error fired: failed.
WoW.enchants[16] = { true, 1500000, 40, 323 }
r = click(B17, nil, { { "UI_ERROR_MESSAGE", 50, "Item is not ready yet." } })
H.eq(r.verdict, "failed", "no change and an error: failed")

-- Renewing the same coating counts: the time left went back up.
WoW.enchants[17] = { true, 1000000, 40, 323 }
r = click(B17, function() WoW.enchants[17] = { true, 1800000, 40, 323 } end)
H.eq(r.verdict:match("^applied") , "applied", "the same poison renewed: applied")

-- Renewing a coating that was nearly full: the time left is back above
-- where the clock alone would have it.
WoW.enchants[16] = { true, 1796000, 40, 323 }
-- (stamped when applied: its time left runs down from the click on)
r = click(A16, function() WoW.enchants[16] = { true, 1800000, 40, 323, t = WoW.time } end)
H.eq(r.verdict:match("^applied") , "applied", "a nearly full coating renewed: applied")
-- Renewed charges count too.
WoW.enchants[16] = { true, 1200000, 12, 323 }
r = click(A16, function() WoW.enchants[16] = { true, 1200000 - 1, 40, 323 } end)
H.eq(r.verdict:match("^applied") , "applied", "charges renewed: applied")
-- A completion event with no visible change: inconclusive, not failed.
r = click(A16, nil, { { "ENCHANT_SPELL_COMPLETED", true } })
H.check(r.verdict:find("^inconclusive %(completed"), "completed but nothing visible changed: inconclusive")

-- Time passing alone is no application: the time left only ran down.
r = click(B16, nil)
H.check(r.verdict:find("^failed"), "only the clock moved: not applied")

-- Still targeting: no verdict until the player picks.
WoW.targeting = true
A16:GetScript("PreClick")(A16, "LeftButton", true)
A16:GetScript("PostClick")(A16, "LeftButton", true)
local n = #ApothecaProbeDB.applyTests
for _ = 1, 8 do WoW.tick(1) end
H.eq(#ApothecaProbeDB.applyTests, n, "no verdict while the cursor still waits for a weapon")
WoW.targeting = false
WoW.enchants[16] = { true, 1800000, 40, 999 }
for _ = 1, 2 do WoW.tick(1) end
H.eq(last().verdict:match("^applied"), "applied", "the verdict comes once the weapon was picked")
H.eq(last().targetingAfterClick, true, "and it records that the click left a targeting cursor")

-- The replace popup is waited for too, and noted.
WoW.popup = "REPLACE_ENCHANT"
A17:GetScript("PreClick")(A17, "LeftButton", true)
A17:GetScript("PostClick")(A17, "LeftButton", true)
n = #ApothecaProbeDB.applyTests
for _ = 1, 8 do WoW.tick(1) end
H.eq(#ApothecaProbeDB.applyTests, n, "no verdict while the replace popup is open")
WoW.popup = nil
WoW.enchants[17] = { true, 1800000, 40, 555 }
for _ = 1, 3 do WoW.tick(1) end
H.eq(last().verdict:match("^applied"), "applied", "answered: the verdict")
H.eq(last().popup, true, "and the popup is recorded")

-- Secret state: never compared, inconclusive.
WoW.enchants[16] = { WoW.Secret(true), WoW.Secret(1), nil, nil }
r = click(A16, nil)
H.check(r.verdict:find("inconclusive"), "secret enchant state: inconclusive")
H.eq(r.before.enchant[16].has, "<secret>", "secrets are stored as <secret>")
WoW.enchants[16] = nil

-- A weapon swap during the attempt: inconclusive.
r = click(A16, function() WoW.equipped[16] = 9999 ; WoW.enchants[16] = { true, 1800000, 40, 1 } end)
H.check(r.verdict:find("inconclusive"), "the weapons changed: inconclusive")
WoW.equipped[16] = 2169

-- One physical click is one attempt, whichever edge the handler acts on.
local before = #ApothecaProbeDB.applyTests
click(A16, function() WoW.enchants[16] = { true, 1800000, 40, 777, t = WoW.time } end)
H.eq(#ApothecaProbeDB.applyTests - before, 1, "press and release make one attempt, not two")

-- A coating lost during a rejected attempt is not an application.
WoW.enchants[16] = { true, 5000, 1, 323 }
r = click(A16, function() WoW.enchants[16] = nil end, { { "UI_ERROR_MESSAGE", 50, "Can't do that" } })
H.eq(r.verdict, "failed", "the intended hand's coating expired, with an error: failed, not applied")
-- The other hand expiring meanwhile does not spoil a real application.
WoW.enchants[17] = { true, 3000, 1, 555 }
r = click(A16, function() WoW.enchants[16] = { true, 1800000, 40, 323, t = WoW.time } ; WoW.enchants[17] = nil end)
H.eq(r.verdict, "applied (gained)", "applied, while the off hand's old coating ran out")
H.eq(r.change.other, "lost", "the other hand is recorded as lost, not coated")

-- Unknown is never "applied": a failed read before the click...
WoW.enchants[16] = nil
WoW.enchantThrow = true
A16:GetScript("PreClick")(A16, "LeftButton", true)
WoW.enchantThrow = false
WoW.enchants[16] = { true, 1800000, 40, 323, t = WoW.time }
A16:GetScript("PostClick")(A16, "LeftButton", true)
for _ = 1, 8 do WoW.tick(1) end
H.check(last().verdict:find("^inconclusive"), "an unreadable baseline: inconclusive, not applied")
-- ...or the other hand secret.
WoW.enchants[16] = nil
WoW.enchants[17] = { WoW.Secret(true), WoW.Secret(1), nil, nil }
r = click(A16, function() WoW.enchants[16] = { true, 1800000, 40, 323, t = WoW.time } end)
H.check(r.verdict:find("^inconclusive %(applied, but the other hand"), "the other hand unreadable: inconclusive")
WoW.enchants[17] = nil

-- A weapon picked late, then the apply cast: the verdict waits for the cast.
WoW.enchants[16] = nil
WoW.targeting = true
A16:GetScript("PreClick")(A16, "LeftButton", true)
A16:GetScript("PostClick")(A16, "LeftButton", true)
for _ = 1, 8 do WoW.tick(1) end
WoW.targeting = false
WoW.fire("UNIT_SPELLCAST_START", "player")
n = #ApothecaProbeDB.applyTests
for _ = 1, 3 do WoW.tick(1) end
H.eq(#ApothecaProbeDB.applyTests, n, "no verdict while the apply cast runs")
WoW.enchants[16] = { true, 1800000, 40, 323, t = WoW.time }
WoW.fire("UNIT_SPELLCAST_SUCCEEDED", "player")
for _ = 1, 3 do WoW.tick(1) end
H.eq(last().verdict:match("^applied"), "applied", "after the cast: applied")

-- A weapon swapped out and back: same IDs at the end, still inconclusive.
WoW.enchants[16] = nil
r = click(A16, function()
    WoW.fire("PLAYER_EQUIPMENT_CHANGED", 16, false)
    WoW.fire("PLAYER_EQUIPMENT_CHANGED", 16, false)
    WoW.enchants[16] = { true, 1800000, 40, 323, t = WoW.time }
end)
H.check(r.verdict:find("^inconclusive %(the weapons"), "a weapon swapped out and back: inconclusive")

-- A second click before the first settled closes the first.
A16:GetScript("PreClick")(A16, "LeftButton", true)
B16:GetScript("PreClick")(B16, "LeftButton", true)
H.eq(ApothecaProbeDB.applyTests[#ApothecaProbeDB.applyTests].ended, "superseded by a new click",
    "a new click closes the open attempt")
for _ = 1, 8 do WoW.tick(1) end

-- An empty hand is recorded as "empty", not as an error (70009 run: the
-- and/or idiom turned nil into "ERROR").
WoW.equipped[17] = nil
r = click(A16, function() WoW.enchants[16] = { true, 1800000, 40, 42, t = WoW.time } end)
H.eq(r.before.weapon[17], "empty", "an empty off hand is recorded as empty")
WoW.equipped[17] = 2209

slash("applytest close")
H.check(not f:IsShown(), "close hides the buttons")

H.done("test_applytest")
