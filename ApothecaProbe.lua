-- ============================================================
-- Apotheca - Forever probe (/apo probe)
--
-- A throwaway measurement tool for the port (issue #3). It prints what
-- the client actually does for each API the port depends on and keeps the
-- last run in ApothecaDB.lastProbe. That table is written to disk at
-- logout even though this client never reads it back, so the results can
-- be read off the SavedVariables file. Run it once out of combat and
-- once in combat.
--
-- Delete this file, and its TOC line, once docs/FOREVER-PROBE.md is settled.
-- ============================================================

Apotheca = Apotheca or {}

local PREFIX = "|cff9966ffApotheca probe:|r "
local log

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
-- text and item spell. The result lands in ApothecaDB.itemScan, which the
-- client writes to disk at logout even though it never reads it back;
-- the item tables are built from that file.
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
                ApothecaDB.itemScan = { build = select(2, GetBuildInfo()), items = found }
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
-- description directly. Results merge into ApothecaDB.itemScan (as `d`).
local RELEVANT_SUB = { [1] = true, [2] = true, [3] = true, [4] = true, [5] = true, [7] = true }
local DESC_TRIES   = 40         -- 0.5 s apart: ~20 s

local function HasUseLine(lines)
    for _, l in ipairs(lines or {}) do
        if l:find("^Use:") then return true end
    end
    return false
end

function Apotheca.RunSpellScan()
    if Apotheca._scanRunning then print(PREFIX .. "scan already running") return end
    local scan = ApothecaDB and ApothecaDB.itemScan
    if not scan then print(PREFIX .. "run /apo scan first") return end
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

    if ApothecaDB then
        ApothecaDB.lastProbe = ApothecaDB.lastProbe or {}
        ApothecaDB.lastProbe[InCombatLockdown() and "combat" or "idle"] = log
    end
    print(PREFIX .. "done. Results are also stored for the SavedVariables file on logout.")
end
