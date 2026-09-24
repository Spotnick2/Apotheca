-- #9 part 2a: stat scrolls per role, and the mage mana gem.

dofile("tests/wow_stubs.lua")
local H = dofile("tests/harness.lua")

-- One scroll of every kind, plus a mana gem.
WoW.AddItem(1, 1, 10306, 3, "Scroll of Spirit IV")
WoW.AddItem(1, 2, 10305, 3, "Scroll of Protection IV")
WoW.AddItem(1, 3, 10308, 3, "Scroll of Intellect IV")
WoW.AddItem(1, 4, 10307, 3, "Scroll of Stamina IV")
WoW.AddItem(1, 5, 12292, 3, "Scroll of Strength")      -- any strength scroll id in data
WoW.AddItem(1, 6, 3012, 3, "Scroll of Agility")
WoW.AddItem(1, 7, 8008, 2, "Mana Ruby")
H.loadAddon()

local function shown(key) local b = Apotheca.buttons[key] return b and b:IsShown() and b.itemID ~= nil end
local function roleIs(cls, lfg) WoW.class, WoW.lfgRoles = cls, lfg ; Apotheca.UpdateAllButtons() end

-- The strength scroll ID the data actually holds.
local strID = Apotheca.DATA.SCROLLS_BY_STAT.strength[1].id
WoW.AddItem(1, 5, strID, 3, "Scroll of Strength")

-- Healer: Spirit, Intellect, Protection; not Stamina / Strength / Agility.
roleIs("PRIEST", { healer = true })
H.check(shown("spiritscroll") and shown("intellectscroll") and shown("protectionscroll"),
    "a healer is offered Spirit, Intellect and Protection scrolls")
H.check(not shown("staminascroll") and not shown("strengthscroll") and not shown("agilityscroll"),
    "but not Stamina, Strength or Agility")
H.eq(Apotheca.buttons.intellectscroll.itemID, 10308, "the Intellect button holds Scroll of Intellect IV")

-- Tank: Protection and Stamina.
roleIs("WARRIOR", { tank = true })
H.check(shown("protectionscroll") and shown("staminascroll"), "a tank is offered Protection and Stamina")
H.check(not shown("spiritscroll") and not shown("intellectscroll"), "and no caster scrolls")

-- Melee: Strength and Agility.
roleIs("WARRIOR", { damage = true })
H.check(shown("strengthscroll") and shown("agilityscroll"), "a melee warrior is offered Strength and Agility")

-- A switched-off kind stays hidden for every role.
ApothecaDB.profiles[ApothecaDB.activeProfile].scrolls.agility = false
roleIs("ROGUE", { damage = true })
H.check(not shown("agilityscroll"), "switching Agility scrolls off hides them")
ApothecaDB.profiles[ApothecaDB.activeProfile].scrolls.agility = true

-- Buffs that do not stack with a scroll count as covered.
local int
for _, k in ipairs(Apotheca.SCROLL_KINDS) do if k.key == "intellectscroll" then int = k end end
H.eq(Apotheca.HasScrollBuff(int), false, "no intellect buff: the Intellect scroll is wanted")
WoW.spellNames[1459] = "Arcane Intellect"
WoW.SetAura("HELPFUL", "Arcane Intellect", 10157)      -- another rank
H.eq(Apotheca.HasScrollBuff(int), true, "Arcane Intellect (any rank) covers the Intellect scroll")
WoW.auras.HELPFUL = {}

-- Mana gem: mages only.
roleIs("MAGE", nil)
H.check(shown("managem"), "a mage gets the Mana Gem button")
H.eq(Apotheca.buttons.managem.itemID, 8008, "holding Mana Ruby")
H.check(not shown("mana") or Apotheca.buttons.mana.itemID ~= 8008, "the gem is not on the Mana potion button")
roleIs("PRIEST", { healer = true })
H.check(not shown("managem"), "a priest carrying a gem gets no Mana Gem button")
ApothecaDB.profiles[ApothecaDB.activeProfile].manaGem.enabled = false
roleIs("MAGE", nil)
H.check(not shown("managem"), "the Mana Gem button can be switched off")

H.done("test_scrolls")
