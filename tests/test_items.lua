-- The generated item data (ApothecaItems.lua) and how the addon reads it.
-- The values themselves come from the client's tooltips; these tests pin
-- the shape and the decisions built on it.

dofile("tests/wow_stubs.lua")
local H = dofile("tests/harness.lua")
H.loadAddon()
local D = Apotheca.DATA

------------------------------------------------------------
-- Shape: strongest first, no duplicates, every value positive
------------------------------------------------------------
local function descending(list, field, name)
    local seen, prev = {}, math.huge
    for i, e in ipairs(list) do
        local id = type(e) == "table" and e.id or e
        H.check(not seen[id], name .. ": item " .. id .. " listed once")
        seen[id] = true
        if field then
            H.check(e[field] > 0, name .. ": " .. id .. " has a positive " .. field)
            H.check(e[field] <= prev, name .. ": entry " .. i .. " is not stronger than the one before")
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
    H.check(type(e.spell) == "number", "elixir " .. e.id .. " carries its buff spell ID")
    H.check(next(e.stats) ~= nil, "elixir " .. e.id .. " grants at least one stat")
end

------------------------------------------------------------
-- Measured on the client
------------------------------------------------------------
H.eq(D.DRINK_ITEMS[1].id, 231778, "the best drink is Mountain Spring Water (Forever conjured, 4903 mana)")
H.eq(D.DRINK_ITEMS[1].conjured, true, "conjured comes from the 'Conjured Item' tooltip line, not the name")
H.eq(D.HEALTHSTONE_ITEMS[1].healValue, 1440, "Major Healthstone restores 1440 on Forever")
H.eq(#D.CONJURED_ITEMS, 0, "nothing collapses Food and Drink into one button")

local function find(list, id)
    for _, e in ipairs(list) do if (type(e) == "table" and e.id or e) == id then return e end end
end
H.eq(find(D.FOOD_ITEMS, 13724) and find(D.FOOD_ITEMS, 13724).restoresMana, true,
    "Enriched Manna Biscuit is food that also restores mana")
H.check(find(D.DRINK_ITEMS, 13724) ~= nil, "and it competes on the Drink button too")

-- Rejuvenation ranks below the pure potion of its tier on the Health button.
H.eq(D.HEALTH_ITEMS[1], 13446, "Major Healing Potion comes before Major Rejuvenation")
local function indexOf(list, id) for i, v in ipairs(list) do if v == id then return i end end end
H.check(indexOf(D.HEALTH_ITEMS, 13446) < indexOf(D.HEALTH_ITEMS, 18253), "Major Rejuvenation after Major Healing")
H.check(not indexOf(D.HEALTH_ITEMS, 4596), "Discolored potions (they hurt you back) are not offered")

------------------------------------------------------------
-- Battleground-only items
------------------------------------------------------------
H.eq(Apotheca.IsItemUsableHere(13446), true, "an ordinary potion is usable anywhere")
H.eq(Apotheca.IsItemUsableHere(17348), false, "a battleground draught is not usable outdoors")
WoW.instanceName, WoW.instanceType = "Arathi Basin", "pvp"
H.eq(Apotheca.IsItemUsableHere(17348), true, "a PvP draught is usable in any battleground")
H.eq(Apotheca.IsItemUsableHere(20065), true, "an Arathi Basin bandage is usable in Arathi Basin")
H.eq(Apotheca.IsItemUsableHere(19066), false, "a Warsong Gulch bandage is not usable in Arathi Basin")
WoW.instanceName, WoW.instanceType = "Kalimdor", "none"

------------------------------------------------------------
-- Role profiles pick the right elixirs and buff food
------------------------------------------------------------
local function bagWith(...)
    local m = {}
    for i = 1, select("#", ...) do m[select(i, ...)] = 1 end
    return m
end
local every = {}
for _, e in ipairs(D.ELIXIR_CATALOG) do every[e.id] = 1 end

local res = Apotheca.ResolveElixirs(every)
H.eq(res.flaskID, 13511, "healer flask: Flask of Distilled Wisdom (+2000 mana)")
H.eq(res.battleID, 250333, "healer elixir: Greater Cleric's Elixir (+40 healing)")
H.eq(res.guardianID, 250341, "healer regen elixir: Greater Mageblood Elixir (20 mp5)")

WoW.SetAura("HELPFUL", "Flask of Distilled Wisdom", 17627)
res = Apotheca.ResolveElixirs(every)
H.eq(res.hasFlask, true, "an active flask is recognised by its spell ID")
H.eq(res.battleID, 250333, "and the elixir slots are still offered: they stack on Forever")
WoW.auras.HELPFUL = {}

WoW.class = "MAGE"
local fresh = {}
res = Apotheca.ResolveElixirs(every)
H.eq(res.flaskID, 13512, "caster flask: Flask of Supreme Power")
local sp = Apotheca.GetStatPriority()
H.eq(sp[1], "spellDmg", "caster buff food leads with spell damage")
WoW.class = "PRIEST"
H.eq(Apotheca.GetStatPriority()[1], "healing", "healer buff food leads with healing power")

-- Buff food: a healer holding Sage's Tea and Nightfin Soup eats the tea.
local id = Apotheca.FindBestBuffFood(bagWith(249870, 13931))
H.eq(id, 249870, "healer buff food: Sage's Tea (+44 healing) over Nightfin Soup (+22 spell damage)")

------------------------------------------------------------
-- Scrolls
------------------------------------------------------------
WoW.SetAura("HELPFUL", "Spirit", 12177)
H.eq(Apotheca.HasSpiritBuff(), true, "a spirit scroll buff is recognised by spell ID, whatever its name")
WoW.auras.HELPFUL = {}
H.eq(Apotheca.HasSpiritBuff(), false, "and its absence is a confirmed false")

H.done("test_items")
