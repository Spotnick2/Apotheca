-- ============================================================
-- ApothecaGlass.lua: the Glass button style without Glass Action Bars (#41)
--
-- An option (`glassButtons`, per profile, off by default) puts GAB's button
-- skin on Apotheca's buttons for players who don't use GAB: the main bar,
-- the profession bar and the Mage Scrolls wheel's slots, plus a glass plate
-- for the Alt-drag anchor. The skin is LibGlass's `Glass.Button` (r13,
-- LibGlass#46: GAB's skin moved into the library so Apotheca wears the same
-- one without a copy; docs/GLASS-MATERIAL.md section 8), built on the
-- wheel's Pearl instance (W.Glass), the material GAB builds by default.
--
-- Who styles a button is decided once, at PLAYER_LOGIN (r13 design note on
-- #41): a button GAB's SkinButton took (#68) stays GAB's, under GAB's look
-- and switch, and the option is greyed out. Every other button (no GAB, or
-- GAB with its glass off: SkinButton says false) can wear Apotheca's own
-- skin. In r13 the first LibGlass instance to skin a button holds it, also
-- while switched off, so going from one owner to the other needs a /reload.
-- Apotheca's own on and off is live (SetButtonShown), out of combat: the
-- switch rewrites the pushed texture, a method of the secure button.
--
-- The look is GAB's, read through the getters each time LibGlass paints:
-- - Following Glass UI's suite (W.ownLook false; GlassUI.Suite.Look()), the
--   suite's tint (clear, smoked, class), hover and press, live on
--   GlassUI.Suite.LookChanged; GAB's own defaults otherwise (clear, glow,
--   flash).
-- - The tints are GAB's Theme.lua PRESETS (Glass UI's SUITE-LOOK.md gives
--   the same numbers): clear is the glass as built, smoked a dark body with
--   a weaker wash, class the class colour shaded to 0.6.
-- - The wheel's slots have no hover of their own (hover "off"): the wheel
--   lights the slot a release would pick (ApothecaWheel.lua, Highlight).
-- - Never an empty slot: a button whose item ran out is out of stock and
--   keeps its greyed icon (#68, owner), so SetButtonEmpty is never called.
--   The empty-slot art's alpha follows the stock, so Apotheca hides it
--   itself; only the bronze frame goes to the skin's `fade` list.
--
-- Off gives the regions back with their alphas at 1 (LibGlass), and
-- Restore puts the rest of Apotheca's look back: the pushed texture, the
-- count and hotkey fonts, the empty-slot art.
-- ============================================================

local Apotheca = Apotheca
local G = {}
Apotheca.GlassButtons = G

G.DEPRESS = "Interface\\Buttons\\UI-Quickslot-Depress"
G.SMOKED = { 0.05, 0.06, 0.08, 0.62 }     -- GAB Theme.PRESETS.smoked.tint
G.SMOKED_WASH = 0.14 / 0.18               -- GAB Theme.PRESETS.smoked.wash
G.CLASS_SHADE = 0.6                       -- GAB Theme.PRESETS.class.classShade
G.TINTS = { clear = true, smoked = true, class = true }
G.HOVERS = { off = true, glow = true, halo = true }
G.PRESSES = { off = true, flash = true, ripple = true }
G.ANCHOR = { 0.40, 0.27, 0.66, 0.55 }     -- the drag anchor's purple (Apotheca.lua)

G.skins = {}        -- button -> Apotheca's own skin
G.errors = {}       -- step -> the first error LibGlass reported for it
G.pending = false   -- a style change waiting for the end of combat
G.started = false
local suiteLook = {}

local function Glass() return Apotheca.Wheel and Apotheca.Wheel.Glass end

-- LibGlass r13's button calls, on the instance.
function G.Available()
    local gl = Glass()
    return type(gl) == "table" and type(gl.Button) == "function" and type(gl.SetButtonShown) == "function"
        and type(gl.RestyleButton) == "function" and type(gl.RefreshButtons) == "function"
end

-- Every button the style covers, and whether it is a wheel slot.
function G.Buttons()
    local list = {}
    local function add(btn, slot) if btn then list[#list + 1] = { btn = btn, slot = slot } end end
    for _, key in ipairs(Apotheca.DEFAULT_BUTTON_ORDER or {}) do add(Apotheca.buttons[key], false) end
    for _, a in ipairs(Apotheca.Utility and Apotheca.Utility.ACTIONS or {}) do
        add(Apotheca.Utility.buttons[a.key], false)
    end
    for _, b in ipairs(Apotheca.Wheel and Apotheca.Wheel.slots or {}) do add(b, true) end
    return list
end

-- Why the option can't be used, or nil: "gab" (GAB styles the buttons) or
-- "library" (no Glass.Button: LibGlass older than r13).
function G.Reason()
    if G.gab then return "gab" end
    if not G.Available() then return "library" end
end

function G.Wanted()
    return G.Reason() == nil and Apotheca.GetDB().glassButtons == true
end

-- ── The look ──
-- The suite's look keys, copied, while Apotheca follows it.
local function CopyLook(look)
    for k in pairs(suiteLook) do suiteLook[k] = nil end
    if type(look) ~= "table" then return end
    local t, h, p = rawget(look, "tint"), rawget(look, "hover"), rawget(look, "press")
    if G.TINTS[t] then suiteLook.tint = t end
    if G.HOVERS[h] then suiteLook.hover = h end
    if G.PRESSES[p] then suiteLook.press = p end
end

function G.ReadSuite()
    local W = Apotheca.Wheel
    local s = W and not W.ownLook and W.Suite and W.Suite()
    CopyLook(s and W.SuiteCall(s, "Look") or nil)
end
G._suiteLook = suiteLook

-- The tint for the current suite tint: nil is the glass as built.
function G.Tint()
    local name = suiteLook.tint or "clear"
    if name == "smoked" then return G.SMOKED end
    if name == "class" then
        local r, g, b = Apotheca.Wheel.ClassColor()
        if r then return { r * G.CLASS_SHADE, g * G.CLASS_SHADE, b * G.CLASS_SHADE } end
    end
    return nil
end

local function LookFor(slot)
    return function(key)
        if key == "hover" then return slot and "off" or suiteLook.hover end
        if key == "press" then return suiteLook.press end
        if key == "tint" then return G.Tint() end
        if key == "tintWash" then return suiteLook.tint == "smoked" and G.SMOKED_WASH or nil end
        return nil
    end
end

local function OnError(step, msg)
    step = tostring(step)
    if G.errors[step] then return end
    G.errors[step] = tostring(msg)
    print("|cff9966ffApotheca:|r the glass buttons hit an error (" .. step .. "): " .. tostring(msg))
end

-- ── Building, on and off ──
local function Build(btn, slot)
    local gl = Glass()
    local skin, why = gl.Button(btn, {
        icon = btn.icon, pushed = btn:GetPushedTexture(), highlight = btn.highlightTex,
        hotkey = btn.hotkey, count = btn.countText,
        fade = { border = btn.btnBorder },
    }, { look = LookFor(slot), onError = OnError, maskIcon = true })
    if skin then
        G.skins[btn] = skin
        btn._glassSize = btn:GetWidth()
    elseif why == "skinned" then
        btn._glassHeld = true   -- another LibGlass instance holds it (until /reload)
    end
    return skin, why
end

-- Apotheca's own look back, after LibGlass let go (its alphas are at 1).
function G.Restore(btn)
    local p = btn:GetPushedTexture()
    if p and p.ClearTextureSlice then p:ClearTextureSlice() end
    btn:SetPushedTexture(G.DEPRESS)
    p = btn:GetPushedTexture()
    if p then p:SetBlendMode("BLEND") end
    btn.countText:SetFontObject("NumberFontNormal")
    if btn.hotkey then btn.hotkey:SetFontObject("NumberFontNormalSmallGray") end
    btn.emptyBg:Show()
end

-- The Alt-drag anchors (both bars): a purple glass plate while the buttons
-- are glass (GAB's or Apotheca's), the flat purple otherwise. The text
-- moves onto the plate's top, over its rim.
local function AnchorGlass(a)
    if a.glass then return a.glass end
    local gl = Glass()
    if not (gl and type(gl.Apply) == "function") then return nil end
    local f = CreateFrame("Frame", nil, a)
    f:SetAllPoints(a)
    f:EnableMouse(false)
    local ok, g = pcall(gl.Apply, f, "small")
    if not ok then
        OnError("anchor", g)
        f:Hide()
        a.glassFailed = true
        return nil
    end
    local c = G.ANCHOR
    gl.SetSurfaceTint(g, c[1], c[2], c[3], c[4])
    a.glass, a.glassG = f, g
    return f
end

function G.SyncAnchor()
    local on = G.gab or (G.Wanted() and next(G.skins) ~= nil)
    for _, a in ipairs(Apotheca.anchors or {}) do
        local glass = on and not a.glassFailed and AnchorGlass(a) or nil
        if a.glass then a.glass:SetShown(glass ~= nil) end
        a.bg:SetShown(glass == nil)
        a.text:SetParent(glass and (a.glassG.top or glass) or a)
    end
end

-- Every button to the option's state. Out of combat only: in combat it
-- waits for PLAYER_REGEN_ENABLED.
function G.Apply()
    if not G.started then return end
    if InCombatLockdown() then
        G.pending = true
        return
    end
    G.pending = false
    local want = G.Wanted()
    local gl = Glass()
    for _, e in ipairs(G.Buttons()) do
        local btn = e.btn
        if not (btn._gabGlass or btn._glassHeld) then
            local skin = G.skins[btn]
            if want then
                if not skin then skin = Build(btn, e.slot) end
                if skin then
                    gl.SetButtonShown(skin, true)
                    btn.emptyBg:Hide()
                end
            elseif skin and not skin.off then
                gl.SetButtonShown(skin, false)
                G.Restore(btn)
            end
        end
    end
    G.SyncAnchor()
end

-- At PLAYER_LOGIN, after GAB's SkinButton calls and the suite's Theme.
function G.Start()
    G.started = true
    for _, e in ipairs(G.Buttons()) do
        if e.btn._gabGlass then G.gab = true end
    end
    G.ReadSuite()
    G.Apply()
end

-- A resize (GridLayout): the skin's setup again (small fonts under 40).
function G.Resized(btn, size)
    local skin = G.skins[btn]
    if not skin or btn._glassSize == size then return end
    btn._glassSize = size
    Glass().RestyleButton(skin)
end

-- Repaint every skin: the look changed, or the class colour can be read.
-- Combat-safe (alphas and colours only).
function G.Refresh()
    if next(G.skins) == nil then return end
    Glass().RefreshButtons()
end

local registry = rawget(_G, "EventRegistry")
if type(registry) == "table" and type(registry.RegisterCallback) == "function" then
    pcall(registry.RegisterCallback, registry, "GlassUI.Suite.LookChanged", function(_, look)
        local W = Apotheca.Wheel
        if W and W.ownLook then return end
        if type(look) == "table" then CopyLook(look) else G.ReadSuite() end
        G.Refresh()
    end, G)
end
