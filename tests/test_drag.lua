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
check(frame._protected, "the bar parents secure buttons")

local function startDrag(x, y)
    frame._left, frame._bottom = nil, nil
    frame._mouseOver, WoW.altDown = true, true
    WoW.step(0.2)
    check(anchor:IsShown(), "Alt over the bar: the drag anchor")
    anchor:GetScript("OnDragStart")(anchor)
    check(frame._moving, "dragging")
    frame._left, frame._bottom = x, y
end

-- An ordinary drag saves where it ends.
startDrag(400, 300)
anchor:GetScript("OnDragStop")(anchor)
check(not frame._moving, "stopped")
eq(ApothecaCharDB.x, 400, "saved where it was dropped")

-- Combat with Alt held: stopped at PLAYER_REGEN_DISABLED, before lockdown.
startDrag(350, 260)
WoW.enterCombat()
check(not frame._moving, "stopped cleanly as combat starts")
eq(ApothecaCharDB.x, 350, "saved where it was")
WoW.step(0.2)
check(not anchor:IsShown(), "the anchor hides in combat")
WoW.leaveCombat()

-- Lockdown already on at the event: the stop waits.
startDrag(300, 250)
WoW.enterLockdown()
WoW.step(0.2)
check(frame._moving, "no stop in lockdown: the client would refuse it")
check(anchor:IsShown(), "the anchor stays up: no click reaches a button under the cursor")
frame._left, frame._bottom = 900, 500              -- it still follows the cursor
WoW.step(0.2)
anchor:GetScript("OnDragStop")(anchor)               -- mouse up in combat
check(frame._moving and anchor:IsShown(), "still waiting, anchor still up")
eq(ApothecaCharDB.x, 350, "nothing saved in combat")
-- Combat over with Alt still held, the poll before the event.
WoW.combat, WoW.aurasThrow = false, false
WoW.step(0.2)
check(not frame._moving, "the poll finishes it once combat is over, Alt held or not")
eq(ApothecaCharDB.x, 300, "where combat caught it, not where the cursor ended")
eq(ApothecaCharDB.y, 250, "both coordinates")
WoW.fire("PLAYER_REGEN_ENABLED")
eq(ApothecaCharDB.x, 300, "the event after changes nothing")
WoW.step(0.2)
check(not frame._moving, "Alt still held doesn't restart it")

-- Lockdown, then the event ends it.
startDrag(120, 80)
WoW.enterLockdown()
frame._left, frame._bottom = 700, 600
WoW.altDown = false
WoW.leaveCombat()
check(not frame._moving, "PLAYER_REGEN_ENABLED finishes it")
check(not anchor:IsShown(), "and the anchor hides with Alt up")
eq(ApothecaCharDB.x, 120, "at the point combat caught it")

-- A logout while it waits saves where combat caught it.
startDrag(220, 180)
WoW.enterLockdown()
frame._left, frame._bottom = 800, 700
WoW.fire("PLAYER_LOGOUT")
eq(ApothecaCharDB.x, 220, "logout saves where combat caught it, not the cursor's spot")
WoW.leaveCombat()

-- No position when combat caught it: the last saved spot, not the cursor's.
startDrag(false, false)
WoW.enterLockdown()
frame._left, frame._bottom = 650, 550
WoW.leaveCombat()
check(not frame._moving, "stopped")
eq(ApothecaCharDB.x, 220, "the last saved position stands")
frame._left, frame._bottom = nil, nil

done("test_drag")
