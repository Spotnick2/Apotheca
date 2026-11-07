-- #9: the role comes from Apotheca's per-character override, then (only if
-- opted in) the group's assigned role, then the game's own role selector,
-- then the class. The resolved role is cached; RefreshRole re-reads it.

dofile("tests/wow_stubs.lua")
local H = dofile("tests/harness.lua")
H.loadAddon()

local function role() Apotheca.RefreshRole() return (Apotheca.ResolveRole()) end
local function key() Apotheca.RefreshRole() local _, k = Apotheca.ResolveRole() return k end
local db = function() return ApothecaDB.profiles[ApothecaDB.activeProfile] end
local function char(k, v) Apotheca.SetCharSetting(k, v) end

-- Class defaults, with nothing ticked in the selector.
local defaults = {
    PRIEST = "HEALER", PALADIN = "HEALER", SHAMAN = "HEALER", DRUID = "HEALER",
    WARRIOR = "MELEE", MAGE = "CASTER", WARLOCK = "CASTER", ROGUE = "AGILITY", HUNTER = "AGILITY",
}
for cls, k in pairs(defaults) do
    WoW.class = cls
    eq(key(), k, cls .. " defaults to " .. k .. " with no role selected")
end

-- The game's selector decides when something is ticked.
WoW.class = "PRIEST"
WoW.lfgRoles = { damage = true }
eq(role(), "DAMAGE", "a priest who ticked Damage plays damage")
eq(key(), "CASTER", "and a damage priest is a caster")
eq(Apotheca.GetStatPriority()[1], "spellDmg", "so buff food leads with spell damage")

-- Several ticked: the class's preference among them.
WoW.class = "WARRIOR"
WoW.lfgRoles = { tank = true, damage = true }
eq(role(), "TANK", "a warrior ticking Tank and Damage is a tank")
eq(Apotheca.GetRoleProfile().flask[1], "maxHealth", "tanks want Flask of the Titans")
WoW.class = "PALADIN"
WoW.lfgRoles = { tank = true, healer = true }
eq(role(), "HEALER", "a paladin ticking Tank and Healer heals")

-- Nothing ticked NOW is a real answer: an older saved pick must not win
-- over the class default (Codex review of #14).
-- (A paladin can tank, so a stale saved Tank WOULD be taken if read.)
WoW.class = "PALADIN"
WoW.lfgRoles, WoW.lfgSavedRoles = { }, { tank = true }
eq(role(), "HEALER", "a cleared selector gives the class default, not a stale saved Tank")
WoW.lfgRoles, WoW.lfgSavedRoles = nil, nil

-- The group-assigned role is ignored (Codex review of #9).
WoW.class = "PRIEST"
WoW.lfgRoles = { healer = true }
WoW.inGroup, WoW.assignedRole = true, "DAMAGER"
eq(role(), "HEALER", "by default a group assignment does not override the selector")
char("useGroupRole", true)
eq(role(), "DAMAGE", "opted in, the group's assigned role wins over the selector")
WoW.assignedRole = "NONE"
eq(role(), "HEALER", "an unset group role falls back to the selector")
WoW.inGroup, WoW.assignedRole = false, "DAMAGER"
eq(role(), "HEALER", "outside a group the assigned role is ignored")
WoW.inGroup = true
char("role", "TANK")
eq(role(), "TANK", "the override still wins over the group role")
char("role", "AUTO") ; char("useGroupRole", false)
WoW.inGroup, WoW.assignedRole = false, nil

-- The override wins over everything.
char("role", "TANK")
eq(role(), "TANK", "Apotheca's own Tank override wins over the selector")
char("role", "AUTO")

-- Druid and Shaman damage follows the style option.
WoW.class, WoW.lfgRoles = "DRUID", { damage = true }
eq(key(), "CASTER", "a damage druid defaults to Spell (Balance)")
char("damageStyle", "PHYSICAL")
eq(key(), "AGILITY", "Physical makes a damage druid Agility (Feral)")
WoW.class = "SHAMAN"
eq(key(), "MELEE", "and a Physical damage shaman Melee (Enhancement)")
char("damageStyle", "SPELL")

-- Mana gating by class, not by the current form's power type.
WoW.lfgRoles = nil
for cls, has in pairs({ WARRIOR = false, ROGUE = false, DRUID = true, HUNTER = true, MAGE = true }) do
    WoW.class = cls
    eq(Apotheca.UsesMana(), has, cls .. (has and " has" or " has no") .. " mana")
end

WoW.class = "WARRIOR"
WoW.AddItem(0, 1, 13444, 3, "Major Mana Potion")
WoW.AddItem(0, 2, 13446, 3, "Major Healing Potion")
Apotheca.UpdateAllButtons()
check(not Apotheca.buttons.mana:IsShown(), "a warrior has no Mana button, even holding mana potions")
check(Apotheca.buttons.health:IsShown(), "but keeps the Health button")
WoW.AddItem(0, 3, 8766, 3, "Morning Glory Dew")
WoW.AddItem(0, 4, 20748, 3, "Brilliant Mana Oil")
WoW.level = 60                          -- the oil needs level 45 (oils are level-checked, #29)
Apotheca.UpdateAllButtons()
check(not Apotheca.buttons.drink:IsShown(), "a warrior has no Drink button, even holding water")
check(not Apotheca.buttons.weaponoil:IsShown(), "nor a Weapon Oil button holding Brilliant Mana Oil")
check(Apotheca.buttons.food:IsShown(), "but keeps the Food button")
WoW.class = "PRIEST"
Apotheca.UpdateAllButtons()
check(Apotheca.buttons.mana:IsShown(), "a priest has the Mana button")
check(Apotheca.buttons.drink:IsShown(), "and the Drink button")
check(Apotheca.buttons.weaponoil:IsShown(), "and the Weapon Oil button")

-- The bar shows for every role by default; "healer only" is opt-in.
WoW.class = "MAGE"
eq(db().onlyWhenHealer, false, "the bar is for every role by default")

-- A role change refreshes only when the resolved role changes.
WoW.class, WoW.lfgRoles = "PRIEST", { healer = true }
Apotheca.UpdateAllButtons()          -- the bar is built for the healer role
WoW.step(1) ; WoW.step(1)            -- let updates requested earlier in this file run out
local updates = 0
local real = Apotheca.UpdateAllButtons
Apotheca.UpdateAllButtons = function(...) updates = updates + 1 return real(...) end
for _ = 1, 5 do WoW.fire("LFG_ROLE_UPDATE") end
WoW.step(1) ; WoW.step(1)
eq(updates, 0, "a burst of role events with no role change costs no update")
WoW.lfgRoles = { damage = true }
WoW.fire("LFG_ROLE_UPDATE")
WoW.step(1) ; WoW.step(1)
eq(updates, 1, "switching to Damage costs one update")
Apotheca.UpdateAllButtons = real

-- Role settings are per character: another character on the same shared
-- profile keeps its own role.
char("role", "TANK")
local saved = ApothecaCharDB
rawset(_G, "ApothecaCharDB", {})           -- a second character, same profile
WoW.class, WoW.lfgRoles = "PRIEST", nil
eq(role(), "HEALER", "a Tank override on one character does not reach another")
rawset(_G, "ApothecaCharDB", saved)
eq(role(), "TANK", "and the first keeps its own")
char("role", "AUTO")

-- The role is re-checked without any event (the selector's event is not
-- measured): the slow out-of-combat poll catches the change.
WoW.lfgRoles = { healer = true }
Apotheca.UpdateAllButtons()
WoW.lfgRoles = { damage = true }            -- no event fired
for _ = 1, 4 do WoW.step(1) end
eq((Apotheca.ResolveRole()), "DAMAGE", "the poll picks up a role change with no event")

done("test_roles")
