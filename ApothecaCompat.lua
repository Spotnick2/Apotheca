-- ============================================================
-- Apotheca - WoW: Forever compatibility layer
--
-- Forever (1.60.1, Interface 16001) is Vanilla content on the Retail
-- (Mainline) API. Every API that moved or disappeared relative to TBC
-- Classic is reached through Apotheca.API, so a client change lands in
-- one file. Call through the table (Apotheca.API.ItemInfo(id)); do not
-- copy functions into file locals.
--
-- Measured facts behind these adapters:
--   C:\Projects\References\PORTING-TBC-TO-FOREVER.md
--   C:\Projects\References\forever-api-1.60.1.69977.md
-- ============================================================

Apotheca = Apotheca or {}
local API = {}
Apotheca.API = API

-- The client build these adapters were measured against. On any other
-- build players get a one-line note at login (see Apotheca.lua).
API.MEASURED_ON_BUILD = 69977

local PREFIX = "|cff9966ffApotheca:|r "

-- ------------------------------------------------------------
-- Items
-- ------------------------------------------------------------

-- C_Item.GetItemInfo keeps the Classic 18-value tuple. It returns NO
-- values (not nil) on a cache miss; GET_ITEM_INFO_RECEIVED follows.
function API.ItemInfo(itemID)
    if not itemID then return nil end
    return C_Item.GetItemInfo(itemID)
end

-- NOT C_Item.GetItemIcon: that one takes an ItemLocation.
function API.ItemIcon(itemID)
    if not itemID then return nil end
    return C_Item.GetItemIconByID(itemID)
end

-- Same (start, duration, enable) tuple as the old global.
-- C_Item.GetItemCooldown is different: its third value is a bool.
function API.ItemCooldown(itemID)
    return C_Container.GetItemCooldown(itemID)
end

-- ------------------------------------------------------------
-- Containers
-- ------------------------------------------------------------

function API.ContainerNumSlots(bag)
    return C_Container.GetContainerNumSlots(bag) or 0
end

function API.ContainerItemID(bag, slot)
    return C_Container.GetContainerItemID(bag, slot)
end

-- GetContainerItemInfo returns a struct here, not the old tuple.
function API.ContainerItemCount(bag, slot)
    local info = C_Container.GetContainerItemInfo(bag, slot)
    return info and info.stackCount or 0
end

-- Carried bags: backpack, bags 1..NUM_BAG_SLOTS, and the reagent bag.
-- Bank IDs all moved on this client, so nothing else is listed.
local carriedBags
function API.CarriedBags()
    if not carriedBags then
        carriedBags = {}
        for bag = 0, (NUM_BAG_SLOTS or 4) do carriedBags[#carriedBags + 1] = bag end
        local reagent = Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag
        if reagent then carriedBags[#carriedBags + 1] = reagent end
    end
    return carriedBags
end

-- ------------------------------------------------------------
-- Auras
--
-- UnitBuff / UnitDebuff are gone. In combat every aura is secret:
-- index reads throw, and a secret value also throws when it is
-- compared or truth-tested. So everything that touches aura data
-- happens inside ONE pcall, and a blocked read is reported as nil
-- ("unknown"), distinct from an empty set ("nothing there").
-- ------------------------------------------------------------

-- Returns names, spellIDs (two sets) of the player's auras, or nil
-- when the client refused the read.
function API.PlayerAuras(filter)
    local ok, names, ids = pcall(function()
        local n, s = {}, {}
        local i = 1
        while true do
            local aura = C_UnitAuras.GetAuraDataByIndex("player", i, filter or "HELPFUL")
            if not aura then break end
            if aura.name then n[aura.name] = true end
            if aura.spellId then s[aura.spellId] = true end
            i = i + 1
        end
        return n, s
    end)
    if not ok then return nil end
    return names, ids
end

-- ------------------------------------------------------------
-- Secret values
--
-- Health, power and cooldowns may be secret in combat on this client.
-- Run the whole calculation through Safe(): it returns ok, results...
-- and never lets a secret-value error escape.
-- ------------------------------------------------------------

function API.Safe(fn, ...)
    return pcall(fn, ...)
end

-- Missing health and mana as plain numbers, or nil, nil when the client
-- would not hand them over. Callers decide what "unknown" means.
function API.PlayerMissing()
    local ok, hp, mana = pcall(function()
        local h = (UnitHealthMax("player") or 0) - (UnitHealth("player") or 0)
        local m = (UnitPowerMax("player") or 0) - (UnitPower("player") or 0)
        -- Arithmetic on a secret may still yield a secret; comparing one
        -- is what throws. Compare here, inside the pcall, so a secret can
        -- never reach a caller's comparison.
        local _ = (h > 0), (m > 0)
        return h, m
    end)
    if not ok then return nil, nil end
    return hp, mana
end

-- ------------------------------------------------------------
-- Using items from insecure code
--
-- The UseItemByName global is gone. C_Item.UseItemByName exists but is
-- probably protected; /apo probe measures it. Returns false when the
-- call is missing or raised an error.
-- ------------------------------------------------------------

function API.UseItemByName(name)
    local fn = C_Item and C_Item.UseItemByName
    if not fn or not name then return false end
    return (pcall(fn, name))
end

-- ------------------------------------------------------------
-- Events
--
-- RegisterEvent throws on an unknown name and is declared to return
-- registered:bool, so false is a refusal too. Every failure is printed:
-- a missing handler must not ship silently.
-- ------------------------------------------------------------

API.eventFailures = {}

function API.RegisterEvents(frame, ...)
    local failed = {}
    for i = 1, select("#", ...) do
        local event = select(i, ...)
        local ok, registered = pcall(frame.RegisterEvent, frame, event)
        if not ok or registered == false then
            failed[#failed + 1] = event
            API.eventFailures[#API.eventFailures + 1] = event
        end
    end
    if #failed > 0 then
        print(PREFIX .. "this client rejected event(s): " .. table.concat(failed, ", "))
    end
    return #failed == 0, failed
end

-- ------------------------------------------------------------
-- Secure buttons
--
-- Register BOTH mouse edges. The client's secure handler acts only on
-- the edge where down == useOnKeyDown (attribute, else the
-- ActionButtonUseKeyDown CVar), so exactly one edge ever acts; a
-- single edge is a dead button for anyone on the other setting.
-- Never set "typerelease": the hold-release path reads it and would
-- use the item twice.
-- ------------------------------------------------------------

function API.ClickEdges()
    return "AnyUp", "AnyDown"
end

-- ------------------------------------------------------------
-- Client
-- ------------------------------------------------------------

function API.ClientBuild()
    return tonumber((select(2, GetBuildInfo())))
end

function API.AddonVersion()
    local fn = C_AddOns and C_AddOns.GetAddOnMetadata
    return fn and fn("Apotheca", "Version") or "?"
end
