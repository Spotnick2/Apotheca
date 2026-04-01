-- ============================================================
-- Apotheca - Smart Consumable Bar for WoW Classic TBC
-- Author: Spotnick
-- ============================================================

Apotheca = {}

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
    showOnlyHealingSpec = true,
    lockPosition        = false,
    visibility          = "ALWAYS",
    showEmptyButtons    = false,
    orientation         = "HORIZONTAL",
    rows                = 1,
    iconSize            = 36,
    iconPadding         = 3,
    buffFood = {
        enabled            = true,
        glowOnMissingBuff  = true,
        allowSubstitutions = true,
        strictBestOnly     = false,
    },
    categories = {
        healing = true,
        mp5     = true,
        crit    = true,
        stamina = true,
    },
    -- Ordered stat priority per class (indices 1-4 = slot order)
    buffFoodPriority = {
        PRIEST  = { "healing", "mp5",  "crit", "stamina" },
        PALADIN = { "healing", "crit", "mp5",  "stamina" },
        SHAMAN  = { "healing", "mp5",  "crit", "stamina" },
        DRUID   = { "healing", "mp5",  "crit", "stamina" },
    },
    elixirs = {
        enabled        = true,
        mode           = "AUTO",
        allowLower     = true,
        allowMageblood = true,
    },
    scrolls = {
        enabled           = true,
        spirit            = true,
        protection        = true,
        glowOnMissingBuff = true,
    },
    weaponOil = {
        enabled           = true,
        glowOnMissingBuff = true,
        includeWizardOils = false,
    },
    health = {
        preferHealthstone = true,
    },
    preventWaste        = true,
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
    end
    ApothecaDB.activeProfile = key
    Apotheca.ResetLayout()
    Apotheca.UpdateAllButtons()
    if Apotheca.RefreshOptions then Apotheca.RefreshOptions() end
end

function Apotheca.GetActiveProfileKey()
    return (ApothecaDB and ApothecaDB.activeProfile) or "Global"
end

-- Initialize ApothecaDB on ADDON_LOADED.
-- Wrapped in pcall so a corrupted SavedVariables file never crashes the addon.
local function InitDB()
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
        local safe = { "debug","showOnlyHealingSpec","visibility",
                       "showEmptyButtons","orientation","rows",
                       "iconSize","iconPadding","buffFood","categories",
                       "buffFoodPriority","elixirs","lockPosition","enabled",
                       "preventWaste" }
        for _, k in ipairs(safe) do
            if old[k] ~= nil then
                ApothecaDB.profiles.Global[k] = old[k]
            end
        end
        ApplyDefaults(ApothecaDB.profiles.Global, PROFILE_DEFAULTS)
    end)

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
-- CONTAINER API SHIMS
-- Wraps both C_Container (TBC Anniversary) and legacy globals.
-- Functions never assign nil — safe at parse time.
-- ============================================================

local _CC = C_Container or {}

local function ContainerGetNumSlots(bag)
    if _CC.GetContainerNumSlots then return _CC.GetContainerNumSlots(bag) end
    if GetContainerNumSlots      then return GetContainerNumSlots(bag) end
    return 0
end

local function ContainerGetItemLink(bag, slot)
    if _CC.GetContainerItemLink then return _CC.GetContainerItemLink(bag, slot) end
    if GetContainerItemLink      then return GetContainerItemLink(bag, slot) end
    return nil
end

local function ContainerGetCount(bag, slot)
    if _CC.GetContainerItemInfo then
        local info = _CC.GetContainerItemInfo(bag, slot)
        return info and info.stackCount or 0
    end
    if GetContainerItemInfo then
        local _, count = GetContainerItemInfo(bag, slot)
        return count or 0
    end
    return 0
end

local function SafeGetItemCooldown(itemID)
    if _CC.GetItemCooldown  then return _CC.GetItemCooldown(itemID) end
    if _G.GetItemCooldown   then return _G.GetItemCooldown(itemID) end
    return 0, 0, 0
end

local function GetItemIDFromLink(link)
    if not link then return nil end
    return tonumber(link:match("item:(%d+)"))
end

-- ============================================================
-- TEXTURE CACHE
-- ============================================================

local itemTextureCache = {}
local itemNameCache    = {}

local function GetCachedTexture(itemID)
    if itemTextureCache[itemID] then return itemTextureCache[itemID] end
    local _, _, _, _, _, _, _, _, _, tex = GetItemInfo(itemID)
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

local HEALER_SPEC = {
    -- tabs = talent tree indices to check (any one qualifying = healer)
    -- threshold = minimum points to count as healing spec
    -- For PRIEST: tab 1 = Discipline, tab 2 = Holy
    -- A full Holy Priest will have 0 in Disc and 41+ in Holy — both tabs
    -- are checked so either spec qualifies.
    -- Threshold is kept low (14) to avoid false negatives during respec or
    -- before talents are fully loaded.
    PRIEST  = { tabs = {1, 2}, threshold = 14 },
    PALADIN = { tabs = {2},    threshold = 14 },
    SHAMAN  = { tabs = {3},    threshold = 14 },
    DRUID   = { tabs = {3},    threshold = 14 },
}

-- Healer classes — if talent data is unavailable (returns "" or nil),
-- fall back to showing the bar for any healer-capable class.
local HEALER_CLASSES = { PRIEST = true, PALADIN = true, SHAMAN = true, DRUID = true }

function Apotheca.IsHealerSpec()
    local _, className = UnitClass("player")
    local spec = HEALER_SPEC[className]
    if not spec then return false end   -- not a healer class at all

    local anyTabRead = false
    for _, tabIndex in ipairs(spec.tabs) do
        local _, _, pts = GetTalentTabInfo(tabIndex)
        local n = tonumber(pts)
        if n then
            anyTabRead = true
            if n >= spec.threshold then return true end
        end
    end

    -- If GetTalentTabInfo returned nothing usable (loading screen, fresh login)
    -- fall back to class-only check so the bar isn't hidden by a transient nil.
    if not anyTabRead then
        return HEALER_CLASSES[className] == true
    end

    return false
end

function Apotheca.GetStatPriority()
    local _, className = UnitClass("player")
    local db = DB()
    local p  = db.buffFoodPriority
    if p and p[className] then return p[className] end
    return PROFILE_DEFAULTS.buffFoodPriority[className]
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
-- ============================================================

local MANA_ITEMS     = { 32902, 32903, 32948, 22832, 33093, 13444, 6149 }
local HEALTH_ITEMS   = {
    -- Healthstones first (conjured, always preferred)
    22103,  -- Master Healthstone (rank 3)
    22102,  -- Master Healthstone (rank 2)
    22101,  -- Master Healthstone (rank 1)
    -- Potions
    32947, 22829, 22795, 22797, 13446, 1710,
}
local RUNE_ITEMS     = { 12662, 20520 }
local CONJURED_ITEMS = { 34062, 22895 }

local DRINK_ITEMS = {
    { id = 27860, manaValue = 4800 },
    { id = 28399, manaValue = 3600 },
    { id = 8766,  manaValue = 2400 },
}

local FOOD_ITEMS = {
    { id = 29449, healthValue = 7500 },
    { id = 29450, healthValue = 6966 },
    { id = 27856, healthValue = 4320 },
    { id = 27859, healthValue = 4320 },
    { id = 29451, healthValue = 4320 },
    { id = 8953,  healthValue = 2148 },
    { id = 8952,  healthValue = 2148 },
}

local BUFF_FOOD_BY_STAT = {
    healing = {
        { id = 33052, value = 30 },
        { id = 27666, value = 44 },
        { id = 30357, value = 44 },
        { id = 35565, value = 14 },
    },
    mp5 = {
        { id = 27663, value = 8 },
        { id = 33867, value = 8 },
    },
    crit = {
        { id = 33825, value = 20 },
    },
    spellDmg = {
        { id = 31673, value = 23 },
        { id = 27657, value = 23 },
        { id = 27665, value = 23 },
        { id = 35565, value = 14 },
    },
    stamina = {
        { id = 27667, value = 30 },
        { id = 31672, value = 20 },
        { id = 27660, value = 20 },
        { id = 33053, value = 20 },
        { id = 27663, value = 20 },
    },
    spirit   = {},
    intellect = {},
    hit = {
        { id = 33872, value = 20 },
    },
}

local NETHERGON_ENERGY_ID = 32902
local TEMPEST_KEEP_INSTANCES = {
    ["The Eye"] = true, ["The Mechanar"] = true,
    ["The Botanica"] = true, ["The Arcatraz"] = true,
}

-- ============================================================
-- HEALTHSTONE ITEMS  (highest rank → lowest)
-- ============================================================
local HEALTHSTONE_ITEMS = {
    22103,  -- Master Healthstone (rank 3)
    22102,  -- Master Healthstone (rank 2)
    22101,  -- Master Healthstone (rank 1)
    5512,   -- Major Healthstone  (rank 3)
    5511,   -- Major Healthstone  (rank 2)
    5510,   -- Major Healthstone  (rank 1)
    5509,   -- Greater Healthstone (rank 2)
    5508,   -- Greater Healthstone (rank 1)
    5507,   -- Lesser Healthstone (rank 2)
    5506,   -- Lesser Healthstone (rank 1)
    5175,   -- Healthstone        (rank 2)
    5174,   -- Healthstone        (rank 1)
}

-- ============================================================
-- SCROLL ITEMS  (highest rank → lowest)
-- ============================================================

-- Scroll of Spirit — buff name "Spirit" (applied buff)
local SPIRIT_SCROLL_ITEMS = {
    27498,  -- Scroll of Spirit VI   (TBC, +30 Spirit)
    10306,  -- Scroll of Spirit V    (+20 Spirit)
    6662,   -- Scroll of Spirit IV   (+16 Spirit)
    1712,   -- Scroll of Spirit III  (+12 Spirit)
    1180,   -- Scroll of Spirit II   (+8 Spirit)
    955,    -- Scroll of Spirit I    (+3 Spirit)
}

-- Scroll of Protection — buff name "Scroll of Protection"
local PROTECTION_SCROLL_ITEMS = {
    27492,  -- Scroll of Protection VI   (TBC, +300 Armor)
    10305,  -- Scroll of Protection V    (+240 Armor)
    6661,   -- Scroll of Protection IV   (+180 Armor)
    1711,   -- Scroll of Protection III  (+120 Armor)
    1179,   -- Scroll of Protection II   (+60 Armor)
    954,    -- Scroll of Protection I    (+30 Armor)
}

-- ============================================================
-- WEAPON OIL / COATING ITEMS
-- Blessed Weapon Coating is always top priority.
-- Mana oils are the default set; wizard oils are opt-in.
-- ============================================================
local WEAPON_COATING_ITEMS = {
    23122,  -- Blessed Weapon Coating (Aldor — +60 spell dmg vs undead/demons)
}

local MANA_OIL_ITEMS = {
    22521,  -- Brilliant Mana Oil    (TBC — +12 mp5, +25 healing)
    18628,  -- Brilliant Mana Oil    (Classic version)
    18256,  -- Superior Mana Oil     (+12 mp5)
    20748,  -- Lesser Mana Oil       (+8 mp5)
}

local WIZARD_OIL_ITEMS = {
    22522,  -- Superior Wizard Oil   (TBC — +42 spell power)
    20750,  -- Wizard Oil            (+24 spell power)
    20749,  -- Minor Mana Oil        (+8 mp5)
    20746,  -- Lesser Wizard Oil     (+16 spell power)
}

-- ============================================================
-- ELIXIR / FLASK DATA
-- Each entry: { id = itemID, value = statValue, buff = "Buff Name" }
-- buff is the exact UnitBuff() name — no tooltip parsing.
-- Flask replaces both elixir slots.
-- ============================================================

local ELIXIRS = {
    PRIEST = {
        flask = {
            { id = 22861, value = 25, buff = "Mighty Restoration" },  -- Flask of Mighty Restoration (+25 mp5)
            { id = 13512, value = 10, buff = "Distilled Wisdom"   },  -- Flask of Distilled Wisdom (classic fallback)
        },
        battle = {
            { id = 22825, value = 50, buff = "Healing Power"      },  -- Elixir of Healing Power (+50 healing)
            { id = 28103, value = 24, buff = "Adept's Elixir"     },  -- Adept's Elixir (+24 spell/heal)
        },
        guardian = {
            { id = 32067, value = 30, buff = "Draenic Wisdom"     },  -- Elixir of Draenic Wisdom (+30 int+spi)
            { id = 22840, value = 16, buff = "Major Mageblood"    },  -- Elixir of Major Mageblood (+16 mp5)
        },
    },
    PALADIN = {
        flask = {
            { id = 22861, value = 25, buff = "Mighty Restoration" },
            { id = 13512, value = 10, buff = "Distilled Wisdom"   },
        },
        battle = {
            { id = 22825, value = 50, buff = "Healing Power"      },
            { id = 28103, value = 24, buff = "Adept's Elixir"     },
        },
        guardian = {
            { id = 32067, value = 30, buff = "Draenic Wisdom"     },
            { id = 22840, value = 16, buff = "Major Mageblood"    },
        },
    },
    SHAMAN = {
        flask = {
            { id = 22861, value = 25, buff = "Mighty Restoration" },
        },
        battle = {
            { id = 22825, value = 50, buff = "Healing Power"      },
            { id = 28103, value = 24, buff = "Adept's Elixir"     },
        },
        guardian = {
            { id = 32067, value = 30, buff = "Draenic Wisdom"     },
            { id = 22840, value = 16, buff = "Major Mageblood"    },
        },
    },
    DRUID = {
        flask = {
            { id = 22861, value = 25, buff = "Mighty Restoration" },
        },
        battle = {
            { id = 22825, value = 50, buff = "Healing Power"      },
            { id = 28103, value = 24, buff = "Adept's Elixir"     },
        },
        guardian = {
            { id = 32067, value = 30, buff = "Draenic Wisdom"     },
            { id = 22840, value = 16, buff = "Major Mageblood"    },
        },
    },
}

-- ============================================================
-- BUTTON CONFIGS
-- ============================================================

local STATIC_BUTTON_CONFIG = {
    { key = "mana",   label = "Mana",   list = MANA_ITEMS,   emptyIcon = "Interface\\Icons\\INV_Potion_76",
      emptyTooltip = "No mana potion in bags" },
    { key = "health", label = "Health", list = HEALTH_ITEMS, emptyIcon = "Interface\\Icons\\INV_Potion_54",
      emptyTooltip = "No health potion or healthstone in bags" },
    { key = "rune",   label = "Rune",   list = RUNE_ITEMS,   emptyIcon = "Interface\\Icons\\INV_Misc_Rune_01",
      emptyTooltip = "Rune of Portals / Battle Resurrect — none in bags" },
}

local RECOVERY_BUTTON_CONFIG = {
    { key = "recovery", label = "Recovery", emptyIcon = "Interface\\Icons\\INV_Misc_Food_15" },
    { key = "food",     label = "Food",     emptyIcon = "Interface\\Icons\\INV_Misc_Food_01" },
    { key = "drink",    label = "Drink",    emptyIcon = "Interface\\Icons\\INV_Drink_05"     },
}

local BUFFFOOD_BUTTON_CONFIG = {
    key = "bufffood", label = "Buff Food", emptyIcon = "Interface\\Icons\\INV_Misc_Food_64",
}

local ELIXIR_BUTTON_CONFIG = {
    { key = "flask",    label = "Flask",    emptyIcon = "Interface\\Icons\\INV_Potion_97"  },
    { key = "battle",   label = "Battle",   emptyIcon = "Interface\\Icons\\INV_Potion_51"  },
    { key = "guardian", label = "Guardian", emptyIcon = "Interface\\Icons\\INV_Potion_Forsaken_01" },
}

local SCROLL_BUTTON_CONFIG = {
    { key = "spiritscroll",     label = "Spirit",     emptyIcon = "Interface\\Icons\\INV_Scroll_03" },
    { key = "protectionscroll", label = "Protection", emptyIcon = "Interface\\Icons\\INV_Scroll_06" },
}

local WEAPONOIL_BUTTON_CONFIG = {
    key = "weaponoil", label = "Weapon Oil", emptyIcon = "Interface\\Icons\\INV_Potion_95",
}

-- ============================================================
-- RESOLUTION FUNCTIONS
-- ============================================================

function Apotheca.BuildBagMap()
    local bagMap = {}
    for bag = 0, 4 do
        local numSlots = ContainerGetNumSlots(bag)
        for slot = 1, numSlots do
            local link = ContainerGetItemLink(bag, slot)
            local id   = GetItemIDFromLink(link)
            if id then
                local count = ContainerGetCount(bag, slot)
                if count > 0 then
                    bagMap[id] = (bagMap[id] or 0) + count
                end
            end
        end
    end
    return bagMap
end

function Apotheca.FindBestItem(list, bagMap)
    local inTK = TEMPEST_KEEP_INSTANCES[GetInstanceInfo()] == true
    for _, id in ipairs(list) do
        if id ~= NETHERGON_ENERGY_ID or inTK then
            local count = bagMap[id]
            if count and count > 0 then
                return id, count, GetCachedTexture(id)
            end
        end
    end
    return nil, 0, nil
end

function Apotheca.FindBestFood(bagMap, missingHP)
    missingHP = missingHP or 0
    local available = {}
    for _, entry in ipairs(FOOD_ITEMS) do
        local count = bagMap[entry.id]
        if count and count > 0 then
            available[#available + 1] = { id = entry.id, healthValue = entry.healthValue, count = count }
        end
    end
    if #available == 0 then return nil, 0, nil end

    local chosen
    if missingHP > 0 then
        local bestSuff = nil
        for i = #available, 1, -1 do
            local e = available[i]
            if e.healthValue >= missingHP then
                if not bestSuff or e.healthValue < bestSuff.healthValue
                or (e.healthValue == bestSuff.healthValue and e.count < bestSuff.count) then
                    bestSuff = e
                end
            end
        end
        chosen = bestSuff or available[1]
    else
        local bestVal = -1
        for _, e in ipairs(available) do
            if e.healthValue > bestVal
            or (e.healthValue == bestVal and chosen and e.count < chosen.count) then
                bestVal = e.healthValue
                chosen  = e
            end
        end
    end

    if chosen then
        return chosen.id, chosen.count, GetCachedTexture(chosen.id)
    end
    return nil, 0, nil
end

function Apotheca.FindBestBuffFood(bagMap)
    local db       = DB()
    local bf       = db.buffFood
    if not bf or not bf.enabled then return nil, 0, nil end

    local priority   = Apotheca.GetStatPriority()
    if not priority then return nil, 0, nil end

    local categories = db.categories or PROFILE_DEFAULTS.categories
    local strict     = bf.strictBestOnly

    local function scanCategory(statKey)
        local entries = BUFF_FOOD_BY_STAT[statKey]
        if not entries or #entries == 0 then return nil, 0, nil end
        if categories[statKey] == false then return nil, 0, nil end

        local bestID, bestVal, bestCount = nil, -1, 0
        local globalBestVal = -1
        for _, entry in ipairs(entries) do
            if entry.value > globalBestVal then globalBestVal = entry.value end
            local count = bagMap[entry.id]
            if count and count > 0 and entry.value > bestVal then
                bestVal   = entry.value
                bestID    = entry.id
                bestCount = count
            end
        end
        if not bestID then return nil, 0, nil end
        if strict and bestVal < globalBestVal then return nil, 0, nil end
        return bestID, bestCount, GetCachedTexture(bestID)
    end

    for _, statKey in ipairs(priority) do
        local id, count, tex = scanCategory(statKey)
        if id then return id, count, tex end
    end

    -- allowSubstitutions fallback: retry without strict
    if strict and bf.allowSubstitutions then
        for _, statKey in ipairs(priority) do
            local entries = BUFF_FOOD_BY_STAT[statKey]
            if entries and categories[statKey] ~= false then
                local bestID, bestVal, bestCount = nil, -1, 0
                for _, entry in ipairs(entries) do
                    local count = bagMap[entry.id]
                    if count and count > 0 and entry.value > bestVal then
                        bestVal   = entry.value
                        bestID    = entry.id
                        bestCount = count
                    end
                end
                if bestID then return bestID, bestCount, GetCachedTexture(bestID) end
            end
        end
    end

    return nil, 0, nil
end

function Apotheca.HasFoodBuff()
    local i = 1
    while true do
        local name = UnitBuff("player", i)
        if not name then break end
        if name == "Well Fed" then return true end
        i = i + 1
    end
    return false
end

-- ============================================================
-- HEALTH CONSUMABLE — healthstone priority over potions
-- ============================================================

function Apotheca.FindBestHealthConsumable(bagMap)
    -- Healthstones are conjured — always prefer them over potions
    for _, id in ipairs(HEALTHSTONE_ITEMS) do
        local count = bagMap[id]
        if count and count > 0 then
            return id, count, GetCachedTexture(id)
        end
    end
    -- Fall back to healing potions
    return Apotheca.FindBestItem(HEALTH_ITEMS, bagMap)
end

-- ============================================================
-- SCROLL HELPERS
-- ============================================================

-- Simple highest-first scan from an ordered item list.
function Apotheca.FindBestScroll(list, bagMap)
    for _, id in ipairs(list) do
        local count = bagMap[id]
        if count and count > 0 then
            return id, count, GetCachedTexture(id)
        end
    end
    return nil, 0, nil
end

-- Check if the player has a Spirit buff (Divine Spirit or scroll-applied spirit).
-- We check for both the priest spell buff and the scroll buff name.
function Apotheca.HasSpiritBuff()
    local i = 1
    while true do
        local name = UnitBuff("player", i)
        if not name then break end
        if name == "Divine Spirit" or name == "Prayer of Spirit"
        or name == "Scroll of Spirit" or name == "Spirit" then
            return true
        end
        i = i + 1
    end
    return false
end

-- Check if the player has the Devotion Aura or a protection scroll buff.
function Apotheca.HasProtectionScrollBuff()
    local i = 1
    while true do
        local name = UnitBuff("player", i)
        if not name then break end
        if name == "Scroll of Protection" or name == "Armor" then
            return true
        end
        i = i + 1
    end
    return false
end

-- ============================================================
-- WEAPON OIL HELPERS
-- ============================================================

-- Returns true if main hand has any temporary enchant active.
function Apotheca.HasMainHandTempEnchant()
    local hasMainHandEnchant = GetWeaponEnchantInfo()
    return hasMainHandEnchant == true or hasMainHandEnchant == 1
end

function Apotheca.FindBestWeaponOil(bagMap)
    -- Blessed Weapon Coating always first
    for _, id in ipairs(WEAPON_COATING_ITEMS) do
        local count = bagMap[id]
        if count and count > 0 then
            return id, count, GetCachedTexture(id)
        end
    end
    -- Mana oils
    for _, id in ipairs(MANA_OIL_ITEMS) do
        local count = bagMap[id]
        if count and count > 0 then
            return id, count, GetCachedTexture(id)
        end
    end
    -- Wizard oils (only if enabled in config)
    local db = DB()
    if db.weaponOil and db.weaponOil.includeWizardOils then
        for _, id in ipairs(WIZARD_OIL_ITEMS) do
            local count = bagMap[id]
            if count and count > 0 then
                return id, count, GetCachedTexture(id)
            end
        end
    end
    return nil, 0, nil
end

-- ============================================================
-- ELIXIR BUFF DETECTION
-- Scans UnitBuff for known flask/battle/guardian buff names.
-- Returns separate flags rather than one combined check so the
-- glow system can highlight individual missing slots.
-- ============================================================

local function GetPlayerElixirData()
    local _, className = UnitClass("player")
    return ELIXIRS[className]
end

-- Build a set of active buff names for quick lookup.
local function GetActiveBoneSet()
    local active = {}
    local i = 1
    while true do
        local name = UnitBuff("player", i)
        if not name then break end
        active[name] = true
        i = i + 1
    end
    return active
end

-- Check if any entry's buff is active.  Tries the stored name first,
-- then common prefixed variants ("Elixir of X", "Flask of X") so the
-- detection works regardless of whether UnitBuff returns the short or
-- long form.
local function HasBuffFromList(list, active)
    for _, entry in ipairs(list) do
        if active[entry.buff]
        or active["Elixir of " .. entry.buff]
        or active["Flask of "  .. entry.buff] then
            return true
        end
    end
    return false
end

function Apotheca.HasFlaskBuff()
    local data = GetPlayerElixirData()
    if not data then return false end
    return HasBuffFromList(data.flask, GetActiveBoneSet())
end

function Apotheca.HasBattleElixirBuff()
    local data = GetPlayerElixirData()
    if not data then return false end
    return HasBuffFromList(data.battle, GetActiveBoneSet())
end

function Apotheca.HasGuardianElixirBuff()
    local data = GetPlayerElixirData()
    if not data then return false end
    return HasBuffFromList(data.guardian, GetActiveBoneSet())
end

-- Pick the highest-value item from an elixir list that exists in bagMap.
local function BestElixirItem(list, bagMap)
    local bestID, bestVal, bestCount = nil, -1, 0
    for _, entry in ipairs(list) do
        local count = bagMap[entry.id]
        if count and count > 0 and entry.value > bestVal then
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
--   mode         = "flask" | "elixirs" | "none"
--   flaskID, flaskCount, flaskTex
--   battleID, battleCount, battleTex
--   guardianID, guardianCount, guardianTex
--   hasFlask, hasBattle, hasGuardian   (active buff flags)
-- }
function Apotheca.ResolveElixirs(bagMap)
    local result = {
        mode        = "none",
        flaskID     = nil, flaskCount   = 0, flaskTex    = nil,
        battleID    = nil, battleCount  = 0, battleTex   = nil,
        guardianID  = nil, guardianCount = 0, guardianTex = nil,
        hasFlask    = false, hasBattle  = false, hasGuardian = false,
    }

    local data = GetPlayerElixirData()
    if not data then return result end

    result.hasFlask   = Apotheca.HasFlaskBuff()
    result.hasBattle  = Apotheca.HasBattleElixirBuff()
    result.hasGuardian = Apotheca.HasGuardianElixirBuff()

    -- If flask buff is active, nothing to suggest
    if result.hasFlask then return result end

    -- Check what's available in bags
    local fID, fCnt, fTex = BestElixirItem(data.flask,   bagMap)
    local bID, bCnt, bTex = BestElixirItem(data.battle,  bagMap)
    local gID, gCnt, gTex = BestElixirItem(data.guardian, bagMap)

    -- Prefer flask if available and no individual elixir buffs are active
    if fID and not result.hasBattle and not result.hasGuardian then
        result.mode      = "flask"
        result.flaskID   = fID
        result.flaskCount = fCnt
        result.flaskTex  = fTex
        return result
    end

    -- Otherwise show individual elixir slots
    if bID or gID then
        result.mode        = "elixirs"
        result.battleID    = bID  ; result.battleCount   = bCnt  ; result.battleTex   = bTex
        result.guardianID  = gID  ; result.guardianCount = gCnt  ; result.guardianTex = gTex
    end

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
    }

    local conjID, conjCount, conjTex = Apotheca.FindBestItem(CONJURED_ITEMS, bagMap)
    if conjID then
        result.mode           = "conjured"
        result.conjuredID     = conjID
        result.conjuredCount  = conjCount
        result.conjuredTexture = conjTex
        return result
    end

    local hpMax   = UnitHealthMax("player") or 0
    local hp      = UnitHealth("player")    or 0
    local manaMax = UnitPowerMax("player")  or 0
    local mana    = UnitPower("player")     or 0
    local missingHP   = hpMax   > 0 and (hpMax   - hp)   or 0
    local missingMana = manaMax > 0 and (manaMax - mana) or 0

    local debug   = DB().debug
    local showFood  = (not Apotheca.hideWhenFull) or missingHP   > 0 or debug
    local showDrink = (not Apotheca.hideWhenFull) or missingMana > 0 or debug

    if showFood then
        local id, cnt, tex = Apotheca.FindBestFood(bagMap, missingHP)
        result.foodID = id ; result.foodCount = cnt ; result.foodTexture = tex
    end

    if showDrink then
        local dID, dCnt, dTex = nil, 0, nil
        if Apotheca.waterSmartMode and missingMana > 0 then
            local bestAvail, bestSuff = nil, nil
            for _, e in ipairs(DRINK_ITEMS) do
                if bagMap[e.id] and bagMap[e.id] > 0 then
                    if not bestAvail then bestAvail = e end
                    if e.manaValue >= missingMana then bestSuff = e end
                end
            end
            local chosen = bestSuff or bestAvail
            if chosen then
                dID  = chosen.id
                dCnt = bagMap[chosen.id]
                dTex = GetCachedTexture(chosen.id)
            end
        else
            for _, e in ipairs(DRINK_ITEMS) do
                if bagMap[e.id] and bagMap[e.id] > 0 then
                    dID  = e.id
                    dCnt = bagMap[e.id]
                    dTex = GetCachedTexture(e.id)
                    break
                end
            end
        end
        result.drinkID = dID ; result.drinkCount = dCnt ; result.drinkTexture = dTex
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

local function UpdateBuffFoodGlow()
    local btn = Apotheca.buttons["bufffood"]
    if not btn then return end
    local db  = DB()
    local glowEnabled = db.buffFood and db.buffFood.glowOnMissingBuff
    if readyCheckActive and glowEnabled and btn.itemID and not Apotheca.HasFoodBuff() then
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

    if elixRes.mode == "flask" then
        -- Glow flask button if we have one but the flask buff isn't active
        if elixRes.flaskID and not elixRes.hasFlask then
            ShowGlow(Apotheca.buttons["flask"])
        else
            HideGlow(Apotheca.buttons["flask"])
        end
        HideGlow(Apotheca.buttons["battle"])
        HideGlow(Apotheca.buttons["guardian"])
    elseif elixRes.mode == "elixirs" then
        HideGlow(Apotheca.buttons["flask"])
        -- Glow each slot independently if buff missing and item available
        if elixRes.battleID and not elixRes.hasBattle then
            ShowGlow(Apotheca.buttons["battle"])
        else
            HideGlow(Apotheca.buttons["battle"])
        end
        if elixRes.guardianID and not elixRes.hasGuardian then
            ShowGlow(Apotheca.buttons["guardian"])
        else
            HideGlow(Apotheca.buttons["guardian"])
        end
    else
        HideGlow(Apotheca.buttons["flask"])
        HideGlow(Apotheca.buttons["battle"])
        HideGlow(Apotheca.buttons["guardian"])
    end
end

local function UpdateScrollGlow()
    local db = DB()
    local glowEnabled = db.scrolls and db.scrolls.glowOnMissingBuff

    local spiritBtn = Apotheca.buttons["spiritscroll"]
    if spiritBtn then
        if readyCheckActive and glowEnabled and spiritBtn.itemID and not Apotheca.HasSpiritBuff() then
            ShowGlow(spiritBtn)
        else
            HideGlow(spiritBtn)
        end
    end

    local protBtn = Apotheca.buttons["protectionscroll"]
    if protBtn then
        if readyCheckActive and glowEnabled and protBtn.itemID and not Apotheca.HasProtectionScrollBuff() then
            ShowGlow(protBtn)
        else
            HideGlow(protBtn)
        end
    end
end

local function UpdateWeaponOilGlow()
    local db  = DB()
    local btn = Apotheca.buttons["weaponoil"]
    if not btn then return end
    local glowEnabled = db.weaponOil and db.weaponOil.glowOnMissingBuff
    if readyCheckActive and glowEnabled and btn.itemID and not Apotheca.HasMainHandTempEnchant() then
        ShowGlow(btn)
    else
        HideGlow(btn)
    end
end

local function CalcFrameWidth(n)
    return FRAME_PADDING * 2 + n * BUTTON_SIZE + (n - 1) * BUTTON_GAP
end

-- Resize and reposition all active buttons according to orientation and rows.
-- Horizontal: buttons flow left→right, wrap into rows.
-- Vertical:   buttons flow top→bottom, wrap into columns.
local function ApplyLayout(active)
    local db          = DB()
    local orientation = db.orientation or "HORIZONTAL"
    local rows        = math.max(1, db.rows or 1)
    local btnSize     = math.max(16, db.iconSize    or BUTTON_SIZE)
    local btnGap      = math.max(0,  db.iconPadding or BUTTON_GAP)
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

anchor:SetScript("OnDragStart", function()
    if not InCombatLockdown() and not DB().lockPosition then
        ApothecaFrame:StartMoving()
    end
end)
anchor:SetScript("OnDragStop", function()
    ApothecaFrame:StopMovingOrSizing()
    SavePosition()
end)
anchor:SetScript("OnMouseDown", function(self, button)
    -- Swallow clicks so they don't reach secure buttons below
end)

local anchorDragging = false
anchor:HookScript("OnDragStart", function() anchorDragging = true end)
anchor:HookScript("OnDragStop",  function() anchorDragging = false end)

local modFrame = CreateFrame("Frame")
modFrame:RegisterEvent("MODIFIER_STATE_CHANGED")
modFrame:SetScript("OnEvent", function(_, _, key, down)
    if key ~= "LALT" and key ~= "RALT" then return end
    if down == 1 and not InCombatLockdown() and not DB().lockPosition
       and ApothecaFrame:IsVisible() and ApothecaFrame:IsMouseOver() then
        anchor:Show()
    else
        if not anchorDragging then
            anchor:Hide()
        end
        -- If we're mid-drag and alt is released, finish the drag
        if anchorDragging then
            ApothecaFrame:StopMovingOrSizing()
            SavePosition()
            anchorDragging = false
            anchor:Hide()
        end
    end
end)

-- ============================================================
-- SECURE ATTRIBUTE MANAGEMENT
-- All writes to btn "type"/"item" attributes go through this
-- single function. Never write them directly anywhere else.
-- ============================================================

function Apotheca.ApplySecureItemAttributes(btn, itemID)
    if InCombatLockdown() then return end
    if DB().debug then
        btn:SetAttribute("type", nil)
        btn:SetAttribute("item", nil)
        return
    end
    if itemID then
        -- Use "item:ID" format — bypasses item-name cache entirely and is the
        -- most reliable identifier for SecureActionButtonTemplate in Classic.
        btn:SetAttribute("type", "item")
        btn:SetAttribute("item", "item:" .. itemID)
    else
        btn:SetAttribute("type", nil)
        btn:SetAttribute("item", nil)
    end
end

local function ApplyDebugAttributes(btn)
    -- Delegates entirely to the centralized helper using the button's current itemID.
    Apotheca.ApplySecureItemAttributes(btn, btn.itemID)
end

local function CreateApothecaButton(cfg)
    local btn = CreateFrame("Button", "ApothecaButton_" .. cfg.key, ApothecaFrame, "SecureActionButtonTemplate")
    btn:SetWidth(BUTTON_SIZE)
    btn:SetHeight(BUTTON_SIZE)
    btn:RegisterForClicks("AnyDown", "AnyUp")
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

    local border = btn:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Buttons\\UI-Quickslot-Depress")
    border:SetAllPoints(btn)
    btn.btnBorder = border
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
Apotheca.buttons["bufffood"]  = CreateApothecaButton(BUFFFOOD_BUTTON_CONFIG)
Apotheca.buttons["weaponoil"] = CreateApothecaButton(WEAPONOIL_BUTTON_CONFIG)

-- ============================================================
-- LAYOUT
-- ============================================================

local currentRecoveryMode = nil
local currentElixirMode   = nil

-- RefreshLayout builds the active button list and positions everything.
-- staticFlags = table keyed by button key → true if that slot should appear
-- scrollFlags = { spirit=bool, protection=bool, oil=bool, food=bool }
local function RefreshLayout(recoveryMode, elixirMode, staticFlags, scrollFlags)
    currentRecoveryMode = recoveryMode
    currentElixirMode   = elixirMode

    local active = {}

    -- ── Core: static slots (only if visible) ───────────────────
    for _, cfg in ipairs(STATIC_BUTTON_CONFIG) do
        if not staticFlags or staticFlags[cfg.key] then
            active[#active + 1] = cfg.key
        end
    end

    -- ── Recovery ────────────────────────────────────────────────
    if recoveryMode == "conjured" then
        active[#active + 1] = "recovery"
    elseif recoveryMode == "split" then
        active[#active + 1] = "food"
        active[#active + 1] = "drink"
    end

    -- ── Elixirs / Flask ─────────────────────────────────────────
    if elixirMode == "flask" then
        active[#active + 1] = "flask"
    elseif elixirMode == "elixirs" then
        active[#active + 1] = "battle"
        active[#active + 1] = "guardian"
    end

    -- ── Buff food ────────────────────────────────────────────────
    if scrollFlags and scrollFlags.food then
        active[#active + 1] = "bufffood"
    end

    -- ── Scrolls (last, after core buttons) ──────────────────────
    if scrollFlags and scrollFlags.spirit then
        active[#active + 1] = "spiritscroll"
    end
    if scrollFlags and scrollFlags.protection then
        active[#active + 1] = "protectionscroll"
    end

    -- ── Weapon oil (very last) ───────────────────────────────────
    if scrollFlags and scrollFlags.oil then
        active[#active + 1] = "weaponoil"
    end

    ApplyLayout(active)

    -- Hide all managed buttons not in active list
    local activeSet = {}
    for _, k in ipairs(active) do activeSet[k] = true end
    -- Static buttons
    for _, cfg in ipairs(STATIC_BUTTON_CONFIG) do
        if not activeSet[cfg.key] then Apotheca.buttons[cfg.key]:Hide() end
    end
    -- Dynamic buttons
    for _, k in ipairs({ "recovery", "food", "drink", "flask", "battle", "guardian",
                         "bufffood", "spiritscroll", "protectionscroll", "weaponoil" }) do
        if not activeSet[k] then Apotheca.buttons[k]:Hide() end
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
        local st, dur = SafeGetItemCooldown(itemID)
        if st and dur and dur > 0 then
            btn.cooldown:SetCooldown(st, dur)
        else
            btn.cooldown:SetCooldown(0, 0)
        end
    else
        btn.countText:SetText("")
        btn.cooldown:SetCooldown(0, 0)
        if db.debug then
            btn.icon:SetTexture(btn.cfg.emptyIcon)
            btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            btn.icon:SetDesaturated(true)
            btn.icon:Show()
            btn.emptyBg:SetAlpha(0.6)
        else
            btn.icon:SetTexture(nil)
            btn.icon:SetDesaturated(false)
            btn.icon:Hide()
            btn.emptyBg:SetAlpha(0.6)
        end
    end
end

-- ============================================================
-- MAIN UPDATE
-- ============================================================

function Apotheca.UpdateAllButtons()
    local db = DB()

    if db.enabled == false then
        ApothecaFrame:Hide()
        return
    end

    local specOk = (not db.showOnlyHealingSpec) or Apotheca.IsHealerSpec()
    if not specOk or not Apotheca.IsVisible() then
        ApothecaFrame:Hide()
        return
    end
    ApothecaFrame:Show()

    if db.debug then debugLabel:Show() else debugLabel:Hide() end

    local showEmpty = db.showEmptyButtons or db.debug
    local bagMap    = Apotheca.BuildBagMap()

    -- ── Static slots ─────────────────────────────────────────────
    local staticFlags = {}
    for _, cfg in ipairs(STATIC_BUTTON_CONFIG) do
        local btn = Apotheca.buttons[cfg.key]
        local id, cnt, tex
        if cfg.key == "health" then
            id, cnt, tex = Apotheca.FindBestHealthConsumable(bagMap)
        else
            id, cnt, tex = Apotheca.FindBestItem(cfg.list, bagMap)
        end
        ApplyItemToButton(btn, id, cnt, tex)
        local show = id ~= nil or showEmpty
        staticFlags[cfg.key] = show
        if show then btn:Show() else btn:Hide() end
    end

    -- ── Recovery + Elixirs ───────────────────────────────────────
    local rec     = ResolveRecovery(bagMap)
    local elixRes = Apotheca.ResolveElixirs(bagMap)

    local recovMode
    if rec.mode == "conjured" then
        recovMode = "conjured"
    elseif rec.foodID or rec.drinkID or showEmpty then
        recovMode = "split"
    else
        recovMode = "none"
    end

    local elixMode
    if elixRes.mode == "flask" then
        elixMode = "flask"
    elseif elixRes.battleID or elixRes.guardianID or showEmpty then
        elixMode = "elixirs"
    else
        elixMode = "none"
    end

    -- ── Scrolls ──────────────────────────────────────────────────
    local scrollsDB  = db.scrolls
    local scrollsOn  = not scrollsDB or scrollsDB.enabled
    local spiritID,  spiritCnt,  spiritTex
    local protID,    protCnt,    protTex
    if scrollsOn then
        if not scrollsDB or scrollsDB.spirit then
            spiritID, spiritCnt, spiritTex = Apotheca.FindBestScroll(SPIRIT_SCROLL_ITEMS, bagMap)
        end
        if not scrollsDB or scrollsDB.protection then
            protID, protCnt, protTex = Apotheca.FindBestScroll(PROTECTION_SCROLL_ITEMS, bagMap)
        end
    end

    -- ── Weapon oil ───────────────────────────────────────────────
    local oilID, oilCnt, oilTex
    if not db.weaponOil or db.weaponOil.enabled then
        oilID, oilCnt, oilTex = Apotheca.FindBestWeaponOil(bagMap)
    end

    -- ── Buff food ────────────────────────────────────────────────
    local buffFoodID, buffFoodCnt, buffFoodTex
    if db.buffFood and db.buffFood.enabled then
        buffFoodID, buffFoodCnt, buffFoodTex = Apotheca.FindBestBuffFood(bagMap)
    end

    -- ── Build layout flags — only include a slot if it has content (or showEmpty) ──
    local flags = {
        food        = (buffFoodID ~= nil)          or (db.buffFood and db.buffFood.enabled and showEmpty),
        spirit      = (spiritID   ~= nil)          or (scrollsOn   and (not scrollsDB or scrollsDB.spirit)   and showEmpty),
        protection  = (protID     ~= nil)          or (scrollsOn   and (not scrollsDB or scrollsDB.protection) and showEmpty),
        oil         = (oilID      ~= nil)          or ((not db.weaponOil or db.weaponOil.enabled) and showEmpty),
    }

    RefreshLayout(recovMode, elixMode, staticFlags, flags)

    -- ── Apply button contents ────────────────────────────────────
    if recovMode == "conjured" then
        ApplyItemToButton(Apotheca.buttons["recovery"], rec.conjuredID, rec.conjuredCount, rec.conjuredTexture)
    elseif recovMode == "split" then
        ApplyItemToButton(Apotheca.buttons["food"],  rec.foodID,  rec.foodCount,  rec.foodTexture)
        ApplyItemToButton(Apotheca.buttons["drink"], rec.drinkID, rec.drinkCount, rec.drinkTexture)
        if not (rec.foodID  or showEmpty) then Apotheca.buttons["food"]:Hide()  end
        if not (rec.drinkID or showEmpty) then Apotheca.buttons["drink"]:Hide() end
    end

    if elixMode == "flask" then
        ApplyItemToButton(Apotheca.buttons["flask"], elixRes.flaskID, elixRes.flaskCount, elixRes.flaskTex)
    elseif elixMode == "elixirs" then
        ApplyItemToButton(Apotheca.buttons["battle"],   elixRes.battleID,   elixRes.battleCount,   elixRes.battleTex)
        ApplyItemToButton(Apotheca.buttons["guardian"], elixRes.guardianID, elixRes.guardianCount, elixRes.guardianTex)
        if not (elixRes.battleID   or showEmpty) then Apotheca.buttons["battle"]:Hide()   end
        if not (elixRes.guardianID or showEmpty) then Apotheca.buttons["guardian"]:Hide() end
    end

    if flags.food then
        ApplyItemToButton(Apotheca.buttons["bufffood"], buffFoodID, buffFoodCnt, buffFoodTex)
    end
    if flags.spirit then
        ApplyItemToButton(Apotheca.buttons["spiritscroll"], spiritID, spiritCnt, spiritTex)
    end
    if flags.protection then
        ApplyItemToButton(Apotheca.buttons["protectionscroll"], protID, protCnt, protTex)
    end
    if flags.oil then
        ApplyItemToButton(Apotheca.buttons["weaponoil"], oilID, oilCnt, oilTex)
    end

    -- ── Waste prevention ──────────────────────────────────────────
    -- When enabled, disable recovery food/drink buttons if the player
    -- is already at full HP or mana. Buff food is excluded — you eat
    -- that for the Well Fed buff, not for the HP.
    if db.preventWaste ~= false and not db.debug and not InCombatLockdown() then
        local hpFull   = (UnitHealth("player") or 0) >= (UnitHealthMax("player") or 1)
        local manaFull = (UnitPower("player")  or 0) >= (UnitPowerMax("player")  or 1)

        local function DisableButton(btn)
            if not btn or not btn.itemID then return end
            btn:SetAttribute("type", nil)
            btn:SetAttribute("item", nil)
            btn.icon:SetDesaturated(true)
        end

        if recovMode == "conjured" and hpFull and manaFull then
            DisableButton(Apotheca.buttons["recovery"])
        elseif recovMode == "split" then
            if hpFull   then DisableButton(Apotheca.buttons["food"])  end
            if manaFull then DisableButton(Apotheca.buttons["drink"]) end
        end
    end

    UpdateBuffFoodGlow()
    UpdateElixirGlow(elixRes)
    UpdateScrollGlow()
    UpdateWeaponOilGlow()
    Apotheca._lastElixRes = elixRes
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
function Apotheca.ResetLayout()
    currentRecoveryMode = nil
    currentElixirMode   = nil
end

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
        end
    end
end

-- ============================================================
-- EVENTS
-- ============================================================

local playerReady = false

local eventFrame = CreateFrame("Frame", "ApothecaEventFrame", UIParent)
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("BAG_UPDATE_DELAYED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
eventFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
eventFrame:RegisterEvent("PLAYER_LOGOUT")
eventFrame:RegisterEvent("PLAYER_TALENT_UPDATE")
eventFrame:RegisterEvent("READY_CHECK")
eventFrame:RegisterEvent("READY_CHECK_FINISHED")

if eventFrame.RegisterUnitEvent then
    eventFrame:RegisterUnitEvent("UNIT_HEALTH",       "player")
    eventFrame:RegisterUnitEvent("UNIT_POWER_UPDATE", "player")
    eventFrame:RegisterUnitEvent("UNIT_AURA",         "player")
else
    eventFrame:RegisterEvent("UNIT_HEALTH")
    eventFrame:RegisterEvent("UNIT_POWER_UPDATE")
    eventFrame:RegisterEvent("UNIT_AURA")
end

local recoveryPending      = false
local recoveryElapsed      = 0
local recoveryInterval     = 1.0
local itemInfoPending      = false
local itemInfoElapsed      = 0
local itemInfoInterval     = 1.0
local deferredPending      = false
local deferredElapsed      = 0
local deferredDelay        = 0.2

local function RequestUpdate()
    deferredPending = true
    deferredElapsed = 0
end

eventFrame:SetScript("OnUpdate", function(self, elapsed)
    if deferredPending and playerReady then
        deferredElapsed = deferredElapsed + elapsed
        if deferredElapsed >= deferredDelay then
            deferredPending = false
            Apotheca.UpdateAllButtons()
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

eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == "Apotheca" then
        InitDB()

    elseif event == "PLAYER_LOGIN" then
        -- PLAYER_LOGIN fires after all addons are loaded and the UI is fully ready.
        -- Safe to build the options panel here — no loading-screen crash risk.
        -- DB is already initialised by ADDON_LOADED above.
        Apotheca.CreateOptionsPanel()

    elseif event == "PLAYER_ENTERING_WORLD" then
        playerReady = true
        ClearTextureCache()
        RestorePosition()
        RequestUpdate()

    elseif event == "PLAYER_TALENT_UPDATE" then
        if playerReady then RequestUpdate() end

    elseif event == "BAG_UPDATE_DELAYED" then
        if playerReady then RequestUpdate() end

    elseif event == "GET_ITEM_INFO_RECEIVED" then
        if playerReady then
            itemInfoPending = true
            itemInfoElapsed = 0
        end

    elseif event == "UNIT_AURA" then
        if (arg1 == "player" or arg1 == nil) and playerReady then
            UpdateBuffFoodGlow()
            UpdateElixirGlow(Apotheca._lastElixRes)
            UpdateScrollGlow()
            UpdateWeaponOilGlow()
        end

    elseif event == "READY_CHECK" then
        if playerReady then
            readyCheckActive = true
            UpdateBuffFoodGlow()
            UpdateElixirGlow(Apotheca._lastElixRes)
            UpdateScrollGlow()
            UpdateWeaponOilGlow()
        end

    elseif event == "READY_CHECK_FINISHED" then
        readyCheckActive = false
        HideBuffFoodGlow()
        UpdateElixirGlow(nil)
        UpdateScrollGlow()
        UpdateWeaponOilGlow()

    elseif event == "PLAYER_REGEN_DISABLED" then
        HideBuffFoodGlow()
        UpdateElixirGlow(nil)
        UpdateScrollGlow()
        UpdateWeaponOilGlow()

    elseif event == "UNIT_HEALTH" or event == "UNIT_POWER_UPDATE" then
        if (arg1 == "player" or arg1 == nil) and playerReady then
            recoveryPending = true
            recoveryElapsed = 0
        end

    elseif event == "PLAYER_REGEN_ENABLED" then
        -- Combat ended — reapply secure attributes that were skipped
        -- during lockdown so buttons are immediately clickable.
        for _, btn in pairs(Apotheca.buttons) do
            Apotheca.ApplySecureItemAttributes(btn, btn.itemID)
        end
        RequestUpdate()

    elseif event == "PLAYER_LOGOUT" then
        SavePosition()
    end
end)