-- Executes every event handler, OnUpdate and slash command the addon
-- installs. Strict globals only catch code that actually runs, and a handler
-- nothing calls is exactly where a removed API hides.

dofile("tests/wow_stubs.lua")
local H = dofile("tests/harness.lua")

WoW.AddItem(0, 1, 13444, 5, "Major Mana Potion")
WoW.AddItem(0, 2, 8079, 20, "Conjured Crystal Water")
WoW.AddItem(5, 1, 14530, 10, "Heavy Runecloth Bandage")   -- reagent bag

H.loadAddon()

local EVENTS = {
    "BAG_UPDATE_DELAYED", "BAG_UPDATE_COOLDOWN", "GET_ITEM_INFO_RECEIVED",
    "UNIT_AURA", "UNIT_HEALTH", "UNIT_POWER_UPDATE", "READY_CHECK",
    "READY_CHECK_FINISHED", "ZONE_CHANGED_NEW_AREA", "PLAYER_TALENT_UPDATE",
    "MODIFIER_STATE_CHANGED",
}

local function fireAll()
    for _, e in ipairs(EVENTS) do WoW.fire(e, "player") end
    WoW.tick(1)
    WoW.tick(1)
end

fireAll()
H.check(true, "every event runs out of combat")

WoW.enterCombat()
fireAll()
H.check(true, "every event runs in combat, with auras throwing and health secret")
-- Worst case, not yet measured: cooldowns and stack counts secret too.
WoW.combatSecret = true
fireAll()
H.check(true, "bag and cooldown refreshes survive secret cooldowns and counts")
WoW.combatSecret = false
WoW.leaveCombat()
fireAll()

-- Readable health (a future client): the same handlers must still run.
WoW.healthSecret = false
fireAll()
WoW.healthSecret = true

for _, cmd in ipairs({ "", "status", "debug", "debug", "probe", "reset", "help" }) do
    SlashCmdList["APOTHECA"](cmd)
end
WoW.enterCombat()
SlashCmdList["APOTHECA"]("status")
SlashCmdList["APOTHECA"]("probe")
WoW.leaveCombat()
H.check(true, "every slash command runs, in and out of combat")

-- /apo scan walks the whole item-ID range over many frames.
SlashCmdList["APOTHECA"]("scan")
for _ = 1, 200 do WoW.tick(1) end
local scan = ApothecaDB.itemScan
H.check(scan and scan.items[13444] and scan.items[13444].t, "the scan records a known consumable with its tooltip")
H.eq(scan and scan.items[13444].t[2], "Use: Restores 61 health over 18 sec.", "tooltip text is kept verbatim")

-- /apo scan2 fills in spell text for anything whose tooltip lacked it.
scan.items[13444].t = { "Major Mana Potion" }
SlashCmdList["APOTHECA"]("scan2")
for _ = 1, 200 do WoW.tick(1) end
H.eq(scan.items[13444].d, "Restores 61 health over 18 sec.", "the second pass records the spell description")

-- Every button's scripts.
for key, btn in pairs(Apotheca.buttons) do
    for _, script in ipairs({ "OnEnter", "OnLeave", "PreClick", "PostClick" }) do
        local h = btn:GetScript(script)
        if h then h(btn, "LeftButton", true) end
    end
    if btn._askOverlay then
        local h = btn._askOverlay:GetScript("OnClick")
        if h then h(btn._askOverlay, "LeftButton") ; h(btn._askOverlay, "RightButton") end
    end
end
H.check(true, "button scripts run")

-- Popups.
for name, dlg in pairs(StaticPopupDialogs) do
    if name:match("^APOTHECA") and dlg.OnAccept then
        dlg.OnAccept({ data = { btnKey = "drink", altItemID = 8079 } })
    end
end
H.check(true, "popup accept handlers run")

-- Drag anchor with Alt held.
WoW.altDown = true
WoW.fire("MODIFIER_STATE_CHANGED", "LALT", 1)
WoW.tick(1)
WoW.altDown = false
WoW.fire("MODIFIER_STATE_CHANGED", "LALT", 0)
WoW.tick(1)

WoW.fire("PLAYER_LOGOUT")
H.check(ApothecaDB.svLoadCheck ~= nil, "the SavedVariables sentinel is written every session")

H.eq(H.messagesMatching("rejected event"), 0, "no event was rejected")

H.done("test_frames")
