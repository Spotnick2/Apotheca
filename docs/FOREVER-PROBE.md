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

## Still to measure

- **Run 3, in combat:** aura secrecy, cooldown and stack-count secrecy, and `GetWeaponEnchantInfo`.
- **`C_Item.UseItemByName` on a real item** from the right-click alternate "Use X instead?" popup.
- **Clicks, on a healer-class character:** one use per click, on left and right click, in and out of combat. This needs an item the bar knows, so it moves to #4.
- **Elixir and flask stacking.** This needs a character high enough to use them, and waits on issue #4.
