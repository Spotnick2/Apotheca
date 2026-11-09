------------------------------------------------------------
-- wow_stubs.lua: Apotheca's WoW: Forever mock for Lua 5.1 unit tests.
-- dofile("tests/wow_stubs.lua") FIRST in every test; drive it via the WoW table.
--
-- The mechanics come from WowTestKit (tests/kit.lua loads the commit
-- tests/kit.pin names; its README is the reference): strict globals, secrets,
-- event names checked against the pinned build, widgets that record every
-- method called, protected frames refused in combat, print (with the
-- stray-"|" check done() fails on), timers and the clock, fire /
-- fireAllRegistered / tick, check / eq / done.
--
-- This file adds Apotheca's own client APIs, each verified in the API dump
-- (C:\Projects\WoW\References\Forever\api\, the highest build). Stub a global
-- only after confirming it there, with the client's signature. A name the
-- client does NOT have goes in the Kit.strict list at the bottom, so the
-- addon has to cope without it. A forgiving stub quietly certifies calls the
-- client will reject.
------------------------------------------------------------

dofile("tests/kit.lua")
local Methods = WoW.Methods
local newWidget = WoW.newWidget

------------------------------------------------------------
-- Secrets
--
-- On Forever, the player's current health and power are secret even out
-- of combat (docs/FOREVER-PROBE.md). The kit's secrets throw on arithmetic,
-- ordering, concat, tostring and indexing. Lua 5.1 cannot make `secret == x`
-- or a truth test throw: review those by hand.
------------------------------------------------------------

-- A secret may carry the real value, hidden from the addon: only what the
-- client draws reads it (WoW.Reveal, the texture's _drawn colour).
local hidden = setmetatable({}, { __mode = "k" })
local kitSecret = WoW.Secret
local function Secret(v)
    local s = kitSecret("Apotheca test secret")
    hidden[s] = v
    return s
end
WoW.Secret = Secret
function WoW.Reveal(v)
    if issecretvalue(v) then return hidden[v] end
    return v
end
function WoW.IsSecret(v) return issecretvalue(v) end

-- WowTestKit #13: the client writes every blocked attempt on a secret to
-- Logs/taint.log, even when a pcall catches it. Count each one a pcall
-- swallowed (WoW.secretBlocked), and fail done() on one, as the old mock did:
-- code that tests issecretvalue first never gets there. Lua 5.1 refuses
-- `secret > 0` before any metamethod runs, with its own message.
local rawpcall = pcall
local function counted(ok, ...)
    local err = ...
    if not ok and type(err) == "string" and (err:find("secret value touched in Lua", 1, true)
            or err:find("attempt to compare %a+ with userdata") or err:find("attempt to compare userdata with")) then
        WoW.secretBlocked = WoW.secretBlocked + 1
    end
    return ok, ...
end
function pcall(f, ...) return counted(rawpcall(f, ...)) end
local kitDone = done
function done(name)
    eq(WoW.secretBlocked, 0, "no arithmetic or comparison was attempted on a secret")
    kitDone(name)
end

------------------------------------------------------------
-- Templates
------------------------------------------------------------

-- Templates measured present on this build bring these regions (a named
-- frame's also as <name><Region> globals, as the client's $parent names do).
local TEMPLATE_REGIONS = {
    InterfaceOptionsCheckButtonTemplate = { "Text" },
    UICheckButtonTemplate               = { "Text" },
    UIPanelButtonTemplate               = { "Text" },
    UIDropDownMenuTemplate              = { "Text" },
    OptionsSliderTemplate               = { "Low", "High", "Text" },
}
for template, regions in pairs(TEMPLATE_REGIONS) do
    WoW.templates[template] = function(w)
        for _, region in ipairs(regions) do
            local r = Methods.CreateFontString(w)
            w[region] = r
            if w._name then rawset(_G, w._name .. region, r) end
        end
    end
end
-- A secure button and the frame that parents it are protected: in combat
-- the client refuses to change them.
WoW.templates.SecureActionButtonTemplate = function(w)
    w._protected = true
    if w._parent then w._parent._protected = true end
end

------------------------------------------------------------
-- Widget methods the kit's core doesn't have (each a real method of that
-- widget type on this build: Kit.checkMethods checks every call)
------------------------------------------------------------

-- Screen geometry: tests place a frame with _left / _bottom / _top (false
-- reads as nil, a frame with no position yet).
function Methods.GetLeft(w) if w._left == false then return nil end return w._left or 600 end
function Methods.GetBottom(w) if w._bottom == false then return nil end return w._bottom or 200 end
function Methods.GetTop(w) if w._top == false then return nil end return w._top or 500 end
function Methods.GetSize(w) return w._width, w._height end
function Methods.GetCenter() return 960, 540 end
function Methods.GetEffectiveScale() return 1 end
-- A frame's own scale (the wheel's opening animation, #94); 1 unless set.
-- An animation's SetScale(x, y) is another widget type: kept apart.
function Methods.SetScale(w, s, ...) if select('#', ...) == 0 then w._scale = s end end
function Methods.GetScale(w) return w._scale or 1 end
function Methods.GetTexture(t) return t._file end
function Methods.GetNumPoints(w) return #w._points end
function Methods.IsMouseOver(w) return w._mouseOver == true end
function Methods.StartMoving(w) w._moving = true end
function Methods.StopMovingOrSizing(w) w._moving = false end
function Methods.GetVerticalScroll(w) return w._vscroll or 0 end
function Methods.GetVerticalScrollRange(w) return w._vrange or 0 end
function Methods.SetVerticalScroll(w, v) w._vscroll = v end
function Methods.GetMinMaxValues(w) return w._min or 0, w._max or 1 end
function Methods.GetStringWidth() return 50 end
function Methods.GetStringHeight() return 12 end
function Methods.GetID() return 1 end
function Methods.IsDesaturated(t) return t._desaturated == true end
-- A button's own font string (its label), made on first ask.
function Methods.GetFontString(b)
    b._fs = b._fs or newWidget("FontString", b)
    return b._fs
end
function Methods.RegisterForClicks(b, ...) b._clicks = { ... } end
-- Every font string made, in order (WoW.fontStrings): the tests find a
-- label, a note or an options row by its text.
local kitFontString = Methods.CreateFontString
function Methods.CreateFontString(w, ...)
    local fs = kitFontString(w, ...)
    WoW.fontStrings[#WoW.fontStrings + 1] = fs
    return fs
end
-- Records what the texture would be drawn with: a secret channel is
-- unwrapped here, as the client does, never by the addon (test_tint reads
-- _drawn).
function Methods.SetVertexColor(t, r, g, b, a)
    t._vertex = { r, g, b, a }
    t._drawn = { WoW.Reveal(r), WoW.Reveal(g), WoW.Reveal(b) }
end
-- Events: the core's check of the name against the build, plus two refusals
-- the tests simulate: WoW.badEvents throws, WoW.refusedEvents returns false
-- (Apotheca.API.RegisterEvents must report both).
local kitRegister = Methods.RegisterEvent
function Methods.RegisterEvent(w, e)
    if WoW.badEvents[e] then error("Attempt to register unknown event \"" .. tostring(e) .. "\"", 2) end
    if WoW.refusedEvents[e] then return false end
    return kitRegister(w, e)
end
function Methods.RegisterUnitEvent(w, e) return Methods.RegisterEvent(w, e) end

-- Protected frames in combat. The core refuses Show / Hide / SetShown /
-- SetPoint / ClearAllPoints / SetAllPoints and records each in WoW.blocked.
-- WowTestKit #12: it drops SetAttribute silently and doesn't refuse
-- resizing or moving, which the client does (StopMovingOrSizing measured on
-- the bar, AGENTS.md "Drag Anchor"); refused and recorded here meanwhile.
-- WoW.strictLockdown (opt-in per test section) turns any of them into an
-- error at the call, which fails the test where it happened.
local CORE_REFUSES = { Show = true, Hide = true, SetPoint = true, ClearAllPoints = true, SetAllPoints = true }
for _, m in ipairs({ "Show", "Hide", "SetPoint", "ClearAllPoints", "SetAllPoints", "SetAttribute",
                     "SetWidth", "SetHeight", "SetSize", "StartMoving", "StopMovingOrSizing", "SetClampedToScreen" }) do
    local plain = Methods[m]
    Methods[m] = function(w, ...)
        if WoW.combat and w._protected then
            if WoW.strictLockdown then
                error("protected " .. m .. " on " .. tostring(w._name) .. " in combat", 2)
            end
            if not CORE_REFUSES[m] then
                table.insert(WoW.blocked, (w._name or w._type) .. ":" .. m)
                return
            end
        end
        if plain then return plain(w, ...) end
    end
end

-- WowTestKit #21: on the client, OnShow / OnHide also fire on each shown
-- descendant whose visibility changes with its parent's (the wheel's art is
-- an insecure child of the ring a snippet shows and hides). The core runs
-- only the frame's own; propagated here meanwhile.
local function fireDown(w, script)
    for _, c in ipairs(w._children or {}) do
        if c._shown then
            if c._scripts[script] then c._scripts[script](c) end
            fireDown(c, script)
        end
    end
end
local guardedShow, guardedHide = Methods.Show, Methods.Hide
function Methods.Show(w, ...)
    local was = Methods.IsVisible(w)
    guardedShow(w, ...)
    if not was and Methods.IsVisible(w) then fireDown(w, "OnShow") end
end
function Methods.Hide(w, ...)
    local was = Methods.IsVisible(w)
    guardedHide(w, ...)
    if was and not Methods.IsVisible(w) then fireDown(w, "OnHide") end
end

------------------------------------------------------------
-- WowTestKit #20: secure handlers (the Mage Scrolls wheel, #94)
--
-- The core has none. This is the subset the wheel uses, from the client's
-- own source (wow-ui-source, Blizzard_RestrictedAddOnEnvironment):
-- SecureHandlerWrapScript on OnClick (Wrapped_Click, SecureHandlers.lua:272),
-- SecureHandlerSetFrameRef, one environment per header, handles with the
-- methods below (RestrictedFrames.lua), and WoW.click to drive a click.
-- A snippet may change protected frames in combat: that's the point.
------------------------------------------------------------

for _, t in ipairs({ "SecureHandlerBaseTemplate", "SecureFrameTemplate" }) do
    WoW.templates[t] = function(w) w._protected = true end
end

-- What a snippet sees besides its handles: no insecure global.
local RESTRICTED = { math = math, string = string, table = table, type = type, tostring = tostring,
                     tonumber = tonumber, select = select, pairs = pairs, ipairs = ipairs }
local function envOf(w)
    w._secureEnv = w._secureEnv or setmetatable({}, { __index = RESTRICTED })
    return w._secureEnv
end

local handles = setmetatable({}, { __mode = "k" })
local HANDLE = {}
HANDLE.__index = HANDLE
local function handle(w)
    if not w then return nil end
    local h = handles[w]
    if not h then
        h = setmetatable({ _frame = w }, HANDLE)
        handles[w] = h
    end
    return h
end
local function frameOf(h) return type(h) == "table" and rawget(h, "_frame") or h end

-- Run a snippet as the client does: `owner` the header's handle, then the
-- signature's names, in the header's environment.
local function runSnippet(header, w, names, body, ...)
    local chunk = assert(loadstring("local owner, " .. names .. " = ...\n" .. body, "snippet"))
    setfenv(chunk, envOf(header))
    return chunk(handle(header), handle(w), ...)
end

-- Shown and hidden from secure code: allowed in combat, never refused.
local function secureShow(w)
    local was = Methods.IsVisible(w)
    w._shown = true
    if not was and Methods.IsVisible(w) then
        if w._scripts.OnShow then w._scripts.OnShow(w) end
        fireDown(w, "OnShow")
    end
end
local function secureHide(w)
    local was = Methods.IsVisible(w)
    w._shown = false
    if was then
        if w._scripts.OnHide then w._scripts.OnHide(w) end
        fireDown(w, "OnHide")
    end
end

function HANDLE:GetAttribute(k) return Methods.GetAttribute(self._frame, k) end
function HANDLE:SetAttribute(k, v)
    local w = self._frame
    w._attrs = w._attrs or {}
    w._attrs[k] = v
end
function HANDLE:Show() secureShow(self._frame) end
function HANDLE:Hide() secureHide(self._frame) end
function HANDLE:IsShown() return self._frame._shown end
function HANDLE:ClearAllPoints() self._frame._points = {} end
function HANDLE:SetPoint(p, rel, rp, x, y) table.insert(self._frame._points, { p, frameOf(rel), rp, x, y }) end
function HANDLE:GetWidth() return self._frame._width end
function HANDLE:GetHeight() return self._frame._height end
-- The cursor as a fraction of the frame's rect, nil outside it
-- (RestrictedFrames.lua:307). The rect: _left / _bottom (0 if unset),
-- _width / _height; effective scale 1.
function HANDLE:GetMousePosition()
    local w = self._frame
    local l, b, wd, ht = w._left or 0, w._bottom or 0, w._width, w._height
    if not wd or not ht or wd == 0 or ht == 0 then return nil end
    local x, y = GetCursorPosition()
    x, y = x - l, y - b
    if x < 0 or x > wd or y < 0 or y > ht then return nil end
    return x / wd, y / ht
end
function HANDLE:GetFrameRef(name) return handle(self._frame._frameRefs and self._frame._frameRefs[name]) end
function HANDLE:RunAttribute(name, ...)
    local body = Methods.GetAttribute(self._frame, name)
    if type(body) ~= "string" then error("RunAttribute: no snippet in " .. tostring(name), 2) end
    return runSnippet(self._frame, self._frame, "self", body, ...)
end
-- Override bindings owned by the frame (WoW.overrideBindings, as
-- SetOverrideBindingClick's).
function HANDLE:SetBindingClick(_, key, name, button)
    WoW.overrideBindings[key] = name .. ":" .. (button or "LeftButton")
    WoW.bindingOwners[key] = self._frame
end
function HANDLE:ClearBindings()
    for key, owner in pairs(WoW.bindingOwners) do
        if owner == self._frame then WoW.overrideBindings[key], WoW.bindingOwners[key] = nil, nil end
    end
end

function SecureHandlerSetFrameRef(header, name, frame)
    header._frameRefs = header._frameRefs or {}
    header._frameRefs[name] = frame
end
function SecureHandlerWrapScript(frame, script, header, pre, post)
    if script ~= "OnClick" then error("the stub wraps OnClick only: " .. tostring(script), 2) end
    frame._wraps = frame._wraps or {}
    table.insert(frame._wraps, { header = header, pre = pre, post = post })
end

-- The button's own secure action: it acts only on the edge where down ==
-- useOnKeyDown (the attribute, else ActionButtonUseKeyDown: WoW.useKeyDown;
-- measured, AGENTS.md). An item is recorded in WoW.secureActions.
local function secureAction(b, down)
    local attrs = b._attrs or {}
    local onDown = attrs.useOnKeyDown
    if onDown == nil then onDown = WoW.useKeyDown end
    if down ~= (onDown and true or false) then return end
    if attrs.type == "item" then
        table.insert(WoW.secureActions, { button = b._name, item = attrs.item, targetSlot = attrs["target-slot"] })
    end
end
-- Wrapped_Click: the newest wrap outermost, each around the next.
local function clickWrapped(b, i, mouse, down)
    local wrap = b._wraps and b._wraps[i]
    if not wrap then return secureAction(b, down) end
    local newbutton, message
    if not WoW.combat or b._protected then
        newbutton, message = runSnippet(wrap.header, b, "self, button, down", wrap.pre, mouse, down)
        if newbutton == false then return end
        if newbutton then mouse = tostring(newbutton) end
    end
    clickWrapped(b, i - 1, mouse, down)
    if wrap.post and message ~= nil then
        runSnippet(wrap.header, b, "self, message, button, down", wrap.post, message, mouse, down)
    end
end
-- One edge of a click or key press on a button, as the client runs it.
function WoW.click(b, mouse, down)
    mouse, down = mouse or "LeftButton", down and true or false
    if b._scripts.PreClick then b._scripts.PreClick(b, mouse, down) end
    clickWrapped(b, b._wraps and #b._wraps or 0, mouse, down)
    if b._scripts.PostClick then b._scripts.PostClick(b, mouse, down) end
end
-- A key binding clicks the button it names (CLICK <name>:<button>), hidden or not.
function WoW.pressKey(key, down)
    local action = WoW.overrideBindings[key]
    if not action then return false end
    local name, mouse = action:match("^(.-):(.+)$")
    WoW.click(_G[name], mouse, down)
    return true
end

------------------------------------------------------------
-- State the tests reset
------------------------------------------------------------

table.insert(WoW.onReset, function()
    WoW.now          = 10000     -- the client's clock is never near 0
    WoW.build        = "70790"
    WoW.class        = "PRIEST"
    WoW.instanceName, WoW.instanceType, WoW.instanceMap = "Kalimdor", "none", 1
    WoW.health, WoW.healthMax = 1000, 1000
    WoW.power,  WoW.powerMax  = 1000, 1000
    WoW.healthSecret = true      -- measured: secret at rest on 69977 and 70009
    WoW.aurasThrow   = false     -- combat: index reads throw
    WoW.combatSecret = false     -- cooldowns and stack counts secret (unmeasured; worst case)
    WoW.auras        = { HELPFUL = {}, HARMFUL = {} }
    WoW.bags         = {}        -- [bag] = { [slot] = { itemID=, stackCount= } }
    WoW.cooldowns    = {}        -- [itemID] = { start, duration }
    WoW.items        = {}        -- [itemID] = name; missing -> cache miss
    WoW.badEvents    = {}        -- RegisterEvent throws
    WoW.refusedEvents = {}       -- RegisterEvent returns false
    WoW.altDown      = false
    WoW.popups       = {}
    WoW.itemsUsed    = {}        -- names passed to C_Item.UseItemByName
    WoW.curvesRefused = false    -- simulate a client that refuses colour curves
    WoW.strictLockdown = false   -- protected frames changed in combat fail the test
    WoW.secretBlocked = 0        -- blocked secret operations a pcall swallowed (taint.log lines)
    WoW.fontStrings  = {}
    WoW.secureActions = {}       -- secure item uses (WowTestKit #20 meanwhile)
    WoW.bindingOwners = {}       -- [key] = the frame whose snippet set it
    WoW.useKeyDown   = true      -- ActionButtonUseKeyDown, the client's default
end)

function WoW.AddItem(bag, slot, itemID, count, name)
    WoW.bags[bag] = WoW.bags[bag] or {}
    WoW.bags[bag][slot] = { itemID = itemID, stackCount = count or 1 }
    WoW.items[itemID] = name or ("Item " .. itemID)
end

function WoW.SetAura(filter, name, spellId)
    local list = WoW.auras[filter]
    list[#list + 1] = { name = name, spellId = spellId }
end

-- As on Retail: PLAYER_REGEN_DISABLED fires just before lockdown engages
-- (the last moment a protected frame may change), then combat is on.
-- WoW.enterLockdown skips that moment, for code that must cope with
-- lockdown already being on.
function WoW.enterCombat()
    WoW.aurasThrow = true
    WoW.fire("PLAYER_REGEN_DISABLED")
    WoW.combat = true
end

function WoW.enterLockdown()
    WoW.combat, WoW.aurasThrow = true, true
    WoW.fire("PLAYER_REGEN_DISABLED")
end

function WoW.leaveCombat()
    WoW.combat, WoW.aurasThrow = false, false
    WoW.fire("PLAYER_REGEN_ENABLED")
end

-- WowTestKit #9: the core's WoW.tick doesn't move GetTime. One step of the
-- game: the clock (and any timer due) moves on by `elapsed` seconds, then
-- every visible frame's OnUpdate runs with it.
function WoW.step(elapsed)
    elapsed = elapsed or 1
    WoW.advance(elapsed)
    WoW.tick(elapsed)
end

------------------------------------------------------------
-- Frames the client makes
------------------------------------------------------------

-- The action bars (#40): frames, so not in the API dump. Bar 1 is measured
-- on 70291 (/fp apo bar): MainActionBar's GetSettingValue returns plain values
-- (icon size in percent, padding), and ActionButton1 stays 45 wide at every
-- size. Bars 2-8 carry Retail's names (Apotheca.API.ACTION_BARS), checked
-- by /fp apo bar. WoW.actionBar sets bar 1, WoW.actionBars[n] any bar;
-- WoW.actionBarThrow refuses every read.
WoW.actionBar = { [0] = 0, [1] = 1, [2] = 12, [3] = 100, [4] = 2 }
WoW.actionBars = {}
WoW.actionBarThrow = false
local BARS = {
    { "MainActionBar", "ActionButton1" }, { "MultiBarBottomLeft", "MultiBarBottomLeftButton1" },
    { "MultiBarBottomRight", "MultiBarBottomRightButton1" }, { "MultiBarRight", "MultiBarRightButton1" },
    { "MultiBarLeft", "MultiBarLeftButton1" }, { "MultiBar5", "MultiBar5Button1" },
    { "MultiBar6", "MultiBar6Button1" }, { "MultiBar7", "MultiBar7Button1" },
}
for i, names in ipairs(BARS) do
    local bar = newWidget("Frame", UIParent, names[1])
    -- EditModeActionBarSystemMixin's (Blizzard_EditMode), so a field here.
    function bar.GetSettingValue(_, setting)
        if WoW.actionBarThrow then error("GetSettingValue refused") end
        local t = (i == 1 and WoW.actionBar) or WoW.actionBars[i] or WoW.actionBar
        return t[setting]
    end
    _G[names[1]] = bar
    local button = newWidget("CheckButton", bar, names[2])
    button._width, button._height = 45, 45
    function button.GetEffectiveScale()   -- the icon size scales the button (measured)
        local t = (i == 1 and WoW.actionBar) or WoW.actionBars[i] or WoW.actionBar
        return (t[3] or 100) / 100
    end
    _G[names[2]] = button
end
GameTooltip = newWidget("GameTooltip", UIParent, "GameTooltip")
GameFontNormal, GameFontHighlight = {}, {}

------------------------------------------------------------
-- Globals present on this client (forever-api-1.60.1.<build>.md)
------------------------------------------------------------

function time() return math.floor(WoW.now) end
function IsAltKeyDown() return WoW.altDown end
function IsControlKeyDown() return WoW.ctrlDown == true end
function IsShiftKeyDown() return WoW.shiftDown == true end
function GetBuildInfo() return "1.60.1", WoW.build, "Sep 22 2026", 16001 end
function GetRealmName() return "ClassicBetaPvE" end
function UnitName() return "Testcase Surname", nil end
function UnitClass() return WoW.class:sub(1, 1) .. WoW.class:sub(2):lower(), WoW.class, 5 end
-- Outdoors this client returns the CONTINENT, not an empty name.
function GetInstanceInfo() return WoW.instanceName, WoW.instanceType, 0, "", 0, 0, false, WoW.instanceMap end
-- Temporary weapon enchants by slot: { has, exp (ms), charges, id }. The
-- time left runs down from the first read, as the client's does.
WoW.enchants = {}
local function left(e)
    if type(e[2]) ~= "number" then return e[2] end
    e.t = e.t or WoW.now
    return e[2] - (WoW.now - e.t) * 1000
end
WoW.enchantThrow = false
function GetWeaponEnchantInfo()
    if WoW.enchantThrow then error("GetWeaponEnchantInfo refused") end
    local m, o = WoW.enchants[16] or {}, WoW.enchants[17] or {}
    return m[1] or false, left(m), m[3], m[4], o[1] or false, left(o), o[3], o[4], false
end
WoW.targeting, WoW.popup = false, nil
function SpellIsTargeting() return WoW.targeting end
-- The cursor in screen pixels (drag and drop in the options, #54).
WoW.cursorX, WoW.cursorY = 0, 0
function GetCursorPosition() return WoW.cursorX, WoW.cursorY end
function StaticPopup_Visible(which) return WoW.popup == which and {} or nil end

local function maybeSecret(v) if WoW.healthSecret then return Secret() end return v end
function UnitHealth()    return maybeSecret(WoW.health) end
function UnitHealthMax() return WoW.healthMax end
function UnitPower()     return maybeSecret(WoW.power) end
function UnitPowerMax()  return WoW.powerMax end

NUM_BAG_SLOTS = 4
Enum = { BagIndex = { Backpack = 0, ReagentBag = 5 }, PowerType = { Mana = 0 },
    -- Measured on 70291 (/fp apo bar, docs/FOREVER-PROBE.md).
    EditModeActionBarSetting = { Orientation = 0, NumRows = 1, NumIcons = 2, IconSize = 3,
        IconPadding = 4, VisibleSetting = 5, HideBarArt = 6, DeprecatedSnapToSide = 7,
        HideBarScrolling = 8, AlwaysShowButtons = 9 },
    ActionBarOrientation = { Horizontal = 0, Vertical = 1 },
    -- The client UI source's values (Player and Pet only); not measured.
    SpellBookSpellBank = { Player = 0, Pet = 1 },
}

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
-- The bags' count (C_Item.GetItemCount leaves the bank out by default).
function C_Item.GetItemCount(itemID)
    local n = 0
    for _, bag in pairs(WoW.bags) do
        for _, it in pairs(bag) do
            if it.itemID == itemID then n = n + (it.stackCount or 1) end
        end
    end
    return n
end
function C_Item.UseItemByName(name) WoW.itemsUsed[#WoW.itemsUsed + 1] = name end
-- Reads the client's item DB: answers for any known ID, cache or not.
-- Item class by ID ({ classID, subClassID, subType }); consumables by
-- default. The type name follows the class, as the client's does.
WoW.itemClass = {}
local CLASS_NAME = { [2] = "Weapon", [4] = "Armor" }
function C_Item.GetItemInfoInstant(itemID)
    local c = WoW.itemClass[itemID]
    if c then return itemID, CLASS_NAME[c[1]] or "Miscellaneous", c[3] or "", "", 134400, c[1], c[2] end
    if not WoW.items[itemID] then return nil end
    return itemID, "Consumable", "Food & Drink", "", 134400, 0, 5
end
function C_Item.RequestLoadItemDataByID() end
-- Items the player cannot use now (C_Item.IsUsableItem false).
WoW.unusable = {}
function C_Item.IsUsableItem(itemID) return not WoW.unusable[itemID], false end
function C_Item.GetItemSpell(itemID)
    if WoW.items[itemID] then return "Food", 433 end
end

C_Spell = C_Spell or {}
-- Spells whose name only appears after `n` load requests, like the client,
-- which answers nil until the data arrives (n = math.huge: never loads).
WoW.spellLoadAfter = {}
function C_Spell.RequestLoadSpellData(spellID)
    local e = WoW.spellLoadAfter[spellID]
    if e then
        e.n = e.n - 1
        if e.n <= 0 then WoW.spellNames[spellID], WoW.spellLoadAfter[spellID] = e.name, nil end
    end
end
-- Localized buff names by spell ID; tests install entries to simulate a
-- buff whose aura spell ID differs from the item's spell.
WoW.spellNames = {}
function C_Spell.GetSpellName(spellID) return WoW.spellNames[spellID] end
function C_Spell.DoesSpellExist(spellID)
    return WoW.spellNames[spellID] ~= nil or WoW.spellLoadAfter[spellID] ~= nil
end
WoW.spellDescriptions = {}
function C_Spell.GetSpellDescription(spellID)
    if spellID == 433 then return "Restores 61 health over 18 sec." end
    return WoW.spellDescriptions[spellID] or ""
end

-- Professions (#42). GetProfessions returns nil x7 on Forever (porting
-- guide), so professions are read from known spells. WoW.knownSpells:
-- [spellID] = true for the player's spellbook.
WoW.knownSpells = {}
-- On 70334 it answers skill line indices for a character with
-- professions: WoW.professions = { 7, 8, 5, 9, 6 }.
WoW.professions = {}
function GetProfessions()
    local p = WoW.professions
    return p[1], p[2], p[3], p[4], p[5], p[6], p[7]
end
function GetProfessionInfo() return nil end
function C_Spell.GetSpellSubtext() return nil end
function C_Spell.GetSpellTexture(id) return WoW.knownSpells[id] and 136243 or nil end
-- Key bindings: WoW.bindings[action] = key.
WoW.bindings = {}
function GetBindingKey(action) return WoW.bindings[action] end
function C_Spell.GetSpellCooldown()
    return { startTime = 0, duration = 0, isEnabled = true, modRate = 1 }
end
function IsSpellKnown(id) return WoW.knownSpells[id] == true end
function IsPlayerSpell(id) return WoW.knownSpells[id] == true end
C_SpellBook = {}
function C_SpellBook.IsSpellKnown(id) return WoW.knownSpells[id] == true end
function C_SpellBook.IsSpellInSpellBook(id) return WoW.knownSpells[id] == true end
-- The spellbook: known spells in ID order, one "Professions" line.
local function SpellBookSlots()
    local ids = {}
    for id in pairs(WoW.knownSpells) do ids[#ids + 1] = id end
    table.sort(ids)
    return ids
end
function C_SpellBook.FindSpellBookSlotForSpell(id)
    for slot, known in ipairs(SpellBookSlots()) do
        if known == id then return slot, Enum.SpellBookSpellBank.Player end
    end
end
function C_SpellBook.GetSpellBookItemInfo(slot)
    local id = SpellBookSlots()[slot]
    if id then return { spellID = id, actionID = id, name = WoW.spellNames[id], isPassive = false } end
end
function C_SpellBook.GetNumSpellBookSkillLines() return 1 end
function C_SpellBook.GetSpellBookSkillLineInfo(i)
    if i == 1 then return { name = "Professions", itemIndexOffset = 0, numSpellBookItems = #SpellBookSlots() } end
end
C_SkillInfo = {}
function C_SkillInfo.GetNumSkillLines() return 0 end
function C_SkillInfo.GetSkillLineInfo() return nil end
WoW.overrideBindings = {}     -- [key] = "buttonName:mouseButton"
function SetOverrideBindingClick(owner, priority, key, name, button)
    WoW.overrideBindings[key] = name .. ":" .. (button or "LeftButton")
end
function ClearOverrideBindings() WoW.overrideBindings, WoW.bindingOwners = {}, {} end
-- Sounds: an addon's own file plays (porting guide); WoW.sounds records them.
WoW.sounds = {}
function PlaySoundFile(path, channel)
    WoW.sounds[#WoW.sounds + 1] = { path = path, channel = channel }
    return true, #WoW.sounds
end
C_ClassColor = {}
WoW.classColors = { MAGE = { r = 0.25, g = 0.78, b = 0.92 }, PRIEST = { r = 1, g = 1, b = 1 } }
function C_ClassColor.GetClassColor(class) return WoW.classColors[class] end
-- FrameXML's callback registry (EventRegistry.RegisterCallback /
-- TriggerEvent): a callback gets its owner, then the event's arguments.
EventRegistry = { _callbacks = {} }
function EventRegistry:RegisterCallback(event, fn, owner)
    self._callbacks[event] = self._callbacks[event] or {}
    table.insert(self._callbacks[event], { fn = fn, owner = owner })
end
function EventRegistry:TriggerEvent(event, ...)
    for _, c in ipairs(self._callbacks[event] or {}) do c.fn(c.owner, ...) end
end
function date(fmt) return os.date(fmt) end

-- A profiling clock that advances with every read, so a per-frame time
-- budget really ends a frame's work in tests.
WoW.profileMs = 0
function debugprofilestop() WoW.profileMs = WoW.profileMs + 0.0005 return WoW.profileMs end

-- Levels (XP food, #19).
WoW.level, WoW.maxLevel, WoW.xpDisabled = 3, 60, false
function UnitLevel() return WoW.level end
WoW.dead = false
function UnitIsDeadOrGhost() return WoW.dead end
function GetMaxPlayerLevel() return WoW.maxLevel end
function GetMaxLevelForPlayerExpansion() return WoW.maxLevel end
function IsXPUserDisabled() return WoW.xpDisabled end

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
function C_Secrets.ShouldAurasBeSecret() return WoW.combat end
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

-- The onReset state above, set once before the first test line.
WoW.reset()

-- Names the client does not have, or that start nil. Reading one returns
-- nil instead of failing the test, so guarded feature checks still run.
-- Any other read of an undefined global fails the test.
Kit.strict({
    -- Removed on Forever (forever-api-1.60.1.70338.md).
    AnimateTexCoords = true, InterfaceOptions_AddCategory = true,
    InterfaceOptionsFrame_OpenToCategory = true, GetItemInfo = true,
    GetItemIcon = true, UnitBuff = true, UnitDebuff = true, UnitAura = true,
    GetTalentTabInfo = true, GetNumTalentTabs = true, UseItemByName = true,
    MouseIsOver = true, GetContainerNumSlots = true, GetContainerItemLink = true,
    GetContainerItemInfo = true, GetItemCooldown = true, MAX_PLAYER_LEVEL = true,
    -- SavedVariables, nil until the client would have loaded them.
    ApothecaDB = true, ApothecaCharDB = true, ApothecaProbeDB = true,
    -- The addon namespace, nil until ApothecaCompat.lua creates it.
    Apotheca = true,
    -- Frames the addon names itself; nil until created.
    ApothecaFrame = true, ApothecaAnchor = true,
    -- Another addon's namespace (an OptionalDep, #68): nil unless installed.
    GlassActionBars = true,
})
