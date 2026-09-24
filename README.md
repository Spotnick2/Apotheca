# Apotheca

**Apotheca** is a smart consumable bar for **World of Warcraft: Forever**. It scans your bags and shows the best potion, food, drink, buff food, flask, elixir, scroll, weapon oil, healthstone and bandage you carry as clickable buttons. The bar updates as your bags change.

It is built for healers (Priest, Paladin, Shaman, Druid). Casters and other roles are next ([#9](https://github.com/Spotnick2/Apotheca/issues/9)).

> **TBC Classic Anniversary** players: 1.0.5 was the last Anniversary release. It stays available on CurseForge, but won't get updates.

## Known limitation: settings reset at login

The WoW: Forever client doesn't load addon settings back yet. This affects every addon, not only Apotheca. Your Apotheca settings therefore go back to defaults each time you log in, and Apotheca says so in chat at login. Once Blizzard fixes the client, settings will stick without any change on your side.

## What it offers

| Button | Picks |
|---|---|
| Mana / Health | The strongest potion you carry. Rejuvenation potions come after plain potions of the same strength. Percentage potions (Restored Healing 30%, Restored Mana 20%) are compared using your own maximum health and mana. |
| Healthstone | The strongest stone. |
| Food / Drink | The best plain food and water. Conjured items are preferred unless vendor food is clearly better; the threshold is configurable. Food that restores both health and mana can appear on both buttons. |
| Buff food | Well Fed food for your stat priority. On Forever that means the teas (mana + healing), the smoothies (mana + spirit), and the new cooking. |
| Flask / Elixir / Elixir 2 | Three separate slots, each offering its best item for your role on its own: Distilled Wisdom, Cleric's Elixirs, Mageblood… Forever has no TBC-style battle/guardian elixir limit. Which elixirs stack with each other hasn't been measured yet; if two don't, please report it. A slot whose buff is already running offers nothing, so a misclick can't waste a two-hour flask. |
| Spirit / Protection scroll | The strongest scroll. |
| Weapon oil | Mana oils; wizard oils are optional. |
| Bandage | The strongest bandage. Battleground bandages are only offered inside their battleground. |

Every value comes from the WoW: Forever client itself, not from a Vanilla database, because Forever changed many of them. For example, Nightfin Soup now gives spell damage, and a plain healthstone restores what an Improved one did in Vanilla.

Battleground-only items (PvP draughts, Warsong Gulch, Arathi Basin, Alterac Valley and Darkspear Islands rations and bandages) are offered only inside their battleground. Darkspear Islands is new in Forever, and its items are recognised on English clients only for now.

Buffs are recognised on every client language.

## Also

- Ready check: missing buffs glow (buff food, flask and elixirs, scrolls, weapon oil).
- Global or per-character profiles.
- Horizontal or vertical layout, rows, icon size and padding.
- Visibility: always, in combat only, out of combat only, or hidden.
- Hold **Alt** to drag the bar (unless locked).
- Debug mode: clicks don't consume anything.

**Waste prevention** (not using food or water at full health or mana) and **smart healthstone rank** are greyed out on WoW: Forever. The client doesn't let addons read your current health or mana, even out of combat. They switch back on by themselves if Blizzard ever allows it.

## Slash commands

```text
/apo          open the options
/apo status   explain, per button, why it is or isn't clickable
/apo debug    toggle debug mode (clicks don't consume items)
```

## Issues

Report bugs at <https://github.com/Spotnick2/Apotheca/issues>. For something wrong with a button, `/apo status` output helps.
