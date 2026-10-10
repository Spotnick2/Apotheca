-- #46: a drag of the main bar that combat interrupts. PLAYER_REGEN_DISABLED
-- fires before lockdown, so the drag is stopped there, where it is. If
-- lockdown is already on, the client refuses the stop: the bar follows the
-- cursor until combat ends, the anchor stays up so clicks can't reach a
-- secure button, and the bar then goes back to where combat caught it,
-- which is what's saved. Nothing protected is touched in combat
-- (WoW.strictLockdown).

dofile("tests/wow_stubs.lua")
local H = dofile("tests/harness.lua")

WoW.AddItem(0, 1, 13444, 5, "Major Mana Potion")
WoW.strictLockdown = true
H.loadAddon()
Apotheca.UpdateAllButtons()

local frame, anchor = ApothecaFrame, ApothecaAnchor
H.check(frame._protected, "the bar parents secure buttons")

local function startDrag(x, y)
    frame._left, frame._bottom = nil, nil
    frame._mouseOver, WoW.altDown = true, true
    WoW.tick(0.2)
    H.check(anchor:IsShown(), "Alt over the bar: the drag anchor")
    anchor:GetScript("OnDragStart")(anchor)
    H.check(frame._moving, "dragging")
    frame._left, frame._bottom = x, y
end

-- An ordinary drag saves where it ends.
startDrag(400, 300)
anchor:GetScript("OnDragStop")(anchor)
H.check(not frame._moving, "stopped")
H.eq(ApothecaCharDB.x, 400, "saved where it was dropped")

-- Combat with Alt held: stopped at PLAYER_REGEN_DISABLED, before lockdown.
startDrag(350, 260)
WoW.enterCombat()
H.check(not frame._moving, "stopped cleanly as combat starts")
H.eq(ApothecaCharDB.x, 350, "saved where it was")
WoW.tick(0.2)
H.check(not anchor:IsShown(), "the anchor hides in combat")
WoW.leaveCombat()

-- Lockdown already on at the event: the stop waits.
startDrag(300, 250)
WoW.enterLockdown()
WoW.tick(0.2)
H.check(frame._moving, "no stop in lockdown: the client would refuse it")
H.check(anchor:IsShown(), "the anchor stays up: no click reaches a button under the cursor")
frame._left, frame._bottom = 900, 500              -- it still follows the cursor
WoW.tick(0.2)
anchor:GetScript("OnDragStop")(anchor)               -- mouse up in combat
H.check(frame._moving and anchor:IsShown(), "still waiting, anchor still up")
H.eq(ApothecaCharDB.x, 350, "nothing saved in combat")
-- Combat over with Alt still held, the poll before the event.
WoW.inCombat, WoW.aurasThrow = false, false
WoW.tick(0.2)
H.check(not frame._moving, "the poll finishes it once combat is over, Alt held or not")
H.eq(ApothecaCharDB.x, 300, "where combat caught it, not where the cursor ended")
H.eq(ApothecaCharDB.y, 250, "both coordinates")
WoW.fire("PLAYER_REGEN_ENABLED")
H.eq(ApothecaCharDB.x, 300, "the event after changes nothing")
WoW.tick(0.2)
H.check(not frame._moving, "Alt still held doesn't restart it")

-- Lockdown, then the event ends it.
startDrag(120, 80)
WoW.enterLockdown()
frame._left, frame._bottom = 700, 600
WoW.altDown = false
WoW.leaveCombat()
H.check(not frame._moving, "PLAYER_REGEN_ENABLED finishes it")
H.check(not anchor:IsShown(), "and the anchor hides with Alt up")
H.eq(ApothecaCharDB.x, 120, "at the point combat caught it")

-- A logout while it waits saves where combat caught it.
startDrag(220, 180)
WoW.enterLockdown()
frame._left, frame._bottom = 800, 700
WoW.fire("PLAYER_LOGOUT")
H.eq(ApothecaCharDB.x, 220, "logout saves where combat caught it, not the cursor's spot")
WoW.leaveCombat()

-- No position when combat caught it: the last saved spot, not the cursor's.
startDrag(false, false)
WoW.enterLockdown()
frame._left, frame._bottom = 650, 550
WoW.leaveCombat()
H.check(not frame._moving, "stopped")
H.eq(ApothecaCharDB.x, 220, "the last saved position stands")
frame._left, frame._bottom = nil, nil

H.done("test_drag")
