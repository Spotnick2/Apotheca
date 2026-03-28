-- ============================================================
-- Apotheca - Smart Consumable Bar for WoW Classic TBC
-- ============================================================

Apotheca = {}

-- ============================================================
-- DEBUG MODE
-- /run Apotheca.SetDebug(true)
-- /run Apotheca.SetDebug(false)
-- ============================================================

Apotheca.DEBUG = false

-- ============================================================
-- CONTAINER API COMPATIBILITY SHIMS
-- TBC Anniversary moved container functions into the C_Container namespace.
-- GetContainerItemID does NOT reliably exist in TBC Anniversary builds —
-- we extract the itemID from the item link string instead, which works in
-- every version of the client including all TBC Anniversary patches.
-- ============================================================

local _C = C_Container or {}

-- GetContainerNumSlots: prefer C_Container, fall back to global
local ContainerGetNumSlots = _C.GetContainerNumSlots or GetContainerNumSlots

-- GetContainerItemLink: prefer C_Container, fall back to global
local ContainerGetItemLink = _C.GetContainerItemLink or GetContainerItemLink

-- GetItemCooldown: prefer C_Container, fall back to global
local ContainerGetItemCooldown = _C.GetItemCooldown or GetItemCooldown

-- Extract a numeric itemID from a standard item hyperlink string.
-- Links look like: |cff...|Hitem:12345:0:0:...|h[Name]|h|r
-- Returns nil if the slot is empty or the link is malformed.
local function GetItemIDFromLink(link)
    if not link then return nil end
    return tonumber(link:match("item:(%d+)"))
end

-- GetContainerItemInfo changed from multi-return to a table in C_Container.
-- Normalise both forms into a single stack count.
local function ContainerGetCount(bag, slot)
    if _C.GetContainerItemInfo then
        local info = _C.GetContainerItemInfo(bag, slot)
        return info and info.stackCount or 0
    else
        local _, count = GetContainerItemInfo(bag, slot)   -- luacheck: ignore
        return count or 0
    end
end

-- ============================================================
-- CONSTANTS
-- ============================================================

local FALLBACK_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"  -- generic (item found but no texture yet)

local BUTTON_SIZE   = 36
local BUTTON_GAP    = 3
local FRAME_PADDING = 4

-- Default position: bottom-center of screen, above the action bars.
-- BOTTOM anchor with a positive Y offset places it above the action bar row.
local DEFAULT_POS = { point = "BOTTOM", x = 0, y = 200 }

-- ============================================================
-- ITEM PRIORITY LISTS  (itemID-based, verified on Wowhead TBC)
-- Ordered highest → lowest priority.
-- ============================================================

-- Mana consumables
-- 32902  Bottled Nethergon Energy  (Tempest Keep instances only)
-- 32903  Cenarion Mana Salve
-- 32948  Auchenai Mana Potion
-- 22832  Super Mana Potion
-- 33093  Mana Potion Injector
-- 13444  Major Mana Potion           (pre-TBC fallback)
--  6149  Greater Mana Potion         (pre-TBC fallback)
local MANA_ITEMS = {
    32902,
    32903,
    32948,
    22832,
    33093,
    13444,
    6149,
}

-- Health consumables
-- 32947  Auchenai Healing Potion
-- 22829  Super Healing Potion
-- 22795  Fel Blossom
-- 22797  Nightmare Seed
-- 13446  Major Healing Potion        (pre-TBC fallback)
--  1710  Greater Healing Potion      (pre-TBC fallback)
local HEALTH_ITEMS = {
    32947,
    22829,
    22795,
    22797,
    13446,
    1710,
}

-- Mana-restore runes (BoP Demonic Rune preferred first)
-- 12662  Demonic Rune
-- 20520  Dark Rune
local RUNE_ITEMS = {
    12662,
    20520,
}

local NETHERGON_ENERGY_ID = 32902   -- gated to Tempest Keep only

local TEMPEST_KEEP_INSTANCES = {
    ["The Eye"]      = true,
    ["The Mechanar"] = true,
    ["The Botanica"] = true,
    ["The Arcatraz"] = true,
}

-- emptyIcon: shown in debug mode when nothing is found for this slot.
-- Each slot type gets a thematically appropriate greyed-out icon so you
-- can tell the slots apart at a glance even when bags are empty.
-- Future phase: these can be surfaced as config options.
local BUTTON_CONFIG = {
    {
        key       = "mana",
        label     = "Mana",
        list      = MANA_ITEMS,
        emptyIcon = "Interface\\Icons\\INV_Potion_76",   -- blue mana flask silhouette
    },
    {
        key       = "health",
        label     = "Health",
        list      = HEALTH_ITEMS,
        emptyIcon = "Interface\\Icons\\INV_Potion_54",   -- red health flask silhouette
    },
    {
        key       = "rune",
        label     = "Rune",
        list      = RUNE_ITEMS,
        emptyIcon = "Interface\\Icons\\INV_Misc_Rune_01", -- rune stone silhouette
    },
}

-- ============================================================
-- UTILITY
-- ============================================================

-- Returns true if the player is inside any Tempest Keep instance.
-- Intentionally does NOT check instanceType: The Eye is a raid ("raid"),
-- the 5-mans are parties ("party") — checking by name alone is correct.
function Apotheca.IsInTempestKeep()
    local name = GetInstanceInfo()
    return TEMPEST_KEEP_INSTANCES[name] == true
end

-- Scan bags 0-4 once, building a map of { [itemID] = count } for every
-- occupied slot. Then walk the priority list and return the first hit.
-- This is more efficient than the naive triple-nested loop because we only
-- call ContainerGetItemLink / GetItemIDFromLink once per slot regardless of
-- how many priority lists reference that slot.
-- Returns: itemID (number|nil), count (number), texture (string|nil)
function Apotheca.FindBestItem(priorityList)
    -- Build bag map (done once per call, shared across priority walk)
    local bagMap = {}   -- [itemID] = total count across all bags
    for bag = 0, 4 do
        local numSlots = ContainerGetNumSlots(bag)
        for slot = 1, numSlots do
            local link = ContainerGetItemLink(bag, slot)
            local slotID = GetItemIDFromLink(link)
            if slotID then
                local count = ContainerGetCount(bag, slot)
                if count > 0 then
                    bagMap[slotID] = (bagMap[slotID] or 0) + count
                end
            end
        end
    end

    -- Priority walk: return first match found in the map
    local inTK = Apotheca.IsInTempestKeep()
    for _, targetID in ipairs(priorityList) do
        if targetID == NETHERGON_ENERGY_ID and not inTK then
            -- skip: Bottled Nethergon Energy only works inside Tempest Keep
        else
            local count = bagMap[targetID]
            if count and count > 0 then
                local _, _, _, _, _, _, _, _, _, texture = GetItemInfo(targetID)
                return targetID, count, texture
            end
        end
    end

    return nil, 0, nil
end

-- ============================================================
-- POSITION PERSISTENCE  (per-character via ApothecaCharDB)
-- ============================================================

-- Save the frame's current screen position into the per-character DB.
-- We store a single anchor point relative to UIParent so the position
-- stays correct regardless of UI scale changes.
local function SavePosition()
    local point, _, _, x, y = ApothecaFrame:GetPoint()
    ApothecaCharDB = ApothecaCharDB or {}
    ApothecaCharDB.point = point
    ApothecaCharDB.x     = x
    ApothecaCharDB.y     = y
end

-- Restore the saved position, or fall back to DEFAULT_POS on first login.
local function RestorePosition()
    local db = ApothecaCharDB
    if db and db.point and db.x and db.y then
        ApothecaFrame:ClearAllPoints()
        ApothecaFrame:SetPoint(db.point, UIParent, db.point, db.x, db.y)
    else
        ApothecaFrame:ClearAllPoints()
        ApothecaFrame:SetPoint(DEFAULT_POS.point, UIParent, DEFAULT_POS.point,
                               DEFAULT_POS.x, DEFAULT_POS.y)
    end
end

-- ============================================================
-- DEBUG HELPERS
-- ============================================================

local function ApplyDebugAttributes(btn)
    if Apotheca.DEBUG then
        btn:SetAttribute("type", nil)
        btn:SetAttribute("item", nil)
    else
        btn:SetAttribute("type", "item")
        -- "item" is written per-update inside UpdateButton
    end
end

local function SetupDebugClick(btn)
    btn:HookScript("OnClick", function(self)
        if not Apotheca.DEBUG then return end
        local label = self.cfg and self.cfg.label or "Unknown"
        if self.itemID then
            local name = GetItemInfo(self.itemID) or ("id:" .. self.itemID)
            print(string.format(
                "|cff9966ffApotheca DEBUG:|r [%s] Would use: %s (id=%d)",
                label, name, self.itemID
            ))
        else
            print(string.format(
                "|cff9966ffApotheca DEBUG:|r [%s] Nothing found in bags",
                label
            ))
        end
    end)
end

-- ============================================================
-- FRAME + BUTTON CREATION
-- ============================================================

local totalWidth  = FRAME_PADDING * 2 + #BUTTON_CONFIG * BUTTON_SIZE + (#BUTTON_CONFIG - 1) * BUTTON_GAP
local totalHeight = FRAME_PADDING * 2 + BUTTON_SIZE

-- Invisible container frame.
-- NOTE: We do NOT register drag on this frame. The child buttons sit on top
-- and eat all mouse events before the frame sees them. Drag is handled on
-- each button's OnMouseDown and forwarded to the frame when Shift is held.
local ApothecaFrame = CreateFrame("Frame", "ApothecaFrame", UIParent)
ApothecaFrame:SetWidth(totalWidth)
ApothecaFrame:SetHeight(totalHeight)
ApothecaFrame:SetPoint(DEFAULT_POS.point, UIParent, DEFAULT_POS.point,
                       DEFAULT_POS.x, DEFAULT_POS.y)
ApothecaFrame:SetMovable(true)
ApothecaFrame:SetClampedToScreen(true)
ApothecaFrame:SetFrameStrata("MEDIUM")

-- Debug badge — floats above the bar, only visible in debug mode
local debugLabel = ApothecaFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
debugLabel:SetPoint("BOTTOMLEFT", ApothecaFrame, "TOPLEFT", 0, 2)
debugLabel:SetText("|cffff6600[DEBUG]|r")
debugLabel:Hide()
Apotheca.debugLabel = debugLabel

Apotheca.buttons = {}

for i, cfg in ipairs(BUTTON_CONFIG) do
    local xOffset = FRAME_PADDING + (i - 1) * (BUTTON_SIZE + BUTTON_GAP)
    local yOffset = -FRAME_PADDING

    local btn = CreateFrame(
        "Button",
        "ApothecaButton_" .. cfg.key,
        ApothecaFrame,
        "SecureActionButtonTemplate"
    )
    btn:SetWidth(BUTTON_SIZE)
    btn:SetHeight(BUTTON_SIZE)
    btn:SetPoint("TOPLEFT", ApothecaFrame, "TOPLEFT", xOffset, yOffset)
    btn:RegisterForClicks("AnyUp")

    -- Shift+LeftClick drag: forward to the parent frame so the whole bar moves.
    -- Buttons sit on top of ApothecaFrame and swallow all mouse events, so the
    -- frame's own OnDragStart would never fire. We handle it here instead.
    -- SecureActionButtonTemplate blocks SetScript in combat, but movement while
    -- in combat is already prevented by the InCombatLockdown() check.
    btn:RegisterForDrag("LeftButton")
    btn:SetScript("OnDragStart", function(self)
        if not InCombatLockdown() and IsShiftKeyDown() then
            ApothecaFrame:StartMoving()
        end
    end)
    btn:SetScript("OnDragStop", function(self)
        ApothecaFrame:StopMovingOrSizing()
        SavePosition()
    end)

    -- Empty slot background (dark inset, shown when no item is found)
    local emptyBg = btn:CreateTexture(nil, "BACKGROUND")
    emptyBg:SetAllPoints(btn)
    emptyBg:SetTexture("Interface\\Buttons\\UI-Quickslot2")
    emptyBg:SetTexCoord(0.1, 0.9, 0.1, 0.9)
    emptyBg:SetAlpha(0.6)
    btn.emptyBg = emptyBg

    -- Item icon
    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(btn)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    btn.icon = icon

    -- Button border overlay (thin bevelled edge)
    local btnBorder = btn:CreateTexture(nil, "OVERLAY")
    btnBorder:SetTexture("Interface\\Buttons\\UI-Quickslot-Depress")
    btnBorder:SetAllPoints(btn)
    btn.btnBorder = btnBorder

    -- Pushed state
    btn:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")

    -- Mouseover highlight
    local highlightTex = btn:CreateTexture(nil, "HIGHLIGHT")
    highlightTex:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
    highlightTex:SetBlendMode("ADD")
    highlightTex:SetAllPoints(btn)
    btn:SetHighlightTexture(highlightTex)

    -- Stack count (bottom-right corner, same as default bag slots)
    local countText = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    countText:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 2)
    btn.countText = countText

    -- Cooldown sweep
    local cd = CreateFrame("Cooldown", "ApothecaCD_" .. cfg.key, btn, "CooldownFrameTemplate")
    cd:SetAllPoints(btn)
    cd:SetDrawEdge(true)
    cd:SetReverse(false)
    btn.cooldown = cd

    -- Tooltip
    btn:SetScript("OnEnter", function(self)
        if self.itemID then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetItemByID(self.itemID)
            if Apotheca.DEBUG then
                GameTooltip:AddLine("|cffff6600[Debug: will not consume]|r", 1, 1, 1, true)
            end
            GameTooltip:Show()
        elseif Apotheca.DEBUG then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(string.format(
                "|cff9966ffApotheca|r — %s\n|cffff6600[Debug] Nothing in bags|r",
                self.cfg.label
            ))
            GameTooltip:Show()
        end
    end)
    btn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    btn.cfg    = cfg
    btn.itemID = nil

    ApplyDebugAttributes(btn)
    SetupDebugClick(btn)

    Apotheca.buttons[cfg.key] = btn
end

-- ============================================================
-- BUTTON UPDATE LOGIC
-- ============================================================

function Apotheca.UpdateButton(btn)
    local itemID, count, texture = Apotheca.FindBestItem(btn.cfg.list)

    -- Emit debug log only when selection changes for this slot
    if Apotheca.DEBUG and itemID ~= btn.itemID then
        local name = itemID and (GetItemInfo(itemID) or ("id:" .. itemID)) or "Nothing"
        print(string.format("|cff9966ffApotheca SCAN:|r [%s] → %s", btn.cfg.label, name))
    end

    btn.itemID = itemID

    -- Secure attributes — only writable outside combat
    if not InCombatLockdown() then
        if Apotheca.DEBUG then
            btn:SetAttribute("type", nil)
            btn:SetAttribute("item", nil)
        elseif itemID then
            btn:SetAttribute("type", "item")
            btn:SetAttribute("item", "item:" .. itemID)
        else
            btn:SetAttribute("type", nil)
            btn:SetAttribute("item", nil)
        end
    end

    if itemID then
        if not texture then
            local _, _, _, _, _, _, _, _, _, retryTex = GetItemInfo(itemID)
            texture = retryTex
        end

        btn.icon:SetTexture(texture or FALLBACK_ICON)
        btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        btn.icon:SetDesaturated(false)
        btn.icon:Show()
        btn.emptyBg:SetAlpha(0)

        btn.countText:SetText(count > 1 and count or "")

        local startTime, duration = ContainerGetItemCooldown(itemID)
        if startTime and duration and duration > 0 then
            btn.cooldown:SetCooldown(startTime, duration)
        else
            btn.cooldown:SetCooldown(0, 0)
        end

        btn:Show()
    else
        btn.countText:SetText("")
        btn.cooldown:SetCooldown(0, 0)

        if Apotheca.DEBUG then
            -- Show a slot-specific greyed placeholder so mana/health/rune
            -- are visually distinguishable even when bags are empty.
            btn.icon:SetTexture(btn.cfg.emptyIcon)
            btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            btn.icon:SetDesaturated(true)
            btn.icon:Show()
            btn.emptyBg:SetAlpha(0.6)
            btn:Show()
        else
            btn.icon:SetTexture(nil)
            btn.icon:SetDesaturated(false)
            btn.icon:Hide()
            btn.emptyBg:SetAlpha(0.6)
            btn:Hide()
        end
    end
end

function Apotheca.UpdateAllButtons()
    if Apotheca.DEBUG then
        Apotheca.debugLabel:Show()
    else
        Apotheca.debugLabel:Hide()
    end
    for _, btn in pairs(Apotheca.buttons) do
        Apotheca.UpdateButton(btn)
    end
end

-- ============================================================
-- PUBLIC API
-- ============================================================

function Apotheca.SetDebug(enabled)
    if InCombatLockdown() then
        print("|cff9966ffApotheca:|r Cannot change debug mode in combat.")
        return
    end
    Apotheca.DEBUG = enabled
    for _, btn in pairs(Apotheca.buttons) do
        ApplyDebugAttributes(btn)
    end
    Apotheca.UpdateAllButtons()
    if enabled then
        print("|cff9966ffApotheca:|r |cffff6600Debug ENABLED.|r Items will not be consumed.")
    else
        print("|cff9966ffApotheca:|r Debug disabled. Normal behavior restored.")
    end
end

-- ============================================================
-- EVENT HANDLING
-- ============================================================

local eventFrame = CreateFrame("Frame", "ApothecaEventFrame", UIParent)
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("BAG_UPDATE_DELAYED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
eventFrame:RegisterEvent("PLAYER_LOGOUT")

-- SPELL_UPDATE_COOLDOWN fires on every GCD (~1.5s in combat) and does
-- NOT carry item-specific data. A full bag scan on every GCD tick caused
-- the disconnect-on-reload issue. CooldownFrameTemplate updates its sweep
-- automatically — we do not need to drive it from an event.

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_ENTERING_WORLD" then
        -- Restore saved position first, then update buttons.
        -- SavedVariables are guaranteed to be loaded by this event.
        RestorePosition()
        Apotheca.UpdateAllButtons()

    elseif event == "BAG_UPDATE_DELAYED" then
        Apotheca.UpdateAllButtons()

    elseif event == "GET_ITEM_INFO_RECEIVED" then
        -- Item cache populated; retry any buttons that had nil textures.
        Apotheca.UpdateAllButtons()

    elseif event == "PLAYER_REGEN_ENABLED" then
        -- Leaving combat: secure attributes are writable again.
        for _, btn in pairs(Apotheca.buttons) do
            ApplyDebugAttributes(btn)
            if not Apotheca.DEBUG and btn.itemID then
                btn:SetAttribute("item", "item:" .. btn.itemID)
            end
        end
        Apotheca.UpdateAllButtons()

    elseif event == "PLAYER_LOGOUT" then
        -- Belt-and-suspenders: save position on logout in addition to OnDragStop.
        -- This catches any edge case where the frame was moved programmatically.
        SavePosition()
    end
end)