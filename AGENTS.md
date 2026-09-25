# Apotheca — Agent Instructions

## What This Repository Is

**Apotheca** is a World of Warcraft addon targeting **WoW: Forever 1.60.1** (interface `16001`): Vanilla content running on Blizzard's Retail (Mainline) API. It displays a smart consumable action bar for healers that automatically scans bags and presents the best available potions, food, drink, buff food, scrolls, weapon oils, elixirs/flasks, and bandages as clickable buttons. There is no build system and no compiler: it is pure Lua executed by the game client, with an offline Lua 5.1 test suite in `tests/`.

**TBC Classic Anniversary is no longer supported.** v1.0.5 was the final TBC release; it stays on CurseForge for Anniversary players, and the code is archived on the `tbc-anniversary` branch / `v1.0.5` tag. Do not add flavor branching for it.

Read `C:\Projects\References\PORTING-TBC-TO-FOREVER.md` before touching an unfamiliar API, and `docs/FOREVER-PROBE.md` for what was measured in game for this addon. The full declared API surface is `C:\Projects\References\forever-api-1.60.1.70009.md`.

## Repository Layout

```
Apotheca.toc           — WoW addon manifest (interface version, files list, SavedVariables)
ApothecaCompat.lua     — Apotheca.API: every moved or removed API; loads first
ApothecaItems.lua      — GENERATED item data (Apotheca.DATA); see Item Data
Apotheca.lua           — Main addon: all logic, item data, frame creation, events
Apotheca_Options.lua   — In-game options panel: tabbed UI, DB read/write helpers
Tools/ApothecaProbe/   — DEV-ONLY addon (never packaged): /apo probe, /apo scan, /apo scan2; `deploy.ps1 -Probe`
.pkgmeta               — BigWigs packager config (release packaging only, not used locally)
tests/                 — Lua 5.1 unit tests against a strict-globals stub; tests/run.ps1
Tools/deploy.ps1       — deploy to the local Forever AddOns folder
Tools/*.py, *.lua      — scan export, item-table generator, consumables reference
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
- **Secret values**: the player's current health and mana are secret **even out of combat** (builds 69977 and 70009), and comparing one throws. Auras throw in combat. `API.PlayerMissing()` and `API.PlayerAuras()` return nil for "unknown"; callers must treat nil as unknown, never as missing or full (`== false`, not `not`). Health-dependent features (waste prevention, right-click alternate, smart healthstone) stay in the code but are dormant and greyed out while the read is refused.
- **Showing fullness (`fullTint`, #6)**: the client colours a texture by current health or mana through a colour curve it evaluates itself (`UnitHealthPercent` / `UnitPowerPercent` with a curve). The returned channels may be secret, and **even `r ~= nil` throws on a secret**. So the channels never leave `ApothecaCompat.lua`: `API.PaintFullness(resource, textures)` paints and returns a plain boolean. `tests/test_tint.lua` fails if any other file calls the curve functions or `GetRGB`.
- **SavedVariables load back since build 1.60.1.70009** (confirmed with a full exit and relaunch, 2026-09-25). Through 69977 they were written but never read, and everything reset at login. `API.SV_BROKEN_THROUGH_BUILD` keeps the "not loaded" login line to those builds. The sentinel stays: it proves the load at every login, and would notice a regression. Migrations in `InitDB` now run on real saved data, so every settings change needs one. `ApothecaDB.svLoadCheck` is written every session and must never be given a default: finding it at load is how the fix will be noticed.
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
**The item tables are generated, never hand-written.** Forever changed restore values, buff food and elixirs relative to Vanilla, and adds items no Vanilla list has, so the only trustworthy source is the client itself:

1. `pwsh Tools/deploy.ps1 -Probe` (the scan lives in the dev-only probe addon). In game, out of combat, in one session (the scan is kept only in memory until the file is written at logout): `/apo scan`, then `/apo scan2`, then `/reload` to write the file. `scan` walks every item ID with `C_Item.GetItemInfoInstant` (the client's item DB, no cache needed) and reads each consumable's tooltip and item spell; `scan2` loads the spells whose "Use:" text was missing.
2. `lua5.1 Tools/export_scan.lua <WTF>/Account/<id>/SavedVariables/Apotheca.lua docs/forever-consumables-<build>.tsv`
3. `python Tools/build_item_tables.py docs/forever-consumables-<build>.tsv`, which writes `ApothecaItems.lua` (`Apotheca.DATA`). Read its "skipped" report and the diff.
4. `python Tools/consumables_reference.py docs/forever-consumables-<build>.tsv C:/Projects/References/forever-consumables-<version>.<build>.md` refreshes the shared human-readable catalog, and copy the TSV next to it. Diffing two builds' catalogs shows what Blizzard changed.

To change what the addon offers, change the generator or the role profiles, not `ApothecaItems.lua`. `tests/test_items.lua` pins the shape (strongest first, no duplicates) and the decisions (which elixir a healer or caster gets, rejuvenation after pure potions, battleground gates).

Wowhead's Forever database is useful for names but is not complete: on 2026-09-23 it had no Scroll of Protection at all, while the client has all four ranks.

What the data looks like:
- Items are classified by what their tooltip says (instant restore, restore over time, "Heals N damage"), **not by subclass**: the client files Dense Runecloth Bandage, some potions and every battleground ration under "Other". A Food & Drink item is always food (Scorpid Surprise "Heals 282 damage" and never says seated). Only real potions and draughts go on the potion buttons, because they share the potion cooldown; instant restoratives with their own cooldown (Whipper Root Tuber, Night Dragon's Breath, Lily Root, Tea with Sugar, mage mana gems) are reported as skipped, as are percentage FOOD and outdoor-zone-locked items. Food whose Well Fed bonus is no Buff Food stat (fishing, herbalism, movement) stays on the plain Food/Drink lists.
- `MANA_ITEMS`, `HEALTH_ITEMS`, `BANDAGE_ITEMS`: item IDs, strongest first. Percentage potions (Restored Healing / Mana Potion) are in `PERCENT_POTIONS`; `Apotheca.FindBestPotion` compares them with the best fixed potion held (`POTION_VALUE`) using the player's maximum, which is readable (only current health and mana are secret). A potion restoring both ranks as 25% weaker so the pure potion of its tier is used first; Discolored (backlash), sleep and gamble potions are left out.
- `FOOD_ITEMS` / `DRINK_ITEMS`: plain (no Well Fed) food and drink, `{ id, healthValue|manaValue, conjured?, restoresMana?|restoresHealth? }`. `conjured` comes from the tooltip's "Conjured Item" line, not the name (Mountain Spring Water is conjured). Food restoring both appears on **both** buttons; `CONJURED_ITEMS` (collapse Food and Drink into one button) is empty on Forever, because a low-level combined item would hide a high-level drink.
- `BUFF_FOOD_BY_STAT`: Well Fed food and drink by stat (`healing`, `spellDmg`, `intellect`, `spirit`, `stamina`, `strength`, `agility`, `attackPower`, `crit`, `armor`). Forever buff food also restores health or mana; the teas are mana drinks with +healing, the smoothies with +spirit. There is no mp5 food.
- `HEALTHSTONE_ITEMS`: `{ id, healValue }`, strongest first. Base stones now restore what fully Improved stones did in Vanilla. `FindBestHealthstone`'s smart rank is dormant while health is secret.
- `SCROLLS_BY_STAT`, `ELIXIR_CATALOG`: every scroll, elixir and flask tagged by stat with its buff `spell` ID. Active buffs are matched by spell ID, and also by the spell's localized name (`C_Spell.GetSpellName`), because "item spell ID == aura spell ID" is not measured for every item.
- `OILS`: `kind = "mana"` (default) or `"wizard"` (opt-in).
- `ZONE_RESTRICTED_ITEMS`: battleground-only items, `"pvp"` (any battleground) or `{ map = instance map ID, name = enUS name }`. The map ID is compared, so it works on any language; Darkspear Islands has no measured ID yet and falls back to the enUS name. `Apotheca.IsItemUsableHere(id)` gates them in `BuildBagMap`, so every finder (food, drink, bandage, potion) skips an item usable only elsewhere; outdoors `GetInstanceInfo()` returns the continent, so the gate is `instanceType == "pvp"`.

**Roles (#9).** `Apotheca.ResolveRole()` returns the role (`TANK` / `HEALER` / `DAMAGE`) and the profile key (`TANK` / `HEALER` / `CASTER` / `MELEE` / `AGILITY`). The order is:
1. Apotheca's own override (`db.role`).
1b. Only with `db.useGroupRole` (opt-in, off by default): the role assigned in the current group (`API.GroupRole`, from `UnitGroupRolesAssigned`). The owner found the party frame's "Set Role" often unset or stale.
2. The game's role selector (`API.SelectedRoles`: `C_LFGListRoles.GetRoles()`, which returns `{ tank, healer, dps }` as measured, then `GetLFGRoles()`). With several roles ticked, the class's preferred one (`CLASS_ROLES[cls].prefer`).
3. The class default.

**There is no spec to detect on Forever**: the talents are one redesigned tree per class, and the spec API reports one class-named spec (`docs/FOREVER-PROBE.md` runs 7 and 8). The group-assigned role is opt-in only (Codex review of #9, and the owner's experience with it). Damage maps to a profile by class; Druid and Shaman use `db.damageStyle` (`SPELL` / `PHYSICAL`). `Apotheca.UsesMana()` is a fixed class table (warriors and rogues have no mana), not `UnitPowerType`, which follows the current form. Buff-food priorities are saved per profile key, not per class; `InitDB` moves a usable per-class order to its class's default role. The role settings (`role`, `damageStyle`, `useGroupRole`) are **per character** (`ApothecaCharDB`, through `Apotheca.CharSetting` / `SetCharSetting`), so a Tank override on one character can't reach another on the shared profile. The resolved role is **cached**, because it's read on hot paths (every `UNIT_AURA`). `Apotheca.RefreshRole()` recomputes it; role events, role settings, every full update (quietly) and a 3-second out-of-combat poll call it, the poll because the event the Forever role selector fires is unmeasured. Only a changed role refreshes the options panel and requests an update. "Healer only" is `onlyWhenHealer`: the old `showOnlyHealingSpec` defaulted to true for everyone, so `InitDB` drops it instead of carrying it over.

**Role profiles** (`ROLE_PROFILES` in `Apotheca.lua`) decide what each role wants: buff food stat priority and the ordered stats for the Flask, Elixir (`battle` key) and Elixir 2 (`guardian` key) slots. Forever has no battle/guardian limit, so all three are offered independently. An item fitting both elixir slots goes to the first only; a slot whose buff is running offers nothing (any active flask fills the flask slot, via the generated `ALL_FLASK_SPELLS`, which includes flasks with no catalog stat); only slots with an item get a place on the bar. There are five profiles: TANK, HEALER, CASTER, MELEE and AGILITY. The bar shows for every role; "only while my role is Healer" (`onlyWhenHealer`) is opt-in.

### Key Functions
- `Apotheca.BuildBagMap()` — scans the carried bags (0–4 plus the reagent bag), returns `{ [itemID] = count }`
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

## Workflow

Work is tracked on GitHub and lands through pull requests.

1. **Open an issue first** describing the change.
2. **Branch** off `main` (`fix/<n>-...`, `forever/<n>-...`). Never commit to `main` directly.
3. **Open a PR** with `Closes #N`. The `package-check` workflow runs `luac`, the tests, the item-data drift and skipped-report checks, a dry-run package, and the zip-contents check.
4. **Run a Codex adversarial review** (`.claude/skills/codex-consult`) with the diff, `AGENTS.md`, `docs/FOREVER-PROBE.md` and the porting guide. Codex's sandbox has no network, so give it the PR discussion as a local file. Post the verdict on the PR, and address or rebut every finding there.
5. **Before merging, check the PR's reviews** (`gh api repos/Spotnick2/Apotheca/pulls/<N>/reviews`), not only its comments. The owner's own Codex posts follow-up reviews there, sometimes minutes after the last push.
6. Squash-merge, then delete the branch.

## Releasing

CurseForge builds from the repository webhook (project `1498195`) when it sees a tag, and publishes `CHANGELOG.md` as the release notes.

**Every tag needs a `CHANGELOG.md` entry, committed before the tag is pushed.** A tag without one publishes the *previous* release's notes against the new build.

1. Add a `## [<version>] - <date>` section at the top. Write it for players, not from the diff: what changed for someone using the addon, in their words. Anything that resets or behaves differently after updating goes under its own heading.
2. Commit, then tag and push: `git tag v2.0.1 && git push origin v2.0.1`.
3. **The release type comes from the tag name**: `alpha` → Alpha, `beta` → Beta, anything else → Release. This is a distribution channel, not a stability claim. CurseForge defaults every user to Release, so tag `beta` only to hold a build back on purpose. The game client being in beta is not a reason: say that in the notes and ship a Release.
4. Check the published file on CurseForge: the game flavor is **Forever** (derived from `## Interface: 16001`), and the zip holds exactly `Apotheca/` with the TOC and the files it lists. There is no probe and no `Tools`.

**Do not add a release workflow.** The webhook publishes; a packager workflow on tags would publish a second time, and without a secret it would silently skip CurseForge while still cutting a GitHub release. The `package-check` workflow's `-d` dry run publishes nothing.

TBC Classic Anniversary is archived on the `tbc-anniversary` branch (`v1.0.5`). Do not tag it again.

## Changing client builds

On a new Forever build, the login note tells players the build differs from `Apotheca.API.MEASURED_ON_BUILD` (`ApothecaCompat.lua`). To re-measure:

1. `/apidump` → `C:/Projects/References/forever-api-<version>.<build>.md` (see the porting guide).
2. `pwsh Tools/deploy.ps1 -Probe`, then `/apo probe` in and out of combat. Update `docs/FOREVER-PROBE.md`.
3. Re-scan the consumables and regenerate: see Item Data. Write the new `forever-consumables-<version>.<build>.md` to References and diff it against the previous build.
4. Bump `MEASURED_ON_BUILD`, and `WoW.build` in `tests/wow_stubs.lua`. Bumping without re-measuring silences the only reminder that the notes are stale.

## Key Conventions

- **Color prefix for addon chat**: `"|cff9966ffApotheca:|r "` (purple)
- **Fallback icon**: `"Interface\\Icons\\INV_Misc_QuestionMark"`
- **Options panel**: Built lazily on first `OnShow` in `Apotheca_Options.lua`. DB helpers `DBGet(...)` and `DBSet(value, ...)` accept vararg key paths into the active profile.
- **No libraries**: Do not introduce LibStub, Ace3, or any other library dependencies.
- **Buff checks** go through `ReadAuras` / `AurasHave` in `Apotheca.lua`: read the auras once, match by spell ID or by the spell's localized name (cached only once found: `GetSpellName` answers nil until the spell loads). Never add an English-name-only check.
- **Roles**, not classes, decide what the bar offers: see Roles under Item Data. `CLASS_ROLES` holds each class's default role, its preference among several ticked roles, and its damage profile.

Trust these instructions. Only search the codebase if the information here is incomplete or appears to be incorrect for the specific change you are making.
