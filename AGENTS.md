# Apotheca — Agent Instructions

## What This Repository Is

**Apotheca** is a World of Warcraft addon targeting **WoW: Forever 1.60.1** (interface `16001`): Vanilla content running on Blizzard's Retail (Mainline) API. It displays a smart consumable action bar for healers that automatically scans bags and presents the best available potions, food, drink, buff food, scrolls, weapon oils, elixirs/flasks, and bandages as clickable buttons. There is no build system and no compiler: it is pure Lua executed by the game client, with an offline Lua 5.1 test suite in `tests/`.

**TBC Classic Anniversary is no longer supported.** v1.0.5 was the final TBC release; it stays on CurseForge for Anniversary players, and the code is archived on the `tbc-anniversary` branch / `v1.0.5` tag. Do not add flavor branching for it.

Read `C:\Projects\References\PORTING-TBC-TO-FOREVER.md` before touching an unfamiliar API, and `docs/FOREVER-PROBE.md` for what was measured in game for this addon. The full declared API surface is `C:\Projects\References\forever-api-1.60.1.69977.md`.

## Repository Layout

```
Apotheca.toc           — WoW addon manifest (interface version, files list, SavedVariables)
ApothecaCompat.lua     — Apotheca.API: every moved or removed API; loads first
Apotheca.lua           — Main addon: all logic, item data, frame creation, events
Apotheca_Options.lua   — In-game options panel: tabbed UI, DB read/write helpers
ApothecaProbe.lua      — throwaway /apo probe measurement tool (remove before release, #5)
.pkgmeta               — BigWigs packager config (release packaging only, not used locally)
tests/                 — Lua 5.1 unit tests against a strict-globals stub; tests/run.ps1
Tools/deploy.ps1       — deploy to the local Forever AddOns folder
docs/FOREVER-PROBE.md  — in-game measurements this addon depends on
.github/workflows/     — package-check: luac, tests, dry-run package, zip contents
CHANGELOG.md           — Version history
README.md              — Feature overview and slash command docs
AGENTS.md              — This file
CLAUDE.md              — Pointer to this file
```

No external libraries. No generated files.

## Language & Runtime

- **Language**: Lua 5.1 (WoW's embedded Lua engine)
- **WoW API target**: WoW: Forever, Retail/Mainline API (`Interface: 16001`; the format is `%d%02d%02d`, and `11601` is a transposed-digit bug)
- **Compat layer**: every moved API goes through `Apotheca.API` in `ApothecaCompat.lua` (item info/icon, container reads, item cooldown, auras, health/mana, event registration, click edges). Call through the table at call time; `Apotheca.lua` keeps thin local wrappers (`ContainerGetNumSlots`, `ContainerGetItemID`, `ContainerGetCount`, `SafeGetItemCooldown`, `GetItemInfo`) that do exactly that. Never call a removed global, and never call a WoW container or item global directly in new code.
- **Secret values**: the player's current health and mana are secret **even out of combat** on build 69977, and comparing one throws. Auras throw in combat. `API.PlayerMissing()` and `API.PlayerAuras()` return nil for "unknown"; callers must treat nil as unknown, never as missing or full (`== false`, not `not`). Health-dependent features (waste prevention, right-click alternate, smart healthstone) stay in the code but are dormant and greyed out while the read is refused.
- **SavedVariables do not load back on this client.** Everything resets at login. `ApothecaDB.svLoadCheck` is written every session and must never be given a default: finding it at load is how the fix will be noticed.
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
`"mana"`, `"health"`, `"healthstone"`, `"rune"`, `"recovery"`, `"food"`, `"drink"`, `"flask"`, `"battle"`, `"guardian"`, `"bufffood"`, `"spiritscroll"`, `"protectionscroll"`, `"weaponoil"`, `"bandage"`

### Item Data
All item lists are plain Lua arrays at the top of `Apotheca.lua`:
`MANA_ITEMS`, `HEALTH_ITEMS`, `RUNE_ITEMS`, `HEALTHSTONE_ITEMS`, `BANDAGE_ITEMS`, `CONJURED_ITEMS`, `FOOD_ITEMS`, `DRINK_ITEMS`, `BUFF_FOOD_BY_STAT`, `SPIRIT_SCROLL_ITEMS`, `PROTECTION_SCROLL_ITEMS`, `MANA_OIL_ITEMS`, `WIZARD_OIL_ITEMS`, `WEAPON_COATING_ITEMS`, `ELIXIRS`. Items are ordered highest-rank → lowest so `FindBestItem` returns the strongest available.

`HEALTHSTONE_ITEMS` is a list of `{ id, healValue }` ordered strongest → weakest. `FindBestHealthstone` returns `itemID, count, texture, healValue, isSmartPick`; with `db.healthstone.smartRank` on it picks the *smallest* stone covering the missing health (all ranks share one cooldown), falling back to the strongest when nothing covers it or health is full. The pick can only change out of combat — it is a secure `item` attribute write.

`ZONE_RESTRICTED_ITEMS` maps the six reputation-quartermaster potions (Cenarion / Auchenai / Bottled Nethergon) to their instance cluster, matched by `instanceMapID` with a localized-name fallback. `Apotheca.IsItemUsableHere(id)` gates them and is applied inside `FindBestItem`, so any new zone-locked consumable only needs an entry in that table. `ZONE_CHANGED_NEW_AREA` triggers the rescan.

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
   pwsh tests/run.ps1    # luac -p on every TOC file, then the strict-globals unit tests
   ```
   `tests/wow_stubs.lua` fails the run on the read of any global it does not stub: it is the list of APIs verified present on this client. Stub a new global only after confirming it in the API dump, and list removed names in `KNOWN_ABSENT`. Known gap: Lua 5.1 cannot make `secret == x` or a truth test throw, so review those by hand.
2. **In-game testing**: deploy to the client's AddOns folder and log in. Use `/apo debug` to enable debug mode (items are not consumed on click).
3. **Checklist for any change**:
   - New settings must be added to `PROFILE_DEFAULTS` with a default value.
   - New settings must survive `ApplyDefaults` (ensure the key exists in `PROFILE_DEFAULTS`).
   - If renaming a setting, add migration code in `InitDB()`.
   - New item lists must be ordered highest-rank → lowest.
   - New button keys must be added to `Apotheca.DEFAULT_BUTTON_ORDER` and `Apotheca.ALL_BUTTON_KEYS`.
   - Secure button attribute writes must be guarded with `if not InCombatLockdown() then`.
   - Secure buttons register **both** mouse edges: `RegisterForClicks(Apotheca.API.ClickEdges())`, which returns `"AnyUp", "AnyDown"`. On WoW: Forever the client's secure handler acts only on the edge where `down == useOnKeyDown`, so one click uses the item once (measured). A single edge is a dead button for anyone on the other `ActionButtonUseKeyDown` setting. Never set `typerelease`: the hold-release path reads it and would use the item twice.
   - Never call WoW container or item globals directly: go through `Apotheca.API`.
   - Register events through `Apotheca.API.RegisterEvents` / `RegisterUnitEvents`, which report a rejected event instead of throwing or failing silently.

### Local Deploy

The live install on this machine is:

```
C:\Program Files (x86)\World of Warcraft\_classic_beta_\Interface\AddOns\Apotheca\
```

Deploy with `pwsh Tools/deploy.ps1`. It copies the TOC and every Lua file it lists, and writes `## Version: dev` into the installed TOC only.

Installed files have diverged from the repo before (local edits made in the AddOns folder that existed nowhere in git). The script records a hash of everything it writes and refuses to overwrite a file changed since. Bring such edits into git first; `-Force` overrides.

## Key Conventions

- **Color prefix for addon chat**: `"|cff9966ffApotheca:|r "` (purple)
- **Fallback icon**: `"Interface\\Icons\\INV_Misc_QuestionMark"`
- **Options panel**: Built lazily on first `OnShow` in `Apotheca_Options.lua`. DB helpers `DBGet(...)` and `DBSet(value, ...)` accept vararg key paths into the active profile.
- **No libraries**: Do not introduce LibStub, Ace3, or any other library dependencies.
- **Healer classes**: `PRIEST`, `PALADIN`, `SHAMAN`, `DRUID`, in `HEALER_CLASSES`. Forever has one spec per class and no talent trees, so the class is the only healer signal.

Trust these instructions. Only search the codebase if the information here is incomplete or appears to be incorrect for the specific change you are making.
