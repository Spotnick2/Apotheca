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
    - Specklefin Feast and Grand Lobster Banquet became plain food (2451).
    - Wizard Oil went from +30 to +24, and Minor Wizard Oil from +15 to +8.
    - The Spellblasting, Frenzy and Mender's combat potions were retuned (not on the bar).
    - New: Shiny Silver Coin (286732).
- `MEASURED_ON_BUILD` is bumped to **70009**.

## Still to measure

- **`C_Item.UseItemByName` on a real item** from the right-click alternate "Use X instead?" popup.
- **Clicks in combat.** Measured out of combat only, since food can't be eaten in combat. Check once with a potion.
- **Clicks with `ActionButtonUseKeyDown = 0`**, the other edge. The porting guide measured it with a forced attribute; Apotheca hasn't been checked on it yet.
- **Elixir and flask stacking.** This needs a character high enough to use them, and waits on issue #4.
