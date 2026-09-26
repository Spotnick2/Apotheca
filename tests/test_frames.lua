-- Executes every event handler, OnUpdate and slash command the addon
-- installs. Strict globals only catch code that actually runs, and a handler
-- nothing calls is exactly where a removed API hides.

dofile("tests/wow_stubs.lua")
local H = dofile("tests/harness.lua")

WoW.AddItem(0, 1, 13444, 5, "Major Mana Potion")
WoW.AddItem(0, 2, 8079, 20, "Conjured Crystal Water")
WoW.AddItem(5, 1, 14530, 10, "Heavy Runecloth Bandage")   -- reagent bag

H.loadAddon({ probe = true })

local EVENTS = {
    "BAG_UPDATE_DELAYED", "BAG_UPDATE_COOLDOWN", "GET_ITEM_INFO_RECEIVED",
    "UNIT_AURA", "UNIT_HEALTH", "UNIT_POWER_UPDATE", "READY_CHECK",
    "READY_CHECK_FINISHED", "ZONE_CHANGED_NEW_AREA", "PLAYER_TALENT_UPDATE",
    "MODIFIER_STATE_CHANGED",
}

local function fireAll()
    for _, e in ipairs(EVENTS) do WoW.fire(e, "player") end
    WoW.tick(1)
    WoW.tick(1)
end

fireAll()
H.check(true, "every event runs out of combat")

WoW.enterCombat()
fireAll()
H.check(true, "every event runs in combat, with auras throwing and health secret")
-- Worst case, not yet measured: cooldowns and stack counts secret too.
WoW.combatSecret = true
fireAll()
H.check(true, "bag and cooldown refreshes survive secret cooldowns and counts")
WoW.combatSecret = false
WoW.leaveCombat()
fireAll()

-- Readable health (a future client): the same handlers must still run.
WoW.healthSecret = false
fireAll()
WoW.healthSecret = true

for _, cmd in ipairs({ "", "status", "debug", "debug", "probe", "reset", "help" }) do
    SlashCmdList["APOTHECA"](cmd)
end
WoW.enterCombat()
SlashCmdList["APOTHECA"]("status")
SlashCmdList["APOTHECA"]("probe")
WoW.leaveCombat()
H.check(true, "every slash command runs, in and out of combat")

-- /apo scan walks the whole item-ID range over many frames.
SlashCmdList["APOTHECA"]("scan")
for _ = 1, 200 do WoW.tick(1) end
local scan = ApothecaProbeDB.itemScan
H.eq(ApothecaDB.itemScan, nil, "the scan is kept in the probe's own SavedVariable, not Apotheca's settings")
H.check(scan and scan.items[13444] and scan.items[13444].t, "the scan records a known consumable with its tooltip")
H.eq(scan and scan.items[13444].t[2], "Use: Restores 61 health over 18 sec.", "tooltip text is kept verbatim")

-- /apo scan2 fills in spell text for anything whose tooltip lacked it.
scan.items[13444].t = { "Major Mana Potion" }
SlashCmdList["APOTHECA"]("scan2")
for _ = 1, 200 do WoW.tick(1) end
H.eq(scan.items[13444].d, "Restores 61 health over 18 sec.", "the second pass records the spell description")

-- Saved data loads back since 70009, so a saved scan may be an older
-- build's: scan2 must not add this build's text to it (/code-review of #17).
scan.build = "69977"
scan.items[13444].t, scan.items[13444].d = { "Major Mana Potion" }, nil
WoW.messages = {}
SlashCmdList["APOTHECA"]("scan2")
for _ = 1, 20 do WoW.tick(1) end
H.eq(scan.items[13444].d, nil, "scan2 leaves another build's scan alone")
H.eq(H.messagesMatching("from build 69977"), 1, "and says to scan again")

-- A scan an older probe left in Apotheca's own settings moves to the probe's.
local old = { build = "69977", items = {} }
ApothecaDB.itemScan = old
rawset(_G, "ApothecaProbeDB", nil)
SlashCmdList["APOTHECA"]("scan2")
H.check(ApothecaProbeDB and ApothecaProbeDB.itemScan == old, "an old scan in ApothecaDB moves to ApothecaProbeDB")
H.eq(ApothecaDB.itemScan, nil, "and leaves Apotheca's settings")

-- /apo scan3 collects every "Well Fed" spell with its description (#19),
-- and says when its result is incomplete (Codex review of #20).
WoW.spellNames[19705]   = "Well Fed"      -- ordinary, Vanilla range
WoW.spellNames[1248422] = "Well Fed"      -- XP (measured on 70009)
WoW.spellNames[1248380] = "Nutritious Food"
WoW.spellNames[1248500] = "Well Fed"      -- its description never loads
WoW.spellLoadAfter[1300001] = { name = "Well Fed", n = 3 }         -- loads on the 3rd request
WoW.spellLoadAfter[1300002] = { name = "Well Fed", n = math.huge } -- never loads
WoW.spellNames[1450000] = "Some Spell"    -- near the 1.5M floor: the sweep goes on
WoW.spellNames[1640000] = "Well Fed"      -- so this one, past 1.5M, is found
WoW.spellDescriptions[19705]   = "Stamina increased by 12."
-- Measured on 70009: the XP aura's DESCRIPTION does not mention experience.
WoW.spellDescriptions[1248422] = "A nutritious meal has made you Well Fed, increasing your Strength."
WoW.spellTooltips[1248422] = { "Well Fed", "Your Strength is increased by 1. Experience gained from kills increased by 5%." }
WoW.spellDescriptions[1300001] = "Your Intellect is increased by 6. Experience gained from kills increased by 5%."
WoW.spellDescriptions[1640000] = "Your Spirit is increased by 4. Experience gained from kills increased by 5%."
local function runScan3()
    WoW.messages = {}
    SlashCmdList["APOTHECA"]("scan3")
    for _ = 1, 1500 do
        WoW.tick(1)
        if H.messagesMatching("Well Fed scan done") > 0 then break end
    end
    return ApothecaProbeDB.wellFedScan
end
local ticks0 = WoW.profileMs
local wf = runScan3()
H.check(wf ~= nil, "scan3 stores its result in the probe's SavedVariable")
H.eq(wf and wf.spells[1248422], WoW.spellDescriptions[1248422], "the XP Well Fed is found with its description")
H.eq(wf and wf.spells[19705], "Stamina increased by 12.", "ordinary Well Fed is recorded too")
H.eq(wf and wf.spells[1300001], WoW.spellDescriptions[1300001], "a name that loads only after retries is found")
H.eq(wf and wf.spells[1640000], WoW.spellDescriptions[1640000], "the sweep follows spells past 1.5M")
H.eq(wf and wf.scannedTo, 1840000, "and stops 200k past the highest spell")
H.eq(wf and wf.spells[1248380], nil, "other spells are not kept")
H.eq(wf and wf.unnamedNeverLoaded, 1, "a name that never loads is counted")
H.eq(wf and wf.neverLoaded[1], 1300002, "and its ID is recorded")
H.eq(wf and wf.tooltips[1248422], WoW.spellTooltips[1248422][1] .. " | " .. WoW.spellTooltips[1248422][2],
    "the spell tooltip is kept, where the XP line may be")
H.eq(wf and wf.noDescription, 1, "a missing description is counted")
H.eq(wf and wf.complete, false, "so the result is marked incomplete")
H.eq(H.messagesMatching("INCOMPLETE"), 1, "and the summary says so")
H.eq(H.messagesMatching("3 with the XP bonus"), 1, "the summary counts the XP ones")

WoW.spellLoadAfter[1300002] = nil
WoW.spellDescriptions[1248500] = "Your Stamina is increased by 2."
wf = runScan3()
H.eq(wf and wf.complete, true, "with every name and description loaded, the scan is complete")
H.eq(H.messagesMatching("%(complete%)"), 1, "and says complete")

-- Every button's scripts.
for key, btn in pairs(Apotheca.buttons) do
    for _, script in ipairs({ "OnEnter", "OnLeave", "PreClick", "PostClick" }) do
        local h = btn:GetScript(script)
        if h then h(btn, "LeftButton", true) end
    end
    if btn._askOverlay then
        local h = btn._askOverlay:GetScript("OnClick")
        if h then h(btn._askOverlay, "LeftButton") ; h(btn._askOverlay, "RightButton") end
    end
end
H.check(true, "button scripts run")

-- Popups.
for name, dlg in pairs(StaticPopupDialogs) do
    if name:match("^APOTHECA") and dlg.OnAccept then
        dlg.OnAccept({ data = { btnKey = "drink", altItemID = 8079 } })
    end
end
H.check(true, "popup accept handlers run")

-- Drag anchor with Alt held.
WoW.altDown = true
WoW.fire("MODIFIER_STATE_CHANGED", "LALT", 1)
WoW.tick(1)
WoW.altDown = false
WoW.fire("MODIFIER_STATE_CHANGED", "LALT", 0)
WoW.tick(1)

WoW.fire("PLAYER_LOGOUT")
H.check(ApothecaDB.svLoadCheck ~= nil, "the SavedVariables sentinel is written every session")

H.eq(H.messagesMatching("rejected event"), 0, "no event was rejected")

H.done("test_frames")
