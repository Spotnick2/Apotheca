-- ============================================================
-- ApothecaWheel.lua: the Mage Scrolls wheel (#94)
--
-- A ring of every mage scroll held, opened at the cursor by the Mage
-- Scrolls button on the main bar (ApothecaButton_magescrolls) or its key
-- binding. Works in combat: secure snippets run on this client since
-- 1.60.1.70425, in combat too (porting guide, "Secure click-casting works").
--
-- How a scroll is used:
-- - Hold the key, release over a scroll (Opie style): the button's wrapped
--   OnClick opens the ring on the down edge; on the up edge it picks the
--   slot nearest the cursor, outside a dead zone at the centre, copies
--   that slot's item onto itself for this one click (the template acts on
--   the release: useOnKeyDown false), and the post-snippet clears it.
-- - Tap the key, or click the button: released inside the dead zone, the
--   ring stays open. Click a scroll (each slot is a secure item button of
--   its own), tap the key again, or press Esc (an override binding the
--   ring holds while open) to close it. A mouse release only counts over
--   the button pressed, so with the mouse it is always click, then click.
--
-- What the ring holds is set out of combat only (SetContents, from the full
-- update) and frozen in combat, like the bar; counts and cooldowns keep
-- updating (RefreshVisuals). The art (disc, highlight, name) is an insecure
-- child of the ring: it shows with it, and is never a parent of a secure
-- button, so it can change in combat.
-- ============================================================

local Apotheca = Apotheca
local API = Apotheca.API
local W = {}
Apotheca.Wheel = W

-- One secure slot per scroll in the catalogue, so every scroll carried is
-- reachable (Codex review of #98: a cap of 24 dropped the rest of a full
-- staff mage's 30). Made at load, out of combat. The ring grows with the
-- count: 34 slots make a radius of about 250, which still fits the screen.
W.SLOTS = math.max(24, #(Apotheca.DATA and Apotheca.DATA.MAGE_SCROLLS or {}))
W.SIZE = 36            -- a slot's size
W.GAP = 10             -- between slots along the ring
W.MIN_RADIUS = 70
W.DEADZONE = 26        -- a release this close to the centre keeps it open
W.LABEL_ROOM = 26      -- under the ring, for the scroll's name (owner: it fell off the screen)
W.CLOSE_NAME = "ApothecaWheelClose"

-- ── Secure frames ─────────────────────────────────────────────────
-- The header covers the screen (never takes the mouse): its mouse position
-- places the ring, and it owns the snippets' shared environment and the
-- Esc override binding. Explicitly protected, as SecureHandlerWrapScript
-- requires.
local screen = CreateFrame("Frame", "ApothecaWheel", UIParent, "SecureHandlerBaseTemplate")
screen:SetAllPoints(UIParent)
screen:SetFrameStrata("DIALOG")
screen:EnableMouse(false)
W.screen = screen

local ring = CreateFrame("Frame", "ApothecaWheelRing", screen, "SecureFrameTemplate")
ring:SetSize(1, 1)
ring:SetPoint("CENTER", screen, "BOTTOMLEFT", 0, 0)
ring:EnableMouse(false)
ring:Hide()
W.ring = ring
SecureHandlerSetFrameRef(screen, "ring", ring)

-- Esc clicks this while the ring is open.
local closeBtn = CreateFrame("Button", W.CLOSE_NAME, screen, "SecureActionButtonTemplate")
closeBtn:RegisterForClicks(API.ClickEdges())
closeBtn:Hide()

-- Hides the ring and drops the Esc binding. Runs as the header.
screen:SetAttribute("close", [[
    self:GetFrameRef("ring"):Hide()
    self:ClearBindings()
]])
screen:SetAttribute("count", 0)
screen:SetAttribute("enabled", false)
screen:SetAttribute("deadzone", W.DEADZONE)
screen:SetAttribute("radius", W.MIN_RADIUS)
screen:SetAttribute("labelroom", W.LABEL_ROOM)

SecureHandlerWrapScript(closeBtn, "OnClick", screen, [[
    owner:RunAttribute("close")
    return false
]])

-- The slots: secure item buttons on the ring. A click uses the scroll (the
-- template acts on the mouse release) and the release closes the ring.
local slots = {}
W.slots = slots
local function SlotOnEnter(self)
    if not self.itemID then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetItemByID(self.itemID)
    GameTooltip:Show()
end
for i = 1, W.SLOTS do
    local b = CreateFrame("Button", "ApothecaWheelSlot" .. i, ring, "SecureActionButtonTemplate")
    b:SetSize(W.SIZE, W.SIZE)
    b:RegisterForClicks(API.ClickEdges())
    Apotheca.StyleButton(b, "ApothecaWheelSlotCD" .. i)
    b:SetScript("OnEnter", SlotOnEnter)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:Hide()
    SecureHandlerWrapScript(b, "OnClick", screen, [[ return nil, "picked" ]],
        [[ if not down then owner:RunAttribute("close") end ]])
    SecureHandlerSetFrameRef(screen, "slot" .. i, b)
    slots[i] = b
end

-- The trigger: press opens, release picks (or leaves it open). `cx, cy`
-- (the ring's centre) and `px, py` (where the press was) live in the
-- header's environment, shared by every snippet it owns. A release still
-- within the dead zone of the press is a tap, even when the ring was moved
-- in from the screen's edge and its centre is far from the cursor (Codex
-- review of #98: a stationary tap there used a scroll).
W.PRE_CLICK = [[
    local ring = owner:GetFrameRef("ring")
    if not owner:GetAttribute("enabled") then
        if ring:IsShown() then owner:RunAttribute("close") end
        return false
    end
    if down then
        if ring:IsShown() then
            -- A second tap closes; its release finds the ring closed.
            owner:RunAttribute("close")
            return false
        end
        local x, y = owner:GetMousePosition()
        if not x then return false end
        local w, h = owner:GetWidth(), owner:GetHeight()
        local r = owner:GetAttribute("radius") + 30
        px, py = x * w, y * h
        cx = math.max(r, math.min(w - r, x * w))
        cy = math.max(r + owner:GetAttribute("labelroom"), math.min(h - r, y * h))
        ring:ClearAllPoints()
        ring:SetPoint("CENTER", owner, "BOTTOMLEFT", cx, cy)
        ring:Show()
        owner:SetBindingClick(true, "ESCAPE", "]] .. W.CLOSE_NAME .. [[")
        return false
    end
    if not ring:IsShown() or not cx then return false end
    local x, y = owner:GetMousePosition()
    if not x then return false end
    local ux, uy = x * owner:GetWidth(), y * owner:GetHeight()
    local dx, dy = ux - cx, uy - cy
    local dead = owner:GetAttribute("deadzone")
    if dx * dx + dy * dy < dead * dead then return false end
    if px and (ux - px) * (ux - px) + (uy - py) * (uy - py) < dead * dead then return false end
    local best, bestD
    for i = 1, owner:GetAttribute("count") do
        local sx, sy = owner:GetAttribute("sx" .. i), owner:GetAttribute("sy" .. i)
        local d = (dx - sx) * (dx - sx) + (dy - sy) * (dy - sy)
        if not bestD or d < bestD then best, bestD = i, d end
    end
    owner:RunAttribute("close")
    if not best then return false end
    local slot = owner:GetFrameRef("slot" .. best)
    local item = slot:GetAttribute("item")
    if not item then return false end
    self:SetAttribute("type", "item")
    self:SetAttribute("item", item)
    self:SetAttribute("target-slot", slot:GetAttribute("target-slot"))
    return nil, "picked"
]]
W.POST_CLICK = [[
    self:SetAttribute("type", nil)
    self:SetAttribute("item", nil)
    self:SetAttribute("target-slot", nil)
]]

local trigger = Apotheca.buttons and Apotheca.buttons["magescrolls"]
W.trigger = trigger
if trigger then
    -- Acts on the release only, whatever ActionButtonUseKeyDown says: the
    -- press opens the ring.
    trigger:SetAttribute("useOnKeyDown", false)
    SecureHandlerWrapScript(trigger, "OnClick", screen, W.PRE_CLICK, W.POST_CLICK)
    trigger:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Mage Scrolls", 1, 1, 1)
        local n = self.scrolls and #self.scrolls or 0
        if n == 0 then
            GameTooltip:AddLine("No mage scroll in bags", 0.6, 0.6, 0.6, true)
        else
            GameTooltip:AddLine(n == 1 and "1 scroll" or (n .. " scrolls"), 0.7, 0.7, 0.9)
            GameTooltip:AddLine("Click, or tap the key: the wheel stays open; click a scroll.",
                0.6, 0.6, 0.6, true)
            GameTooltip:AddLine("Hold the key and release over a scroll to use it.", 0.6, 0.6, 0.6, true)
        end
        GameTooltip:Show()
    end)
end

-- ── Art (insecure) ────────────────────────────────────────────────
-- The disc, highlight and name are an insecure child of the ring: they
-- show with it, and are never a parent of a secure button, so they can
-- change in combat. The ring's own SetAlpha works in combat too (measured on
-- a protected bar: GlassActionBars docs/FOREVER-PROBE.md, item 5, 70374).
--
-- Opening: the disc grows from 70% while the ring (slots included) fades
-- in. Closing: the snippet hides the ring at once, so a ghost (a UIParent
-- child, never part of the ring) copies the disc and the icons and fades
-- out. The timings are GlassPearls' raid mark wheel's.
--
-- The glass is LibGlass's (embedded, Libs\LibGlass-1.0; owner, 2026-11-09:
-- "I really don't like this design... why the tint doesn't align like the
-- rest of glassui"), built as Glass UI builds its own: Pearl, a disc for
-- the wheel and a rounded glass plate for the name, each with an opaque
-- backing under the tint (GlassUI Theme.lua). The body follows Glass UI's
-- suite when it is loaded (docs/SUITE-LOOK.md: the current tint's backing,
-- tint and wash, the accent on the name, as its windows' titles), repainted
-- live on GlassUI.Suite.LookChanged; without it, Glass UI's own default,
-- clear. The name's plate opens over the action bars, so its backing is a
-- window's (GlassUI Theme.WINDOW_BACKING): readable over anything. The
-- disc's backing is at least DISC_BACKING: at clear's 0.35 the action bars
-- and bright scenery showed through it (owner, third run: "a bit more
-- opacity"); 0.6 is the middle of the three Glass UI's owner compared on its
-- merchant (0.85, 0.6, 0.35). Smoked's 0.92 stays.
W.OPEN, W.CLOSE = 0.15, 0.12      -- seconds
W.DISC_BACKING = 0.6
W.PLATE_ALPHA = 0.93              -- GlassUI Theme.WINDOW_BACKING
W.HOVER_ALPHA = 0.4               -- GAB's hover glow (Buttons.HIGHLIGHT)
W.GOLD = { 1, 0.82, 0 }           -- Glass UI's default accent
W.OWN = {                         -- Glass UI's clear body (Suite.BODY.clear)
    backing = { 0.04, 0.05, 0.07, 0.35 }, tint = { 0.13, 0.16, 0.22, 0.24 }, wash = 1,
}
W.DISC_SIDE = 200                 -- the disc is built at this size and scaled
W.PLATE_H = 24
W.SOUNDS = {                      -- Portal Roulette's open and close
    open = "Interface\\AddOns\\Apotheca\\Sounds\\WheelOpen.ogg",
    close = "Interface\\AddOns\\Apotheca\\Sounds\\WheelClose.ogg",
}

-- One LibGlass instance for Apotheca, Pearl (the suite's only material; a
-- copy older than r11 has no Pearl and builds its default).
local Glass
do
    local lib = LibStub("LibGlass-1.0")
    local ok, made = pcall(lib.New, lib, { preset = "pearl" })
    Glass = ok and made or lib:New()
end
W.Glass = Glass

local art = CreateFrame("Frame", nil, ring)
art:SetPoint("CENTER", ring, "CENTER")
art:SetSize(2 * W.MIN_RADIUS + W.SIZE + 20, 2 * W.MIN_RADIUS + W.SIZE + 20)
art:SetFrameLevel(ring:GetFrameLevel())
art:EnableMouse(false)
W.art = art

-- A glass body on `host`: the material plus an opaque backing under the
-- tint, clipped by the glass's own mask (GlassUI Skin/Kit.lua, Backing).
local function Body(host, g)
    local backing = host:CreateTexture(nil, "BACKGROUND", nil, -7)
    backing:SetAllPoints(host)
    backing:AddMaskTexture(g.mask)
    return backing
end

-- The regions of one wheel: the art's, and the ghost's copy. The disc is
-- built square at DISC_SIDE on a frame of its own and scaled to the wheel
-- (LibGlass: resize a disc with SetScale, never SetSize). Its rims stay at
-- its own level, under the slots (GlassUI Kit:Disc).
local function DiscParts(host)
    local p = {}
    p.disc = CreateFrame("Frame", nil, host)
    p.disc:SetSize(W.DISC_SIDE, W.DISC_SIDE)
    p.disc:SetPoint("CENTER", host, "CENTER")
    p.disc:SetFrameLevel(host:GetFrameLevel())
    p.g = Glass.Disc(p.disc, "disc")
    if p.g.top then p.g.top:SetFrameLevel(p.disc:GetFrameLevel()) end
    p.backing = Body(p.disc, p.g)
    -- The name, on a glass plate under the disc, as wide as the name.
    p.plate = CreateFrame("Frame", nil, host)
    p.plate:SetSize(120, W.PLATE_H)
    p.plate:SetPoint("TOP", host, "BOTTOM", 0, -2)
    p.pg = Glass.Apply(p.plate, "small")
    p.plateBacking = Body(p.plate, p.pg)
    p.label = (p.pg.top or p.plate):CreateFontString(nil, "OVERLAY", "GameFontNormal")
    p.label:SetPoint("CENTER", p.plate, "CENTER", 0, 0)
    -- The slot under the cursor: GAB's hover glow, over the slots.
    p.over = CreateFrame("Frame", nil, host)
    p.over:SetAllPoints(host)
    p.over:SetFrameLevel(host:GetFrameLevel() + 6)
    p.hilite = p.over:CreateTexture(nil, "OVERLAY")
    p.hilite:SetSize(W.SIZE, W.SIZE)
    p.hilite:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
    p.hilite:SetBlendMode("ADD")
    p.hilite:SetVertexColor(1, 1, 1, W.HOVER_ALPHA)
    p.hilite:Hide()
    return p
end
local parts = DiscParts(art)
local label = parts.label
W.parts, W.label = parts, label

-- The disc's scale for a wheel of this size, and the plate's width for the
-- name it shows.
local function FitDisc(p, side) p.disc:SetScale(side / W.DISC_SIDE) end
local function SetName(p, text)
    p.label:SetText(text)
    local w = p.label:GetStringWidth()
    if type(w) ~= "number" then w = 0 end
    p.plate:SetWidth(math.max(80, w + 28))
end

-- ── Look ──
-- Optional globals are read with rawget: Glass UI may be absent, and the
-- test stub fails on a global it doesn't list.
local function Suite()
    local gui = rawget(_G, "GlassUI")
    local s = type(gui) == "table" and rawget(gui, "Suite")
    if type(s) == "table" and rawget(s, "API") == 1 then return s end
end
-- Each function feature-detected and called under pcall (SUITE.md).
local function SuiteCall(s, name, ...)
    local fn = rawget(s, name)
    if type(fn) ~= "function" then return nil end
    local ok, r = pcall(fn, ...)
    if ok then return r end
end
local function IsColor(c, n)
    if type(c) ~= "table" then return false end
    for i = 1, n do
        if type(c[i]) ~= "number" or c[i] < 0 or c[i] > 1 then return false end
    end
    return true
end
local function ClassColor()
    local cc = rawget(_G, "C_ClassColor")
    local _, class = UnitClass("player")
    if not (type(cc) == "table" and type(class) == "string") then return nil end
    local ok, c = pcall(cc.GetClassColor, class)
    if ok and type(c) == "table" and type(c.r) == "number" then return c.r, c.g, c.b end
end

-- The look now: { backing = rgba, tint = rgb[a] or nil (the built tint),
-- wash = factor, accent = rgb }.
function W.Look()
    local s = Suite()
    local body = s and SuiteCall(s, "Body")       -- nil: the suite's current tint
    local accent = s and SuiteCall(s, "Accent")
    accent = IsColor(accent, 3) and accent or W.GOLD
    if not (type(body) == "table" and IsColor(body.backing, 4)) then
        return { backing = W.OWN.backing, tint = W.OWN.tint, wash = W.OWN.wash, accent = accent }
    end
    local look = { backing = body.backing, accent = accent,
                   wash = type(body.wash) == "number" and body.wash or 1 }
    if IsColor(body.tint, 4) then
        look.tint = body.tint
    elseif type(body.classShade) == "number" then
        -- The class body has no colour of its own: the class colour, shaded,
        -- at the material's alpha (GlassUI Theme.lua, tintFor).
        local r, g, bl = ClassColor()
        if r then look.tint = { r * body.classShade, g * body.classShade, bl * body.classShade } end
    end
    return look
end

-- Glass UI's paint (Theme.lua): the tint (nil: the material's own), the
-- wash as a factor of the material's, the backing under them.
local function PaintBody(g, backing, look, floor)
    local t = look.tint
    if t then
        Glass.SetSurfaceTint(g, t[1], t[2], t[3], t[4])
    else
        Glass.SetSurfaceTint(g)
    end
    Glass.SetWash(g, math.min(1, Glass.STYLE.wash * look.wash))
    local c = look.backing
    backing:SetColorTexture(c[1], c[2], c[3], math.max(c[4], floor or 0))
end
local function Paint(p, look)
    PaintBody(p.g, p.backing, look, W.DISC_BACKING)
    PaintBody(p.pg, p.plateBacking, look, W.PLATE_ALPHA)
    local a = look.accent
    p.label:SetTextColor(a[1], a[2], a[3])
end
function W.Paint() Paint(parts, W.Look()) end

-- Live: Glass UI fires this when the player changes the suite look, in or
-- out of combat. Only our own textures change.
local registry = rawget(_G, "EventRegistry")
if type(registry) == "table" and type(registry.RegisterCallback) == "function" then
    pcall(registry.RegisterCallback, registry, "GlassUI.Suite.LookChanged", function() W.Paint() end, W)
end

local function Sound(which)
    local s = Apotheca.GetDB().mageScrolls
    if s and s.sound == false then return end
    local play = rawget(_G, "PlaySoundFile")
    if type(play) == "function" then pcall(play, W.SOUNDS[which], "SFX") end
end

-- Positions are in the ring's own units (the header's: the ring is not
-- scaled). Slot i of n sits clockwise from the top.
function W.Layout(n)
    local r = math.max(W.MIN_RADIUS, n * (W.SIZE + W.GAP) / (2 * math.pi))
    local pos = {}
    for i = 1, n do
        local a = math.pi / 2 - (i - 1) * 2 * math.pi / n
        pos[i] = { r * math.cos(a), r * math.sin(a) }
    end
    return pos, r
end

-- The slot the release would pick for a cursor offset (dx, dy) from the
-- centre, or nil inside the dead zone: the snippet's rule, for the art.
function W.Pick(dx, dy, pos)
    if dx * dx + dy * dy < W.DEADZONE * W.DEADZONE then return nil end
    local best, bestD
    for i, p in ipairs(pos) do
        local d = (dx - p[1]) ^ 2 + (dy - p[2]) ^ 2
        if not bestD or d < bestD then best, bestD = i, d end
    end
    return best
end

local layout = {}       -- the current slot positions
local lit               -- the highlighted slot, or nil
local pressX, pressY    -- the cursor when the wheel opened (the snippet's px, py)
local function Highlight()
    local x, y = GetCursorPosition()
    local scale = ring:GetEffectiveScale()
    local rx, ry = ring:GetCenter()
    local i = rx and W.Pick(x / scale - rx, y / scale - ry, layout)
    -- Still where the press was: a release there is a tap, picks nothing.
    if pressX and (x / scale - pressX) ^ 2 + (y / scale - pressY) ^ 2 < W.DEADZONE * W.DEADZONE then i = nil end
    local b = i and slots[i]
    if b and b.itemID then
        lit = i
        parts.hilite:ClearAllPoints()
        parts.hilite:SetPoint("CENTER", art, "CENTER", layout[i][1], layout[i][2])
        parts.hilite:Show()
        SetName(parts, API.ItemInfo(b.itemID) or "")
    else
        lit = nil
        parts.hilite:Hide()
        SetName(parts, "Mage Scrolls")
    end
end

-- An animation's "OUT" and "IN" smoothing.
local function Out(t) return 1 - (1 - t) * (1 - t) end
local function In(t) return t * t end

-- ── Closing: the ghost ──
local ghost
local function BuildGhost()
    ghost = CreateFrame("Frame", nil, UIParent)
    ghost:SetFrameStrata("DIALOG")
    ghost:EnableMouse(false)
    ghost:Hide()
    ghost.parts = DiscParts(ghost)
    ghost.icons = {}
    for i = 1, W.SLOTS do
        local t = ghost:CreateTexture(nil, "ARTWORK")
        t:SetSize(W.SIZE, W.SIZE)
        t:Hide()
        ghost.icons[i] = t
    end
    ghost:SetScript("OnUpdate", function(self)
        local t = math.min(1, (GetTime() - self.started) / W.CLOSE)
        self:SetAlpha(1 - In(t))
        self:SetScale(1 - 0.15 * In(t))
        if t >= 1 then self:Hide() end
    end)
    W.ghost = ghost
end

local cx0, cy0    -- the ring's centre while open (the header fills UIParent: its units)
local function FadeOut()
    if not cx0 then return end
    if not ghost then BuildGhost() end
    ghost:SetSize(art:GetWidth(), art:GetHeight())
    ghost:SetScale(1)
    ghost:SetAlpha(1)
    ghost:ClearAllPoints()
    ghost:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx0, cy0)
    local p = ghost.parts
    Paint(p, W.Look())
    FitDisc(p, art:GetWidth())
    SetName(p, label:GetText() or "")
    p.hilite:ClearAllPoints()
    if lit and layout[lit] then
        p.hilite:SetPoint("CENTER", ghost, "CENTER", layout[lit][1], layout[lit][2])
        p.hilite:Show()
    else
        p.hilite:Hide()
    end
    for i, t in ipairs(ghost.icons) do
        local b, pos = slots[i], layout[i]
        if pos and b.itemID then
            t:SetTexture(b.icon:GetTexture())
            t:SetDesaturated(b.icon:IsDesaturated())
            t:ClearAllPoints()
            t:SetPoint("CENTER", ghost, "CENTER", pos[1], pos[2])
            t:Show()
        else
            t:Hide()
        end
    end
    ghost.started = GetTime()
    ghost:Show()
end

-- ── Opening ──
local opened = 0
art:SetScript("OnShow", function()
    if ghost then ghost:Hide() end
    -- The bar button's tooltip would cover the wheel opened next to it.
    if trigger and GameTooltip:IsOwned(trigger) then GameTooltip:Hide() end
    W.Paint()
    opened = GetTime()
    art:SetScale(0.7)
    ring:SetAlpha(0)
    cx0, cy0 = ring:GetCenter()
    local x, y = GetCursorPosition()
    local s = ring:GetEffectiveScale()
    pressX, pressY = x / s, y / s
    Highlight()
    Sound("open")
end)
art:SetScript("OnUpdate", function()
    if art:GetScale() < 1 then
        local t = math.min(1, (GetTime() - opened) / W.OPEN)
        art:SetScale(0.7 + 0.3 * Out(t))
        ring:SetAlpha(Out(t))
    end
    local x, y = ring:GetCenter()
    if x then cx0, cy0 = x, y end
    Highlight()
end)
art:SetScript("OnHide", function()
    FadeOut()
    Sound("close")
end)

-- ── Contents ──────────────────────────────────────────────────────
-- list: Apotheca.FindMageScrolls's { id, count, tex, entry }, in order.
-- enabled: the button is on the bar with something to offer (else the key
-- does nothing). debug: slots carry no item (debug mode uses nothing).
-- Out of combat only: the full update calls it, and returns in combat.
function W.SetContents(list, enabled, debug)
    if InCombatLockdown() then return end
    local n = math.min(#list, W.SLOTS)
    local pos, r = W.Layout(n)
    layout = pos
    for i, b in ipairs(slots) do
        local e = i <= n and list[i] or nil
        b.itemID = e and e.id or nil
        b:SetAttribute("target-slot", nil)
        if e and not debug then
            b:SetAttribute("type", "item")
            b:SetAttribute("item", "item:" .. e.id)
            -- An imbue goes on the main hand, like the weapon oil (#24); the
            -- client reads it only if the scroll asks for a target.
            if e.entry and e.entry.kind == "imbue" then b:SetAttribute("target-slot", 16) end
        else
            b:SetAttribute("type", nil)
            b:SetAttribute("item", nil)
        end
        if e then
            b:ClearAllPoints()
            b:SetPoint("CENTER", ring, "CENTER", pos[i][1], pos[i][2])
            b.icon:SetTexture(e.tex or "Interface\\Icons\\INV_Misc_QuestionMark")
            b.icon:SetDesaturated(debug and true or false)
            b.emptyBg:SetAlpha(0)
            b.countText:SetText(e.count and e.count > 1 and e.count or "")
            Apotheca.ApplyItemCooldown(b.cooldown, e.id)
            b:Show()
        else
            b:Hide()
        end
        screen:SetAttribute("sx" .. i, pos[i] and pos[i][1] or nil)
        screen:SetAttribute("sy" .. i, pos[i] and pos[i][2] or nil)
    end
    screen:SetAttribute("count", n)
    screen:SetAttribute("radius", r)
    screen:SetAttribute("enabled", enabled and n > 0 and true or false)
    art:SetSize(2 * r + W.SIZE + 20, 2 * r + W.SIZE + 20)
    FitDisc(parts, 2 * r + W.SIZE + 20)
    -- Nothing left to offer: close an open ring.
    if n == 0 and ring:IsShown() then W.Close() end
end

-- Out of combat: close from Lua (the snippet does it in combat).
function W.Close()
    if InCombatLockdown() then return end
    ring:Hide()
    ClearOverrideBindings(screen)
end

-- Counts and cooldowns: no secure change, safe in combat. bagMap nil
-- (counts unreadable) keeps the counts shown.
function W.RefreshVisuals(bagMap)
    for _, b in ipairs(slots) do
        if b.itemID and b:IsShown() then
            Apotheca.ApplyItemCooldown(b.cooldown, b.itemID)
            if bagMap then
                local c = bagMap[b.itemID] or 0
                b.countText:SetText(c > 1 and c or "")
                b.icon:SetDesaturated(c == 0)
            end
        end
    end
end

-- The bar may be skinned by Glass Action Bars (#68): the slots wear it too.
function W.WearGlass()
    if not Apotheca.WearGlass then return end
    for _, b in ipairs(slots) do Apotheca.WearGlass(b) end
end
