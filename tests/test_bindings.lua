-- #49: named key bindings for the main bar. One CLICK binding per button,
-- and a button that isn't on the bar has no item: a binding clicks a
-- button even while it is hidden (measured on the profession bar).

dofile("tests/wow_stubs.lua")
local H = dofile("tests/harness.lua")

WoW.AddItem(0, 1, 13444, 5, "Major Mana Potion")
WoW.AddItem(0, 2, 14530, 10, "Heavy Runecloth Bandage")
H.loadAddon()
local db = ApothecaDB.profiles[ApothecaDB.activeProfile]
local B = Apotheca.buttons

-- Every button has a binding in the Apotheca category, a label and a name.
local xml = assert(io.open("Bindings.xml")):read("*a")
local bound = {}
for key, cat in xml:gmatch('<Binding name="CLICK ApothecaButton_(%w+):LeftButton" category="(%w+)"/>') do
    bound[key] = cat
end
local n = 0
for _, key in ipairs(Apotheca.DEFAULT_BUTTON_ORDER) do
    n = n + 1
    H.eq(bound[key], "Apotheca", "Bindings.xml: " .. key .. " in the Apotheca category")
    H.eq(_G["BINDING_NAME_CLICK ApothecaButton_" .. key .. ":LeftButton"], Apotheca.BUTTON_LABELS[key],
        "its label is the Button Order name: " .. key)
    H.check(_G["ApothecaButton_" .. key] == B[key], "its button exists from load: " .. key)
end
for key in pairs(bound) do
    H.check(Apotheca.ALL_BUTTON_KEYS[key], "no binding for an unknown button: " .. key)
end
H.check(n > 20, "every button is covered")

local function item(key) return B[key]:GetAttribute("item") end

-- On the bar: set up. Off it: nothing to click.
H.eq(item("mana"), "item:13444", "the mana potion button is set up")
H.eq(item("bandage"), "item:14530", "the bandage button is set up")
H.eq(item("flask"), nil, "no flask carried: the Flask button has no item")
H.eq(B.flask:GetAttribute("type"), nil, "and no type")

-- A button switched off loses its item, and nothing outside the full
-- update arms it again.
db.bandage.enabled = false
Apotheca.UpdateAllButtons()
H.check(not B.bandage:IsShown(), "Bandage switched off: hidden")
H.eq(item("bandage"), nil, "and its key does nothing")
WoW.fire("UNIT_AURA", "player")
H.eq(item("bandage"), nil, "an aura change doesn't arm it (the bandage debuff check)")
WoW.enterCombat()
WoW.leaveCombat()
H.eq(item("bandage"), nil, "nor does leaving combat")
Apotheca.SetDebug(true)
Apotheca.SetDebug(false)
H.eq(item("bandage"), nil, "nor does debug mode off")
H.eq(item("mana"), "item:13444", "while the mana potion stays set up")
db.bandage.enabled = true
Apotheca.UpdateAllButtons()
H.eq(item("bandage"), "item:14530", "switched back on: set up again")

-- Used up: the button has nothing to click.
WoW.bags[0][2] = nil
Apotheca.UpdateAllButtons()
H.eq(item("bandage"), nil, "the last bandage used: no item")

-- The Visibility setting only hides the bar: the keys keep working.
db.visibility = "HIDDEN"
Apotheca.UpdateAllButtons()
H.check(not ApothecaFrame:IsShown(), "Visibility Hidden: the bar is hidden")
H.eq(item("mana"), "item:13444", "and its mana potion key still works")
WoW.AddItem(0, 2, 14530, 10, "Heavy Runecloth Bandage")
Apotheca.UpdateAllButtons()
H.eq(item("bandage"), "item:14530", "a bandage picked up meanwhile is set up too")
db.visibility = "ALWAYS"

-- The bar switched off: every key does nothing.
db.enabled = false
Apotheca.UpdateAllButtons()
for key, btn in pairs(B) do
    H.eq(btn:GetAttribute("item"), nil, "bar off: no item on " .. key)
end
Apotheca.SetDebug(true)
Apotheca.SetDebug(false)
WoW.enterCombat()
WoW.leaveCombat()
H.eq(item("mana"), nil, "bar off: leaving combat doesn't arm a button")
db.enabled = true
Apotheca.UpdateAllButtons()
H.eq(item("mana"), "item:13444", "bar on again: set up")

-- Key text, as an action bar shows it.
WoW.bindings["CLICK ApothecaButton_mana:LeftButton"] = "CTRL-SHIFT-F"
WoW.fire("UPDATE_BINDINGS")
H.eq(B.mana.hotkey:GetText(), "csF", "the bound key shows on the button")
WoW.bindings["CLICK ApothecaButton_mana:LeftButton"] = nil
WoW.fire("UPDATE_BINDINGS")
H.eq(B.mana.hotkey:GetText(), "", "unbound: no key text")

-- In combat nothing secure changes (WoW.strictLockdown).
WoW.strictLockdown = true
WoW.enterCombat()
db.bandage.enabled = false
Apotheca.UpdateAllButtons()
Apotheca.ClearInactiveButtons()
WoW.fire("UNIT_AURA", "player")
WoW.fire("UPDATE_BINDINGS")
H.eq(item("bandage"), "item:14530", "in combat: unchanged until combat ends")
WoW.leaveCombat()
WoW.tick(1)
WoW.tick(1)
H.eq(item("bandage"), nil, "after combat: cleared")
WoW.strictLockdown = false

H.done("test_bindings")
