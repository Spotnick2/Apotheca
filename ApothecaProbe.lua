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
