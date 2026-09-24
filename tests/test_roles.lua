-- #9: the role comes from Apotheca's override, then the game's own role
-- selector, then the class. The group-assigned role is NOT used (Codex).

dofile("tests/wow_stubs.lua")
local H = dofile("tests/harness.lua")
H.loadAddon()

local function role() return Apotheca.ResolveRole() end
local function key() local _, k = Apotheca.ResolveRole() return k end
local db = function() return ApothecaDB.profiles[ApothecaDB.activeProfile] end

-- Class defaults, with nothing ticked in the selector.
local defaults = {
    PRIEST = "HEALER", PALADIN = "HEALER", SHAMAN = "HEALER", DRUID = "HEALER",
    WARRIOR = "MELEE", MAGE = "CASTER", WARLOCK = "CASTER", ROGUE = "AGILITY", HUNTER = "AGILITY",
}
for cls, k in pairs(defaults) do
    WoW.class = cls
    H.eq(key(), k, cls .. " defaults to " .. k .. " with no role selected")
end

-- The game's selector decides when something is ticked.
WoW.class = "PRIEST"
WoW.lfgRoles = { damage = true }
H.eq(role(), "DAMAGE", "a priest who ticked Damage plays damage")
H.eq(key(), "CASTER", "and a damage priest is a caster")
H.eq(Apotheca.GetStatPriority()[1], "spellDmg", "so buff food leads with spell damage")

-- Several ticked: the class's preference among them.
WoW.class = "WARRIOR"
WoW.lfgRoles = { tank = true, damage = true }
H.eq(role(), "TANK", "a warrior ticking Tank and Damage is a tank")
H.eq(Apotheca.GetRoleProfile().flask[1], "maxHealth", "tanks want Flask of the Titans")
WoW.class = "PALADIN"
WoW.lfgRoles = { tank = true, healer = true }
H.eq(role(), "HEALER", "a paladin ticking Tank and Healer heals")

-- The group-assigned role is ignored (Codex review of #9).
WoW.class = "PRIEST"
WoW.lfgRoles = { healer = true }
WoW.inGroup, WoW.assignedRole = true, "DAMAGER"
H.eq(role(), "HEALER", "by default a group assignment does not override the selector")
db().useGroupRole = true
H.eq(role(), "DAMAGE", "opted in, the group's assigned role wins over the selector")
WoW.assignedRole = "NONE"
H.eq(role(), "HEALER", "an unset group role falls back to the selector")
WoW.inGroup, WoW.assignedRole = false, "DAMAGER"
H.eq(role(), "HEALER", "outside a group the assigned role is ignored")
WoW.inGroup = true
db().role = "TANK"
H.eq(role(), "TANK", "the override still wins over the group role")
db().role, db().useGroupRole = "AUTO", false
WoW.inGroup, WoW.assignedRole = false, nil

-- The override wins over everything.
db().role = "TANK"
H.eq(role(), "TANK", "Apotheca's own Tank override wins over the selector")
db().role = "AUTO"

-- Druid and Shaman damage follows the style option.
WoW.class, WoW.lfgRoles = "DRUID", { damage = true }
H.eq(key(), "CASTER", "a damage druid defaults to Spell (Balance)")
db().damageStyle = "PHYSICAL"
H.eq(key(), "AGILITY", "Physical makes a damage druid Agility (Feral)")
WoW.class = "SHAMAN"
H.eq(key(), "MELEE", "and a Physical damage shaman Melee (Enhancement)")
db().damageStyle = "SPELL"

-- Mana gating by class, not by the current form's power type.
WoW.lfgRoles = nil
for cls, has in pairs({ WARRIOR = false, ROGUE = false, DRUID = true, HUNTER = true, MAGE = true }) do
    WoW.class = cls
    H.eq(Apotheca.UsesMana(), has, cls .. (has and " has" or " has no") .. " mana")
end

WoW.class = "WARRIOR"
WoW.AddItem(0, 1, 13444, 3, "Major Mana Potion")
WoW.AddItem(0, 2, 13446, 3, "Major Healing Potion")
Apotheca.ResetLayout()
Apotheca.UpdateAllButtons()
H.check(not Apotheca.buttons.mana:IsShown(), "a warrior has no Mana button, even holding mana potions")
H.check(Apotheca.buttons.health:IsShown(), "but keeps the Health button")
WoW.AddItem(0, 3, 8766, 3, "Morning Glory Dew")
WoW.AddItem(0, 4, 20748, 3, "Brilliant Mana Oil")
Apotheca.ResetLayout()
Apotheca.UpdateAllButtons()
H.check(not Apotheca.buttons.drink:IsShown(), "a warrior has no Drink button, even holding water")
H.check(not Apotheca.buttons.weaponoil:IsShown(), "nor a Weapon Oil button holding Brilliant Mana Oil")
H.check(Apotheca.buttons.food:IsShown(), "but keeps the Food button")
WoW.class = "PRIEST"
Apotheca.ResetLayout()
Apotheca.UpdateAllButtons()
H.check(Apotheca.buttons.mana:IsShown(), "a priest has the Mana button")
H.check(Apotheca.buttons.drink:IsShown(), "and the Drink button")
H.check(Apotheca.buttons.weaponoil:IsShown(), "and the Weapon Oil button")

-- The bar shows for every role by default; "healer only" is opt-in.
WoW.class = "MAGE"
H.eq(db().showOnlyHealingSpec, false, "the bar is for every role by default")

-- A role change refreshes only when the resolved role changes.
WoW.class, WoW.lfgRoles = "PRIEST", { healer = true }
Apotheca.UpdateAllButtons()          -- the bar is built for the healer role
local updates = 0
local real = Apotheca.UpdateAllButtons
Apotheca.UpdateAllButtons = function(...) updates = updates + 1 return real(...) end
for _ = 1, 5 do WoW.fire("LFG_ROLE_UPDATE") end
WoW.tick(1) ; WoW.tick(1)
H.eq(updates, 0, "a burst of role events with no role change costs no update")
WoW.lfgRoles = { damage = true }
WoW.fire("LFG_ROLE_UPDATE")
WoW.tick(1) ; WoW.tick(1)
H.eq(updates, 1, "switching to Damage costs one update")
Apotheca.UpdateAllButtons = real

H.done("test_roles")
