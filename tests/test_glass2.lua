-- Glass Action Bars' public API version 2 (#70): the player matches a
-- docked bar's size and spacing and its rows and direction separately, so
-- Layout(geom) carries only what is matched (GAB #48, its PUBLIC-API.md
-- "What changed in 2"). Apotheca asks for its own rows by default.
-- test_glass.lua covers version 1 and everything both versions share.

dofile("tests/wow_stubs.lua")
local H = dofile("tests/harness.lua")

WoW.AddItem(0, 1, 13444, 5, "Major Mana Potion")
WoW.AddItem(0, 2, 8079, 20, "Conjured Crystal Water")
WoW.AddItem(0, 3, 13446, 5, "Major Healing Potion")
WoW.AddItem(0, 4, 14530, 10, "Heavy Runecloth Bandage")

local GAB = { PUBLIC_API_VERSION = 2, skinned = {}, requests = 0 }
local client
function GAB.RegisterBar(def)
    if client then return false, "id '" .. def.id .. "' is already registered" end
    client = { def = def, hosted = false }
    return true
end
function GAB.RequestLayout(id)
    if client and id == client.def.id and not client.inLayout then GAB.requests = GAB.requests + 1 end
end
function GAB.SkinButton(button)
    GAB.skinned[button] = true
    return true
end
-- One dock pass, as Dock.lua's: out of combat only.
local function pass(geom)
    assert(not WoW.inCombat, "the dock never runs in combat")
    if not client.hosted then client.def.OnHosted(true) end
    client.inLayout = true
    client.def.Layout(geom)
    client.inLayout = false
    local f = client.def.frame
    f:ClearAllPoints()
    f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 900, 100)
    client.hosted = true
end
rawset(_G, "GlassActionBars", GAB)

H.loadAddon()
local db = ApothecaDB.profiles[ApothecaDB.activeProfile]

H.check(client, "registered on version 2")
H.check(GAB.skinned[Apotheca.buttons.mana], "skinned on version 2")
H.eq(type(client.def.default), "table", "a default is given")
H.eq(client.def.default.matchRows, false, "its own rows unless the player matches them (owner)")
H.eq(client.def.default.bar, nil, "not docked until the player docks it")

db.rows, db.orientation, db.iconSize, db.iconPadding = 2, "HORIZONTAL", 36, 3
Apotheca.UpdateAllButtons()
local shown = {}
for _, key in ipairs(Apotheca.GetButtonOrder()) do
    if Apotheca.buttons[key]:IsShown() then shown[#shown + 1] = key end
end
H.check(#shown >= 4, "several buttons on the bar")
local first = Apotheca.buttons[shown[1]]
local function grid(size, pad, cols, rows)
    return cols * size + (cols - 1) * pad, rows * size + (rows - 1) * pad
end
local function frameIs(what, w, h)
    H.eq(ApothecaFrame:GetWidth(), w, what .. ": width")
    H.eq(ApothecaFrame:GetHeight(), h, what .. ": height")
end

-- Size and spacing only (the default): Apotheca's two rows.
pass({ size = 40, padding = 5 })
local layout, matched = Apotheca.LayoutSettings()
H.check(matched, "size matched")
H.eq(layout.rows, 2, "own rows")
H.eq(layout.orientation, "HORIZONTAL", "own orientation")
H.check(not layout.dockRows, "the rows aren't the dock's")
H.eq(first:GetWidth(), 40, "the bar's size")
local cols = math.ceil(#shown / 2)
frameIs("two rows of the bar's size", grid(40, 5, cols, 2))

-- The options say what the dock decides, and grey out what it decides.
local panel = Apotheca.optionsPanel
panel._scripts.OnShow(panel)
local sliders = H.framesWithTemplate("OptionsSliderTemplate")
local function sliderLabelled(text)
    local found
    for _, s in ipairs(sliders) do
        if s.label and s.label:GetText() == text then found = found or s end
    end
    return found
end
local function noteSaying(text)
    for _, f in ipairs(WoW.fontStrings) do
        if type(f._text) == "string" and f._text:find(text, 1, true) then return f end
    end
end
local rowsSlider = sliderLabelled("Rows")
H.check(rowsSlider, "the Rows slider exists")
Apotheca.RefreshOptions()
H.check(noteSaying("Docked by Glass Action Bars: 40.0 px icons, 5.0 px apart.|r"), "note: size only")
H.check(rowsSlider:IsEnabled(), "rows are Apotheca's: the slider works")
H.check(not sliderLabelled("Icon Size"):IsEnabled(), "the size is the dock's: greyed out")

-- Both matched: the bar's rows and direction.
local before = GAB.requests
pass({ size = 40, padding = 5, rows = 1, orientation = 0 })
layout, matched = Apotheca.LayoutSettings()
H.check(matched and layout.dockRows, "both matched")
H.eq(layout.rows, 1, "the bar's rows")
frameIs("one row of the bar's size", grid(40, 5, #shown, 1))
H.eq(GAB.requests, before, "no request from inside Layout")
Apotheca.RefreshOptions()
H.check(noteSaying("40.0 px icons, 5.0 px apart; the bar's rows and direction."), "note: both")
H.check(not rowsSlider:IsEnabled(), "the rows are the dock's: greyed out")
H.eq(db.rows, 2, "the own rows are kept for later")

-- Rows only, on a vertical bar: rows are columns there, as Apotheca's own.
pass({ rows = 2, orientation = 1 })
layout, matched = Apotheca.LayoutSettings()
H.check(not matched, "size not matched")
H.eq(layout.orientation, "VERTICAL", "the bar's direction")
H.eq(layout.iconSize, 36, "own size")
frameIs("two columns of the own size", grid(36, 3, 2, math.ceil(#shown / 2)))
Apotheca.RefreshOptions()
H.check(noteSaying("Docked by Glass Action Bars: the bar's rows and direction.|r"), "note: rows only")
H.check(sliderLabelled("Icon Size"):IsEnabled(), "the size is Apotheca's again")

-- Nothing matched: all Apotheca's own.
pass(nil)
layout, matched = Apotheca.LayoutSettings()
H.check(not matched and not layout.dockRows, "nothing matched")
H.eq(layout.orientation, "HORIZONTAL", "own orientation back")
frameIs("the own grid", grid(36, 3, cols, 2))
H.check(noteSaying("Docked by Glass Action Bars, which places the bar."), "note: nothing matched")
H.check(rowsSlider:IsEnabled(), "rows slider back")

-- A rows value that makes no sense is ignored, not laid out.
pass({ size = 40, padding = 5, rows = 0, orientation = 0 })
H.check(not Apotheca.LayoutSettings().dockRows, "zero rows ignored")
pass({ size = 40, padding = 5, rows = 2, orientation = 7 })
H.check(not Apotheca.LayoutSettings().dockRows, "an unknown direction ignored")

H.done("test_glass2")
