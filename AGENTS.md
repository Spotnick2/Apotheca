# Apotheca — Agent Instructions

## What This Repository Is

**Apotheca** is a World of Warcraft addon targeting **TBC Classic / Classic Anniversary** (interface version `20505`). It displays a smart consumable action bar for healers that automatically scans bags and presents the best available potions, food, drink, buff food, scrolls, weapon oils, elixirs/flasks, and bandages as clickable buttons. There is no build system, no compiler, and no test runner — this is pure Lua executed directly by the WoW game client.

## Repository Layout

```
Apotheca.toc           — WoW addon manifest (interface version, files list, SavedVariables)
Apotheca.lua           — Main addon (~2600 lines): all logic, item data, frame creation, events
Apotheca_Options.lua   — In-game options panel (~620 lines): tabbed UI, DB read/write helpers
.pkgmeta               — BigWigs packager config (release packaging only, not used locally)
CHANGELOG.md           — Version history
README.md              — Feature overview and slash command docs
AGENTS.md              — This file
CLAUDE.md              — Pointer to this file
```

No subdirectories. No external libraries. No generated files.

## Language & Runtime

- **Language**: Lua 5.1 (WoW's embedded Lua engine)
- **WoW API target**: TBC Classic Anniversary (`Interface: 20505`)
- **Container API shims**: Both `C_Container.*` (newer) and legacy globals (`GetContainerNumSlots`, etc.) are supported via shims at the top of `Apotheca.lua` — always use the shim functions (`ContainerGetNumSlots`, `ContainerGetItemLink`, `ContainerGetCount`, `SafeGetItemCooldown`), never call WoW globals directly in new code.
- **No external dependencies**: No LibStub, no AceDB, no Ace3 libraries.

## Architecture

### Global Namespace
Everything lives under a single global table: `Apotheca = {}` (declared at line 1 of `Apotheca.lua`). The options file also defines local helpers and attaches functions to the `Apotheca` table.

### Saved Variables
- `ApothecaDB` — global SavedVariables (profiles, active profile key)
- `ApothecaCharDB` — per-character SavedVariables (declared in `.toc` but reserved for future use)

### Profile System
```lua
ApothecaDB = {
    profiles    = { ["Global"] = { ... }, ["RealmName-CharName"] = { ... } },
    activeProfile = "Global"  -- or "RealmName-CharName"
}
```
- `DB()` (local in each file) always returns the active profile table.
- `PROFILE_DEFAULTS` (top of `Apotheca.lua`) is the canonical schema — add new settings here with defaults.
- `ApplyDefaults(dst, src)` fills in missing keys recursively; this runs on every load.
- Always add migration logic in `InitDB()` when renaming or changing the type of existing settings.

### Button Keys
The canonical set of button keys (also `Apotheca.DEFAULT_BUTTON_ORDER`):
`"mana"`, `"health"`, `"rune"`, `"recovery"`, `"food"`, `"drink"`, `"flask"`, `"battle"`, `"guardian"`, `"bufffood"`, `"spiritscroll"`, `"protectionscroll"`, `"weaponoil"`, `"bandage"`

### Item Data
All item lists are plain Lua arrays at the top of `Apotheca.lua`:
`MANA_ITEMS`, `HEALTH_ITEMS`, `RUNE_ITEMS`, `HEALTHSTONE_ITEMS`, `BANDAGE_ITEMS`, `CONJURED_ITEMS`, `FOOD_ITEMS`, `DRINK_ITEMS`, `BUFF_FOOD_BY_STAT`, `SPIRIT_SCROLL_ITEMS`, `PROTECTION_SCROLL_ITEMS`, `MANA_OIL_ITEMS`, `WIZARD_OIL_ITEMS`, `WEAPON_COATING_ITEMS`, `ELIXIRS`. Items are ordered highest-rank → lowest so `FindBestItem` returns the strongest available.

Food entries may carry `restoresMana = true` (e.g. Homemade Cherry Pie). `FindBestFood` returns that flag and `ResolveRecovery` exposes it as `rec.foodRestoresMana`, which waste prevention uses to require *both* health and mana to be full before blocking.

### Key Functions
- `Apotheca.BuildBagMap()` — scans bags 0–4, returns `{ [itemID] = count }`
- `Apotheca.FindBestItem(list, bagMap)` — first-match scan
- `Apotheca.FindBestFood/Drink(bagMap)` — conjured-vs-non-conjured with threshold logic
- `Apotheca.UpdateAllButtons()` — rebuilds bag map and refreshes all button states
- `Apotheca.RefreshButtonVisuals(countsToo)` — cooldown swipe and count text only; touches no secure attributes, so it is safe during combat lockdown
- `Apotheca.ResetLayout()` — forces full layout recalculation on next update

### Events
Registered in the `EVENTS` section near the bottom of `Apotheca.lua`. Key events: `ADDON_LOADED` (init DB), `PLAYER_LOGIN` (create options panel, first update), `BAG_UPDATE_DELAYED` (refresh buttons), `BAG_UPDATE_COOLDOWN` (combat-safe cooldown swipe), `PLAYER_REGEN_ENABLED/DISABLED` (combat visibility), `UNIT_AURA` (buff glow), `READY_CHECK` (glow missing buffs).

### Combat Lockdown
Secure button attributes (`type`, `item`) must **never** be set while `InCombatLockdown()` is true. Use `Apotheca.pendingUpdate = true` to defer updates and apply them in `PLAYER_REGEN_ENABLED`.

`Apotheca.UpdateAllButtons()` returns immediately during combat lockdown. Anything that must stay correct *during* a fight therefore cannot live inside it — either put it in a combat-safe path like `RefreshButtonVisuals`, or re-check the live state at the point of use. The waste-prevention ask overlay does the latter: `IsStillWasteful(btn)` re-reads health and mana on click, because the overlay it belongs to may have been armed before combat started.

### Drag Anchor
`ApothecaAnchor` is the purple "Drag to move" overlay shown while Alt is held over the bar. Its visibility is derived from live state in `UpdateAnchorState()` (`IsAltKeyDown()`, combat, `lockPosition`, visibility, mouse-over), driven by both `MODIFIER_STATE_CHANGED` and a throttled `OnUpdate`. Do not go back to showing or hiding it purely on key-event edges — a missed key-up leaves the bar stuck in the unlocked state. All drag teardown goes through `StopAnchorDrag()`.

## Build & Validation

There is **no local build step**. The addon runs directly in the WoW client.

**Release packaging** uses the [BigWigs packager](https://github.com/BigWigsMods/packager) configured via `.pkgmeta`. The `@project-version@` token in `Apotheca.toc` is replaced by the packager at release time — do not replace it manually in the repo.

### How to Validate Changes

1. **Lua syntax check** — the only validation available outside the game:
   ```
   luac -p Apotheca.lua Apotheca_Options.lua
   ```
   WoW globals are undefined outside the client, so syntax errors are the only reliable catch.
2. **In-game testing**: deploy to the client's AddOns folder and log in. Use `/apo debug` to enable debug mode (items are not consumed on click).
3. **Checklist for any change**:
   - New settings must be added to `PROFILE_DEFAULTS` with a default value.
   - New settings must survive `ApplyDefaults` (ensure the key exists in `PROFILE_DEFAULTS`).
   - If renaming a setting, add migration code in `InitDB()`.
   - New item lists must be ordered highest-rank → lowest.
   - New button keys must be added to `Apotheca.DEFAULT_BUTTON_ORDER` and `Apotheca.ALL_BUTTON_KEYS`.
   - Secure button attribute writes must be guarded with `if not InCombatLockdown() then`.
   - Secure buttons must register a single click edge (`RegisterForClicks("AnyUp")`). Registering both edges runs the secure handler twice per click and can use the item twice.
   - Never call WoW Container globals directly — use the shim functions.

### Local Deploy

The live install on this machine is:

```
C:\Program Files (x86)\World of Warcraft\_anniversary_\Interface\AddOns\Apotheca\
```

Only `Apotheca.lua`, `Apotheca_Options.lua`, and `Apotheca.toc` are deployed there. Two things to watch:

- The installed `.toc` needs a real version string in place of `@project-version@`, or the raw token shows in the addon list.
- Check the installed files against the repo before overwriting. They have diverged before — local edits were made directly in the AddOns folder and existed nowhere in git.

## Key Conventions

- **Color prefix for addon chat**: `"|cff9966ffApotheca:|r "` (purple)
- **Fallback icon**: `"Interface\\Icons\\INV_Misc_QuestionMark"`
- **Options panel**: Built lazily on first `OnShow` in `Apotheca_Options.lua`. DB helpers `DBGet(...)` and `DBSet(value, ...)` accept vararg key paths into the active profile.
- **No libraries**: Do not introduce LibStub, Ace3, or any other library dependencies.
- **Healer classes**: `PRIEST`, `PALADIN`, `SHAMAN`, `DRUID` — defined in `HEALER_SPEC` and `HEALER_CLASSES`.

Trust these instructions. Only search the codebase if the information here is incomplete or appears to be incorrect for the specific change you are making.
