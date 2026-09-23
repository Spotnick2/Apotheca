-- What the Forever port must guarantee, measured on build 69977
-- (docs/FOREVER-PROBE.md and PORTING-TBC-TO-FOREVER.md).

dofile("tests/wow_stubs.lua")
local H = dofile("tests/harness.lua")

WoW.AddItem(0, 1, 13444, 5, "Major Mana Potion")
WoW.AddItem(0, 2, 5512, 1, "Minor Healthstone")
WoW.AddItem(0, 3, 9421, 1, "Major Healthstone")
WoW.AddItem(5, 1, 3928, 7, "Superior Healing Potion")   -- reagent bag, bag 5
H.loadAddon()

------------------------------------------------------------
-- Secure buttons: both edges, and never a typerelease
------------------------------------------------------------
local secure = H.framesWithTemplate("SecureActionButtonTemplate")
H.check(#secure > 0, "secure buttons were created")
for _, b in ipairs(secure) do
    local c = b._clicks or {}
    local set = {}
    for _, v in ipairs(c) do set[v] = true end
    H.check(set.AnyUp and set.AnyDown and #c == 2,
        b:GetName() .. " registers exactly AnyUp and AnyDown (the client picks the edge)")
    H.eq(b:GetAttribute("typerelease"), nil, b:GetName() .. " sets no typerelease (it would double-use)")
end

------------------------------------------------------------
-- Bag scan covers the reagent bag
------------------------------------------------------------
local bagMap = Apotheca.BuildBagMap()
H.eq(bagMap[3928], 7, "an item in the reagent bag (5) is counted")
H.eq(bagMap[13444], 5, "an item in the backpack is counted")

local mana = Apotheca.buttons.mana
H.eq(mana and mana:GetAttribute("item"), "item:13444", "mana button is wired to the potion")
H.eq(mana and mana:GetAttribute("type"), "item", "mana button type is item")

------------------------------------------------------------
-- Secret health: health-dependent features stay dormant
------------------------------------------------------------
WoW.healthSecret = true
H.eq(Apotheca.API.PlayerMissing(), nil, "secret health reads as unknown, and does not throw")

local id = Apotheca.FindBestHealthstone(Apotheca.BuildBagMap())
H.eq(id, 9421, "with health unreadable, the strongest healthstone is offered")

-- Readable health (a future client): smart rank works again.
WoW.healthSecret = false
WoW.health = 950
local missing = Apotheca.API.PlayerMissing()
H.eq(missing, 50, "readable health gives the plain missing amount")
id = Apotheca.FindBestHealthstone(Apotheca.BuildBagMap())
H.eq(id, 5512, "with 50 missing health, smart rank picks the smallest stone that covers it")
WoW.health = 1000
WoW.healthSecret = true

------------------------------------------------------------
-- Auras: blocked is not "missing"
------------------------------------------------------------
WoW.SetAura("HELPFUL", "Well Fed", 19710)
H.eq(Apotheca.HasFoodBuff(), true, "an aura is found out of combat")
WoW.aurasThrow = true
H.eq(Apotheca.HasFoodBuff(), nil, "a refused aura read is unknown (nil), not false")
WoW.aurasThrow = false

-- A ready check running when combat starts must not glow a scroll whose
-- buff it simply cannot see: unknown is not missing. ShowGlow creates
-- btn.__apothecaGlow, so its absence proves no glow was ever requested.
WoW.AddItem(1, 1, 10306, 3, "Scroll of Spirit V")
Apotheca.UpdateAllButtons()
local spirit = Apotheca.buttons.spiritscroll
H.check(spirit and spirit.itemID == 10306, "the spirit scroll button holds the scroll")

-- Positive control: out of combat, buff genuinely missing -> it glows.
WoW.fire("READY_CHECK")
H.check(spirit.__apothecaGlow ~= nil, "a missing spirit buff glows during a ready check")
WoW.fire("READY_CHECK_FINISHED")

-- Now: buff present, but combat hides it.
spirit.__apothecaGlow = nil
WoW.SetAura("HELPFUL", "Scroll of Spirit", 12177)
WoW.fire("READY_CHECK")
H.eq(spirit.__apothecaGlow, nil, "no glow when the buff is visibly present")
WoW.enterCombat()                       -- PLAYER_REGEN_DISABLED re-evaluates the glows
H.eq(spirit.__apothecaGlow, nil, "no glow in combat when the aura read is refused")
WoW.leaveCombat()
WoW.fire("READY_CHECK_FINISHED")

------------------------------------------------------------
-- Events: a rejected registration is reported, not swallowed
------------------------------------------------------------
local f = CreateFrame("Frame")
WoW.badEvents.NOT_AN_EVENT = true
WoW.refusedEvents.REFUSED_EVENT = true
local ok, failed = Apotheca.API.RegisterEvents(f, "BAG_UPDATE", "NOT_AN_EVENT", "REFUSED_EVENT")
H.eq(ok, false, "RegisterEvents reports failure")
H.eq(#failed, 2, "both a throw and a false return count as failures")
H.check(H.messagesMatching("NOT_AN_EVENT") > 0, "the rejected event is printed")

------------------------------------------------------------
-- SavedVariables: sentinel detection
------------------------------------------------------------
H.check(H.messagesMatching("does not load addon settings") == 1,
    "players are told settings reset when nothing loaded")

H.done("test_forever")
