------------------------------------------------------------
-- wow_stubs.lua
--
-- A minimal WoW: Forever API surface so Apotheca's files load and run
-- under stock Lua 5.1 with no game client.
--
-- The important rule: READING AN UNSTUBBED GLOBAL IS AN ERROR. This file is
-- the list of APIs verified present on build 1.60.1.69977
-- (C:\Projects\References\forever-api-1.60.1.69977.md). Stub a global only
-- after confirming it there, with the client's signature. Names the client
-- does NOT have go in KNOWN_ABSENT, so the addon has to cope without them.
-- A forgiving stub quietly certifies calls the client will reject.
--
-- Methods are NOT covered: unknown widget methods fall through to a no-op.
-- Assert what a handler produced, not only that it ran.
--
--     dofile("tests/wow_stubs.lua")   -- first, in every test
--     WoW.reset()
------------------------------------------------------------

WoW = {}
local WoW = WoW

WoW.frames = {}       -- every frame created, in order
WoW.events = {}       -- [frame] = { [event] = true }

------------------------------------------------------------
-- Secret values
--
-- On Forever, the player's current health and power are secret even out
-- of combat (docs/FOREVER-PROBE.md). A secret here is a table whose
-- arithmetic yields another secret and whose ORDERING comparison with a
-- number throws, which Lua 5.1 does by itself for table < number.
--
-- KNOWN GAP: the real client also throws on `secret == x` and on truth
-- tests (`if secret`, `secret or 0`). Lua 5.1 cannot model either: __eq is
-- ignored between a table and a number, and a table is always truthy. So
-- these tests cannot catch an equality or truth test on a secret. Review
-- for that by hand: every read of health, power, cooldowns, counts, auras
-- or GetWeaponEnchantInfo belongs inside a pcall together with every
-- comparison made on it.
------------------------------------------------------------

local secretMT = {}
-- A secret may carry the real value, hidden from the addon (it can only be
-- read through WoW.Reveal, i.e. by what the client would draw).
local hidden = setmetatable({}, { __mode = "k" })
local function Secret(v)
    local s = setmetatable({}, secretMT)
    hidden[s] = v
    return s
end
function WoW.Reveal(v)
    if getmetatable(v) == secretMT then return hidden[v] end
    return v
end
for _, op in ipairs({ "__add", "__sub", "__mul", "__div", "__unm" }) do
    secretMT[op] = function() return Secret() end
end
secretMT.__lt = function() error("attempt to compare a secret number value", 2) end
secretMT.__le = secretMT.__lt
WoW.Secret = Secret
function WoW.IsSecret(v) return getmetatable(v) == secretMT end

------------------------------------------------------------
-- State
------------------------------------------------------------

function WoW.reset()
    WoW.time         = 10000
    WoW.inCombat     = false
    WoW.build        = "69977"
    WoW.class        = "PRIEST"
    WoW.instanceName, WoW.instanceType, WoW.instanceMap = "Kalimdor", "none", 1
    WoW.health, WoW.healthMax = 1000, 1000
    WoW.power,  WoW.powerMax  = 1000, 1000
    WoW.healthSecret = true      -- measured: secret at rest on 69977
    WoW.aurasThrow   = false     -- combat: index reads throw
    WoW.combatSecret = false     -- cooldowns and stack counts secret (unmeasured; worst case)
    WoW.auras        = { HELPFUL = {}, HARMFUL = {} }
    WoW.bags         = {}        -- [bag] = { [slot] = { itemID=, stackCount= } }
    WoW.cooldowns    = {}        -- [itemID] = { start, duration }
    WoW.items        = {}        -- [itemID] = name; missing -> cache miss
    WoW.messages     = {}
    WoW.badEvents    = {}        -- RegisterEvent throws
    WoW.refusedEvents = {}       -- RegisterEvent returns false
    WoW.altDown      = false
    WoW.popups       = {}
    WoW.itemsUsed    = {}        -- names passed to C_Item.UseItemByName
    WoW.curvesRefused = false    -- simulate a client that refuses colour curves
end

function WoW.AddItem(bag, slot, itemID, count, name)
    WoW.bags[bag] = WoW.bags[bag] or {}
    WoW.bags[bag][slot] = { itemID = itemID, stackCount = count or 1 }
    WoW.items[itemID] = name or ("Item " .. itemID)
end

function WoW.SetAura(filter, name, spellId)
    local list = WoW.auras[filter]
    list[#list + 1] = { name = name, spellId = spellId }
end

------------------------------------------------------------
-- Frames
------------------------------------------------------------

local Frame = {}
local FrameMT = {
    __index = function(_, k)
        local m = Frame[k]
        if m then return m end
        -- Unknown METHODS (capitalised, like the client's) are no-ops; see
        -- the header. Unknown fields stay nil, as on a real frame.
        if type(k) == "string" and k:match("^%u") then return function() end end
        return nil
    end,
}

local function NewRegion(kind, parent, name)
    local f = setmetatable({
        _kind = kind, _parent = parent, _name = name, _shown = true,
        _attrs = {}, _scripts = {}, _points = {}, _level = 1,
        _w = 36, _h = 36,
    }, FrameMT)
    return f
end

function Frame:GetName() return self._name end
function Frame:GetParent() return self._parent end
function Frame:Show() self._shown = true end
function Frame:Hide() self._shown = false end
function Frame:SetShown(v) self._shown = v and true or false end
function Frame:IsShown() return self._shown end
function Frame:IsVisible() return self._shown end
function Frame:SetScript(event, fn) self._scripts[event] = fn end
function Frame:GetScript(event) return self._scripts[event] end
function Frame:HookScript(event, fn)
    local old = self._scripts[event]
    self._scripts[event] = function(...) if old then old(...) end fn(...) end
end
function Frame:SetAttribute(k, v) self._attrs[k] = v end
function Frame:GetAttribute(k) return self._attrs[k] end
function Frame:RegisterForClicks(...) self._clicks = { ... } end
function Frame:RegisterEvent(event)
    if WoW.badEvents[event] then
        error("Attempt to register unknown event \"" .. event .. "\"", 2)
    end
    if WoW.refusedEvents[event] then return false end
    WoW.events[self] = WoW.events[self] or {}
    WoW.events[self][event] = true
    return true
end
function Frame:RegisterUnitEvent(event) return Frame.RegisterEvent(self, event) end
function Frame:UnregisterEvent(event)
    if WoW.events[self] then WoW.events[self][event] = nil end
end
function Frame:SetWidth(w) self._w = w end
function Frame:SetHeight(h) self._h = h end
function Frame:SetSize(w, h) self._w, self._h = w, h end
function Frame:GetWidth() return self._w end
function Frame:GetHeight() return self._h end
function Frame:GetSize() return self._w, self._h end
function Frame:GetLeft() return 600 end
function Frame:GetBottom() return 200 end
function Frame:GetCenter() return 960, 540 end
function Frame:GetEffectiveScale() return 1 end
function Frame:GetScale() return 1 end
function Frame:SetFrameLevel(l) self._level = l end
function Frame:GetFrameLevel() return self._level end
function Frame:IsMouseOver() return false end
function Frame:IsProtected() return false end
function Frame:GetChecked() return self._checked end
function Frame:SetChecked(v) self._checked = v end
function Frame:GetValue() return self._value or 0 end
function Frame:SetValue(v) self._value = v end
function Frame:GetMinMaxValues() return 0, 1 end
function Frame:GetStringWidth() return 50 end
function Frame:GetStringHeight() return 12 end
function Frame:GetText() return self._text end
function Frame:SetText(t) self._text = t end
function Frame:GetID() return 1 end
function Frame:IsPlaying() return false end
function Frame:GetNumPoints() return #self._points end
function Frame:SetPoint(...) self._points[#self._points + 1] = { ... } end
function Frame:ClearAllPoints() self._points = {} end
function Frame:GetPoint() return "CENTER", nil, "CENTER", 0, 0 end
function Frame:GetFontString() return self._fs end
-- Records what the texture would be drawn with: a secret channel is
-- unwrapped here, as the client does, never by the addon.
function Frame:SetVertexColor(r, g, b)
    self._vertex = { r, g, b }
    self._drawn = { WoW.Reveal(r), WoW.Reveal(g), WoW.Reveal(b) }
end

local function childRegion(self, kind)
    return NewRegion(kind, self)
end
function Frame:CreateTexture() return childRegion(self, "Texture") end
function Frame:CreateFontString() return childRegion(self, "FontString") end
function Frame:CreateAnimationGroup() return childRegion(self, "AnimationGroup") end
function Frame:CreateAnimation(t) return childRegion(self, t or "Animation") end

-- Templates measured present on this build bring these regions.
local TEMPLATE_REGIONS = {
    InterfaceOptionsCheckButtonTemplate = { "Text" },
    UICheckButtonTemplate               = { "Text" },
    UIPanelButtonTemplate               = { "Text" },
    UIDropDownMenuTemplate              = { "Text" },
    OptionsSliderTemplate               = { "Low", "High", "Text" },
}

function CreateFrame(kind, name, parent, template)
    local f = NewRegion(kind, parent, name)
    f._template = template
    for tpl in tostring(template or ""):gmatch("[^,%s]+") do
        for _, region in ipairs(TEMPLATE_REGIONS[tpl] or {}) do
            local r = NewRegion("FontString", f)
            f[region] = r
            if name then _G[name .. region] = r end
        end
    end
    if kind == "Button" or kind == "CheckButton" then f._fs = NewRegion("FontString", f) end
    if name then _G[name] = f end
    WoW.frames[#WoW.frames + 1] = f
    return f
end

UIParent = NewRegion("Frame", nil, "UIParent")
GameTooltip = NewRegion("GameTooltip", UIParent, "GameTooltip")
GameFontNormal, GameFontHighlight = {}, {}

------------------------------------------------------------
-- Dispatch helpers
------------------------------------------------------------

function WoW.fire(event, ...)
    for frame, evs in pairs(WoW.events) do
        if evs[event] then
            local h = frame._scripts.OnEvent
            if h then h(frame, event, ...) end
        end
    end
end

-- Run every OnUpdate handler once, as if `elapsed` seconds had passed.
function WoW.tick(elapsed)
    WoW.time = WoW.time + (elapsed or 1)
    for _, f in ipairs(WoW.frames) do
        local h = f._scripts.OnUpdate
        if h then h(f, elapsed or 1) end
    end
end

function WoW.enterCombat()
    WoW.inCombat, WoW.aurasThrow = true, true
    WoW.fire("PLAYER_REGEN_DISABLED")
end

function WoW.leaveCombat()
    WoW.inCombat, WoW.aurasThrow = false, false
    WoW.fire("PLAYER_REGEN_ENABLED")
end

------------------------------------------------------------
-- Globals present on 1.60.1.69977
------------------------------------------------------------

function print(...)
    local t = {}
    for i = 1, select("#", ...) do t[i] = tostring(select(i, ...)) end
    WoW.messages[#WoW.messages + 1] = table.concat(t, " ")
end

function time() return math.floor(WoW.time) end
function GetTime() return WoW.time end
function InCombatLockdown() return WoW.inCombat end
function IsAltKeyDown() return WoW.altDown end
function GetBuildInfo() return "1.60.1", WoW.build, "Sep 22 2026", 16001 end
function GetRealmName() return "ClassicBetaPvE" end
function UnitName() return "Testcase Surname", nil end
function UnitClass() return WoW.class:sub(1, 1) .. WoW.class:sub(2):lower(), WoW.class, 5 end
-- Outdoors this client returns the CONTINENT, not an empty name.
function GetInstanceInfo() return WoW.instanceName, WoW.instanceType, 0, "", 0, 0, false, WoW.instanceMap end
function GetWeaponEnchantInfo() return false, nil, nil, nil, false, nil, nil, nil, false end

local function maybeSecret(v) if WoW.healthSecret then return Secret() end return v end
function UnitHealth()    return maybeSecret(WoW.health) end
function UnitHealthMax() return WoW.healthMax end
function UnitPower()     return maybeSecret(WoW.power) end
function UnitPowerMax()  return WoW.powerMax end
function issecretvalue(v) return WoW.IsSecret(v) end

NUM_BAG_SLOTS = 4
Enum = { BagIndex = { Backpack = 0, ReagentBag = 5 }, PowerType = { Mana = 0 } }

C_Container = {}
function C_Container.GetContainerNumSlots(bag)
    local b = WoW.bags[bag]
    if not b then return 0 end
    local n = 0
    for slot in pairs(b) do if slot > n then n = slot end end
    return n
end
function C_Container.GetContainerItemID(bag, slot)
    local s = WoW.bags[bag] and WoW.bags[bag][slot]
    return s and s.itemID
end
function C_Container.GetContainerItemInfo(bag, slot)
    local s = WoW.bags[bag] and WoW.bags[bag][slot]
    if not s then return nil end
    local count = WoW.combatSecret and Secret() or s.stackCount
    return { itemID = s.itemID, stackCount = count, hyperlink = "item:" .. s.itemID }
end
function C_Container.GetItemCooldown(itemID)
    if WoW.combatSecret then return Secret(), Secret(), 1 end
    local c = WoW.cooldowns[itemID]
    if c then return c[1], c[2], 1 end
    return 0, 0, 1
end

C_Item = {}
-- Cache miss returns NO values, not nil.
function C_Item.GetItemInfo(itemID)
    local name = WoW.items[itemID]
    if not name then return end
    return name, "item:" .. itemID, 1, 1, 1, "Consumable", "Potion", 20, "", 134400
end
function C_Item.GetItemIconByID(itemID) return WoW.items[itemID] and 134400 or nil end
function C_Item.GetItemCount(itemID) return 0 end
function C_Item.UseItemByName(name) WoW.itemsUsed[#WoW.itemsUsed + 1] = name end
-- Reads the client's item DB: answers for any known ID, cache or not.
function C_Item.GetItemInfoInstant(itemID)
    if not WoW.items[itemID] then return nil end
    return itemID, "Consumable", "Food & Drink", "", 134400, 0, 5
end
function C_Item.RequestLoadItemDataByID() end
function C_Item.GetItemSpell(itemID)
    if WoW.items[itemID] then return "Food", 433 end
end

C_Spell = C_Spell or {}
function C_Spell.RequestLoadSpellData() end
-- Localized buff names by spell ID; tests install entries to simulate a
-- buff whose aura spell ID differs from the item's spell.
WoW.spellNames = {}
function C_Spell.GetSpellName(spellID) return WoW.spellNames[spellID] end
function C_Spell.GetSpellDescription(spellID)
    if spellID == 433 then return "Restores 61 health over 18 sec." end
    return ""
end

C_TooltipInfo = {}
function C_TooltipInfo.GetItemByID(itemID)
    local name = WoW.items[itemID]
    if not name then return nil end
    return { lines = { { leftText = name }, { leftText = "Use: Restores 61 health over 18 sec." } } }
end

C_UnitAuras = {}
function C_UnitAuras.GetAuraDataByIndex(unit, index, filter)
    if WoW.aurasThrow then
        error("Auras cannot be accessed when secret while tainted by 'Apotheca'", 2)
    end
    return WoW.auras[filter or "HELPFUL"][index]
end

C_AddOns = {}
function C_AddOns.GetAddOnMetadata(_, field) if field == "Version" then return "dev" end end

C_CVar = {}
function C_CVar.GetCVar() return "1" end

C_Secrets = {}
function C_Secrets.ShouldAurasBeSecret() return WoW.inCombat end
function C_Secrets.ShouldCooldownsBeSecret() return false end
function C_Secrets.ShouldUnitHealthMaxBeSecret() return false end
function C_Secrets.ShouldUnitPowerBeSecret() return WoW.healthSecret end

-- Role sources (#9). Solo by default: no group, no assigned role, and an
-- empty role selector.
function IsInGroup() return WoW.inGroup or false end
function IsInRaid() return WoW.inRaid or false end
function UnitGroupRolesAssigned() return WoW.assignedRole or "NONE" end
function GetLFGRoles()
    local r = WoW.lfgRoles or {}
    return false, r.tank or false, r.healer or false, r.damage or false
end
C_LFGListRoles = {}
function C_LFGListRoles.GetRoles()
    local r = WoW.lfgRoles or {}
    return { tank = r.tank or false, healer = r.healer or false, dps = r.damage or false }
end
-- Saved roles can differ from the current ones (WoW.lfgSavedRoles).
function C_LFGListRoles.GetSavedRoles()
    local r = WoW.lfgSavedRoles or WoW.lfgRoles or {}
    return { tank = r.tank or false, healer = r.healer or false, dps = r.damage or false }
end
function UnitPowerType() return 0, "MANA" end
function GetInventoryItemID(_, slot) return WoW.equipped and WoW.equipped[slot] end

C_SpecializationInfo = {}
function C_SpecializationInfo.GetSpecialization() return 1 end
function C_SpecializationInfo.GetSpecializationInfo() return 1487, "Priest", "", 626004, "DAMAGER" end
function C_SpecializationInfo.GetNumSpecializationsForClassID() return 1 end

-- UnitHealthMissing / UnitHealthPercent etc. return secrets like UnitHealth.
-- Given a colour CURVE, the Percent functions evaluate it inside the client
-- and return a colour; the stub evaluates it on the true percentage, and
-- hands back secret channels when health is secret, as the client may.
function UnitHealthMissing() return Secret() end
function UnitPowerMissing() return Secret() end

local function curveColor(curve, pct)
    local r, g, b = curve:_eval(pct)
    if WoW.healthSecret then r, g, b = Secret(r), Secret(g), Secret(b) end
    return { GetRGB = function() return r, g, b end }
end
-- usePredicted: WoW.incomingHeal counts only when predicted is asked for.
function UnitHealthPercent(_, usePredicted, curve)
    if not curve then return Secret() end
    if WoW.curvesRefused then error("curve refused") end
    local h = WoW.health
    if usePredicted ~= false then h = math.min(WoW.healthMax, h + (WoW.incomingHeal or 0)) end
    WoW.lastPredicted = usePredicted
    return curveColor(curve, h / WoW.healthMax)
end
function UnitPowerPercent(_, _, _, curve)
    if not curve then return Secret() end
    if WoW.curvesRefused then error("curve refused") end
    return curveColor(curve, WoW.power / WoW.powerMax)
end

-- A linear colour curve, evaluated the way the client does.
function CreateColor(r, g, b, a) return { r = r, g = g, b = b, a = a } end
C_CurveUtil = {}
function C_CurveUtil.CreateColorCurve()
    local pts = {}
    local c = {}
    function c:AddPoint(x, color) pts[#pts + 1] = { x = x, c = color } ; table.sort(pts, function(p, q) return p.x < q.x end) end
    function c:_eval(x)
        if x <= pts[1].x then local k = pts[1].c return k.r, k.g, k.b end
        for i = 2, #pts do
            local a, b = pts[i - 1], pts[i]
            if x <= b.x then
                local t = (x - a.x) / (b.x - a.x)
                return a.c.r + (b.c.r - a.c.r) * t, a.c.g + (b.c.g - a.c.g) * t, a.c.b + (b.c.b - a.c.b) * t
            end
        end
        local k = pts[#pts].c
        return k.r, k.g, k.b
    end
    return c
end

Settings = {}
function Settings.RegisterCanvasLayoutCategory(panel, name)
    return { GetID = function() return 1 end, name = name }
end
function Settings.RegisterAddOnCategory() end
function Settings.OpenToCategory() end

StaticPopupDialogs = {}
function StaticPopup_Show(which, a, b, data)
    WoW.popups[#WoW.popups + 1] = { which = which, a = a, b = b, data = data }
    return { data = data }
end

SlashCmdList = {}

function UIDropDownMenu_SetWidth() end
function UIDropDownMenu_Initialize(dd, fn) dd._init = fn end
function UIDropDownMenu_CreateInfo() return {} end
function UIDropDownMenu_AddButton() end
function UIDropDownMenu_SetText(dd, t) dd._ddText = t end

------------------------------------------------------------
-- Strict globals
------------------------------------------------------------

-- Names the client does not have, or that start nil. Reading one returns
-- nil instead of failing the test, so guarded feature checks still run.
local KNOWN_ABSENT = {
    -- Removed on Forever (forever-api-1.60.1.69977.md).
    AnimateTexCoords = true, InterfaceOptions_AddCategory = true,
    InterfaceOptionsFrame_OpenToCategory = true, GetItemInfo = true,
    GetItemIcon = true, UnitBuff = true, UnitDebuff = true, UnitAura = true,
    GetTalentTabInfo = true, GetNumTalentTabs = true, UseItemByName = true,
    MouseIsOver = true, GetContainerNumSlots = true, GetContainerItemLink = true,
    GetContainerItemInfo = true, GetItemCooldown = true, MAX_PLAYER_LEVEL = true,
    -- SavedVariables, nil until the client would have loaded them.
    ApothecaDB = true, ApothecaCharDB = true,
    -- The addon namespace, nil until ApothecaCompat.lua creates it.
    Apotheca = true,
    -- Frames the addon names itself; nil until created.
    ApothecaFrame = true, ApothecaAnchor = true,
}
WoW.KNOWN_ABSENT = KNOWN_ABSENT

setmetatable(_G, {
    __index = function(_, k)
        if KNOWN_ABSENT[k] then return nil end
        error("read of undefined global '" .. tostring(k) .. "': stub it only if "
              .. "forever-api-1.60.1.69977.md confirms it exists, or list it in KNOWN_ABSENT", 2)
    end,
})

WoW.reset()
