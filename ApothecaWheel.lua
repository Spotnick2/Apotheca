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

W.SLOTS = 24           -- the most scrolls the ring shows (34 kinds exist)
W.SIZE = 36            -- a slot's size
W.GAP = 10             -- between slots along the ring
W.MIN_RADIUS = 70
W.DEADZONE = 26        -- a release this close to the centre keeps it open
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
-- (the ring's centre) and `swallow` live in the header's environment,
-- shared by every snippet it owns.
W.PRE_CLICK = [[
    local ring = owner:GetFrameRef("ring")
    if not owner:GetAttribute("enabled") then
        if ring:IsShown() then owner:RunAttribute("close") end
        return false
    end
    if down then
        if ring:IsShown() then
            -- A second tap closes; its release does nothing.
            owner:RunAttribute("close")
            swallow = true
            return false
        end
        swallow = false
        local x, y = owner:GetMousePosition()
        if not x then return false end
        local w, h = owner:GetWidth(), owner:GetHeight()
        local r = owner:GetAttribute("radius") + 30
        cx = math.max(r, math.min(w - r, x * w))
        cy = math.max(r, math.min(h - r, y * h))
        ring:ClearAllPoints()
        ring:SetPoint("CENTER", owner, "BOTTOMLEFT", cx, cy)
        ring:Show()
        owner:SetBindingClick(true, "ESCAPE", "]] .. W.CLOSE_NAME .. [[")
        return false
    end
    if swallow then
        swallow = false
        return false
    end
    if not ring:IsShown() or not cx then return false end
    local x, y = owner:GetMousePosition()
    if not x then return false end
    local dx, dy = x * owner:GetWidth() - cx, y * owner:GetHeight() - cy
    local dead = owner:GetAttribute("deadzone")
    if dx * dx + dy * dy < dead * dead then return false end
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
local art = CreateFrame("Frame", nil, ring)
art:SetPoint("CENTER", ring, "CENTER")
art:SetSize(2 * W.MIN_RADIUS + W.SIZE + 20, 2 * W.MIN_RADIUS + W.SIZE + 20)
art:SetFrameLevel(ring:GetFrameLevel())
art:EnableMouse(false)
W.art = art

local disc = art:CreateTexture(nil, "BACKGROUND")
disc:SetAllPoints(art)
disc:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
disc:SetVertexColor(0, 0, 0, 0.55)

local hub = art:CreateTexture(nil, "BORDER")
hub:SetSize(2 * W.DEADZONE, 2 * W.DEADZONE)
hub:SetPoint("CENTER", art, "CENTER")
hub:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
hub:SetVertexColor(0.6, 0.4, 1, 0.25)

local hilite = art:CreateTexture(nil, "ARTWORK")
hilite:SetSize(W.SIZE + 18, W.SIZE + 18)
hilite:SetTexture("Interface\\Buttons\\CheckButtonHilight")
hilite:SetBlendMode("ADD")
hilite:Hide()

local label = art:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
label:SetPoint("TOP", art, "BOTTOM", 0, -4)
W.label = label

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
local function Highlight()
    local x, y = GetCursorPosition()
    local scale = ring:GetEffectiveScale()
    local rx, ry = ring:GetCenter()
    local i = rx and W.Pick(x / scale - rx, y / scale - ry, layout)
    local b = i and slots[i]
    if b and b.itemID then
        hilite:ClearAllPoints()
        hilite:SetPoint("CENTER", b, "CENTER")
        hilite:Show()
        label:SetText(API.ItemInfo(b.itemID) or "")
    else
        hilite:Hide()
        label:SetText("Mage Scrolls")
    end
end
art:SetScript("OnUpdate", Highlight)
art:SetScript("OnShow", Highlight)

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
