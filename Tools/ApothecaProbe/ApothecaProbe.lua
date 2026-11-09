-- ============================================================
-- ApothecaProbe: Apotheca's developer probe, a ForeverProbe module (/fp apo)
--
-- A throwaway measurement tool (issue #3 onwards): what the client
-- actually does for each API Apotheca depends on, the client's own
-- consumable and Well Fed data (the item tables are generated from it),
-- the action bar layout, professions, and how a secure button applies a
-- weapon coating. Its lines go to the /fp console and ApothecaProbeDB.log;
-- its results stay in ApothecaProbeDB (SavedVariables/ApothecaProbe.lua),
-- written at /reload or logout, where Tools/export_*.lua read them.
--
--   /fp apo                  the commands
--   /fp steps apo scan       rebuild the item data: scan, scan2, scan3, /reload
--   /fp steps apo probe      the bar's APIs out of combat, then in combat
--
-- A separate, development-only addon (Tools/ApothecaProbe, after
-- ForeverProbe and Apotheca): never packaged; `pwsh Tools/deploy.ps1
-- -Probe` installs it next to ForeverProbe (#76).
-- ============================================================

local ADDON, NS = ...
local MAX_LOG = 3000

local Probe = ForeverProbe:Module("ApothecaProbe", { api = 1, cmd = "apo" })
NS = NS or {}
NS._test = NS._test or {}          -- the test seam, never on _G

local function say(msg) Probe:Say(msg) end
local log   -- the lines of the run in progress, kept by name (lastProbe, barProbe, profProbe)

-- The probe keeps its results in its own SavedVariable, not in Apotheca's
-- settings: the item scan is large, and now that saved data loads back it
-- would be parsed and rewritten with Apotheca's settings at every login.
-- Results an older probe left in ApothecaDB move here.
local function ProbeDB()
    if type(ApothecaProbeDB) ~= "table" then ApothecaProbeDB = {} end
    if type(ApothecaDB) == "table" then
        for _, k in ipairs({ "itemScan", "lastProbe" }) do
            if ApothecaDB[k] ~= nil then
                if ApothecaProbeDB[k] == nil then ApothecaProbeDB[k] = ApothecaDB[k] end
                ApothecaDB[k] = nil
            end
        end
    end
    return ApothecaProbeDB
end

-- Saved tables only at our own ADDON_LOADED: the client loads them after
-- the files (GUIDE.md section 1).
local boot = CreateFrame("Frame")
Probe:RegisterEvents(boot, { "ADDON_LOADED" })
boot:SetScript("OnEvent", function(self, _, name)
    if name ~= ADDON then return end
    self:UnregisterEvent("ADDON_LOADED")
    Probe:Ready()
    local db = ProbeDB()
    if type(db.log) ~= "table" then db.log = {} end
    Probe:UseLog(db.log, MAX_LOG)
    db.loads = (db.loads or 0) + 1
    say("loaded (" .. db.loads .. " loads). /fp apo for the commands, /fp steps apo for the procedures")
end)

-- A run's line: kept in the run's table and said.
local function out(key, value)
    local text = tostring(value)
    log[#log + 1] = key .. " = " .. text
    say(key .. " = " .. text)
end

-- Every return, unquoted, a secret as <secret>, never compared.
-- select("#") keeps trailing nils, so "returned nil" and "returned
-- nothing" stay distinct: C_Item.GetItemInfo's cache miss is the latter.
local function describe(...)
    local n = select("#", ...)
    if n == 0 then return "(no returns)" end
    local parts = {}
    for i = 1, n do parts[i] = Probe.Show((select(i, ...)), true) end
    return table.concat(parts, ", ")
end

-- The run's "key = returns" line. Probe:Try says the ERROR line itself;
-- the run's table gets it too, in the old format.
local function try(key, fn)
    local r = Probe.Pack(Probe:Try(key, fn))
    if r[1] then
        out(key, describe(unpack(r, 2, r.n)))
    else
        log[#log + 1] = key .. " = ERROR: " .. Probe.Show(r[2], true)
    end
end

-- Blocked actions. The host's baseline is the one ADDON_ACTION_BLOCKED /
-- FORBIDDEN watcher, and it logs them; the probe also needs them inside
-- its own records (UseItemByName in /fp apo probe, an attempt's verdict
-- in applytest and proftest). The host has no callback for that yet, so
-- this listens on the baseline's frame. Workaround: replace it with the
-- host's callback once ForeverProbe offers one (ForeverProbe#19).
local blockedListeners = {}
local function OnBlocked(fn) blockedListeners[#blockedListeners + 1] = fn end
do
    local taint = ForeverProbe.Baseline and ForeverProbe.Baseline.taintFrame
    if taint and taint.HookScript then
        taint:HookScript("OnEvent", function(_, event, ...)
            for _, fn in ipairs(blockedListeners) do fn(event, ...) end
        end)
    else
        say("ForeverProbe's taint watcher not found: blocked actions are missing from the verdicts")
    end
end

local blockedBy
OnBlocked(function(event, addon, func)
    blockedBy = event .. " (" .. Probe.Show(addon, true) .. ", " .. Probe.Show(func, true) .. ")"
end)

local TEMPLATES = {
    { "CheckButton", "InterfaceOptionsCheckButtonTemplate", "Text" },
    { "CheckButton", "UIRadioButtonTemplate", nil },
    { "Slider",      "OptionsSliderTemplate", "Low" },
    { "Frame",       "UIDropDownMenuTemplate", "Text" },
    { "Button",      "UIPanelButtonTemplate", "Text" },
    { "Cooldown",    "CooldownFrameTemplate", nil },
}

-- ============================================================
-- /fp apo scan: the client's own consumable database (issue #4)
--
-- Wowhead's Forever database lists names, but Forever changed restore
-- values, and a database can miss items. So walk every item ID with
-- C_Item.GetItemInfoInstant (it reads the client's item DB, no cache
-- needed), keep the consumables (classID 0), then read each one's tooltip
-- text and item spell. The result lands in ApothecaProbeDB.itemScan, which
-- the client writes to disk at logout; the item tables are built from that
-- file.
-- ============================================================

local SCAN_MAX_ID    = 300000   -- Wowhead's highest Forever consumable is ~286k
local SCAN_PER_FRAME = 3000
local TIP_TRIES      = 20       -- 0.5 s apart: ~10 s for a slow item load
local FRAME_MS       = 8        -- work per frame in the retry phases
local RETRY_DELAY    = 0.5

-- A retry queue, shared by the three scans. Drain() tries entries with
-- step(id, try) until the frame's time budget is spent; step returns true
-- when the entry is settled, false to try it again RETRY_DELAY later.
-- A retry is appended and the head moves on, which is O(1) (/code-review
-- of #20: table.remove shifted the whole queue on every retry). Retries
-- are appended in the order they fall due, so a head that is not due yet
-- means nothing behind it is either: wait for the next frame.
local function NewQueue(ids)
    local copy = {}                -- the queue grows; never the caller's list
    for i = 1, #ids do copy[i] = ids[i] end
    return { ids = copy, head = 1, tries = {}, due = {} }
end

local function Drain(q, step)
    local deadline = debugprofilestop() + FRAME_MS
    local ids = q.ids
    while q.head <= #ids do
        if debugprofilestop() > deadline then return false end
        local id = ids[q.head]
        if q.due[id] and q.due[id] > GetTime() then return false end
        local n = (q.tries[id] or 0) + 1
        q.tries[id] = n
        q.head = q.head + 1
        if not step(id, n) then
            q.due[id] = GetTime() + RETRY_DELAY
            ids[#ids + 1] = id
        end
    end
    return true
end

-- One scan at a time. status[name] is "running", "done" or "error: ..."
-- (name: items, spells, wellfed), progress what the running one is at,
-- summary[name] its last done line: the scan procedure waits on these.
local scans = { running = nil, status = {}, summary = {}, progress = nil }
NS._test.scans = scans

local function StartScan(name)
    if scans.running then
        say("scan already running")
        return false
    end
    scans.running, scans.status[name], scans.progress = name, "running", nil
    return true
end

local function ScanDone(name, line)
    scans.summary[name] = line
    say(line)
end

-- Runs body() every frame until it returns true. An error stops the scan
-- and says so, instead of erroring every frame with the "scan already
-- running" guard stuck until /reload (/code-review of #20).
local function RunScanFrames(body)
    local f = CreateFrame("Frame")
    local name = scans.running
    NS._test.scanFrame = f            -- a test stops it as a /reload would
    f:SetScript("OnUpdate", function(self)
        local ok, finished = pcall(body)
        if not ok or finished then
            self:SetScript("OnUpdate", nil)
            scans.running = nil
            scans.status[name] = ok and "done" or ("error: " .. Probe.Show(finished, true))
            if not ok then say("scan stopped by an error: " .. Probe.Show(finished, true)) end
        end
    end)
end

local function TooltipLines(id)
    local ok, lines = pcall(function()
        local data = C_TooltipInfo.GetItemByID(id)
        if not data or not data.lines then return nil end
        local out = {}
        for _, line in ipairs(data.lines) do
            if line.leftText and line.leftText ~= "" then out[#out + 1] = line.leftText end
            if line.rightText and line.rightText ~= "" then out[#out + 1] = "  >" .. line.rightText end
        end
        return #out > 1 and out or nil   -- a name-only tooltip is not loaded yet
    end)
    return ok and lines or nil
end

local function RunItemScan()
    if not StartScan("items") then return false end
    local found, order = {}, {}
    local nextID, tips = 1, nil
    say("scanning item IDs 1-" .. SCAN_MAX_ID .. " for consumables...")

    RunScanFrames(function()
        if not tips then
            local last = math.min(nextID + SCAN_PER_FRAME - 1, SCAN_MAX_ID)
            for id = nextID, last do
                local itemID, _, subType, _, _, classID, subClassID = C_Item.GetItemInfoInstant(id)
                if itemID and classID == 0 then
                    found[id] = { c = classID, s = subClassID, st = subType }
                    order[#order + 1] = id
                    C_Item.RequestLoadItemDataByID(id)
                end
            end
            nextID = last + 1
            scans.progress = "item ID " .. math.min(nextID, SCAN_MAX_ID) .. " of " .. SCAN_MAX_ID
            if nextID > SCAN_MAX_ID then
                tips = NewQueue(order)
                say(#order .. " consumables found; reading tooltips...")
            end
            return false
        end
        scans.progress = "tooltips " .. (tips.head - 1) .. " of " .. #tips.ids
        local done = Drain(tips, function(id, try)
            local lines = TooltipLines(id)
            if not lines and try < TIP_TRIES then
                C_Item.RequestLoadItemDataByID(id)   -- not loaded yet: ask again
                return false
            end
            local e = found[id]
            e.t = lines
            e.n = C_Item.GetItemInfo(id)
            local okSpell, spellName, spellID = pcall(C_Item.GetItemSpell, id)
            if okSpell then e.sp, e.spn = spellID, spellName end
            return true
        end)
        if not done then return false end
        local missing = 0
        for _, e in pairs(found) do if not e.t then missing = missing + 1 end end
        ProbeDB().itemScan = { build = select(2, GetBuildInfo()), items = found }
        ScanDone("items", "scan done: " .. #order .. " consumables, " .. missing
              .. " without tooltip text. /reload or log out to write the file.")
        return true
    end)
    return true
end

-- /fp apo scan2: second pass. Item tooltips come back without their "Use:"
-- line until the item's SPELL is loaded, and on the first run most
-- potions, elixirs, flasks, scrolls and bandages had none. For the
-- healer-relevant categories, load each item's spell and read its
-- description directly. Results merge into ApothecaProbeDB.itemScan (as `d`).
-- 8 = "Other": healthstones, battleground rations, mana gems, Stratholme
-- Holy Water and Dense Runecloth Bandage all live there. On 70009 they came
-- back without spell text because this list left them out (#16).
local RELEVANT_SUB = { [1] = true, [2] = true, [3] = true, [4] = true, [5] = true, [7] = true, [8] = true }
local DESC_TRIES   = 40         -- 0.5 s apart: ~20 s

local function HasUseLine(lines)
    for _, l in ipairs(lines or {}) do
        if l:find("^Use:") then return true end
    end
    return false
end

local function RunSpellScan()
    if scans.running then say("scan already running") return false end
    local scan = ProbeDB().itemScan
    if not scan then say("run /fp apo scan first") return false end
    -- Saved data loads back since 70009, so the scan found here may be a
    -- previous build's. Adding this build's spell text to it would export
    -- two builds under one name (/code-review of #17).
    local build = select(2, GetBuildInfo())
    if tostring(scan.build) ~= tostring(build) then
        say("the saved scan is from build " .. tostring(scan.build)
              .. ", this client is " .. tostring(build) .. ": run /fp apo scan first")
        return false
    end
    StartScan("spells")

    local ids = {}
    for id, e in pairs(scan.items) do
        local oil = e.n and e.n:find("Oil")
        if (RELEVANT_SUB[e.s] or oil) and e.sp and not HasUseLine(e.t) and not e.d then
            ids[#ids + 1] = id
            C_Spell.RequestLoadSpellData(e.sp)
            C_Item.RequestLoadItemDataByID(id)
        end
    end
    local count = #ids
    say(count .. " items need their spell text; loading...")

    local q = NewQueue(ids)
    RunScanFrames(function()
        scans.progress = "spell text " .. (q.head - 1) .. " of " .. #q.ids
        local done = Drain(q, function(id, try)
            local e = scan.items[id]
            local okD, desc = pcall(C_Spell.GetSpellDescription, e.sp)
            local lines = TooltipLines(id)
            local got = (okD and desc and desc ~= "") or HasUseLine(lines)
            if not got and try < DESC_TRIES then
                C_Spell.RequestLoadSpellData(e.sp)
                return false
            end
            if okD and desc and desc ~= "" then e.d = desc end
            if lines and HasUseLine(lines) then e.t = lines end
            return true
        end)
        if not done then return false end
        local still = 0
        for id in pairs(q.tries) do
            local e = scan.items[id]
            if not e.d and not HasUseLine(e.t) then still = still + 1 end
        end
        ScanDone("spells", "spell scan done: " .. count .. " items, " .. still
              .. " still without text. /reload to write the file.")
        return true
    end)
    return true
end

-- /fp apo scan3: the Well Fed buffs (#19). Forever's XP food ("experience
-- gained from kills is increased by 5%") gives ONE aura named "Well Fed",
-- like ordinary food, and its spell ID is not the item's spell (measured:
-- item spell 1248380 gives aura 1248422). The only language-independent
-- way to tell an XP Well Fed from an ordinary one is its aura spell ID, so
-- this pass collects every spell named "Well Fed" with its description.
-- The XP line is in neither the description nor the spell tooltip
-- (measured on 70009), so the probe does not classify: the generator does.
--
-- Nothing assumes where those IDs are (Codex reviews of #19 and #20):
-- - the sweep goes on until SPELL_SCAN_TAIL IDs past the highest spell that
--   exists, and at least to SPELL_SCAN_MIN;
-- - every spell whose name was not loaded is requested and retried, unless
--   there are more than SPELL_LOAD_ALL_LIMIT of them; then only those in
--   SPELL_LOAD_FROM..SPELL_LOAD_TO (Forever's new food spells) are, and the
--   rest are counted as skipped: only a skip makes the scan INCOMPLETE.
-- - Names that never load are listed as `hidden`: Blizzard keeps some spell
--   data encrypted until it is discovered, so these are permanent on a
--   build, not a failure to retry (/code-review of #20). Empty descriptions
--   are recorded as they are: old Vanilla Well Fed spells have none.
-- Each frame stops after FRAME_MS of work. Names are compared in English:
-- run it on an enUS client.
local SPELL_SCAN_MIN        = 1500000
local SPELL_SCAN_TAIL       = 200000
local SPELL_LOAD_ALL_LIMIT  = 60000
local SPELL_LOAD_FROM, SPELL_LOAD_TO = 1200000, 1400000
local SPELL_LOAD_TRIES      = 30      -- 0.5 s apart: 13 names outlasted 10 on 70009
local WELL_FED = "Well Fed"

local function RunWellFedScan()
    if not StartScan("wellfed") then return false end
    local result = { build = select(2, GetBuildInfo()), highest = 0, scannedTo = 0, exist = 0,
                     unnamedSkipped = 0, hidden = {}, emptyDescription = 0,
                     complete = false, spells = {} }
    local unnamed, candidates = {}, {}
    local nextID, names, descs = 1, nil, nil

    local function named(id)
        local name = C_Spell.GetSpellName(id)
        if name == WELL_FED then candidates[#candidates + 1] = id end
        return name ~= nil
    end
    local function lastID() return math.max(SPELL_SCAN_MIN, result.highest + SPELL_SCAN_TAIL) end

    say("Well Fed scan: walking spell IDs...")
    RunScanFrames(function()
        if not names then
            -- Which spells exist, and the names that are already loaded.
            local deadline = debugprofilestop() + FRAME_MS
            while nextID <= lastID() and debugprofilestop() <= deadline do
                local id = nextID
                nextID = nextID + 1
                if C_Spell.DoesSpellExist(id) then
                    result.exist, result.highest = result.exist + 1, id
                    if not named(id) then unnamed[#unnamed + 1] = id end
                end
            end
            scans.progress = "spell ID " .. nextID .. " of at least " .. lastID()
            if nextID <= lastID() then return false end
            result.scannedTo = nextID - 1
            if #unnamed > SPELL_LOAD_ALL_LIMIT then
                local keep = {}
                for _, id in ipairs(unnamed) do
                    if id >= SPELL_LOAD_FROM and id <= SPELL_LOAD_TO then keep[#keep + 1] = id
                    else result.unnamedSkipped = result.unnamedSkipped + 1 end
                end
                unnamed = keep
            end
            names = NewQueue(unnamed)
            say(result.exist .. " spells exist (highest " .. result.highest .. "); loading "
                  .. #unnamed .. " unnamed ones" .. (result.unnamedSkipped > 0
                  and (", skipping " .. result.unnamedSkipped .. " outside " .. SPELL_LOAD_FROM
                       .. ".." .. SPELL_LOAD_TO) or "") .. "...")
            return false
        end
        if not descs then
            -- Names that were not loaded: request under the frame budget,
            -- retry, and list the ones that never load.
            scans.progress = "names " .. (names.head - 1) .. " of " .. #names.ids
            if not Drain(names, function(id, try)
                if try > 1 and named(id) then return true end
                if try > SPELL_LOAD_TRIES then
                    result.hidden[#result.hidden + 1] = id
                    return true
                end
                C_Spell.RequestLoadSpellData(id)
                return false
            end) then return false end
            table.sort(result.hidden)
            descs = NewQueue(candidates)
            say(#candidates .. " spells named " .. WELL_FED .. "; loading their descriptions...")
            return false
        end
        -- Descriptions of the Well Fed spells.
        if not Drain(descs, function(id, try)
            local ok, desc = pcall(C_Spell.GetSpellDescription, id)
            if ok and desc and desc ~= "" then
                result.spells[id] = desc
                return true
            end
            if try >= DESC_TRIES then
                result.spells[id] = ""
                result.emptyDescription = result.emptyDescription + 1
                return true
            end
            C_Spell.RequestLoadSpellData(id)
            return false
        end) then return false end
        result.complete = result.unnamedSkipped == 0
        ProbeDB().wellFedScan = result
        ScanDone("wellfed", "Well Fed scan done (" .. (result.complete and "complete" or "INCOMPLETE")
              .. "): " .. #candidates .. " Well Fed spells, " .. result.emptyDescription
              .. " with an empty description; " .. result.exist .. " spells to " .. result.scannedTo
              .. "; names skipped " .. result.unnamedSkipped .. ", hidden " .. #result.hidden
              .. (#result.hidden > 0 and (" (" .. table.concat(result.hidden, ", ", 1,
                  math.min(#result.hidden, 20)) .. ")") or "")
              .. ". /reload to write the file.")
        return true
    end)
    return true
end

-- ============================================================
-- /fp apo applytest <itemID>: how a secure button applies a weapon coating
-- (poison, oil, stone) to a chosen hand (#24). Two methods, each hand:
--   A  type=item + "target-slot" 16/17 (Blizzard's SecureTemplates reads
--      it after the item use, upstream; not proven on Forever)
--   B  type=macro: "/use item:<id>" then "/use 16|17"
-- Every click is one attempt. It records both hands' weapons and enchant
-- state and the item count just before (PreClick), the targeting state
-- right after (PostClick), the cast / error / enchant / equipment events
-- in between, and both hands again once things settle. The verdict is
-- "applied" only if the INTENDED hand changed and the other did not
-- (Codex review of #24): a targeting cursor that went away proves nothing.
-- Values that could be secret are kept as "<secret>", never compared.
-- Out of combat only: the buttons are secure frames.
-- ============================================================
local APPLY_SETTLE  = 6      -- seconds after the click before the verdict
local APPLY_QUIET   = 2      -- ...and this long with no cursor, popup, cast or event
local APPLY_TIMEOUT = 45     -- give up
local SLOT_NAME = { [16] = "main hand", [17] = "off hand" }

local applyFrame, applyAttempt, applyEvents

-- A value safe to keep and compare: secrets become the string "<secret>".
local function plain(v)
    if issecretvalue and issecretvalue(v) then return "<secret>" end
    return v
end

-- Both hands' temporary enchant: has, time left (ms), charges, enchant ID.
local function EnchantState()
    local ok, r = pcall(function()
        local t = {}
        local v = { GetWeaponEnchantInfo() }
        t.raw = describe(GetWeaponEnchantInfo())
        t[16] = { has = plain(v[1]), exp = plain(v[2]), charges = plain(v[3]), id = plain(v[4]) }
        t[17] = { has = plain(v[5]), exp = plain(v[6]), charges = plain(v[7]), id = plain(v[8]) }
        return t
    end)
    if ok then return r end
    -- A failed read is unknown, never "no coating" (Codex review of #25).
    return { raw = "ERROR: " .. tostring(r), [16] = { unknown = true }, [17] = { unknown = true } }
end

local function Snapshot(itemID)
    local s = { t = GetTime(), enchant = EnchantState() }
    s.weapon = {}
    for _, slot in ipairs({ 16, 17 }) do
        local ok, id = pcall(GetInventoryItemID, "player", slot)
        -- Not `ok and plain(id) or "ERROR"`: an empty slot (nil) fell
        -- through to "ERROR" (70009 run).
        if ok then s.weapon[slot] = plain(id) or "empty" else s.weapon[slot] = "ERROR" end
    end
    local okC, n = pcall(C_Item.GetItemCount, itemID)
    if okC then s.count = plain(n) else s.count = "ERROR" end
    return s
end

-- What happened to one hand's coating between two snapshots, by direction
-- (Codex review of #25): "gained", "replaced" or "renewed" is an
-- application; "lost" (expired, charges used up) and "same" are not; nil
-- is unknown (a failed read, a secret, or a value missing to tell).
local function HandChange(a, b, elapsedMs)
    if a.unknown or b.unknown or a.has == "<secret>" or b.has == "<secret>" then return nil end
    local had, has = a.has and true or false, b.has and true or false
    if not had and has then return "gained" end
    if had and not has then return "lost" end
    if not has then return "same" end
    if a.id == "<secret>" or b.id == "<secret>" then return nil end
    if a.id ~= b.id then return "replaced" end
    -- Same coating: a fresh application renews the charges, or the time
    -- left beyond what the attempt's own duration took off it.
    if type(a.charges) == "number" and type(b.charges) == "number" and b.charges > a.charges then
        return "renewed"
    end
    if type(a.exp) == "number" and type(b.exp) == "number" then
        return (b.exp > a.exp - elapsedMs + 3000) and "renewed" or "same"
    end
    return nil
end
local APPLIED = { gained = true, replaced = true, renewed = true }

local function Verdict(att)
    local before, after = att.before.enchant, att.after.enchant
    local other = att.slot == 16 and 17 or 16
    local elapsedMs = 1000 * (att.after.t - att.before.t)
    local mine   = HandChange(before[att.slot], after[att.slot], elapsedMs)
    local theirs = HandChange(before[other], after[other], elapsedMs)
    att.change = { mine = mine or "unknown", other = theirs or "unknown" }
    local failed, completed = false, false
    for _, e in ipairs(att.events) do
        if e[2] == "ENCHANT_SPELL_COMPLETED" and e[3] == "true" then completed = true end
        if e[2]:find("FAILED") or e[2]:find("INTERRUPTED") or e[2] == "UI_ERROR_MESSAGE"
                or e[2]:find("ADDON_ACTION") then
            failed = true
        end
    end
    if att.weaponChanged then return "inconclusive (the weapons changed during the attempt)" end
    if APPLIED[theirs] then return "WRONG HAND (the other hand was coated)" end
    -- Applied only if the intended hand was coated AND the other hand is
    -- known not to have been (it may have expired meanwhile: "lost").
    if APPLIED[mine] and theirs then return "applied (" .. mine .. ")" end
    if APPLIED[mine] then return "inconclusive (applied, but the other hand is unreadable)" end
    if mine == nil then return "inconclusive (enchant state unreadable)" end
    -- Refreshing a coating that was still full changes nothing visible:
    -- the completion event is then the only evidence.
    if completed then return "inconclusive (completed, no visible change: was it still full?)" end
    return failed and "failed" or "failed (nothing changed)"
end

local function FinishAttempt(reason)
    local att = applyAttempt
    if not att then return end
    applyAttempt = nil
    att.after = Snapshot(att.item)
    att.targetingAtEnd = plain(SpellIsTargeting())
    for _, slot in ipairs({ 16, 17 }) do
        if att.after.weapon[slot] ~= att.before.weapon[slot] then att.weaponChanged = true end
    end
    att.ended = reason
    att.verdict = Verdict(att)
    local db = ProbeDB()
    db.applyTests = db.applyTests or {}
    db.applyTests[#db.applyTests + 1] = att
    local evs = {}
    for _, e in ipairs(att.events) do evs[#evs + 1] = e[2] end
    say("#" .. att.n .. " " .. att.method .. " " .. SLOT_NAME[att.slot] .. ": "
          .. att.verdict .. " [" .. (#evs > 0 and table.concat(evs, ", ") or "no events") .. "]"
          .. (att.popup and " (replace popup)" or "")
          .. (att.targetingAfterClick == true and " (cursor after click)" or ""))
    say("    before " .. att.before.enchant.raw)
    say("    after  " .. att.after.enchant.raw)
end

-- ADDON_ACTION_BLOCKED / FORBIDDEN reach an attempt through OnBlocked
-- (the host's watcher), not by registering them here.
local APPLY_EVENTS = {
    "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_FAILED",
    "UNIT_SPELLCAST_INTERRUPTED", "UI_ERROR_MESSAGE",
    "WEAPON_ENCHANT_CHANGED", "ENCHANT_SPELL_COMPLETED",
    "UNIT_INVENTORY_CHANGED", "PLAYER_EQUIPMENT_CHANGED",
}

-- What fired during the open attempt.
local function ApplyEvent(event, a1, a2, a3)
    local att = applyAttempt
    if not att then return end
    if (event:find("^UNIT_") and a1 ~= "player") then return end
    att.events[#att.events + 1] = { GetTime() - att.t0, event,
        tostring(plain(a1)), tostring(plain(a2)), tostring(plain(a3)) }
    att.lastActivity = GetTime()
    -- A weapon swapped out and back ends with the same item IDs, so
    -- the swap itself marks the attempt (Codex review of #25).
    if event == "PLAYER_EQUIPMENT_CHANGED" and (a1 == 16 or a1 == 17) then
        att.weaponChanged = true
    end
    -- The apply cast: no verdict while it runs.
    if event == "UNIT_SPELLCAST_START" then att.casting = true end
    if event == "UNIT_SPELLCAST_SUCCEEDED" or event == "UNIT_SPELLCAST_FAILED"
            or event == "UNIT_SPELLCAST_INTERRUPTED" then
        att.casting = false
    end
end
OnBlocked(ApplyEvent)

local attemptCount = 0

local function MakeButton(parent, method, slot, itemID, x, y)
    local b = CreateFrame("Button", nil, parent, "SecureActionButtonTemplate")
    b:SetSize(120, 26)
    b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    b:RegisterForClicks(Apotheca.API.ClickEdges())
    local label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("CENTER")
    label:SetText(method .. ": " .. SLOT_NAME[slot])
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.25, 0.1, 0.4, 0.9)
    b.method, b.slot = method, slot
    if method == "A" then
        b:SetAttribute("type", "item")
        b:SetAttribute("item", "item:" .. itemID)
        b:SetAttribute("target-slot", slot)
    else
        b:SetAttribute("type", "macro")
        b:SetAttribute("macrotext", "/use item:" .. itemID .. "\n/use " .. slot)
    end
    -- Observation only: no protected call from these insecure scripts.
    -- Both mouse edges are registered (Apotheca.API.ClickEdges), but the
    -- secure handler acts on one: down when ActionButtonUseKeyDown is 1
    -- (measured). Only that edge starts an attempt, so one click is one
    -- record (Codex review of #25).
    b:SetScript("PreClick", function(self, button, down)
        local keyDown = C_CVar and C_CVar.GetCVar("ActionButtonUseKeyDown") == "1"
        if (down and true or false) ~= (keyDown and true or false) then return end
        if applyAttempt then FinishAttempt("superseded by a new click") end
        attemptCount = attemptCount + 1
        applyAttempt = {
            n = attemptCount, method = self.method, slot = self.slot, item = itemID,
            button = button, down = down and true or false,
            combat = InCombatLockdown() and true or false,
            keyDown = C_CVar and C_CVar.GetCVar("ActionButtonUseKeyDown"),
            build = select(2, GetBuildInfo()),
            t0 = GetTime(), events = {}, before = Snapshot(itemID),
        }
    end)
    b:SetScript("PostClick", function(self, button, down)
        local att = applyAttempt
        if not att or att.method ~= self.method or att.slot ~= self.slot then return end
        if (down and true or false) ~= att.down then return end
        att.targetingAfterClick = plain(SpellIsTargeting())
        local okP, popup = pcall(StaticPopup_Visible, "REPLACE_ENCHANT")
        att.popup = okP and popup and true or nil
    end)
    return b
end

local function RunApplyTest(arg)
    arg = (arg or ""):lower()
    if arg == "close" then
        if InCombatLockdown() then say("out of combat only") return end
        if applyFrame then applyFrame:Hide() end
        FinishAttempt("closed")
        return
    end
    local itemID = tonumber(arg:match("^(%d+)"))
    if not itemID then
        say("usage: /fp apo applytest <itemID>  (a poison, oil or stone in your bags), /fp apo applytest close")
        return
    end
    if InCombatLockdown() then say("out of combat only: the test buttons are secure frames") return end
    if applyFrame then applyFrame:Hide() end

    local f = CreateFrame("Frame", nil, UIParent)
    applyFrame = f
    f:SetSize(270, 110)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 150)
    f:SetFrameStrata("DIALOG")
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.8)
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", f, "TOP", 0, -8)
    title:SetText("Apotheca apply test: " .. (C_Item.GetItemInfo(itemID) or ("item " .. itemID)))
    f.buttons = {
        A16 = MakeButton(f, "A", 16, itemID, 10, -30),
        A17 = MakeButton(f, "A", 17, itemID, 140, -30),
        B16 = MakeButton(f, "B", 16, itemID, 10, -64),
        B17 = MakeButton(f, "B", 17, itemID, 140, -64),
    }
    NS._test.applyFrame = f

    if not applyEvents then
        applyEvents = CreateFrame("Frame")
        Probe:RegisterEvents(applyEvents, APPLY_EVENTS)
        applyEvents:SetScript("OnEvent", function(_, event, a1, a2, a3) ApplyEvent(event, a1, a2, a3) end)
        applyEvents:SetScript("OnUpdate", function()
            local att = applyAttempt
            if not att then return end
            local age = GetTime() - att.t0
            local okT, targeting = pcall(SpellIsTargeting)
            local okP, popup = pcall(StaticPopup_Visible, "REPLACE_ENCHANT")
            if okP and popup then att.popup = true end
            -- Wait while the player still has to pick a weapon or answer
            -- the replace popup, and while the apply cast runs; then for a
            -- quiet spell, so a late pick or answer gets its cast in (Codex
            -- review of #25).
            local waiting = (okT and targeting == true) or (okP and popup and true) or att.casting
            if waiting then att.lastActivity = GetTime() end
            local quiet = GetTime() - (att.lastActivity or att.t0)
            if age >= APPLY_TIMEOUT then
                FinishAttempt("timeout")
            elseif age >= APPLY_SETTLE and not waiting and quiet >= APPLY_QUIET then
                FinishAttempt("settled")
            end
        end)
    end
    f:Show()
    say("apply test: click A or B for a hand, one at a time; wait for the verdict line. "
          .. "Results are kept for the SavedVariables file. /fp apo applytest close to hide.")
end

local probeBar   -- the StatusBar the health readback is tried on

local function RunProbe()
    log = {}
    local API = Apotheca.API

    out("build", describe(GetBuildInfo()))
    out("measuredOnBuild", API.MEASURED_ON_BUILD)
    out("inCombat", InCombatLockdown())
    try("CVar ActionButtonUseKeyDown", function() return C_CVar.GetCVar("ActionButtonUseKeyDown") end)
    try("CVar ActionButtonUseKeyHeldSpell", function() return C_CVar.GetCVar("ActionButtonUseKeyHeldSpell") end)

    -- Secrecy switches, and the values the bar reads during combat.
    try("C_Secrets.ShouldAurasBeSecret", function() return C_Secrets.ShouldAurasBeSecret() end)
    try("C_Secrets.ShouldCooldownsBeSecret", function() return C_Secrets.ShouldCooldownsBeSecret() end)
    try("C_Secrets.ShouldUnitHealthMaxBeSecret", function() return C_Secrets.ShouldUnitHealthMaxBeSecret("player") end)
    try("C_Secrets.ShouldUnitPowerBeSecret", function() return C_Secrets.ShouldUnitPowerBeSecret("player") end)
    try("UnitHealth/Max", function() return UnitHealth("player"), UnitHealthMax("player") end)
    try("UnitPower/Max", function() return UnitPower("player"), UnitPowerMax("player") end)
    try("UnitHealthMissing", function() return UnitHealthMissing("player") end)
    try("UnitPowerMissing", function() return UnitPowerMissing("player") end)
    try("UnitPower(Mana)", function() return UnitPower("player", Enum.PowerType.Mana) end)
    try("UnitHealthPercent", function() return UnitHealthPercent("player") end)
    try("UnitPowerPercent", function() return UnitPowerPercent("player") end)
    try("compare UnitHealthMissing == 0", function() return UnitHealthMissing("player") == 0 end)
    try("API.PlayerMissing", function() return API.PlayerMissing() end)
    -- Unit frame addons DISPLAY secret health by handing it to a widget.
    -- Does the widget hand back a plain number? If so, that is a readback.
    try("StatusBar readback of UnitHealth", function()
        local bar = probeBar or CreateFrame("StatusBar", nil, UIParent)
        probeBar = bar
        bar:Hide()
        bar:SetMinMaxValues(0, UnitHealthMax("player"))
        bar:SetValue(UnitHealth("player"))
        local v = bar:GetValue()
        return v, issecretvalue and issecretvalue(v)
    end)
    try("API.PlayerAuras is nil (blocked)", function() return API.PlayerAuras("HELPFUL") == nil end)
    try("GetWeaponEnchantInfo", function() return GetWeaponEnchantInfo() end)

    -- Every bar button with an item: cooldown shape and stack count.
    for key, btn in pairs(Apotheca.buttons or {}) do
        if btn.itemID then
            local id = btn.itemID
            try("cooldown " .. key .. " " .. id, function() return C_Container.GetItemCooldown(id) end)
            try("C_Item.GetItemCount " .. id, function() return C_Item.GetItemCount(id) end)
        end
    end
    try("first carried stack", function()
        for _, bag in ipairs(API.CarriedBags()) do
            for slot = 1, API.ContainerNumSlots(bag) do
                local info = C_Container.GetContainerItemInfo(bag, slot)
                if info then return bag, slot, info.itemID, info.stackCount end
            end
        end
    end)
    out("carriedBags", table.concat(API.CarriedBags(), ","))

    -- Using an item from insecure code (the waste popup's "Yes"). The name
    -- matches nothing, so nothing is used; a protected function is
    -- refused before it looks at its argument.
    blockedBy = nil
    try("C_Item.UseItemByName (bogus name)", function()
        return C_Item.UseItemByName("Apotheca Probe No Such Item")
    end)
    out("  -> blocked event", blockedBy or "none")

    -- Role sources (#9): the group-assigned role, and the game's own role
    -- selector (Tank / Healer / Damage), through each API that may hold it.
    local function fields(t)
        if type(t) ~= "table" then return tostring(t) end
        local parts = {}
        for k, v in pairs(t) do parts[#parts + 1] = tostring(k) .. "=" .. tostring(v) end
        table.sort(parts)
        return "{" .. table.concat(parts, ", ") .. "}"
    end
    try("IsInGroup / IsInRaid", function() return IsInGroup(), IsInRaid() end)
    try("UnitGroupRolesAssigned(player)", function() return UnitGroupRolesAssigned("player") end)
    try("GetLFGRoles", function() return GetLFGRoles() end)
    try("C_LFGListRoles.GetRoles", function() return fields(C_LFGListRoles.GetRoles()) end)
    try("C_LFGListRoles.GetSavedRoles", function() return fields(C_LFGListRoles.GetSavedRoles()) end)
    try("UnitPowerType / UnitPowerMax(Mana)", function()
        return UnitPowerType("player"), UnitPowerMax("player", Enum.PowerType.Mana)
    end)
    -- XP food (#19): the button hides at the level cap or with XP turned off.
    try("UnitLevel / GetMaxPlayerLevel", function() return UnitLevel("player"), GetMaxPlayerLevel() end)
    try("GetMaxLevelForPlayerExpansion", function() return GetMaxLevelForPlayerExpansion() end)
    try("IsXPUserDisabled", function() return IsXPUserDisabled() end)

    -- Weapons (#9 stones and poisons): main hand 16, off hand 17, with the
    -- item class and subclass that tell a blade from a blunt weapon.
    for _, slot in ipairs({ 16, 17 }) do
        try("weapon slot " .. slot, function()
            local id = GetInventoryItemID("player", slot)
            if not id then return "empty" end
            local _, itemType, subType, _, _, classID, subClassID = C_Item.GetItemInfoInstant(id)
            return id, itemType, subType, classID, subClassID
        end)
    end

    -- Talents (#9): points spent per tree would give the real spec. The
    -- Classic tab API is gone; try the two routes the dump offers.
    -- 1) C_SpecializationInfo.GetTalentInfo{ specializationIndex, talentIndex }
    --    returns rank / maxRank (Classic-shaped). Sum the ranks per tree.
    try("talents via GetTalentInfo (tree: talents found, points)", function()
        local out = {}
        for tree = 1, 4 do
            local found, points, names = 0, 0, {}
            for i = 1, 40 do
                local ok, r = pcall(C_SpecializationInfo.GetTalentInfo,
                    { specializationIndex = tree, talentIndex = i })
                if ok and type(r) == "table" and r.name then
                    found = found + 1
                    points = points + (tonumber(r.rank) or 0)
                    if #names < 2 then names[#names + 1] = tostring(r.name) end
                end
            end
            out[#out + 1] = tree .. ":" .. found .. "/" .. points .. "(" .. table.concat(names, ",") .. ")"
        end
        return table.concat(out, "  ")
    end)
    try("talents via GetTalentInfo tier/column (tree 1)", function()
        local ok, r = pcall(C_SpecializationInfo.GetTalentInfo, { specializationIndex = 1, tier = 1, column = 1 })
        return ok, type(r) == "table" and (tostring(r.name) .. " rank " .. tostring(r.rank) .. "/" .. tostring(r.maxRank)) or tostring(r)
    end)
    -- 2) C_ClassTalents / C_Traits: the active config's trees and the points
    --    spent in each.
    try("talents via C_Traits (config, trees, spent)", function()
        local configID = C_ClassTalents.GetActiveConfigID()
        if not configID then return "no active config" end
        local info = C_Traits.GetConfigInfo(configID)
        local parts = { "config " .. configID }
        for _, treeID in ipairs(info and info.treeIDs or {}) do
            local cur = C_Traits.GetTreeCurrencyInfo(configID, treeID, false) or {}
            local spent = {}
            for _, c in ipairs(cur) do
                spent[#spent + 1] = tostring(c.traitCurrencyID) .. ":" .. tostring(c.spent)
                    .. "/" .. tostring(c.spentInTree)
            end
            parts[#parts + 1] = "tree " .. treeID .. " [" .. table.concat(spent, " ") .. "]"
        end
        return table.concat(parts, "  ")
    end)
    -- 3) Forever keeps all three Vanilla trees in ONE trait tree. Walk its
    --    nodes and group the points spent by every field that could name
    --    the Vanilla tree: subTreeID (with its name), groupIDs, and posX.
    try("talent nodes (count, with points)", function()
        local configID = C_ClassTalents.GetActiveConfigID()
        local treeID = C_Traits.GetConfigInfo(configID).treeIDs[1]
        local nodes = C_Traits.GetTreeNodes(treeID)
        local withPoints = 0
        for _, nodeID in ipairs(nodes) do
            local n = C_Traits.GetNodeInfo(configID, nodeID)
            if n and (n.ranksPurchased or 0) > 0 then withPoints = withPoints + 1 end
        end
        return #nodes, withPoints
    end)
    try("talent points by subTree / group / posX", function()
        local configID = C_ClassTalents.GetActiveConfigID()
        local treeID = C_Traits.GetConfigInfo(configID).treeIDs[1]
        local bySub, byGroup, byX, subNames = {}, {}, {}, {}
        local minX, maxX = math.huge, -math.huge
        for _, nodeID in ipairs(C_Traits.GetTreeNodes(treeID)) do
            local n = C_Traits.GetNodeInfo(configID, nodeID)
            if n and n.isVisible then
                if n.posX < minX then minX = n.posX end
                if n.posX > maxX then maxX = n.posX end
                local pts = n.ranksPurchased or 0
                local sub = tostring(n.subTreeID)
                bySub[sub] = (bySub[sub] or 0) + pts
                if n.subTreeID and not subNames[sub] then
                    local ok, st = pcall(C_Traits.GetSubTreeInfo, configID, n.subTreeID)
                    subNames[sub] = ok and st and tostring(st.name) or "?"
                end
                local g = tostring(n.groupIDs and n.groupIDs[1])
                byGroup[g] = (byGroup[g] or 0) + pts
                local x = tostring(math.floor(n.posX / 1000))
                byX[x] = (byX[x] or 0) + pts
            end
        end
        local function fmt(t, names)
            local out = {}
            for k, v in pairs(t) do out[#out + 1] = k .. (names and names[k] and ("(" .. names[k] .. ")") or "") .. "=" .. v end
            table.sort(out)
            return table.concat(out, " ")
        end
        return "sub{" .. fmt(bySub, subNames) .. "} group{" .. fmt(byGroup) .. "} posX/1000{"
            .. fmt(byX) .. "} x range " .. minX .. ".." .. maxX
    end)
    try("purchased talents (spell @ posX,posY)", function()
        local configID = C_ClassTalents.GetActiveConfigID()
        local treeID = C_Traits.GetConfigInfo(configID).treeIDs[1]
        local out = {}
        for _, nodeID in ipairs(C_Traits.GetTreeNodes(treeID)) do
            local n = C_Traits.GetNodeInfo(configID, nodeID)
            if n and (n.ranksPurchased or 0) > 0 then
                local name = "?"
                local entryID = n.activeEntry and n.activeEntry.entryID or (n.entryIDs and n.entryIDs[1])
                if entryID then
                    local e = C_Traits.GetEntryInfo(configID, entryID)
                    local d = e and e.definitionID and C_Traits.GetDefinitionInfo(e.definitionID)
                    if d and d.spellID then name = tostring(C_Spell.GetSpellName(d.spellID)) end
                end
                out[#out + 1] = name .. "x" .. n.ranksPurchased .. "@" .. n.posX .. "," .. n.posY
            end
        end
        return table.concat(out, "; ")
    end)
    try("UnitCharacterPoints / GetUnspentTalentPoints", function()
        local a = UnitCharacterPoints and UnitCharacterPoints("player")
        local b = GetUnspentTalentPoints and GetUnspentTalentPoints()
        return a, b
    end)

    -- Spec detection candidates. The talent-tab API is gone.
    try("C_SpecializationInfo.GetSpecialization", function() return C_SpecializationInfo.GetSpecialization() end)
    try("C_SpecializationInfo.GetSpecializationInfo(1)", function() return C_SpecializationInfo.GetSpecializationInfo(1) end)
    try("C_SpecializationInfo.GetNumSpecializationsForClassID", function()
        local _, _, classID = UnitClass("player")
        return C_SpecializationInfo.GetNumSpecializationsForClassID(classID)
    end)

    -- Templates the options panel and bar use. A missing template does not
    -- throw here, so check for a region the template should bring.
    for i, t in ipairs(TEMPLATES) do
        try("template " .. t[2], function()
            local name = "ApothecaProbeTemplate" .. i
            local f = _G[name] or CreateFrame(t[1], name, UIParent, t[2])
            f:Hide()
            if not t[3] then return "created" end
            return (f[t[3]] or _G[name .. t[3]]) and "applied" or "BARE FRAME"
        end)
    end
    out("GameTooltip.SetItemByID", type(GameTooltip.SetItemByID))
    out("AnimateTexCoords", type(AnimateTexCoords))

    -- Aura list with spell IDs: drink a flask and several elixirs, run
    -- the probe, and see which stayed (Vanilla stacking, issue #4).
    try("player auras", function()
        local rows = {}
        local i = 1
        while true do
            local a = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
            if not a then break end
            rows[#rows + 1] = tostring(a.name) .. "#" .. tostring(a.spellId)
            i = i + 1
        end
        return #rows > 0 and table.concat(rows, "; ") or "none"
    end)

    local db = ProbeDB()
    local mode = InCombatLockdown() and "combat" or "idle"
    db.lastProbe = db.lastProbe or {}
    db.lastProbe[mode] = log
    say("done. Kept as lastProbe." .. mode .. " for the SavedVariables file on /reload or logout.")
    return "lastProbe." .. mode .. ": " .. #log .. " lines"
end

-- ============================================================
-- /fp apo bar [label]: Action Bar 1's layout (#40)
--
-- "Match Action Bar 1" needs the bar's icon size, padding, rows and
-- orientation. Two sources: the Edit Mode layout (C_EditMode and the bar
-- system frame's GetSettingValue), whose encoding on Forever is unmeasured,
-- and the live buttons (ActionButton1 / ActionButton2 geometry). Run it
-- with a few settings changed in Edit Mode (icon size, padding, rows,
-- orientation, a preset layout and a custom one), giving each run a label;
-- every run is kept under ApothecaProbeDB.barProbe[label].
-- ============================================================

local function EnumDump(name)
    local e = Enum and Enum[name]
    if type(e) ~= "table" then return "absent" end
    local keys = {}
    for k, v in pairs(e) do keys[#keys + 1] = tostring(k) .. "=" .. tostring(v) end
    table.sort(keys)
    return table.concat(keys, ", ")
end

local function Geometry(f)
    if not f then return "absent" end
    local l, b, w, h = f:GetRect()
    return string.format("shown=%s size=%.2fx%.2f scale=%.3f eff=%.3f rect=%s,%s",
        tostring(f:IsShown()), f:GetWidth(), f:GetHeight(), f:GetScale(), f:GetEffectiveScale(),
        tostring(l and math.floor(l * 100 + 0.5) / 100), tostring(b and math.floor(b * 100 + 0.5) / 100))
end

-- The pixel gap between two buttons in UIParent units, horizontal and vertical.
local function Gap(a, b)
    if not (a and b) then return "absent" end
    local al, ab, aw, ah = a:GetRect()
    local bl, bb = b:GetRect()
    if not (al and bl) then return "no rect" end
    local s = a:GetEffectiveScale() / UIParent:GetEffectiveScale()
    return string.format("dx=%.2f dy=%.2f (button %.2f, in UIParent units: scale %.3f)",
        (bl - al - aw) * s, (ab - bb - ah) * s, aw * s, s)
end

-- Labels are lowercased, as the old /apo command did, so a run keeps the
-- key earlier runs were saved under.
local function RunLabel(label)
    label = label and label:lower():match("^%s*(.-)%s*$") or ""
    return label ~= "" and label or "default"
end

local function RunBarProbe(label)
    label = RunLabel(label)
    log = {}
    say("Action Bar 1 layout, run '" .. label .. "'")

    try("build", function() return select(4, GetBuildInfo()), (select(2, GetBuildInfo())) end)
    try("UIParent", function() return Geometry(UIParent) end)
    try("Enum.EditModeSystem", function() return EnumDump("EditModeSystem") end)
    try("Enum.EditModeActionBarSystemIndices", function() return EnumDump("EditModeActionBarSystemIndices") end)
    try("Enum.EditModeActionBarSetting", function() return EnumDump("EditModeActionBarSetting") end)
    try("Enum.ActionBarOrientation", function() return EnumDump("ActionBarOrientation") end)

    -- The layouts as stored. Presets (Modern, Classic) are not in .layouts
    -- on Retail: activeLayout counts the presets first.
    try("C_EditMode.GetLayouts", function()
        local info = C_EditMode.GetLayouts()
        return "activeLayout=" .. tostring(info and info.activeLayout)
            .. " custom=" .. tostring(info and info.layouts and #info.layouts)
    end)
    try("activeLayoutSettings", function()
        local info = C_EditMode.GetLayouts()
        local presets = EditModePresetLayoutManager and EditModePresetLayoutManager.GetCopyOfPresetLayouts
            and EditModePresetLayoutManager:GetCopyOfPresetLayouts() or {}
        local all = {}
        for _, l in ipairs(presets) do all[#all + 1] = l end
        for _, l in ipairs(info.layouts or {}) do all[#all + 1] = l end
        local layout = all[info.activeLayout]
        if not layout then return "no layout at index " .. tostring(info.activeLayout) .. " of " .. #all end
        local sysEnum = Enum.EditModeSystem and Enum.EditModeSystem.ActionBar
        local mainIdx = Enum.EditModeActionBarSystemIndices and Enum.EditModeActionBarSystemIndices.MainBar
        for _, sys in ipairs(layout.systems or {}) do
            if sys.system == sysEnum and sys.systemIndex == mainIdx then
                local parts = { "name=" .. tostring(layout.layoutName), "type=" .. tostring(layout.layoutType) }
                for _, s in ipairs(sys.settings or {}) do
                    parts[#parts + 1] = tostring(s.setting) .. ":" .. tostring(s.value)
                end
                local a = sys.anchorInfo
                if a then
                    parts[#parts + 1] = "anchor=" .. tostring(a.point) .. "/" .. tostring(a.relativeTo)
                        .. "/" .. tostring(a.relativePoint) .. " " .. tostring(a.offsetX) .. "," .. tostring(a.offsetY)
                end
                return table.concat(parts, " ")
            end
        end
        return "MainBar system not found in layout " .. tostring(layout.layoutName)
    end)

    -- The live bar frame. Retail renamed MainMenuBar to MainActionBar (11.1).
    for _, name in ipairs({ "MainActionBar", "MainMenuBar" }) do
        local bar = _G[name]
        try(name, function() return Geometry(bar) end)
        if bar then
            try(name .. ".fields", function()
                return "isHorizontal=" .. tostring(bar.isHorizontal) .. " numRows=" .. tostring(bar.numRows)
                    .. " numButtonsShowable=" .. tostring(bar.numButtonsShowable)
                    .. " buttonPadding=" .. tostring(bar.buttonPadding)
                    .. " system=" .. tostring(bar.system) .. " systemIndex=" .. tostring(bar.systemIndex)
            end)
            if bar.GetSettingValue and Enum.EditModeActionBarSetting then
                for sName, sID in pairs(Enum.EditModeActionBarSetting) do
                    try(name .. ":GetSettingValue(" .. sName .. ")", function()
                        return bar:GetSettingValue(sID)
                    end)
                end
            end
        end
    end
    try("EditModeManagerFrame:GetActiveLayoutInfo", function()
        local l = EditModeManagerFrame:GetActiveLayoutInfo()
        return tostring(l and l.layoutName) .. " type=" .. tostring(l and l.layoutType)
    end)

    for i = 1, 3 do
        try("ActionButton" .. i, function() return Geometry(_G["ActionButton" .. i]) end)
    end
    try("ActionButton1.icon", function() return Geometry(ActionButton1 and ActionButton1.icon) end)
    try("ActionButton1.NormalTexture", function()
        local t = ActionButton1:GetNormalTexture()
        return t and (tostring(t:GetTexture()) .. " atlas=" .. tostring(t:GetAtlas()) .. " " .. Geometry(t)) or "none"
    end)
    try("ActionButton1.IconMask", function() return tostring(ActionButton1.IconMask ~= nil) end)
    try("gap 1->2", function() return Gap(ActionButton1, ActionButton2) end)
    -- Second row, if the bar has one: the first button below button 1.
    try("gap 1->7 (row 2 at 6 per row)", function() return Gap(ActionButton1, ActionButton7) end)
    try("gap 1->5 (row 2 at 4 per row)", function() return Gap(ActionButton1, ActionButton5) end)

    -- Every action bar Apotheca can match: the frame and first button
    -- names in Apotheca.API.ACTION_BARS are Retail's, unmeasured past bar 1.
    for i, names in ipairs(Apotheca.API and Apotheca.API.ACTION_BARS or {}) do
        try("bar " .. i, function()
            local bar, button = _G[names.bar], _G[names.button]
            if not bar then return names.bar .. " absent" end
            local s = Enum.EditModeActionBarSetting
            local size, pad
            if bar.GetSettingValue then
                size, pad = bar:GetSettingValue(s.IconSize), bar:GetSettingValue(s.IconPadding)
            end
            local w = button and button:GetWidth() * button:GetEffectiveScale() / UIParent:GetEffectiveScale()
            return string.format("%s shown=%s size=%s pad=%s %s=%s width=%s layout=%s",
                names.bar, tostring(bar:IsShown()), tostring(size), tostring(pad), names.button,
                tostring(button and button:GetWidth()), w and string.format("%.2f", w) or "absent",
                (function()
                    local l = Apotheca.API.ActionBarLayout(i)
                    return l and string.format("%.2f/%.2f", l.size, l.padding) or "nil"
                end)())
        end)
    end

    -- One line to read off the chat, and when: the saved file can't tell a
    -- rerun from a run that never happened.
    try("summary", function()
        local bar, s = MainActionBar, Enum.EditModeActionBarSetting
        local w = ActionButton1:GetWidth() * ActionButton1:GetEffectiveScale() / UIParent:GetEffectiveScale()
        return string.format("%s size=%s pad=%s rows=%s orient=%s editMode=%s button=%.2f",
            date("%H:%M:%S"), tostring(bar:GetSettingValue(s.IconSize)), tostring(bar:GetSettingValue(s.IconPadding)),
            tostring(bar:GetSettingValue(s.NumRows)), tostring(bar:GetSettingValue(s.Orientation)),
            tostring(EditModeManagerFrame and EditModeManagerFrame:IsShown()), w)
    end)

    local db = ProbeDB()
    db.barProbe = db.barProbe or {}
    db.barProbe[label] = log
    say("done. Kept as barProbe['" .. label .. "'] for the SavedVariables file on logout.")
end

-- ============================================================
-- /fp apo prof, /fp apo proftest: professions (#42)
--
-- GetProfessions() returns nil x7 on Forever and the Professions
-- subsystem is inert (porting guide), so the profession bar will detect
-- professions from spell IDs. This measures, for a draft catalog of
-- Vanilla spell IDs, which ones the client knows and by which API, every
-- entry of the spellbook and the skill list (to find spells the catalog
-- misses), and, with /fp apo proftest, what each spell does from a secure
-- button by mouse and by key: window, cast, cursor, tracking, refusal.
-- ============================================================

-- The draft catalog, highest rank first. Only what /fp apo prof confirms
-- goes into ApothecaUtility.lua. noButton: measured for context only.
local PROF_CATALOG = {
    { key = "alchemy",        ids = { 11611, 3464, 3101, 2259 } },
    { key = "blacksmithing",  ids = { 9785, 3538, 3100, 2018 } },
    { key = "enchanting",     ids = { 13920, 7413, 7412, 7411 } },
    { key = "engineering",    ids = { 12656, 4038, 4037, 4036 } },
    { key = "leatherworking", ids = { 10662, 3811, 3104, 2108 } },
    { key = "tailoring",      ids = { 12180, 3910, 3909, 3908 } },
    { key = "cooking",        ids = { 18260, 3413, 3102, 2550 } },
    { key = "firstaid",       ids = { 10846, 7924, 3274, 3273 } },
    { key = "smelting",       ids = { 2656 } },
    { key = "poisons",        ids = { 2842 } },
    { key = "fishing",        ids = { 18248, 7732, 7731, 7620 } },
    { key = "disenchant",     ids = { 13262 } },
    { key = "findherbs",      ids = { 2383 } },
    { key = "findminerals",   ids = { 2580 } },
    { key = "picklock",       ids = { 1804 } },
    { key = "mining",         ids = { 10248, 3564, 2576, 2575 }, noButton = true },
    { key = "herbalism",      ids = { 11993, 3570, 2368, 2366 }, noButton = true },
    { key = "skinning",       ids = { 10768, 8618, 8617, 8613 }, noButton = true },
}
NS._test.PROF_CATALOG = PROF_CATALOG
local HEARTHSTONE = 6948

-- A table's fields, sorted, secrets kept unread.
local function fields(t)
    if type(t) ~= "table" then return describe(t) end
    local keys = {}
    for k in pairs(t) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local parts = {}
    for _, k in ipairs(keys) do parts[#parts + 1] = tostring(k) .. "=" .. tostring(plain(t[k])) end
    return "{" .. table.concat(parts, " ") .. "}"
end

local function PlayerBank()
    return Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player
end

-- The first candidate the client says is known, by C_SpellBook.IsSpellKnown.
local function KnownRank(entry)
    for _, id in ipairs(entry.ids) do
        local ok, known = pcall(C_SpellBook.IsSpellKnown, id)
        if ok and known == true then return id end
    end
end

local function RunProfProbe(label)
    label = RunLabel(label)
    log = {}
    say("professions, run '" .. label .. "'")
    try("build", function() return select(4, GetBuildInfo()), (select(2, GetBuildInfo())) end)
    try("class, level, combat", function()
        return select(2, UnitClass("player")), UnitLevel("player"), InCombatLockdown()
    end)
    -- Measured nil x7 before; recorded again so a change shows.
    try("GetProfessions", function() return GetProfessions() end)

    -- Every candidate, by every API that could answer.
    local bank = PlayerBank()
    for _, entry in ipairs(PROF_CATALOG) do
        for _, id in ipairs(entry.ids) do
            local k = entry.key .. " " .. id
            try(k .. " name", function()
                return C_Spell.GetSpellName(id), C_Spell.GetSpellSubtext(id)
            end)
            try(k .. " known", function()
                return "C_SpellBook.IsSpellKnown=" .. describe(C_SpellBook.IsSpellKnown(id))
                    .. " IsSpellKnown=" .. describe(IsSpellKnown(id))
                    .. " IsPlayerSpell=" .. describe(IsPlayerSpell(id))
                    .. " InSpellBook=" .. describe(C_SpellBook.IsSpellInSpellBook(id))
            end)
            try(k .. " slot", function()
                local slot, b = C_SpellBook.FindSpellBookSlotForSpell(id)
                if not slot then return "no slot" end
                return "slot=" .. tostring(slot) .. " bank=" .. tostring(b) .. " "
                    .. fields(C_SpellBook.GetSpellBookItemInfo(slot, b or bank))
            end)
        end
        try(entry.key .. " rank in use", function() return KnownRank(entry) or "none known" end)
    end

    -- GetProfessions answers on 70334 (nil x7 on 70009): skill line
    -- indices past the visible ones. GetProfessionInfo for each.
    local okP, profs = pcall(function() return { GetProfessions() } end)
    for i = 1, 7 do
        local idx = okP and profs[i]
        if idx then
            try("GetProfessionInfo(" .. tostring(plain(idx)) .. ")", function() return GetProfessionInfo(idx) end)
        end
    end

    -- The whole player spellbook, line by line: spells the catalog misses.
    -- Profession lines sit past GetNumSpellBookSkillLines (lines 5-9 on
    -- 70334), so walk on until a line answers nothing.
    try("spellbook lines", function() return C_SpellBook.GetNumSpellBookSkillLines() end)
    for line = 1, 20 do
        local okL, info = pcall(C_SpellBook.GetSpellBookSkillLineInfo, line)
        if not (okL and type(info) == "table") then
            try("line " .. line, function() return okL and describe(info) or ("ERROR: " .. tostring(info)) end)
            break
        end
        try("line " .. line, function() return fields(info) end)
        local first = (info.itemIndexOffset or 0) + 1
        for slot = first, first + (info.numSpellBookItems or 0) - 1 do
            try("line " .. line .. " slot " .. slot, function()
                return fields(C_SpellBook.GetSpellBookItemInfo(slot, bank))
            end)
        end
    end

    -- The skill list, collapsed headers included: a collapsed header must
    -- not read as "no profession". Nothing is expanded.
    try("skill lines", function() return C_SkillInfo.GetNumSkillLines() end)
    local okS, nSkills = pcall(C_SkillInfo.GetNumSkillLines)
    for i = 1, (okS and tonumber(nSkills) or 0) do
        try("skill " .. i, function() return fields(C_SkillInfo.GetSkillLineInfo(i)) end)
    end

    -- Cooldowns: is a spell's or the Hearthstone's cooldown secret (run
    -- this in combat too)?
    for _, entry in ipairs(PROF_CATALOG) do
        if entry.key == "disenchant" or entry.key == "smelting" or entry.key == "fishing" then
            local id = KnownRank(entry)
            if id then
                try(entry.key .. " cooldown", function() return fields(C_Spell.GetSpellCooldown(id)) end)
            end
        end
    end
    try("hearthstone count", function() return C_Item.GetItemCount(HEARTHSTONE) end)
    try("hearthstone cooldown", function() return C_Container.GetItemCooldown(HEARTHSTONE) end)
    try("hearthstone spell", function() return C_Item.GetItemSpell(HEARTHSTONE) end)

    local db = ProbeDB()
    db.profProbe = db.profProbe or {}
    db.profProbe[label] = log
    say("done. Kept as profProbe['" .. label .. "'] for the SavedVariables file on logout.")
    return "profProbe." .. label .. ": " .. #log .. " lines"
end

-- Always on: what fires when a profession or a rank is learned or
-- unlearned, and whether the catalog is known yet at login and at
-- entering the world (when the bar can first be built). Capped.
local PROF_EVENT_CAP = 300

local function KnownList()
    local now = {}
    for _, entry in ipairs(PROF_CATALOG) do
        local ok, id = pcall(KnownRank, entry)
        if ok and id then now[#now + 1] = entry.key .. ":" .. id end
    end
    return now
end

local learnFrame = CreateFrame("Frame")
Probe:RegisterEvents(learnFrame, { "SKILL_LINES_CHANGED", "LEARNED_SPELL_IN_SKILL_LINE", "SPELLS_CHANGED",
                                   "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD" })
learnFrame:SetScript("OnEvent", function(_, event, a1, a2)
    -- Nothing saved before our ADDON_LOADED: it would be replaced.
    if not Probe.log then return end
    local db = ProbeDB()
    if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
        db.profLoad = db.profLoad or {}
        db.profLoad[event] = date("%H:%M:%S") .. " " .. table.concat(KnownList(), ",")
        return
    end
    db.profEvents = db.profEvents or {}
    local list = db.profEvents
    if #list >= PROF_EVENT_CAP then table.remove(list, 1) end
    -- The known catalog after each event: which event a learned rank shows on.
    list[#list + 1] = string.format("%s %s %s %s | %s", date("%H:%M:%S"), event,
        tostring(plain(a1)), tostring(plain(a2)), table.concat(KnownList(), ","))
end)

-- /fp apo proftest: one secure button per known family (its rank in use)
-- and the Hearthstone, each bound to CTRL-SHIFT-<n> by an override CLICK
-- binding. A press with the cursor off the frame is recorded as "key",
-- a click as "mouse". Each attempt ends once things settle, and records
-- what happened: casts, a profession window, a targeting cursor, a
-- tracking change, an error or a blocked action.
local PROF_KEYS = { "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "F1", "F2", "F3", "F4", "F5", "F6" }
local PROF_SETTLE, PROF_QUIET, PROF_TIMEOUT = 2, 1.5, 30
local PROF_TEST_EVENTS = {
    "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_SUCCEEDED",
    "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_CHANNEL_START",
    "UNIT_SPELLCAST_CHANNEL_STOP", "UI_ERROR_MESSAGE",
    "TRADE_SKILL_SHOW", "TRADE_SKILL_CLOSE", "CRAFT_SHOW",
    "CRAFT_CLOSE", "MINIMAP_UPDATE_TRACKING",
}   -- ADDON_ACTION_BLOCKED / FORBIDDEN come through OnBlocked (the host's watcher)
local profFrame, profAttempt, profEvents
local profCount = 0
-- The key watcher (WatchKeys, below); FinishProfAttempt reads it.
local keyWatch

local function FinishProfAttempt(reason)
    local att = profAttempt
    if not att then return end
    profAttempt = nil
    att.ended = reason
    local seen, sent = {}, 0
    for _, e in ipairs(att.events) do
        seen[e[2]] = true
        if e[2] == "UNIT_SPELLCAST_SENT" then sent = sent + 1 end
    end
    local what = {}
    if seen.ADDON_ACTION_BLOCKED or seen.ADDON_ACTION_FORBIDDEN then what[#what + 1] = "BLOCKED" end
    if seen.TRADE_SKILL_SHOW or seen.CRAFT_SHOW then what[#what + 1] = "window" end
    if att.cursor then what[#what + 1] = "cursor" end
    if seen.UNIT_SPELLCAST_CHANNEL_START then what[#what + 1] = "channel" end
    if seen.MINIMAP_UPDATE_TRACKING then what[#what + 1] = "tracking" end
    if seen.UNIT_SPELLCAST_SUCCEEDED then what[#what + 1] = "succeeded" end
    if seen.UI_ERROR_MESSAGE then what[#what + 1] = "error" end
    if #what == 0 then what[1] = "nothing" end
    att.casts = sent
    att.verdict = table.concat(what, "+") .. " (" .. sent .. " cast" .. (sent == 1 and "" or "s") .. ")"
    local db = ProbeDB()
    db.profTests = db.profTests or {}
    db.profTests[#db.profTests + 1] = att
    local evs = {}
    for _, e in ipairs(att.events) do
        evs[#evs + 1] = e[2] .. (e[2] == "UI_ERROR_MESSAGE" and (":" .. e[4]) or "")
    end
    if att.via == "mouse" and not (keyWatch and keyWatch.pressed) then
        say("reminder: press the CTRL-SHIFT keys too, with the cursor off the panel")
    end
    say("#" .. att.n .. " " .. att.key .. " by " .. att.via
          .. (att.combat and " in combat" or "") .. (att.hidden and " (hidden)" or "")
          .. " (keydown " .. tostring(att.keyDown) .. "): "
          .. att.verdict .. " [" .. (#evs > 0 and table.concat(evs, ", ") or "no events") .. "]")
end

-- A CTRL-SHIFT key press, seen by a frame that passes every key on. If
-- its button's PreClick doesn't follow within a second, the binding never
-- reached the button: recorded as SILENT.
local function WatchKeys(byKey)
    if not keyWatch then
        keyWatch = CreateFrame("Frame", nil, UIParent)
        keyWatch:EnableKeyboard(true)
        keyWatch:SetPropagateKeyboardInput(true)
        keyWatch:SetScript("OnKeyDown", function(self, key)
            if not (IsControlKeyDown() and IsShiftKeyDown()) then return end
            local target = self.byKey and self.byKey[key]
            if not target then return end
            self.pressed = true
            self.pending = { key = target, bind = "CTRL-SHIFT-" .. key, t = GetTime(),
                             combat = InCombatLockdown() and true or false, n = profCount }
        end)
        keyWatch:SetScript("OnUpdate", function(self)
            local p = self.pending
            if not p or GetTime() - p.t < 1 then return end
            self.pending = nil
            -- A press that reached its button started an attempt.
            if profCount ~= p.n then return end
            local db = ProbeDB()
            db.profTests = db.profTests or {}
            db.profTests[#db.profTests + 1] = { key = p.key, via = "key", combat = p.combat,
                keyDown = C_CVar and C_CVar.GetCVar("ActionButtonUseKeyDown"),
                hidden = not (profFrame and profFrame:IsShown()), events = {},
                verdict = "SILENT: " .. p.bind .. " never reached the button",
                build = select(2, GetBuildInfo()) }
            say(p.key .. " by key (" .. p.bind .. "): SILENT, the button never got the press")
        end)
    end
    keyWatch.byKey = byKey
    keyWatch:Show()
end

local function ProfButton(parent, i, key, kind, value)
    local b = CreateFrame("Button", "ApothecaProbeProf_" .. key, parent, "SecureActionButtonTemplate")
    b:SetSize(170, 22)
    b:SetPoint("TOPLEFT", parent, "TOPLEFT", 10 + ((i - 1) % 2) * 180, -30 - math.floor((i - 1) / 2) * 26)
    b:RegisterForClicks(Apotheca.API.ClickEdges())
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.25, 0.1, 0.4, 0.9)
    local label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("CENTER")
    local bind = PROF_KEYS[i] and ("CTRL-SHIFT-" .. PROF_KEYS[i])
    label:SetText(key .. " " .. value .. (bind and ("  [" .. bind .. "]") or ""))
    b:SetAttribute("type", kind)
    b:SetAttribute(kind, kind == "item" and ("item:" .. value) or value)
    if bind then SetOverrideBindingClick(parent, true, bind, b:GetName(), "LeftButton") end
    b.key, b.bind, b.keyName = key, bind, PROF_KEYS[i]
    -- Observation only. Both edges are registered; the secure handler acts
    -- on one (down when ActionButtonUseKeyDown is 1), so only that edge
    -- starts an attempt. A second acting edge from one press shows as a
    -- superseded attempt.
    b:SetScript("PreClick", function(self, button, down)
        local keyDown = C_CVar and C_CVar.GetCVar("ActionButtonUseKeyDown") == "1"
        if (down and true or false) ~= (keyDown and true or false) then return end
        if profAttempt then FinishProfAttempt("superseded by a new press") end
        profCount = profCount + 1
        profAttempt = {
            n = profCount, key = self.key, value = value, button = button,
            via = self:IsMouseOver() and "mouse" or "key",
            down = down and true or false, combat = InCombatLockdown() and true or false,
            keyDown = C_CVar and C_CVar.GetCVar("ActionButtonUseKeyDown"),
            hidden = not parent:IsShown(),
            build = select(2, GetBuildInfo()), t0 = GetTime(), events = {},
        }
    end)
    b:SetScript("PostClick", function(self, button, down)
        local att = profAttempt
        if att and att.key == self.key and (down and true or false) == att.down
                and plain(SpellIsTargeting()) == true then
            att.cursor = true
        end
    end)
    return b
end

-- What fired during the open attempt.
local function ProfEvent(event, a1, a2, a3, a4)
    local att = profAttempt
    if not att then return end
    if event:find("^UNIT_") and a1 ~= "player" then return end
    att.events[#att.events + 1] = { GetTime() - att.t0, event,
        tostring(plain(a1)), tostring(plain(a2)), tostring(plain(a3)), tostring(plain(a4)) }
    att.lastActivity = GetTime()
end
OnBlocked(ProfEvent)

local function RunProfTest(arg)
    arg = (arg or ""):lower():match("^%s*(.-)%s*$")
    if InCombatLockdown() then
        say("out of combat only: the test buttons and their bindings are secure")
        return
    end
    if arg == "close" then
        if profFrame then ClearOverrideBindings(profFrame) ; profFrame:Hide() end
        if keyWatch then keyWatch:Hide() end
        FinishProfAttempt("closed")
        return
    end
    -- Hidden, the bindings stay: does a CLICK binding act on a hidden button?
    if arg == "hide" then if profFrame then profFrame:Hide() end return end
    if arg == "show" then
        if profFrame then
            profFrame:Show()
            if keyWatch then keyWatch:Show() end
            -- Close cleared the bindings: show binds them again.
            for _, b in pairs(profFrame.buttons) do
                if b.bind then SetOverrideBindingClick(profFrame, true, b.bind, b:GetName(), "LeftButton") end
            end
        end
        return
    end
    -- Button names are global: built once, then shown again.
    if profFrame then
        say("already built this session: /fp apo proftest show (after a /reload for newly learned spells)")
        return
    end

    local f = CreateFrame("Frame", nil, UIParent)
    profFrame = f
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 150)
    f:SetFrameStrata("DIALOG")
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.8)
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", f, "TOP", 0, -8)
    title:SetText("Apotheca profession test")
    f.buttons = {}
    local i = 0
    for _, entry in ipairs(PROF_CATALOG) do
        local id = not entry.noButton and KnownRank(entry)
        if id then
            i = i + 1
            f.buttons[entry.key] = ProfButton(f, i, entry.key, "spell", id)
        end
    end
    i = i + 1
    f.buttons.hearthstone = ProfButton(f, i, "hearthstone", "item", HEARTHSTONE)
    f:SetSize(370, 40 + math.ceil(i / 2) * 26)
    NS._test.profFrame = f
    local byKey = {}
    for k, b in pairs(f.buttons) do
        if b.keyName then byKey[b.keyName] = k end
    end
    WatchKeys(byKey)

    if not profEvents then
        profEvents = CreateFrame("Frame")
        Probe:RegisterEvents(profEvents, PROF_TEST_EVENTS)
        profEvents:SetScript("OnEvent", function(_, event, ...) ProfEvent(event, ...) end)
        profEvents:SetScript("OnUpdate", function()
            local att = profAttempt
            if not att then return end
            local okT, targeting = pcall(SpellIsTargeting)
            if okT and plain(targeting) == true then att.cursor = true ; att.lastActivity = GetTime() end
            local age = GetTime() - att.t0
            local quiet = GetTime() - (att.lastActivity or att.t0)
            if age >= PROF_TIMEOUT then
                FinishProfAttempt("timeout")
            elseif age >= PROF_SETTLE and quiet >= PROF_QUIET then
                FinishProfAttempt("settled")
            end
        end)
    end
    f:Show()
    say("profession test: click a button, or press its CTRL-SHIFT key with the cursor "
          .. "OFF this frame, one at a time; wait for the verdict line. Try both ActionButtonUseKeyDown "
          .. "settings, and in combat. /fp apo proftest hide|show (bindings stay while hidden), "
          .. "/fp apo proftest close.")
end

-- ============================================================
-- Commands: /fp apo <command> [args]
-- ============================================================

Probe:Command("probe", function() RunProbe() end,
    "the APIs the bar depends on (run out of and in combat: /fp steps apo probe)")
Probe:Command("scan", function() RunItemScan() end,
    "every consumable in the client's item DB (the item tables' source)")
Probe:Command("scan2", function() RunSpellScan() end, "the spell text scan's tooltips lacked")
Probe:Command("scan3", function() RunWellFedScan() end, "every spell named Well Fed, with its description (#19)")
Probe:Command("applytest", function(args) RunApplyTest(args) end,
    "<itemID> | close: how a secure button coats a chosen hand (#24)")
Probe:Command("bar", function(args) RunBarProbe(args) end, "[label]: the action bars' layout (#40)")
Probe:Command("prof", function(args) RunProfProbe(args) end, "[label]: the profession spells known (#42)")
Probe:Command("proftest", function(args) RunProfTest(args) end,
    "[hide | show | close]: profession spells from secure buttons, by mouse and key (#42)")
Probe:Command("clear", function() Probe:ClearLog(); say("log cleared") end, "empty the saved log")

-- ============================================================
-- Procedures: /fp steps apo <name>
-- ============================================================

-- A scan's run step: an error keeps the step, for Retry or Skip.
local function StartOrFail(start, what)
    return function()
        if not start() then error(what .. " did not start: see the console") end
        return "started"
    end
end

-- A scan's wait step: done only once that scan finished in this session.
-- A failed check does not stop a procedure, so the wait itself must never
-- complete without it (Codex review of #77):
-- - nil: a /reload during the scan. ForeverProbe resumes the procedure at
--   this step, but the scan's state is per session and it no longer runs:
--   start it again (once; a refusal becomes an error below);
-- - an error: stay, until the owner goes Back and runs it again.
local function WaitFor(name, start)
    return function()
        local s = scans.status[name]
        if s == "done" then return true, scans.summary[name] end
        if s == "running" then return false, scans.progress or "starting" end
        if s == nil then
            if scans.running then return false, "waiting for the " .. scans.running .. " scan to end" end
            if start() then
                say("STEP the " .. name .. " scan was interrupted (a /reload): started again")
                return false, "started again after a /reload"
            end
            scans.status[name] = "error: could not start it again"
            s = scans.status[name]
        end
        return false, s .. ": press Back, then Run, to scan again"
    end
end

local function ScanCheck(name)
    return function() return scans.status[name] == "done", scans.summary[name] or scans.status[name] end
end

-- The item data comes from these three scans (AGENTS.md, Item Data). They
-- are written to disk only at /reload or logout, so the last step is one.
Probe:Steps("scan", {
    rev = 2,   -- 2: a wait never completes without its scan (Codex review of #77)
    title = "Rebuild the item data: consumables and Well Fed",
    { text = "Out of combat, on an English (enUS) client: the Well Fed scan compares spell names in "
          .. "English. Press Run to scan every item ID for consumables.",
      button = "Scan items", run = StartOrFail(RunItemScan, "the item scan"),
      check = function() return not InCombatLockdown(), "out of combat" end },
    { text = "Scanning the items and reading their tooltips. This takes a few minutes; you can keep "
          .. "playing.", wait = WaitFor("items", RunItemScan), check = ScanCheck("items") },
    { text = "Loading the spell text the tooltips lacked.", auto = true,
      run = StartOrFail(RunSpellScan, "the spell scan") },
    { text = "Loading spell text.", wait = WaitFor("spells", RunSpellScan), check = ScanCheck("spells") },
    { text = "Walking every spell ID for the Well Fed auras.", auto = true,
      run = StartOrFail(RunWellFedScan, "the Well Fed scan") },
    { text = "Scanning spells. This is the longest part.", wait = WaitFor("wellfed", RunWellFedScan),
      check = function()
          local wf = ProbeDB().wellFedScan
          return scans.status.wellfed == "done" and wf and wf.complete == true,
              scans.summary.wellfed or scans.status.wellfed
      end },
    { text = "Press Reload now (or type /reload) to write ApothecaProbe.lua. The session exports it "
          .. "from there.", reload = true },
})

-- The bar's APIs, once out of combat and once in combat (secrets differ).
Probe:Steps("probe", {
    title = "The bar's APIs, out of combat and in combat",
    { text = "Out of combat, with some consumables on the bar. Press Run.", button = "Run the probe",
      run = RunProbe, check = function() return not InCombatLockdown(), "out of combat" end },
    -- Not an event step on PLAYER_REGEN_DISABLED: it fires just before
    -- lockdown starts (AGENTS.md, Drag Anchor), so a run from it would
    -- read as out of combat. The wait runs it once lockdown is on.
    { text = "Enter combat (attack a training dummy or a low-level mob). The probe runs again once "
          .. "you are in combat.",
      wait = function()
          if not InCombatLockdown() then return false, "waiting for combat" end
          return true, RunProbe()
      end,
      check = function() return ProbeDB().lastProbe.combat ~= nil, "lastProbe.combat" end },
    { text = "Leave combat, then press Reload now (or type /reload) to write the results.", reload = true },
})

-- ============================================================
-- The Mage Scrolls wheel (#94): /fp steps apo wheel
-- ============================================================
-- What the wheel depends on and has not been measured: an imbue scroll on
-- the main hand through target-slot (or the cursor), the familiar's aura
-- (the glow), the Esc override, hold-and-release and tap on both
-- ActionButtonUseKeyDown settings, and the wheel in combat.

local WHEEL_ACTION = "CLICK ApothecaButton_magescrolls:LeftButton"
local wheel = { blocked = {} }   -- this session's baselines and findings
OnBlocked(function(event, addon, func)
    if wheel.watching then
        wheel.blocked[#wheel.blocked + 1] = event .. " " .. Probe.Show(addon, true) .. " " .. Probe.Show(func, true)
    end
end)

-- What the game answered while the wheel steps run (owner's second run: an
-- imbue and the combat steps went by hand, with no reason recorded). Each
-- line goes to the log, between the step lines: the wheel opening and
-- closing, the casts and the red error text.
local function WheelTrace(event, a1, a2, a3)
    if not wheel.watching then return end
    if event:find("^UNIT_") and a1 ~= "player" then return end
    local what = event
    if event:find("^UNIT_SPELLCAST") then
        local ok, name = pcall(C_Spell.GetSpellName, a3)
        if not ok then name = "?" end
        what = what .. " " .. tostring(plain(name)) .. " #" .. tostring(plain(a3))
    elseif event == "UI_ERROR_MESSAGE" then
        what = what .. " " .. tostring(plain(a2))
    else
        what = what .. " " .. tostring(plain(a1))
    end
    say("wheel trace: " .. what .. (InCombatLockdown() and " (combat)" or ""))
end
local wheelTrace = CreateFrame("Frame")
Probe:RegisterEvents(wheelTrace, APPLY_EVENTS)
wheelTrace:SetScript("OnEvent", function(_, event, a1, a2, a3) WheelTrace(event, a1, a2, a3) end)
local traceHooked
local function HookWheelArt()
    if traceHooked or not (Apotheca and Apotheca.Wheel and Apotheca.Wheel.art) then return end
    traceHooked = true
    Apotheca.Wheel.art:HookScript("OnShow", function()
        if wheel.watching then say("wheel trace: opened" .. (InCombatLockdown() and " (combat)" or "")) end
    end)
    Apotheca.Wheel.art:HookScript("OnHide", function()
        if wheel.watching then say("wheel trace: closed" .. (InCombatLockdown() and " (combat)" or "")) end
    end)
end

local function WheelOpen()
    local r = Apotheca and Apotheca.Wheel and Apotheca.Wheel.ring
    return r ~= nil and r:IsShown() == true
end

local function EscAction()
    local ok, a = pcall(GetBindingAction, "ESCAPE", true)
    return ok and a or nil
end

-- Every mage scroll held, counted: a drop means one was used.
local function ScrollTotal()
    local n = 0
    for _, e in ipairs(Apotheca.DATA.MAGE_SCROLLS or {}) do
        local ok, c = pcall(C_Item.GetItemCount, e.id)
        if ok and type(c) == "number" and not (issecretvalue and issecretvalue(c)) then n = n + c end
    end
    return n
end

local function AuraIDs()
    local ids = {}
    local ok = pcall(function()
        local i = 1
        while true do
            local a = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
            if not a then break end
            ids[a.spellId] = tostring(a.name)
            i = i + 1
        end
    end)
    return ok and ids or nil
end

local function MainHandEnchant()
    local ok, has, _, _, id = pcall(GetWeaponEnchantInfo)
    if not ok then return "refused" end
    return Probe.Show(has, true) .. " enchant " .. Probe.Show(id, true)
end

local function WheelState()
    if not (Apotheca and Apotheca.Wheel) then
        -- An Apotheca without the wheel (a release from before #94): say so, don't throw.
        local v = C_AddOns.GetAddOnMetadata("Apotheca", "Version")
        return { missing = "Apotheca " .. tostring(v) .. " has no wheel: deploy the dev build" }
    end
    local s = Apotheca.Wheel.screen
    local names = {}
    for _, b in ipairs(Apotheca.Wheel.slots) do
        if b:IsShown() and b.itemID then names[#names + 1] = Apotheca.API.ItemInfo(b.itemID) or b.itemID end
    end
    local _, sub = Apotheca.API.HandWeapon(16)
    return {
        enabled = s:GetAttribute("enabled"), count = s:GetAttribute("count"),
        scrolls = table.concat(names, ", "), key = GetBindingKey(WHEEL_ACTION),
        keyDown = C_CVar.GetCVar("ActionButtonUseKeyDown"), weaponSub = sub,
        imbueFor = Apotheca.ImbueWeapon(), mainHand = MainHandEnchant(),
    }
end

-- An auto step: remember the scroll count (and the auras) now.
local function Baseline()
    wheel.total, wheel.auras, wheel.seenOpen, wheel.targeting = ScrollTotal(), AuraIDs(), false, false
    wheel.watching = true
    HookWheelArt()
    return "scrolls " .. wheel.total
end

-- A wait: a scroll was used since the baseline (the count dropped).
local function WaitUsed(needCombat)
    return function()
        if WheelOpen() then wheel.seenOpen = true end
        if needCombat and not InCombatLockdown() then return false, "waiting for combat" end
        local now = ScrollTotal()
        if now < (wheel.total or now) then
            return true, "used one (" .. wheel.total .. " -> " .. now .. "), wheel seen open: "
                .. tostring(wheel.seenOpen) .. ", in combat: " .. tostring(InCombatLockdown())
        end
        return false, "waiting for a scroll to be used"
    end
end

local function OneUsed() return ScrollTotal() == (wheel.total or 0) - 1, "exactly one used" end

Probe:Command("wheel", function()
    for k, v in pairs(WheelState()) do say("wheel " .. k .. " = " .. Probe.Show(v, true)) end
end, "the Mage Scrolls wheel's state (#94)")

local CLOSE_ACTION = "CLICK ApothecaWheelClose:LeftButton"
-- Two ways in, named the same in every step (owner: "very confusing on what
-- button to push and what to hold"): THE BUTTON is the Mage Scrolls button on
-- Apotheca's bar, used with the mouse; YOUR KEY is the key bound to it.
local CLICK_OPEN = "Click THE BUTTON with the mouse (press and let go). The wheel opens and stays open. "
local HOLD = "Press YOUR KEY and keep holding it. The wheel opens around the mouse cursor. Still holding the "
      .. "key, move the mouse onto "
Probe:Steps("wheel", {
    title = "The Mage Scrolls wheel (#94)",
    { text = "On a mage, out of combat, with some mage scrolls in your bags (a familiar, an imbue for your "
          .. "main-hand weapon, Minor Evocation or Cryoblast). In this test, THE BUTTON is the Mage Scrolls "
          .. "button on Apotheca's bar (its tooltip says Mage Scrolls), and YOUR KEY is a key you bind to it "
          .. "now: Esc > Options > Keybindings, find the Apotheca section, click the box next to Mage "
          .. "Scrolls, press a free key, then Okay. The step goes on by itself once the key is bound.",
      wait = function()
          local s = WheelState()
          if s.missing then return false, s.missing end
          if s.key == nil then return false, "no key bound to Mage Scrolls yet" end
          return true, s
      end, timeout = 300,
      check = function()
          local s = WheelState()
          if s.missing then return false, s.missing end
          return s.enabled == true and (s.count or 0) > 0 and s.key ~= nil,
              "enabled " .. tostring(s.enabled) .. ", " .. tostring(s.count) .. " scrolls, key " .. tostring(s.key)
      end },
    { text = CLICK_OPEN .. "Leave it open.", screenshot = "wheel open",
      wait = function()
          if not WheelOpen() then return false, "waiting for the wheel" end
          return true, "open; Esc is now " .. Probe.Show(EscAction(), true)
      end,
      check = function() return EscAction() == CLOSE_ACTION, Probe.Show(EscAction(), true) end },
    { text = "Move the mouse over the scrolls without clicking. Does it look right: the scrolls' icons on a "
          .. "glass disc like Glass UI's windows (same tint), the name of the scroll under the cursor on a "
          .. "glass plate under it (all of it on screen, readable), a soft glow on that scroll, and no "
          .. "tooltip covering the wheel?", ask = true },
    { text = "Press Esc on the keyboard. The wheel closes.",
      wait = function()
          if WheelOpen() then return false, "waiting for Esc" end
          return true, "closed; Esc is now " .. Probe.Show(EscAction(), true)
      end,
      check = function() return EscAction() ~= CLOSE_ACTION, Probe.Show(EscAction(), true) end },
    { text = "Did the game menu stay closed when you pressed Esc?", ask = true },
    { text = "Remembering your buffs.", auto = true, run = Baseline },
    { text = CLICK_OPEN .. "Then click the FAMILIAR scroll on the wheel (Familiar: Rat, Frog, Cat...). "
          .. "No familiar scroll? Press Skip.",
      wait = function()
          local now = AuraIDs()
          if not now or not wheel.auras then return false, "auras unreadable" end
          local new = {}
          for id, name in pairs(now) do
              if not wheel.auras[id] then new[#new + 1] = name .. "#" .. id end
          end
          if #new == 0 then return false, "waiting for a new buff" end
          return true, "new buffs: " .. table.concat(new, "; ")
      end, timeout = 120,
      check = function() return Apotheca.HasFamiliar() == true, "Apotheca.HasFamiliar() sees it" end },
    { text = "Remembering the main hand.", auto = true,
      run = function() Baseline(); return MainHandEnchant() end },
    { text = HOLD .. "the IMBUE scroll (Imbue Lesser Flame, Chillknife...), then let go of the key. The "
          .. "imbue goes on your weapon. If the cursor turns into a pointing hand instead, click your "
          .. "weapon in the character sheet. No imbue scroll? Press Skip.",
      wait = function()
          if WheelOpen() then wheel.seenOpen = true end
          local ok, t = pcall(SpellIsTargeting)
          if ok and t then wheel.targeting = true end
          if Apotheca.API.HandCoated(16) ~= true or ScrollTotal() >= (wheel.total or 0) then
              return false, "waiting for the imbue"
          end
          return true, "imbued: " .. MainHandEnchant() .. "; targeting cursor seen: " .. tostring(wheel.targeting)
              .. "; wheel seen open: " .. tostring(wheel.seenOpen)
      end, timeout = 120,
      check = function() return wheel.targeting == false, "no targeting cursor: target-slot applied it" end },
    { text = "Remembering your scrolls.", auto = true, run = Baseline },
    { text = "Press YOUR KEY once, quickly (press and let go at once, without moving the mouse). The wheel "
          .. "opens and stays open. Press YOUR KEY once more: the wheel closes. Nothing is used.",
      wait = function()
          if WheelOpen() then wheel.seenOpen = true; return false, "open: press your key once more" end
          if not wheel.seenOpen then return false, "waiting for the wheel" end
          return true, "opened and closed; scrolls " .. ScrollTotal()
      end, timeout = 120,
      check = function() return ScrollTotal() == wheel.total, "nothing used" end },
    { text = "Next, the same with the game's other 'cast on key down' setting. Press Flip it; a later "
          .. "step puts your setting back.", button = "Flip it",
      run = function()
          wheel.keyDown = C_CVar.GetCVar("ActionButtonUseKeyDown")
          C_CVar.SetCVar("ActionButtonUseKeyDown", wheel.keyDown == "1" and "0" or "1")
          return "was " .. tostring(wheel.keyDown) .. ", now " .. tostring(C_CVar.GetCVar("ActionButtonUseKeyDown"))
      end },
    { text = "Remembering your scrolls.", auto = true, run = Baseline },
    { text = HOLD .. "any scroll you don't mind using (Minor Evocation, Cryoblast...), then let go of the "
          .. "key. That scroll is used, once.",
      wait = WaitUsed(false), timeout = 120, check = OneUsed },
    { text = "Remembering your scrolls.", auto = true, run = Baseline },
    { text = CLICK_OPEN .. "Then click a scroll on the wheel with the mouse, one that is not cooling down "
          .. "(the one you just used may be). That scroll is used, once.",
      wait = WaitUsed(false), timeout = 120, check = OneUsed },
    { text = "Putting your 'cast on key down' setting back.", auto = true,
      run = function()
          if wheel.keyDown then C_CVar.SetCVar("ActionButtonUseKeyDown", wheel.keyDown) end
          return "now " .. tostring(C_CVar.GetCVar("ActionButtonUseKeyDown"))
      end },
    { text = "Remembering your scrolls.", auto = true, run = Baseline },
    { text = "Get into combat (attack a training dummy or a low-level mob). Then: " .. HOLD
          .. "any scroll that is not cooling down, then let go of the key. If the game says no (red text), "
          .. "press Done: the log keeps what it said.",
      wait = WaitUsed(true), timeout = 300, check = OneUsed },
    { text = "Remembering your scrolls.", auto = true, run = Baseline },
    { text = "Still in combat: " .. CLICK_OPEN .. "Then click a scroll on the wheel with the mouse, one that is "
          .. "not cooling down. If the game says no, press Done.",
      wait = WaitUsed(true), timeout = 300,
      check = function()
          return #wheel.blocked == 0, #wheel.blocked == 0 and "nothing blocked" or table.concat(wheel.blocked, "; ")
      end },
    { text = "Did you see any red error, or 'Interface action failed because of an AddOn'?", ask = true },
    { text = "Leave combat, then press Reload now (or type /reload) to write the results.", reload = true },
})
