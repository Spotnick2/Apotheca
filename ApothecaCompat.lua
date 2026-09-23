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
-- The player's current health and power are secret on this client, even
-- out of combat (docs/FOREVER-PROBE.md); cooldowns and counts may be in
-- combat. A secret must never reach a comparison outside a pcall.
-- ------------------------------------------------------------

-- Missing health and missing MANA as plain numbers, each nil when the
-- client would not hand it over. Read separately: the two secrecy switches
-- are independent (measured), and mana is asked for by power type so a
-- shapeshifted druid's energy or rage is never mistaken for it.
local function missing(cur, max)
    local ok, m = pcall(function()
        local v = (max() or 0) - (cur() or 0)
        -- Comparing a secret is what throws; do it here, inside the pcall.
        local _ = v > 0
        return v
    end)
    if ok then return m end
    return nil
end

function API.PlayerMissing()
    local mana = Enum and Enum.PowerType and Enum.PowerType.Mana or 0
    return missing(function() return UnitHealth("player") end,
                   function() return UnitHealthMax("player") end),
           missing(function() return UnitPower("player", mana) end,
                   function() return UnitPowerMax("player", mana) end)
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

function API.RegisterEvents(frame, ...)
    local failed = {}
    for i = 1, select("#", ...) do
        local event = select(i, ...)
        local ok, registered = pcall(frame.RegisterEvent, frame, event)
        if not ok or registered == false then
            failed[#failed + 1] = event
        end
    end
    if #failed > 0 then
        print(PREFIX .. "this client rejected event(s): " .. table.concat(failed, ", "))
    end
    return #failed == 0, failed
end

-- Same, for events registered to one unit.
function API.RegisterUnitEvents(frame, unit, ...)
    local failed = {}
    for i = 1, select("#", ...) do
        local event = select(i, ...)
        local ok, registered = pcall(frame.RegisterUnitEvent, frame, event, unit)
        if not ok or registered == false then failed[#failed + 1] = event end
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
