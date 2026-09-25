# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### Added
- **Apotheca is for every role now, not just healers.** It follows the role you tick in the game's own role selector (Tank / Healer / Damage), or your class if you haven't picked one. You can also set the role yourself in the options. That's handy for a healer questing solo who wants caster food. In a group, you can opt in to use the role set on the party frame.
- **A Tank role:** stamina and armor buff food, Flask of the Titans, and armor and stamina elixirs.
- **Damage roles pick the right items:** casters get spell damage and intellect, warriors strength, and rogues and hunters agility. Druids and Shamans choose Spell or Physical damage in the options.
- **Intellect, Stamina, Strength and Agility scroll buttons**, next to Spirit and Protection. Each role gets the scrolls it uses:
  - Healers and casters: Spirit and Intellect
  - Tanks: Stamina
  - Melee and agility classes: Strength and Agility
  - Every role: Protection
  - Every class with mana (hunters, paladins, druids…): Intellect as well

  A scroll counts as not needed while a buff it doesn't stack with is up, such as Arcane Intellect for Intellect or Power Word: Fortitude for Stamina.
- **Mana Gem button for mages** (Jade, Citrine, Ruby), separate from mana potions because gems have their own cooldown.
- **Full health / mana tint:** food, drink, potions, healthstones, bandages and runes turn grey while what they restore is full. Display only: a click still uses the item.

### Changed
- The bar shows for every class. "Only show on healer classes" became "Only show the bar while my role is Healer", and it's off by default.
- Warriors and rogues no longer see mana buttons.
- Buff food priority is saved per role, so switching from Healer to Damage switches your food too.

## [2.0.0] - 2026-09-24

**Apotheca now runs on World of Warcraft: Forever.** It is no longer for TBC Classic Anniversary: Anniversary players should stay on 1.0.5, which remains on CurseForge.

### Read this after updating
- **Your settings reset at every login.** The WoW: Forever client doesn't load addon settings back yet, and this is true for every addon. Apotheca tells you so in chat. When Blizzard fixes it, settings will stick without an update.
- **Waste prevention, the right-click alternate and smart healthstone rank are greyed out.** WoW: Forever doesn't let addons read your current health or mana, even out of combat, so Apotheca can't tell whether you're full. The options come back by themselves if that ever changes. Until then, food and water are never blocked, and the Healthstone button offers your strongest stone.
- **"Only show in healing spec" is now "Only show on healer classes".** Forever has one spec per class and no talent trees, so the class is all there is to go on.
- **The Battle and Guardian elixir buttons are now Flask, Elixir and Elixir 2**, and they work differently: see below.

### Added
- Every table is rebuilt from what the Forever client itself reports. That brings in:
  - the teas (mana with +healing) and smoothies (mana with +spirit)
  - Cleric's Elixirs, the Mageblood tiers, and the Owl and Whale elixirs
  - Mountain Spring Water, the new conjured water
  - Drinkable Stratholme Holy Water
  - Dense Runecloth Bandage
  - the Restored and Perishable potions
  - Forever's new cooking
- Restore values are Forever's own, which often differ from Vanilla's.
- Flask, Elixir and Elixir 2 are offered as separate slots, because Forever has no TBC battle/guardian elixir limit. A slot whose buff is already running offers nothing, and any active flask counts, so a misclick can't waste a two-hour flask. Which elixirs stack with each other isn't measured yet: please report any pair that doesn't.
- Percentage potions (Restored Healing Potion 30%, Restored Mana Potion 20%) are compared with your other potions using your own maximum health and mana. The choice updates when your maximum changes.
- Battleground-only items (PvP draughts, and the Warsong Gulch, Arathi Basin, Alterac Valley and Darkspear Islands rations and bandages) are offered only inside their battleground. Darkspear Islands items are recognised on English clients only for now.
- Buff food priorities now cover Healing Power, Spell Damage, Intellect, Spirit, Stamina, Strength, Agility, Attack Power, Crit and Armor. Forever buff food has no mp5.
- A login note when your game build differs from the one Apotheca was tested on.

### Fixed
- Buffs are recognised on every client language. Previously the ready-check glows only worked in English.
- Buttons respond however your client is set to act, on press or on release. One click still uses one item.
- Food that restores both health and mana appears on both the Food and Drink buttons. It no longer merges them into a single button.
- The addon list shows an icon instead of a question mark.

## [1.0.5] - 2026-09-23

**This is the final release for TBC Classic Anniversary.** From 2.0.0, Apotheca targets World of Warcraft: Forever. 1.0.5 stays available on CurseForge for Anniversary players, but it will not get further updates.

### Added
- Added live cooldown swipes on bar buttons, so the cooldown animation starts the moment an item is used instead of only after combat ends.
- Added live stack counts, so item counts tick down during combat instead of waiting for combat to end.
- Added mana-aware food handling: food that also restores mana is now only blocked when both health **and** mana are full.
- Added `/apo status`, which prints why each visible button is or isn't clickable (debug mode, waste prevention, missing item, combat).
- Added a dedicated **Healthstone** button covering every rank from Minor through Master, in all three Improved Healthstone variants. Because all healthstone ranks share one cooldown, the button offers the smallest stone that still covers your missing health rather than burning the biggest one on a scratch; the tooltip shows how much it restores and why that stone was chosen. Smart ranking can be turned off in the options to always offer the strongest stone.

### Fixed
- Fixed the Drink button missing **Conjured Glacier Water** entirely. It was dropped in 1.0.4, so a mage's best water could never be offered and **Purified Draenic Water** was picked instead. Glacier Water is back and, restoring the same 7200 mana, is now preferred as the conjured option with Purified Draenic Water as the right-click alternate.
- Fixed wrong mana values and wrong names throughout the drink list. **Purified Draenic Water** was listed as "Filtered Draenic Water" at 4800 (really 7200), **Filtered Draenic Water** as "Sweetened Goat's Milk" at 3600 (really 5100), **Conjured Mountain Spring Water** at 4800 (really 5100), and **Morning Glory Dew** at 2400 (really 2934). Drinks are now ranked by their real tooltip values.
- Fixed the Food button badly undervaluing **Conjured Croissant** at 4800 health when it restores 7500, which made vendor food win the conjured comparison and offered a mage the wrong food.
- Fixed the food list containing item IDs that are not food at all. `33662`, listed as **Homemade Cherry Pie**, is a weapon; `27636`, listed as **Roasted Quail**, is Bat Bites, a level 5 food restoring 247 health. Homemade Cherry Pie and Roasted Quail are now present under their real IDs, and Homemade Cherry Pie no longer claims to restore mana — it restores health only.
- Fixed six more mislabelled food entries whose IDs pointed at different items than their names claimed, including **Talbuk Steak**, **Mag'har Grainbread**, **Lynx Steak**, **Ogri'la Chicken Fingers**, **Alterac Swiss**, and **Dried King Bolete**. Every food entry now matches its real item and tooltip value.
- Fixed three food entries (**Sour Goat Cheese**, **Crusty Flatbread**, **Salted Venison**) that are Wrath-era items and do not exist on this client. They have been removed.
- Fixed the Food and Drink buttons ignoring several common vendor consumables at tiers they already covered: **Mag'har Mild Cheese** and **Zangar Trout** (7500 health), **Garadar Sharp** and **Sunspring Carp** (4320 health), and **Silverwine** (5100 mana). Carrying only one of these left you with no item on the button at all.
- Fixed **Conjured Cinnamon Roll** being treated as a combined food-and-drink item. It restores health only, so carrying one collapsed the Food and Drink buttons into a single biscuit button and left you with no water. It is now ranked as ordinary conjured food, and **Conjured Sourdough** was added to cover the level 35 tier.
- Fixed instance-restricted potions being offered outside the instances they work in. **Cenarion Mana Salve**, **Auchenai Mana Potion**, and the matching healing versions showed up on the bar anywhere, even though they can only be drunk inside Coilfang Reservoir and Auchindoun respectively. All six restricted potions — Cenarion, Auchenai, and Bottled Nethergon — are now offered only while you are inside their own instances, and the bar rescans on zone change so they appear the moment you zone in.
- Fixed the Health button missing **Bottled Nethergon Vapor** and **Cenarion Healing Salve** entirely, and mislabelling **Auchenai Healing Potion** as a Tempest Keep item.
- Fixed waste-prevention **Block** giving no feedback. A blocked button — most often a conjured mana biscuit at full health and mana — simply did nothing when clicked. The tooltip now says why the button is blocked, and clicking it prints an explanation instead of silently ignoring the click.
- Fixed the bar unlocking itself: the purple **Drag to move** overlay could get stuck on after a missed Alt key press, leaving the bar movable for a while. The overlay now follows the real Alt key state and clears itself automatically.
- Fixed the bar staying attached to the cursor when a drag was interrupted.
- Fixed bar buttons responding to both the press and the release of a click, which could use an item twice from a single click. Buttons now act on press only.
- Fixed every bar button being completely unclickable. Making buttons act on release alone stopped them from doing anything at all on this client, which only performs a button's action on the press.
- Fixed the waste-prevention confirmation appearing for resources that were no longer full. The bar cannot refresh during combat, so a conjured mana biscuit blocked at full health and mana would keep asking for confirmation even after mana had been spent. Buttons now re-check current health and mana when clicked and use the item without prompting when nothing would be wasted.

## [1.0.4] - 2026-04-08

### Added
- Added right-click alternate support for recovery items when waste prevention is set to **Ask**.
- Added a configurable **Conjured preference threshold** to control when non-conjured food or drink should be preferred over conjured items.
- Added a dedicated **Button Order** tab in the options panel with move up / move down controls and a reset to default option.
- Added a **Profile** tab with support for switching between global and character-specific settings from the UI.
- Added tooltip hints showing the alternate item available on right-click for food and drink buttons.
- Added support for many more recovery food and drink items, including additional conjured, vendor, quest, drop, and cooked options.

### Changed
- Reworked the options panel into a tabbed layout for easier navigation.
- Food and drink selection is now smarter:
  - conjured food and drink are preferred by default,
  - non-conjured alternatives are chosen only when they are significantly better based on the configured threshold,
  - the non-primary choice is preserved as an alternate right-click option.
- Health consumable handling now separates **healthstones** from healing potions instead of mixing them in the same item list.
- Recovery buttons now expose clearer alternate behavior and better waste-prevention flow.

### Fixed
- Corrected healthstone priority and expanded healthstone coverage to include the proper improved and base ranks.
- Added missing healing potion tiers to improve fallback health consumable selection.
- Added missing drink tiers and corrected food/drink coverage for lower and mid-level consumables.
- Prevented secure button updates while in combat to avoid combat-lockdown issues during bar refreshes.
- Cleared temporary alternate-item swaps on refresh so buttons always return to their proper primary item state.

## [1.0.3] - 2026-04-05

- Fixed changelog packaging

## [1.0.2] - 2026-04-05

### Added
- Added a **Bandage** button that shows the best available bandage from your bags.
- Added **Bandage** options in the settings panel, including an enable/disable toggle.
- Added automatic **Recently Bandaged** detection to disable bandage usage while the debuff is active.
- Added **custom button ordering** in options, with up/down controls and a reset-to-default action.
- Added support for more **conjured food and drink** items, including stronger mage water/food entries.
- Added an **Ask first** waste-prevention mode that shows a confirmation popup before using recovery items at full health/mana.

### Changed
- Replaced the old boolean **preventWaste** setting with a new **preventWasteMode** setting:
  - `BLOCK`
  - `ASK`
  - `DO_NOTHING`
- Added profile migration so old saved settings automatically convert to the new waste-prevention mode.
- Updated food selection to always prefer the **highest healing food**, and prefer **conjured food on ties**.
- Updated drink selection to better prefer the **best available mana drink**, with **conjured drinks preferred on ties**.
- Updated layout logic so visible buttons now follow the user’s **custom button order**.
- Health and mana potion buttons now remain visible as **greyed-out empty slots** when no item is available.
- Food and drink buttons now remain visible as empty slots instead of disappearing when unavailable.
- Empty buttons now consistently show their **desaturated placeholder icon** outside of debug mode.

### Fixed
- Fixed compatibility for old saved profiles by migrating legacy waste-prevention settings.
- Fixed bandage usability handling so the bandage button is disabled when it cannot legally be used and re-enabled when the debuff expires.
- Fixed recovery-button waste prevention so it can now either block usage, ask for confirmation, or allow usage depending on configuration.
- Fixed layout refresh behavior so button visibility and ordering stay in sync after settings changes.

### Notes
- The new default button order now includes **Bandage** as a supported category.
- Existing custom orders are validated to remove duplicates/unknown keys and automatically append any missing buttons.


## [1.0.0] - 2026-04-01

### Added
- Initial full public release of Apotheca
- Smart consumable action bar for healer-focused gameplay
- Automatic bag scanning and best-item selection
- Support for recovery consumables
- Support for food and drink buttons
- Support for buff food buttons
- Support for spirit and protection scrolls
- Support for weapon oil management
- Support for elixir and flask handling
- Ready check glow support for missing consumable buffs
- In-game options panel
- Global and character-specific profile support
- Configurable visibility modes
- Configurable layout options:
  - orientation
  - rows
  - icon size
  - icon padding
- Optional healer-spec-only visibility
- Optional empty button display
- Optional prevent-waste behavior
- Debug mode with safe non-consuming clicks
- Slash commands for opening options and toggling debug

### Improved
- More complete consumable coverage beyond simple potion buttons
- Better configurability for healer and support gameplay
- Dynamic layout refresh based on active settings and available item categories

### Notes
- This release establishes the first complete configurable version of Apotheca
- Future updates may expand item coverage, polish UI behavior, and refine category logic