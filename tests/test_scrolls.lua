-- #9 part 2a: stat scrolls per role, and the mage mana gem.

dofile("tests/wow_stubs.lua")
local H = dofile("tests/harness.lua")

-- One scroll of every kind, plus a mana gem.
WoW.AddItem(1, 1, 10306, 3, "Scroll of Spirit IV")
WoW.AddItem(1, 2, 10305, 3, "Scroll of Protection IV")
WoW.AddItem(1, 3, 10308, 3, "Scroll of Intellect IV")
WoW.AddItem(1, 4, 10307, 3, "Scroll of Stamina IV")
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

-- Hunters (Agility profile, but mana users) also get Intellect; rogues not.
roleIs("HUNTER", { damage = true })
H.check(shown("intellectscroll") and shown("agilityscroll"), "a hunter is offered Intellect as well as Agility")
roleIs("ROGUE", { damage = true })
H.check(not shown("intellectscroll"), "a rogue is not offered Intellect")

-- A switched-off kind stays hidden for every role.
ApothecaDB.profiles[ApothecaDB.activeProfile].scrolls.agility = false
roleIs("ROGUE", { damage = true })
H.check(not shown("agilityscroll"), "switching Agility scrolls off hides them")
ApothecaDB.profiles[ApothecaDB.activeProfile].scrolls.agility = true

-- Buffs that do not stack with a scroll count as covered.
local int
for _, k in ipairs(Apotheca.SCROLL_KINDS) do if k.key == "intellectscroll" then int = k end end
H.eq(Apotheca.HasScrollBuff(int), false, "no intellect buff: the Intellect scroll is wanted")
WoW.SetAura("HELPFUL", "Arcane Intellect", 10157)      -- a listed rank: by spell ID
H.eq(Apotheca.HasScrollBuff(int), true, "Arcane Intellect (a listed rank) covers the Intellect scroll")
WoW.auras.HELPFUL = {}
WoW.spellNames[1459] = "Intelligence des Arcanes"        -- a French client
WoW.SetAura("HELPFUL", "Intelligence des Arcanes", 9999999) -- an ID NOT in the list
H.eq(Apotheca.HasScrollBuff(int), true, "an unlisted Arcane Intellect is matched by its localized name")
WoW.auras.HELPFUL = {}

-- A buff NAME shared with an elixir must not hide a missing scroll (the
-- scan shows Agility, Strength and Armor are shared).
local agi, prot
for _, k in ipairs(Apotheca.SCROLL_KINDS) do
    if k.key == "agilityscroll" then agi = k end
    if k.key == "protectionscroll" then prot = k end
end
WoW.spellNames[8115], WoW.spellNames[11328] = "Agility", "Agility"      -- scroll, elixir
WoW.spellNames[8091], WoW.spellNames[11349] = "Armor", "Armor"          -- scroll, elixir
WoW.SetAura("HELPFUL", "Agility", 11328)                                -- Elixir of Agility
H.eq(Apotheca.HasScrollBuff(agi), false, "Elixir of Agility does not count as the Agility scroll")
WoW.auras.HELPFUL = {}
WoW.SetAura("HELPFUL", "Agility", 12174)                                -- Scroll of Agility IV
H.eq(Apotheca.HasScrollBuff(agi), true, "the Agility scroll's own buff is found by spell ID")
WoW.auras.HELPFUL = {}
WoW.SetAura("HELPFUL", "Armor", 11349)                                  -- Elixir of Defense
H.eq(Apotheca.HasScrollBuff(prot), false, "Elixir of Defense does not count as the Protection scroll")
WoW.auras.HELPFUL = {}

-- A scroll the role no longer shows does not glow (stale itemID while hidden).
roleIs("PRIEST", { healer = true })
local spirit = Apotheca.buttons.spiritscroll
H.check(shown("spiritscroll"), "a healer shows the Spirit scroll")
roleIs("WARRIOR", { tank = true })
spirit.__apothecaGlow = nil
WoW.fire("READY_CHECK")
H.eq(spirit.__apothecaGlow, nil, "the hidden Spirit scroll does not glow on a ready check")
WoW.fire("READY_CHECK_FINISHED")

-- Mana gem: mages only.
roleIs("MAGE", nil)
H.check(shown("managem"), "a mage gets the Mana Gem button")
H.eq(Apotheca.buttons.managem.itemID, 8008, "holding Mana Ruby")
H.check(not shown("mana") or Apotheca.buttons.mana.itemID ~= 8008, "the gem is not on the Mana potion button")
-- Each gem has its own cooldown: a Ruby on cooldown must not hide a ready Citrine.
WoW.AddItem(1, 8, 8007, 2, "Mana Citrine")
WoW.cooldowns[8008] = { WoW.time, 120 }
roleIs("MAGE", nil)
H.eq(Apotheca.buttons.managem.itemID, 8007, "with the Ruby on cooldown, the ready Citrine is offered")
-- When the Ruby's cooldown ends, the button re-picks it, with no bag change
-- and even if no event fires (Codex review of #15).
WoW.cooldowns[8008] = { WoW.time - 118, 120 }          -- 2 s left
roleIs("MAGE", nil)
H.eq(Apotheca.buttons.managem.itemID, 8007, "Citrine while the Ruby has 2 s left")
WoW.cooldowns[8008] = nil                               -- the Ruby is ready
for _ = 1, 4 do WoW.tick(1) end                         -- time passes; no event
H.eq(Apotheca.buttons.managem.itemID, 8008, "once the Ruby is ready the button offers it again")
WoW.cooldowns[8008] = { WoW.time - 118, 120 }
roleIs("MAGE", nil)
WoW.cooldowns[8008] = nil
WoW.time = WoW.time + 3
WoW.fire("BAG_UPDATE_COOLDOWN")
WoW.tick(1) ; WoW.tick(1)
H.eq(Apotheca.buttons.managem.itemID, 8008, "a cooldown event after expiry re-picks the Ruby too")
WoW.cooldowns[8008] = { WoW.time, 120 }
WoW.cooldowns[8007] = { WoW.time, 120 }
roleIs("MAGE", nil)
H.eq(Apotheca.buttons.managem.itemID, 8008, "with both on cooldown, the strongest (Ruby) is offered")
WoW.cooldowns = {}
roleIs("PRIEST", { healer = true })
H.check(not shown("managem"), "a priest carrying a gem gets no Mana Gem button")
ApothecaDB.profiles[ApothecaDB.activeProfile].manaGem.enabled = false
roleIs("MAGE", nil)
H.check(not shown("managem"), "the Mana Gem button can be switched off")

H.done("test_scrolls")
