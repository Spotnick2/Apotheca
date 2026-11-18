-- The glass buttons without Glass Action Bars (#41): LibGlass r13's
-- Glass.Button on both bars and the wheel's slots, and a glass plate on the
-- drag anchors, under the `glassButtons` option. GAB is loaded here with its
-- glass off (SkinButton says false), so Apotheca's own skin is used: the
-- same path as no GAB at all. test_glass.lua covers GAB styling them.

dofile("tests/wow_stubs.lua")
local H = dofile("tests/harness.lua")

local function near(a, b) return type(a) == "number" and math.abs(a - b) < 1e-6 end

WoW.AddItem(0, 1, 13444, 5, "Major Mana Potion")
WoW.AddItem(0, 2, 13446, 5, "Major Healing Potion")

local GAB = { PUBLIC_API_VERSION = 2, asked = 0 }
function GAB.RegisterBar() return true end
function GAB.RequestLayout() end
function GAB.SkinButton() GAB.asked = GAB.asked + 1; return false end
rawset(_G, "GlassActionBars", GAB)

WoW.class = "MAGE"
H.loadAddon()
WoW.step(1)

local G = Apotheca.GlassButtons
local W = Apotheca.Wheel
local Glass = W.Glass
local db = Apotheca.GetDB()
local mana = Apotheca.buttons.mana
local slot = W.slots[1]
local util = Apotheca.Utility.buttons[Apotheca.Utility.ACTIONS[1].key]
local mainAnchor, utilAnchor = Apotheca.anchors[1], Apotheca.anchors[2]

------------------------------------------------------------
-- At login: GAB asked first, its glass off, so the option is Apotheca's
------------------------------------------------------------
check(G.Available(), "LibGlass r13's button skin is there")
check(GAB.asked > 0, "GAB's SkinButton was asked first")
check(not G.gab, "GAB styles nothing (its glass is off)")
eq(G.Reason(), nil, "so the option can be used")
eq(db.glassButtons, false, "off by default")
eq(next(G.skins), nil, "off: no skin built")
eq(Glass.ButtonSkin(mana), nil, "the library holds no button")
check(mana.btnBorder:IsShown() and mana.btnBorder:GetAlpha() == 1, "the bronze frame, as always")
eq(mana:GetPushedTexture() and mana:GetPushedTexture()._file, G.DEPRESS, "the gold pushed texture")
check(mainAnchor.bg:IsShown(), "the anchor's flat purple")
eq(mainAnchor.glass, nil, "no anchor glass built")
local nMain = 0
for _ in pairs(Apotheca.buttons) do nMain = nMain + 1 end
check(nMain > 20, "the main bar's buttons exist")
eq(#G.Buttons(), nMain + #Apotheca.Utility.ACTIONS + #W.slots,
   "the style covers both bars and every wheel slot")

------------------------------------------------------------
-- Switched on
------------------------------------------------------------
db.glassButtons = true
G.Apply()
local skin = G.skins[mana]
check(skin ~= nil, "a main bar button wears the skin")
eq(Glass.ButtonSkin(mana), skin, "built on the wheel's instance (Pearl)")
local all = true
for _, e in ipairs(G.Buttons()) do
    if not (G.skins[e.btn] and Glass.ButtonSkin(e.btn) == G.skins[e.btn]) then all = false end
end
check(all, "every button: both bars and the wheel's slots")
eq(skin.regions.icon, mana.icon, "region: the icon")
eq(skin.regions.pushed, mana:GetPushedTexture(), "region: the pushed texture")
eq(skin.regions.highlight, mana.highlightTex, "region: the highlight")
eq(skin.regions.hotkey, mana.hotkey, "region: the hotkey")
eq(skin.regions.count, mana.countText, "region: the count")
eq(skin.regions.fade and skin.regions.fade.border, mana.btnBorder, "fade: the bronze frame")
eq(skin.regions.fade and skin.regions.fade.empty, nil, "not the empty-slot art: its alpha follows the stock")
eq(skin.regions.cooldown, nil, "the cooldown stays Apotheca's")
eq(mana.btnBorder:GetAlpha(), 0, "the bronze frame faded out")
check(not mana.emptyBg:IsShown(), "the empty-slot art hidden by Apotheca")
check(skin.occupied, "never an empty slot: out of stock isn't empty (#68)")
check(mana:GetPushedTexture()._file ~= G.DEPRESS, "the pushed look is the glass's rim")
eq(#(mana.icon._masks or {}), 1, "the icon rounded (maskIcon)")
check(mana.countText:GetFont() ~= nil, "the count in the glass font")
check(near(mana.highlightTex:GetAlpha(), 0.4), "the bar's hover: GAB's glow (0.4)")
eq(slot.highlightTex:GetAlpha(), 0, "a wheel slot's hover is off: the wheel lights the pick")
check(G.skins[util] ~= nil, "the profession bar too")

-- The anchors: glass plates, the text on top.
check(mainAnchor.glass and mainAnchor.glass:IsShown(), "the main bar's anchor: a glass plate")
check(not mainAnchor.bg:IsShown(), "its flat purple hidden")
eq(mainAnchor.text:GetParent(), mainAnchor.glassG.top, "the text over the plate")
local tc = mainAnchor.glassG.tint._color or {}
check(near(tc[1], 0.40) and near(tc[2], 0.27) and near(tc[3], 0.66) and near(tc[4], 0.55),
      "tinted the anchor's purple")
check(utilAnchor.glass and utilAnchor.glass:IsShown(), "the profession bar's anchor too")
check(not mainAnchor.glass:IsMouseEnabled(), "the plate never takes the mouse (the anchor drags)")

------------------------------------------------------------
-- The look: GAB's defaults without Glass UI, the suite's while following
------------------------------------------------------------
local look, slotLook = skin.look, G.skins[slot].look
eq(look("tint"), nil, "no Glass UI: the glass as built (clear)")
eq(look("hover"), nil, "LibGlass's default hover (glow)")
eq(look("press"), nil, "LibGlass's default press (flash)")
eq(look("tintWash"), nil, "the material's wash")
eq(slotLook("hover"), "off", "a slot: no hover of its own")

local suiteAnswer = { tint = "smoked", hover = "halo", press = "ripple" }
rawset(_G, "GlassUI", { Suite = { API = 1, Look = function() return suiteAnswer end } })
G.ReadSuite()
eq(look("tint"), G.SMOKED, "the suite's smoked: GAB's smoked body")
check(near(look("tintWash"), 0.14 / 0.18), "with GAB's smoked wash")
eq(look("hover"), "halo", "the suite's hover")
eq(look("press"), "ripple", "the suite's press")
eq(slotLook("hover"), "off", "a slot's hover stays off")
G.Refresh()
eq(mana.highlightTex:GetAlpha(), 0, "repainted: the halo answers the hover, not the highlight")

EventRegistry:TriggerEvent("GlassUI.Suite.LookChanged", { tint = "class", hover = "glow", press = "flash" })
local c = WoW.classColors.MAGE
local t = look("tint")
check(t and near(t[1], c.r * 0.6) and near(t[2], c.g * 0.6) and near(t[3], c.b * 0.6),
      "class: the class colour shaded to 0.6 (GAB's)")
eq(look("tintWash"), nil, "class keeps the material's wash")
check(near(mana.highlightTex:GetAlpha(), 0.4), "live on LookChanged: the glow is back")

EventRegistry:TriggerEvent("GlassUI.Suite.LookChanged", { tint = "neon", hover = 3, press = "boom" })
eq(look("tint"), nil, "an unknown tint: as built")
eq(look("hover"), nil, "an unknown hover: the default")
eq(look("press"), nil, "an unknown press: the default")

-- Not following (Glass UI's switch, #101): GAB's own defaults until /reload.
W.ownLook = true
G.ReadSuite()
eq(look("tint"), nil, "own look: as built")
EventRegistry:TriggerEvent("GlassUI.Suite.LookChanged", { tint = "smoked" })
eq(look("tint"), nil, "own look: a LookChanged changes nothing")
W.ownLook = false
rawset(_G, "GlassUI", nil)
G.ReadSuite()

------------------------------------------------------------
-- A resize restyles (small fonts under 40 wide)
------------------------------------------------------------
check(skin.small, "36 px: LibGlass's small fonts (under 40 wide)")
db.iconSize = 44
Apotheca.UpdateAllButtons()
eq(mana:GetWidth(), 44, "the bar's buttons resized")
check(not skin.small, "restyled: the regular fonts")
db.iconSize = 36
Apotheca.UpdateAllButtons()
check(skin.small, "and back")

------------------------------------------------------------
-- Switched off, live: Apotheca's own look back
------------------------------------------------------------
db.glassButtons = false
G.Apply()
check(skin.off, "the skin is off")
check(not skin.body:IsShown(), "its glass hidden")
eq(mana.btnBorder:GetAlpha(), 1, "the bronze frame back")
check(mana.emptyBg:IsShown(), "the empty-slot art back")
local p = mana:GetPushedTexture()
eq(p._file, G.DEPRESS, "the gold pushed texture back")
eq(p._blend, "BLEND", "blended as before")
eq(mana.countText:GetFontObject(), "NumberFontNormal", "the count's font back")
eq(mana.hotkey:GetFontObject(), "NumberFontNormalSmallGray", "the hotkey's font back")
eq(#(mana.icon._masks or {}), 0, "the icon square again")
eq(mana.highlightTex:GetAlpha(), 1, "the highlight at full")
check(mainAnchor.bg:IsShown() and not mainAnchor.glass:IsShown(), "the anchor's flat purple back")
eq(mainAnchor.text:GetParent(), mainAnchor, "its text back on the anchor")
eq(Glass.ButtonSkin(mana), skin, "the skin keeps the button (one skin per button)")

db.glassButtons = true
G.Apply()
eq(G.skins[mana], skin, "on again: the same skin, not a second")
check(not skin.off and skin.body:IsShown(), "shown again")
eq(mana.btnBorder:GetAlpha(), 0, "the bronze frame faded again")
check(not mana.emptyBg:IsShown(), "the empty-slot art hidden again")
eq(#(mana.icon._masks or {}), 1, "the same mask back")

------------------------------------------------------------
-- In combat the switch waits (it rewrites the secure button's pushed texture)
------------------------------------------------------------
WoW.strictLockdown = true
WoW.enterCombat()
db.glassButtons = false
G.Apply()
check(G.pending, "in combat: pending")
check(not skin.off, "nothing changed yet")
G.Refresh()   -- a LookChanged in combat repaints (alphas and colours only)
WoW.leaveCombat()
check(not G.pending, "applied at the end of combat")
check(skin.off, "off after combat")
WoW.strictLockdown = false

------------------------------------------------------------
-- A profile switch follows the new profile's setting
------------------------------------------------------------
db.glassButtons = true
G.Apply()
check(not skin.off, "on")
Apotheca.SetProfile("Test-Other")
eq(Apotheca.GetDB().glassButtons, false, "a new profile: off by default")
check(skin.off, "the switch follows it")
Apotheca.SetProfile("Global")
check(not skin.off, "and back")

done("test_glassbuttons")
