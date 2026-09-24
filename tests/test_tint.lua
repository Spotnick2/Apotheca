-- #6: grey recovery icons while the resource they restore is full. The
-- client colours the icon by a curve it evaluates itself; the addon never
-- sees the number (health is secret even out of combat on Forever).
-- Assertions read what the TEXTURE would be drawn with (_drawn), set only
-- through the addon's own event paths.

dofile("tests/wow_stubs.lua")
local H = dofile("tests/harness.lua")

WoW.AddItem(0, 1, 4604, 5, "Forest Mushroom Cap")        -- food: health only
WoW.AddItem(0, 2, 159, 5, "Refreshing Spring Water")     -- drink: mana only
H.loadAddon()

local food, drink = Apotheca.buttons.food, Apotheca.buttons.drink
local grey = Apotheca.API.FULL_GREY
local function drawn(btn) return btn.icon._drawn and btn.icon._drawn[1] end
local function near(a, b) return a and math.abs(a - b) < 1e-6 end

H.eq(food.itemID, 4604, "the Food button holds the mushroom")
H.eq(drink.itemID, 159, "the Drink button holds the water")

-- Full health and mana, after a bar update: both drawn grey, and the
-- addon itself only ever held secret channels.
WoW.health, WoW.power = 1000, 1000
Apotheca.UpdateAllButtons()
H.check(near(drawn(food), grey), "at full health the food icon is drawn grey")
H.check(near(drawn(drink), grey), "at full mana the drink icon is drawn grey")
H.check(WoW.IsSecret(food.icon._vertex[1]), "the addon passed secret channels, never numbers")

-- Damage: UNIT_HEALTH alone repaints (no direct call).
WoW.health = 700
WoW.fire("UNIT_HEALTH", "player")
H.check(near(drawn(food), 1), "after damage, UNIT_HEALTH repaints the food icon white")
H.check(near(drawn(drink), grey), "the drink icon stays grey: mana is still full")

-- Mana spent: UNIT_POWER_UPDATE repaints the drink.
WoW.power = 400
WoW.fire("UNIT_POWER_UPDATE", "player")
H.check(near(drawn(drink), 1), "after spending mana, UNIT_POWER_UPDATE repaints the drink white")

-- One hit point short of full is white, not dimmed.
WoW.health = 999
WoW.fire("UNIT_HEALTH", "player")
H.check(drawn(food) > 0.99, "one point below full the food icon is still (almost) white")

-- An incoming heal must not grey the icon before it lands.
WoW.health, WoW.incomingHeal = 700, 500
WoW.fire("UNIT_HEALTH", "player")
H.eq(WoW.lastPredicted, false, "health is read without predicted heals")
H.check(near(drawn(food), 1), "so an incoming heal does not grey the food icon early")
WoW.incomingHeal = 0

-- In combat it still follows (display only, no secure attribute).
WoW.enterCombat()
WoW.health = 1000
WoW.fire("UNIT_HEALTH", "player")
H.check(near(drawn(food), grey), "in combat, healed to full, the food icon greys again")
WoW.leaveCombat()

-- Items restoring both are never greyed (useful while one is not full).
WoW.AddItem(0, 3, 13724, 5, "Enriched Manna Biscuit")   -- 2065 health + 4240 mana
WoW.bags[0][1] = nil
WoW.health, WoW.power = 1000, 400
Apotheca.UpdateAllButtons()
H.eq(food.itemID, 13724, "the Food button now holds the Enriched Manna Biscuit")
H.check(near(drawn(food), 1), "at full health but missing mana, the biscuit is NOT greyed")
H.check(Apotheca._RESTORES_BOTH[18253], "a rejuvenation potion counts as restoring both")

-- Turned off: plain white.
WoW.bags[0][3] = nil
WoW.AddItem(0, 1, 4604, 5, "Forest Mushroom Cap")
Apotheca.UpdateAllButtons()
ApothecaDB.profiles[ApothecaDB.activeProfile].fullTint = false
WoW.fire("UNIT_HEALTH", "player")
H.check(near(drawn(food), 1), "with the option off, the icon is plain white")
ApothecaDB.profiles[ApothecaDB.activeProfile].fullTint = true

-- A client that refuses the curve: white, and no error.
WoW.curvesRefused = true
local ok = pcall(WoW.fire, "UNIT_HEALTH", "player")
H.check(ok, "a refused curve does not raise")
H.check(near(drawn(food), 1), "and the icon is left white")
WoW.curvesRefused = false

-- An empty button is never greyed.
WoW.bags[0] = nil
Apotheca.UpdateAllButtons()
H.eq(food.itemID, nil, "no food in bags")
H.check(near(drawn(food), 1), "the empty Food button is white")

H.done("test_tint")
