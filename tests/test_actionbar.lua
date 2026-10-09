-- Match Action Bar 1 (#40): the bar takes its icon size and padding from
-- the client's Action Bar 1 while the setting is on, and its own settings
-- otherwise or when the client doesn't say. Rows and orientation always
-- stay its own: it often sits beside several stacked action bars.

dofile("tests/wow_stubs.lua")
local H = dofile("tests/harness.lua")

WoW.AddItem(0, 1, 13444, 5, "Major Mana Potion")
WoW.AddItem(0, 2, 8079, 20, "Conjured Crystal Water")

H.loadAddon()
local db = Apotheca.GetDB and Apotheca.GetDB() or ApothecaDB.profiles[ApothecaDB.activeProfile]

local function shownButton()
    for _, key in ipairs(Apotheca.GetButtonOrder()) do
        local b = Apotheca.buttons[key]
        if b and b:IsShown() then return b end
    end
end

-- Off by default: the bar's own settings.
H.eq(db.matchBar, 0, "off by default")
Apotheca.UpdateAllButtons()
local btn = shownButton()
H.check(btn, "a button is shown")
H.eq(btn:GetWidth(), 36, "own icon size while off")

-- On: Action Bar 1 at 120%, padding 6, 2 rows, vertical (measured: a
-- 54 px button 7.2 px apart).
WoW.actionBar = { [0] = 1, [1] = 2, [2] = 12, [3] = 120, [4] = 6 }
db.rows = 3
db.matchBar = 1
local layout, matched = Apotheca.LayoutSettings()
H.check(matched, "matched while on and readable")
H.eq(layout.orientation, "HORIZONTAL", "orientation stays the bar's own")
H.eq(layout.rows, 3, "rows stay the bar's own")
H.check(math.abs(layout.iconSize - 54) < 1e-9, "icon size 45 x 120% = 54")
H.check(math.abs(layout.iconPadding - 7.2) < 1e-9, "padding scales with the icon size: 6 x 1.2")
Apotheca.UpdateAllButtons()
H.check(math.abs(btn:GetWidth() - 54) < 1e-9, "buttons take Action Bar 1's size")
H.eq(db.iconSize, 36, "the bar's own size is kept for switching off")

-- A change made in Edit Mode fires nothing: the out-of-combat poll sees it.
WoW.actionBar = { [0] = 0, [1] = 1, [2] = 12, [3] = 90, [4] = 2 }
WoW.tick(3)
WoW.tick(1)
H.check(math.abs(btn:GetWidth() - 40.5) < 1e-9, "the poll follows a live change (90% = 40.5)")

-- The poll costs nothing while nothing changed.
local seq = Apotheca._updateSeq
WoW.tick(3)
WoW.tick(1)
H.eq(Apotheca._updateSeq, seq, "no update while Action Bar 1 is unchanged")

-- A saved or switched layout fires EDIT_MODE_LAYOUTS_UPDATED.
H.check(WoW.events[ApothecaEventFrame]["EDIT_MODE_LAYOUTS_UPDATED"], "the layout event is registered")
WoW.actionBar = { [0] = 0, [1] = 1, [2] = 12, [3] = 100, [4] = 2 }
WoW.fire("EDIT_MODE_LAYOUTS_UPDATED")
WoW.tick(1)
H.check(math.abs(btn:GetWidth() - 45) < 1e-9, "a layout switch is followed")

-- Unreadable: the bar's own settings, never an error.
WoW.actionBarThrow = true
layout, matched = Apotheca.LayoutSettings()
H.check(not matched, "a refused read falls back")
H.eq(layout.iconSize, 36, "to the bar's own settings")
Apotheca.UpdateAllButtons()
H.eq(btn:GetWidth(), 36, "and the buttons follow the fallback")
WoW.actionBarThrow = false

WoW.actionBar = { [0] = 0, [1] = 1, [2] = 12, [4] = 2 }   -- no icon size
H.check(not select(2, Apotheca.LayoutSettings()), "a missing value falls back")
WoW.actionBar = { [0] = 0, [1] = 1, [2] = 12, [3] = 100, [4] = 2 }
Apotheca.UpdateAllButtons()
H.check(math.abs(btn:GetWidth() - 45) < 1e-9, "readable again: 100% = 45")

-- In combat the poll waits: the secure buttons can't be resized.
WoW.enterCombat()
WoW.actionBar = { [0] = 0, [1] = 1, [2] = 12, [3] = 150, [4] = 2 }
WoW.tick(3)
H.check(math.abs(btn:GetWidth() - 45) < 1e-9, "no resize in combat")
WoW.leaveCombat()
WoW.tick(1)
H.check(math.abs(btn:GetWidth() - 67.5) < 1e-9, "resized after combat (150% = 67.5)")

-- Another bar: Action Bar 3 at 80%, padding 4.
WoW.actionBars[3] = { [3] = 80, [4] = 4 }
db.matchBar = 3
layout, matched = Apotheca.LayoutSettings()
H.check(matched, "bar 3 is read")
H.check(math.abs(layout.iconSize - 36) < 1e-9 and math.abs(layout.iconPadding - 3.2) < 1e-9,
    "bar 3's own size and padding (45 x 80% = 36, 4 x 0.8 = 3.2)")
db.matchBar = 9
H.check(not select(2, Apotheca.LayoutSettings()), "a bar number out of range falls back")

-- Off again: back to the bar's own settings.
db.matchBar = 0
Apotheca.UpdateAllButtons()
H.eq(btn:GetWidth(), 36, "own settings once switched off")

-- The options panel: the layout controls grey out while matching.
local panel = Apotheca.optionsPanel
H.check(panel, "the options panel exists")
panel._scripts.OnShow(panel)
local sliders = H.framesWithTemplate("OptionsSliderTemplate")
local function sliderLabelled(text)
    for _, s in ipairs(sliders) do
        if s.label and s.label:GetText() == text then return s end
    end
end
local size = sliderLabelled("Icon Size")
H.check(size, "the Icon Size slider exists")
H.check(size:IsEnabled(), "enabled while off")
db.matchBar = 1
Apotheca.RefreshOptions()
H.check(not size:IsEnabled(), "greyed out while matching")
H.check(not sliderLabelled("Icon Padding"):IsEnabled(), "padding too")
H.check(sliderLabelled("Rows"):IsEnabled(), "rows stay the bar's own setting")
WoW.actionBarThrow = true
Apotheca.RefreshOptions()
H.check(size:IsEnabled(), "enabled again when Action Bar 1 can't be read")
WoW.actionBarThrow = false

H.done("test_actionbar")
