# Apotheca

**Apotheca** is a smart consumable bar for **World of Warcraft: Forever**. It scans your bags and shows the best potion, food, drink, buff food, flask, elixir, scroll, weapon oil, healthstone and bandage you carry as clickable buttons. The bar updates as your bags change.

It is built for healers (Priest, Paladin, Shaman, Druid). Casters and other roles are next ([#9](https://github.com/Spotnick2/Apotheca/issues/9)).

> **TBC Classic Anniversary** players: 1.0.5 was the last Anniversary release. It stays available on CurseForge, but won't get updates.

## Settings

Your settings are saved per profile (global or per character), and your role choices are saved per character. The first WoW: Forever beta builds didn't load addon settings back at all. That was a client bug, fixed in build 1.60.1.70009.

## What it offers

| Button | Picks |
|---|---|
| Mana / Health | The strongest potion you carry. Rejuvenation potions come after plain potions of the same strength. Percentage potions (Restored Healing 30%, Restored Mana 20%) are compared using your own maximum health and mana. |
| Healthstone | The strongest stone. |
| Food / Drink | The best plain food and water. Conjured items are preferred unless vendor food is clearly better; the threshold is configurable. Food that restores both health and mana can appear on both buttons. |
| Buff food | Well Fed food for your stat priority. On Forever that means the teas (mana + healing), the smoothies (mana + spirit), and the new cooking. |
| XP food *(optional, off by default)* | While you're levelling: food or drink with Forever's 5% kill-XP bonus that you can eat at your level: a stat your role uses first, then the highest level. When you leave combat without that buff, it glows for a few seconds as a reminder. |
| Flask / Elixir / Elixir 2 | Three separate slots, each offering its best item for your role on its own: Distilled Wisdom, Cleric's Elixirs, Mageblood… Forever has no TBC-style battle/guardian elixir limit. Which elixirs stack with each other hasn't been measured yet; if two don't, please report it. A slot whose buff is already running offers nothing, so a misclick can't waste a two-hour flask. |
| Spirit / Protection scroll | The strongest scroll. |
| Weapon oil | By role: healers get mana oil, casters wizard oil (a Druid or Shaman on Spell damage too), tanks and physical damage mana oil; you can choose instead. Only an oil you can use yet. Left-click applies it to your main-hand weapon; right-click lets you pick the weapon. |
| Weapon stones *(experimental, chosen per character and hand)* | Pick "Damage stone first" or "Elemental first" for a hand: a sharpening stone for a sharp weapon, a weightstone for a blunt one, Elemental (crit) for any. A stone on the main hand replaces the Weapon Oil button there. Not yet tried in game. |
| Poisons *(rogues, experimental, off by default)* | One button per hand: your strongest poison of the kind you pick for that hand (Instant and Deadly by default), applied to that weapon on click. Not yet tried on a rogue in game, so please report whether it works. |
| Bandage | The strongest bandage. Battleground bandages are only offered inside their battleground. |

Every value comes from the WoW: Forever client itself, not from a Vanilla database, because Forever changed many of them. For example, Nightfin Soup now gives spell damage, and a plain healthstone restores what an Improved one did in Vanilla.

Battleground-only items (PvP draughts, Warsong Gulch, Arathi Basin, Alterac Valley and Darkspear Islands rations and bandages) are offered only inside their battleground. Darkspear Islands is new in Forever, and its items are recognised on English clients only for now.

Buffs are recognised on every client language.

## Profession bar

An optional second bar (off by default: `/apo utility`, or the Profession Bar tab) that builds itself from the character's professions, so you don't set up the same action bar on every character:

- Cooking, First Aid and Fishing, and your professions' windows (Alchemy, Blacksmithing, Enchanting, Engineering, Leatherworking, Tailoring, Skinning, Smelting, Poisons).
- Their actions: Disenchant, Find Herbs, Find Minerals, Pick Lock, Bait and Tackle.
- Your Hearthstone.

Each action has its own key binding (Options > Keybindings > Apotheca). The key follows the action, so Disenchant on F9 is Disenchant on every character, wherever its button is. Tick what the bar may show and set the order in the options; it has its own position, layout and lock, and can match one of your action bars like the main bar.

Measured in game so far: Cooking, First Aid, Fishing, Enchanting, Tailoring, Leatherworking, Skinning, Disenchant and the Hearthstone. The others use the spell IDs from Vanilla and haven't been tried on Forever yet; please report one that doesn't show or doesn't work.

## Also

- Ready check: missing buffs glow (buff food, XP food, flask and elixirs, scrolls, weapon oil).
- Global or per-character profiles.
- Horizontal or vertical layout, rows, icon size and padding, or the icon size and padding of one of your action bars (Edit Mode), followed as you change it.
- Visibility: always, in combat only, out of combat only, or hidden.
- Hold **Alt** to drag the bar (unless locked).
- Debug mode: clicks don't consume anything.

**Waste prevention** (not using food or water at full health or mana) and **smart healthstone rank** are greyed out on WoW: Forever. The client doesn't let addons read your current health or mana, even out of combat. They switch back on by themselves if Blizzard ever allows it.

## Slash commands

```text
/apo          open the options
/apo status   explain, per button, why it is or isn't clickable
/apo debug    toggle debug mode (clicks don't consume items)
/apo utility  show or hide the profession bar
```

## Issues

Report bugs at <https://github.com/Spotnick2/Apotheca/issues>. For something wrong with a button, `/apo status` output helps.
