
## `CHANGELOG.md`

```md
# Changelog

All notable changes to this project will be documented in this file.

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