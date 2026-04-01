# Apotheca

**Apotheca** is a smart consumable bar for **World of Warcraft: The Burning Crusade Classic / Classic Anniversary** focused on healer-friendly recovery and buff upkeep.

It builds a compact on-screen bar that automatically selects the best available consumables from your bags and presents them as clickable buttons.

## Features

- Smart consumable bar with automatic bag scanning
- Healer-focused recovery and maintenance items
- Support for:
  - Recovery potions / runes / stones
  - Food and drink
  - Buff food
  - Flasks and elixirs
  - Spirit scrolls
  - Protection scrolls
  - Weapon oils
- Character-specific or global profiles
- Options panel with configurable layout and behavior
- Horizontal or vertical layout
- Adjustable rows, icon size, and padding
- Visibility rules:
  - Always visible
  - In combat only
  - Out of combat only
  - Hidden
- Optional healer-spec-only display
- Optional empty button display
- Optional anti-waste behavior to avoid using food/drink at full health or mana
- Ready check glow support for missing buffs:
  - Buff food
  - Scrolls
  - Weapon oil
- Debug mode for safe testing

---

## Supported Button Types

Apotheca dynamically shows buttons based on your settings and what is available in your bags.

### Core Recovery
- Mana consumables
- Health consumables
- Runes / equivalent recovery items
- Food
- Drink

### Buff Maintenance
- Buff food
- Spirit scrolls
- Protection scrolls
- Weapon oils

### Elixirs and Flasks
Depending on your settings, Apotheca can:
- prefer flasks
- prefer separate elixirs
- auto-pick the best available option

---

## Profiles

Apotheca supports:

- **Global profile**
- **Character-specific profile**

This lets you keep different settings on different characters while still having a shared default if you want one.

---

## Options

Apotheca includes an in-game options panel where you can configure:

- Enable / disable the addon
- Only show in healing spec
- Show empty buttons
- Lock bar position
- Prevent waste
- Visibility mode
- Orientation
- Number of rows
- Icon size
- Icon padding
- Buff food behavior and priority
- Elixir / flask mode
- Scroll toggles
- Weapon oil behavior
- Debug mode

---

## Slash Commands

```text
/apotheca
/apo