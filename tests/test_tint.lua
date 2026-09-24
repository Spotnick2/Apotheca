-- #6: grey recovery icons while the resource they restore is full. The
-- client colours the icon by a curve it evaluates itself; the addon never
-- sees the number (health is secret even out of combat on Forever).

dofile("tests/wow_stubs.lua")
local H = dofile("tests/harness.lua")

WoW.AddItem(0, 1, 4604, 5, "Forest Mushroom Cap")        -- food: health
WoW.AddItem(0, 2, 159, 5, "Refreshing Spring Water")     -- drink: mana
H.loadAddon()

local food, drink = Apotheca.buttons.food, Apotheca.buttons.drink
H.eq(food.itemID, 4604, "the Food button holds the mushroom")
H.eq(drink.itemID, 159, "the Drink button holds the water")

local grey = Apotheca.API.FULL_GREY
local function painted() return WoW.lastCurveColor and WoW.lastCurveColor[1] end

-- Full health and mana: both greyed (the client paints the curve colour).
WoW.health, WoW.power = 1000, 1000
Apotheca.RefreshFullTint()
H.check(food.icon._vertex ~= nil, "the food icon received a colour from the curve")
H.check(WoW.IsSecret(food.icon._vertex[1]), "and the addon only handled secret channels, never numbers")

-- What the client would draw, from the curve itself:
WoW.fire("UNIT_HEALTH", "player")
H.eq(painted(), grey, "at full health and mana the curve paints grey")

-- Take damage: the next UNIT_HEALTH repaints, now white.
WoW.health = 700
WoW.fire("UNIT_HEALTH", "player")
local seen = {}
-- the last colour evaluated is the mana one (drink), so check health directly
Apotheca.API.TintByFullness(food.icon, "health")
H.eq(painted(), 1, "below full health the food icon is painted white")
Apotheca.API.TintByFullness(drink.icon, "mana")
H.eq(painted(), grey, "while the drink icon stays grey: mana is still full")

-- In combat it still follows (display only, no secure attribute).
WoW.enterCombat()
WoW.health = 1000
WoW.fire("UNIT_HEALTH", "player")
Apotheca.API.TintByFullness(food.icon, "health")
H.eq(painted(), grey, "in combat, healed to full, the food icon greys again")
WoW.leaveCombat()

-- Turned off: plain white, no curve.
ApothecaDB.profiles[ApothecaDB.activeProfile].fullTint = false
Apotheca.RefreshFullTint()
H.eq(food.icon._vertex[1], 1, "with the option off, the icon is plain white")
ApothecaDB.profiles[ApothecaDB.activeProfile].fullTint = true

-- A client that refuses the curve: white, and no error.
WoW.curvesRefused = true
local ok = pcall(Apotheca.RefreshFullTint)
H.check(ok, "a refused curve does not raise")
H.eq(food.icon._vertex[1], 1, "and the icon is left white")
WoW.curvesRefused = false

-- An empty button is never greyed.
WoW.bags[0] = nil
Apotheca.UpdateAllButtons()
H.eq(food.itemID, nil, "no food in bags")
H.eq(food.icon._vertex[1], 1, "the empty Food button is white")

H.done("test_tint")
