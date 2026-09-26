-- ============================================================
-- Apotheca - Forever probe (/apo probe)
--
-- A throwaway measurement tool for the port (issue #3). It prints what
-- the client actually does for each API the port depends on and keeps the
-- last run in ApothecaProbeDB.lastProbe, which is written to disk at
-- logout, so the results can be read off the probe's SavedVariables file
-- (SavedVariables/ApothecaProbe.lua). Run it once out of combat and once
-- in combat.
--
-- A separate, development-only addon (Tools/ApothecaProbe, loaded after
-- Apotheca): it is never packaged, and `pwsh Tools/deploy.ps1 -Probe`
-- installs it. /apo probe, /apo scan, /apo scan2 and /apo scan3 do nothing
-- without it.
-- ============================================================

Apotheca = Apotheca or {}

local PREFIX = "|cff9966ffApotheca probe:|r "
local log

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

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, _, name)
    if name == "ApothecaProbe" then
        ProbeDB()
        self:UnregisterEvent("ADDON_LOADED")
    end
end)

local function out(key, value)
    local text = tostring(value)
    log[#log + 1] = key .. " = " .. text
    print(PREFIX .. key .. " = " .. text)
end

-- Describe a value without comparing it: comparing a secret throws.
local function describe(...)
    local n = select("#", ...)
    if n == 0 then return "(no returns)" end
    local parts = {}
    for i = 1, n do
        local v = select(i, ...)
        if issecretvalue and issecretvalue(v) then
            parts[i] = "<secret>"
        else
            parts[i] = tostring(v)
        end
    end
    return table.concat(parts, ", ")
end

-- select("#") keeps trailing nils, so "returned nil" and "returned
-- nothing" stay distinct: C_Item.GetItemInfo's cache miss is the latter.
local function report(key, ok, ...)
    if ok then
        out(key, describe(...))
    else
        out(key, "ERROR: " .. tostring((...)))
    end
end

local function try(key, fn)
    report(key, pcall(fn))
end

-- ADDON_ACTION_BLOCKED / FORBIDDEN are how the client reports a protected
-- call from insecure code. Listen while calling UseItemByName.
local blockedBy
local blockFrame = CreateFrame("Frame")
blockFrame:SetScript("OnEvent", function(_, event, addon, func)
    blockedBy = event .. " (" .. tostring(addon) .. ", " .. tostring(func) .. ")"
end)
pcall(blockFrame.RegisterEvent, blockFrame, "ADDON_ACTION_BLOCKED")
pcall(blockFrame.RegisterEvent, blockFrame, "ADDON_ACTION_FORBIDDEN")

local TEMPLATES = {
    { "CheckButton", "InterfaceOptionsCheckButtonTemplate", "Text" },
    { "CheckButton", "UIRadioButtonTemplate", nil },
    { "Slider",      "OptionsSliderTemplate", "Low" },
    { "Frame",       "UIDropDownMenuTemplate", "Text" },
    { "Button",      "UIPanelButtonTemplate", "Text" },
    { "Cooldown",    "CooldownFrameTemplate", nil },
}

-- ============================================================
-- /apo scan: the client's own consumable database (issue #4)
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
local TIP_PER_FRAME  = 20
local TIP_TRIES      = 20       -- 0.5 s apart: ~10 s for a slow item load

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

function Apotheca.RunItemScan()
    if Apotheca._scanRunning then
        print(PREFIX .. "scan already running")
        return
    end
    Apotheca._scanRunning = true
    local found, order = {}, {}
    local nextID = 1
    print(PREFIX .. "scanning item IDs 1-" .. SCAN_MAX_ID .. " for consumables...")

    local f = CreateFrame("Frame")
    local phase, tipIndex, tries = "ids", 1, {}
    f:SetScript("OnUpdate", function(self)
        if phase == "ids" then
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
            if nextID > SCAN_MAX_ID then
                phase = "tips"
                print(PREFIX .. #order .. " consumables found; reading tooltips...")
            end
        elseif phase == "tips" then
            local done = 0
            while done < TIP_PER_FRAME and tipIndex <= #order do
                local id = order[tipIndex]
                local e = found[id]
                -- The queue is FIFO, so if the head was retried too
                -- recently, everything behind it was too: wait a frame.
                if e.retryAt and e.retryAt > GetTime() then break end
                local lines = TooltipLines(id)
                tries[id] = (tries[id] or 0) + 1
                if lines or tries[id] >= TIP_TRIES then
                    e.t, e.retryAt = lines, nil
                    e.n = C_Item.GetItemInfo(id)
                    local okSpell, spellName, spellID = pcall(C_Item.GetItemSpell, id)
                    if okSpell then e.sp, e.spn = spellID, spellName end
                    tipIndex = tipIndex + 1
                else
                    -- Not loaded yet: ask again and move it to the back.
                    C_Item.RequestLoadItemDataByID(id)
                    e.retryAt = GetTime() + 0.5
                    table.remove(order, tipIndex)
                    order[#order + 1] = id
                end
                done = done + 1
            end
            if tipIndex > #order then
                self:SetScript("OnUpdate", nil)
                Apotheca._scanRunning = false
                local missing = 0
                for _, e in pairs(found) do if not e.t then missing = missing + 1 end end
                ProbeDB().itemScan = { build = select(2, GetBuildInfo()), items = found }
                print(PREFIX .. "scan done: " .. #order .. " consumables, " .. missing
                      .. " without tooltip text. /reload or log out to write the file.")
            end
        end
    end)
end

-- /apo scan2: second pass. Item tooltips come back without their "Use:"
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

function Apotheca.RunSpellScan()
    if Apotheca._scanRunning then print(PREFIX .. "scan already running") return end
    local scan = ProbeDB().itemScan
    if not scan then print(PREFIX .. "run /apo scan first") return end
    -- Saved data loads back since 70009, so the scan found here may be a
    -- previous build's. Adding this build's spell text to it would export
    -- two builds under one name (/code-review of #17).
    local build = select(2, GetBuildInfo())
    if tostring(scan.build) ~= tostring(build) then
        print(PREFIX .. "the saved scan is from build " .. tostring(scan.build)
              .. ", this client is " .. tostring(build) .. ": run /apo scan first")
        return
    end
    Apotheca._scanRunning = true

    local queue = {}
    for id, e in pairs(scan.items) do
        local oil = e.n and e.n:find("Oil")
        if (RELEVANT_SUB[e.s] or oil) and e.sp and not HasUseLine(e.t) and not e.d then
            queue[#queue + 1] = id
            C_Spell.RequestLoadSpellData(e.sp)
            C_Item.RequestLoadItemDataByID(id)
        end
    end
    print(PREFIX .. #queue .. " items need their spell text; loading...")

    local head, tries = 1, {}
    local f = CreateFrame("Frame")
    f:SetScript("OnUpdate", function(self)
        local done = 0
        while done < TIP_PER_FRAME and head <= #queue do
            local id = queue[head]
            local e = scan.items[id]
            if e.retryAt and e.retryAt > GetTime() then break end
            local okD, desc = pcall(C_Spell.GetSpellDescription, e.sp)
            local lines = TooltipLines(id)
            tries[id] = (tries[id] or 0) + 1
            local got = (okD and desc and desc ~= "") or HasUseLine(lines)
            if got or tries[id] >= DESC_TRIES then
                if okD and desc and desc ~= "" then e.d = desc end
                if lines and HasUseLine(lines) then e.t = lines end
                e.retryAt = nil
                head = head + 1
            else
                C_Spell.RequestLoadSpellData(e.sp)
                e.retryAt = GetTime() + 0.5
                table.remove(queue, head)
                queue[#queue + 1] = id
            end
            done = done + 1
        end
        if head > #queue then
            self:SetScript("OnUpdate", nil)
            Apotheca._scanRunning = false
            local still = 0
            for _, id in ipairs(queue) do
                local e = scan.items[id]
                if not e.d and not HasUseLine(e.t) then still = still + 1 end
            end
            print(PREFIX .. "spell scan done: " .. #queue .. " items, " .. still
                  .. " still without text. /reload to write the file.")
        end
    end)
end

-- /apo scan3: the Well Fed buffs (#19). Forever's XP food ("experience
-- gained from kills is increased by 5%") gives ONE aura named "Well Fed",
-- like ordinary food, and its spell ID is not the item's spell (measured:
-- item spell 1248380 gives aura 1248422). The only language-independent
-- way to tell an XP Well Fed from an ordinary one is its aura spell ID, so
-- this pass collects every spell named "Well Fed" with its description.
--
-- Nothing assumes where those IDs are (Codex reviews of #19 and #20):
-- - the sweep goes on until SPELL_SCAN_TAIL IDs past the highest spell that
--   exists, and at least to SPELL_SCAN_MIN;
-- - every spell whose name was not loaded is requested and retried, unless
--   there are more than SPELL_LOAD_ALL_LIMIT of them; then only those in
--   SPELL_LOAD_FROM..SPELL_LOAD_TO (Forever's new food spells) are, and the
--   rest are counted as skipped;
-- - the result is `complete` only if no name was skipped or never loaded
--   and every Well Fed spell has a description. export_wellfed.lua refuses
--   to call an incomplete scan complete.
-- Each frame stops after SPELL_FRAME_MS of work. Names are compared in
-- English: run it on an enUS client.
local SPELL_SCAN_MIN        = 1500000
local SPELL_SCAN_TAIL       = 200000
local SPELL_LOAD_ALL_LIMIT  = 60000
local SPELL_LOAD_FROM, SPELL_LOAD_TO = 1200000, 1400000
local SPELL_LOAD_TRIES      = 10      -- 0.5 s apart
local SPELL_FRAME_MS        = 8
local WELL_FED = "Well Fed"

function Apotheca.RunWellFedScan()
    if Apotheca._scanRunning then print(PREFIX .. "scan already running") return end
    Apotheca._scanRunning = true
    local result = { build = select(2, GetBuildInfo()), highest = 0, scannedTo = 0, exist = 0,
                     unnamedSkipped = 0, unnamedNeverLoaded = 0, noDescription = 0,
                     complete = false, spells = {} }
    local unnamed, candidates = {}, {}
    local phase, nextID, head, tries, retryAt = 1, 1, 1, {}, {}

    local function named(id)
        local name = C_Spell.GetSpellName(id)
        if name == WELL_FED then candidates[#candidates + 1] = id end
        return name ~= nil
    end

    -- Work through a retry queue: `step(id)` returns true when the entry is
    -- settled, false to retry it later. Returns true when the queue is done.
    local function drain(queue, step, deadline)
        while head <= #queue do
            if debugprofilestop() > deadline then return false end
            local id = queue[head]
            if retryAt[id] and retryAt[id] > GetTime() then return false end
            tries[id] = (tries[id] or 0) + 1
            if step(id) then
                head = head + 1
            else
                retryAt[id] = GetTime() + 0.5
                table.remove(queue, head)
                queue[#queue + 1] = id
            end
        end
        return true
    end

    print(PREFIX .. "Well Fed scan: walking spell IDs...")
    local f = CreateFrame("Frame")
    f:SetScript("OnUpdate", function(self)
        local deadline = debugprofilestop() + SPELL_FRAME_MS
        if phase == 1 then
            -- Which spells exist, and the names that are already loaded.
            while debugprofilestop() <= deadline do
                local last = math.max(SPELL_SCAN_MIN, result.highest + SPELL_SCAN_TAIL)
                if nextID > last then break end
                local id = nextID
                nextID = nextID + 1
                if C_Spell.DoesSpellExist(id) then
                    result.exist, result.highest = result.exist + 1, id
                    if not named(id) then unnamed[#unnamed + 1] = id end
                end
            end
            if nextID > math.max(SPELL_SCAN_MIN, result.highest + SPELL_SCAN_TAIL) then
                result.scannedTo = nextID - 1
                if #unnamed > SPELL_LOAD_ALL_LIMIT then
                    local keep = {}
                    for _, id in ipairs(unnamed) do
                        if id >= SPELL_LOAD_FROM and id <= SPELL_LOAD_TO then keep[#keep + 1] = id
                        else result.unnamedSkipped = result.unnamedSkipped + 1 end
                    end
                    unnamed = keep
                end
                for _, id in ipairs(unnamed) do C_Spell.RequestLoadSpellData(id) end
                phase, head = 2, 1
                print(PREFIX .. result.exist .. " spells exist (highest " .. result.highest .. "); loading "
                      .. #unnamed .. " unnamed ones" .. (result.unnamedSkipped > 0
                      and (", skipping " .. result.unnamedSkipped .. " outside " .. SPELL_LOAD_FROM
                           .. ".." .. SPELL_LOAD_TO) or "") .. "...")
            end
        elseif phase == 2 then
            -- Names that were not loaded: retry, then give up and count.
            local done = drain(unnamed, function(id)
                if named(id) then return true end
                if tries[id] >= SPELL_LOAD_TRIES then
                    result.unnamedNeverLoaded = result.unnamedNeverLoaded + 1
                    return true
                end
                C_Spell.RequestLoadSpellData(id)
                return false
            end, deadline)
            if done then
                phase, head, tries, retryAt = 3, 1, {}, {}
                for _, id in ipairs(candidates) do C_Spell.RequestLoadSpellData(id) end
                print(PREFIX .. #candidates .. " spells named " .. WELL_FED .. "; loading their descriptions...")
            end
        else
            -- Descriptions of the Well Fed spells.
            local done = drain(candidates, function(id)
                local ok, desc = pcall(C_Spell.GetSpellDescription, id)
                if ok and desc and desc ~= "" then
                    result.spells[id] = desc
                    return true
                end
                if tries[id] >= DESC_TRIES then
                    result.spells[id] = ""
                    result.noDescription = result.noDescription + 1
                    return true
                end
                C_Spell.RequestLoadSpellData(id)
                return false
            end, deadline)
            if done then
                self:SetScript("OnUpdate", nil)
                Apotheca._scanRunning = false
                local xp = 0
                for _, d in pairs(result.spells) do
                    if d:find("[Ee]xperience gained from kills") then xp = xp + 1 end
                end
                result.complete = result.unnamedSkipped == 0 and result.unnamedNeverLoaded == 0
                                  and result.noDescription == 0
                ProbeDB().wellFedScan = result
                print(PREFIX .. "Well Fed scan done (" .. (result.complete and "complete" or "INCOMPLETE")
                      .. "): " .. #candidates .. " Well Fed spells, " .. xp .. " with the XP bonus; "
                      .. result.exist .. " spells to " .. result.scannedTo .. "; names skipped "
                      .. result.unnamedSkipped .. ", never loaded " .. result.unnamedNeverLoaded
                      .. "; without description " .. result.noDescription .. ". /reload to write the file.")
            end
        end
    end)
end

function Apotheca.RunProbe()
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
        local bar = Apotheca._probeBar or CreateFrame("StatusBar", nil, UIParent)
        Apotheca._probeBar = bar
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
    db.lastProbe = db.lastProbe or {}
    db.lastProbe[InCombatLockdown() and "combat" or "idle"] = log
    print(PREFIX .. "done. Results are also stored for the SavedVariables file on logout.")
end
