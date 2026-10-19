-- Glass Action Bars (#68): with GAB installed the bar docks through its
-- public API (RegisterBar) and every button wears its glass (SkinButton).
-- The fake below follows GAB's contract (its docs/PUBLIC-API.md and
-- Dock.lua): OnHosted(true) once, then Layout(geom) on every placement,
-- then the frame is placed; RequestLayout from inside Layout is ignored.

dofile("tests/wow_stubs.lua")
local H = dofile("tests/harness.lua")

WoW.AddItem(0, 1, 13444, 5, "Major Mana Potion")
WoW.AddItem(0, 2, 8079, 20, "Conjured Crystal Water")
WoW.AddItem(0, 3, 13446, 5, "Major Healing Potion")

-- Every other test runs without GAB (GlassActionBars is nil): the bar is
-- unchanged there. The end of this file checks the button directly.

local GAB = { PUBLIC_API_VERSION = 1, skinned = {}, owners = {}, requests = 0 }
local client
function GAB.RegisterBar(def)
    if client then return false, "id '" .. def.id .. "' is already registered" end
    client = { def = def, hosted = false }
    return true
end
function GAB.RequestLayout(id)
    if client and id == client.def.id and not client.inLayout then GAB.requests = GAB.requests + 1 end
end
function GAB.SkinButton(button, regions, owner)
    GAB.skinned[button] = regions
    GAB.owners[#GAB.owners + 1] = owner
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
local function release()
    client.hosted = false
    client.def.OnHosted(false)
end
rawset(_G, "GlassActionBars", GAB)

ApothecaCharDB = { point = "BOTTOMLEFT", x = 321, y = 123 }
H.loadAddon()
local db = Apotheca.GetDB and Apotheca.GetDB() or ApothecaDB.profiles[ApothecaDB.activeProfile]

-- Registration at login.
H.check(client, "the bar is registered")
H.eq(client.def.id, "apotheca", "a stable dock id")
H.eq(client.def.frame, ApothecaFrame, "the main bar's frame")
H.check(not Apotheca.DockHosted(), "not docked until GAB says so")

-- Every button wears the glass, on both bars.
local mana = Apotheca.buttons.mana
local r = GAB.skinned[mana]
H.check(r, "a main bar button is skinned")
H.eq(r.icon, mana.icon, "icon region")
H.eq(r.cooldown, mana.cooldown, "cooldown region")
H.eq(r.count, mana.countText, "count region")
H.eq(r.hotkey, mana.hotkey, "hotkey region")
H.eq(r.highlight, mana.highlightTex, "highlight region")
H.eq(r.border, mana.btnBorder, "border region (for GAB's border key)")
H.eq(r.empty, mana.emptyBg, "empty region (for GAB's empty key)")
H.check(not mana.btnBorder:IsShown(), "the bronze frame goes under glass")
H.check(not mana.emptyBg:IsShown(), "the empty-slot art goes under glass")
for key, btn in pairs(Apotheca.buttons) do
    H.check(GAB.skinned[btn], "skinned: " .. key)
end
for key, btn in pairs(Apotheca.Utility.buttons) do
    H.check(GAB.skinned[btn], "profession bar skinned: " .. key)
end
H.eq(GAB.owners[1], "Apotheca", "the owner names Apotheca for Glass UI's page")

-- The icon stays Apotheca's: an empty button still greys out under glass.
Apotheca.UpdateAllButtons()
local shown = {}
for _, key in ipairs(Apotheca.GetButtonOrder()) do
    if Apotheca.buttons[key]:IsShown() then shown[#shown + 1] = key end
end
H.check(#shown >= 2, "several buttons on the bar")

-- ------------------------------------------------------------
-- Docked: matching a bar takes its size and padding only.
-- ------------------------------------------------------------
db.rows = 2
db.orientation = "HORIZONTAL"
db.matchBar = 1
WoW.actionBar = { [0] = 0, [1] = 1, [2] = 12, [3] = 120, [4] = 6 }
Apotheca.UpdateAllButtons()
pass({ size = 40, padding = 5, rows = 1, orientation = 1 })
H.check(Apotheca.DockHosted(), "docked")
local layout, matched = Apotheca.LayoutSettings()
H.check(matched, "matched while the dock matches")
H.eq(layout.iconSize, 40, "the dock's size, not matchBar's")
H.eq(layout.iconPadding, 5, "the dock's padding")
H.eq(layout.rows, 2, "rows stay Apotheca's own (owner)")
H.eq(layout.orientation, "HORIZONTAL", "orientation stays Apotheca's own (owner)")
local first = Apotheca.buttons[shown[1]]
H.eq(first:GetWidth(), 40, "buttons take the matched size")
local pt = first._points[1]
H.eq(pt[4], 0, "no margin around the buttons while docked (x)")
H.eq(pt[5], 0, "no margin around the buttons while docked (y)")
local cols = math.ceil(#shown / 2)
H.eq(ApothecaFrame:GetWidth(), cols * 40 + (cols - 1) * 5, "the frame is exactly its buttons")

-- Not matching: the bar's own size, not matchBar's.
pass(nil)
layout, matched = Apotheca.LayoutSettings()
H.check(not matched, "own geometry when the dock doesn't match")
H.eq(layout.iconSize, db.iconSize, "own icon size, matchBar waits")
H.eq(first:GetWidth(), db.iconSize, "buttons back to the own size")

-- Nothing of Apotheca's moves a docked bar.
ApothecaCharDB.x, ApothecaCharDB.y = 321, 123
WoW.fire("PLAYER_ENTERING_WORLD")
WoW.tick(1)
H.eq(ApothecaFrame._points[1][4], 900, "zoning doesn't restore the saved spot over the dock")
WoW.fire("PLAYER_LOGOUT")
H.eq(ApothecaCharDB.x, 321, "logout doesn't save the docked spot")
H.eq(ApothecaCharDB.y, 123, "logout keeps the saved y")
WoW.altDown = true
ApothecaFrame._mouseOver = true
WoW.tick(0.2)
H.check(not ApothecaAnchor:IsShown(), "no Alt+Drag anchor while docked")
ApothecaAnchor:GetScript("OnDragStart")()
H.check(not ApothecaFrame._moving, "no drag while docked")
WoW.altDown = false
ApothecaFrame._mouseOver = false
WoW.tick(0.2)

-- The poll and Edit Mode lay nothing out for matchBar while docked.
local seq = Apotheca._updateSeq
WoW.actionBar = { [0] = 0, [1] = 1, [2] = 12, [3] = 90, [4] = 2 }
WoW.tick(3)
WoW.tick(1)
H.eq(Apotheca._updateSeq, seq, "matchBar's poll is idle while docked")

-- A changed grid asks to be placed again; an unchanged one doesn't.
local before = GAB.requests
Apotheca.UpdateAllButtons()
H.eq(GAB.requests, before, "no request while the grid is unchanged")
WoW.AddItem(1, 1, 14530, 10, "Heavy Runecloth Bandage")
Apotheca.UpdateAllButtons()
H.eq(GAB.requests, before + 1, "a new button asks to be placed again")
db.rows = 1
Apotheca.UpdateAllButtons()
H.eq(GAB.requests, before + 2, "a changed row count asks too")

-- In combat nothing is laid out, and nothing is asked.
WoW.strictLockdown = true
WoW.enterCombat()
Apotheca.UpdateAllButtons()
H.eq(GAB.requests, before + 2, "no request in combat")
WoW.leaveCombat()
WoW.tick(1)
WoW.strictLockdown = false

-- ------------------------------------------------------------
-- Undocked: the saved spot and the bar's own layout come back.
-- ------------------------------------------------------------
release()
H.check(not Apotheca.DockHosted(), "undocked")
H.eq(ApothecaFrame._points[1][4], 321, "the saved spot comes back")
layout, matched = Apotheca.LayoutSettings()
H.check(matched, "matchBar applies again")
H.eq(first:GetWidth(), 40.5, "matchBar's size again (90%)")
WoW.altDown = true
ApothecaFrame._mouseOver = true
WoW.tick(0.2)
H.check(ApothecaAnchor:IsShown(), "Alt+Drag is back")
WoW.altDown = false
ApothecaFrame._mouseOver = false
WoW.tick(0.2)

-- A drag in progress when the dock takes the bar ends and is saved first.
WoW.altDown = true
ApothecaFrame._mouseOver = true
WoW.tick(0.2)
ApothecaAnchor:GetScript("OnDragStart")()
H.check(ApothecaFrame._moving, "dragging")
ApothecaFrame._left, ApothecaFrame._bottom = 555, 66
pass(nil)
H.check(not ApothecaFrame._moving, "the drag stopped when docked")
H.eq(ApothecaCharDB.x, 555, "the drop was saved before docking")
H.check(not ApothecaAnchor:IsShown(), "the anchor hid")
WoW.altDown = false
ApothecaFrame._mouseOver = false

-- ------------------------------------------------------------
-- A GAB with another API version is left alone.
-- ------------------------------------------------------------
GAB.PUBLIC_API_VERSION = 2
H.eq(Apotheca.WearGlass(Apotheca.buttons.health), false, "no skin from an incompatible GAB")
rawset(_G, "GlassActionBars", nil)
H.eq(Apotheca.WearGlass(Apotheca.buttons.health), false, "no skin without GAB")

H.done("test_glass")
