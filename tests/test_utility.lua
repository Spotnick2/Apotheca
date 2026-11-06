-- #42: the profession bar (ApothecaUtility.lua). Built from the spells
-- the character knows, one named binding per action, and nothing protected
-- touched in combat (WoW.strictLockdown).

dofile("tests/wow_stubs.lua")
local H = dofile("tests/harness.lua")

-- The measured warlock (70334): Tailoring Journeyman, Enchanting,
-- Disenchant, Cooking, First Aid, Fishing; a Hearthstone in the bags.
for _, id in ipairs({ 3909, 7411, 13262, 2550, 3273, 7620 }) do WoW.knownSpells[id] = true end
WoW.AddItem(0, 1, 6948, 1, "Hearthstone")

-- Saved data from before the bar existed (Other), and a Global profile
-- with a partial utility table: an explicit false must survive defaults.
local saved = {
    activeProfile = "Global",
    profiles = {
        Global = { utility = { enabled = true, show = { poisons = false } } },
        Other  = { iconSize = 40 },
    },
}
WoW.strictLockdown = true
H.loadAddon({ savedDB = saved })
local U = Apotheca.Utility
local frame = U.frame

local function tick() WoW.step(0.2) end
local function keys(list)
    local out = {}
    for _, e in ipairs(list) do out[#out + 1] = e.key end
    return table.concat(out, ",")
end
local function attr(key, a) return U.buttons[key]:GetAttribute(a) end

-- Once per account, a line says the bar exists (it is off by default).
check(ApothecaDB.utilityIntroShown, "the intro line is shown once")

-- Defaults: two levels deep, explicit values kept.
local g = ApothecaDB.profiles.Global.utility
eq(g.enabled, true, "a saved enabled is kept")
eq(g.rows, 2, "a partial utility table gets the missing defaults")
eq(g.show.poisons, false, "an explicit false is kept")

-- Bindings: every action has one, in the Apotheca category, with a label.
local xml = assert(io.open("Bindings.xml")):read("*a")
local bound = {}
for name, cat in xml:gmatch('<Binding name="CLICK ApothecaUtil_(%w+):LeftButton" category="(%w+)"/>') do
    bound[name] = cat
end
for _, a in ipairs(U.ACTIONS) do
    eq(bound[a.key], "Apotheca", "Bindings.xml: " .. a.key .. " in the Apotheca category")
    check(type(_G["BINDING_NAME_CLICK ApothecaUtil_" .. a.key .. ":LeftButton"]) == "string",
        "a label for " .. a.key)
    check(_G["ApothecaUtil_" .. a.key], "its button exists from load: " .. a.key)
end
check(not xml:find("header="), "no header (a raw HEADER_ row without a category)")

-- A Hearthstone not cached at login: its label is retried when it arrives.
local hearthLabel = "BINDING_NAME_CLICK ApothecaUtil_hearthstone:LeftButton"
local cachedName = WoW.items[6948]
WoW.items[6948] = nil
_G[hearthLabel] = "Hearthstone"
U.LocalizeBindingNames()
check(U.namesPending, "a name the client can't give yet is pending")
WoW.items[6948] = "Ruhestein"
WoW.fire("GET_ITEM_INFO_RECEIVED", 6948, true)
eq(_G[hearthLabel], "Ruhestein", "the label follows once the item is cached")
WoW.items[6948] = cachedName
U.LocalizeBindingNames()

-- Catalog shape: no spell ID in two actions.
local seenIDs = {}
for _, a in ipairs(U.ACTIONS) do
    for _, id in ipairs(a.spells or {}) do
        check(not seenIDs[id], "spell " .. id .. " in one action only")
        seenIDs[id] = true
    end
end

-- The bar, built at login from what the character knows, in catalog order.
check(frame:IsShown(), "enabled: the bar is shown")
eq(keys(U.Collect()), "hearthstone,cooking,firstaid,fishing,enchanting,tailoring,disenchant",
    "what the warlock has, in the default order")
eq(attr("hearthstone", "type"), "item", "the Hearthstone is an item button")
eq(attr("hearthstone", "item"), "item:6948", "for the Hearthstone")
eq(attr("tailoring", "type"), "spell", "a profession is a spell button")
eq(attr("tailoring", "spell"), 3909, "the rank the character knows")
eq(attr("disenchant", "spell"), 13262, "Disenchant")
eq(attr("alchemy", "type"), nil, "an unknown profession has no action")
check(not U.buttons.alchemy:IsShown(), "and no button")

-- Skinning opens a window on Forever (#52): a skinner gets its button.
WoW.knownSpells[8617] = true
eq(keys(U.Collect()), "hearthstone,cooking,firstaid,fishing,enchanting,tailoring,skinning,disenchant",
    "Skinning (Journeyman, measured) after the crafting professions")
WoW.knownSpells[8617] = nil

-- Comprehend Scroll (#84): a mage's spell, so it shows only where known.
WoW.knownSpells[1296017] = true
U.Refresh() ; tick()
eq(attr("comprehend", "type"), "spell", "Comprehend Scroll known: a spell button")
eq(attr("comprehend", "spell"), 1296017, "  its spell")
eq(keys(U.Collect()), "hearthstone,cooking,firstaid,fishing,enchanting,tailoring,disenchant,comprehend",
    "  after the other actions")
WoW.knownSpells[1296017] = nil
U.Refresh() ; tick()
eq(attr("comprehend", "type"), nil, "not known (not a mage): no action")
check(not U.buttons.comprehend:IsShown(), "  and no button")

-- Two ranks known: the higher one.
WoW.knownSpells[3274] = true
eq(U.KnownSpell(U.BY_KEY.firstaid), 3274, "two ranks known: the higher")
WoW.knownSpells[3274] = nil

-- Order: a saved order first, unknown keys dropped, the rest appended.
g.order = { "disenchant", "nonsense", "hearthstone" }
eq(keys(U.Collect()), "disenchant,hearthstone,cooking,firstaid,fishing,enchanting,tailoring",
    "the saved order, then the rest")
g.order = {}

-- Switched off: no action, so its key does nothing even on a hidden button.
g.show.disenchant = false
U.Refresh() ; tick()
eq(attr("disenchant", "type"), nil, "switched off: no action")
eq(attr("disenchant", "spell"), nil, "and no spell")
g.show.disenchant = nil
U.Refresh() ; tick()
eq(attr("disenchant", "spell"), 13262, "back on")

-- No Hearthstone in the bags: no button.
WoW.bags[0][1] = nil
U.Refresh() ; tick()
eq(attr("hearthstone", "type"), nil, "no Hearthstone: no action")
WoW.AddItem(0, 1, 6948, 1, "Hearthstone")
U.Refresh() ; tick()

-- Key text: the bound key, shortened like the action bars.
WoW.bindings["CLICK ApothecaUtil_disenchant:LeftButton"] = "F9"
WoW.bindings["CLICK ApothecaUtil_cooking:LeftButton"] = "CTRL-SHIFT-1"
WoW.fire("UPDATE_BINDINGS")
eq(U.buttons.disenchant.hotkey:GetText(), "F9", "the bound key on the button")
eq(U.buttons.cooking.hotkey:GetText(), "cs1", "modifiers shortened")

-- Combat: a profession learned, the bar toggled and the layout changed
-- touch nothing protected (strictLockdown would fail the test); all of it
-- applies after combat, from the current state.
WoW.enterCombat()
WoW.knownSpells[2108] = true                         -- Leatherworking learned
WoW.fire("SKILL_LINES_CHANGED")
tick()
check(U.pending, "a change in combat waits")
eq(attr("leatherworking", "type"), nil, "nothing changed yet")
g.rows = 3
U.Toggle()                                           -- off, in combat
check(frame:IsShown(), "the bar can't be hidden in combat")
U.Toggle()                                           -- and back on
WoW.leaveCombat()
WoW.fire("PLAYER_REGEN_ENABLED")
check(not U.pending, "applied after combat")
eq(attr("leatherworking", "spell"), 2108, "the profession learned in combat")
check(frame:IsShown(), "on: the state after combat, not the one in between")

-- Disabled out of combat: every action cleared, the bar hidden.
U.Toggle()
check(not frame:IsShown(), "off: hidden")
for key, btn in pairs(U.buttons) do
    eq(btn:GetAttribute("type"), nil, "off: " .. key .. " has no action")
end
U.Toggle()

-- A profile switch rebuilds the bar: a profile from before the bar has it
-- off (defaults), with no bag or profession event.
Apotheca.SetProfile("Other")
tick()
eq(ApothecaDB.profiles.Other.utility.enabled, false, "an older profile gets the bar, off")
check(not frame:IsShown(), "and the switch hides it")
Apotheca.SetProfile("Global")
tick()
check(frame:IsShown(), "switching back shows it")

-- Dragging (#46): stopped as combat starts (PLAYER_REGEN_DISABLED comes
-- before lockdown); with lockdown already on, finished after it, with no
-- movement call in combat (strictLockdown).
local anchor = ApothecaUtilityAnchor
local function startUtilDrag()
    frame._mouseOver, WoW.altDown = true, true
    U.UpdateAnchor()
    check(anchor:IsShown(), "Alt over the bar: the drag anchor")
    anchor:GetScript("OnDragStart")(anchor)
    check(frame._moving and U.dragging, "dragging")
end
startUtilDrag()
frame._left, frame._bottom = 350, 260
WoW.enterCombat()
check(not frame._moving and not U.dragging, "stopped cleanly as combat starts")
eq(ApothecaCharDB.utility.x, 350, "saved where it was")
WoW.leaveCombat()

startUtilDrag()
frame._left, frame._bottom = 300, 250                -- where combat catches it
WoW.enterLockdown()
anchor:GetScript("OnDragStop")(anchor)               -- mouse up in combat
frame._left, frame._bottom = 900, 500                -- it still follows the cursor
WoW.altDown = false
U.UpdateAnchor()
check(frame._moving, "no stop in combat: the client would refuse it")
check(U.dragStopPending, "the stop waits")
check(anchor:IsShown(), "the anchor stays up: no click reaches a button under the cursor")
ApothecaCharDB = ApothecaCharDB or {}
ApothecaCharDB.utility = nil
WoW.leaveCombat()
check(not frame._moving, "stopped after combat")
check(not anchor:IsShown(), "and the anchor hides")
check(ApothecaCharDB.utility and ApothecaCharDB.utility.x, "the position saved, per character")
eq(ApothecaCharDB.utility.x, 300, "where combat stopped the drag, not where the cursor ended")
eq(ApothecaCharDB.utility.y, 250, "both coordinates")
frame._left, frame._bottom = nil, nil
check(not U.dragging and not U.dragStopPending, "drag state cleared")
frame._mouseOver = false

-- Locks are separate.
g.lockPosition = true
WoW.altDown, frame._mouseOver = true, true
U.UpdateAnchor()
check(not anchor:IsShown(), "locked: no anchor")
eq(ApothecaDB.profiles.Global.lockPosition, false, "the main bar's lock is its own")
g.lockPosition = false
WoW.altDown, frame._mouseOver = false, false

-- The main bar keeps its own per-character position.
eq(type(ApothecaCharDB.utility), "table", "the profession bar saves under .utility")
eq(ApothecaCharDB.x, nil, "and leaves the main bar's position alone")

-- Options: the tab's checkboxes write the profile and rebuild the bar.
local panel = Apotheca.optionsPanel
panel._scripts.OnShow(panel)
local function checkboxLabelled(text)
    for _, f in ipairs(H.framesWithTemplate("InterfaceOptionsCheckButtonTemplate")) do
        if f.Text and type(f.Text:GetText()) == "string" and f.Text:GetText():find(text, 1, true) == 1 then
            return f
        end
    end
end
local showCB = checkboxLabelled("Show the profession bar")
check(showCB and showCB:GetChecked(), "the enable box reflects the profile")
showCB:SetChecked(false)
showCB:GetScript("OnClick")(showCB)
tick()
eq(g.enabled, false, "unticked: off")
check(not frame:IsShown(), "and the bar hides")
showCB:SetChecked(true)
showCB:GetScript("OnClick")(showCB)
tick()
check(frame:IsShown(), "ticked again: shown")
local deCB = checkboxLabelled("Disenchant")
check(deCB and deCB:GetChecked(), "an action row, ticked")
deCB:SetChecked(false)
deCB:GetScript("OnClick")(deCB)
tick()
eq(g.show.disenchant, false, "unticking an action stores off")
eq(attr("disenchant", "type"), nil, "and clears its action")
deCB:SetChecked(true)
deCB:GetScript("OnClick")(deCB)
tick()
eq(g.show.disenchant, nil, "ticking it again stores nothing (shown is the default)")
eq(attr("disenchant", "spell"), 13262, "and Disenchant is back")

-- Refreshing the options reuses the action rows (frames are never freed).
local function count(label)
    local n = 0
    for _, f in ipairs(H.framesWithTemplate("InterfaceOptionsCheckButtonTemplate")) do
        if f.Text and f.Text:GetText() == label then n = n + 1 end
    end
    return n
end
Apotheca.RefreshOptions()
Apotheca.RefreshOptions()
eq(count("Disenchant"), 1, "one Disenchant row after refreshes")

-- A /reload in combat: the saved position waits for the end of combat
-- (strictLockdown fails the test if it is set in combat).
ApothecaCharDB.utility = { x = 123, y = 456 }
WoW.enterCombat()
WoW.fire("PLAYER_LOGIN")
check(U.positionPending, "logged in during combat: the position waits")
WoW.leaveCombat()
WoW.fire("PLAYER_REGEN_ENABLED")
check(not U.positionPending, "restored after combat")
local pt = frame._points[#frame._points]
eq(pt and pt[4], 123, "at the saved x")
eq(pt and pt[5], 456, "and y")

-- Off: the first rebuild clears every action, later ones have nothing to do.
g.enabled = false
U.Reconcile()
check(U.cleared, "off: cleared once")
U.buttons.cooking:SetAttribute("type", "spell")       -- would be cleared again if it rebuilt
U.Reconcile()
eq(attr("cooking", "type"), "spell", "an off bar doesn't redo the clearing")
U.buttons.cooking:SetAttribute("type", nil)
g.enabled = true
U.Reconcile()
check(not U.cleared and frame:IsShown(), "on again: rebuilt")

-- A bag event that rebuilds the bar with a new matched layout before the
-- 3-second poll: the open tab's note and sliders follow it (Codex review).
local function noteSaying(text)
    for _, f in ipairs(WoW.fontStrings) do
        if type(f._text) == "string" and f._text:find(text, 1, true) then return f end
    end
end
local function utilitySlider(label)
    local found
    for _, sl in ipairs(H.framesWithTemplate("OptionsSliderTemplate")) do
        if sl.label and sl.label:GetText() == label then found = sl end   -- the tab's is the last
    end
    return found
end
g.matchBar = 1
WoW.actionBar = { [0] = 0, [1] = 1, [2] = 12, [3] = 100, [4] = 2 }
U.Reconcile()
WoW.actionBar = { [0] = 0, [1] = 1, [2] = 12, [3] = 120, [4] = 2 }
WoW.fire("BAG_UPDATE_DELAYED")
WoW.step(0.1)                                     -- the next-frame rebuild, before any poll
check(noteSaying("Following Action Bar 1: 54.0 px"), "the note follows a bag-triggered rebuild")
check(not utilitySlider("Icon Size"):IsEnabled(), "its size slider is greyed while matching")
WoW.actionBarThrow = true
WoW.fire("SPELLS_CHANGED")
WoW.step(0.1)
check(noteSaying("can't be read here"), "an unreadable bar: the note says so")
check(utilitySlider("Icon Size"):IsEnabled(), "and the slider is enabled again")
WoW.actionBarThrow = false
-- The matched bar as big as the bar's own settings (Codex on #45): losing
-- and regaining it still refreshes the tab.
local pct = g.iconSize / 45 * 100
WoW.actionBar = { [0] = 0, [1] = 1, [2] = 12, [3] = pct, [4] = g.iconPadding / (pct / 100) }
WoW.fire("SPELLS_CHANGED")
WoW.step(0.1)
check(not utilitySlider("Icon Size"):IsEnabled(), "matching at the own size: greyed")
WoW.actionBarThrow = true
WoW.fire("SPELLS_CHANGED")
WoW.step(0.1)
check(noteSaying("can't be read here"), "losing it at the same size: the note says so")
check(utilitySlider("Icon Size"):IsEnabled(), "and the slider is enabled")
WoW.actionBarThrow = false
WoW.fire("SPELLS_CHANGED")
WoW.step(0.1)
check(not utilitySlider("Icon Size"):IsEnabled(), "regained at the same size: greyed again")
g.matchBar = 0
U.Reconcile()

done("test_utility")
