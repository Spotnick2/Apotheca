-- ============================================================
-- Apotheca - Smart Consumable Bar for WoW: Forever
-- Author: Spotnick
-- ============================================================

-- ApothecaCompat.lua loads first and has already set Apotheca.API.
Apotheca = Apotheca or {}

-- ============================================================
-- SAVED VARIABLES & DEFAULTS
-- ============================================================

-- ============================================================
-- SAVED VARIABLES STRUCTURE
-- ApothecaDB = {
--   profiles    = { ["Global"] = {...}, ["Realm-Name"] = {...} }
--   activeProfile = "Global"   -- "Global" or a "Realm-CharName" key
-- }
-- DB() always returns the active profile table.
-- ============================================================

local PROFILE_DEFAULTS = {
    enabled             = true,
    debug               = false,
    -- Only show the bar while the resolved role is Healer. Replaces the old
    -- showOnlyHealingSpec (see InitDB): off by default, the bar serves
    -- every role (#9). The role settings themselves (override, damage
    -- style, group role) are PER CHARACTER, in ApothecaCharDB.
    onlyWhenHealer      = false,
    -- Grey the food, drink, potion and healthstone icons while the resource
    -- they restore is full (#6). Display only: clicks still work.
    fullTint            = true,
    lockPosition        = false,
    visibility          = "ALWAYS",
    showEmptyButtons    = false,
    orientation         = "HORIZONTAL",
    rows                = 1,
    iconSize            = 36,
    iconPadding         = 3,
    -- Take the icon size and padding from one of the client's action bars
    -- (1-8, 0 = off) in the current Edit Mode layout (#40), over the two
    -- above, which are kept for when it is switched off. Rows and
    -- orientation stay the bar's own: one Apotheca bar often sits beside
    -- several stacked action bars.
    matchBar            = 0,
    buffFood = {
        enabled            = true,
        glowOnMissingBuff  = true,
        allowSubstitutions = true,
        strictBestOnly     = false,
    },
    -- Buff food stat categories considered at all (keys as in
    -- ApothecaItems.lua BUFF_FOOD_BY_STAT).
    categories = {
        healing = true, spellDmg = true, intellect = true, spirit = true,
        stamina = true, strength = true, agility = true, attackPower = true,
        crit = true, armor = true,
    },
    -- Ordered stat priority per ROLE profile key (HEALER, TANK, CASTER,
    -- MELEE, AGILITY; indices 1-4 = slot order). Empty: the role's profile
    -- decides (Apotheca.GetRoleProfile).
    buffFoodPriority = {},
    elixirs = {
        enabled        = true,
    },
    -- Scroll buttons: each role shows the scrolls it wants (the profile's
    -- `scrolls`); these switch one kind off for every role.
    scrolls = {
        enabled           = true,
        spirit            = true,
        protection        = true,
        intellect         = true,
        stamina           = true,
        strength          = true,
        agility           = true,
        glowOnMissingBuff = true,
    },
    -- Mage mana gem button (#9).
    manaGem = {
        enabled = true,
    },
    weaponOil = {
        enabled           = true,
        glowOnMissingBuff = true,
        -- Which oil (#29): "AUTO" by role, "MANA_FIRST", "WIZARD_FIRST",
        -- "MANA_ONLY". Replaces the old includeWizardOils checkbox.
        kind              = "AUTO",
    },
    health = {
        preferHealthstone = true,
    },
    healthstone = {
        enabled   = true,
        -- Pick the smallest stone that covers the missing health instead
        -- of always offering the strongest one.
        smartRank = true,
    },
    bandage = {
        enabled = true,
    },
    -- Rogue poisons (#24): EXPERIMENTAL, off by default, not yet tried on a
    -- rogue in game. The poison kind per hand is a per-character setting
    -- (Apotheca.PoisonChoice).
    -- Weapon stones (#32): EXPERIMENTAL. Which stone per hand is a
    -- per-character choice (Apotheca.StoneChoice, default "none"), so
    -- nothing changes for anyone who doesn't pick one.
    stones = {
        glowOnMissingBuff = true,
        remind            = false,
    },
    poisons = {
        enabled           = false,
        glowOnMissingBuff = true,
        remind            = false,   -- the 5-second reminder after combat
    },
    -- XP food (#19): optional, off by default. Offers a food with the 5%
    -- kill-XP bonus while you can still gain XP, and glows for a few
    -- seconds after combat when that buff is not up.
    xpFood = {
        enabled = false,
    },
    -- "BLOCK" = silently disable button, "ASK" = confirmation popup,
    -- "DO_NOTHING" = no prevention
    preventWasteMode    = "BLOCK",
    -- Right-click on food/drink (via waste popup) to use the alternate item.
    -- "OFF" = right-click same as left, "ASK" = confirmation popup.
    rightClickAlternate = "OFF",
    -- Prefer conjured food/drink unless non-conjured is >= this multiplier better.
    conjuredThreshold   = 1.5,
    -- Custom visual order of button categories.
    -- nil / missing = use the built-in default order.
    buttonOrder         = nil,
}

local function DeepCopy(src)
    if type(src) ~= "table" then return src end
    local dst = {}
    for k, v in pairs(src) do dst[k] = DeepCopy(v) end
    return dst
end

local function ApplyDefaults(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            for k2, v2 in pairs(v) do
                if dst[k][k2] == nil then dst[k][k2] = DeepCopy(v2) end
            end
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end

-- Returns the character-specific profile key: "RealmName-CharName"
-- Only valid after PLAYER_LOGIN.
function Apotheca.GetCharProfileKey()
    local realm = GetRealmName and GetRealmName() or "Unknown"
    local name  = UnitName and UnitName("player") or "Unknown"
    return realm .. "-" .. name
end

-- Returns the active profile table.
-- Falls back to PROFILE_DEFAULTS before ADDON_LOADED fires.
local function DB()
    if not ApothecaDB or not ApothecaDB.profiles then return PROFILE_DEFAULTS end
    local key = ApothecaDB.activeProfile or "Global"
    return ApothecaDB.profiles[key] or PROFILE_DEFAULTS
end

-- Switch to a named profile, creating it from defaults if it doesn't exist.
function Apotheca.SetProfile(key)
    if not ApothecaDB then return end
    if not ApothecaDB.profiles[key] then
        ApothecaDB.profiles[key] = DeepCopy(PROFILE_DEFAULTS)
    else
        -- InitDB only backfills the profile that was active at load, so a
        -- profile last touched by an older version is still missing every
        -- setting added since. Fill it in on the way in, or the code that
        -- reads those keys sees nil and disagrees about what is enabled.
        ApplyDefaults(ApothecaDB.profiles[key], PROFILE_DEFAULTS)
    end
    ApothecaDB.activeProfile = key
    Apotheca.UpdateAllButtons()
    if Apotheca.RefreshOptions then Apotheca.RefreshOptions() end
end

function Apotheca.GetActiveProfileKey()
    return (ApothecaDB and ApothecaDB.activeProfile) or "Global"
end

-- Initialize ApothecaDB on ADDON_LOADED.
-- Wrapped in pcall so a corrupted SavedVariables file never crashes the addon.
-- SavedVariables were written but never read back through build 69977
-- (PORTING-TBC-TO-FOREVER.md section 1); 70009 fixed it. svLoadCheck is
-- written every session and is never in PROFILE_DEFAULTS, so finding it at
-- load proves the client really read the file, at every login. Missing on a
-- new build, the login line says the bug may be back.
-- It must never be given a default.
local svLoaded = false

-- The migration pass for one saved profile: legacy keys, and buff food
-- priorities saved by older builds. Buff food priorities saved by TBC builds
-- are the old defaults
-- ({healing, mp5, crit, stamina} and the paladin variant), or name stats
-- Forever food no longer has. Drop them so the role profile decides; a real
-- custom order survives. Applied to EVERY profile, whichever route the data
-- came in by (profile structure, flat-DB migration, or a later SetProfile).
local function MigrateProfile(prof)
    if type(prof) ~= "table" then return end
    -- The old boolean preventWaste becomes preventWasteMode. v1.0.0 saved
    -- preventWaste = true in every profile, and from v1.0.2 ApplyDefaults
    -- filled preventWasteMode = "BLOCK" before the old migration looked, so
    -- the old key was never removed. So the boolean's presence says nothing:
    -- - ASK or DO_NOTHING can only be the player's choice: keep it.
    -- - BLOCK may be that filled-in default over a saved `false`: the
    --   boolean is the better evidence (Codex and /code-review of #17).
    if prof.preventWaste ~= nil then
        if prof.preventWasteMode == nil or prof.preventWasteMode == "BLOCK" then
            prof.preventWasteMode = prof.preventWaste and "BLOCK" or "DO_NOTHING"
        end
        prof.preventWaste = nil
    end
    -- The old includeWizardOils checkbox (#29): ticked was a choice, "mana
    -- oil, then wizard oil", which is MANA_FIRST. Unticked was the saved
    -- default for everyone, so it becomes the new default, by role. It
    -- overrides the "AUTO" ApplyDefaults has already filled in.
    -- Only over no choice or the default: a kind picked in the new dropdown
    -- is never replaced by a leftover checkbox (/code-review of #30).
    if type(prof.weaponOil) == "table" and prof.weaponOil.includeWizardOils ~= nil then
        local kind = prof.weaponOil.kind
        if prof.weaponOil.includeWizardOils == true and (kind == nil or kind == "AUTO") then
            prof.weaponOil.kind = "MANA_FIRST"
        end
        prof.weaponOil.includeWizardOils = nil
    end
    -- A custom button order saved before a newer button gets it next to its
    -- neighbour, as in the default order, not at the end where
    -- GetButtonOrder would append it: XP Food (#19), poisons (#24).
    if type(prof.buttonOrder) == "table" and #prof.buttonOrder > 0 then
        for _, new in ipairs({ { "xpfood", "bufffood" }, { "poisonmh", "weaponoil" },
                               { "poisonoh", "poisonmh" }, { "stonemh", "poisonoh" },
                               { "stoneoh", "stonemh" } }) do
            local at, has = nil, false
            for i, k in ipairs(prof.buttonOrder) do
                if k == new[1] then has = true end
                if k == new[2] then at = i end
            end
            if not has and at then table.insert(prof.buttonOrder, at + 1, new[1]) end
        end
    end
    -- showOnlyHealingSpec was a class check that defaulted to TRUE, so every
    -- saved profile holds true whether or not anyone chose it. Under the new
    -- role check it would hide the whole bar for a healer class playing
    -- Tank or Damage. It is renamed onlyWhenHealer (default false) and the
    -- old value is dropped, not carried over (/code-review of #14).
    prof.showOnlyHealingSpec = nil
    if type(prof.buffFoodPriority) ~= "table" then return end
    local valid = {}
    for k in pairs(Apotheca.DATA.BUFF_FOOD_BY_STAT) do valid[k] = true end
    -- A usable priority: a list of known stat names that is not one of the
    -- two old TBC defaults (their "mp5" and "crit" are valid stats, so the
    -- defaults are matched whole).
    local function usable(list)
        if type(list) ~= "table" then return false end
        for _, stat in ipairs(list) do
            if type(stat) ~= "string" or not valid[stat] then return false end
        end
        local joined = table.concat(list, ",")
        return joined ~= "healing,mp5,crit,stamina" and joined ~= "healing,crit,mp5,stamina"
    end
    -- Priorities are per role profile now (#9). A usable per-CLASS entry
    -- moves to the role that class defaults to, unless that role already
    -- has a usable order. It is checked BEFORE moving: several classes map
    -- to HEALER, and an old default must not take the slot of a real one.
    local CLASS_DEFAULT_KEY = {
        PRIEST = "HEALER", PALADIN = "HEALER", SHAMAN = "HEALER", DRUID = "HEALER",
        WARRIOR = "MELEE", MAGE = "CASTER", WARLOCK = "CASTER",
        ROGUE = "AGILITY", HUNTER = "AGILITY",
    }
    for cls, key in pairs(CLASS_DEFAULT_KEY) do
        local list = prof.buffFoodPriority[cls]
        prof.buffFoodPriority[cls] = nil
        if usable(list) and not usable(prof.buffFoodPriority[key]) then
            prof.buffFoodPriority[key] = list
        end
    end
    for key, list in pairs(prof.buffFoodPriority) do
        if not usable(list) then prof.buffFoodPriority[key] = nil end
    end
end
Apotheca._MigrateProfile = MigrateProfile

local function InitDB()
    svLoaded = type(ApothecaDB) == "table" and ApothecaDB.svLoadCheck ~= nil
    local ok, err = pcall(function()
        if type(ApothecaDB) ~= "table" then ApothecaDB = {} end

        -- Already in the new profile structure — just ensure defaults
        if type(ApothecaDB.profiles) == "table" then
            local key = ApothecaDB.activeProfile or "Global"
            if type(ApothecaDB.profiles[key]) ~= "table" then
                ApothecaDB.profiles[key] = DeepCopy(PROFILE_DEFAULTS)
            else
                ApplyDefaults(ApothecaDB.profiles[key], PROFILE_DEFAULTS)
            end
            -- The old boolean preventWaste is converted in the cleanup pass
            -- below, for every profile (MigrateProfile).
            return
        end

        -- Migrate old flat structure into Global profile
        local old = {}
        for k, v in pairs(ApothecaDB) do
            if k ~= "profiles" and k ~= "activeProfile" then
                old[k] = v
            end
        end
        for k in pairs(ApothecaDB) do ApothecaDB[k] = nil end
        ApothecaDB.profiles      = { Global = DeepCopy(PROFILE_DEFAULTS) }
        ApothecaDB.activeProfile = "Global"
        -- Salvage flat keys that match known profile fields
        local safe = { "debug","showOnlyHealingSpec","preventWaste","visibility",
                       "showEmptyButtons","orientation","rows",
                       "iconSize","iconPadding","buffFood","categories",
                       "buffFoodPriority","elixirs","lockPosition","enabled",
                       "preventWasteMode","buttonOrder" }
        for _, k in ipairs(safe) do
            if old[k] ~= nil then
                ApothecaDB.profiles.Global[k] = old[k]
            end
        end
        ApplyDefaults(ApothecaDB.profiles.Global, PROFILE_DEFAULTS)
    end)
    -- Inside its own pcall, and only on a DB that initialised: a malformed
    -- saved priority must fall into the reset below, never escape it.
    if ok then
        ok, err = pcall(function()
            for _, prof in pairs(ApothecaDB.profiles) do MigrateProfile(prof) end
        end)
    end

    if not ok then
        -- SavedVariables was corrupt — wipe and start fresh
        print("|cff9966ffApotheca:|r SavedVariables error, resetting to defaults. (" .. tostring(err) .. ")")
        ApothecaDB = {
            profiles      = { Global = DeepCopy(PROFILE_DEFAULTS) },
            activeProfile = "Global",
        }
    end
end

-- ============================================================
-- CONTAINER / ITEM HELPERS
-- Thin wrappers over Apotheca.API (ApothecaCompat.lua), which owns
-- every moved API. They call through the table at call time.
-- ============================================================

local function ContainerGetNumSlots(bag)   return Apotheca.API.ContainerNumSlots(bag) end
local function ContainerGetItemID(bag, slot) return Apotheca.API.ContainerItemID(bag, slot) end
local function ContainerGetCount(bag, slot) return Apotheca.API.ContainerItemCount(bag, slot) end
local function SafeGetItemCooldown(itemID) return Apotheca.API.ItemCooldown(itemID) end

-- Draw an item's cooldown swipe. Cooldowns may be secret in combat, and a
-- secret throws when compared, so the values go straight to the widget,
-- which accepts secrets. A zero duration already clears the swipe. The
-- pcall only guards a client that refuses the call outright.
local function ApplyItemCooldown(cooldown, itemID)
    pcall(function()
        local st, dur = SafeGetItemCooldown(itemID)
        cooldown:SetCooldown(st or 0, dur or 0)
    end)
end
local function GetItemInfo(itemID)         return Apotheca.API.ItemInfo(itemID) end

-- ============================================================
-- TEXTURE CACHE
-- ============================================================

local itemTextureCache = {}
local itemNameCache    = {}

local function GetCachedTexture(itemID)
    if itemTextureCache[itemID] then return itemTextureCache[itemID] end
    -- GetItemIconByID answers without the item cache, so a fresh login shows
    -- the right icon instead of a question mark until GET_ITEM_INFO_RECEIVED.
    local tex = Apotheca.API.ItemIcon(itemID)
    if not tex then tex = select(10, GetItemInfo(itemID)) end
    if tex then itemTextureCache[itemID] = tex end
    return tex
end

local function GetCachedItemName(itemID)
    if itemNameCache[itemID] then return itemNameCache[itemID] end
    local name = GetItemInfo(itemID)
    if name then itemNameCache[itemID] = name end
    return name
end

local function ClearTextureCache()
    itemTextureCache = {}
    itemNameCache    = {}
end

-- ============================================================
-- CONSTANTS
-- ============================================================

local FALLBACK_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local BUTTON_SIZE   = 36
local BUTTON_GAP    = 3
local FRAME_PADDING = 4
local DEFAULT_POS = { point = "BOTTOMLEFT", x = 600, y = 200 }

-- ============================================================
-- HEALER SPEC DETECTION
-- ============================================================

-- WoW: Forever has no talent trees: GetTalentTabInfo is gone, and
-- C_SpecializationInfo reports exactly one spec per class, named after the
-- class, with role DAMAGER even for a Priest (docs/FOREVER-PROBE.md). The
-- role comes from the game's role selector instead (Apotheca.ResolveRole).
function Apotheca.IsHealerSpec()
    return (Apotheca.ResolveRole()) == "HEALER"
end

-- Buff-food stat priority, per role PROFILE (not per class: a healer who
-- switches to damage must not keep healer food).
function Apotheca.GetStatPriority()
    local _, key = Apotheca.ResolveRole()
    local p = DB().buffFoodPriority
    if p and type(p[key]) == "table" then return p[key] end
    return Apotheca.GetRoleProfile().buffFood
end

function Apotheca.IsVisible()
    local v = DB().visibility or "ALWAYS"
    if v == "HIDDEN"        then return false end
    if v == "IN_COMBAT"     then return InCombatLockdown() end
    if v == "OUT_OF_COMBAT" then return not InCombatLockdown() end
    return true
end

-- ============================================================
-- ITEM DATA
-- Generated from the client's own tooltips into ApothecaItems.lua
-- (Tools/build_item_tables.py). Edit the generator, not the data.
-- ============================================================

local DATA = Apotheca.DATA

local MANA_ITEMS        = DATA.MANA_ITEMS
local HEALTH_ITEMS      = DATA.HEALTH_ITEMS
local POTION_VALUE      = DATA.POTION_VALUE
local PERCENT_POTIONS   = DATA.PERCENT_POTIONS
local RUNE_ITEMS        = DATA.RUNE_ITEMS
local CONJURED_ITEMS    = DATA.CONJURED_ITEMS
local DRINK_ITEMS       = DATA.DRINK_ITEMS
local FOOD_ITEMS        = DATA.FOOD_ITEMS
local BUFF_FOOD_BY_STAT = DATA.BUFF_FOOD_BY_STAT
local HEALTHSTONE_ITEMS = DATA.HEALTHSTONE_ITEMS
local BANDAGE_ITEMS     = DATA.BANDAGE_ITEMS

-- Threshold: prefer conjured over non-conjured UNLESS the non-conjured
-- item restores at least this multiplier more mana/health.
-- Configurable via db.conjuredThreshold (default 1.5).
local function GetConjuredThreshold()
    local db = DB()
    return db.conjuredThreshold or 1.5
end

-- Scrolls: item IDs strongest first, plus the buff spell IDs they apply so
-- an active scroll buff is recognised on any client language.
local function IDs(list)
    local ids, spells = {}, {}
    for _, e in ipairs(list or {}) do
        ids[#ids + 1] = e.id
        if e.spell then spells[#spells + 1] = e.spell end
    end
    return ids, spells
end
-- Every scroll button, by the stat its scroll grants. `setting` is the
-- db.scrolls switch; `blockers` are buffs the scroll does not stack with
-- (spell IDs of any rank; their localized name matches every rank).
local SCROLL_KINDS = {
    { key = "spiritscroll",     stat = "spirit",    setting = "spirit",     label = "Spirit",
      emptyIcon = "Interface\\Icons\\INV_Scroll_03",
      blockers = { 14752, 14818, 14819, 27841, 27681 }, blockerName = "Divine Spirit" },
    { key = "protectionscroll", stat = "armor",     setting = "protection", label = "Protection",
      emptyIcon = "Interface\\Icons\\INV_Scroll_06" },
    { key = "intellectscroll",  stat = "intellect", setting = "intellect",  label = "Intellect",
      emptyIcon = "Interface\\Icons\\INV_Scroll_01",
      blockers = { 1459, 1460, 1461, 10156, 10157, 23028 }, blockerName = "Arcane Intellect" },
    { key = "staminascroll",    stat = "stamina",   setting = "stamina",    label = "Stamina",
      emptyIcon = "Interface\\Icons\\INV_Scroll_07",
      blockers = { 1243, 1244, 1245, 2791, 10937, 10938, 21562, 21564 },
      blockerName = "Power Word: Fortitude" },
    { key = "strengthscroll",   stat = "strength",  setting = "strength",   label = "Strength",
      emptyIcon = "Interface\\Icons\\INV_Scroll_02" },
    { key = "agilityscroll",    stat = "agility",   setting = "agility",    label = "Agility",
      emptyIcon = "Interface\\Icons\\INV_Scroll_04" },
}
for _, kind in ipairs(SCROLL_KINDS) do
    kind.items, kind.spells = IDs(DATA.SCROLLS_BY_STAT[kind.stat])
end
Apotheca.SCROLL_KINDS = SCROLL_KINDS

-- Weapon oils, strongest first by kind.
-- Oil entries ({ id, level }) by kind, strongest first.
local MANA_OIL_ITEMS, WIZARD_OIL_ITEMS = {}, {}
for _, oil in ipairs(DATA.OILS) do
    local list = oil.kind == "mana" and MANA_OIL_ITEMS or WIZARD_OIL_ITEMS
    list[#list + 1] = { id = oil.id, level = oil.level or 1 }
end

-- Battleground-only items: "pvp" means any battleground, otherwise
-- { map = instance map ID, name = enUS name }.
local ZONE_RESTRICTED_ITEMS = DATA.ZONE_RESTRICTED_ITEMS

-- True unless the item is battleground-only and we are somewhere else.
-- GetInstanceInfo returns the CONTINENT outdoors on this client, so the
-- gate is instanceType first. The map ID works on every client language;
-- the enUS name is only the fallback for a battleground whose ID is not
-- measured yet (Darkspear Islands).
function Apotheca.IsItemUsableHere(itemID)
    local where = ZONE_RESTRICTED_ITEMS[itemID]
    if not where then return true end
    local name, instanceType, _, _, _, _, _, mapID = GetInstanceInfo()
    if instanceType ~= "pvp" then return false end
    if where == "pvp" then return true end
    if where.map then return mapID == where.map end
    return name == where.name
end

-- ============================================================
-- ROLE PROFILES
-- What a role wants from buff food and from each elixir slot, as ordered
-- stat lists (stat keys are the ones Tools/build_item_tables.py emits).
-- Only healers are shown the bar by default; the other profiles are the
-- starting point for widening Apotheca to casters and other roles.
-- ============================================================

local ROLE_PROFILES = {
    TANK = {
        oil      = "MANA_ONLY",   -- Weapon Oil "by role" (#29)
        scrolls  = { "armor", "stamina" },
        buffFood = { "stamina", "armor", "strength", "agility" },
        flask    = { "maxHealth" },
        battle   = { "armor", "maxHealth", "stamina" },
        guardian = { "stamina", "strength", "agility" },
    },
    HEALER = {
        oil      = "MANA_FIRST",   -- Weapon Oil "by role" (#29)
        scrolls  = { "spirit", "intellect", "armor" },
        buffFood = { "healing", "intellect", "spirit", "stamina" },
        flask    = { "maxMana", "healing" },
        battle   = { "healing", "intellect" },    -- first elixir slot
        guardian = { "mp5", "spirit" },           -- second elixir slot
    },
    CASTER = {
        oil      = "WIZARD_FIRST",   -- Weapon Oil "by role" (#29)
        scrolls  = { "intellect", "spirit", "armor" },
        buffFood = { "spellDmg", "intellect", "spirit", "stamina" },
        flask    = { "spellDmg", "maxMana" },
        battle   = { "spellDmg", "intellect" },
        guardian = { "mp5", "spirit" },
    },
    MELEE = {
        oil      = "MANA_ONLY",   -- Weapon Oil "by role" (#29)
        scrolls  = { "strength", "agility", "armor" },
        buffFood = { "strength", "agility", "attackPower", "stamina" },
        flask    = { "maxHealth" },
        battle   = { "strength", "agility", "attackPower" },
        guardian = { "crit", "stamina", "armor" },
    },
    AGILITY = {
        oil      = "MANA_ONLY",   -- Weapon Oil "by role" (#29)
        scrolls  = { "agility", "strength", "armor" },
        buffFood = { "agility", "attackPower", "crit", "stamina" },
        flask    = { "maxHealth" },
        battle   = { "agility", "attackPower" },
        guardian = { "crit", "stamina" },
    },
}

-- Per class: the role it defaults to, the order it prefers when several
-- roles are ticked in the game's selector, and what its damage looks like.
local CLASS_ROLES = {
    PRIEST  = { default = "HEALER", prefer = { "HEALER", "DAMAGE" },           damage = "CASTER" },
    PALADIN = { default = "HEALER", prefer = { "HEALER", "TANK", "DAMAGE" },   damage = "MELEE" },
    SHAMAN  = { default = "HEALER", prefer = { "HEALER", "DAMAGE", "TANK" },   damage = "HYBRID_MELEE" },
    DRUID   = { default = "HEALER", prefer = { "HEALER", "TANK", "DAMAGE" },   damage = "HYBRID_AGILITY" },
    WARRIOR = { default = "DAMAGE", prefer = { "TANK", "DAMAGE" },             damage = "MELEE" },
    MAGE    = { default = "DAMAGE", prefer = { "DAMAGE" },                     damage = "CASTER" },
    WARLOCK = { default = "DAMAGE", prefer = { "DAMAGE" },                     damage = "CASTER" },
    ROGUE   = { default = "DAMAGE", prefer = { "DAMAGE" },                     damage = "AGILITY" },
    HUNTER  = { default = "DAMAGE", prefer = { "DAMAGE" },                     damage = "AGILITY" },
}
Apotheca.CLASS_ROLES = CLASS_ROLES

-- Classes whose characters have mana at all, whatever form they are in:
-- UnitPowerType follows the current form, so it cannot decide this.
local NO_MANA_CLASSES = { WARRIOR = true, ROGUE = true }

function Apotheca.UsesMana()
    local _, className = UnitClass("player")
    return not NO_MANA_CLASSES[className]
end

-- The role this character plays: "TANK", "HEALER" or "DAMAGE", and the
-- profile key it maps to ("TANK", "HEALER", "CASTER", "MELEE", "AGILITY").
-- Order: Apotheca's own override; then, only if the player opted in, the
-- role assigned in the current group; then the game's role selector (one
-- ticked role, or the class's preferred one among several); then the
-- class default.
-- Role settings are PER CHARACTER (ApothecaCharDB): a Tank override on a
-- warrior must not turn the priest on the same shared profile into a tank.
function Apotheca.CharSetting(key, default)
    local c = ApothecaCharDB
    local v = type(c) == "table" and c[key]
    if v == nil then return default end
    return v
end

function Apotheca.SetCharSetting(key, value)
    ApothecaCharDB = type(ApothecaCharDB) == "table" and ApothecaCharDB or {}
    ApothecaCharDB[key] = value
    Apotheca.RefreshRole()
end

local function ComputeRole()
    local _, className = UnitClass("player")
    local cls = CLASS_ROLES[className] or CLASS_ROLES.PRIEST

    local role = Apotheca.CharSetting("role", "AUTO")
    if role ~= "TANK" and role ~= "HEALER" and role ~= "DAMAGE" then
        role = Apotheca.CharSetting("useGroupRole", false) == true and Apotheca.API.GroupRole() or nil
    end
    if not role then
        local t, h, d = Apotheca.API.SelectedRoles()
        if t ~= nil then
            local ticked = { TANK = t, HEALER = h, DAMAGE = d }
            for _, r in ipairs(cls.prefer) do
                if ticked[r] then role = r break end
            end
        end
        role = role or cls.default
    end

    local key = role
    if role == "DAMAGE" then
        key = cls.damage
        if key == "HYBRID_MELEE" or key == "HYBRID_AGILITY" then
            if Apotheca.CharSetting("damageStyle", "SPELL") == "PHYSICAL" then
                key = key == "HYBRID_MELEE" and "MELEE" or "AGILITY"
            else
                key = "CASTER"
            end
        end
    end
    return role, key
end

-- The resolved role is cached: it is read on hot paths (every UNIT_AURA
-- through the elixir state, several times per update). It is recomputed
-- by RefreshRole, which role events, role settings, every full update and
-- a slow out-of-combat check call.
local roleCache
function Apotheca.ResolveRole()
    if not roleCache then
        local role, key = ComputeRole()
        roleCache = { role, key }
    end
    return roleCache[1], roleCache[2]
end

-- Recompute; true when the resolved role CHANGED. A change refreshes the
-- options panel (its buff-food dropdowns follow the role) and, unless
-- `quiet` (the caller IS the update), asks for an update, which waits out
-- of combat.
function Apotheca.RefreshRole(quiet)
    local old = roleCache and roleCache[2]
    roleCache = nil
    local _, key = Apotheca.ResolveRole()
    if old ~= nil and key ~= old then
        if Apotheca.RefreshOptions then Apotheca.RefreshOptions() end
        if not quiet and Apotheca.RequestUpdate then Apotheca.RequestUpdate() end
        return true
    end
    return false
end

function Apotheca.GetRoleProfile()
    local _, key = Apotheca.ResolveRole()
    return ROLE_PROFILES[key] or ROLE_PROFILES.HEALER
end
Apotheca.ROLE_PROFILES = ROLE_PROFILES

-- Elixir slot lists for a profile, built from the catalog: every elixir
-- (or flask) that grants one of the slot's stats, best first. Earlier
-- stats in the slot's list win over later ones; within a stat, the bigger
-- value wins. `value` keeps BestElixirItem's "highest wins" contract.
local function ElixirSlot(stats, wantFlask)
    local picked = {}
    for _, e in ipairs(DATA.ELIXIR_CATALOG) do
        if e.flask == wantFlask then
            for rank, stat in ipairs(stats) do
                local v = e.stats[stat]
                if v then
                    picked[#picked + 1] = { id = e.id, spell = e.spell,
                        value = (#stats - rank + 1) * 100000 + v }
                    break
                end
            end
        end
    end
    table.sort(picked, function(x, y) return x.value > y.value end)
    return picked
end

local elixirCache = {}
local function GetPlayerElixirData()
    local profile = Apotheca.GetRoleProfile()
    if not elixirCache[profile] then
        local battle, guardian = ElixirSlot(profile.battle, false), ElixirSlot(profile.guardian, false)
        local function spells(list)
            local out = {}
            for _, e in ipairs(list) do out[#out + 1] = e.spell end
            return out
        end
        elixirCache[profile] = {
            flask          = ElixirSlot(profile.flask, true),
            battle         = battle,
            guardian       = guardian,
            battleSpells   = spells(battle),
            guardianSpells = spells(guardian),
        }
    end
    return elixirCache[profile]
end

-- ============================================================
-- BUTTON CONFIGS
-- ============================================================

local STATIC_BUTTON_CONFIG = {
    { key = "mana",   label = "Mana",   list = MANA_ITEMS,   restores = "mana",   emptyIcon = "Interface\\Icons\\INV_Potion_76",
      emptyTooltip = "No mana potion in bags" },
    { key = "health", label = "Health", list = HEALTH_ITEMS, restores = "health", emptyIcon = "Interface\\Icons\\INV_Potion_54",
      emptyTooltip = "No health potion in bags" },
    { key = "rune",   label = "Rune",   list = RUNE_ITEMS,   restores = "mana",   emptyIcon = "Interface\\Icons\\INV_Misc_Rune_01",
      emptyTooltip = "No Demonic or Dark Rune in bags" },
}

local RECOVERY_BUTTON_CONFIG = {
    { key = "recovery", label = "Recovery", emptyIcon = "Interface\\Icons\\INV_Misc_Food_15" },
    { key = "food",     label = "Food",     restores = "health", emptyIcon = "Interface\\Icons\\INV_Misc_Food_01" },
    { key = "drink",    label = "Drink",    restores = "mana",   emptyIcon = "Interface\\Icons\\INV_Drink_05"     },
}

local BUFFFOOD_BUTTON_CONFIG = {
    key = "bufffood", label = "Buff Food", emptyIcon = "Interface\\Icons\\INV_Misc_Food_64",
}

local XPFOOD_BUTTON_CONFIG = {
    key = "xpfood", label = "XP Food", emptyIcon = "Interface\\Icons\\INV_Misc_Food_65",
    emptyTooltip = "No XP food in bags",
}

local ELIXIR_BUTTON_CONFIG = {
    { key = "flask",    label = "Flask",    emptyIcon = "Interface\\Icons\\INV_Potion_97"  },
    { key = "battle",   label = "Elixir",   emptyIcon = "Interface\\Icons\\INV_Potion_51"  },
    { key = "guardian", label = "Elixir 2", emptyIcon = "Interface\\Icons\\INV_Potion_Forsaken_01" },
}

-- Scroll buttons come from SCROLL_KINDS: one list, not three.
local SCROLL_BUTTON_CONFIG = {}
for _, kind in ipairs(SCROLL_KINDS) do
    SCROLL_BUTTON_CONFIG[#SCROLL_BUTTON_CONFIG + 1] =
        { key = kind.key, label = kind.label, emptyIcon = kind.emptyIcon }
end

-- Mage mana gem: its own cooldown, so its own button. Mages only.
local MANAGEM_BUTTON_CONFIG = {
    key = "managem", label = "Mana Gem", restores = "mana", classOnly = "MAGE",
    emptyIcon = "Interface\\Icons\\INV_Misc_Gem_Stone_01",
    emptyTooltip = "No mana gem in bags",
}

-- Rogue poisons (#24, experimental): one button per hand. targetSlot makes
-- the secure button apply the item to that hand ("target-slot", read by
-- the client's secure item action after the use). Measured on the main
-- hand with a weapon oil (70009); poisons and the off hand are not yet.
local POISON_BUTTON_CONFIG = {
    { key = "poisonmh", label = "Poison (main hand)", classOnly = "ROGUE", targetSlot = 16, group = "poisons",
      emptyIcon = "Interface\\Icons\\Ability_Poisons", emptyTooltip = "No poison of the chosen kind in bags" },
    { key = "poisonoh", label = "Poison (off hand)", classOnly = "ROGUE", targetSlot = 17, group = "poisons",
      emptyIcon = "Interface\\Icons\\Ability_Poisons", emptyTooltip = "No poison of the chosen kind in bags" },
}

-- Left-click applies the oil to the main hand directly, with no targeting
-- cursor (measured on 70009 with Minor Wizard Oil, /apo applytest: a
-- 3-second cast, then the oil renewed; #24). Right-click keeps the old way:
-- the cursor, to pick any weapon (Codex review of #28). leftClickOnly sets
-- "target-slot1" (the secure template's left-button variant, upstream);
-- if a client ignored it, left-click would just fall back to the cursor.
-- No target at all while the main hand can't take a coating.
local WEAPONOIL_BUTTON_CONFIG = {
    requiresMana = true,   -- mana and wizard oils are for casters and healers
    key = "weaponoil", label = "Weapon Oil", emptyIcon = "Interface\\Icons\\INV_Potion_95",
    targetSlot = 16, leftClickOnly = true,
    -- Shown with Show Empty Buttons: the role's oil choice may skip an oil
    -- you do carry.
    emptyTooltip = "No usable oil for your oil choice in bags (Options: Scrolls & Weapon Oil, Oil)",
}

-- Weapon stones (#32, experimental): one button per hand, only for a hand
-- the character chose a stone for (StoneChoice). target-slot on every
-- click, like the poisons.
local STONE_BUTTON_CONFIG = {
    { key = "stonemh", label = "Stone (main hand)", targetSlot = 16, group = "stones",
      emptyIcon = "Interface\\Icons\\INV_Stone_SharpeningStone_01", emptyTooltip = "No stone for this weapon in bags" },
    { key = "stoneoh", label = "Stone (off hand)", targetSlot = 17, group = "stones",
      emptyIcon = "Interface\\Icons\\INV_Stone_SharpeningStone_01", emptyTooltip = "No stone for this weapon in bags" },
}
-- Every per-hand coating button (poisons, stones): one glow lifecycle.
local COATING_BUTTON_CONFIG = {}
for _, list in ipairs({ POISON_BUTTON_CONFIG, STONE_BUTTON_CONFIG }) do
    for _, cfg in ipairs(list) do COATING_BUTTON_CONFIG[#COATING_BUTTON_CONFIG + 1] = cfg end
end

local BANDAGE_BUTTON_CONFIG = {
    restores = "health",
    key = "bandage", label = "Bandage", emptyIcon = "Interface\\Icons\\INV_Misc_Bandage_Netherweave_Heavy",
    emptyTooltip = "No bandage in bags",
}

local HEALTHSTONE_BUTTON_CONFIG = {
    restores = "health",
    key = "healthstone", label = "Healthstone", emptyIcon = "Interface\\Icons\\INV_Stone_04",
    emptyTooltip = "No healthstone in bags",
}

-- ============================================================
-- RESOLUTION FUNCTIONS
-- ============================================================

function Apotheca.BuildBagMap()
    local bagMap = {}
    for _, bag in ipairs(Apotheca.API.CarriedBags()) do
        local numSlots = ContainerGetNumSlots(bag)
        for slot = 1, numSlots do
            local id = ContainerGetItemID(bag, slot)
            -- Items usable only somewhere else (battleground rations,
            -- bandages, draughts) are left out here, so every finder skips
            -- them, not only FindBestItem.
            if id and Apotheca.IsItemUsableHere(id) then
                local count = ContainerGetCount(bag, slot)
                if count > 0 then
                    bagMap[id] = (bagMap[id] or 0) + count
                end
            end
        end
    end
    return bagMap
end

-- The best potion held for `resource` ("health" or "mana"): the strongest
-- fixed potion, unless a percentage potion restores more for THIS player.
-- Maximum health and mana are readable, so "30%" becomes a number here;
-- if they are not, a percentage potion is only used when nothing else is.
function Apotheca.FindBestPotion(resource, list, bagMap)
    local id, count, tex = Apotheca.FindBestItem(list, bagMap)
    local best = id and POTION_VALUE[resource][id] or 0
    local maxHP, maxMana = Apotheca.API.PlayerMax()
    local max = resource == "health" and maxHP or maxMana
    for _, p in ipairs(PERCENT_POTIONS) do
        local c = bagMap[p.id]
        if p.resource == resource and c and c > 0 then
            local value = max and max * p.percent / 100 or 0
            if not id or value > best then
                id, count, tex, best = p.id, c, GetCachedTexture(p.id), value
            end
        end
    end
    return id, count, tex
end

-- The strongest item held that is off cooldown; if none is (or cooldowns
-- are unreadable, e.g. secret in combat), the strongest held.
-- 4th return: when a STRONGER item was skipped for its cooldown, the time
-- its cooldown ends, so the caller can re-pick it then (an expiry may fire
-- no event at all).
function Apotheca.FindBestReadyItem(list, bagMap)
    local firstID, firstCount
    local strongerReadyAt
    for _, id in ipairs(list) do
        local count = bagMap[id]
        if count and count > 0 then
            if not firstID then firstID, firstCount = id, count end
            local ok, onCooldown, endsAt = pcall(function()
                local start, dur = SafeGetItemCooldown(id)
                local cd = (dur or 0) > 1.5       -- more than a global cooldown
                return cd, cd and (start + dur) or nil
            end)
            if ok and not onCooldown then
                return id, count, GetCachedTexture(id), strongerReadyAt
            end
            if ok and endsAt and (not strongerReadyAt or endsAt < strongerReadyAt) then
                strongerReadyAt = endsAt
            end
        end
    end
    if firstID then return firstID, firstCount, GetCachedTexture(firstID), strongerReadyAt end
    return nil, 0, nil, nil
end

function Apotheca.FindBestItem(list, bagMap)
    for _, id in ipairs(list) do
        local count = bagMap[id]
        if count and count > 0 then
            return id, count, GetCachedTexture(id)
        end
    end
    return nil, 0, nil
end

-- Returns: primaryID, primaryCount, primaryTex, alternateID, alternateCount, alternateTex, restoresMana
function Apotheca.FindBestFood(bagMap, missingHP)
    missingHP = missingHP or 0

    -- Find the best conjured and best non-conjured food in bags.
    local bestConj, bestNonConj = nil, nil
    for _, entry in ipairs(FOOD_ITEMS) do
        local count = bagMap[entry.id]
        if count and count > 0 then
            local e = { id = entry.id, healthValue = entry.healthValue,
                        count = count, conjured = entry.conjured or false,
                        restoresMana = entry.restoresMana or false }
            if e.conjured then
                if not bestConj or e.healthValue > bestConj.healthValue then
                    bestConj = e
                end
            else
                if not bestNonConj or e.healthValue > bestNonConj.healthValue then
                    bestNonConj = e
                end
            end
        end
    end

    if not bestConj and not bestNonConj then return nil, 0, nil, nil, 0, nil, false end

    -- Only one type available — no alternate.
    if not bestConj then
        return bestNonConj.id, bestNonConj.count, GetCachedTexture(bestNonConj.id),
               nil, 0, nil, bestNonConj.restoresMana
    end
    if not bestNonConj then
        return bestConj.id, bestConj.count, GetCachedTexture(bestConj.id),
               nil, 0, nil, bestConj.restoresMana
    end

    -- Both available — apply threshold.
    if bestNonConj.healthValue >= bestConj.healthValue * GetConjuredThreshold() then
        return bestNonConj.id, bestNonConj.count, GetCachedTexture(bestNonConj.id),
               bestConj.id, bestConj.count, GetCachedTexture(bestConj.id),
               bestNonConj.restoresMana
    else
        return bestConj.id, bestConj.count, GetCachedTexture(bestConj.id),
               bestNonConj.id, bestNonConj.count, GetCachedTexture(bestNonConj.id),
               bestConj.restoresMana
    end
end

-- Returns: primaryID, primaryCount, primaryTex, alternateID, alternateCount, alternateTex
function Apotheca.FindBestDrink(bagMap)
    -- Find the best conjured and best non-conjured drink in bags.
    local bestConj, bestNonConj = nil, nil
    for _, entry in ipairs(DRINK_ITEMS) do
        local count = bagMap[entry.id]
        if count and count > 0 then
            local e = { id = entry.id, manaValue = entry.manaValue,
                        count = count, conjured = entry.conjured or false,
                        restoresHealth = entry.restoresHealth or false }
            if e.conjured then
                if not bestConj or e.manaValue > bestConj.manaValue then
                    bestConj = e
                end
            else
                if not bestNonConj or e.manaValue > bestNonConj.manaValue then
                    bestNonConj = e
                end
            end
        end
    end

    if not bestConj and not bestNonConj then return nil, 0, nil, nil, 0, nil end

    -- 7th return: the chosen drink also restores health.
    if not bestConj then
        return bestNonConj.id, bestNonConj.count, GetCachedTexture(bestNonConj.id),
               nil, 0, nil, bestNonConj.restoresHealth
    end
    if not bestNonConj then
        return bestConj.id, bestConj.count, GetCachedTexture(bestConj.id),
               nil, 0, nil, bestConj.restoresHealth
    end

    -- Both available — apply 1.5x threshold.
    if bestNonConj.manaValue >= bestConj.manaValue * GetConjuredThreshold() then
        return bestNonConj.id, bestNonConj.count, GetCachedTexture(bestNonConj.id),
               bestConj.id, bestConj.count, GetCachedTexture(bestConj.id),
               bestNonConj.restoresHealth
    else
        return bestConj.id, bestConj.count, GetCachedTexture(bestConj.id),
               bestNonConj.id, bestNonConj.count, GetCachedTexture(bestNonConj.id),
               bestConj.restoresHealth
    end
end

-- `skip`: item IDs Buff Food must not offer (the XP food, while the XP
-- Food button shows one; #19). Skipped outright, so strict mode measures
-- only against food Buff Food can offer.
function Apotheca.FindBestBuffFood(bagMap, skip)
    local db       = DB()
    local bf       = db.buffFood
    if not bf or not bf.enabled then return nil, 0, nil end

    local priority   = Apotheca.GetStatPriority()
    if not priority then return nil, 0, nil end

    local categories = db.categories or PROFILE_DEFAULTS.categories

    -- The best held food of one stat. `strict`: nothing unless it is the
    -- best that stat has at all.
    local function scanCategory(statKey, strict)
        local entries = BUFF_FOOD_BY_STAT[statKey]
        if not entries or #entries == 0 then return nil, 0, nil end
        if categories[statKey] == false then return nil, 0, nil end

        local bestID, bestVal, bestCount = nil, -1, 0
        local globalBestVal = -1
        for _, entry in ipairs(entries) do
            if not (skip and skip[entry.id]) then
                if entry.value > globalBestVal then globalBestVal = entry.value end
                local count = bagMap[entry.id]
                if count and count > 0 and entry.value > bestVal then
                    bestVal   = entry.value
                    bestID    = entry.id
                    bestCount = count
                end
            end
        end
        if not bestID then return nil, 0, nil end
        if strict and bestVal < globalBestVal then return nil, 0, nil end
        return bestID, bestCount, GetCachedTexture(bestID)
    end

    for _, statKey in ipairs(priority) do
        local id, count, tex = scanCategory(statKey, bf.strictBestOnly)
        if id then return id, count, tex end
    end

    -- allowSubstitutions fallback: the same scan without strict
    if bf.strictBestOnly and bf.allowSubstitutions then
        for _, statKey in ipairs(priority) do
            local id, count, tex = scanCategory(statKey, false)
            if id then return id, count, tex end
        end
    end

    return nil, 0, nil
end

-- ============================================================
-- BUFF CHECKS
-- Every check returns true / false, or nil when the client refused the
-- read (combat secrecy). Callers must treat nil as "unknown", never as
-- "missing".
--
-- A buff is matched by spell ID, or by the LOCALIZED name of that spell
-- (C_Spell.GetSpellName), so every check works on any client language.
-- The name also covers other ranks of the same buff, and an aura whose ID
-- differs from the item's spell (not measured for every item).
-- ============================================================

-- Localized spell names are static for the session: look each up once.
-- Only a found name is cached: GetSpellName answers nil until the spell's
-- data is loaded, and caching that miss would stop the name ever matching.
local spellNameCache = {}
local function SpellName(spellID)
    local n = spellNameCache[spellID]
    if n == nil then
        local ok, name = pcall(C_Spell.GetSpellName, spellID)
        if ok and name then
            n = name
            spellNameCache[spellID] = n
        end
    end
    return n
end

-- One read of the player's auras, or nil when refused.
local function ReadAuras(filter)
    local names, ids = Apotheca.API.PlayerAuras(filter)
    if not names then return nil end
    return { names = names, ids = ids }
end

-- Is any of these spells active? `spells` is a list of spell IDs;
-- `fallback` is an enUS name used only if no ID resolves to a name.
-- `notByName`: localized names that must NOT match by name, because a
-- different buff carries the same one (Scroll of Agility and Elixir of
-- Agility are both "Agility"); those spells match by spell ID only.
local function AurasHave(auras, spells, fallback, notByName)
    if not auras then return nil end
    local named = false
    for _, id in ipairs(spells) do
        if auras.ids[id] then return true end
        local n = SpellName(id)
        if n then
            named = true
            if auras.names[n] and not (notByName and notByName[n]) then return true end
        end
    end
    if not named and fallback and auras.names[fallback] then return true end
    return false
end

-- Buffs that are not an item's own spell. Spell IDs are Vanilla's; the
-- localized name of any one rank matches all of them.
local WELL_FED_SPELLS          = { 19705 }
local RECENTLY_BANDAGED_SPELLS = { 11196 }

function Apotheca.HasFoodBuff()
    return AurasHave(ReadAuras("HELPFUL"), WELL_FED_SPELLS, "Well Fed")
end

-- ============================================================
-- XP FOOD (#19)
-- Forever's "Nutritious" food adds 5% kill XP to its Well Fed bonus. The
-- buff is one aura named "Well Fed", like ordinary food, with its own
-- spell ID, so it is recognised by ID only (never by name: the name is
-- shared). DATA.XP_WELL_FED_SPELLS and DATA.WELL_FED_SPELLS come from the
-- client's own spell data (/apo scan3, docs/FOREVER-PROBE.md).
-- ============================================================
local XP_WELL_FED, ORDINARY_WELL_FED = {}, {}
for _, id in ipairs(DATA.XP_WELL_FED_SPELLS or {}) do XP_WELL_FED[id] = true end
for _, id in ipairs(DATA.ORDINARY_WELL_FED_SPELLS or {}) do ORDINARY_WELL_FED[id] = true end

local XP_FOOD_IDS = {}
for _, e in ipairs(DATA.XP_FOOD or {}) do XP_FOOD_IDS[e.id] = true end

-- Every XP food item ID: while the XP Food button offers one, Buff Food
-- leaves all of them to it (UpdateAllButtonsBody).
Apotheca.XP_FOOD_IDS = XP_FOOD_IDS

-- Is the XP Food button in play: switched on, and XP to gain?
function Apotheca.XPFoodEnabled()
    local xp = DB().xpFood
    return (xp and xp.enabled and Apotheca.CanGainXP()) and true or false
end

-- While the player can still gain XP: below the level cap, and XP not
-- turned off (measured on 70009: GetMaxPlayerLevel 60, IsXPUserDisabled).
local function CanGainXPUnprotected()
    return UnitLevel("player") < GetMaxPlayerLevel() and not IsXPUserDisabled()
end
function Apotheca.CanGainXP()
    local ok, can = pcall(CanGainXPUnprotected)
    return ok and can or false
end

-- Is the XP food buff up? true / false, or nil when unknown:
-- - auras unreadable (combat);
-- - a Well Fed aura that is neither XP nor known ordinary: a Forever spell
--   with no text (1283082), or one a later build revealed (Blizzard keeps
--   some data encrypted until it is discovered). Unknown never glows, so
--   such a buff cannot make the button nag.
-- IDs decide first. "Is some other aura a Well Fed?" is by name, in the
-- client's language: every scanned Well Fed spell's name, so it matches as
-- soon as any has loaded, and the English name only if none has.
function Apotheca.HasXPFoodBuff(auras)
    auras = auras or ReadAuras("HELPFUL")
    if not auras then return nil end
    local ordinary = false
    for id in pairs(auras.ids) do
        if XP_WELL_FED[id] then return true end
        if ORDINARY_WELL_FED[id] then ordinary = true end
    end
    if ordinary then return false end
    local named = false
    for _, id in ipairs(DATA.WELL_FED_SPELLS or WELL_FED_SPELLS) do
        local n = SpellName(id)
        if n then
            named = true
            if auras.names[n] then return nil end   -- a Well Fed we don't know
        end
    end
    if not named and auras.names["Well Fed"] then return nil end
    return false
end

-- The XP food to offer: one the player carries and can eat at their level.
-- Every XP food gives the same 5%, so what differs is the Well Fed stat
-- (Codex design consult on #21):
--   1. a stat in the role's buff food priority beats one that isn't (or
--      none: movement speed, fishing, herbalism), whatever the level;
--   2. then the highest required level (a bigger bonus of a wanted stat);
--   3. then the earliest stat in the priority;
--   4. then the bigger value (same stat by then), then the lower item ID.
-- So a level-1 role-stat food beats a level-55 stat-less one: same XP,
-- and a stat the role wants.
function Apotheca.FindBestXPFood(bagMap)
    local level = UnitLevel("player") or 1
    local rank = {}
    -- The first occurrence ranks: the options allow a stat twice.
    for i, stat in ipairs(Apotheca.GetStatPriority() or {}) do
        if not rank[stat] then rank[stat] = i end
    end
    -- A stat category switched off in the Buff Food filters is never offered.
    local categories = DB().categories or PROFILE_DEFAULTS.categories
    local best, bestKey
    for _, e in ipairs(DATA.XP_FOOD or {}) do
        local count = bagMap[e.id]
        if count and count > 0 and e.level <= level
                and not (e.stat and categories[e.stat] == false) then
            local r = e.stat and rank[e.stat]
            local key = { r and 1 or 0, e.level, -(r or 99), e.value, -e.id }
            local better = not best
            if best then
                for i = 1, 5 do
                    if key[i] ~= bestKey[i] then better = key[i] > bestKey[i] break end
                end
            end
            if better then best, bestKey = e, key end
        end
    end
    if not best then return nil, 0, nil end
    return best.id, bagMap[best.id], GetCachedTexture(best.id)
end

-- ============================================================
-- HEALTH CONSUMABLE — healthstone priority over potions
-- ============================================================

-- Picks the healthstone to put on the Healthstone button.
--
-- With smart ranking on, this is the *smallest* stone that still covers
-- the health currently missing, so a big stone is not burned to heal a
-- scratch — all healthstone ranks share one cooldown, so spending the
-- Master stone at 300 missing throws away the whole two minutes. When
-- nothing in the bags covers the deficit (or health is full, or smart
-- ranking is off) the strongest available stone wins.
--
-- The pick can only change out of combat, because swapping it means
-- writing the `item` secure attribute. Entering a fight at or near full
-- health therefore arms the strongest stone, which is the safe default;
-- the smaller-stone pick is what you get between pulls, topping off.
--
-- Returns: itemID, count, texture, healValue, isSmartPick
function Apotheca.FindBestHealthstone(bagMap)
    local best, bestCount           -- strongest stone held
    local pick, pickCount           -- smallest stone that covers the deficit

    local db      = DB()
    local hsDB    = db.healthstone
    local smart   = (not hsDB) or hsDB.smartRank ~= false
    -- Unreadable health (secret in combat) counts as full, which offers
    -- the strongest stone.
    local missing = (Apotheca.API.PlayerMissing()) or 0

    -- List is strongest → weakest, so the first hit is the strongest held
    -- and the last stone that still covers `missing` is the smallest one.
    for _, entry in ipairs(HEALTHSTONE_ITEMS) do
        local count = bagMap[entry.id]
        if count and count > 0 then
            if not best then best, bestCount = entry, count end
            if entry.healValue >= missing then pick, pickCount = entry, count end
        end
    end

    if not best then return nil, 0, nil, nil, false end
    if not smart or missing <= 0 or not pick then
        return best.id, bestCount, GetCachedTexture(best.id), best.healValue, false
    end
    return pick.id, pickCount, GetCachedTexture(pick.id), pick.healValue, pick ~= best
end

function Apotheca.FindBestHealthConsumable(bagMap)
    -- Healthstones are conjured — prefer them over potions, unless the
    -- dedicated Healthstone button is on (it owns them then) or the
    -- player has turned the preference off.
    -- Both tests must read a missing table as enabled, exactly as the
    -- dedicated scan in UpdateAllButtons does. Reading nil as disabled
    -- here would put the same stone on both buttons.
    local db      = DB()
    local hsOwned = (not db.healthstone) or db.healthstone.enabled ~= false
    local prefer  = (not db.health) or db.health.preferHealthstone ~= false
    if prefer and not hsOwned then
        local id, count = Apotheca.FindBestHealthstone(bagMap)
        if id then return id, count, GetCachedTexture(id) end
    end
    -- Fall back to healing potions
    return Apotheca.FindBestPotion("health", HEALTH_ITEMS, bagMap)
end

-- ============================================================
-- SCROLL HELPERS
-- ============================================================

-- Simple highest-first scan from an ordered item list.
-- Scrolls use the same first-match scan as everything else.
Apotheca.FindBestScroll = function(list, bagMap) return Apotheca.FindBestItem(list, bagMap) end

-- A scroll's buff is present: the scroll's own spell, or a buff it does not
-- stack with (Divine Spirit for Spirit, Arcane Intellect for Intellect,
-- Power Word: Fortitude for Stamina). nil = unreadable (combat).
-- Localized names of every elixir and flask buff. A scroll whose buff has
-- one of these names (Agility, Strength, Armor: measured in the scan) is
-- matched by spell ID only, or a running elixir would hide a missing
-- scroll. Built once every name has resolved (names load lazily).
local elixirNames
local function ElixirBuffNames()
    if elixirNames then return elixirNames end
    local names, complete = {}, true
    for _, e in ipairs(DATA.ELIXIR_CATALOG) do
        local n = e.spell and SpellName(e.spell)
        if n then names[n] = true elseif e.spell then complete = false end
    end
    if complete then elixirNames = names end
    return names
end

-- `auras` may be passed in so a caller checking several kinds reads the
-- auras once.
function Apotheca.HasScrollBuff(kind, auras)
    auras = auras or ReadAuras("HELPFUL")
    if not auras then return nil end
    if AurasHave(auras, kind.spells, nil, ElixirBuffNames()) then return true end
    if kind.blockers and AurasHave(auras, kind.blockers, kind.blockerName) then return true end
    return false
end

local function ScrollKind(key)
    for _, k in ipairs(SCROLL_KINDS) do if k.key == key then return k end end
end

function Apotheca.HasSpiritBuff()           return Apotheca.HasScrollBuff(ScrollKind("spiritscroll")) end
function Apotheca.HasProtectionScrollBuff() return Apotheca.HasScrollBuff(ScrollKind("protectionscroll")) end

-- ============================================================
-- WEAPON OIL HELPERS
-- ============================================================

-- Returns true if main hand has any temporary enchant active, false if
-- not, or nil when the client would not say (its combat secrecy is not
-- measured yet, and a secret boolean throws when compared).
-- ============================================================
-- ROGUE POISONS (#24, experimental)
-- ============================================================
local POISON_DEFAULTS = { [16] = "instant", [17] = "deadly" }
-- Weapon subclasses a poison cannot coat: bows, guns, miscellaneous,
-- thrown, crossbows, wands and fishing poles (/code-review of #26).
local NOT_POISONABLE = { [2] = true, [3] = true, [14] = true, [16] = true, [18] = true, [19] = true, [20] = true }

-- Does this hand hold a weapon a coating (poison, oil) can go on?
function Apotheca.CoatableHand(slot)
    local id, sub = Apotheca.API.HandWeapon(slot)
    return id ~= nil and not NOT_POISONABLE[sub]
end
local POISON_KEYS = { none = true }
for _, f in ipairs(DATA.POISON_FAMILIES or {}) do POISON_KEYS[f.key] = true end

-- Per-character, per-hand choices (poisons, stones), saved as
-- <prefix>MH / <prefix>OH: the saved value if it is valid, else the
-- default. Setting one saves only a valid value and asks for an update:
-- the button must change item (Codex review of #24). Not through
-- SetCharSetting, which re-resolves the role for nothing; and a caller's
-- own full update right after satisfies the request (/code-review of #26).
local function HandChoice(prefix, slot, valid, default)
    local v = Apotheca.CharSetting(prefix .. (slot == 17 and "OH" or "MH"), default)
    if not valid[v] then v = default end
    return v
end

local function SetHandChoice(prefix, slot, valid, value)
    if not valid[value] then return end
    ApothecaCharDB = type(ApothecaCharDB) == "table" and ApothecaCharDB or {}
    ApothecaCharDB[prefix .. (slot == 17 and "OH" or "MH")] = value
    Apotheca.RequestUpdate()
end

-- The poison family chosen for a hand (16 / 17): "none" or a family key.
function Apotheca.PoisonChoice(slot)
    return HandChoice("poison", slot, POISON_KEYS, POISON_DEFAULTS[slot])
end

function Apotheca.SetPoisonChoice(slot, family)
    SetHandChoice("poison", slot, POISON_KEYS, family)
end

-- The first entry ({ id, level }) of these lists, in order, that the
-- player carries and can use: its required level, and whatever else the
-- client says (a rune, a class). One loop for the poison, oil and stone
-- finders (/code-review of #33).
local function FirstUsable(lists, bagMap)
    local level = UnitLevel("player") or 1
    for _, list in ipairs(lists) do
        for _, e in ipairs(list) do
            local count = bagMap[e.id]
            if count and count > 0 and e.level <= level
                    and Apotheca.API.ItemUsable(e.id) ~= false then
                return e.id, count, GetCachedTexture(e.id)
            end
        end
    end
    return nil, 0, nil
end

-- The strongest poison of a family the player carries and can use: its
-- required level, and whatever else the client says (a rune the Season of
-- Discovery poisons may need). No other family is ever offered: the wrong
-- poison on a weapon is worse than none.
function Apotheca.FindBestPoison(family, bagMap)
    local list = DATA.POISONS and DATA.POISONS[family]
    if not list then return nil, 0, nil end
    return FirstUsable({ list }, bagMap)
end

-- The oil lists to try, in order, for a weaponOil.kind (#29). "AUTO"
-- follows the role PROFILE (ROLE_PROFILES[...].oil): HEALER mana oil then
-- wizard oil, CASTER wizard oil then mana oil, the others (TANK, MELEE,
-- AGILITY) mana oil only. A Damage-role druid or shaman is CASTER unless
-- their damage style is Physical, as for their food.
local OIL_ORDER = {
    MANA_FIRST   = { MANA_OIL_ITEMS, WIZARD_OIL_ITEMS },
    WIZARD_FIRST = { WIZARD_OIL_ITEMS, MANA_OIL_ITEMS },
    MANA_ONLY    = { MANA_OIL_ITEMS },
}
Apotheca.OIL_KINDS = OIL_ORDER
function Apotheca.OilKind()
    local w = DB().weaponOil
    local kind = w and w.kind or "AUTO"
    if OIL_ORDER[kind] then return kind end
    local oil = Apotheca.GetRoleProfile().oil
    return OIL_ORDER[oil] and oil or "MANA_ONLY"
end

-- The first oil, in the kind's order, that the player carries and can
-- use: its required level, and whatever else the client says. So the
-- fallback to the other kind reaches a usable oil (/code-review of #30).
function Apotheca.FindBestWeaponOil(bagMap)
    return FirstUsable(OIL_ORDER[Apotheca.OilKind()], bagMap)
end

-- ============================================================
-- WEAPON STONES (#32, experimental)
-- ============================================================
-- Which stone a weapon takes, by weapon subclass: an explicit list, not
-- measured in game. Fist weapons get only the "any" stone (Elemental)
-- until tested; any other subclass gets nothing.
local STONE_KIND = {
    [0] = "sharp", [1] = "sharp", [6] = "sharp", [7] = "sharp", [8] = "sharp", [15] = "sharp",
    [4] = "blunt", [5] = "blunt", [10] = "blunt",
    [13] = "fist",
}
local STONE_CHOICES = { none = true, damage = true, elemental = true }

-- "sharp", "blunt", "fist", or nil when the hand holds nothing a stone fits.
function Apotheca.StoneKind(slot)
    local id, sub = Apotheca.API.HandWeapon(slot)
    return id and STONE_KIND[sub] or nil
end

-- The stone choice for a hand (16 / 17), per character: "none" (default),
-- "damage" (a damage stone first) or "elemental" (Elemental first).
function Apotheca.StoneChoice(slot)
    return HandChoice("stone", slot, STONE_CHOICES, "none")
end

function Apotheca.SetStoneChoice(slot, choice)
    SetHandChoice("stone", slot, STONE_CHOICES, choice)
end

-- The stone to offer for a hand: the chosen order, then the other type,
-- among stones that fit the weapon and that the player can use.
function Apotheca.FindBestStone(choice, weaponKind, bagMap)
    local S = DATA.STONES or {}
    local damage = (weaponKind == "sharp" or weaponKind == "blunt") and S[weaponKind] or {}
    local order = choice == "elemental" and { S.any or {}, damage } or { damage, S.any or {} }
    return FirstUsable(order, bagMap)
end

-- Does this stone fit a weapon of this kind? Elemental ("any") fits any
-- melee weapon; a damage stone only its own kind; fist weapons only
-- Elemental (unmeasured).
local STONE_ITEM_KIND = {}
for kind, list in pairs(DATA.STONES or {}) do
    for _, e in ipairs(list) do STONE_ITEM_KIND[e.id] = kind end
end
function Apotheca.StoneFits(itemID, weaponKind)
    local kind = STONE_ITEM_KIND[itemID]
    if not kind or not weaponKind then return false end
    if kind == "any" then return true end
    return kind == weaponKind
end

-- In combat a stone button can't change item, and a secure click can't be
-- stopped either. So after a weapon swap that the stone no longer fits (a
-- sharpening stone and now a mace), the button greys out until the
-- update after combat restores it (/code-review of #33). Recomputed both
-- ways on every swap: swapping back to a weapon the stone fits clears it
-- (Codex review of #33).
function Apotheca.MarkStaleStones()
    for _, cfg in ipairs(STONE_BUTTON_CONFIG) do
        local btn = Apotheca.buttons[cfg.key]
        if btn and btn.itemID and btn:IsShown() then
            btn.icon:SetDesaturated(not Apotheca.StoneFits(btn.itemID, Apotheca.StoneKind(cfg.targetSlot)))
        end
    end
end

-- ============================================================
-- BANDAGE HELPERS
-- ============================================================

-- Pick the best available bandage from bags (highest rank first).
function Apotheca.FindBestBandage(bagMap)
    for _, id in ipairs(BANDAGE_ITEMS) do
        local count = bagMap[id]
        if count and count > 0 then
            return id, count, GetCachedTexture(id)
        end
    end
    return nil, 0, nil
end

-- Returns true if the player has the "Recently Bandaged" debuff,
-- which prevents using another bandage for 60 seconds.
function Apotheca.HasRecentlyBandaged()
    return AurasHave(ReadAuras("HARMFUL"), RECENTLY_BANDAGED_SPELLS, "Recently Bandaged")
end

-- ============================================================
-- ELIXIR BUFF DETECTION
-- Separate flags per slot so the glow can highlight each missing one.
-- ============================================================

-- Every flask, whatever the role: only one flask can be active, so ANY
-- active flask fills the slot.
-- Generated from every flask the client has, including those whose effect
-- is no catalog stat (Chromatic Resistance, Petrification).
local ALL_FLASK_SPELLS = DATA.ALL_FLASK_SPELLS

-- Pick the highest-value item from an elixir list that exists in bagMap,
-- other than `exclude` (an item another slot already took).
local function BestElixirItem(list, bagMap, exclude)
    local bestID, bestVal, bestCount = nil, -1, 0
    for _, entry in ipairs(list) do
        local count = bagMap[entry.id]
        if count and count > 0 and entry.id ~= exclude and entry.value > bestVal then
            bestVal   = entry.value
            bestID    = entry.id
            bestCount = count
        end
    end
    if bestID then
        return bestID, bestCount, GetCachedTexture(bestID)
    end
    return nil, 0, nil
end

-- Resolve which elixir buttons to show.
-- Returns: {
--   mode         = "all" | "none"
--   flaskID, flaskCount, flaskTex
--   battleID, battleCount, battleTex
--   guardianID, guardianCount, guardianTex
--   hasFlask, hasBattle, hasGuardian   (active buff flags)
-- }
-- Has any elixir slot's buff come or gone since the last resolve? Cheap
-- (one aura read), so UNIT_AURA can afford it on every event and only pay
-- for a full update when a slot actually needs re-resolving.
function Apotheca.ElixirBuffStateChanged()
    local last = Apotheca._lastElixRes
    if not last then return true end
    local auras = ReadAuras("HELPFUL")
    if not auras then return false end
    local data = GetPlayerElixirData()
    return AurasHave(auras, ALL_FLASK_SPELLS) ~= last.hasFlask
        or AurasHave(auras, data.battleSpells) ~= last.hasBattle
        or AurasHave(auras, data.guardianSpells) ~= last.hasGuardian
end

function Apotheca.ResolveElixirs(bagMap)
    local result = {
        mode        = "none",
        flaskID     = nil, flaskCount   = 0, flaskTex    = nil,
        battleID    = nil, battleCount  = 0, battleTex   = nil,
        guardianID  = nil, guardianCount = 0, guardianTex = nil,
        hasFlask    = false, hasBattle  = false, hasGuardian = false,
    }

    local db = DB()
    if db.elixirs and db.elixirs.enabled == false then return result end
    local data = GetPlayerElixirData()

    -- One aura read for all three slots. Unreadable: an unknown buff is not
    -- a missing one, so keep the last known answer rather than offering a
    -- flask that may already be running.
    local auras = ReadAuras("HELPFUL")
    if not auras then return Apotheca._lastElixRes or result end
    result.hasFlask    = AurasHave(auras, ALL_FLASK_SPELLS)
    result.hasBattle   = AurasHave(auras, data.battleSpells)
    result.hasGuardian = AurasHave(auras, data.guardianSpells)

    -- Forever has no battle/guardian limit: a flask and elixirs stack, so
    -- every slot is offered on its own. An item that fits both elixir
    -- slots goes to the first one only. A slot whose buff is already
    -- running offers nothing: a flask lasts two hours, and a second click
    -- would only spend another one to refresh it.
    local fID, fCnt, fTex = BestElixirItem(data.flask,   bagMap)
    local bID, bCnt, bTex = BestElixirItem(data.battle,  bagMap)
    local gID, gCnt, gTex = BestElixirItem(data.guardian, bagMap, bID)
    if result.hasFlask    then fID, fCnt, fTex = nil, 0, nil end
    if result.hasBattle   then bID, bCnt, bTex = nil, 0, nil end
    if result.hasGuardian then gID, gCnt, gTex = nil, 0, nil end
    result.flaskID    = fID ; result.flaskCount    = fCnt ; result.flaskTex    = fTex
    result.battleID   = bID ; result.battleCount   = bCnt ; result.battleTex   = bTex
    result.guardianID = gID ; result.guardianCount = gCnt ; result.guardianTex = gTex
    if fID or bID or gID then result.mode = "all" end

    return result
end

-- ============================================================
-- RECOVERY RESOLUTION
-- ============================================================

Apotheca.waterSmartMode = true
Apotheca.hideWhenFull   = false

local function ResolveRecovery(bagMap)
    local result = {
        mode = "split",
        conjuredID = nil, conjuredCount = 0, conjuredTexture = nil,
        foodID     = nil, foodCount     = 0, foodTexture     = nil,
        drinkID    = nil, drinkCount    = 0, drinkTexture    = nil,
        -- Alternate items for right-click
        foodAltID  = nil, foodAltCount  = 0, foodAltTexture  = nil,
        drinkAltID = nil, drinkAltCount = 0, drinkAltTexture = nil,
        -- True if the selected food also restores mana
        foodRestoresMana = false,
    }

    local conjID, conjCount, conjTex = Apotheca.FindBestItem(CONJURED_ITEMS, bagMap)
    if conjID then
        result.mode           = "conjured"
        result.conjuredID     = conjID
        result.conjuredCount  = conjCount
        result.conjuredTexture = conjTex
        return result
    end

    local debug   = DB().debug
    local missHP, missMana = Apotheca.API.PlayerMissing()
    -- Unknown (nil) shows the button: hiding it needs proof it is full.
    local showFood  = (not Apotheca.hideWhenFull) or debug
                      or missHP == nil or missHP > 0
    local showDrink = (not Apotheca.hideWhenFull) or debug
                      or missMana == nil or missMana > 0

    if showFood then
        local id, cnt, tex, aID, aCnt, aTex, restoresMana = Apotheca.FindBestFood(bagMap, 0)
        result.foodID  = id  ; result.foodCount  = cnt  ; result.foodTexture  = tex
        result.foodAltID = aID ; result.foodAltCount = aCnt ; result.foodAltTexture = aTex
        result.foodRestoresMana = restoresMana or false
    end

    if showDrink then
        local id, cnt, tex, aID, aCnt, aTex, restoresHealth = Apotheca.FindBestDrink(bagMap)
        result.drinkID  = id  ; result.drinkCount  = cnt  ; result.drinkTexture  = tex
        result.drinkAltID = aID ; result.drinkAltCount = aCnt ; result.drinkAltTexture = aTex
        result.drinkRestoresHealth = restoresHealth or false
    end

    return result
end

-- ============================================================
-- POSITION
-- ============================================================

local function SavePosition()
    -- Always store the BOTTOMLEFT corner so the bar grows rightward on resize.
    -- GetLeft/GetBottom return screen coordinates we can convert to UIParent offsets.
    local left   = ApothecaFrame:GetLeft()
    local bottom = ApothecaFrame:GetBottom()
    ApothecaCharDB         = ApothecaCharDB or {}
    ApothecaCharDB.point   = "BOTTOMLEFT"
    ApothecaCharDB.x       = left   or 0
    ApothecaCharDB.y       = bottom or 200
end

local function RestorePosition()
    local db = ApothecaCharDB
    ApothecaFrame:ClearAllPoints()
    if db and db.point and db.x and db.y then
        -- Migrate old BOTTOM-anchored saves to BOTTOMLEFT
        local point = (db.point == "BOTTOM") and "BOTTOMLEFT" or db.point
        if point == "BOTTOMLEFT" then
            ApothecaFrame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", db.x, db.y)
        else
            ApothecaFrame:SetPoint(point, UIParent, point, db.x, db.y)
        end
    else
        ApothecaFrame:SetPoint(DEFAULT_POS.point, UIParent, DEFAULT_POS.point,
                               DEFAULT_POS.x, DEFAULT_POS.y)
    end
end

-- ============================================================
-- GLOW SYSTEM (LibButtonGlow-1.0 port)
-- ============================================================

local glowPool = {}
local numGlows = 0

local function GlowAnimOutFinished(ag)
    local o = ag:GetParent()
    local f = o:GetParent()
    o:Hide()
    glowPool[#glowPool + 1] = o
    f.__apothecaGlow = nil
end

local function GlowOnHide(self)
    if self.animOut:IsPlaying() then
        self.animOut:Stop()
        GlowAnimOutFinished(self.animOut)
    end
end

local function GlowOnUpdate(self, elapsed)
    if AnimateTexCoords then
        AnimateTexCoords(self.ants, 256, 256, 48, 48, 22, elapsed, 0.01)
    end
    self:SetAlpha(1.0)
end

local function MakeScaleAnim(group, target, order, dur, x, y, delay)
    local a = group:CreateAnimation("Scale")
    a:SetTarget(target)
    a:SetOrder(order)
    a:SetDuration(dur)
    a:SetScale(x, y)
    if delay then a:SetStartDelay(delay) end
end

local function MakeAlphaAnim(group, target, order, dur, from, to, delay)
    local a = group:CreateAnimation("Alpha")
    a:SetTarget(target)
    a:SetOrder(order)
    a:SetDuration(dur)
    a:SetFromAlpha(from)
    a:SetToAlpha(to)
    if delay then a:SetStartDelay(delay) end
end

local ICON_ALERT      = "Interface\\SpellActivationOverlay\\IconAlert"
local ICON_ALERT_ANTS = "Interface\\SpellActivationOverlay\\IconAlertAnts"

local function CreateGlowOverlay()
    numGlows = numGlows + 1
    local o = CreateFrame("Frame", "ApothecaGlow" .. numGlows, UIParent)

    local function MakeTex(layer, l, r, t, b)
        local tx = o:CreateTexture(nil, layer)
        tx:SetPoint("CENTER")
        tx:SetAlpha(0)
        tx:SetTexture(ICON_ALERT)
        tx:SetTexCoord(l, r, t, b)
        return tx
    end

    o.spark         = MakeTex("BACKGROUND", 0.00781, 0.61719, 0.00391, 0.26953)
    o.innerGlow     = MakeTex("ARTWORK",    0.00781, 0.50781, 0.27734, 0.52734)
    o.outerGlow     = MakeTex("ARTWORK",    0.00781, 0.50781, 0.27734, 0.52734)

    o.innerGlowOver = o:CreateTexture(nil, "ARTWORK")
    o.innerGlowOver:SetPoint("TOPLEFT",     o.innerGlow, "TOPLEFT")
    o.innerGlowOver:SetPoint("BOTTOMRIGHT", o.innerGlow, "BOTTOMRIGHT")
    o.innerGlowOver:SetAlpha(0)
    o.innerGlowOver:SetTexture(ICON_ALERT)
    o.innerGlowOver:SetTexCoord(0.00781, 0.50781, 0.53516, 0.78516)

    o.outerGlowOver = o:CreateTexture(nil, "ARTWORK")
    o.outerGlowOver:SetPoint("TOPLEFT",     o.outerGlow, "TOPLEFT")
    o.outerGlowOver:SetPoint("BOTTOMRIGHT", o.outerGlow, "BOTTOMRIGHT")
    o.outerGlowOver:SetAlpha(0)
    o.outerGlowOver:SetTexture(ICON_ALERT)
    o.outerGlowOver:SetTexCoord(0.00781, 0.50781, 0.53516, 0.78516)

    o.ants = o:CreateTexture(nil, "OVERLAY")
    o.ants:SetPoint("CENTER")
    o.ants:SetAlpha(0)
    o.ants:SetTexture(ICON_ALERT_ANTS)
    -- AnimateTexCoords is absent on Forever. Without it the texture would
    -- show the whole 256x256 flipbook sheet, so pin it to the first frame.
    if not AnimateTexCoords then o.ants:SetTexCoord(0, 48/256, 0, 48/256) end

    -- animIn
    o.animIn = o:CreateAnimationGroup()
    MakeScaleAnim(o.animIn, o.spark,         1, 0.2, 1.5, 1.5)
    MakeAlphaAnim(o.animIn, o.spark,         1, 0.2, 0, 1)
    MakeScaleAnim(o.animIn, o.innerGlow,     1, 0.3, 2, 2)
    MakeScaleAnim(o.animIn, o.innerGlowOver, 1, 0.3, 2, 2)
    MakeAlphaAnim(o.animIn, o.innerGlowOver, 1, 0.3, 1, 0)
    MakeScaleAnim(o.animIn, o.outerGlow,     1, 0.3, 0.5, 0.5)
    MakeScaleAnim(o.animIn, o.outerGlowOver, 1, 0.3, 0.5, 0.5)
    MakeAlphaAnim(o.animIn, o.outerGlowOver, 1, 0.3, 1, 0)
    MakeScaleAnim(o.animIn, o.spark,         1, 0.2, 0.667, 0.667, 0.2)
    MakeAlphaAnim(o.animIn, o.spark,         1, 0.2, 1, 0, 0.2)
    MakeAlphaAnim(o.animIn, o.innerGlow,     1, 0.2, 1, 0, 0.3)
    MakeAlphaAnim(o.animIn, o.ants,          1, 0.2, 0, 1, 0.3)
    o.animIn:SetScript("OnPlay", function(ag)
        local f = ag:GetParent()
        local w, h = f:GetSize()
        f.spark:SetSize(w, h)          ; f.spark:SetAlpha(0.3)
        f.innerGlow:SetSize(w/2, h/2)  ; f.innerGlow:SetAlpha(1)
        f.innerGlowOver:SetAlpha(1)
        f.outerGlow:SetSize(w*2, h*2)  ; f.outerGlow:SetAlpha(1)
        f.outerGlowOver:SetAlpha(1)
        f.ants:SetSize(w*0.85, h*0.85) ; f.ants:SetAlpha(0)
        f:Show()
    end)
    o.animIn:SetScript("OnFinished", function(ag)
        local f = ag:GetParent()
        local w, h = f:GetSize()
        f.spark:SetAlpha(0)
        f.innerGlow:SetAlpha(0)        ; f.innerGlow:SetSize(w, h)
        f.innerGlowOver:SetAlpha(0)
        f.outerGlow:SetSize(w, h)
        f.outerGlowOver:SetAlpha(0)    ; f.outerGlowOver:SetSize(w, h)
        f.ants:SetAlpha(1)
    end)

    -- animOut
    o.animOut = o:CreateAnimationGroup()
    MakeAlphaAnim(o.animOut, o.outerGlowOver, 1, 0.2, 0, 1)
    MakeAlphaAnim(o.animOut, o.ants,          1, 0.2, 1, 0)
    MakeAlphaAnim(o.animOut, o.outerGlowOver, 2, 0.2, 1, 0)
    MakeAlphaAnim(o.animOut, o.outerGlow,     2, 0.2, 1, 0)
    o.animOut:SetScript("OnFinished", GlowAnimOutFinished)

    o:SetScript("OnUpdate", GlowOnUpdate)
    o:SetScript("OnHide",   GlowOnHide)
    return o
end

local function GetGlowOverlay()
    if #glowPool > 0 then return table.remove(glowPool) end
    return CreateGlowOverlay()
end

-- Generic glow show/hide — works on any button frame.
local function ShowGlow(btn)
    if not btn then return end
    if btn.__apothecaGlow then
        if btn.__apothecaGlow.animOut:IsPlaying() then
            btn.__apothecaGlow.animOut:Stop()
            btn.__apothecaGlow.animIn:Play()
        end
        return
    end
    local w, h = btn:GetSize()
    local o    = GetGlowOverlay()
    o:SetParent(btn)
    o:SetFrameLevel(btn:GetFrameLevel() + 5)
    o:ClearAllPoints()
    o:SetSize(w * 1.4, h * 1.4)
    o:SetPoint("TOPLEFT",     btn, "TOPLEFT",     -w * 0.2,  h * 0.2)
    o:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT",  w * 0.2, -h * 0.2)
    o.animIn:Play()
    btn.__apothecaGlow = o
end

local function HideGlow(btn)
    if not btn or not btn.__apothecaGlow then return end
    if btn.__apothecaGlow.animIn:IsPlaying() then
        btn.__apothecaGlow.animIn:Stop()
    end
    if btn:IsVisible() then
        btn.__apothecaGlow.animOut:Play()
    else
        GlowAnimOutFinished(btn.__apothecaGlow.animOut)
    end
end

local function ShowBuffFoodGlow()
    ShowGlow(Apotheca.buttons["bufffood"])
end

local function HideBuffFoodGlow()
    HideGlow(Apotheca.buttons["bufffood"])
end

local readyCheckActive = false

-- The after-combat reminder window, shared by every button that reminds
-- (XP food, poisons): armed on leaving combat, started after the
-- post-combat update (UpdateAllButtonsBody), cleared on entering combat.
--
-- XP food glow: ONE function decides, for both reasons it can glow (Codex
-- review of #19): a ready check, or the reminder for a few seconds after
-- combat. Recomputed from state on every call, so a stale timer or event
-- can never hide a glow another reason still wants. Only a button on the
-- bar with an item, and only when the XP buff is confirmed missing.
local REMIND_SECONDS = 5
local remindUntil     = 0
local remindPending   = false

local function XPFoodGlowWanted()
    local btn = Apotheca.buttons["xpfood"]
    if not btn then return false end
    local reason = readyCheckActive or GetTime() < remindUntil
    -- Not while dead: dying ends combat too, and a ghost cannot eat.
    return (reason and btn.itemID and btn:IsShown() and not InCombatLockdown()
            and not UnitIsDeadOrGhost("player")
            and Apotheca.HasXPFoodBuff() == false) and true or false
end

local function UpdateXPFoodGlow()
    local btn = Apotheca.buttons["xpfood"]
    if not btn then return end
    if XPFoodGlowWanted() then ShowGlow(btn) else HideGlow(btn) end
end

-- Poison and stone glows (#24, #32): the same one-decision pattern, per
-- hand, with each group's own settings (db.poisons / db.stones). A ready
-- check (glowOnMissingBuff) or the after-combat reminder window (opt-in,
-- `remind`), for a button on the bar with an item, while that hand is
-- confirmed to carry no coating at all. Any coating counts as covered:
-- which poison is on is not measured yet.
local function CoatingGlowWanted(btn)
    local p = DB()[btn.cfg.group] or {}
    local reason = (readyCheckActive and p.glowOnMissingBuff ~= false)
                   or (p.remind and GetTime() < remindUntil)
    return (reason and btn.itemID and btn:IsShown() and not InCombatLockdown()
            and not UnitIsDeadOrGhost("player")
            and Apotheca.API.HandCoated(btn.cfg.targetSlot) == false) and true or false
end

local function UpdateCoatingGlow()
    for _, cfg in ipairs(COATING_BUTTON_CONFIG) do
        local btn = Apotheca.buttons[cfg.key]
        if btn then
            if CoatingGlowWanted(btn) then ShowGlow(btn) else HideGlow(btn) end
        end
    end
end


local function UpdateBuffFoodGlow()
    local btn = Apotheca.buttons["bufffood"]
    if not btn then return end
    local db  = DB()
    local glowEnabled = db.buffFood and db.buffFood.glowOnMissingBuff
    -- Only a button on the bar (a hidden one keeps its last itemID). And not
    -- while XP Food asks to be eaten: Well Fed doesn't stack, so two glows
    -- would read as "eat both" when the second replaces the first.
    if readyCheckActive and glowEnabled and btn.itemID and btn:IsShown()
            and not XPFoodGlowWanted() and Apotheca.HasFoodBuff() == false then
        ShowBuffFoodGlow()
    else
        HideBuffFoodGlow()
    end
end

-- Glow elixir buttons during a ready check if their buff is missing.
-- elixRes is the result table from Apotheca.ResolveElixirs().
local function UpdateElixirGlow(elixRes)
    if not readyCheckActive or not elixRes then
        HideGlow(Apotheca.buttons["flask"])
        HideGlow(Apotheca.buttons["battle"])
        HideGlow(Apotheca.buttons["guardian"])
        return
    end

    -- Each slot glows on its own: an item is in the bags and its buff is
    -- confirmed missing (unknown does not glow).
    for _, slot in ipairs({ { "flask", "flaskID", "hasFlask" },
                            { "battle", "battleID", "hasBattle" },
                            { "guardian", "guardianID", "hasGuardian" } }) do
        local btn = Apotheca.buttons[slot[1]]
        if elixRes[slot[2]] and elixRes[slot[3]] == false then ShowGlow(btn) else HideGlow(btn) end
    end
end

local function UpdateScrollGlow()
    local db = DB()
    local glowEnabled = db.scrolls and db.scrolls.glowOnMissingBuff
    -- One aura read for every kind; only buttons on the bar can glow (a
    -- kind the role does not want keeps a stale itemID while hidden).
    local auras = readyCheckActive and glowEnabled and ReadAuras("HELPFUL") or nil
    for _, kind in ipairs(SCROLL_KINDS) do
        local btn = Apotheca.buttons[kind.key]
        if btn then
            if auras and btn.itemID and btn:IsShown() and Apotheca.HasScrollBuff(kind, auras) == false then
                ShowGlow(btn)
            else
                HideGlow(btn)
            end
        end
    end
end

local function UpdateWeaponOilGlow()
    local db  = DB()
    local btn = Apotheca.buttons["weaponoil"]
    if not btn then return end
    local glowEnabled = db.weaponOil and db.weaponOil.glowOnMissingBuff
    if readyCheckActive and glowEnabled and btn.itemID and btn:IsShown()
            and Apotheca.API.HandCoated(16) == false then
        ShowGlow(btn)
    else
        HideGlow(btn)
    end
end

-- Lightweight bandage debuff check called from UNIT_AURA.
-- Toggles the button without a full UpdateAllButtons pass.
local function UpdateBandageUsability()
    local btn = Apotheca.buttons["bandage"]
    if not btn or not btn.itemID then return end
    if InCombatLockdown() then return end
    local db = DB()
    if db.debug then return end

    if Apotheca.HasRecentlyBandaged() then
        btn:SetAttribute("type", nil)
        btn:SetAttribute("item", nil)
        btn.icon:SetDesaturated(true)
    else
        -- Re-enable if the debuff just fell off
        Apotheca.ApplySecureItemAttributes(btn, btn.itemID)
        btn.icon:SetDesaturated(false)
    end
end

local function CalcFrameWidth(n)
    return FRAME_PADDING * 2 + n * BUTTON_SIZE + (n - 1) * BUTTON_GAP
end

-- Resize and reposition all active buttons according to orientation and rows.
-- UI-Quickslot2 has a wide transparent margin: Blizzard's ActionButtonTemplate
-- draws it at 66x66 around a 36x36 button, one pixel low. Scale that with the
-- icon size so the frame sits on the icon's edge at any size.
local function SizeButtonBorder(btn, size)
    local border = btn.btnBorder
    if not border then return end
    border:ClearAllPoints()
    border:SetSize(size * 66 / 36, size * 66 / 36)
    border:SetPoint("CENTER", btn, "CENTER", 0, -size / 36)
end

-- The layout the bar uses: its own settings, with the chosen action bar's
-- icon size and padding while matchBar names one and the client reports
-- them. The second return says whether they did, for the options panel.
function Apotheca.LayoutSettings()
    local db = DB()
    local layout = {
        orientation = db.orientation, rows = db.rows,
        iconSize = db.iconSize, iconPadding = db.iconPadding,
    }
    if (tonumber(db.matchBar) or 0) > 0 then
        local bar = Apotheca.API.ActionBarLayout(tonumber(db.matchBar))
        if bar then
            layout.iconSize, layout.iconPadding = bar.size, bar.padding
            return layout, true
        end
    end
    return layout, false
end

-- What the layout was built from, to notice the matched action bar changing.
local function LayoutSignature(l)
    return string.format("%s/%s/%.2f/%.2f", tostring(l.orientation), tostring(l.rows),
        l.iconSize or 0, l.iconPadding or 0)
end

-- Horizontal: buttons flow left→right, wrap into rows.
-- Vertical:   buttons flow top→bottom, wrap into columns.
local function ApplyLayout(active)
    local layout      = Apotheca.LayoutSettings()
    Apotheca._layoutSig = LayoutSignature(layout)
    local orientation = layout.orientation or "HORIZONTAL"
    local rows        = math.max(1, layout.rows or 1)
    local btnSize     = math.max(16, layout.iconSize    or BUTTON_SIZE)
    local btnGap      = math.max(0,  layout.iconPadding or BUTTON_GAP)
    local n           = #active

    if n == 0 then
        ApothecaFrame:SetWidth(FRAME_PADDING * 2 + btnSize)
        ApothecaFrame:SetHeight(FRAME_PADDING * 2 + btnSize)
        return
    end

    local cols
    if orientation == "VERTICAL" then
        cols = rows
        rows = math.ceil(n / cols)
    else
        cols = math.ceil(n / rows)
    end

    local frameW = FRAME_PADDING * 2 + cols * btnSize + (cols - 1) * btnGap
    local frameH = FRAME_PADDING * 2 + rows * btnSize + (rows - 1) * btnGap
    ApothecaFrame:SetWidth(frameW)
    ApothecaFrame:SetHeight(frameH)

    for i, key in ipairs(active) do
        local btn  = Apotheca.buttons[key]
        local idx  = i - 1
        local col  = idx % cols
        local row  = math.floor(idx / cols)
        local x    = FRAME_PADDING + col * (btnSize + btnGap)
        local y    = -(FRAME_PADDING + row * (btnSize + btnGap))
        btn:SetWidth(btnSize)
        btn:SetHeight(btnSize)
        SizeButtonBorder(btn, btnSize)
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", ApothecaFrame, "TOPLEFT", x, y)
        btn:Show()
    end
end

local ApothecaFrame = CreateFrame("Frame", "ApothecaFrame", UIParent)
ApothecaFrame:SetWidth(CalcFrameWidth(5))
ApothecaFrame:SetHeight(FRAME_PADDING * 2 + BUTTON_SIZE)
ApothecaFrame:SetPoint(DEFAULT_POS.point, UIParent, DEFAULT_POS.point, DEFAULT_POS.x, DEFAULT_POS.y)
ApothecaFrame:SetMovable(true)
ApothecaFrame:SetClampedToScreen(true)
ApothecaFrame:SetFrameStrata("MEDIUM")
ApothecaFrame:EnableMouse(true)  -- catch clicks on frame padding

local debugLabel = ApothecaFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
debugLabel:SetPoint("BOTTOMLEFT", ApothecaFrame, "TOPLEFT", 0, 2)
debugLabel:SetText("|cffff6600[DEBUG]|r")
debugLabel:Hide()
Apotheca.debugLabel = debugLabel

-- ============================================================
-- DRAG ANCHOR  (alt-activated overlay)
-- A transparent overlay at HIGH strata sits above secure buttons
-- when Alt is held and the mouse is over the bar, intercepting mouse events for drag-to-move.
-- When Alt is released the anchor hides and buttons work normally.
-- ============================================================

local anchor = CreateFrame("Frame", "ApothecaAnchor", ApothecaFrame)
anchor:SetAllPoints(ApothecaFrame)
anchor:SetFrameStrata("DIALOG")
anchor:EnableMouse(true)
anchor:RegisterForDrag("LeftButton")
anchor:Hide()

local anchorBg = anchor:CreateTexture(nil, "BACKGROUND")
anchorBg:SetAllPoints()
anchorBg:SetColorTexture(0.40, 0.27, 0.66, 0.55)

local anchorText = anchor:CreateFontString(nil, "OVERLAY", "GameFontNormal")
anchorText:SetPoint("CENTER")
anchorText:SetTextColor(1, 1, 1, 0.9)
anchorText:SetText("Drag to move")

local anchorDragging = false

-- The overlay state is derived from the *live* input state, never from a
-- single MODIFIER_STATE_CHANGED edge. A missed key-up (alt-tab, a popup
-- taking focus, a click swallowed mid-channel) used to leave the overlay
-- stuck on, so the bar looked like it unlocked itself for a while.
local function AnchorShouldShow()
    return IsAltKeyDown()
       and not InCombatLockdown()
       and not DB().lockPosition
       and ApothecaFrame:IsVisible()
       and ApothecaFrame:IsMouseOver()
end

local function StopAnchorDrag()
    ApothecaFrame:StopMovingOrSizing()
    SavePosition()
    anchorDragging = false
end

local function UpdateAnchorState()
    if anchorDragging then
        -- Mid-drag: only alt release, combat, or a lock ends the drag.
        if not IsAltKeyDown() or InCombatLockdown() or DB().lockPosition then
            StopAnchorDrag()
            anchor:Hide()
        end
        return
    end

    if AnchorShouldShow() then
        if not anchor:IsShown() then anchor:Show() end
    elseif anchor:IsShown() then
        anchor:Hide()
    end
end

anchor:SetScript("OnDragStart", function()
    if not InCombatLockdown() and not DB().lockPosition then
        ApothecaFrame:StartMoving()
        anchorDragging = true
    end
end)
anchor:SetScript("OnDragStop", function()
    if anchorDragging then StopAnchorDrag() end
    UpdateAnchorState()
end)
anchor:SetScript("OnMouseDown", function(self, button)
    -- Swallow clicks so they don't reach secure buttons below
end)
anchor:SetScript("OnHide", function()
    -- Safety net: never leave the frame attached to the cursor.
    if anchorDragging then StopAnchorDrag() end
end)

local modFrame = CreateFrame("Frame")
Apotheca.API.RegisterEvents(modFrame, "MODIFIER_STATE_CHANGED", "PLAYER_REGEN_DISABLED")
modFrame:SetScript("OnEvent", function(_, event, key)
    if event == "MODIFIER_STATE_CHANGED" and key ~= "LALT" and key ~= "RALT" then
        return
    end
    UpdateAnchorState()
end)

-- Poll as well, so the overlay self-corrects within a frame or two even if
-- the matching key event never arrives.
local anchorElapsed = 0
modFrame:SetScript("OnUpdate", function(_, elapsed)
    if not (anchor:IsShown() or anchorDragging or IsAltKeyDown()) then return end
    anchorElapsed = anchorElapsed + elapsed
    if anchorElapsed < 0.1 then return end
    anchorElapsed = 0
    UpdateAnchorState()
end)

-- ============================================================
-- SECURE ATTRIBUTE MANAGEMENT
-- All writes to btn "type"/"item" attributes go through this
-- single function. Never write them directly anywhere else.
-- ============================================================

function Apotheca.ApplySecureItemAttributes(btn, itemID)
    if InCombatLockdown() then return end
    -- A button aimed at a weapon hand (poisons) also carries target-slot;
    -- cleared with the item on every other path, so no stale target is
    -- left behind (Codex review of #24).
    local cfg = btn.cfg or {}
    local slot = cfg.targetSlot
    -- Only a hand that can take a coating gets a target; otherwise the
    -- click leaves the cursor for the player, as without a target.
    if slot and not Apotheca.CoatableHand(slot) then slot = nil end
    local key = cfg.leftClickOnly and "target-slot1" or "target-slot"
    btn:SetAttribute("target-slot", nil)
    btn:SetAttribute("target-slot1", nil)
    if DB().debug or not itemID then
        btn:SetAttribute("type", nil)
        btn:SetAttribute("item", nil)
        return
    end
    btn:SetAttribute("type", "item")
    btn:SetAttribute("item", "item:" .. itemID)
    if slot then btn:SetAttribute(key, slot) end
end

local function ApplyDebugAttributes(btn)
    -- Delegates entirely to the centralized helper using the button's current itemID.
    Apotheca.ApplySecureItemAttributes(btn, btn.itemID)
end

local function CreateApothecaButton(cfg)
    local btn = CreateFrame("Button", "ApothecaButton_" .. cfg.key, ApothecaFrame, "SecureActionButtonTemplate")
    btn:SetWidth(BUTTON_SIZE)
    btn:SetHeight(BUTTON_SIZE)
    -- Register BOTH mouse edges. The client's SecureActionButton_OnClick
    -- acts only on the edge where down == useOnKeyDown (the attribute, else
    -- the ActionButtonUseKeyDown CVar), so one click uses the item once
    -- (measured on Forever). A single edge is a dead button for anyone on
    -- the other CVar setting. Never set "typerelease": the press-and-hold
    -- release path reads it and would use the item a second time.
    btn:RegisterForClicks(Apotheca.API.ClickEdges())
    -- Do NOT RegisterForDrag on secure buttons — that taints them.
    -- Do NOT SetScript("OnDragStart/Stop") on secure buttons — that taints them.
    -- Do NOT HookScript("OnClick") on secure buttons — that taints them.
    -- Dragging is handled on ApothecaFrame itself (see below).

    local emptyBg = btn:CreateTexture(nil, "BACKGROUND")
    emptyBg:SetAllPoints(btn)
    emptyBg:SetTexture("Interface\\Buttons\\UI-Quickslot2")
    emptyBg:SetTexCoord(0.1, 0.9, 0.1, 0.9)
    emptyBg:SetAlpha(0.6)
    btn.emptyBg = emptyBg

    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(btn)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    btn.icon = icon

    -- The same bronze frame as the client's own action buttons. Not
    -- UI-Quickslot-Depress: that is the gold pushed state, shown on press.
    local border = btn:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Buttons\\UI-Quickslot2")
    btn.btnBorder = border
    SizeButtonBorder(btn, BUTTON_SIZE)
    btn:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")

    local hl = btn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
    hl:SetBlendMode("ADD")
    hl:SetAllPoints(btn)
    btn:SetHighlightTexture(hl)

    local ct = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    ct:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 2)
    btn.countText = ct

    local cd = CreateFrame("Cooldown", "ApothecaCD_" .. cfg.key, btn, "CooldownFrameTemplate")
    cd:SetAllPoints(btn)
    cd:SetDrawEdge(true)
    cd:SetReverse(false)
    btn.cooldown = cd

    -- OnEnter/OnLeave are safe on secure buttons (they are not restricted).
    btn:SetScript("OnEnter", function(self)
        if self.itemID then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetItemByID(self.itemID)
            if DB().debug then
                GameTooltip:AddLine("|cffff6600[Debug: will not consume]|r", 1, 1, 1, true)
                local name = GetItemInfo(self.itemID) or ("id:" .. self.itemID)
                GameTooltip:AddLine("|cff9966ffWould use:|r " .. name, 1, 1, 1, true)
            end
            -- Explain the smart-rank healthstone pick, so a player who
            -- expects the Master stone can see why a smaller one is up.
            if self._healValue then
                GameTooltip:AddLine(" ", 1, 1, 1, false)
                GameTooltip:AddLine("|cff9966ffRestores:|r " .. self._healValue .. " health",
                    0.7, 0.7, 0.9, true)
                if self._smartRankPick then
                    GameTooltip:AddLine("|cff888888Smallest stone that covers your missing health.|r",
                        0.6, 0.6, 0.6, true)
                end
            end

            -- Explain a waste-blocked button. Without this the only clue
            -- that the click will do nothing is a desaturated icon.
            if self._wasteBlocked then
                local mode = DB().preventWasteMode or "BLOCK"
                GameTooltip:AddLine(" ", 1, 1, 1, false)
                GameTooltip:AddLine("|cffff6600Waste prevention:|r you are at full "
                    .. (self._wasteResource or "health/mana") .. ".", 1, 0.6, 0.2, true)
                GameTooltip:AddLine(mode == "BLOCK"
                    and "|cff888888Clicking does nothing. Change Prevent waste in /apo.|r"
                    or  "|cff888888Click to confirm using it anyway.|r", 0.6, 0.6, 0.6, true)
            end
            -- Show alternate item hint if right-click alternate is enabled
            local rcMode = DB().rightClickAlternate or "OFF"
            if rcMode ~= "OFF" and self._alternateItemID then
                local altName = GetItemInfo(self._alternateItemID) or ("id:" .. self._alternateItemID)
                GameTooltip:AddLine(" ", 1, 1, 1, false)
                GameTooltip:AddLine("|cff9966ffRight-click:|r " .. altName, 0.7, 0.7, 0.9, true)
            end
            GameTooltip:Show()
        elseif DB().showEmptyButtons then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            local tip = cfg.emptyTooltip
                        or ("|cff9966ffApotheca|r — " .. cfg.label .. "\n|cff888888Nothing in bags|r")
            GameTooltip:SetText(tip, 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    btn.cfg    = cfg
    btn.itemID = nil
    ApplyDebugAttributes(btn)
    return btn
end

Apotheca.buttons = {}
for _, cfg in ipairs(STATIC_BUTTON_CONFIG) do
    Apotheca.buttons[cfg.key] = CreateApothecaButton(cfg)
end
for _, cfg in ipairs(RECOVERY_BUTTON_CONFIG) do
    Apotheca.buttons[cfg.key] = CreateApothecaButton(cfg)
end
for _, cfg in ipairs(ELIXIR_BUTTON_CONFIG) do
    Apotheca.buttons[cfg.key] = CreateApothecaButton(cfg)
end
for _, cfg in ipairs(SCROLL_BUTTON_CONFIG) do
    Apotheca.buttons[cfg.key] = CreateApothecaButton(cfg)
end
do
    local cfg = MANAGEM_BUTTON_CONFIG
    Apotheca.buttons[cfg.key] = CreateApothecaButton(cfg)
end
Apotheca.buttons["bufffood"]    = CreateApothecaButton(BUFFFOOD_BUTTON_CONFIG)
Apotheca.buttons["xpfood"]      = CreateApothecaButton(XPFOOD_BUTTON_CONFIG)
Apotheca.buttons["weaponoil"]   = CreateApothecaButton(WEAPONOIL_BUTTON_CONFIG)
for _, cfg in ipairs(COATING_BUTTON_CONFIG) do
    Apotheca.buttons[cfg.key] = CreateApothecaButton(cfg)
end
Apotheca.buttons["bandage"]     = CreateApothecaButton(BANDAGE_BUTTON_CONFIG)
Apotheca.buttons["healthstone"] = CreateApothecaButton(HEALTHSTONE_BUTTON_CONFIG)

-- ============================================================
-- WASTE PREVENTION & RIGHT-CLICK ALTERNATE — BYPASS SYSTEM
-- Standard StaticPopup dialogs. On "Yes" they set a temporary
-- bypass so the NEXT click on the real SecureActionButton works.
-- This avoids trying to use items from popup callbacks (which
-- doesn't work in Classic TBC).
-- ============================================================

-- Per-button bypass flags. When set, waste prevention skips that button.
-- Cleared after 5 seconds or on the next UpdateAllButtons cycle.
local wasteBypass = {}   -- key → GetTime()

local function SetWasteBypass(key)
    wasteBypass[key] = GetTime()
end

local function IsWasteBypassed(key)
    local t = wasteBypass[key]
    if not t then return false end
    if GetTime() - t > 5 then
        wasteBypass[key] = nil
        return false
    end
    return true
end

-- When a right-click alternate is confirmed, temporarily swap the
-- button to the alternate item. Cleared on next update.
local altSwap = {}  -- key → alternateItemID

StaticPopupDialogs["APOTHECA_WASTE_ASK"] = {
    text    = "|cff9966ffApotheca|r\nYou are at full %s.\nUse %s anyway?",
    button1 = "Yes",
    button2 = "No",
    OnAccept = function(self)
        local data = self.data
        if not data then return end
        SetWasteBypass(data.btnKey)
        local btn = Apotheca.buttons[data.btnKey]
        if btn and btn.itemID and not InCombatLockdown() then
            -- Use the item directly — the "Yes" click is a hardware event.
            local name = GetItemInfo(btn.itemID)
            if name then
                Apotheca.API.UseItemByName(name)
            end
            -- Also re-enable the button for subsequent clicks
            Apotheca.ApplySecureItemAttributes(btn, btn.itemID)
            btn.icon:SetDesaturated(false)
            if btn._askOverlay then btn._askOverlay:Hide() end
        end
    end,
    timeout       = 0,
    whileDead     = false,
    hideOnEscape  = true,
    preferredIndex = 3,
}

StaticPopupDialogs["APOTHECA_ALT_ASK"] = {
    text    = "|cff9966ffApotheca|r\nUse %s instead?",
    button1 = "Yes",
    button2 = "No",
    OnAccept = function(self)
        local data = self.data
        if not data then return end
        local btn = Apotheca.buttons[data.btnKey]
        if btn and data.altItemID and not InCombatLockdown() then
            -- Use the alternate item directly.
            local name = GetItemInfo(data.altItemID)
            if name then
                Apotheca.API.UseItemByName(name)
            end
            -- Also swap the button in case the direct use failed
            SetWasteBypass(data.btnKey)
            altSwap[data.btnKey] = data.altItemID
            Apotheca.ApplySecureItemAttributes(btn, data.altItemID)
            btn.icon:SetTexture(GetCachedTexture(data.altItemID) or FALLBACK_ICON)
            btn.icon:SetDesaturated(false)
            if btn._askOverlay then btn._askOverlay:Hide() end
        end
    end,
    timeout       = 0,
    whileDead     = false,
    hideOnEscape  = true,
    preferredIndex = 3,
}

-- Helper: show a StaticPopup and attach data via the dialog.data field
-- (Classic TBC passes data as 4th arg to StaticPopup_Show).
local function ShowPopupWithData(which, text1, text2, data)
    local dialog = StaticPopup_Show(which, text1, text2)
    if dialog then
        dialog.data = data
    end
end

-- ── ASK overlay for waste prevention ─────────────────────────

-- Would using this button's item actually waste it *right now*?
-- The overlay is armed by UpdateAllButtons, which bails out during combat
-- lockdown, so by the time it is clicked the stored state can be stale —
-- e.g. a mana biscuit blocked at full health and mana, then clicked after
-- mana has been spent. Re-read the live values instead of trusting it.
local function IsStillWasteful(btn)
    local missHP, missMana = Apotheca.API.PlayerMissing()
    -- Unreadable means nothing is known to be wasted: use the item.
    local hpFull   = missHP ~= nil and missHP <= 0
    local manaFull = missMana ~= nil and missMana <= 0
    local res = btn._wasteResource
    if res == "health" then return hpFull end
    if res == "mana"   then return manaFull end
    -- "health and mana" (conjured biscuits, mana-restoring food): both must
    -- be full, since the item is still doing something useful otherwise.
    return hpFull and manaFull
end

local function CreateAskOverlay(btn)
    local overlay = CreateFrame("Button", nil, btn)
    overlay:SetAllPoints(btn)
    overlay:SetFrameLevel(btn:GetFrameLevel() + 10)
    overlay:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    overlay:Hide()
    overlay:SetScript("OnClick", function(self, button)
        if not btn.itemID then return end

        -- Nothing is being wasted any more — behave exactly like an
        -- unblocked button: use the primary item, no confirmation.
        if not IsStillWasteful(btn) then
            -- UseItemByName is protected. This OnClick is an insecure path,
            -- so calling it during lockdown raises ADDON_ACTION_BLOCKED
            -- instead of using the item — and because the overlay can only
            -- be hidden out of combat, every further click repeats the
            -- error. Every button carrying an overlay holds food or drink,
            -- which cannot be consumed in combat anyway, so say so instead.
            if InCombatLockdown() then
                local name = GetCachedItemName(btn.itemID) or ("item:" .. btn.itemID)
                print("|cff9966ffApotheca:|r " .. name .. " cannot be used in combat.")
                return
            end
            local name = GetCachedItemName(btn.itemID) or GetItemInfo(btn.itemID)
            if name then Apotheca.API.UseItemByName(name) end
            -- Hand the button back to the secure path so later clicks skip
            -- this overlay entirely.
            Apotheca.ApplySecureItemAttributes(btn, btn.itemID)
            btn.icon:SetDesaturated(false)
            overlay:Hide()
            return
        end

        -- BLOCK mode: the overlay exists purely so the click has a voice.
        -- Without it the button is silently dead and the only clue is a
        -- slightly desaturated icon.
        if (DB().preventWasteMode or "BLOCK") == "BLOCK" then
            local name = GetCachedItemName(btn.itemID) or ("item:" .. btn.itemID)
            print("|cff9966ffApotheca:|r " .. name .. " not used — you are at full "
                  .. (btn._wasteResource or "health/mana")
                  .. ". Change this under Prevent waste in /apo.")
            return
        end

        -- Right-click: check for alternate item
        if button == "RightButton" then
            local altID  = btn._alternateItemID
            local rcMode = DB().rightClickAlternate or "OFF"
            if altID and rcMode ~= "OFF" then
                local altName = GetCachedItemName(altID) or GetItemInfo(altID) or ("item:" .. altID)
                ShowPopupWithData("APOTHECA_ALT_ASK", altName, nil,
                    { btnKey = btn.cfg.key, altItemID = altID })
                return
            end
        end

        -- Left-click (or right-click without alternate): waste confirm
        local name    = GetCachedItemName(btn.itemID) or ("item:" .. btn.itemID)
        local resType = btn._wasteResource or "health/mana"
        ShowPopupWithData("APOTHECA_WASTE_ASK", resType, name,
            { btnKey = btn.cfg.key })
    end)
    overlay:SetScript("OnEnter", function() btn:GetScript("OnEnter")(btn) end)
    overlay:SetScript("OnLeave", function() btn:GetScript("OnLeave")(btn) end)
    btn._askOverlay = overlay
end

for _, key in ipairs({ "recovery", "food", "drink" }) do
    CreateAskOverlay(Apotheca.buttons[key])
end

-- Note: Right-click alternate (ASK mode) only works when the waste
-- prevention overlay is visible. When waste prevention is OFF or BLOCK,
-- or the player is not at full health/mana, right-click uses the
-- primary item (same as left-click). PostClick hooks on secure buttons
-- introduce taint in Classic TBC that spreads to all sibling buttons.

-- ============================================================
-- BUTTON ORDER — DEFAULT KEY SEQUENCE
-- This is the canonical default order. Custom orders stored
-- in db.buttonOrder override it.
-- ============================================================

Apotheca.DEFAULT_BUTTON_ORDER = {
    "mana", "managem", "health", "healthstone", "rune",
    "recovery", "food", "drink",
    "flask", "battle", "guardian",
    "bufffood", "xpfood",
    "spiritscroll", "protectionscroll",
    "intellectscroll", "staminascroll", "strengthscroll", "agilityscroll",
    "weaponoil", "poisonmh", "poisonoh", "stonemh", "stoneoh",
    "bandage",
}

-- All known button keys (for validation).
Apotheca.ALL_BUTTON_KEYS = {}
for _, k in ipairs(Apotheca.DEFAULT_BUTTON_ORDER) do
    Apotheca.ALL_BUTTON_KEYS[k] = true
end

-- Returns the saved order from the profile, validated and
-- back-filled with any missing keys.
function Apotheca.GetButtonOrder()
    local db    = DB()
    local saved = db.buttonOrder
    if not saved or type(saved) ~= "table" or #saved == 0 then
        return { unpack(Apotheca.DEFAULT_BUTTON_ORDER) }
    end

    -- Validate: strip unknowns and duplicates, then append missing.
    local seen, clean = {}, {}
    for _, k in ipairs(saved) do
        if Apotheca.ALL_BUTTON_KEYS[k] and not seen[k] then
            seen[k]         = true
            clean[#clean+1] = k
        end
    end
    for _, k in ipairs(Apotheca.DEFAULT_BUTTON_ORDER) do
        if not seen[k] then
            clean[#clean+1] = k
        end
    end
    return clean
end

-- ============================================================
-- LAYOUT
-- ============================================================

-- RefreshLayout builds the active button list and positions everything.
-- staticFlags = table keyed by button key → true if that slot should appear
-- scrollFlags = { scrolls = { [key] = { id, count, tex, show } }, managem=bool,
--                 oil=bool, food=bool, bandage=bool, healthstone=bool }
local function RefreshLayout(recoveryMode, elixirMode, staticFlags, scrollFlags)
    -- 1. Determine which keys are active this frame.
    local shouldShow = {}

    for _, cfg in ipairs(STATIC_BUTTON_CONFIG) do
        if not staticFlags or staticFlags[cfg.key] then
            shouldShow[cfg.key] = true
        end
    end

    if recoveryMode == "conjured" then
        shouldShow["recovery"] = true
    elseif recoveryMode == "split" then
        shouldShow["food"]  = true
        shouldShow["drink"] = true
    end

    if elixirMode then
        shouldShow["flask"]    = elixirMode.flask
        shouldShow["battle"]   = elixirMode.battle
        shouldShow["guardian"] = elixirMode.guardian
    end

    if scrollFlags and scrollFlags.food       then shouldShow["bufffood"]         = true end
    if scrollFlags and scrollFlags.xpfood     then shouldShow["xpfood"]           = true end
    if scrollFlags and scrollFlags.scrolls then
        for key, r in pairs(scrollFlags.scrolls) do
            if r.show then shouldShow[key] = true end
        end
    end
    if scrollFlags and scrollFlags.managem then shouldShow["managem"] = true end
    if scrollFlags and scrollFlags.oil        then shouldShow["weaponoil"]        = true end
    for key, r in pairs(scrollFlags and scrollFlags.poisons or {}) do
        if r.show then shouldShow[key] = true end
    end
    if scrollFlags and scrollFlags.bandage    then shouldShow["bandage"]          = true end
    if scrollFlags and scrollFlags.healthstone then shouldShow["healthstone"]      = true end

    -- 1b. Class gating, in one place, from each button's config:
    --   restores == "mana" / requiresMana: never for a class without mana
    --   classOnly = "MAGE": only for that class
    local usesMana = Apotheca.UsesMana()
    local _, playerClass = UnitClass("player")
    for key in pairs(shouldShow) do
        local btn = Apotheca.buttons[key]
        local cfg = btn and btn.cfg
        if cfg then
            if not usesMana and (cfg.restores == "mana" or cfg.requiresMana) then shouldShow[key] = nil end
            if cfg.classOnly and cfg.classOnly ~= playerClass then shouldShow[key] = nil end
        end
    end

    -- 2. Build the active list in the user's custom order.
    local order  = Apotheca.GetButtonOrder()
    local active = {}
    for _, key in ipairs(order) do
        if shouldShow[key] then
            active[#active + 1] = key
        end
    end

    ApplyLayout(active)

    -- Hide every managed button not in the active list: all of them, so a
    -- new button cannot be forgotten in a hand-written list.
    local activeSet = {}
    for _, k in ipairs(active) do activeSet[k] = true end
    for key, btn in pairs(Apotheca.buttons) do
        if not activeSet[key] then btn:Hide() end
    end
end

-- ============================================================
-- APPLY ITEM TO BUTTON
-- ============================================================

local function ApplyItemToButton(btn, itemID, count, texture)
    local db = DB()
    if db.debug and itemID ~= btn.itemID then
        local name = itemID and (GetItemInfo(itemID) or ("id:" .. itemID)) or "Nothing"
        print(string.format("|cff9966ffApotheca:|r [%s] → %s", btn.cfg.label, name))
    end

    btn.itemID = itemID
    Apotheca.ApplySecureItemAttributes(btn, itemID)

    if itemID then
        btn.icon:SetTexture(texture or GetCachedTexture(itemID) or FALLBACK_ICON)
        btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        btn.icon:SetDesaturated(false)
        btn.icon:Show()
        btn.emptyBg:SetAlpha(0)
        btn.countText:SetText(count and count > 1 and count or "")
        ApplyItemCooldown(btn.cooldown, itemID)
    else
        btn.countText:SetText("")
        btn.cooldown:SetCooldown(0, 0)
        -- Always show the empty-slot icon desaturated so the player
        -- knows what WOULD go here. Previously only debug mode did this.
        btn.icon:SetTexture(btn.cfg.emptyIcon)
        btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        btn.icon:SetDesaturated(true)
        btn.icon:Show()
        btn.emptyBg:SetAlpha(0.6)
    end
end

-- ============================================================
-- COMBAT-SAFE VISUAL REFRESH
-- ============================================================
-- Refreshes ONLY the cooldown swipe and count text on buttons that
-- already have an itemID assigned. Does not touch secure attributes,
-- layout, Show/Hide, or SetPoint, so it is safe to run during combat
-- lockdown. Used on BAG_UPDATE_COOLDOWN (so the GCD swipe shows the
-- moment an item is used) and alongside BAG_UPDATE_DELAYED (so the
-- stack count ticks down live instead of after combat ends).
function Apotheca.RefreshButtonVisuals(countsToo)
    -- Stack counts may be secret in combat. Scan once; on failure keep the
    -- counts already shown instead of rescanning for every button.
    local bagMap
    if countsToo then
        local ok, map = pcall(Apotheca.BuildBagMap)
        if ok then bagMap = map else countsToo = false end
    end
    for _, btn in pairs(Apotheca.buttons) do
        if btn.itemID then
            ApplyItemCooldown(btn.cooldown, btn.itemID)
            if countsToo then
                local count = bagMap[btn.itemID] or 0
                btn.countText:SetText(count > 1 and count or "")
            end
        end
    end
end

-- ============================================================
-- FULL TINT (#6)
-- Greys a recovery icon while the resource it restores is full, using
-- the client-side colour curve (Apotheca.API.TintByFullness). Waste
-- prevention cannot BLOCK on Forever, because current health and mana
-- are secret; this is the part that can still be shown. It touches no
-- secure attribute, so it runs in combat too.
-- ============================================================

-- Items that restore BOTH health and mana: Enriched Manna Biscuit, the
-- rations, rejuvenation potions. They are still useful while only one of
-- the two is full, and "both full" cannot be shown: it would mean combining
-- two secret colours, which Lua may not touch. So they are never greyed.
-- Built from the same DATA flags FindBestFood / FindBestDrink return (the
-- waste check's rec.foodRestoresMana), plus potions on both potion tables;
-- a lookup by item, because an alt-swapped item needs it too.
local RESTORES_BOTH = {}
for _, e in ipairs(DATA.FOOD_ITEMS)  do if e.restoresMana   then RESTORES_BOTH[e.id] = true end end
for _, e in ipairs(DATA.DRINK_ITEMS) do if e.restoresHealth then RESTORES_BOTH[e.id] = true end end
for id in pairs(DATA.POTION_VALUE.health) do
    if DATA.POTION_VALUE.mana[id] then RESTORES_BOTH[id] = true end
end
Apotheca._RESTORES_BOTH = RESTORES_BOTH

-- Repaint every button whose `cfg.restores` is `only` (or every button when
-- `only` is nil): the fullness colour is asked once per resource. The item
-- judged is the one the icon SHOWS, which is the alternate after an alt
-- swap. Safe in combat: no secure attribute is touched.
function Apotheca.RefreshFullTint(only)
    local on = DB().fullTint ~= false
    -- Sort the icons: those to tint, per resource, and those to reset.
    local toTint = { health = {}, mana = {} }
    local toReset = {}
    for key, btn in pairs(Apotheca.buttons) do
        local resource = btn.cfg and btn.cfg.restores
        if resource and btn.icon and (not only or only == resource) then
            local id = altSwap[key] or btn.itemID
            if on and id and not RESTORES_BOTH[id] then
                local list = toTint[resource]
                list[#list + 1] = btn.icon
            else
                toReset[#toReset + 1] = btn.icon
            end
        end
    end
    -- The compat layer paints; this file never holds a (secret) colour.
    for resource, icons in pairs(toTint) do
        if not Apotheca.API.PaintFullness(resource, icons) then
            for _, icon in ipairs(icons) do toReset[#toReset + 1] = icon end
        end
    end
    for _, icon in ipairs(toReset) do icon:SetVertexColor(1, 1, 1) end
end

-- ============================================================
-- MAIN UPDATE
-- ============================================================

-- The body writes secure attributes, so it stays file-local: the only way
-- in is the guarded Apotheca.UpdateAllButtons below.
local UpdateAllButtonsBody

function Apotheca.UpdateAllButtons()
    -- Secure buttons cannot be shown/hidden/moved/resized during combat.
    -- The bar will refresh automatically when combat ends (PLAYER_REGEN_ENABLED).
    if InCombatLockdown() then return end
    -- Resolve the role once, fresh, for this whole update (quietly: this
    -- IS the update a change would ask for).
    Apotheca.RefreshRole(true)
    UpdateAllButtonsBody()
    Apotheca.RefreshFullTint()
    -- Counts full updates: a deferred request (RequestUpdate) made before
    -- this one is satisfied by it and does not run again.
    Apotheca._updateSeq = (Apotheca._updateSeq or 0) + 1
end

function UpdateAllButtonsBody()

    local db = DB()

    if db.enabled == false then
        ApothecaFrame:Hide()
        remindPending = false   -- a hidden bar has nothing to remind
        return
    end

    local specOk = (not db.onlyWhenHealer) or Apotheca.IsHealerSpec()
    if not specOk or not Apotheca.IsVisible() then
        ApothecaFrame:Hide()
        remindPending = false
        return
    end
    ApothecaFrame:Show()

    if db.debug then debugLabel:Show() else debugLabel:Hide() end

    local showEmpty = db.showEmptyButtons or db.debug
    local bagMap    = Apotheca.BuildBagMap()

    -- ── Static slots ─────────────────────────────────────────────
    -- "mana" and "health" are always visible — show greyed out
    -- with the highest-tier icon when nothing is in bags.
    local ALWAYS_VISIBLE_STATIC = { mana = true, health = true }
    local staticFlags = {}
    for _, cfg in ipairs(STATIC_BUTTON_CONFIG) do
        local btn = Apotheca.buttons[cfg.key]
        local id, cnt, tex
        if cfg.key == "health" then
            id, cnt, tex = Apotheca.FindBestHealthConsumable(bagMap)
        else
            if cfg.key == "mana" then
                id, cnt, tex = Apotheca.FindBestPotion("mana", cfg.list, bagMap)
            else
                id, cnt, tex = Apotheca.FindBestItem(cfg.list, bagMap)
            end
        end
        ApplyItemToButton(btn, id, cnt, tex)
        local show = id ~= nil or showEmpty or ALWAYS_VISIBLE_STATIC[cfg.key]
        staticFlags[cfg.key] = show
        if show then btn:Show() else btn:Hide() end
    end

    -- ── XP food (optional, while levelling) ───────────────────────
    -- Resolved before Food, Drink and Buff Food: while it offers an item,
    -- every XP food is its own, and they offer only the others, so one food
    -- never shows on two buttons. That includes Food and Drink: XP food
    -- whose Well Fed is movement speed, fishing or herbalism (Sweetpaw Jam,
    -- Goldthorn Tea) is plain food or drink (Codex review of #22). When it
    -- offers nothing (none held, or all above the level), they offer
    -- everything as usual.
    local xpOn = Apotheca.XPFoodEnabled()
    local xpID, xpCnt, xpTex
    if xpOn then
        xpID, xpCnt, xpTex = Apotheca.FindBestXPFood(bagMap)
    end
    local xpOwned = xpID and Apotheca.XP_FOOD_IDS or nil
    local recoveryBags = bagMap
    if xpOwned then
        recoveryBags = {}
        for id, n in pairs(bagMap) do
            if not xpOwned[id] then recoveryBags[id] = n end
        end
    end

    -- ── Recovery + Elixirs ───────────────────────────────────────
    local rec     = ResolveRecovery(recoveryBags)
    local elixRes = Apotheca.ResolveElixirs(bagMap)

    local recovMode
    if rec.mode == "conjured" then
        recovMode = "conjured"
    else
        -- Always use split mode so food/drink buttons remain visible
        -- (greyed out when empty).
        recovMode = "split"
    end

    -- Which elixir slots get a place on the bar. Only slots that will show:
    -- a slot hidden after layout would leave a hole in the bar.
    local elixirsOn = not (db.elixirs and db.elixirs.enabled == false)
    local elixMode = {
        flask    = elixirsOn and (elixRes.flaskID    ~= nil or showEmpty),
        battle   = elixirsOn and (elixRes.battleID   ~= nil or showEmpty),
        guardian = elixirsOn and (elixRes.guardianID ~= nil or showEmpty),
    }

    -- ── Scrolls: the kinds the role wants, minus those switched off ──
    local scrollsDB  = db.scrolls
    local scrollsOn  = not scrollsDB or scrollsDB.enabled
    local wanted = {}
    for _, stat in ipairs(Apotheca.GetRoleProfile().scrolls or {}) do wanted[stat] = true end
    -- Every mana user also wants Intellect (more mana): hunters share the
    -- Agility profile with rogues, and paladin or druid tanks and ret
    -- paladins have mana too. Warriors and rogues do not.
    if Apotheca.UsesMana() then wanted.intellect = true end
    local scrollRes = {}      -- key -> { id, count, tex, show }
    for _, kind in ipairs(SCROLL_KINDS) do
        local on = scrollsOn and wanted[kind.stat]
            and (not scrollsDB or scrollsDB[kind.setting] ~= false)
        local r = { show = false }
        if on then
            r.id, r.count, r.tex = Apotheca.FindBestItem(kind.items, bagMap)
            r.show = r.id ~= nil or showEmpty
        end
        scrollRes[kind.key] = r
    end

    -- ── Mana gem (mages) ─────────────────────────────────────────
    -- Which class may see it is the config's `classOnly` (RefreshLayout).
    -- Out of combat the button offers the strongest gem that is READY:
    -- each gem has its own cooldown, and a Ruby on cooldown must not hide
    -- a usable Citrine. (In combat the button cannot change.)
    local gemOn = not (db.manaGem and db.manaGem.enabled == false)
    local gemID, gemCnt, gemTex
    -- When a stronger gem was skipped for its cooldown, re-pick once it is
    -- ready (the slow out-of-combat poll requests the update).
    Apotheca._recheckAt = nil
    if gemOn then
        gemID, gemCnt, gemTex, Apotheca._recheckAt = Apotheca.FindBestReadyItem(DATA.MANA_GEMS, bagMap)
    end

    -- ── Buff food ────────────────────────────────────────────────
    local buffFoodID, buffFoodCnt, buffFoodTex
    if db.buffFood and db.buffFood.enabled then
        buffFoodID, buffFoodCnt, buffFoodTex =
            Apotheca.FindBestBuffFood(bagMap, xpOwned)
    end

    -- ── Weapon coatings: poisons, stones (experimental), oil ───────
    -- One owner per hand (Codex review of #32), each hand's choices read
    -- once:
    -- 1. a rogue's chosen poison, even out of stock: the choice reserves
    --    the hand (poisons are for rogues only: checked here, and by the
    --    buttons' classOnly in RefreshLayout);
    -- 2. else a stone the player chose AND has one to offer for this
    --    weapon: a choice with nothing to offer must not hide a usable oil
    --    (/code-review of #33);
    -- 3. else, on the main hand, the Weapon Oil button, as before.
    local _, playerClass = UnitClass("player")
    local poisonsOn = db.poisons and db.poisons.enabled and playerClass == "ROGUE"
    local poisonRes, handOwner = {}, {}
    for _, hand in ipairs({ { 16, "poisonmh", "stonemh" }, { 17, "poisonoh", "stoneoh" } }) do
        local slot = hand[1]
        local p, st = { show = false }, { show = false }
        local family = poisonsOn and Apotheca.PoisonChoice(slot)
        if family and family ~= "none" then
            handOwner[slot] = "poison"
            if Apotheca.CoatableHand(slot) then
                p.id, p.count, p.tex = Apotheca.FindBestPoison(family, bagMap)
                p.show = p.id ~= nil or showEmpty
            end
        else
            local choice = Apotheca.StoneChoice(slot)
            st.kind = choice ~= "none" and Apotheca.StoneKind(slot) or nil
            if st.kind then
                st.id, st.count, st.tex = Apotheca.FindBestStone(choice, st.kind, bagMap)
                if st.id then handOwner[slot] = "stone" end
            end
        end
        poisonRes[hand[2]], poisonRes[hand[3]] = p, st
    end
    -- The oil only when nothing else owns the main hand.
    local oilID, oilCnt, oilTex
    if not handOwner[16] and (not db.weaponOil or db.weaponOil.enabled) then
        oilID, oilCnt, oilTex = Apotheca.FindBestWeaponOil(bagMap)
    end
    -- A chosen stone with none to offer shows empty (Show Empty Buttons)
    -- only where no oil stands in for it; then it keeps the hand.
    for slot, key in pairs({ [16] = "stonemh", [17] = "stoneoh" }) do
        local st = poisonRes[key]
        st.show = st.id ~= nil or (st.kind ~= nil and showEmpty and not (slot == 16 and oilID))
    end
    local oilOwned = handOwner[16] ~= nil or poisonRes.stonemh.show

    -- ── Bandage ──────────────────────────────────────────────────
    local bandageID, bandageCnt, bandageTex
    if not db.bandage or db.bandage.enabled then
        bandageID, bandageCnt, bandageTex = Apotheca.FindBestBandage(bagMap)
    end

    -- ── Healthstone ──────────────────────────────────────────────
    local hsID, hsCnt, hsTex, hsHeal, hsSmart
    if not db.healthstone or db.healthstone.enabled ~= false then
        hsID, hsCnt, hsTex, hsHeal, hsSmart = Apotheca.FindBestHealthstone(bagMap)
    end

    -- ── Build layout flags — only include a slot if it has content (or showEmpty) ──
    local flags = {
        food        = (buffFoodID ~= nil)          or (db.buffFood and db.buffFood.enabled and showEmpty),
        scrolls     = scrollRes,
        managem     = gemOn and (gemID ~= nil or showEmpty),
        xpfood      = xpOn and (xpID ~= nil or showEmpty),
        oil         = not oilOwned and ((oilID ~= nil) or ((not db.weaponOil or db.weaponOil.enabled) and showEmpty)),
        poisons     = poisonRes,
        bandage     = (bandageID  ~= nil)          or ((not db.bandage or db.bandage.enabled) and showEmpty),
        healthstone = (hsID       ~= nil)          or ((not db.healthstone or db.healthstone.enabled ~= false) and showEmpty),
    }

    RefreshLayout(recovMode, elixMode, staticFlags, flags)

    -- ── Apply button contents ────────────────────────────────────
    if recovMode == "conjured" then
        Apotheca.buttons["recovery"]._alternateItemID = nil
        ApplyItemToButton(Apotheca.buttons["recovery"], rec.conjuredID, rec.conjuredCount, rec.conjuredTexture)
    elseif recovMode == "split" then
        -- Set alternate items BEFORE apply so secure attributes can bind type2/item2.
        Apotheca.buttons["food"]._alternateItemID  = rec.foodAltID
        Apotheca.buttons["drink"]._alternateItemID = rec.drinkAltID
        ApplyItemToButton(Apotheca.buttons["food"],  rec.foodID,  rec.foodCount,  rec.foodTexture)
        ApplyItemToButton(Apotheca.buttons["drink"], rec.drinkID, rec.drinkCount, rec.drinkTexture)
        -- Food and drink are always visible; ApplyItemToButton handles
        -- greyed-out display when itemID is nil.
    end

    if elixMode.flask then
        ApplyItemToButton(Apotheca.buttons["flask"], elixRes.flaskID, elixRes.flaskCount, elixRes.flaskTex)
    end
    if elixMode.battle then
        ApplyItemToButton(Apotheca.buttons["battle"], elixRes.battleID, elixRes.battleCount, elixRes.battleTex)
    end
    if elixMode.guardian then
        ApplyItemToButton(Apotheca.buttons["guardian"], elixRes.guardianID, elixRes.guardianCount, elixRes.guardianTex)
    end

    if flags.food then
        ApplyItemToButton(Apotheca.buttons["bufffood"], buffFoodID, buffFoodCnt, buffFoodTex)
    end
    for key, r in pairs(flags.scrolls or {}) do
        if r.show then ApplyItemToButton(Apotheca.buttons[key], r.id, r.count, r.tex) end
    end
    if flags.managem then
        ApplyItemToButton(Apotheca.buttons["managem"], gemID, gemCnt, gemTex)
    end
    if flags.xpfood then
        ApplyItemToButton(Apotheca.buttons["xpfood"], xpID, xpCnt, xpTex)
    end
    -- Applied even when hidden (a stone took the main hand), so no stale
    -- item or target stays on the button.
    if flags.oil then
        ApplyItemToButton(Apotheca.buttons["weaponoil"], oilID, oilCnt, oilTex)
    else
        ApplyItemToButton(Apotheca.buttons["weaponoil"], nil, 0, nil)
    end
    -- Poison and stone buttons are applied even when hidden, so a hand left
    -- with nothing loses its item AND its target-slot, not only its place.
    for key, r in pairs(flags.poisons or {}) do
        ApplyItemToButton(Apotheca.buttons[key], r.id, r.count, r.tex)
    end
    if flags.bandage then
        ApplyItemToButton(Apotheca.buttons["bandage"], bandageID, bandageCnt, bandageTex)
    end
    if flags.healthstone then
        local hsBtn = Apotheca.buttons["healthstone"]
        -- Stashed for the tooltip so it can explain the smart-rank pick.
        hsBtn._healValue    = hsHeal
        hsBtn._smartRankPick = hsSmart
        ApplyItemToButton(hsBtn, hsID, hsCnt, hsTex)
    end

    -- ── Bandage usability ─────────────────────────────────────────
    -- "Recently Bandaged" debuff blocks further bandage use for 60 s.
    -- Desaturate and disable the button while the debuff is active.
    if flags.bandage and not db.debug and not InCombatLockdown() then
        local bandageBtn = Apotheca.buttons["bandage"]
        if bandageBtn and bandageBtn.itemID and Apotheca.HasRecentlyBandaged() then
            bandageBtn:SetAttribute("type", nil)
            bandageBtn:SetAttribute("item", nil)
            bandageBtn.icon:SetDesaturated(true)
        end
    end

    -- ── Clear stale alt-swaps from right-click ──────────────────
    -- If a button was temporarily swapped to an alternate, clear it
    -- so this update puts the correct primary item back.
    for k, _ in pairs(altSwap) do
        altSwap[k] = nil
    end

    -- ── Waste prevention ──────────────────────────────────────────
    -- Modes: "BLOCK"      — disable button entirely (old default)
    --        "ASK"        — show overlay that asks for confirmation
    --        "DO_NOTHING" — no prevention
    -- Buff food is always excluded (you eat for the buff, not the HP).
    local wasteMode = db.preventWasteMode or "BLOCK"
    if wasteMode ~= "DO_NOTHING" and not db.debug and not InCombatLockdown() then
        local missHP, missMana = Apotheca.API.PlayerMissing()
        local hpFull   = missHP ~= nil and missHP <= 0
        local manaFull = missMana ~= nil and missMana <= 0

        local function DisableButton(btn, resource)
            if not btn or not btn.itemID then return end
            -- If this button was recently bypassed via "Yes", skip prevention.
            if IsWasteBypassed(btn.cfg.key) then
                btn._wasteBlocked = false
                if btn._askOverlay then btn._askOverlay:Hide() end
                return
            end
            btn._wasteResource = resource
            btn._wasteBlocked  = true
            if wasteMode == "BLOCK" then
                btn:SetAttribute("type", nil)
                btn:SetAttribute("item", nil)
                btn.icon:SetDesaturated(true)
                -- Overlay is shown in BLOCK mode too — it does not confirm
                -- anything here, it just explains why the click did nothing.
                if btn._askOverlay then btn._askOverlay:Show() end
            elseif wasteMode == "ASK" then
                btn:SetAttribute("type", nil)
                btn:SetAttribute("item", nil)
                if btn._askOverlay then btn._askOverlay:Show() end
            end
        end

        local function EnableButton(btn)
            if not btn then return end
            btn._wasteBlocked = false
            if btn._askOverlay then btn._askOverlay:Hide() end
        end

        if recovMode == "conjured" then
            if hpFull and manaFull then
                DisableButton(Apotheca.buttons["recovery"], "health and mana")
            else
                EnableButton(Apotheca.buttons["recovery"])
            end
        elseif recovMode == "split" then
            -- Food that also restores mana (Enriched Manna Biscuit), or a
            -- drink that also restores health, is only wasted when BOTH are
            -- full. Written as plain ifs: `a and (b and c) or b` falls
            -- through to b whenever (b and c) is false, which blocked a
            -- mana-restoring food at full health with mana missing.
            local foodFull = hpFull
            if rec.foodRestoresMana then foodFull = hpFull and manaFull end
            local drinkFull = manaFull
            if rec.drinkRestoresHealth then drinkFull = hpFull and manaFull end
            if foodFull then DisableButton(Apotheca.buttons["food"],
                              rec.foodRestoresMana and "health and mana" or "health")
            else             EnableButton(Apotheca.buttons["food"]) end
            if drinkFull then DisableButton(Apotheca.buttons["drink"],
                              rec.drinkRestoresHealth and "health and mana" or "mana")
            else             EnableButton(Apotheca.buttons["drink"]) end
        end
    else
        for _, key in ipairs({ "recovery", "food", "drink" }) do
            local btn = Apotheca.buttons[key]
            if btn then
                btn._wasteBlocked = false
                if btn._askOverlay then btn._askOverlay:Hide() end
            end
        end
    end

    UpdateBuffFoodGlow()
    UpdateElixirGlow(elixRes)
    UpdateScrollGlow()
    UpdateWeaponOilGlow()
    Apotheca._lastElixRes = elixRes

    -- The after-combat reminder starts here, AFTER the bar was rebuilt for
    -- the post-combat bags, so it glows the item the button now holds.
    if remindPending then
        remindPending = false
        -- Death ends combat as well; no reminder for a corpse.
        if not UnitIsDeadOrGhost("player") then remindUntil = GetTime() + REMIND_SECONDS end
    end
    UpdateXPFoodGlow()
    UpdateCoatingGlow()
end

-- ============================================================
-- PUBLIC API
-- ============================================================

function Apotheca.SetDebug(enabled)
    if InCombatLockdown() then
        print("|cff9966ffApotheca:|r Cannot change debug in combat.")
        return
    end
    DB().debug = enabled
    for _, btn in pairs(Apotheca.buttons) do ApplyDebugAttributes(btn) end
    Apotheca.UpdateAllButtons()
    if enabled then
        print("|cff9966ffApotheca:|r |cffff6600Debug ON|r — items will not be consumed.")
    else
        print("|cff9966ffApotheca:|r Debug OFF.")
    end
end

-- Called by Options.lua when buff food enabled is toggled,
-- so the bar recalculates its width on the next update.

-- ============================================================
-- OPTIONS PANEL  (implemented in Apotheca_Options.lua)
-- Apotheca.CreateOptionsPanel() is defined there and called
-- from the ADDON_LOADED handler below.
-- ============================================================

-- ============================================================
-- SLASH COMMANDS
-- ============================================================

SLASH_APOTHECA1 = "/apotheca"
SLASH_APOTHECA2 = "/apo"
SlashCmdList["APOTHECA"] = function(msg)
    local cmd = msg and msg:lower():match("^%s*(.-)%s*$") or ""
    if cmd == "debug" then
        Apotheca.SetDebug(not DB().debug)
    elseif cmd == "probe" and Apotheca.RunProbe then
        Apotheca.RunProbe()
    elseif cmd == "scan" and Apotheca.RunItemScan then
        Apotheca.RunItemScan()
    elseif cmd == "scan2" and Apotheca.RunSpellScan then
        Apotheca.RunSpellScan()
    elseif cmd == "scan3" and Apotheca.RunWellFedScan then
        Apotheca.RunWellFedScan()
    elseif cmd:match("^proftest") and Apotheca.RunProfTest then
        Apotheca.RunProfTest(cmd:match("^proftest%s*(.*)$"))
    elseif cmd:match("^prof") and Apotheca.RunProfProbe then
        Apotheca.RunProfProbe(cmd:match("^prof%s*(.*)$"))
    elseif cmd:match("^bar") and Apotheca.RunBarProbe then
        Apotheca.RunBarProbe(cmd:match("^bar%s*(.*)$"))
    elseif cmd:match("^applytest") and Apotheca.RunApplyTest then
        Apotheca.RunApplyTest(cmd:match("^applytest%s*(.*)$"))
    elseif cmd == "status" then
        -- Diagnostic for "I click a button and nothing happens".
        local db = DB()
        local missHP, missMana = Apotheca.API.PlayerMissing()
        local hpFull   = missHP == nil and "unknown" or tostring(missHP <= 0)
        local manaFull = missMana == nil and "unknown" or tostring(missMana <= 0)
        print("|cff9966ffApotheca:|r debug=" .. tostring(db.debug and true or false)
              .. "  preventWaste=" .. (db.preventWasteMode or "BLOCK")
              .. "  combat=" .. tostring(InCombatLockdown() and true or false)
              .. "  healthFull=" .. hpFull
              .. "  manaFull=" .. manaFull)
        for _, key in ipairs(Apotheca.GetButtonOrder()) do
            local btn = Apotheca.buttons[key]
            if btn and btn:IsShown() then
                local name = btn.itemID and (GetItemInfo(btn.itemID) or ("id:" .. btn.itemID))
                              or "(empty)"
                local why
                if not btn.itemID then                  why = "no item in bags"
                elseif db.debug then                    why = "|cffff6600debug mode — will not consume|r"
                elseif btn._wasteBlocked then           why = "|cffff6600blocked: full "
                                                              .. (btn._wasteResource or "health/mana") .. "|r"
                elseif btn:GetAttribute("type") then    why = "|cff66ff66clickable|r"
                else                                    why = "|cffff6600no click action set|r"
                end
                print(string.format("|cff9966ff  %s:|r %s — %s", btn.cfg.label, name, why))
            end
        end
    else
        local panel = Apotheca.optionsPanel
        if Settings and Settings.OpenToCategory and panel and panel._category then
            Settings.OpenToCategory(panel._category:GetID())
        elseif InterfaceOptionsFrame_OpenToCategory and panel then
            InterfaceOptionsFrame_OpenToCategory(panel)
            InterfaceOptionsFrame_OpenToCategory(panel)
        else
            print("|cff9966ffApotheca:|r Options panel not ready. Try again after login.")
            print("|cff9966ffApotheca:|r /apo debug — toggle debug mode")
            print("|cff9966ffApotheca:|r /apo status — why a button is or isn't clickable")
        end
    end
end

-- ============================================================
-- EVENTS
-- ============================================================

local playerReady = false

local eventFrame = CreateFrame("Frame", "ApothecaEventFrame", UIParent)
-- ZONE_CHANGED_NEW_AREA: instance-restricted potions become usable or
-- unusable purely by where you are standing, so the bar rescans on zone
-- change, not just on bag change.
Apotheca.API.RegisterEvents(eventFrame,
    "LFG_ROLE_UPDATE", "ROLE_CHANGED_INFORM", "PLAYER_ROLES_ASSIGNED", "GROUP_ROSTER_UPDATE",
    "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD",
    "BAG_UPDATE_DELAYED", "BAG_UPDATE_COOLDOWN",
    "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED",
    "GET_ITEM_INFO_RECEIVED", "PLAYER_LOGOUT", "PLAYER_TALENT_UPDATE",
    "READY_CHECK", "READY_CHECK_FINISHED", "ZONE_CHANGED_NEW_AREA", "PLAYER_LEVEL_UP",
    "DISABLE_XP_GAIN", "ENABLE_XP_GAIN", "PLAYER_EQUIPMENT_CHANGED", "WEAPON_ENCHANT_CHANGED",
    "EDIT_MODE_LAYOUTS_UPDATED")

-- UNIT_MAXHEALTH / UNIT_MAXPOWER: percentage potions are ranked against the
-- maximum (FindBestPotion), so a Fortitude buff, a level-up or gear can
-- change which potion is best.
Apotheca.API.RegisterUnitEvents(eventFrame, "player",
    "UNIT_HEALTH", "UNIT_POWER_UPDATE", "UNIT_AURA", "UNIT_MAXHEALTH", "UNIT_MAXPOWER")

local recoveryPending      = false
local recoveryElapsed      = 0
local recoveryInterval     = 1.0
local itemInfoPending      = false
local itemInfoElapsed      = 0
local itemInfoInterval     = 1.0
local deferredPending      = false
local deferredElapsed      = 0
local deferredDelay        = 0.2

local deferredSeq = 0
local function RequestUpdate()
    deferredPending = true
    deferredElapsed = 0
    deferredSeq     = Apotheca._updateSeq or 0
end
Apotheca.RequestUpdate = RequestUpdate

-- Which event the Forever role selector fires is not measured, so the
-- role is also re-checked every few seconds out of combat. Cheap: a change
-- is the only thing that costs an update.
local ROLE_POLL = 3
local rolePollElapsed = 0

eventFrame:SetScript("OnUpdate", function(self, elapsed)
    -- The XP food reminder ends: recompute, the ready check may still glow.
    if remindUntil > 0 and GetTime() >= remindUntil then
        remindUntil = 0
        UpdateXPFoodGlow()
        UpdateCoatingGlow()
    end
    if playerReady and not InCombatLockdown() then
        rolePollElapsed = rolePollElapsed + elapsed
        if rolePollElapsed >= ROLE_POLL then
            rolePollElapsed = 0
            Apotheca.RefreshRole()
            -- The matched action bar changed (#40): Edit Mode fires nothing while a
            -- slider moves, and the bar follows it live, so poll it. A
            -- hidden bar lays nothing out: showing it runs a full update.
            if (tonumber(DB().matchBar) or 0) > 0 and ApothecaFrame:IsShown()
                and LayoutSignature((Apotheca.LayoutSettings())) ~= Apotheca._layoutSig then
                RequestUpdate()
                if Apotheca.RefreshOptions then Apotheca.RefreshOptions() end
            end
            -- A stronger item skipped for its cooldown (mana gem) is ready:
            -- re-pick it. Only out of combat, where the button may change.
            if Apotheca._recheckAt and GetTime() >= Apotheca._recheckAt then
                Apotheca._recheckAt = nil
                RequestUpdate()
            end
        end
    end
    if deferredPending and playerReady then
        deferredElapsed = deferredElapsed + elapsed
        if deferredElapsed >= deferredDelay then
            deferredPending = false
            -- A full update since the request already did the work.
            if (Apotheca._updateSeq or 0) == deferredSeq then Apotheca.UpdateAllButtons() end
        end
    end

    if recoveryPending and playerReady then
        recoveryElapsed = recoveryElapsed + elapsed
        if recoveryElapsed >= recoveryInterval then
            recoveryElapsed = 0
            recoveryPending = false
            if not InCombatLockdown() then Apotheca.UpdateAllButtons() end
        end
    end

    if itemInfoPending and playerReady then
        itemInfoElapsed = itemInfoElapsed + elapsed
        if itemInfoElapsed >= itemInfoInterval then
            itemInfoElapsed = 0
            itemInfoPending = false
            Apotheca.UpdateAllButtons()
        end
    end
end)

eventFrame:SetScript("OnEvent", function(self, event, arg1, arg2)
    if event == "ADDON_LOADED" and arg1 == "Apotheca" then
        InitDB()

    elseif event == "PLAYER_LOGIN" then
        -- PLAYER_LOGIN fires after all addons are loaded and the UI is fully ready.
        -- Safe to build the options panel here — no loading-screen crash risk.
        -- DB is already initialised by ADDON_LOADED above.
        Apotheca.CreateOptionsPanel()

        -- No saved settings loaded is a first install, or the client bug
        -- fixed in 70009; the sentinel can't tell them apart.
        -- - Through 69977 it is the bug: say so.
        -- - On the measured build, which loads settings: a first install,
        --   and nothing to say.
        -- - On any other build, the bug may be back: say it may be either.
        local build = Apotheca.API.ClientBuild()
        if not svLoaded and build then
            if build <= Apotheca.API.SV_BROKEN_THROUGH_BUILD then
                print("|cff9966ffApotheca:|r no saved settings were loaded, so defaults are in use. "
                      .. "This client build does not load addon settings.")
            elseif build ~= Apotheca.API.MEASURED_ON_BUILD then
                print("|cff9966ffApotheca:|r no saved settings were loaded. On a first install that's "
                      .. "expected; if your settings were reset, this client build may not load addon settings.")
            end
        end
        ApothecaDB.svLoadCheck = time()

        -- The adapters were measured on one client build. On any other,
        -- say so: the findings behind them may be stale.
        if build and build ~= Apotheca.API.MEASURED_ON_BUILD then
            print("|cff9966ffApotheca:|r this client build (" .. build .. ") is different from "
                  .. "the one Apotheca was tested on (" .. Apotheca.API.MEASURED_ON_BUILD
                  .. "). If something looks wrong, please report it.")
        end

    elseif event == "PLAYER_ENTERING_WORLD" then
        playerReady = true
        ClearTextureCache()
        RestorePosition()
        RequestUpdate()

    elseif event == "PLAYER_TALENT_UPDATE" or event == "ZONE_CHANGED_NEW_AREA" then
        if playerReady then RequestUpdate() end

    elseif event == "BAG_UPDATE_DELAYED" then
        if playerReady then
            -- Tick the stack count down immediately, even during combat
            -- lockdown. The full layout refresh is still deferred via
            -- RequestUpdate() and will run when combat ends.
            Apotheca.RefreshButtonVisuals(true)
            RequestUpdate()
        end

    elseif event == "BAG_UPDATE_COOLDOWN" then
        -- Fires on every item cooldown change, including the 1.5s GCD
        -- that starts the moment you use any item. This is what draws
        -- the swipe animation on mana/health pots etc. Safe in combat.
        if playerReady then
            Apotheca.RefreshButtonVisuals(false)
            -- A cooldown change may make a skipped, stronger item ready.
            if not InCombatLockdown() and Apotheca._recheckAt and GetTime() >= Apotheca._recheckAt then
                Apotheca._recheckAt = nil
                RequestUpdate()
            end
        end

    elseif event == "GET_ITEM_INFO_RECEIVED" then
        if playerReady then
            itemInfoPending = true
            itemInfoElapsed = 0
        end

    elseif event == "UNIT_AURA" then
        -- Registered for "player" only, so the unit needs no test. The
        -- payload (updateInfo) is secret data on this client and is never
        -- touched. In combat every aura read is refused, so the glows are
        -- left as PLAYER_REGEN_DISABLED set them.
        if playerReady and not InCombatLockdown() then
            UpdateBuffFoodGlow()
            UpdateElixirGlow(Apotheca._lastElixRes)
            UpdateScrollGlow()
            UpdateWeaponOilGlow()
            UpdateXPFoodGlow()
            UpdateBandageUsability()
            -- A slot whose buff was running offers nothing; when the buff
            -- expires there is no bag event, so re-resolve. Only when an
            -- elixir buff actually came or went: UNIT_AURA fires for every
            -- aura, and each full update is a bag scan and a layout pass.
            if Apotheca.ElixirBuffStateChanged() then RequestUpdate() end
        end

    elseif event == "READY_CHECK" then
        -- The flag is set even in combat, so a check that outlasts the fight
        -- glows on PLAYER_REGEN_ENABLED. The glow checks are tri-state and
        -- show nothing while auras are unreadable.
        readyCheckActive = true
        if playerReady and not InCombatLockdown() then
            UpdateBuffFoodGlow()
            UpdateElixirGlow(Apotheca._lastElixRes)
            UpdateScrollGlow()
            UpdateWeaponOilGlow()
            UpdateXPFoodGlow()
            UpdateCoatingGlow()
        end

    elseif event == "READY_CHECK_FINISHED" then
        readyCheckActive = false
        HideBuffFoodGlow()
        UpdateElixirGlow(nil)
        UpdateScrollGlow()
        UpdateWeaponOilGlow()
        UpdateXPFoodGlow()
        UpdateCoatingGlow()

    elseif event == "PLAYER_REGEN_DISABLED" then
        HideBuffFoodGlow()
        UpdateElixirGlow(nil)
        UpdateScrollGlow()
        UpdateWeaponOilGlow()
        -- Hide outright, like the other glows: at this event lockdown may not
        -- be engaged yet, so a recompute could still show it for the fight.
        remindPending, remindUntil = false, 0
        HideGlow(Apotheca.buttons["xpfood"])
        for _, cfg in ipairs(COATING_BUTTON_CONFIG) do HideGlow(Apotheca.buttons[cfg.key]) end

    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        -- A weapon swap changes which hands take a poison or which stone
        -- fits (#24, #32). In combat the buttons wait for the update after
        -- combat; a stone that no longer fits greys out meanwhile.
        if playerReady and (arg1 == 16 or arg1 == 17) then
            RequestUpdate()
            if InCombatLockdown() then Apotheca.MarkStaleStones() end
        end

    elseif event == "WEAPON_ENCHANT_CHANGED" then
        -- A coating applied or run out (#24): the poison glows follow.
        if playerReady and not InCombatLockdown() then UpdateCoatingGlow() end

    elseif event == "EDIT_MODE_LAYOUTS_UPDATED" then
        -- A layout saved or switched (#40). Changes still being made in
        -- Edit Mode fire nothing: the out-of-combat poll catches those.
        if playerReady and (tonumber(DB().matchBar) or 0) > 0 then
            RequestUpdate()
            if Apotheca.RefreshOptions then Apotheca.RefreshOptions() end
        end

    elseif event == "PLAYER_LEVEL_UP" or event == "DISABLE_XP_GAIN" or event == "ENABLE_XP_GAIN" then
        -- A new level opens better XP food; the cap, or XP turned off,
        -- hides the button (CanGainXP).
        if playerReady then RequestUpdate() end

    elseif event == "LFG_ROLE_UPDATE" or event == "ROLE_CHANGED_INFORM"
        or event == "PLAYER_ROLES_ASSIGNED" or event == "GROUP_ROSTER_UPDATE" then
        -- Only a change of the RESOLVED role costs an update: these can
        -- come in bursts. In combat the update waits for combat's end.
        if playerReady then Apotheca.RefreshRole() end

    elseif event == "UNIT_MAXHEALTH" or event == "UNIT_MAXPOWER" then
        -- Rare, and each changes which potion is best: one deferred update.
        -- In combat UpdateAllButtons waits; PLAYER_REGEN_ENABLED updates.
        -- The tint does not wait: a new maximum can end "full" mid-fight.
        if playerReady then
            RequestUpdate()
            Apotheca.RefreshFullTint(event == "UNIT_MAXHEALTH" and "health" or "mana")
        end

    elseif event == "UNIT_HEALTH" or event == "UNIT_POWER_UPDATE" then
        -- The full tint follows health and mana live, in combat too. Only
        -- the changed resource's buttons, and only mana among the power
        -- types (a druid's energy or rage ticks change nothing here).
        if playerReady then
            if event == "UNIT_HEALTH" then
                Apotheca.RefreshFullTint("health")
            elseif arg2 == nil or arg2 == "MANA" then
                Apotheca.RefreshFullTint("mana")
            end
        end
        -- Everything this rescan feeds reads health or mana. While both are
        -- secret (always, on 69977), the rescan cannot change anything.
        local missHP, missMana = Apotheca.API.PlayerMissing()
        if playerReady and (missHP ~= nil or missMana ~= nil) then
            recoveryPending = true
            recoveryElapsed = 0
        end

    elseif event == "PLAYER_REGEN_ENABLED" then
        -- Combat ended — reapply secure attributes that were skipped
        -- during lockdown so buttons are immediately clickable.
        for _, btn in pairs(Apotheca.buttons) do
            Apotheca.ApplySecureItemAttributes(btn, btn.itemID)
        end
        -- The XP food reminder waits for this update (UpdateAllButtonsBody).
        remindPending = true
        RequestUpdate()

    elseif event == "PLAYER_LOGOUT" then
        SavePosition()
    end
end)