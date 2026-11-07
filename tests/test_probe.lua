-- The developer probe as a ForeverProbe module (#76): /fp apo probe, the
-- three scans the item tables are generated from (/fp apo scan, scan2,
-- scan3), its saved log, and the procedures /fp steps apo scan and probe.
-- Local only: ForeverProbe is private, so CI skips this file (harness.lua).

dofile("tests/wow_stubs.lua")
local H = dofile("tests/harness.lua")

WoW.AddItem(0, 1, 13444, 5, "Major Mana Potion")
WoW.AddItem(0, 2, 8079, 20, "Conjured Crystal Water")
H.loadAddon({ probe = true })

local FP = ForeverProbe
local Steps = FP.Steps
local fp = H.fp

-- Registered as a module, its log bound to its own SavedVariable.
check(FP.byCmd.apo and FP.byCmd.apo.name == "ApothecaProbe", "the probe answers /fp apo")
check(type(ApothecaProbeDB.log) == "table" and FP.modules.ApothecaProbe.log == ApothecaProbeDB.log,
    "its log is ApothecaProbeDB.log, bound by reference")
eq(ApothecaProbeDB.loads, 1, "loads are counted")

-- /apo no longer runs the probe: those words open the options, like any other.
WoW.chat = {}
SlashCmdList["APOTHECA"]("probe")
eq(ApothecaProbeDB.lastProbe, nil, "/apo probe is not a probe command any more")

-- /fp apo probe: out of combat and in combat, every line in the console and
-- the saved log, none in chat.
fp("probe")
check(ApothecaProbeDB.lastProbe and ApothecaProbeDB.lastProbe.idle, "out of combat: kept as lastProbe.idle")
check(H.probeMatching("UnitHealth/Max = <secret>, 1000") == 1, "a secret is shown as <secret>, never read")
check(H.probeMatching("  %-> blocked event = none") == 1, "UseItemByName unblocked: none")
eq(#WoW.chat, 0, "nothing in chat")
WoW.enterCombat()
fp("probe")
WoW.leaveCombat()
check(ApothecaProbeDB.lastProbe.combat, "in combat: kept as lastProbe.combat")

-- A blocked action reaches the probe through the host's watcher (it no
-- longer registers ADDON_ACTION_BLOCKED itself).
local realUse = C_Item.UseItemByName
C_Item.UseItemByName = function() WoW.fire("ADDON_ACTION_BLOCKED", "Apotheca", "UseItemByName") end
fp("probe")
C_Item.UseItemByName = realUse
eq(H.probeMatching("blocked event = ADDON_ACTION_BLOCKED %(Apotheca, UseItemByName%)"), 1,
    "a blocked UseItemByName is reported, through the host's watcher")

-- An error inside a probed call is the run's line, in the old format.
local log = ApothecaProbeDB.lastProbe.idle
local function has(prefix)
    for _, line in ipairs(log) do if line:sub(1, #prefix) == prefix then return line end end
end
check(has("build = "), "the run's own table keeps 'key = returns' lines")

-- /fp apo scan walks the whole item-ID range over many frames.
fp("scan")
for _ = 1, 200 do WoW.step(1) end
local scan = ApothecaProbeDB.itemScan
eq(ApothecaDB.itemScan, nil, "the scan is kept in the probe's own SavedVariable, not Apotheca's settings")
check(scan and scan.items[13444] and scan.items[13444].t, "the scan records a known consumable with its tooltip")
eq(scan and scan.items[13444].t[2], "Use: Restores 61 health over 18 sec.", "tooltip text is kept verbatim")
eq(H.probeMatching("scan done"), 1, "the summary is in the console")
eq(#WoW.chat, 0, "and nothing in chat")

-- /fp apo scan2 fills in spell text for anything whose tooltip lacked it.
scan.items[13444].t = { "Major Mana Potion" }
fp("scan2")
for _ = 1, 200 do WoW.step(1) end
eq(scan.items[13444].d, "Restores 61 health over 18 sec.", "the second pass records the spell description")

-- Saved data loads back since 70009, so a saved scan may be an older
-- build's: scan2 must not add this build's text to it (/code-review of #17).
scan.build = "69977"
scan.items[13444].t, scan.items[13444].d = { "Major Mana Potion" }, nil
fp("scan2")
for _ = 1, 20 do WoW.step(1) end
eq(scan.items[13444].d, nil, "scan2 leaves another build's scan alone")
eq(H.probeMatching("from build 69977"), 1, "and says to scan again")

-- A scan an older probe left in Apotheca's own settings moves to the probe's.
local old = { build = "69977", items = {} }
ApothecaProbeDB.itemScan = nil
ApothecaDB.itemScan = old
fp("scan2")
check(ApothecaProbeDB.itemScan == old, "an old scan in ApothecaDB moves to ApothecaProbeDB")
eq(ApothecaDB.itemScan, nil, "and leaves Apotheca's settings")

-- /fp apo scan3 collects every "Well Fed" spell with its description (#19),
-- lists the names that never load, and is INCOMPLETE only when unnamed
-- spells were skipped (Codex review and /code-review of #20).
WoW.spellNames[19705]   = "Well Fed"      -- ordinary, Vanilla range: empty description
WoW.spellNames[1248422] = "Well Fed"      -- XP (measured on 70009)
WoW.spellNames[1248380] = "Nutritious Food"
WoW.spellLoadAfter[1300001] = { name = "Well Fed", n = 3 }         -- loads on the 3rd request
WoW.spellLoadAfter[1300002] = { name = "Well Fed", n = math.huge } -- hidden: never loads
WoW.spellNames[1450000] = "Some Spell"    -- near the 1.5M floor: the sweep goes on
WoW.spellNames[1640000] = "Well Fed"      -- so this one, past 1.5M, is found
-- Measured on 70009: the XP aura's description does not mention experience.
WoW.spellDescriptions[1248422] = "A nutritious meal has made you Well Fed, increasing your Strength."
WoW.spellDescriptions[1300001] = "A nutritious meal has made you Well Fed, increasing your Intellect."
WoW.spellDescriptions[1640000] = "A tasty drink has made you Well Fed, increasing your Spirit."
local function runScan3()
    fp("scan3")
    for _ = 1, 3000 do
        WoW.step(1)
        if H.probeMatching("Well Fed scan done") + H.probeMatching("stopped by an error") > 0 then break end
    end
    return ApothecaProbeDB.wellFedScan
end
local wf = runScan3()
check(wf ~= nil, "scan3 stores its result in the probe's SavedVariable")
eq(wf and wf.spells[1248422], WoW.spellDescriptions[1248422], "the XP Well Fed is found with its description")
eq(wf and wf.spells[19705], "", "a Well Fed with an empty description is recorded as empty")
eq(wf and wf.emptyDescription, 1, "and counted")
eq(wf and wf.spells[1300001], WoW.spellDescriptions[1300001], "a name that loads only after retries is found")
eq(wf and wf.spells[1640000], WoW.spellDescriptions[1640000], "the sweep follows spells past 1.5M")
eq(wf and wf.scannedTo, 1840000, "and stops 200k past the highest spell")
eq(wf and wf.spells[1248380], nil, "other spells are not kept")
eq(wf and #wf.hidden, 1, "a name that never loads is listed as hidden")
eq(wf and wf.hidden[1], 1300002, "by its ID")
eq(wf and wf.complete, true, "hidden names and empty descriptions do not make the scan incomplete")
eq(H.probeMatching("%(complete%)"), 1, "the summary says complete")
eq(H.probeMatching("hidden 1 %(1300002%)"), 1, "and lists the hidden ID")

-- More unnamed spells than the load limit: those outside 1.2M..1.4M are
-- skipped, and only that makes the scan INCOMPLETE.
for id = 200001, 260001 do WoW.spellLoadAfter[id] = { name = "Filler", n = 1 } end
wf = runScan3()
eq(wf and wf.unnamedSkipped, 60001, "unnamed spells past the load limit are skipped outside the range")
eq(wf and wf.complete, false, "and the scan is INCOMPLETE")
eq(wf and wf.spells[1300001] ~= nil, true, "names inside the range are still loaded")
for id = 200001, 260001 do WoW.spellLoadAfter[id] = nil end

-- An error mid-scan stops it and frees the guard, instead of erroring
-- every frame with "scan already running" until /reload.
local realName = C_Spell.GetSpellName
C_Spell.GetSpellName = function() error("boom") end
runScan3()
C_Spell.GetSpellName = realName
eq(H.probeMatching("stopped by an error"), 1, "an error stops the scan and says so")
check(H.probe.scans.status.wellfed:find("^error"), "and its status says so")
fp("scan3")
eq(H.probeMatching("already running"), 0, "and a new scan can start")
for _ = 1, 3000 do WoW.step(1) if H.probeMatching("Well Fed scan done") > 0 then break end end
fp("scan")
fp("scan2")
eq(H.probeMatching("already running"), 1, "one scan at a time")
for _ = 1, 400 do WoW.step(1) if H.probe.scans.running == nil then break end end

-- /fp steps apo scan: the three scans, each waited for, then a /reload.
local function record(name) return FP.db.steps.records["ApothecaProbe/" .. name] end
SlashCmdList.FOREVERPROBE("steps apo scan")
eq(FP.db.steps.active, "ApothecaProbe/scan", "the scan procedure starts")
Steps.Run()                                       -- 1: start the item scan
for _ = 1, 4000 do
    WoW.step(1)
    local rec = record("scan")
    if rec.at >= 7 then break end
end
local rec = record("scan")
eq(rec.at, 7, "every scan ran and was waited for, up to the /reload step")
eq(rec.results[2].check, "PASS", "the item scan finished")
eq(rec.results[4].check, "PASS", "the spell scan finished")
eq(rec.results[6].check, "PASS", "the Well Fed scan finished, complete")
-- The reload: a new run at login completes the step.
FP.db.baseline.loadCount = FP.db.baseline.loadCount + 1
FP.run = FP.db.baseline.loadCount
Steps.Resume()
eq(record("scan").status, "done", "after the /reload the procedure is done")

-- A /reload during a scan (Codex review of #77): ForeverProbe resumes the
-- procedure at the wait step, but the scan's state was per session and its
-- frame is gone. The wait must not complete on that: an older same-build
-- scan saved earlier would be carried into scan2, scan3 and the export.
local stale = { build = select(2, GetBuildInfo()), items = {}, stale = true }
ApothecaProbeDB.itemScan = stale
-- What a /reload does to the probe: the running scan stops, the session's
-- scan state starts empty, and ForeverProbe resumes the procedure at login.
local function reloadMidScan()
    H.probe.scanFrame:SetScript("OnUpdate", nil)
    for k in pairs(H.probe.scans.status) do H.probe.scans.status[k] = nil end
    H.probe.scans.running, H.probe.scans.progress = nil, nil
    FP.db.baseline.loadCount = FP.db.baseline.loadCount + 1
    FP.run = FP.db.baseline.loadCount
    Steps.Resume()
end
SlashCmdList.FOREVERPROBE("steps apo scan")
Steps.Run()                                       -- 1: the item scan starts
WoW.step(1)
eq(H.probe.scans.status.items, "running", "the item scan is running")
reloadMidScan()
eq(record("scan").at, 2, "after the /reload the procedure is back at the item scan's wait")
for _ = 1, 3 do WoW.step(1) end
eq(record("scan").at, 2, "and does not go on without the scan")
eq(H.probe.scans.running, "items", "the interrupted scan is started again")
eq(H.probeMatching("interrupted %(a /reload%): started again"), 1, "and says so")
for _ = 1, 4000 do WoW.step(1) if record("scan").at >= 7 then break end end
eq(record("scan").at, 7, "the restarted scans run through to the /reload step")
check(not ApothecaProbeDB.itemScan.stale, "with this session's item scan, never the stale one")
eq(record("scan").results[2].check, "PASS", "and the item scan's check passes")
Steps.Stop("test")

-- A scan stopped by an error: its wait stays until it is run again.
SlashCmdList.FOREVERPROBE("steps apo scan")
Steps.Run()
WoW.step(1)
eq(H.probe.scans.status.items, "running", "the item scan is running")
H.probe.scanFrame:SetScript("OnUpdate", nil)
H.probe.scans.running, H.probe.scans.status.items = nil, "error: boom"
for _ = 1, 3 do WoW.step(1) end
eq(record("scan").at, 2, "an errored scan does not complete its wait")
Steps.Back()                                      -- 1: run the item scan again
Steps.Run()
for _ = 1, 4000 do WoW.step(1) if record("scan").at >= 7 then break end end
eq(record("scan").at, 7, "run again, the procedure goes on")
eq(record("scan").results[2].check, "PASS", "and the item scan's check passes")
Steps.Stop("test")

-- A scan that cannot start keeps its step, for Retry or Skip.
ApothecaProbeDB.itemScan = nil
SlashCmdList.FOREVERPROBE("steps apo scan")
H.probe.scans.running = "items"                   -- as if one were already running
Steps.Run()
eq(record("scan").at, 1, "refused: the step stays")
eq(record("scan").results[1].errors, 1, "with the error counted")
H.probe.scans.running = nil
Steps.Stop("test")

-- /fp steps apo probe: out of combat, then in combat on entering it.
ApothecaProbeDB.lastProbe = nil
SlashCmdList.FOREVERPROBE("steps apo probe")
Steps.Run()
check(ApothecaProbeDB.lastProbe and ApothecaProbeDB.lastProbe.idle, "step 1 runs the probe out of combat")
eq(record("probe").results[1].check, "PASS", "and checks it was out of combat")
-- PLAYER_REGEN_DISABLED fires before lockdown: nothing runs until it is on.
WoW.fire("PLAYER_REGEN_DISABLED")
for _ = 1, 3 do WoW.step(1) end
eq(ApothecaProbeDB.lastProbe.combat, nil, "not before lockdown is on")
WoW.enterCombat()
for _ = 1, 3 do WoW.step(1) end
check(ApothecaProbeDB.lastProbe.combat, "in lockdown the probe runs again, in combat")
eq(record("probe").results[2].check, "PASS", "and it is checked")
WoW.leaveCombat()
eq(record("probe").at, 3, "then waits for the /reload")
Steps.Stop("test")

-- clear empties the saved log in place: the host keeps the same table.
local saved = ApothecaProbeDB.log
fp("clear")
check(ApothecaProbeDB.log == saved, "clear keeps the table")
FP.modules.ApothecaProbe:Say("after clear")
eq(saved[#saved]:match("after clear$"), "after clear", "a new line reaches the saved log")
eq(H.probeMatching("after clear$"), 1, "and the console")

eq(H.messagesMatching("."), 0, "nothing the probe did reached chat")
done("test_probe")
