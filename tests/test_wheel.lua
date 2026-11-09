-- The Mage Scrolls wheel (#94): the generated data, what the wheel offers,
-- the secure snippets (open, pick, tap, Esc, combat), the art (animation,
-- ghost, sounds, Glass UI's look) and the ready-check glow.
--
-- The snippets run in the stub's model of the secure handlers (WowTestKit
-- #20 meanwhile): a click is WoW.click(button, mouse, down), one edge at a
-- time, and a secure item use is recorded in WoW.secureActions.

dofile("tests/wow_stubs.lua")
local H = dofile("tests/harness.lua")

local D = nil   -- Apotheca.DATA, once loaded
local function byKind(kind, weapon)
    for _, e in ipairs(D.MAGE_SCROLLS) do
        if e.kind == kind and (weapon == nil or e.weapon == weapon) then return e end
    end
end

WoW.class = "MAGE"
local DAGGER, STAFF = 900001, 900002
WoW.itemClass[DAGGER] = { 2, 15, "Daggers" }
WoW.itemClass[STAFF] = { 2, 10, "Staves" }
WoW.equipped = { [16] = DAGGER }
H.loadAddon()
WoW.class = "MAGE"
D = Apotheca.DATA
local W = Apotheca.Wheel

------------------------------------------------------------
-- The generated data
------------------------------------------------------------

local KINDS = { familiar = 1, imbue = 2, mana = 3, damage = 4, utility = 5 }
local seen, prev, ordered, shaped = {}, nil, true, true
for _, e in ipairs(D.MAGE_SCROLLS) do
    if seen[e.id] then shaped = false end
    seen[e.id] = true
    if not (KINDS[e.kind] and type(e.level) == "number" and type(e.spell) == "number") then shaped = false end
    if (e.kind == "imbue") ~= (e.weapon ~= nil) then shaped = false end
    if e.weapon and not ({ staff = true, dagger = true, sword = true })[e.weapon] then shaped = false end
    if prev and (KINDS[e.kind] < KINDS[prev.kind]
            or (e.kind == prev.kind and e.level > prev.level)) then ordered = false end
    prev = e
end
check(#D.MAGE_SCROLLS >= 30, "the generator found the mage scrolls (" .. #D.MAGE_SCROLLS .. ")")
check(shaped, "each has an ID once, a kind, a level and a spell; imbues alone carry a staff, dagger or sword")
check(ordered, "ordered by kind (familiar, imbue, mana, damage, utility), then strongest first")
check(seen[275067] and seen[213564] and seen[277493] and seen[217495],
    "Chillknife, Minor Evocation, the Cat familiar and Cryoblast are in")
check(not seen[217496] and not seen[223171] and not seen[213549],
    "a quest object's scroll (Blade, Geomancy) and one with no Use spell (Arcane Angling) are not")
eq(byKind("imbue", "dagger") and true, true, "there are dagger imbues")
eq(byKind("imbue", "staff") and true, true, "and staff imbues")

local CHILL, STAFFIMB = 275067, byKind("imbue", "staff").id
local RAT, EVO, CRYO = 275069, 213564, 217495
WoW.AddItem(1, 1, CHILL, 3, "Scroll of Imbue Chillknife")
WoW.AddItem(1, 2, STAFFIMB, 2, "Scroll of Imbue Staff")
WoW.AddItem(1, 3, RAT, 1, "Scroll of Familiar: Rat")
WoW.AddItem(1, 4, EVO, 4, "Scroll of Minor Evocation")
WoW.AddItem(1, 5, CRYO, 1, "Scroll of Cryoblast")

------------------------------------------------------------
-- What the wheel offers
------------------------------------------------------------

local function ids(list)
    local out = {}
    for i, r in ipairs(list) do out[i] = r.id end
    return table.concat(out, ",")
end
local function offered() return Apotheca.FindMageScrolls(Apotheca.BuildBagMap()) end

eq(ids(offered()), table.concat({ RAT, CHILL, EVO, CRYO }, ","),
    "a dagger in hand: the familiar, the dagger imbue, Evocation, Cryoblast; no staff imbue")
WoW.equipped[16] = STAFF
eq(ids(offered()), table.concat({ RAT, STAFFIMB, EVO, CRYO }, ","), "a staff: the staff imbue instead")
WoW.equipped[16] = nil
eq(ids(offered()), table.concat({ RAT, EVO, CRYO }, ","), "no weapon: no imbue")
WoW.equipped[16] = DAGGER
WoW.unusable[CRYO] = true
eq(ids(offered()), table.concat({ RAT, CHILL, EVO }, ","), "a scroll the client says is unusable is left out")
WoW.unusable[CRYO] = nil
eq(offered()[2].count, 3, "with its count")

------------------------------------------------------------
-- The bar button and the ring's contents
------------------------------------------------------------

Apotheca.UpdateAllButtons()
local btn = Apotheca.buttons.magescrolls
check(btn:IsShown(), "a mage gets the Mage Scrolls button")
eq(btn.itemID, nil, "which never holds an item itself (no other path can arm it)")
eq(#btn.scrolls, 4, "it carries the four scrolls for the wheel")

local slots, screen, ring = W.slots, W.screen, W.ring
eq(screen:GetAttribute("count"), 4, "the ring has four slots")
eq(screen:GetAttribute("enabled"), true, "and is enabled")
eq(slots[2]:GetAttribute("item"), "item:" .. CHILL, "slot 2 uses Chillknife")
eq(slots[2]:GetAttribute("target-slot"), 16, "on the main hand, like the weapon oil")
eq(slots[3]:GetAttribute("target-slot"), nil, "Evocation has no target slot")
check(slots[4]:IsShown() and not slots[5]:IsShown(), "slots past the fourth are hidden")
check(math.abs(screen:GetAttribute("sx1")) < 1e-9, "slot 1 sits at the top")
check(screen:GetAttribute("sy1") > 0, "above the centre")

-- Debug mode: the slots carry no item.
ApothecaDB.profiles.Global.debug = true
Apotheca.UpdateAllButtons()
eq(slots[1]:GetAttribute("type"), nil, "debug mode: a slot uses nothing")
ApothecaDB.profiles.Global.debug = false
Apotheca.UpdateAllButtons()
eq(slots[1]:GetAttribute("type"), "item", "and back")

-- Another class: no button, and the key does nothing.
WoW.class = "PRIEST"
Apotheca.UpdateAllButtons()
check(not btn:IsShown(), "a priest has no Mage Scrolls button")
eq(screen:GetAttribute("enabled"), false, "and the wheel is disabled")
WoW.class = "MAGE"
ApothecaDB.profiles.Global.mageScrolls.enabled = false
Apotheca.UpdateAllButtons()
check(not btn:IsShown(), "switched off: no button")
eq(screen:GetAttribute("enabled"), false, "and the wheel is disabled")
ApothecaDB.profiles.Global.mageScrolls.enabled = true
Apotheca.UpdateAllButtons()

------------------------------------------------------------
-- The snippets
------------------------------------------------------------

screen._width, screen._height = 1920, 1080
local CX, CY = 960, 540
local function cursor(x, y) WoW.cursorX, WoW.cursorY = x, y end
local function slotAt(i) return CX + screen:GetAttribute("sx" .. i), CY + screen:GetAttribute("sy" .. i) end
local function used() return WoW.secureActions[#WoW.secureActions] end
local function reset() WoW.secureActions = {} end
local ESC = "ApothecaWheelClose:LeftButton"

-- Hold and release over a scroll (key down, key up).
cursor(CX, CY)
reset()
WoW.click(btn, "LeftButton", true)
check(ring:IsShown(), "the press opens the ring")
eq(ring._points[1][4], CX, "at the cursor")
eq(WoW.overrideBindings.ESCAPE, ESC, "Esc is bound to close it while open")
eq(#WoW.secureActions, 0, "the press uses nothing")
cursor(slotAt(2))
WoW.click(btn, "LeftButton", false)
eq(used() and used().item, "item:" .. CHILL, "releasing over slot 2 uses Chillknife")
eq(used().targetSlot, 16, "on the main hand")
check(not ring:IsShown(), "and closes the ring")
eq(WoW.overrideBindings.ESCAPE, nil, "dropping the Esc binding")
eq(btn:GetAttribute("type"), nil, "the button is disarmed after the use")
eq(btn:GetAttribute("item"), nil, "no item left on it")

-- The release picks the nearest slot, not only an exact hit.
reset()
cursor(CX, CY)
WoW.click(btn, "LeftButton", true)
local x3, y3 = slotAt(3)
cursor(x3 + 8, y3 - 6)
WoW.click(btn, "LeftButton", false)
eq(used() and used().item, "item:" .. EVO, "near slot 3: Evocation")
eq(used().targetSlot, nil, "with no target slot")

-- Tap: released inside the dead zone, it stays open; click a scroll.
reset()
cursor(CX, CY)
WoW.click(btn, "LeftButton", true)
cursor(CX + 10, CY + 10)
WoW.click(btn, "LeftButton", false)
check(ring:IsShown(), "released in the dead zone: the ring stays open")
eq(#WoW.secureActions, 0, "and nothing is used")
cursor(slotAt(4))
WoW.click(slots[4], "LeftButton", true)       -- ActionButtonUseKeyDown on: acts on the press
eq(used() and used().item, "item:" .. CRYO, "clicking slot 4 uses Cryoblast")
check(ring:IsShown(), "the ring waits for the release")
WoW.click(slots[4], "LeftButton", false)
check(not ring:IsShown(), "and closes on it")
eq(#WoW.secureActions, 1, "one use for one click")

-- The other ActionButtonUseKeyDown setting: the slot acts on the release.
WoW.useKeyDown = false
reset()
cursor(CX, CY)
WoW.click(btn, "LeftButton", true)
WoW.click(btn, "LeftButton", false)
WoW.click(slots[1], "LeftButton", true)
eq(#WoW.secureActions, 0, "key-down off: the slot's press does nothing")
WoW.click(slots[1], "LeftButton", false)
eq(used() and used().item, "item:" .. RAT, "its release uses the familiar")
check(not ring:IsShown(), "and closes the ring")
-- The trigger acts on the release whatever the setting.
reset()
cursor(CX, CY)
WoW.click(btn, "LeftButton", true)
cursor(slotAt(3))
WoW.click(btn, "LeftButton", false)
eq(used() and used().item, "item:" .. EVO, "hold and release works with key-down off too")
WoW.useKeyDown = true

-- A second tap closes it; that release does nothing.
reset()
cursor(CX, CY)
WoW.click(btn, "LeftButton", true)
WoW.click(btn, "LeftButton", false)
cursor(slotAt(2))
WoW.click(btn, "LeftButton", true)
check(not ring:IsShown(), "a second tap closes the open ring")
WoW.click(btn, "LeftButton", false)
eq(#WoW.secureActions, 0, "and its release over a scroll uses nothing")
check(not ring:IsShown(), "nor reopens it")

-- Esc.
cursor(CX, CY)
WoW.click(btn, "LeftButton", true)
WoW.click(btn, "LeftButton", false)
check(WoW.pressKey("ESCAPE", true), "Esc clicks the close button while open")
check(not ring:IsShown(), "which closes the ring")
eq(WoW.overrideBindings.ESCAPE, nil, "and gives Esc back")
check(not WoW.pressKey("ESCAPE", true), "Esc is the game's again")

-- Near the screen's edge, the ring is moved in to fit.
cursor(5, 5)
WoW.click(btn, "LeftButton", true)
local r = screen:GetAttribute("radius") + 30
eq(ring._points[1][4], r, "clamped from the left edge")
eq(ring._points[1][5], r, "and the bottom")
WoW.pressKey("ESCAPE", true)

-- Disabled (nothing to offer): the key does nothing.
W.SetContents({}, false, false)
reset()
cursor(CX, CY)
WoW.click(btn, "LeftButton", true)
check(not ring:IsShown(), "disabled: the press opens nothing")
WoW.click(btn, "LeftButton", false)
eq(#WoW.secureActions, 0, "and the release uses nothing")
Apotheca.UpdateAllButtons()
eq(screen:GetAttribute("enabled"), true, "the next update enables it again")

-- In combat: the snippets work, contents are frozen, nothing is blocked.
WoW.enterCombat()
WoW.strictLockdown = true
reset()
cursor(CX, CY)
WoW.click(btn, "LeftButton", true)
check(ring:IsShown(), "in combat the press opens the ring")
cursor(slotAt(2))
WoW.click(btn, "LeftButton", false)
eq(used() and used().item, "item:" .. CHILL, "and the release uses the scroll")
check(not ring:IsShown(), "and closes it")
W.SetContents({}, false, false)
eq(screen:GetAttribute("count"), 4, "the contents can't change in combat")
eq(screen:GetAttribute("enabled"), true, "nor be switched off")
WoW.click(btn, "LeftButton", true)
WoW.click(btn, "LeftButton", false)
WoW.step(0.2)
WoW.pressKey("ESCAPE", true)
WoW.step(0.2)
eq(#WoW.blocked, 0, "nothing was blocked (" .. table.concat(WoW.blocked, ", ") .. ")")
WoW.strictLockdown = false
WoW.leaveCombat()

------------------------------------------------------------
-- The art: animation, ghost, sounds
------------------------------------------------------------

local art = W.art
WoW.sounds = {}
cursor(CX, CY)
WoW.click(btn, "LeftButton", true)
WoW.click(btn, "LeftButton", false)
eq(art:GetScale(), 0.7, "the disc opens small")
eq(ring:GetAlpha(), 0, "and the ring transparent")
eq(WoW.sounds[1] and WoW.sounds[1].path, W.SOUNDS.open, "with the open sound")
eq(WoW.sounds[1].channel, "SFX", "on the effects channel")
WoW.step(0.05)
check(art:GetScale() > 0.7 and art:GetScale() < 1, "it grows")
WoW.step(0.2)
eq(art:GetScale(), 1, "to full size")
eq(ring:GetAlpha(), 1, "fully shown")
cursor(slotAt(4))
WoW.step(0.02)
eq(W.label:GetText(), "Scroll of Cryoblast", "the name of the scroll under the cursor")
cursor(CX, CY)
WoW.step(0.02)
eq(W.label:GetText(), "Mage Scrolls", "the wheel's own in the dead zone")
cursor(slotAt(4))
WoW.step(0.02)

WoW.pressKey("ESCAPE", true)
local ghost = W.ghost
check(ghost and ghost:IsShown(), "closing shows the ghost")
local icons = 0
for _, t in ipairs(ghost.icons) do if t:IsShown() then icons = icons + 1 end end
eq(icons, 4, "with the four scrolls' icons")
eq(ghost.icons[1]:GetTexture(), slots[1].icon:GetTexture(), "copied from the slots")
check(ghost.parts.hilite:IsShown(), "and the highlight where it was")
eq(ghost.parts.label:GetText(), "Scroll of Cryoblast", "and the name")
eq(WoW.sounds[2] and WoW.sounds[2].path, W.SOUNDS.close, "the close sound")
WoW.step(0.06)
check(ghost:IsShown() and ghost:GetAlpha() < 1, "the ghost fades")
WoW.step(0.1)
check(not ghost:IsShown(), "and is gone")

-- Opening again while the ghost fades: the ghost goes at once.
cursor(CX, CY)
WoW.click(btn, "LeftButton", true)
WoW.click(btn, "LeftButton", false)
WoW.pressKey("ESCAPE", true)
WoW.click(btn, "LeftButton", true)
check(not ghost:IsShown(), "reopening hides the ghost")
WoW.click(btn, "LeftButton", false)
WoW.pressKey("ESCAPE", true)

-- The sound setting.
WoW.sounds = {}
ApothecaDB.profiles.Global.mageScrolls.sound = false
WoW.click(btn, "LeftButton", true)
WoW.click(btn, "LeftButton", false)
WoW.pressKey("ESCAPE", true)
eq(#WoW.sounds, 0, "sounds off: silent")
ApothecaDB.profiles.Global.mageScrolls.sound = true
eq(Apotheca.GetDB().mageScrolls.sound, true, "the setting is in the profile (defaults)")

------------------------------------------------------------
-- The look: our own, or Glass UI's suite
------------------------------------------------------------

local parts = W.parts
local function near(a, b) return math.abs(a - b) < 1e-6 end
W.Paint()
eq(parts.backing._vertex[4], W.OWN.backing[4], "without Glass UI: our own dark disc")
check(not parts.tint:IsShown(), "with no tint layer")

local accent = { 1, 0.82, 0 }
local suiteBody = { tint = { 0.13, 0.16, 0.22, 0.24 }, backing = { 0.04, 0.05, 0.07, 0.35 }, wash = 1 }
local suite = { API = 1,
    Body = function(name)
        if name == "clear" then return { tint = { 0.13, 0.16, 0.22, 0.24 }, backing = { 0.04, 0.05, 0.07, 0.35 }, wash = 1 } end
        if name == nil then return suiteBody end
    end,
    Accent = function() return accent end }
rawset(_G, "GlassUI", { Suite = suite })
W.Paint()
check(near(parts.backing._vertex[4], W.BACKING_FLOOR), "Glass UI's clear body: the backing raised to the floor")
check(parts.tint:IsShown() and near(parts.tint._vertex[4], 0.24), "its tint over it")
local tr, tg = W.label:GetTextColor()
check(near(tr, 1) and near(tg, 0.82), "the name in the suite's accent (gold)")
check(near(parts.hilite._vertex[2], 0.82), "and the highlight")

suiteBody = { tint = { 0.05, 0.06, 0.08, 0.62 }, backing = { 0.04, 0.05, 0.07, 0.92 }, wash = 0.8 }
accent = { 0.65, 0.835, 0.905 }
EventRegistry:TriggerEvent("GlassUI.Suite.LookChanged", { tint = "smoked", accent = "ice" })
check(near(parts.backing._vertex[4], 0.92), "a change to Smoked repaints live: its denser backing kept")
tr = W.label:GetTextColor()
check(near(tr, 0.65), "and the accent changes to ice")

suiteBody = { classShade = 0.6, backing = { 0.04, 0.05, 0.07, 0.35 }, wash = 1 }
W.Paint()
local c = WoW.classColors.MAGE
check(near(parts.tint._vertex[1], c.r * 0.6) and near(parts.tint._vertex[4], 0.24),
    "the class body: the class colour shaded, at clear's alpha")

suite.Body = function() error("broken") end
W.Paint()
eq(parts.backing._vertex[4], W.OWN.backing[4], "a failing Glass UI: our own look")
suite.Body = function() return suiteBody end
suite.API = 2
W.Paint()
eq(parts.backing._vertex[4], W.OWN.backing[4], "an API it doesn't know: our own look")
rawset(_G, "GlassUI", nil)
W.Paint()

------------------------------------------------------------
-- The ready-check glow
------------------------------------------------------------

local function glowAt(setup)
    btn.__apothecaGlow = nil
    setup()
    Apotheca.UpdateAllButtons()
    WoW.fire("READY_CHECK")
    local g = btn.__apothecaGlow ~= nil
    WoW.fire("READY_CHECK_FINISHED")
    return g
end
WoW.enchants = {}
eq(glowAt(function() end), true, "an imbue held and a bare main hand: it glows")
WoW.enchants = { [16] = { true, 600000, 0, 1 } }
WoW.bags[1][3] = nil                                   -- no familiar scroll
eq(glowAt(function() end), false, "the hand imbued and no familiar scroll: no glow")
WoW.AddItem(1, 3, RAT, 1, "Scroll of Familiar: Rat")
eq(glowAt(function() end), true, "a familiar scroll and no familiar out: it glows")
local ratSpell
for _, e in ipairs(D.MAGE_SCROLLS) do if e.id == RAT then ratSpell = e.spell end end
WoW.auras.HELPFUL = {}
WoW.SetAura("HELPFUL", "Familiar", ratSpell)
eq(glowAt(function() end), false, "the familiar out (by its spell): no glow")
WoW.auras.HELPFUL = {}
ApothecaDB.profiles.Global.mageScrolls.glowOnMissingBuff = false
eq(glowAt(function() end), false, "the glow switched off")
ApothecaDB.profiles.Global.mageScrolls.glowOnMissingBuff = true
WoW.enchantThrow = true
WoW.bags[1][3] = nil
WoW.enchants = {}
eq(glowAt(function() end), false, "the main hand unreadable: unknown never glows")
WoW.enchantThrow = false

done("test_wheel")
