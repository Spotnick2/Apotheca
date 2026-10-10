-- ============================================================
-- Apotheca - Profession bar (#42)
--
-- An optional second bar that builds itself from the character's
-- professions: Cooking, First Aid, Fishing, the primary professions'
-- windows, their action spells (Disenchant, Smelting, Find Herbs, Find
-- Minerals, Pick Lock) and the Hearthstone. Off by default.
--
-- Professions are found by spell ID (measured on 70334, docs/FOREVER-PROBE.md):
-- only a profession's current rank is known, so a family's spell is the one
-- candidate the client says is known. GetProfessions answers on 70334 but
-- returned nil x7 on 70009, so it is not relied on.
--
-- Every action has a named key binding (Bindings.xml, category "Apotheca")
-- that clicks its button, ApothecaUtil_<key>. All buttons exist from load,
-- so a saved binding always has a target. A binding acts on a hidden
-- button (measured), so an action that is off, unavailable or on a
-- disabled bar has its attributes cleared: its key then does nothing.
--
-- Combat: secure buttons and their parent can't be changed, shown, hidden,
-- moved or have a drag stopped in combat. Every change waits for
-- PLAYER_REGEN_ENABLED, which redoes it from the current state.
-- ============================================================

local Utility = {}
Apotheca.Utility = Utility

local PREFIX = "|cff9966ffApotheca:|r "
local HEARTHSTONE = 6948

-- The actions, in their default order. `spells`: candidate IDs, highest
-- rank first (only one is known at a time). Measured on 70334: hearthstone,
-- cooking, firstaid, fishing, baittackle (seen), enchanting, tailoring,
-- leatherworking, disenchant. The rest are Vanilla's IDs, not measured yet.
local ACTIONS = {
    { key = "hearthstone",    label = "Hearthstone",     item = HEARTHSTONE },
    { key = "cooking",        label = "Cooking",         spells = { 18260, 3413, 3102, 2550 } },
    { key = "firstaid",       label = "First Aid",       spells = { 10846, 7924, 3274, 3273 } },
    { key = "fishing",        label = "Fishing",         spells = { 18248, 7732, 7731, 7620 } },
    { key = "baittackle",     label = "Bait and Tackle", spells = { 1278067 } },
    { key = "alchemy",        label = "Alchemy",         spells = { 11611, 3464, 3101, 2259 } },
    { key = "blacksmithing",  label = "Blacksmithing",   spells = { 9785, 3538, 3100, 2018 } },
    { key = "enchanting",     label = "Enchanting",      spells = { 13920, 7413, 7412, 7411 } },
    { key = "engineering",    label = "Engineering",     spells = { 12656, 4038, 4037, 4036 } },
    { key = "leatherworking", label = "Leatherworking",  spells = { 10662, 3811, 3104, 2108 } },
    { key = "tailoring",      label = "Tailoring",       spells = { 12180, 3910, 3909, 3908 } },
    { key = "smelting",       label = "Smelting",        spells = { 2656 } },
    { key = "poisons",        label = "Poisons",         spells = { 2842 } },
    { key = "disenchant",     label = "Disenchant",      spells = { 13262 } },
    { key = "findherbs",      label = "Find Herbs",      spells = { 2383 } },
    { key = "findminerals",   label = "Find Minerals",   spells = { 2580 } },
    { key = "picklock",       label = "Pick Lock",       spells = { 1804 } },
}
Utility.ACTIONS = ACTIONS
local BY_KEY = {}
for _, a in ipairs(ACTIONS) do BY_KEY[a.key] = a end
Utility.BY_KEY = BY_KEY

local function ButtonName(key) return "ApothecaUtil_" .. key end
function Utility.BindingAction(key) return "CLICK " .. ButtonName(key) .. ":LeftButton" end

-- Key Bindings labels, set at load so the page shows them on its first
-- open, even for an action this character doesn't have. Localized at login
-- once the client can name the spells.
for _, a in ipairs(ACTIONS) do
    _G["BINDING_NAME_" .. Utility.BindingAction(a.key)] = a.label
end

local function LocalizeBindingNames()
    for _, a in ipairs(ACTIONS) do
        local name
        if a.item then
            name = Apotheca.API.ItemInfo(a.item)
        else
            name = Apotheca.API.SpellName(a.spells[#a.spells])
        end
        if type(name) == "string" and name ~= "" then
            _G["BINDING_NAME_" .. Utility.BindingAction(a.key)] = name
        end
    end
end

-- ------------------------------------------------------------
-- Settings
-- ------------------------------------------------------------

-- The profile's utility table (PROFILE_DEFAULTS.utility). `show[key]` is
-- false for an action switched off, nil or true for on, so a new action
-- needs no migration. Position is per character (ApothecaCharDB.utility).
function Utility.Settings()
    local db = Apotheca.GetDB()
    return type(db.utility) == "table" and db.utility or {}
end

-- The saved order, keeping only known keys, with any action it lacks
-- appended in catalog order.
function Utility.Order()
    local s, out, seen = Utility.Settings(), {}, {}
    for _, key in ipairs(type(s.order) == "table" and s.order or {}) do
        if BY_KEY[key] and not seen[key] then out[#out + 1] = key ; seen[key] = true end
    end
    for _, a in ipairs(ACTIONS) do
        if not seen[a.key] then out[#out + 1] = a.key end
    end
    return out
end

function Utility.IsShown(key)
    local show = Utility.Settings().show
    return not (type(show) == "table" and show[key] == false)
end

-- ------------------------------------------------------------
-- What the character has
-- ------------------------------------------------------------

-- The spell an action casts: the one candidate the client says is known.
function Utility.KnownSpell(action)
    for _, id in ipairs(action.spells or {}) do
        if Apotheca.API.SpellKnown(id) == true then return id end
    end
end

-- The ordered list of { key, kind, value } this character can use and
-- has switched on. kind is "spell" or "item".
function Utility.Collect()
    local list = {}
    for _, key in ipairs(Utility.Order()) do
        local a = BY_KEY[key]
        if Utility.IsShown(key) then
            if a.item then
                if Apotheca.API.ItemCount(a.item) > 0 then list[#list + 1] = { key = key, kind = "item", value = a.item } end
            else
                local id = Utility.KnownSpell(a)
                if id then list[#list + 1] = { key = key, kind = "spell", value = id } end
            end
        end
    end
    return list
end

-- ------------------------------------------------------------
-- Frame, anchor and buttons
-- ------------------------------------------------------------

local frame = CreateFrame("Frame", "ApothecaUtilityFrame", UIParent)
frame:SetSize(44, 44)
frame:SetPoint("RIGHT", UIParent, "RIGHT", -150, 0)
frame:SetMovable(true)
frame:SetClampedToScreen(true)
frame:SetFrameStrata("MEDIUM")
frame:EnableMouse(true)
frame:Hide()
Utility.frame = frame

Utility.buttons = {}
for _, a in ipairs(ACTIONS) do
    local btn = CreateFrame("Button", ButtonName(a.key), frame, "SecureActionButtonTemplate")
    btn:SetSize(36, 36)
    -- Both edges, as on the main bar: the client acts on the one matching
    -- ActionButtonUseKeyDown, once (measured for clicks and CLICK bindings).
    btn:RegisterForClicks(Apotheca.API.ClickEdges())
    Apotheca.StyleButton(btn, "ApothecaUtilCD_" .. a.key)
    local hk = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmallGray")
    hk:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -2, -3)
    btn.hotkey = hk
    btn.action = a
    btn:SetScript("OnEnter", function(self)
        if not self.kind then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if self.kind == "item" then GameTooltip:SetItemByID(self.value)
        else GameTooltip:SetSpellByID(self.value) end
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    btn:Hide()
    Utility.buttons[a.key] = btn
end

-- Position: per character, the BOTTOMLEFT corner, like the main bar.
local function SavePosition()
    ApothecaCharDB = ApothecaCharDB or {}
    ApothecaCharDB.utility = { x = frame:GetLeft() or 0, y = frame:GetBottom() or 200 }
end

local function RestorePosition()
    local p = type(ApothecaCharDB) == "table" and ApothecaCharDB.utility
    frame:ClearAllPoints()
    if type(p) == "table" and p.x and p.y then
        frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", p.x, p.y)
    else
        frame:SetPoint("RIGHT", UIParent, "RIGHT", -150, 0)
    end
end

local anchor = CreateFrame("Frame", "ApothecaUtilityAnchor", frame)
anchor:SetAllPoints(frame)
anchor:SetFrameStrata("DIALOG")
anchor:EnableMouse(true)
anchor:RegisterForDrag("LeftButton")
anchor:Hide()
do
    local bg = anchor:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.40, 0.27, 0.66, 0.55)
    local text = anchor:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("CENTER")
    text:SetTextColor(1, 1, 1, 0.9)
    text:SetText("Drag")
end

-- Dragging. No StartMoving or StopMovingOrSizing in combat: the client
-- refuses them on a frame that parents secure buttons (porting guide). A
-- drag that combat interrupts is finished at PLAYER_REGEN_ENABLED, before
-- anything else touches the frame, and the bar stays where it was dropped.
Utility.dragging, Utility.dragStopPending = false, false

local function StopDrag()
    if not Utility.dragging then return end
    if InCombatLockdown() then
        Utility.dragStopPending = true
        return
    end
    frame:StopMovingOrSizing()
    SavePosition()
    Utility.dragging, Utility.dragStopPending = false, false
end
Utility.StopDrag = StopDrag

local function AnchorShouldShow()
    return IsAltKeyDown() and not InCombatLockdown() and not Utility.Settings().lockPosition
       and frame:IsVisible() and frame:IsMouseOver()
end

local function UpdateAnchor()
    if Utility.dragging then
        if not IsAltKeyDown() or InCombatLockdown() or Utility.Settings().lockPosition then
            StopDrag()
            anchor:Hide()
        end
        return
    end
    if AnchorShouldShow() then
        if not anchor:IsShown() then anchor:Show() end
    elseif anchor:IsShown() then
        anchor:Hide()
    end
end
Utility.UpdateAnchor = UpdateAnchor

anchor:SetScript("OnDragStart", function()
    if not InCombatLockdown() and not Utility.Settings().lockPosition then
        frame:StartMoving()
        Utility.dragging = true
    end
end)
anchor:SetScript("OnDragStop", function()
    StopDrag()
    UpdateAnchor()
end)
anchor:SetScript("OnMouseDown", function() end)   -- keep clicks off the buttons below
-- Safety net: never leave the frame on the cursor. In combat this only
-- marks the stop for later (StopDrag).
anchor:SetScript("OnHide", function() StopDrag() end)

-- ------------------------------------------------------------
-- Building the bar (out of combat only)
-- ------------------------------------------------------------

local SHORT_KEYS = { { "CTRL%-", "c" }, { "SHIFT%-", "s" }, { "ALT%-", "a" }, { "NUMPAD", "N" },
                     { "MOUSEWHEELUP", "MwU" }, { "MOUSEWHEELDOWN", "MwD" }, { "BUTTON", "M" } }

local function ShortKey(key)
    if not key then return "" end
    for _, r in ipairs(SHORT_KEYS) do key = key:gsub(r[1], r[2]) end
    return key
end

-- Cooldown swipes and key text: no secure change, safe in combat. Spell
-- cooldowns are secret in combat (measured): the values go straight to
-- the widget, never compared.
function Utility.RefreshVisuals()
    for _, btn in pairs(Utility.buttons) do
        if btn.kind then
            pcall(function()
                local st, dur
                if btn.kind == "item" then
                    st, dur = Apotheca.API.ItemCooldown(btn.value)
                else
                    st, dur = Apotheca.API.SpellCooldown(btn.value)
                end
                -- Unchanged: `st or 0` would truth-test a secret, which throws.
                btn.cooldown:SetCooldown(st, dur)
            end)
            btn.hotkey:SetText(ShortKey(GetBindingKey(Utility.BindingAction(btn.action.key))))
        end
    end
end

local function ClearButton(btn)
    btn:SetAttribute("type", nil)
    btn:SetAttribute("spell", nil)
    btn:SetAttribute("item", nil)
    btn.kind, btn.value = nil, nil
    btn:Hide()
end

-- Rebuilds the bar from the current settings and character. In combat it
-- only marks itself pending; PLAYER_REGEN_ENABLED runs it again.
function Utility.Reconcile()
    if InCombatLockdown() then
        Utility.pending = true
        return
    end
    Utility.pending = false
    local s = Utility.Settings()
    if not s.enabled then
        -- Off: every action cleared once; later events have nothing to do.
        if not Utility.cleared then
            for _, btn in pairs(Utility.buttons) do ClearButton(btn) end
            Utility.cleared = true
        end
        frame:Hide()
        return
    end
    Utility.cleared = false

    local list = Utility.Collect()
    local active, shown = {}, {}
    for _, entry in ipairs(list) do
        local btn = Utility.buttons[entry.key]
        btn:SetAttribute("type", entry.kind)
        if entry.kind == "item" then
            btn:SetAttribute("spell", nil)
            btn:SetAttribute("item", "item:" .. entry.value)
            btn.icon:SetTexture(Apotheca.API.ItemIcon(entry.value) or "Interface\\Icons\\INV_Misc_QuestionMark")
        else
            btn:SetAttribute("item", nil)
            btn:SetAttribute("spell", entry.value)
            btn.icon:SetTexture(Apotheca.API.SpellIcon(entry.value) or "Interface\\Icons\\INV_Misc_QuestionMark")
        end
        btn.kind, btn.value = entry.kind, entry.value
        active[entry.key] = true
        shown[#shown + 1] = btn
    end
    for key, btn in pairs(Utility.buttons) do
        if not active[key] then ClearButton(btn) end
    end

    local layout = Apotheca.LayoutSettings(s)
    Utility._layoutSig = Apotheca.LayoutSignature(layout)
    Apotheca.GridLayout(frame, shown, layout)
    if #shown > 0 then frame:Show() else frame:Hide() end
    Utility.RefreshVisuals()
end

-- After a rebuild the matched action bar changed: the open options tab's
-- "Following Action Bar" note and greyed sliders follow it.
local function RefreshOpenOptions()
    local panel = Apotheca.optionsPanel
    if panel and panel:IsVisible() and Apotheca.RefreshOptions then Apotheca.RefreshOptions() end
end

-- A rebuild on the next frame: coalesces bursts (SPELLS_CHANGED fires
-- often) and keeps the work out of event handlers.
function Utility.Refresh()
    Utility.wanted = true
end

-- ------------------------------------------------------------
-- Events
-- ------------------------------------------------------------

local ready = false
local events = CreateFrame("Frame")
Apotheca.API.RegisterEvents(events,
    "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED",
    "SKILL_LINES_CHANGED", "SPELLS_CHANGED", "LEARNED_SPELL_IN_SKILL_LINE",
    "BAG_UPDATE_DELAYED", "BAG_UPDATE_COOLDOWN", "SPELL_UPDATE_COOLDOWN",
    "UPDATE_BINDINGS", "MODIFIER_STATE_CHANGED", "EDIT_MODE_LAYOUTS_UPDATED")

events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        ready = true
        LocalizeBindingNames()
        -- Once per account: the bar is off by default, so say it exists.
        if type(ApothecaDB) == "table" and not ApothecaDB.utilityIntroShown then
            ApothecaDB.utilityIntroShown = true
            print(PREFIX .. "new: a profession bar (Cooking, First Aid, your professions, "
                  .. "Disenchant, Hearthstone...) with its own key bindings. /apo utility to show it.")
        end
        -- A /reload in combat: the position waits for the end of combat.
        if InCombatLockdown() then Utility.positionPending = true else RestorePosition() end
        Utility.Refresh()
    elseif not ready then
        return
    elseif event == "PLAYER_REGEN_ENABLED" then
        -- The interrupted drag first, before a rebuild can move or hide
        -- the frame, then whatever combat held back.
        if Utility.dragStopPending then StopDrag() end
        if Utility.positionPending then
            Utility.positionPending = false
            RestorePosition()
        end
        if Utility.pending then Utility.Reconcile() end
    elseif event == "BAG_UPDATE_COOLDOWN" or event == "SPELL_UPDATE_COOLDOWN"
            or event == "UPDATE_BINDINGS" then
        Utility.RefreshVisuals()
    elseif event == "MODIFIER_STATE_CHANGED" then
        UpdateAnchor()
    elseif event == "EDIT_MODE_LAYOUTS_UPDATED" then
        if (tonumber(Utility.Settings().matchBar) or 0) > 0 then
            Utility.Reconcile()
            RefreshOpenOptions()
        end
    else
        -- Professions learned or lost, bags (the Hearthstone), entering
        -- the world.
        Utility.Refresh()
    end
end)

local POLL = 3
local pollElapsed, anchorElapsed = 0, 0
events:SetScript("OnUpdate", function(_, elapsed)
    if not ready then return end
    if Utility.wanted then
        Utility.wanted = false
        Utility.Reconcile()
    end
    -- The anchor follows the live Alt and mouse state, as on the main bar.
    anchorElapsed = anchorElapsed + elapsed
    if anchorElapsed >= 0.1 then
        anchorElapsed = 0
        if Utility.dragging or anchor:IsShown() or frame:IsMouseOver() then UpdateAnchor() end
    end
    -- The matched action bar changed in Edit Mode, which fires nothing
    -- while a slider moves (#40).
    pollElapsed = pollElapsed + elapsed
    if pollElapsed >= POLL then
        pollElapsed = 0
        local s = Utility.Settings()
        if not InCombatLockdown() and frame:IsShown() and (tonumber(s.matchBar) or 0) > 0
                and Apotheca.LayoutSignature((Apotheca.LayoutSettings(s))) ~= Utility._layoutSig then
            Utility.Reconcile()
            RefreshOpenOptions()
        end
    end
end)

-- /apo utility: switch the bar on or off.
function Utility.Toggle()
    local s = Apotheca.GetDB().utility
    if type(s) ~= "table" then return end
    s.enabled = not s.enabled
    print(PREFIX .. "profession bar " .. (s.enabled and "on" or "off")
          .. (InCombatLockdown() and " (after combat)" or "") .. ".")
    Utility.Reconcile()
    if Apotheca.RefreshOptions then Apotheca.RefreshOptions() end
end
