-- ============================================================
-- Apotheca - WoW: Forever compatibility layer
--
-- Forever (1.60.1, Interface 16001) is Vanilla content on the Retail
-- (Mainline) API. Every API that moved or disappeared relative to TBC
-- Classic is reached through Apotheca.API, so a client change lands in
-- one file. Call through the table (Apotheca.API.ItemInfo(id)); do not
-- copy functions into file locals.
--
-- Measured facts behind these adapters:
--   C:\Projects\WoW\References\PORTING-TBC-TO-FOREVER.md
--   C:\Projects\WoW\References\forever-api-1.60.1.70338.md
-- ============================================================

Apotheca = Apotheca or {}
local API = {}
Apotheca.API = API

-- The client build these adapters were measured against. On any other
-- build players get a one-line note at login (see Apotheca.lua).
API.MEASURED_ON_BUILD = 70009

-- The last client build on which SavedVariables were written but never
-- read back. Build 70009 fixed it (confirmed with a full exit and relaunch,
-- 2026-09-25). On a build at or below this one, "no saved settings were
-- loaded" is the client bug; above it, it only means a first install.
API.SV_BROKEN_THROUGH_BUILD = 69977

local PREFIX = "|cff9966ffApotheca:|r "

-- ------------------------------------------------------------
-- Items
-- ------------------------------------------------------------

-- C_Item.GetItemInfo keeps the Classic 18-value tuple. It returns NO
-- values (not nil) on a cache miss; GET_ITEM_INFO_RECEIVED follows.
function API.ItemInfo(itemID)
    if not itemID then return nil end
    return C_Item.GetItemInfo(itemID)
end

-- NOT C_Item.GetItemIcon: that one takes an ItemLocation.
function API.ItemIcon(itemID)
    if not itemID then return nil end
    return C_Item.GetItemIconByID(itemID)
end

-- Same (start, duration, enable) tuple as the old global.
-- C_Item.GetItemCooldown is different: its third value is a bool.
function API.ItemCooldown(itemID)
    return C_Container.GetItemCooldown(itemID)
end

-- ------------------------------------------------------------
-- Spells (#42, the profession bar)
-- ------------------------------------------------------------

-- Whether the player knows a spell: true, false, or nil when the client
-- doesn't say. Measured on 70334: C_SpellBook.IsSpellKnown agrees with
-- IsSpellKnown, IsPlayerSpell and IsSpellInSpellBook on every profession
-- spell, and only a profession's current rank is known.
function API.SpellKnown(spellID)
    local ok, known = pcall(C_SpellBook.IsSpellKnown, spellID)
    if not ok or type(known) ~= "boolean" then return nil end
    return known
end

function API.SpellIcon(spellID)
    local ok, icon = pcall(C_Spell.GetSpellTexture, spellID)
    return ok and icon or nil
end

function API.SpellName(spellID)
    local ok, name = pcall(C_Spell.GetSpellName, spellID)
    return ok and name or nil
end

-- (start, duration) for a cooldown swipe. Secret in combat (measured on
-- 70334: startTime, duration and modRate), so callers hand them straight
-- to Cooldown:SetCooldown and never compare or truth-test them (not even
-- `st or 0`).
function API.SpellCooldown(spellID)
    local info = C_Spell.GetSpellCooldown(spellID)
    if type(info) ~= "table" then return 0, 0 end
    return info.startTime, info.duration
end

-- How many of an item the bags hold (not the bank): one count, without
-- scanning every slot.
function API.ItemCount(itemID)
    local ok, n = pcall(C_Item.GetItemCount, itemID)
    if ok and type(n) == "number" then return n end
    return 0
end

-- ------------------------------------------------------------
-- Containers
-- ------------------------------------------------------------

function API.ContainerNumSlots(bag)
    return C_Container.GetContainerNumSlots(bag) or 0
end

function API.ContainerItemID(bag, slot)
    return C_Container.GetContainerItemID(bag, slot)
end

-- GetContainerItemInfo returns a struct here, not the old tuple.
function API.ContainerItemCount(bag, slot)
    local info = C_Container.GetContainerItemInfo(bag, slot)
    return info and info.stackCount or 0
end

-- Carried bags: backpack, bags 1..NUM_BAG_SLOTS, and the reagent bag.
-- Bank IDs all moved on this client, so nothing else is listed.
local carriedBags
function API.CarriedBags()
    if not carriedBags then
        carriedBags = {}
        for bag = 0, (NUM_BAG_SLOTS or 4) do carriedBags[#carriedBags + 1] = bag end
        local reagent = Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag
        if reagent then carriedBags[#carriedBags + 1] = reagent end
    end
    return carriedBags
end

-- ------------------------------------------------------------
-- Auras
--
-- UnitBuff / UnitDebuff are gone. In combat every aura is secret:
-- index reads throw, and a secret value also throws when it is
-- compared or truth-tested. So everything that touches aura data
-- happens inside ONE pcall, and a blocked read is reported as nil
-- ("unknown"), distinct from an empty set ("nothing there").
-- ------------------------------------------------------------

-- Returns names, spellIDs (two sets) of the player's auras, or nil
-- when the client refused the read.
function API.PlayerAuras(filter)
    local ok, names, ids = pcall(function()
        local n, s = {}, {}
        local i = 1
        while true do
            local aura = C_UnitAuras.GetAuraDataByIndex("player", i, filter or "HELPFUL")
            if not aura then break end
            if aura.name then n[aura.name] = true end
            if aura.spellId then s[aura.spellId] = true end
            i = i + 1
        end
        return n, s
    end)
    if not ok then return nil end
    return names, ids
end

-- ------------------------------------------------------------
-- Secret values
--
-- The player's current health and power are secret on this client, even
-- out of combat (docs/FOREVER-PROBE.md); cooldowns and counts may be in
-- combat. A secret must never reach a comparison outside a pcall.
-- ------------------------------------------------------------

-- Missing health and missing MANA as plain numbers, each nil when the
-- client would not hand it over. Read separately: the two secrecy switches
-- are independent (measured), and mana is asked for by power type so a
-- shapeshifted druid's energy or rage is never mistaken for it.
local function missing(cur, max)
    local ok, m = pcall(function()
        local v = (max() or 0) - (cur() or 0)
        -- Comparing a secret is what throws; do it here, inside the pcall.
        local _ = v > 0
        return v
    end)
    if ok then return m end
    return nil
end

function API.PlayerMissing()
    local mana = Enum and Enum.PowerType and Enum.PowerType.Mana or 0
    return missing(function() return UnitHealth("player") end,
                   function() return UnitHealthMax("player") end),
           missing(function() return UnitPower("player", mana) end,
                   function() return UnitPowerMax("player", mana) end)
end

-- Maximum health and mana. Unlike the current values these are readable
-- (measured: ShouldUnitHealthMaxBeSecret = false, UnitPowerMax plain), but
-- read inside a pcall anyway so a future build cannot throw here.
function API.PlayerMax()
    local mana = Enum and Enum.PowerType and Enum.PowerType.Mana or 0
    local ok, h, m = pcall(function()
        local hh, mm = UnitHealthMax("player"), UnitPowerMax("player", mana)
        local _ = (hh > 0), (mm >= 0)
        return hh, mm
    end)
    if not ok then return nil, nil end
    return h, m
end

-- ------------------------------------------------------------
-- Showing fullness without knowing it (#6)
--
-- The client will not tell an addon whether the player is at full health
-- or mana, but it will COLOUR something by it: UnitHealthPercent /
-- UnitPowerPercent take a colour curve and evaluate it inside the client,
-- returning a colour whose channels may be secret. Those go straight into
-- a setter (SetVertexColor) and are never compared. This is how unit
-- frame addons draw health on Forever.
--
-- The curve is white up to 99.99999% and grey at exactly 100%, linear
-- (set explicitly when the client has the enum; it is not in the API dump,
-- and EllesmereUI's Forever port sets it). The 1e-7 ramp is under one
-- point for any maximum below ten million. Health uses usePredicted =
-- false: an incoming heal must not grey the icon before it lands.
-- ------------------------------------------------------------

API.FULL_GREY = 0.4

local fullCurve
local function FullCurve()
    if fullCurve == nil then
        fullCurve = false
        pcall(function()
            local c = C_CurveUtil.CreateColorCurve()
            -- Its own pcall: a SetType this client rejects must not throw
            -- away the whole curve (linear is the likely default anyway).
            local linear = Enum and Enum.LuaCurveType and Enum.LuaCurveType.Linear
            if linear and c.SetType then pcall(c.SetType, c, linear) end
            local g = API.FULL_GREY
            c:AddPoint(0,         CreateColor(1, 1, 1, 1))
            c:AddPoint(0.9999999, CreateColor(1, 1, 1, 1))
            c:AddPoint(1,         CreateColor(g, g, g, 1))
            fullCurve = c
        end)
    end
    return fullCurve or nil
end

-- Paint every texture in `textures` with the fullness colour for
-- `resource` ("health" or "mana"): white, or grey when full. The colour is
-- asked for ONCE, and its channels (possibly secret) never leave this
-- function: they go straight into SetVertexColor. Even `r ~= nil` throws
-- on a secret (Codex review of #13), and Lua 5.1 tests cannot catch that,
-- so no caller is ever handed a channel. Returns a plain boolean: false
-- when the client refused, and nothing was painted.
local function paint(resource, curve, textures)
    local color
    if resource == "health" then
        color = UnitHealthPercent("player", false, curve)
    else
        local mana = Enum and Enum.PowerType and Enum.PowerType.Mana or 0
        color = UnitPowerPercent("player", mana, false, curve)
    end
    local r, g, b = color:GetRGB()
    for i = 1, #textures do textures[i]:SetVertexColor(r, g, b) end
end

function API.PaintFullness(resource, textures)
    local curve = FullCurve()
    if not curve or #textures == 0 then return false end
    return (pcall(paint, resource, curve, textures))
end

-- ------------------------------------------------------------
-- The game's role selector (#9)
--
-- The Tank / Healer / Damage checkboxes the player ticks in the game's
-- own role selector. Read through the typed C_LFGListRoles first, then the
-- older GetLFGRoles global; each inside a pcall, and only real booleans
-- are trusted, so an unexpected shape reads as "nothing selected".
-- (The group-assigned role is a separate, opt-in source: API.GroupRole.)
-- Returns tank, healer, damage (plain booleans), or nil when no source
-- answered.
-- ------------------------------------------------------------

local function fromStruct(r)
    if type(r) ~= "table" then return nil end
    local tank, healer = r.tank, r.healer
    local damage = r.dps
    if damage == nil then damage = r.damage end
    if type(tank) ~= "boolean" and type(healer) ~= "boolean" and type(damage) ~= "boolean" then
        return nil
    end
    return tank == true, healer == true, damage == true
end

-- The role assigned in the current group ("Set Role" on the party frame),
-- as "TANK" / "HEALER" / "DAMAGE", or nil when not in a group or none is
-- set. Opt-in only (db.useGroupRole): the owner found it often unset or
-- stale, which is why it is not part of the default order.
function API.GroupRole()
    local ok, inGroup, role = pcall(function()
        return IsInGroup(), UnitGroupRolesAssigned("player")
    end)
    if not ok or not inGroup then return nil end
    if role == "TANK" or role == "HEALER" then return role end
    if role == "DAMAGER" then return "DAMAGE" end
    return nil
end

-- The FIRST source that answers with a valid shape wins, even when nothing
-- is ticked: "nothing ticked" is a real answer (the class default then
-- applies), and a later source may still hold an older pick (Codex review
-- of #14). The fallbacks are only for a failing call or a wrong shape.
function API.SelectedRoles()
    local L = C_LFGListRoles
    if L then
        for _, getter in ipairs({ "GetRoles", "GetSavedRoles" }) do
            local fn = L[getter]
            if fn then
                local ok, r = pcall(fn)
                if ok then
                    local t, h, d = fromStruct(r)
                    if t ~= nil then return t, h, d end
                end
            end
        end
    end
    if GetLFGRoles then
        local ok, _, t, h, d = pcall(GetLFGRoles)   -- leader, tank, healer, dps
        if ok and (type(t) == "boolean" or type(h) == "boolean" or type(d) == "boolean") then
            return t == true, h == true, d == true
        end
    end
    return nil
end

-- ------------------------------------------------------------
-- Using items from insecure code
--
-- The UseItemByName global is gone. C_Item.UseItemByName exists but is
-- probably protected; /apo probe measures it. Returns false when the
-- call is missing or raised an error.
-- ------------------------------------------------------------

function API.UseItemByName(name)
    local fn = C_Item and C_Item.UseItemByName
    if not fn or not name then return false end
    return (pcall(fn, name))
end

-- ------------------------------------------------------------
-- Events
--
-- RegisterEvent throws on an unknown name and is declared to return
-- registered:bool, so false is a refusal too. Every failure is printed:
-- a missing handler must not ship silently.
-- ------------------------------------------------------------

function API.RegisterEvents(frame, ...)
    local failed = {}
    for i = 1, select("#", ...) do
        local event = select(i, ...)
        local ok, registered = pcall(frame.RegisterEvent, frame, event)
        if not ok or registered == false then
            failed[#failed + 1] = event
        end
    end
    if #failed > 0 then
        print(PREFIX .. "this client rejected event(s): " .. table.concat(failed, ", "))
    end
    return #failed == 0, failed
end

-- Same, for events registered to one unit.
function API.RegisterUnitEvents(frame, unit, ...)
    local failed = {}
    for i = 1, select("#", ...) do
        local event = select(i, ...)
        local ok, registered = pcall(frame.RegisterUnitEvent, frame, event, unit)
        if not ok or registered == false then failed[#failed + 1] = event end
    end
    if #failed > 0 then
        print(PREFIX .. "this client rejected event(s): " .. table.concat(failed, ", "))
    end
    return #failed == 0, failed
end

-- ------------------------------------------------------------
-- Secure buttons
--
-- Register BOTH mouse edges. The client's secure handler acts only on
-- the edge where down == useOnKeyDown (attribute, else the
-- ActionButtonUseKeyDown CVar), so exactly one edge ever acts; a
-- single edge is a dead button for anyone on the other setting.
-- Never set "typerelease": the hold-release path reads it and would
-- use the item twice.
-- ------------------------------------------------------------

-- Weapons (#24). Plain values only; nil means unknown or none.
-- The WEAPON in an inventory slot (16 main hand, 17 off hand): its item
-- ID and weapon subclass, or nil for an empty slot, a shield or a held
-- off-hand item.
function API.HandWeapon(slot)
    -- One pcall around the whole read, and the secret check before any
    -- comparison: comparing a secret throws (Codex review of #26).
    local ok, id, sub = pcall(function()
        local id = GetInventoryItemID("player", slot)
        if issecretvalue and issecretvalue(id) then return nil end
        if id == nil then return nil end
        local _, _, _, _, _, classID, subClassID = C_Item.GetItemInfoInstant(id)
        if issecretvalue and (issecretvalue(classID) or issecretvalue(subClassID)) then return nil end
        if classID ~= 2 then return nil end
        return id, subClassID
    end)
    if not ok then return nil end
    return id, sub
end

-- Can the player use this item now? true / false, or nil when unknown.
-- (C_Item.IsUsableItem: false for a level, class or rune requirement.)
function API.ItemUsable(itemID)
    local ok, usable = pcall(C_Item.IsUsableItem, itemID)
    if not ok or (issecretvalue and issecretvalue(usable)) then return nil end
    return usable and true or false
end

-- Does this hand carry a temporary coating (poison, oil, stone)? true /
-- false, or nil when the read is refused or secret. Any coating counts:
-- which one is on is not measured yet (enchant IDs, #24).
function API.HandCoated(slot)
    local ok, has = pcall(function()
        local v = { GetWeaponEnchantInfo() }
        local h = v[slot == 17 and 5 or 1]
        if issecretvalue and issecretvalue(h) then return nil end
        return h and true or false
    end)
    if ok then return has end
    return nil
end

function API.ClickEdges()
    return "AnyUp", "AnyDown"
end

-- ------------------------------------------------------------
-- Action bars (#40)
-- ------------------------------------------------------------

-- The action bars by Edit Mode number: the bar frame and its first button.
-- All eight are measured on 70291 under Retail's names (/apo bar,
-- docs/FOREVER-PROBE.md).
API.ACTION_BARS = {
    { bar = "MainActionBar",       button = "ActionButton1" },
    { bar = "MultiBarBottomLeft",  button = "MultiBarBottomLeftButton1" },
    { bar = "MultiBarBottomRight", button = "MultiBarBottomRightButton1" },
    { bar = "MultiBarRight",       button = "MultiBarRightButton1" },
    { bar = "MultiBarLeft",        button = "MultiBarLeftButton1" },
    { bar = "MultiBar5",           button = "MultiBar5Button1" },
    { bar = "MultiBar6",           button = "MultiBar6Button1" },
    { bar = "MultiBar7",           button = "MultiBar7Button1" },
}

-- Action bar n's icon size and padding, in UIParent units: { size,
-- padding }, or nil if the client doesn't say. Measured on 70291 for bar 1
-- (docs/FOREVER-PROBE.md, /apo bar): its GetSettingValue returns plain
-- values (icon size in percent, padding in pixels) for presets and custom
-- layouts alike, including a change not yet saved while Edit Mode is open.
-- The stored layout encodes icon size as a step instead, so it is not read.
-- The first button stays 45 wide and the icon size scales it, padding
-- included: at 90% a button is 40.5 and the gap 1.8. Rows and orientation
-- are not read: Apotheca keeps its own.
local BAR_BUTTON = 45

function API.ActionBarLayout(n)
    local names = API.ACTION_BARS[n]
    if not names then return nil end
    local bar = _G[names.bar]
    local s = Enum.EditModeActionBarSetting
    if not (bar and bar.GetSettingValue and s) then return nil end
    local ok, size, pad = pcall(function()
        return bar:GetSettingValue(s.IconSize), bar:GetSettingValue(s.IconPadding)
    end)
    if not ok or type(size) ~= "number" or type(pad) ~= "number" or size <= 0 then
        return nil
    end
    -- The button's own effective scale is the size it is drawn at, wherever
    -- the client puts the icon scale (measured: on the button). Without a
    -- button, the percent times the bar's scale.
    local button = _G[names.button]
    local base, factor
    if button and button.GetEffectiveScale then
        base = button:GetWidth()
        factor = button:GetEffectiveScale() / UIParent:GetEffectiveScale()
    else
        base = BAR_BUTTON
        factor = size / 100 * bar:GetEffectiveScale() / UIParent:GetEffectiveScale()
    end
    return { size = base * factor, padding = pad * factor }
end

-- ------------------------------------------------------------
-- Client
-- ------------------------------------------------------------

function API.ClientBuild()
    return tonumber((select(2, GetBuildInfo())))
end
