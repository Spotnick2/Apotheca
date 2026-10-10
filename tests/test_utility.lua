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

local function tick() WoW.tick(0.2) end
local function keys(list)
    local out = {}
    for _, e in ipairs(list) do out[#out + 1] = e.key end
    return table.concat(out, ",")
end
local function attr(key, a) return U.buttons[key]:GetAttribute(a) end

-- Once per account, a line says the bar exists (it is off by default).
H.check(ApothecaDB.utilityIntroShown, "the intro line is shown once")

-- Defaults: two levels deep, explicit values kept.
local g = ApothecaDB.profiles.Global.utility
H.eq(g.enabled, true, "a saved enabled is kept")
H.eq(g.rows, 2, "a partial utility table gets the missing defaults")
H.eq(g.show.poisons, false, "an explicit false is kept")

-- Bindings: every action has one, in the Apotheca category, with a label.
local xml = assert(io.open("Bindings.xml")):read("*a")
local bound = {}
for name, cat in xml:gmatch('<Binding name="CLICK ApothecaUtil_(%w+):LeftButton" category="(%w+)"/>') do
    bound[name] = cat
end
for _, a in ipairs(U.ACTIONS) do
    H.eq(bound[a.key], "Apotheca", "Bindings.xml: " .. a.key .. " in the Apotheca category")
    H.check(type(_G["BINDING_NAME_CLICK ApothecaUtil_" .. a.key .. ":LeftButton"]) == "string",
        "a label for " .. a.key)
    H.check(_G["ApothecaUtil_" .. a.key], "its button exists from load: " .. a.key)
end
H.check(not xml:find("header="), "no header (a raw HEADER_ row without a category)")

-- Catalog shape: no spell ID in two actions.
local seenIDs = {}
for _, a in ipairs(U.ACTIONS) do
    for _, id in ipairs(a.spells or {}) do
        H.check(not seenIDs[id], "spell " .. id .. " in one action only")
        seenIDs[id] = true
    end
end

-- The bar, built at login from what the character knows, in catalog order.
H.check(frame:IsShown(), "enabled: the bar is shown")
H.eq(keys(U.Collect()), "hearthstone,cooking,firstaid,fishing,enchanting,tailoring,disenchant",
    "what the warlock has, in the default order")
H.eq(attr("hearthstone", "type"), "item", "the Hearthstone is an item button")
H.eq(attr("hearthstone", "item"), "item:6948", "for the Hearthstone")
H.eq(attr("tailoring", "type"), "spell", "a profession is a spell button")
H.eq(attr("tailoring", "spell"), 3909, "the rank the character knows")
H.eq(attr("disenchant", "spell"), 13262, "Disenchant")
H.eq(attr("alchemy", "type"), nil, "an unknown profession has no action")
H.check(not U.buttons.alchemy:IsShown(), "and no button")

-- Two ranks known: the higher one.
WoW.knownSpells[3274] = true
H.eq(U.KnownSpell(U.BY_KEY.firstaid), 3274, "two ranks known: the higher")
WoW.knownSpells[3274] = nil

-- Order: a saved order first, unknown keys dropped, the rest appended.
g.order = { "disenchant", "nonsense", "hearthstone" }
H.eq(keys(U.Collect()), "disenchant,hearthstone,cooking,firstaid,fishing,enchanting,tailoring",
    "the saved order, then the rest")
g.order = {}

-- Switched off: no action, so its key does nothing even on a hidden button.
g.show.disenchant = false
U.Refresh() ; tick()
H.eq(attr("disenchant", "type"), nil, "switched off: no action")
H.eq(attr("disenchant", "spell"), nil, "and no spell")
g.show.disenchant = nil
U.Refresh() ; tick()
H.eq(attr("disenchant", "spell"), 13262, "back on")

-- No Hearthstone in the bags: no button.
WoW.bags[0][1] = nil
U.Refresh() ; tick()
H.eq(attr("hearthstone", "type"), nil, "no Hearthstone: no action")
WoW.AddItem(0, 1, 6948, 1, "Hearthstone")
U.Refresh() ; tick()

-- Key text: the bound key, shortened like the action bars.
WoW.bindings["CLICK ApothecaUtil_disenchant:LeftButton"] = "F9"
WoW.bindings["CLICK ApothecaUtil_cooking:LeftButton"] = "CTRL-SHIFT-1"
WoW.fire("UPDATE_BINDINGS")
H.eq(U.buttons.disenchant.hotkey:GetText(), "F9", "the bound key on the button")
H.eq(U.buttons.cooking.hotkey:GetText(), "cs1", "modifiers shortened")

-- Combat: a profession learned, the bar toggled and the layout changed
-- touch nothing protected (strictLockdown would fail the test); all of it
-- applies after combat, from the current state.
WoW.enterCombat()
WoW.knownSpells[2108] = true                         -- Leatherworking learned
WoW.fire("SKILL_LINES_CHANGED")
tick()
H.check(U.pending, "a change in combat waits")
H.eq(attr("leatherworking", "type"), nil, "nothing changed yet")
g.rows = 3
U.Toggle()                                           -- off, in combat
H.check(frame:IsShown(), "the bar can't be hidden in combat")
U.Toggle()                                           -- and back on
WoW.leaveCombat()
WoW.fire("PLAYER_REGEN_ENABLED")
H.check(not U.pending, "applied after combat")
H.eq(attr("leatherworking", "spell"), 2108, "the profession learned in combat")
H.check(frame:IsShown(), "on: the state after combat, not the one in between")

-- Disabled out of combat: every action cleared, the bar hidden.
U.Toggle()
H.check(not frame:IsShown(), "off: hidden")
for key, btn in pairs(U.buttons) do
    H.eq(btn:GetAttribute("type"), nil, "off: " .. key .. " has no action")
end
U.Toggle()

-- A profile switch rebuilds the bar: a profile from before the bar has it
-- off (defaults), with no bag or profession event.
Apotheca.SetProfile("Other")
tick()
H.eq(ApothecaDB.profiles.Other.utility.enabled, false, "an older profile gets the bar, off")
H.check(not frame:IsShown(), "and the switch hides it")
Apotheca.SetProfile("Global")
tick()
H.check(frame:IsShown(), "switching back shows it")

-- Dragging: interrupted by combat, finished after it, with no movement
-- call in combat (strictLockdown).
local anchor = ApothecaUtilityAnchor
frame._mouseOver, WoW.altDown = true, true
U.UpdateAnchor()
H.check(anchor:IsShown(), "Alt over the bar: the drag anchor")
anchor:GetScript("OnDragStart")(anchor)
H.check(frame._moving and U.dragging, "dragging")
WoW.enterCombat()
anchor:GetScript("OnDragStop")(anchor)               -- mouse up in combat
WoW.altDown = false
U.UpdateAnchor()
H.check(frame._moving, "no stop in combat: the client would refuse it")
H.check(U.dragStopPending, "the stop waits")
ApothecaCharDB = ApothecaCharDB or {}
ApothecaCharDB.utility = nil
WoW.leaveCombat()
WoW.fire("PLAYER_REGEN_ENABLED")
H.check(not frame._moving, "stopped after combat")
H.check(ApothecaCharDB.utility and ApothecaCharDB.utility.x, "the position saved, per character")
H.check(not U.dragging and not U.dragStopPending, "drag state cleared")
frame._mouseOver = false

-- Locks are separate.
g.lockPosition = true
WoW.altDown, frame._mouseOver = true, true
U.UpdateAnchor()
H.check(not anchor:IsShown(), "locked: no anchor")
H.eq(ApothecaDB.profiles.Global.lockPosition, false, "the main bar's lock is its own")
g.lockPosition = false
WoW.altDown, frame._mouseOver = false, false

-- The main bar keeps its own per-character position.
H.eq(type(ApothecaCharDB.utility), "table", "the profession bar saves under .utility")
H.eq(ApothecaCharDB.x, nil, "and leaves the main bar's position alone")

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
H.check(showCB and showCB:GetChecked(), "the enable box reflects the profile")
showCB:SetChecked(false)
showCB:GetScript("OnClick")(showCB)
tick()
H.eq(g.enabled, false, "unticked: off")
H.check(not frame:IsShown(), "and the bar hides")
showCB:SetChecked(true)
showCB:GetScript("OnClick")(showCB)
tick()
H.check(frame:IsShown(), "ticked again: shown")
local deCB = checkboxLabelled("Disenchant")
H.check(deCB and deCB:GetChecked(), "an action row, ticked")
deCB:SetChecked(false)
deCB:GetScript("OnClick")(deCB)
tick()
H.eq(g.show.disenchant, false, "unticking an action stores off")
H.eq(attr("disenchant", "type"), nil, "and clears its action")
deCB:SetChecked(true)
deCB:GetScript("OnClick")(deCB)
tick()
H.eq(g.show.disenchant, nil, "ticking it again stores nothing (shown is the default)")
H.eq(attr("disenchant", "spell"), 13262, "and Disenchant is back")

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
H.eq(count("Disenchant"), 1, "one Disenchant row after refreshes")

-- A /reload in combat: the saved position waits for the end of combat
-- (strictLockdown fails the test if it is set in combat).
ApothecaCharDB.utility = { x = 123, y = 456 }
WoW.enterCombat()
WoW.fire("PLAYER_LOGIN")
H.check(U.positionPending, "logged in during combat: the position waits")
WoW.leaveCombat()
WoW.fire("PLAYER_REGEN_ENABLED")
H.check(not U.positionPending, "restored after combat")
local pt = frame._points[#frame._points]
H.eq(pt and pt[4], 123, "at the saved x")
H.eq(pt and pt[5], 456, "and y")

-- Off: the first rebuild clears every action, later ones have nothing to do.
g.enabled = false
U.Reconcile()
H.check(U.cleared, "off: cleared once")
U.buttons.cooking:SetAttribute("type", "spell")       -- would be cleared again if it rebuilt
U.Reconcile()
H.eq(attr("cooking", "type"), "spell", "an off bar doesn't redo the clearing")
U.buttons.cooking:SetAttribute("type", nil)
g.enabled = true
U.Reconcile()
H.check(not U.cleared and frame:IsShown(), "on again: rebuilt")

H.done("test_utility")
