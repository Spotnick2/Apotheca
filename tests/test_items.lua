-- The generated item data (ApothecaItems.lua) and how the addon reads it.
-- The values themselves come from the client's tooltips; these tests pin
-- the shape and the decisions built on it.

dofile("tests/wow_stubs.lua")
local H = dofile("tests/harness.lua")
H.loadAddon()
local D = Apotheca.DATA

local function bagWith(...)
    local m = {}
    for i = 1, select("#", ...) do m[select(i, ...)] = 1 end
    return m
end

------------------------------------------------------------
-- Shape: strongest first, no duplicates, every value positive
------------------------------------------------------------
local function descending(list, field, name)
    local seen, prev = {}, math.huge
    for i, e in ipairs(list) do
        local id = type(e) == "table" and e.id or e
        check(not seen[id], name .. ": item " .. id .. " listed once")
        seen[id] = true
        if field then
            check(e[field] > 0, name .. ": " .. id .. " has a positive " .. field)
            check(e[field] <= prev, name .. ": entry " .. i .. " is not stronger than the one before")
            prev = e[field]
        end
    end
end
descending(D.DRINK_ITEMS, "manaValue", "DRINK_ITEMS")
descending(D.FOOD_ITEMS, "healthValue", "FOOD_ITEMS")
descending(D.HEALTHSTONE_ITEMS, "healValue", "HEALTHSTONE_ITEMS")
descending(D.HEALTH_ITEMS, nil, "HEALTH_ITEMS")
descending(D.MANA_ITEMS, nil, "MANA_ITEMS")
descending(D.BANDAGE_ITEMS, nil, "BANDAGE_ITEMS")
for stat, list in pairs(D.BUFF_FOOD_BY_STAT) do descending(list, "value", "BUFF_FOOD." .. stat) end

for _, e in ipairs(D.ELIXIR_CATALOG) do
    check(type(e.spell) == "number", "elixir " .. e.id .. " carries its buff spell ID")
    check(next(e.stats) ~= nil, "elixir " .. e.id .. " grants at least one stat")
end

------------------------------------------------------------
-- Measured on the client
------------------------------------------------------------
local function find(list, id)
    for _, e in ipairs(list) do if (type(e) == "table" and e.id or e) == id then return e end end
end
eq(find(D.DRINK_ITEMS, 231778).conjured, true,
    "Mountain Spring Water is conjured: from the 'Conjured Item' tooltip line, not the name")
eq(D.HEALTHSTONE_ITEMS[1].healValue, 1440, "Major Healthstone restores 1440 on Forever")
eq(#D.CONJURED_ITEMS, 0, "nothing collapses Food and Drink into one button")

eq(find(D.FOOD_ITEMS, 13724) and find(D.FOOD_ITEMS, 13724).restoresMana, true,
    "Enriched Manna Biscuit is food that also restores mana")
check(find(D.DRINK_ITEMS, 13724) ~= nil, "and it competes on the Drink button too")

-- Rejuvenation ranks below the pure potion of its tier on the Health button.
local function indexOf(list, id) for i, v in ipairs(list) do if v == id then return i end end end
check(indexOf(D.HEALTH_ITEMS, 13446) < indexOf(D.HEALTH_ITEMS, 18253), "Major Rejuvenation after Major Healing")
check(not indexOf(D.HEALTH_ITEMS, 4596), "Discolored potions (they hurt you back) are not offered")
check(not indexOf(D.MANA_ITEMS, 8008), "mage mana gems are not on the potion button")

-- Items the client files under "Other" still make it: classification is by tooltip.
eq(D.BANDAGE_ITEMS[1], 232433, "Dense Runecloth Bandage (3400, subclass Other) is the best bandage")
eq(D.DRINK_ITEMS[1].id, 227813, "Drinkable Stratholme Holy Water (6363 mana) is the best drink")
check(find(D.FOOD_ITEMS, 19060) ~= nil, "a battleground ration (subclass Other) is food")
check(find(D.FOOD_ITEMS, 5473) ~= nil, "Scorpid Surprise ('Heals 282 damage', Food & Drink) is food")
check(not indexOf(D.BANDAGE_ITEMS, 5473), "and not a bandage")
check(not indexOf(D.HEALTH_ITEMS, 11951), "Whipper Root Tuber (own cooldown) is not on the potion button")
check(not find(D.FOOD_ITEMS, 11951) and not find(D.DRINK_ITEMS, 11951), "nor on Food or Drink")

-- Food whose Well Fed bonus Buff Food does not offer is still recovery food.
check(find(D.DRINK_ITEMS, 10841) ~= nil, "Goldthorn Tea (1292 mana, +herbalism) is a drink")
check(find(D.FOOD_ITEMS, 4594) ~= nil, "Rockscale Cod (841 health, +fishing) is food")

-- Percentage potions are ranked against the player's (readable) maximum.
WoW.healthMax = 1000
local pid = Apotheca.FindBestPotion("health", D.HEALTH_ITEMS, bagWith(282011, 118))
eq(pid, 282011, "at 1000 max health, Restored Healing Potion (30% = 300) beats Minor Healing (80)")
WoW.healthMax = 200
pid = Apotheca.FindBestPotion("health", D.HEALTH_ITEMS, bagWith(282011, 118))
eq(pid, 118, "at 200 max health (30% = 60), the Minor Healing Potion (80) wins")
pid = Apotheca.FindBestPotion("health", D.HEALTH_ITEMS, bagWith(282011))
eq(pid, 282011, "a percentage potion alone is still offered")
WoW.powerMax = 5000
pid = Apotheca.FindBestPotion("mana", D.MANA_ITEMS, bagWith(282013, 13444))
eq(pid, 13444, "20% of 5000 mana (1000) loses to a Major Mana Potion (1800)")
WoW.healthMax, WoW.powerMax = 1000, 1000

-- The buttons follow a change of maximum (#10): Fortitude, a level-up or
-- gear can make the percentage potion the better one.
WoW.AddItem(4, 1, 282011, 1, "Restored Healing Potion")
WoW.AddItem(4, 2, 118, 1, "Minor Healing Potion")
WoW.healthMax = 200
Apotheca.UpdateAllButtons()
eq(Apotheca.buttons.health.itemID, 118, "at 200 max health the Health button holds Minor Healing (80)")
WoW.healthMax = 1000
WoW.fire("UNIT_MAXHEALTH", "player")
WoW.step(1) ; WoW.step(1)
eq(Apotheca.buttons.health.itemID, 282011, "after UNIT_MAXHEALTH to 1000 it holds Restored Healing (300)")
WoW.bags[4] = nil
Apotheca.UpdateAllButtons()

------------------------------------------------------------
-- Battleground-only items
------------------------------------------------------------
eq(Apotheca.IsItemUsableHere(13446), true, "an ordinary potion is usable anywhere")
eq(Apotheca.IsItemUsableHere(17348), false, "a battleground draught is not usable outdoors")
WoW.instanceName, WoW.instanceType, WoW.instanceMap = "Arathi Basin", "pvp", 529
eq(Apotheca.IsItemUsableHere(17348), true, "a PvP draught is usable in any battleground")
eq(Apotheca.IsItemUsableHere(20065), true, "an Arathi Basin bandage is usable in Arathi Basin")
eq(Apotheca.IsItemUsableHere(19066), false, "a Warsong Gulch bandage is not usable in Arathi Basin")
WoW.instanceName = "Bassin Arathi"   -- a French client
eq(Apotheca.IsItemUsableHere(20065), true, "the gate uses the map ID, so it works on a localized client")
WoW.instanceName, WoW.instanceType, WoW.instanceMap = "Kalimdor", "none", 1

-- Windstone (#85): usable only on Zephras Isle (map 2991, outdoors), and
-- offered on BOTH Food and Drink there, ranked by its average like food.
eq(Apotheca.IsItemUsableHere(255663), false, "Windstone is not usable on Kalimdor")
WoW.instanceName, WoW.instanceType, WoW.instanceMap = "Zephras Isle", "none", 2991
eq(Apotheca.IsItemUsableHere(255663), true, "Windstone is usable on Zephras Isle")
eq(Apotheca.IsItemUsableHere(17348), false, "a battleground draught is still not usable there")
WoW.AddItem(2, 1, 255663, 5, "Windstone")
WoW.AddItem(2, 2, 117, 5, "Tough Jerky")
local zmap = Apotheca.BuildBagMap()
eq(zmap[255663], 5, "on Zephras Isle, Windstone is in the usable bag map")
local fid, _, _, _, _, _, fmana = Apotheca.FindBestFood(zmap)
eq(fid, 255663, "the Food button offers Windstone (60) over Tough Jerky (58)")
eq(fmana, true, "  as food that also restores mana")
local did, _, _, _, _, _, dhealth = Apotheca.FindBestDrink(zmap)
eq(did, 255663, "the Drink button offers Windstone with no other drink")
eq(dhealth, true, "  as drink that also restores health")
-- Its own cooldown (Codex review of #85): while Windstone cools down the
-- Food button falls back to the ready Jerky, and re-picks Windstone once it
-- is ready, with no bag change and no event.
Apotheca.UpdateAllButtons()
eq(Apotheca.buttons.food.itemID, 255663, "the Food button holds Windstone")
WoW.cooldowns[255663] = { WoW.now, 120 }               -- one was used
Apotheca.UpdateAllButtons()                             -- the bag update
eq(Apotheca.buttons.food.itemID, 117, "while Windstone cools down, the Food button offers the Jerky")
eq(Apotheca.buttons.drink.itemID, 255663, "  the Drink button, with no other drink, keeps Windstone")
eq(Apotheca._recheckAt, WoW.now + 120, "  and a re-pick is asked for when it is ready")
WoW.cooldowns[255663] = { WoW.now - 118, 120 }         -- 2 s left
for _ = 1, 4 do WoW.step(1) end
eq(Apotheca.buttons.food.itemID, 117, "  still the Jerky with 2 s left")
WoW.cooldowns[255663] = nil                             -- ready
WoW.now = WoW.now + 120
for _ = 1, 4 do WoW.step(1) end                         -- time passes; no event
eq(Apotheca.buttons.food.itemID, 255663, "once ready, the Food button offers Windstone again")
eq(Apotheca._recheckAt, nil, "  and nothing more is asked for")
-- An unreadable cooldown (secret in combat) never hides it.
WoW.cooldowns[255663] = { WoW.now, 120 }
WoW.combatSecret = true
eq((Apotheca.FindBestFood(zmap)), 255663, "a secret cooldown: Windstone is offered as usual")
eq(WoW.secretBlocked or 0, 0, "  with no blocked secret comparison")
WoW.combatSecret = false
WoW.cooldowns[255663] = nil
WoW.instanceName, WoW.instanceType, WoW.instanceMap = "Kalimdor", "none", 1
zmap = Apotheca.BuildBagMap()
eq(zmap[255663], nil, "elsewhere, Windstone is not in the usable bag map")
eq((Apotheca.FindBestFood(zmap)), 117, "  so the Food button offers Tough Jerky")
eq((Apotheca.FindBestDrink(zmap)), nil, "  and the Drink button nothing")
WoW.bags[2] = nil

-- The gate applies to EVERY finder, not only potions: it is in the bag map.
WoW.AddItem(2, 1, 19060, 3, "Warsong Gulch Enriched Ration")
WoW.AddItem(2, 2, 8766, 3, "Morning Glory Dew")
WoW.AddItem(2, 3, 20066, 3, "Arathi Basin Runecloth Bandage")
local map = Apotheca.BuildBagMap()
eq(map[19060], nil, "outdoors, a Warsong Gulch ration is not in the usable bag map")
eq(Apotheca.FindBestDrink(map), 8766, "so the Drink button offers Morning Glory Dew, not the ration")
eq(Apotheca.FindBestBandage(map), nil, "and an Arathi Basin bandage is not offered outdoors")
WoW.instanceName, WoW.instanceType, WoW.instanceMap = "Arathi Basin", "pvp", 529
eq(Apotheca.FindBestBandage(Apotheca.BuildBagMap()), 20066, "inside Arathi Basin it is")
WoW.instanceName, WoW.instanceType, WoW.instanceMap = "Kalimdor", "none", 1
WoW.bags[2] = nil

------------------------------------------------------------
-- Role profiles pick the right elixirs and buff food
------------------------------------------------------------
local every = {}
for _, e in ipairs(D.ELIXIR_CATALOG) do every[e.id] = 1 end

local res = Apotheca.ResolveElixirs(every)
eq(res.flaskID, 13511, "healer flask: Flask of Distilled Wisdom (+2000 mana)")
eq(res.battleID, 250333, "healer elixir: Greater Cleric's Elixir (+40 healing)")
eq(res.guardianID, 250341, "healer regen elixir: Greater Mageblood Elixir (20 mp5)")

WoW.SetAura("HELPFUL", "Flask of Distilled Wisdom", 17627)
res = Apotheca.ResolveElixirs(every)
eq(res.hasFlask, true, "an active flask is recognised by its spell ID")
eq(res.flaskID, nil, "and the flask slot offers nothing: a second click would only waste one")
eq(res.battleID, 250333, "the elixir slots are still offered: they stack on Forever")
WoW.auras.HELPFUL = {}

-- When the flask runs out, the slot comes back without any bag event:
-- UNIT_AURA re-resolves.
WoW.AddItem(3, 1, 13511, 2, "Flask of Distilled Wisdom")
WoW.SetAura("HELPFUL", "Flask of Distilled Wisdom", 17627)
Apotheca.UpdateAllButtons()
eq(Apotheca.buttons.flask.itemID, nil, "while the flask runs, the Flask button holds nothing")
WoW.auras.HELPFUL = {}
WoW.fire("UNIT_AURA", "player")
WoW.step(1) ; WoW.step(1)
eq(Apotheca.buttons.flask.itemID, 13511, "when it expires, UNIT_AURA brings the flask back")

-- An unrelated aura coming and going costs no full update.
local updates = 0
local realUpdate = Apotheca.UpdateAllButtons
Apotheca.UpdateAllButtons = function(...) updates = updates + 1 return realUpdate(...) end
WoW.SetAura("HELPFUL", "Power Word: Fortitude", 1243)
WoW.fire("UNIT_AURA", "player")
WoW.step(1) ; WoW.step(1)
eq(updates, 0, "an aura that is no elixir's does not trigger a full update")
WoW.auras.HELPFUL = {}
WoW.fire("UNIT_AURA", "player")
WoW.step(1) ; WoW.step(1)
eq(updates, 0, "nor does it going away")
Apotheca.UpdateAllButtons = realUpdate

WoW.bags[3] = nil
Apotheca.UpdateAllButtons()

-- Only one flask can be active, so ANY flask fills the slot, even one
-- that is not the role's own.
WoW.SetAura("HELPFUL", "Flask of the Titans", 17626)
res = Apotheca.ResolveElixirs(every)
eq(res.hasFlask, true, "a healer with Flask of the Titans running has a flask")
eq(res.flaskID, nil, "and is not offered Distilled Wisdom on top of it")
WoW.auras.HELPFUL = {}

-- A flask whose effect is no catalog stat still fills the slot (Codex
-- follow-up on #8: Chromatic Resistance was invisible).
WoW.SetAura("HELPFUL", "Chromatic Resistance", 17629)
res = Apotheca.ResolveElixirs(every)
eq(res.hasFlask, true, "Flask of Chromatic Resistance running counts as a flask")
eq(res.flaskID, nil, "so Distilled Wisdom is not offered over it")
WoW.auras.HELPFUL = {}

-- An elixir fitting both slots goes to the first slot only.
res = Apotheca.ResolveElixirs(bagWith(13447))
eq(res.battleID, 13447, "Elixir of the Sages (Int + Spi) takes the first elixir slot")
eq(res.guardianID, nil, "and does not also appear on the second")

-- The Enable Elixir / Flask option is honoured.
ApothecaDB.profiles[ApothecaDB.activeProfile].elixirs.enabled = false
res = Apotheca.ResolveElixirs(every)
eq(res.flaskID or res.battleID or res.guardianID, nil, "elixirs disabled offers nothing")
ApothecaDB.profiles[ApothecaDB.activeProfile].elixirs.enabled = true

-- An aura whose spell ID differs from the item's spell is still found by
-- the spell's localized name.
WoW.spellNames[17627] = "Weisheit"
WoW.SetAura("HELPFUL", "Weisheit", 99999)
eq(Apotheca.ResolveElixirs(every).hasFlask, true, "a buff with another spell ID is matched by localized name")
WoW.auras.HELPFUL = {}

WoW.class = "MAGE"
Apotheca.RefreshRole()
res = Apotheca.ResolveElixirs(every)
eq(res.flaskID, 13512, "caster flask: Flask of Supreme Power")
local sp = Apotheca.GetStatPriority()
eq(sp[1], "spellDmg", "caster buff food leads with spell damage")
WoW.class = "PRIEST"
Apotheca.RefreshRole()
eq(Apotheca.GetStatPriority()[1], "healing", "healer buff food leads with healing power")

-- Buff food: a healer holding Sage's Tea and Nightfin Soup eats the tea.
local id = Apotheca.FindBestBuffFood(bagWith(249870, 13931))
eq(id, 249870, "healer buff food: Sage's Tea (+44 healing) over Nightfin Soup (+22 spell damage)")

------------------------------------------------------------
-- Scrolls
------------------------------------------------------------
WoW.SetAura("HELPFUL", "Spirit", 12177)
eq(Apotheca.HasSpiritBuff(), true, "a spirit scroll buff is recognised by spell ID, whatever its name")
WoW.auras.HELPFUL = {}
eq(Apotheca.HasSpiritBuff(), false, "and its absence is a confirmed false")

-- Localized clients: Divine Spirit, Well Fed and Recently Bandaged are
-- matched by the client's own name for the spell.
WoW.spellNames[14752] = "Göttlicher Willen"
WoW.SetAura("HELPFUL", "Göttlicher Willen", 5555555) -- an ID not in the list: only the name can match
eq(Apotheca.HasSpiritBuff(), true, "a German Divine Spirit (any rank) blocks the spirit scroll")
WoW.auras.HELPFUL = {}
WoW.spellNames[19705] = "Satt"
WoW.SetAura("HELPFUL", "Satt", 1234567)
eq(Apotheca.HasFoodBuff(), true, "German Well Fed is found by its localized name")
WoW.auras.HELPFUL = {}
WoW.spellNames[11196] = "Kürzlich bandagiert"
WoW.SetAura("HARMFUL", "Kürzlich bandagiert", 5555556) -- only the name can match
eq(Apotheca.HasRecentlyBandaged(), true, "Recently Bandaged is found on any language")
WoW.auras.HARMFUL = {}

done("test_items")
