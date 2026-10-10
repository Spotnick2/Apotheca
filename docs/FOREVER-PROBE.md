# Apotheca on WoW: Forever: probe results

These were measured with `/apo probe` (`ApothecaProbe.lua`) on build **1.60.1.69977**, interface 16001. Addon-agnostic findings live in `C:\Projects\References\PORTING-TBC-TO-FOREVER.md`. This file records only what Apotheca itself depends on.

## Run 1: 2026-09-23, out of combat (level 15 Hunter)

### Health and power are secret even out of combat

This is the headline, and it is not what the porting guide led us to expect for the player.

```
C_Secrets.ShouldUnitHealthMaxBeSecret = false
C_Secrets.ShouldUnitPowerBeSecret     = true
UnitHealth/Max = <secret>, 477
UnitPower/Max  = <secret>, 505
API.PlayerMissing -> nil, nil   (the guarded comparison threw)
```

The max values are readable, but the current values are not, even at rest. Any branch on "am I at full health or mana" is impossible. That means these three features have nothing to go on:

- **Waste prevention**, which blocks or asks for food/drink/potions at full.
- **Smart healthstone rank**, which picks the smallest stone that covers the missing health.
- **`hideWhenFull`** for the Food and Drink buttons.

The Foundation commit already degrades each one to its safe default through `API.PlayerMissing()` returning nil:
- Waste prevention never blocks.
- The healthstone button offers the strongest stone.
- The Food and Drink buttons stay shown.

Run 2 checks whether `UnitHealthMissing`, `UnitPowerMissing` or `UnitHealthPercent` are any different.

### Everything else

| Question | Result |
|---|---|
| `ActionButtonUseKeyDown` / `...KeyHeldSpell` | `1` / `0` (default: act on press, no hold-release) |
| Auras out of combat | readable: `Aspect of the Hawk#13165; Camp Benefits#1229741` |
| `GetWeaponEnchantInfo()` | works, 9 returns |
| `C_Container.GetContainerItemInfo` | struct; `stackCount` readable out of combat |
| Carried bags | `0,1,2,3,4,5`. The reagent bag, `Enum.BagIndex.ReagentBag` = 5, is included. |
| `C_Item.UseItemByName("<bogus>")` | no error, and no `ADDON_ACTION_BLOCKED`/`FORBIDDEN`. **Not conclusive**: a real item has to be tried. |
| `C_SpecializationInfo.GetSpecialization()` | `1`. `GetSpecializationInfo(1)` = `1485, "Hunter", "", 626000, "DAMAGER", ...`, and `GetNumSpecializationsForClassID` = **1**. |
| Templates | `InterfaceOptionsCheckButtonTemplate`, `OptionsSliderTemplate`, `UIDropDownMenuTemplate` and `UIPanelButtonTemplate` all applied. `UIRadioButtonTemplate` and `CooldownFrameTemplate` were created. |
| `GameTooltip.SetItemByID` | a function (present) |
| `AnimateTexCoords` | nil (absent). The glow pins the first flipbook frame. |
| Addon list icon | a question mark, because the TOC had no `## IconTexture`. Now set to `INV_Potion_76`. |

On specs: **each class has exactly one spec, named after the class, with no tree.** Healer detection by spec is meaningless on this client, which confirms that class-only detection is right. The `showOnlyHealingSpec` option has to be reworded as "healer classes only", or removed.

## Run 2: 2026-09-23, out of combat (Priest)

Run 2 was taken on a Priest and confirms run 1. **Every** current health and power reading is secret at rest:

```
UnitHealthMissing / UnitPowerMissing / UnitPower(Mana)   = <secret>
UnitHealthPercent / UnitPowerPercent                     = <secret>
UnitHealthMissing("player") == 0
    -> ERROR: attempt to compare a secret number value (execution tainted by 'Apotheca')
```

**There is no way for an addon to branch on the player's current health or mana on this build.** Secret values can only be handed to widgets for display, and cannot be compared.

On specs: the Priest also has one spec (`1487, "Priest", ..., "DAMAGER"`). The role reads `DAMAGER` even for a Priest, so neither the spec nor the role says who heals.

## Run 3: 2026-09-23, the bar itself (Priest, level 3)

- The bar renders with four empty-slot icons (mana, health, food, drink) and no Lua errors.
- **Forest Mushroom Cap (4604)** has a tooltip reading *"Restores 58 health over 18 sec."* That's 61 in Vanilla, so **Forever's restore values differ from Vanilla's** and can't be copied from a 1.12 database. Issue #4 reads them from the client's tooltip data instead.

## Run 4: 2026-09-23, IN combat (Priest)

| Question | Result |
|---|---|
| `ShouldAurasBeSecret` | **true**. `GetAuraDataByIndex` throws *"Auras cannot be accessed when secret while tainted by 'Apotheca'"*, and `API.PlayerAuras` returns nil, as designed. |
| `ShouldCooldownsBeSecret` | **true**. Item cooldowns are secret in combat. The swipe hands them straight to `SetCooldown` without comparing them (the `/code-review` fix on #7). |
| Health / power | secret, the same as at rest. `API.PlayerMissing` = `nil, nil`. |
| **StatusBar readback** | `bar:SetValue(UnitHealth("player"))`, then `bar:GetValue()`, gives `<secret>`. **There is no readback loophole.** Unit frame addons can *display* health, but no addon can *decide* on it. |
| Stack counts | readable in combat (`stackCount = 8`) |
| `GetWeaponEnchantInfo` | readable in combat (plain `false`, 12 returns) |
| `C_Item.UseItemByName("<bogus>")` in combat | no error, and no blocked event. Still inconclusive: a real item is needed. |

## Run 5: 2026-09-23, the consumable database (`/apo scan` + `/apo scan2`)

`C_Item.GetItemInfoInstant` over item IDs 1 to 300000 finds **2442 consumables** (classID 0). Their tooltips and item spells went into `docs/forever-consumables-69977.tsv`, from which `ApothecaItems.lua` is generated. The shared, readable catalog is `C:/Projects/References/forever-consumables-1.60.1.69977.md`.

- **Tooltips arrive without their "Use:" line until the item's SPELL is loaded.** After the first pass, only 17 of 106 potions had it. `C_Spell.RequestLoadSpellData` in a second pass brought that to 103.
- **Forever food is a new system.** Most cooked food uses a "Nutritious Food" spell that restores health, gives Well Fed and adds +5% kill XP. Restore values are rescaled (58 / 234 / 530 / 841 / 1338 / 2065 against Vanilla's 61 / 243 / 552 / 874 / 1392 / 2148).
- **New Forever items include:**
  - Mountain Spring Water, a **conjured** level-55 water (4903 mana) with no "Conjured" in its name
  - Teas: mana drinks with +healing
  - Smoothies: mana drinks with +spirit
  - Cleric's Elixirs: +healing
  - Mageblood, Minor to Greater
  - Elixirs of Spirit, of the Owl, and of the Whale
  - the Restored and Perishable potions
  - Darkspear Islands battleground bandages
- **Base healthstones restore what fully Improved stones did in Vanilla:** 120 / 300 / 600 / 960 / 1440.
- **Absent from the client:** Demonic Rune, Dark Rune, Lesser Mana Oil and Lesser Wizard Oil.
- **Wowhead is incomplete.** It lists no Scroll of Protection, but the client has ranks I to IV.

## Run 6: 2026-09-24, clicks (Priest, level 3)

With Forest Mushroom Cap on the Food button (secure button registered for both edges, `AnyUp` + `AnyDown`, and `ActionButtonUseKeyDown = 1`), out of combat:

- **Left click: one item eaten.**
- **Right click: one item eaten.**

This confirms the both-edges registration in game: the client's secure handler acts on exactly one edge, so one click uses one item.

## Run 7: 2026-09-24, role sources and talents (Hunter, level 15)

| Question | Result |
|---|---|
| `IsInGroup / IsInRaid`, solo | `false, false` |
| `UnitGroupRolesAssigned("player")`, solo | `NONE` |
| `GetLFGRoles()`, Damage ticked | `false, false, false, true` (leader, tank, healer, dps) |
| `C_LFGListRoles.GetRoles()` / `GetSavedRoles()` | `{ dps = true, healer = false, tank = false }` (the shape `API.SelectedRoles` reads) |
| `UnitPowerType / UnitPowerMax(Mana)` (Hunter) | `0, 505`: hunters have mana |
| Weapon slot 16 | `15424, "Weapon", "Two-Handed Axes", classID 2, subClassID 1`. The subclass tells a blade from a blunt weapon. |
| Classic talent query (`C_SpecializationInfo.GetTalentInfo{ specializationIndex, talentIndex }`) | nothing: 0 talents in any tree |
| `C_Traits` | **one** trait tree (1091) for the whole class, currency 3820, `spent 7`. All three Vanilla trees live in a single modern tree. |
| `UnitCharacterPoints`, `GetUnspentTalentPoints` | absent |

## Run 8: 2026-09-24, walking the talent tree (Hunter, level 15)

- The one tree (1091) has **52 nodes in 21 groups** (`groupIDs` 11370 to 11390). **No node has a `subTreeID`**, and `posX` does not split into three columns.
- The purchased talents are **Deadly Aspects** (5 points, x 1620, group 11372) and **Focused Fire** (2 points, x 1020, group 11390). Neither is a Vanilla talent.

**Conclusion: Forever has no Vanilla spec to detect.** The talent tree is a redesigned single tree, not Beast Mastery / Marksmanship / Survival, and the client reports one class-named spec per class (role `DAMAGER` even for a Priest). A player's role is what they tick in the game's **role selector**, which is readable (run 7). Apotheca's order is therefore:
1. its own override
2. the role selector
3. the class default

Talent-based detection would need a hand-made role map of every class's new tree; it isn't attempted.

## Build 1.60.1.70009 (client built Sep 23), 2026-09-25

- **SavedVariables load back.** The owner confirmed it with a **full exit and relaunch**: settings, the bar position and options survive. On disk, `svLoadCheck` was written as before; what changed is that the client now reads it. Through 69977 nothing loaded (account-wide or per-character). `API.SV_BROKEN_THROUGH_BUILD = 69977` limits the "not loaded" login line to those builds.
- **API dump** `C:/Projects/References/forever-api-1.60.1.70009.md`: 6596 documented functions (69977: 6577). Of 220 changed or removed lines against 69977, **none touches an API Apotheca or the probe calls**. The changes are UI mixins, LFG frames, a role-poll popup, and `C_UnitAuras.GetRefreshCarryOverDuration` (new).
- **Probe on 70009:** identical to 69977. Health and power are secret (max readable), cooldowns and auras are not secret out of combat, the role selector and talents read the same, and templates, bags and weapon slots are unchanged.
- **Consumable scan on 70009** (`docs/forever-consumables-70009.tsv`, catalog `C:/Projects/References/forever-consumables-1.60.1.70009.md`):
  - The first scan exposed a tool gap: `/apo scan2` skipped subclass 8 ("Other"), so healthstones, rations, mana gems, Holy Water and Dense Runecloth had no Use text, and regenerating would have dropped them silently. scan2 now covers subclass 8, and the generator's `--expect-present` (in CI) fails the build if a must-have item is missing.
  - Five Forever fruits (249791 to 249795: Shiny Green Apple, Sweetsour Grapes, Wayward Pomegranate, Tel'Abim Plantains, Flame Papaya) never loaded their item data. Their 69977 rows are carried over and marked `CARRIED FROM 69977`.
  - **Real changes vs 69977:**
    - Prowler Steak and Filet o' Flank became Well Fed food (+25).
    - Specklefin Feast and Grand Lobster Banquet lost their Well Fed bonus. They are feasts ("Use: Serve a delicious feast..."), placed for the group rather than eaten from the bag, so the generator skips them.
    - Wizard Oil went from +30 to +24, and Minor Wizard Oil from +15 to +8.
    - The Spellblasting, Frenzy and Mender's combat potions were retuned (not on the bar).
    - New: Shiny Silver Coin (286732).
- `MEASURED_ON_BUILD` is bumped to **70009**.

## Full health / mana tint in game (#6), 2026-09-25, build 70009

Measured on a level 3 Undead at full health and mana: the Food and Drink buttons were grey, while the same items on the default action bar stayed in full colour. The client evaluates the colour curve itself (`UnitHealthPercent` / `UnitPowerPercent`), so the tint works although current health and mana are secret.

## XP food and the Well Fed buffs (#19), 2026-09-25, build 70009

**XP food's buff.** Eating Beer Basted Boar Ribs (item 2888, item spell 1248380 "Nutritious Food") gives **one** aura:
- Its name is **"Well Fed"**, the same as ordinary food. Its spell ID is **1248422**.
- The buff tooltip reads: *"Your Strength is increased by 1. Experience gained from kills increased by 5%."*
- There is no separate XP aura, and the aura ID is not the item's spell ID.

**`/apo scan3`** (`docs/forever-wellfed-70009.tsv`, COMPLETE):
- 31,716 spells exist; the highest is 1,322,007, and the scan went to 1,522,007.
- No unnamed spell was skipped.
- **13 names are hidden** (never served by the client): 27997, 32837, 32980, 32981, 34320, 34584, 37214, 37655, 38334, 39440, 243798, 243809, 245186. All are far below Forever's new food spells, which start at 1.22M. Blizzard keeps some data encrypted until it is discovered, so a later build may reveal them.
- (The first run was saved by an earlier probe; the TSV was converted to the new format from it, with the same data.)

**30 spells are named "Well Fed"**, in four groups:
- **Vanilla, 10 IDs:** 19705, 19706, 19708, 19709, 19710, 19711, 24799, 24870, 25694, 25941. The descriptions are empty except 19708.
- **Forever, item-style text, 4 IDs:** 1225778, 1225779, 1225780, 1225782, e.g. "gain 25 Strength and 10 Stamina". These match the non-XP Forever foods: Prowler Steak, Filet o' Flank, Sunrise Omelette and the feasts.
- **Forever, "nutritious" family, 15 IDs covering 13 stats:** "A nutritious meal / A tasty drink has made you Well Fed, increasing your <stat>."
  - 1248406 Stamina, 1248420 Agility, 1248421 Intellect
  - **1248422 and 1302064 Strength**
  - **1248688 and 1294007 movement speed**
  - 1249519 Attack Power, 1249520 Spell Damage, 1249521 Fishing, 1249523 crit
  - 1249907 herbalism, 1249926 Spirit, 1249927 Healing Power
  - 1319310 Armor
- **1283082:** no text at all.

**Neither `C_Spell.GetSpellDescription` nor `C_TooltipInfo.GetSpellByID` shows the XP line**; the two returned the same text for every Well Fed spell. Only an active buff's tooltip shows it, so XP can't be read from spell data. The evidence that the "nutritious" family **is** the XP set:
- The 105 XP foods give 13 kinds of Well Fed (movement speed counted once for Westfall and Hyjal), and each kind has a "nutritious" aura.
- None of the 18 non-XP Well Fed foods (Vanilla sweets, Dirge's Chops, the four item-style Forever foods) gives a stat in that wording.
- One in-game measurement: 1248422.

**Second XP aura measured (2026-09-27):** eating Herb Baked Egg (item 6888, item spell 1248377 "Nutritious Food", +1 Stamina) gives `Well Fed#1248406`, in the "nutritious" family (Stamina). That makes two of the 15 confirmed in game.

**Level APIs:**
- `UnitLevel` = 11 and `GetMaxPlayerLevel()` = 60 at level 11.
- `GetMaxLevelForPlayerExpansion()` = 60.
- `IsXPUserDisabled()` = false.

## Applying a weapon coating from a secure button (#24), 2026-09-27, build 70009

Measured with `/apo applytest 20744` (Minor Wizard Oil) on a warlock with a two-handed staff, out of combat, standing still, `ActionButtonUseKeyDown = 1`:

| Attempt | Result |
|---|---|
| **A** (`type=item` + `target-slot` 16), main hand | **Applied.** No targeting cursor after the click; a 3-second cast (spell 25117); the oil already on the staff renewed. |
| **B** (`/use item:20744` + `/use 16` macro), main hand | **Applied**, the same way. |
| A, off hand (empty) | Failed at once (+0.00 s after the click): "Item is not ready yet." Cause undetermined (the probe does not record the item cooldown), so it says nothing about an empty hand. |
| B, off hand (empty) | Left a **targeting cursor**: `/use 17` had no weapon to aim at. |

- **Events, in order:** `UNIT_SPELLCAST_START`; then after 3 s `UNIT_SPELLCAST_SUCCEEDED`, `ENCHANT_SPELL_COMPLETED (true, <item location>)`, `UNIT_INVENTORY_CHANGED (player)`, `WEAPON_ENCHANT_CHANGED`.
- **Re-applying the same oil** raised no replace popup.
- **`GetWeaponEnchantInfo()`** out of combat: `true, <ms left>, 0, 2623` for the main hand. Minor Wizard Oil is **enchant ID 2623**. An oil has **0 charges**.
- **What it shows:** method A applies to the main hand in one click, renewing the same oil on a two-handed staff, out of combat, standing still, with `ActionButtonUseKeyDown = 1`. **Not shown:**
  - coating an uncoated weapon, or replacing a different coating;
  - combat, or the key-up setting;
  - the off hand, or a one-hander with a held off-hand item;
  - what method A does on an empty or unsuitable slot.
- **Consequence:**
  - The Weapon Oil button's **left-click** sets `target-slot1` 16 and applies to the main hand. **Right-click** leaves the cursor to pick any weapon, as before. A main hand that can't take a coating gets no target.
  - The poison buttons use method A on both clicks. Poisons and the off hand are not measured yet.
- **Confirmed on the Weapon Oil button (owner, same day):** left-click applied the oil straight to the main hand, and right-click gave the targeting cursor to pick the weapon. So the left-button variant `target-slot1` works on Forever.

## Action Bar 1's layout (#40), 2026-10-09, build 70291

`/apo bar <label>`, with Action Bar 1's settings changed in Edit Mode between runs. UIParent scale 0.640.

- **The bar is `MainActionBar`.** `MainMenuBar` is absent. Its fields: `isHorizontal`, `numRows`, `numButtonsShowable`, `buttonPadding`, `system = 0` (ActionBar), `systemIndex = 1` (MainBar).
- **`MainActionBar:GetSettingValue(Enum.EditModeActionBarSetting.X)` returns plain values:** IconSize in percent (90, 100, 120), IconPadding in pixels (2, 6), NumRows (1, 2), Orientation 0 or 1 (`Enum.ActionBarOrientation`: Horizontal 0, Vertical 1). This holds for a preset (Modern) and a custom layout ("My UI").
- **It reports a change straight away, while Edit Mode is still open and before Save.** A change reverted on leaving Edit Mode is gone by the next read, and no event fires while a slider moves.
- **The stored layout encodes differently:** `C_EditMode.GetLayouts()` keeps IconSize as a step (4 = 90%, 5 = 100%), and the presets are not in its `.layouts`: `activeLayout` counts them first. Apotheca reads the bar, not the layout.
- **`Enum.EditModeActionBarSetting`:** Orientation 0, NumRows 1, NumIcons 2, IconSize 3, IconPadding 4, VisibleSetting 5, HideBarArt 6, DeprecatedSnapToSide 7, HideBarScrolling 8, AlwaysShowButtons 9.

Geometry in UIParent units (`ActionButton1` stays 45 x 45; the icon size is its effective scale):

| Run | Icon size | Padding | Rows | Orientation | Button | Gap 1 to 2 | Row or column 2 |
|---|---|---|---|---|---|---|---|
| Modern preset | 100% | 2 | 1 | horizontal | 45 | 2.0 | |
| My UI | 90% | 2 | 1 | horizontal | 40.5 | 1.8 | |
| size120 | 120% | 2 | 1 | horizontal | 54 | 2.4 | |
| pad6 | 120% | 6 | 1 | horizontal | 54 | 7.2 | |
| rows2 | 120% | 6 | 2 | horizontal | 54 | 7.2 | button 7 is **above** button 1, 7.2 apart |
| vertical | 120% | 6 | 2 | vertical | 54 | 7.2, downward | button 7 is to the **right**, 7.2 apart |

- **Button size = 45 x icon size, and the gap = padding x icon size.**
- **NumRows counts columns when vertical,** as Apotheca's Rows does.
- **Horizontal rows stack upward** from button 1; Apotheca's wrap downward. Vertical: top to bottom, then columns to the right, as Apotheca does.
- **All eight action bars carry Retail's names** (`/apo bar bars`, build 70291, every bar shown at 90%, padding 2): `MainActionBar`, `MultiBarBottomLeft`, `MultiBarBottomRight`, `MultiBarRight`, `MultiBarLeft`, `MultiBar5`, `MultiBar6`, `MultiBar7`, each with `<bar>Button1` 45 wide, and each `GetSettingValue` read plain values. `API.ActionBarLayout(n)` gave 40.5 / 1.8 for every one, the same as bar 1's measured geometry.
- **The button frame** is the `UI-HUD-ActionBar-IconFrame` atlas (`-AddRow` with Hide Bar Art), on file 7948326, with an `IconMask`.

## Still to measure

- **Professions (#42), the gate for the profession bar.** `GetProfessions()` returns nil x7, so the bar will detect professions from spell IDs. The draft catalog (`PROF_CATALOG` in the probe) holds the Vanilla IDs, highest rank first. Run, out of combat unless noted:
  1. `/apo prof <label>` on characters with each profession (an enchanter, a miner/herbalist, a rogue, one with no primary profession), and once **in combat** (spell and Hearthstone cooldowns: secret?). It records, per candidate: name and rank text, `C_SpellBook.IsSpellKnown` / `IsSpellKnown` / `IsPlayerSpell` / `IsSpellInSpellBook`, the spellbook slot and its item info. Then every spellbook line and slot (spells the catalog misses) and every skill row as returned (collapsed headers kept), kept as `profProbe[<label>]`.
  2. **Train a rank** (First Aid, Fishing or Mining Apprentice to Journeyman), then `/apo prof <label>` again: does the old rank stay known, and which ID is in use? Learning and unlearning are logged all the time in `profEvents` (event, arguments, the catalog known after it), and the catalog known at `PLAYER_LOGIN` and `PLAYER_ENTERING_WORLD` in `profLoad`.
  3. `/apo proftest`: one secure button per known family (its rank in use) plus the Hearthstone, each bound to `CTRL-SHIFT-1`, `-2`, ... For each, click it, and press its key **with the cursor off the frame**. Do this on both `ActionButtonUseKeyDown` settings, and in combat. The verdict line says what happened: `window`, `cursor`, `channel`, `tracking`, `succeeded`, `error`, `BLOCKED`, and the number of casts. A press should be one cast. `/apo proftest hide`, then a key: does a CLICK binding act on a hidden button? `/apo proftest close` clears the bindings.

  Exit the game to write `SavedVariables/ApothecaProbe.lua` (`profProbe`, `profEvents`, `profLoad`, `profTests`).

- **Poisons and the off hand (#24).** The main hand is measured with an oil (above). `/apo applytest <itemID>` shows four buttons:
  - method A (`type=item` + `target-slot`) for each hand;
  - method B (the `/use item:<id>` + `/use 16|17` macro) for each hand.

  Each click prints a verdict and is kept in `ApothecaProbeDB.applyTests`. To measure, with a dual-wielding rogue and real poisons: each method on each hand, re-applying the same poison, replacing with another family (the replace popup), moving while applying, and in combat. Record which events fired.

- **`C_Item.UseItemByName` on a real item** from the right-click alternate "Use X instead?" popup.
- **Clicks in combat.** Measured out of combat only, since food can't be eaten in combat. Check once with a potion.
- **Clicks with `ActionButtonUseKeyDown = 0`**, the other edge. The porting guide measured it with a forced attribute; Apotheca hasn't been checked on it yet.
- **Elixir and flask stacking.** This needs a character high enough to use them, and waits on issue #4.
