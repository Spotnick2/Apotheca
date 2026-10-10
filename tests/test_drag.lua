-- #46: a drag of the main bar that combat interrupts. The client refuses to
-- stop it in combat, so the stop waits for the end of combat, and the bar
-- goes back to where combat caught it: that is what's saved, not wherever
-- the cursor ends up. Nothing protected is touched in combat
-- (WoW.strictLockdown).

dofile("tests/wow_stubs.lua")
local H = dofile("tests/harness.lua")

WoW.AddItem(0, 1, 13444, 5, "Major Mana Potion")
WoW.strictLockdown = true
H.loadAddon()
Apotheca.UpdateAllButtons()

local frame, anchor = ApothecaFrame, ApothecaAnchor
H.check(frame._protected, "the bar parents secure buttons")

local function startDrag()
    frame._mouseOver, WoW.altDown = true, true
    WoW.tick(0.2)
    H.check(anchor:IsShown(), "Alt over the bar: the drag anchor")
    anchor:GetScript("OnDragStart")(anchor)
    H.check(frame._moving, "dragging")
end

-- An ordinary drag saves where it ends.
startDrag()
frame._left, frame._bottom = 400, 300
anchor:GetScript("OnDragStop")(anchor)
H.check(not frame._moving, "stopped")
H.eq(ApothecaCharDB.x, 400, "saved where it was dropped")

-- Combat catches the drag with Alt still held.
startDrag()
frame._left, frame._bottom = 300, 250
WoW.enterCombat()
WoW.tick(0.2)                                       -- the anchor poll sees combat
H.check(frame._moving, "no stop in combat: the client would refuse it")
H.check(not anchor:IsShown(), "the anchor hides")
frame._left, frame._bottom = 900, 500              -- it still follows the cursor
WoW.tick(0.2)
anchor:GetScript("OnDragStop")(anchor)               -- mouse up in combat
H.check(frame._moving, "still no stop")
H.eq(ApothecaCharDB.x, 400, "nothing saved in combat")

-- Combat ends with Alt still held: the drag ends, it doesn't carry on.
WoW.leaveCombat()
WoW.fire("PLAYER_REGEN_ENABLED")
H.check(not frame._moving, "stopped after combat")
H.eq(ApothecaCharDB.x, 300, "where combat caught it, not where the cursor ended")
H.eq(ApothecaCharDB.y, 250, "both coordinates")
WoW.tick(0.2)
H.check(not frame._moving, "Alt still held after combat doesn't restart it")

-- Combat interrupting, then the anchor poll ending it before the event.
frame._left, frame._bottom = nil, nil
startDrag()
frame._left, frame._bottom = 120, 80
WoW.enterCombat()
WoW.tick(0.2)
frame._left, frame._bottom = 700, 600
WoW.leaveCombat()
WoW.tick(0.2)                                       -- out of combat, event not yet fired
H.check(not frame._moving, "the poll finishes it once combat is over")
H.eq(ApothecaCharDB.x, 120, "at the point combat caught it")
WoW.fire("PLAYER_REGEN_ENABLED")
H.eq(ApothecaCharDB.x, 120, "the event after changes nothing")

H.done("test_drag")
