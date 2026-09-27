"""
build_item_tables.py - generate ApothecaItems.lua from the client's own data.

WoW: Forever changed restore values, buff food and elixirs relative to
Vanilla, and adds items no Vanilla list has. So the item tables are not
written by hand: they are generated from what the client reports.

Input:  docs/forever-consumables-<build>.tsv, exported from an in-game
        `/apo scan` + `/apo scan2` run (ApothecaProbe.lua) with
        Tools/export_scan.lua. Columns: id, subClassID, subType, name,
        spellID, spellName, tooltip ("line | line | ...").
        docs/forever-wellfed-<build>.tsv, next to it: every spell named
        "Well Fed" (`/apo scan3`, Tools/export_wellfed.lua), for XP food.
Output: ApothecaItems.lua (Apotheca.DATA), loaded before Apotheca.lua.

Usage:
    python Tools/build_item_tables.py docs/forever-consumables-70009.tsv

Rerun after a new client build: re-scan in game, re-export, regenerate,
and review the diff. Anything the parser does not recognise is simply
left out, so read the "skipped" report it prints.
"""

import os
import re
import sys
from collections import defaultdict

SUB_POTION, SUB_ELIXIR, SUB_FLASK, SUB_SCROLL, SUB_FOOD, SUB_BANDAGE = 1, 2, 3, 4, 5, 7
SUB_OTHER = 8
RESTORE_SUBS = (SUB_POTION, SUB_FOOD, SUB_BANDAGE, SUB_OTHER)
PERCENT = re.compile(r'Restores (\d+)% (?:of your )?(health|mana)|(\d+)% of (?:your )?(?:total )?(?:health|mana)', re.I)


def kind(r):
    """What the tooltip says the item is: "potion" (instant restore),
    "food" (restore over time), "bandage", or None."""
    u = r['use']
    if r['sub'] not in RESTORE_SUBS or not u or r['quest'] or 'Healthstone' in r['name']:
        return None
    # A feast is PLACED for the group ("Serve a delicious feast...", "Lay
    # out Cookie's Feast..."); its tooltip quotes the food it serves, which
    # must not make the feast itself look like food in the bag.
    if re.match(r'Use: (Serve|Lay out|Set out)\b', u):
        return 'feast'
    # Food & Drink items are food, and so is anything eaten seated: Scorpid
    # Surprise (Food & Drink) says "Heals 282 damage over 21 sec" and never
    # mentions sitting, so the subclass has to decide, not the wording.
    if r['sub'] == SUB_FOOD or re.search(r'Must remain seated', u) or re.search(
            r'Restores [\d,]+ (?:health|mana)(?: and [\d,]+ (?:health|mana)| and (?:mana|health))? over', u):
        return 'food'
    if re.search(r'Heals [\d,]+ damage over', u):
        return 'bandage'
    # Only real potions go on the potion buttons: they share the potion
    # cooldown. Whipper Root Tuber, Night Dragon's Breath, Lily Root and
    # Tea with Sugar each have their own, and on the button would hide a
    # potion that is still ready.
    if re.search(r'Restores [\d,]+ to [\d,]+ (?:health|mana)', u):
        if r['sub'] == SUB_POTION or re.search(r'Potion|Draught', r['name']):
            return 'potion'
        return 'other-restore'
    return None

# Items to leave out whatever their tooltip says.
EXCLUDE_NAME = re.compile(r'^(Deprecated|Test |\[PH\])|\(TEST\)|McWeaksauce', re.I)


def num(s):
    return int(s.replace(',', ''))


def load(path):
    rows = []
    for line in open(path, encoding='utf-8'):
        p = line.rstrip('\n').split('\t')
        if len(p) < 7 or p[3] in ('nil', ''):
            continue
        tip = p[6]
        lines = [x.strip() for x in tip.split(' | ')]
        use = ' '.join(x for x in lines if x.startswith('Use:'))
        if not use:
            # /apo scan2 appends the spell description when the tooltip had
            # no Use: line; it carries the same text.
            m = re.search(r'\|\| DESC: (.*)$', tip)
            if m:
                use = 'Use: ' + m.group(1).strip()
        m = re.search(r'Requires Level (\d+)', tip)
        rows.append(dict(
            id=int(p[0]), sub=int(p[1]) if p[1] != 'nil' else -1, name=p[3],
            spell=int(p[4]) if p[4] not in ('nil', '') else None,
            use=use, lvl=int(m.group(1)) if m else 0,
            conjured='Conjured Item' in lines,
            quest='Quest Item' in lines,
            tip=tip,
        ))
    return [r for r in rows if not EXCLUDE_NAME.search(r['name'])]


# ------------------------------------------------------------------
# Where an item may be used
# ------------------------------------------------------------------

# enUS name -> instance map ID (8th return of GetInstanceInfo). The ID is
# what the addon compares, so the gate works on any client language; the
# name is only a fallback. Darkspear Islands is Forever-new and its ID is
# not measured yet (None): name only, so enUS only, until it is.
BATTLEGROUNDS = {
    'Warsong Gulch': 489, 'Arathi Basin': 529, 'Alterac Valley': 30,
    'Darkspear Islands': None,
}


def restriction(r):
    """None, "pvp" (any battleground), or (mapID, enUS name) of one battleground."""
    t = r['tip']
    if re.search(r'may only be used in PvP Battlegrounds', t, re.I):
        return 'pvp'
    for name, map_id in BATTLEGROUNDS.items():
        if re.search(r'(only inside|only be used in) ' + name, t, re.I):
            return (map_id, name)
    return None


def outdoor_locked(r):
    """Usable only in an outdoor zone (e.g. Windstone, Skywall): cannot be gated
    by instance, so such items are left out."""
    return re.search(r'cannot be used outside of|only (?:be )?usable in (?!side)', r['use'], re.I)


# ------------------------------------------------------------------
# Stats a buff grants, keyed the way the addon names them
# ------------------------------------------------------------------

STAT_WORDS = {
    'strength': 'strength', 'agility': 'agility', 'stamina': 'stamina',
    'intellect': 'intellect', 'spirit': 'spirit', 'armor': 'armor',
    'attack power': 'attackPower', 'healing power': 'healing',
    'spell damage': 'spellDmg',
}


def parse_stats(text):
    """Stats from a buff description. Returns {stat: value}."""
    s = {}
    t = text

    def add(k, v):
        s[k] = max(s.get(k, 0), v)

    # "Increases Intellect and Spirit by 18", "increase your Strength and Agility by 18"
    for a, b, v in re.findall(r'(?:Increases|increase|gain)(?: your)? (\w+) and (\w+) by (\d+)', t, re.I):
        for w in (a, b):
            if w.lower() in STAT_WORDS: add(STAT_WORDS[w.lower()], int(v))
    # "Increases Intellect by 25", "increase your Spirit by 10", "Strength goes up by 8"
    for w, v in re.findall(r'(?:Increases|increase)(?: your)? (Strength|Agility|Stamina|Intellect|Spirit) by (\d+)', t, re.I):
        add(STAT_WORDS[w.lower()], int(v))
    # "gain 25 Agility and Intellect"
    for v, a, b in re.findall(r'gain (\d+) (\w+) and (\w+)', t, re.I):
        for w in (a, b):
            if w.lower() in STAT_WORDS: add(STAT_WORDS[w.lower()], int(v))
    # Well Fed: "gain 6 Attack Power", "gain 2 Stamina and Spirit", "gain 1% Critical Strike chance"
    m = re.search(r'well fed and gain (.*?) for \d+ min', t, re.I)
    if m:
        g = m.group(1)
        m2 = re.match(r'(\d+)% Critical Strike chance', g, re.I)
        if m2:
            add('crit', int(m2.group(1)))
        m2 = re.match(r'(\d+) (.+)$', g)
        if m2 and not m2.group(2).lower().endswith('skill'):
            v, words = int(m2.group(1)), m2.group(2).lower()
            if words in STAT_WORDS:
                add(STAT_WORDS[words], v)
            else:
                for w in words.split(' and '):
                    if w in STAT_WORDS: add(STAT_WORDS[w], v)
    # spell damage / healing
    m = re.search(r'spell damage and healing by up to (\d+)', t, re.I)
    if m: add('spellDmg', int(m.group(1))); add('healing', int(m.group(1)))
    m = re.search(r'(?<!nature )(?<!fire )spell damage by up to (\d+)', t, re.I)
    if m and 'against' not in t: add('spellDmg', int(m.group(1)))
    for school, v in re.findall(r'spell (fire|frost|shadow|holy) damage by up to (\d+)', t, re.I):
        add('spellDmg' + school.capitalize(), int(v))
    m = re.search(r'nature spell damage by up to (\d+)', t, re.I)
    if m: add('spellDmgNature', int(m.group(1)))
    m = re.search(r'damage done by magical spells and effects by up to (\d+)', t, re.I)
    if m: add('spellDmg', int(m.group(1)))
    m = re.search(r'increases healing done by up to (\d+)', t, re.I)
    if m: add('healing', int(m.group(1)))
    # "If you eat for 10 seconds will also increase your Spell Damage by 12"
    # "Also increases your Stamina by 10 for 10 min"
    for w, v in re.findall(r'(?:will also increase|Also increases) your (Strength|Agility|Stamina|Intellect|Spirit|Spell Damage|Healing done) by (\d+)', t, re.I):
        key = {'spell damage': 'spellDmg', 'healing done': 'healing'}.get(w.lower(), STAT_WORDS.get(w.lower()))
        if key: add(key, int(v))
    # "become refreshed and gain 6 Mana every 5 seconds"
    m = re.search(r'refreshed and gain (\d+) Mana every 5 sec', t, re.I)
    if m: add('mp5', int(m.group(1)))
    m = re.search(r'healing done by spells and effects by up to (\d+)', t, re.I)
    if m: add('healing', int(m.group(1)))
    m = re.search(r'effect of healing spells by up to (\d+)', t, re.I)
    if m: add('healing', int(m.group(1)))
    # regeneration
    m = re.search(r'(?:regenerate|restores?) (\d+) mana (?:per|every|to the caster every) 5 sec', t, re.I)
    if m: add('mp5', int(m.group(1)))
    m = re.search(r'restore (\d+) health and (\d+) mana every 5 sec', t, re.I)
    if m: add('hp5', int(m.group(1))); add('mp5', int(m.group(2)))
    m = re.search(r'Regenerate (\d+) health every 5 sec', t, re.I)
    if m: add('hp5', int(m.group(1)))
    # crit
    m = re.search(r'chance to (?:get a )?critical(?:ly)? hit by (\d+)%', t, re.I)
    if m: add('crit', int(m.group(1)))
    m = re.search(r'Spell Critical chance by (\d+)%', t, re.I)
    if m: add('spellCrit', int(m.group(1)))
    # the rest
    m = re.search(r'(?:melee )?attack power by (\d+)', t, re.I)
    if m and 'against' not in t: add('attackPower', int(m.group(1)))
    m = re.search(r'maximum Mana by ([\d,]+)', t, re.I)
    if m: add('maxMana', num(m.group(1)))
    m = re.search(r'maximum health by ([\d,]+)', t, re.I)
    if m: add('maxHealth', num(m.group(1)))
    m = re.search(r'gain (\d+) maximum health and (\d+) armor', t, re.I)
    if m: add('maxHealth', int(m.group(1))); add('armor', int(m.group(2)))
    m = re.search(r'[Ii]ncreases (?:the target\'s )?[Aa]rmor by (\d+)', t)
    if m: add('armor', int(m.group(1)))
    m = re.search(r'Increases your Stamina by (\d+)', t)
    if m: add('stamina', int(m.group(1)))
    m = re.search(r'Increases the target\'s (Strength|Agility|Stamina|Intellect|Spirit) by (\d+)', t)
    if m: add(STAT_WORDS[m.group(1).lower()], int(m.group(2)))
    return s


# ------------------------------------------------------------------
# Restore amounts
# ------------------------------------------------------------------

def avg_range(pat, text):
    m = re.search(r'[Rr]estores ([\d,]+) to ([\d,]+) ' + pat, text)
    if m:
        return (num(m.group(1)) + num(m.group(2))) // 2
    return None


def potion_values(u):
    """(health, mana) averages for an instant potion, or None each."""
    m = re.search(r'Restores ([\d,]+) to ([\d,]+) (?:mana and health|health and mana)', u)
    if m:
        v = (num(m.group(1)) + num(m.group(2))) // 2
        return v, v
    m = re.search(r'Restores ([\d,]+) to ([\d,]+) mana and ([\d,]+) to ([\d,]+) health', u)
    if m:
        return (num(m.group(3)) + num(m.group(4))) // 2, (num(m.group(1)) + num(m.group(2))) // 2
    return avg_range('health', u), avg_range('mana', u)


def food_values(u):
    """(health, mana) totals for food/drink eaten over time."""
    m = re.search(r'Heals ([\d,]+) damage over', u)
    if m and not re.search(r'Restores [\d,]+ health', u):
        h = num(m.group(1))
        mm = re.search(r'Restores ([\d,]+) mana', u)
        return h, (num(mm.group(1)) if mm else None)
    m = re.search(r'Restores ([\d,]+) (?:health and mana|mana and health) over', u)
    if m:
        return num(m.group(1)), num(m.group(1))
    m = re.search(r'Restores ([\d,]+) health and ([\d,]+) mana', u)
    if m:
        return num(m.group(1)), num(m.group(2))
    m = re.search(r'Restores ([\d,]+) mana and ([\d,]+) health', u)
    if m:
        return num(m.group(2)), num(m.group(1))
    h = re.search(r'Restores ([\d,]+) health', u)
    mm = re.search(r'Restores ([\d,]+) mana', u)
    return (num(h.group(1)) if h else None), (num(mm.group(1)) if mm else None)


# ------------------------------------------------------------------
# Build
# ------------------------------------------------------------------

def build(rows):
    out = {}
    skipped = []
    zone = {}

    # Potions: instant health / mana. Discolored ones hurt you back, the
    # sleep potions stun you, Wildvine is a 0-1500 gamble: none of those
    # belong on a "best potion" button.
    health, mana, percent_h, percent_m = [], [], [], []
    gems = []
    for r in rows:
        u = r['use']
        m = re.search(r'Restores (\d+)% (health|mana)\.', u)
        if m and r['sub'] == SUB_POTION:
            (percent_h if m.group(2) == 'health' else percent_m).append((r, int(m.group(1))))
            continue
        # Mage mana gems (subclass Other): class-only, their own cooldown,
        # their own button. Checked first: they are not potions.
        if re.match(r'Mana (Agate|Jade|Citrine|Ruby)$', r['name']) and u:
            _, gm = potion_values(u)
            if gm: gems.append((-gm, r['id'], r['name'], gm))
            skipped.append((r['id'], r['name'], 'mage mana gem: its own button, not a potion'))
            continue
        if kind(r) == 'other-restore':
            skipped.append((r['id'], r['name'], 'restores instantly but is not a potion (own cooldown)'))
            continue
        if kind(r) != 'potion':
            continue
        if re.search(r'Discolored|Dreamless|Wildvine', r['name']) or 'sleep' in u:
            continue
        # Mage mana gems: class-only, their own cooldown. On the potion
        # button they would hide real potions; they get their own button.
        if outdoor_locked(r):
            skipped.append((r['id'], r['name'], 'usable only in an outdoor zone'))
            continue
        h, mn = potion_values(u)
        if not h and not mn:
            continue
        z = restriction(r)
        if z: zone[r['id']] = z
        # Perishable potions expire: at equal strength, use them first.
        tie = 0 if 'Perishable' in r['name'] else 1
        # A potion that restores both is the expensive one: rank it as if it
        # were 25% weaker, so a pure potion of the same tier is used first.
        both = h and mn
        if h: health.append((-h * (0.75 if both else 1), tie, r['id'], r['name'], h, h * (0.75 if both else 1)))
        if mn: mana.append((-mn * (0.75 if both else 1), tie, r['id'], r['name'], mn, mn * (0.75 if both else 1)))
    # Fixed-value potions, strongest first. Percentage potions cannot be
    # ranked here (it depends on the player's maximum), so they are listed
    # apart and ranked in game against the player's readable maximum.
    out['MANA_GEMS'] = sorted(gems)
    out['HEALTH_ITEMS'] = sorted(health)
    out['MANA_ITEMS'] = sorted(mana)
    out['PERCENT_POTIONS'] = [(r['id'], r['name'], 'health', pct) for r, pct in percent_h] + \
                             [(r['id'], r['name'], 'mana', pct) for r, pct in percent_m]

    # Food and drink.
    food, drink, both, buff = [], [], [], defaultdict(list)
    for r in rows:
        u = r['use']
        if r['sub'] == SUB_FOOD and u and PERCENT.search(u):
            skipped.append((r['id'], r['name'], 'restores a percentage: not rankable against fixed amounts'))
            continue
        if kind(r) == 'feast':
            skipped.append((r['id'], r['name'], 'feast: placed for the group, not eaten from the bag'))
            continue
        if kind(r) != 'food':
            if r['sub'] == SUB_FOOD and not r['quest']:
                skipped.append((r['id'], r['name'], 'Food & Drink with no Use text in the scan'))
            continue
        h, mn = food_values(u)
        if not h and not mn:
            # Say why, so a future scan's report can be reviewed.
            if re.search(r'Restores [\d,]+ to [\d,]+ (?:health|mana)', u):
                why = 'instant restore with its own cooldown: not food, not a potion'
            else:
                why = 'Food & Drink restoring no fixed health or mana (alcohol, novelty)'
            skipped.append((r['id'], r['name'], why))
            continue
        buffy = re.search(r'well fed|will also increase|Also increases|become refreshed', u, re.I)
        stats = parse_stats(u) if buffy else {}
        z = restriction(r)
        if z: zone[r['id']] = z
        if stats:
            for k, v in stats.items():
                buff[k].append((-v, r['lvl'], r['id'], r['name'], v))
            continue
        if buffy and not (h or mn):
            skipped.append((r['id'], r['name'], 'buff food, no stat recognised and no fixed restore'))
            continue
        # A bonus Buff Food does not offer (fishing skill, herbalism,
        # movement speed) does not stop it being good food or drink:
        # Rockscale Cod restores 841, Goldthorn Tea 1292 mana.
        # Food restoring both competes on BOTH buttons. It must not collapse
        # them into one: a low-level item would hide a high-level drink.
        if h:
            food.append((-h, 0 if r['conjured'] else 1, r['id'], r['name'], h, r['conjured'], mn))
        if mn:
            drink.append((-mn, 0 if r['conjured'] else 1, r['id'], r['name'], mn, r['conjured'], h))
    out['FOOD_ITEMS'] = sorted(food)
    out['DRINK_ITEMS'] = sorted(drink)
    out['CONJURED_ITEMS'] = []
    out['BUFF_FOOD_BY_STAT'] = {k: sorted(v) for k, v in buff.items()}

    # Healthstones: every stone, strongest first.
    hs = []
    for r in rows:
        m = re.search(r'Instantly restores ([\d,]+) life', r['use'])
        if m and 'Healthstone' in r['name']:
            hs.append((-num(m.group(1)), r['id'], r['name'], num(m.group(1))))
    out['HEALTHSTONE_ITEMS'] = sorted(hs)

    # Bandages.
    bd = []
    for r in rows:
        if kind(r) != 'bandage':
            continue
        m = re.search(r'Heals ([\d,]+) damage', r['use'])
        if not m:
            continue
        z = restriction(r)
        if z: zone[r['id']] = z
        bd.append((-num(m.group(1)), r['id'], r['name'], num(m.group(1))))
    out['BANDAGE_ITEMS'] = sorted(bd)

    # Scrolls, by stat. Familiar scrolls summon a pet: not a buff scroll.
    scrolls = defaultdict(list)
    for r in rows:
        if r['sub'] != SUB_SCROLL or 'Familiar' in r['name']:
            continue
        st = parse_stats(r['use'])
        for k, v in st.items():
            scrolls[k].append((-v, r['id'], r['name'], v, r['spell']))
    out['SCROLLS_BY_STAT'] = {k: sorted(v) for k, v in scrolls.items()}

    # Elixirs and flasks: a catalog tagged by stat. Which slot shows what
    # is the addon's decision (a role profile), not the data's.
    cat = []
    for r in rows:
        if r['sub'] not in (SUB_ELIXIR, SUB_FLASK) and not (r['sub'] == SUB_POTION and 'Elixir' in r['name']):
            continue
        st = parse_stats(r['use'])
        if not st:
            if r['use']:
                skipped.append((r['id'], r['name'], 'elixir, no stat recognised'))
            continue
        cat.append((r['id'], r['name'], r['sub'] == SUB_FLASK, r['spell'], st, r['lvl']))
    out['ELIXIR_CATALOG'] = sorted(cat)

    # Weapon oils.
    oils = []
    for r in rows:
        if not re.search(r'(Mana|Wizard) Oil$', r['name']) or 'against' in r['use']:
            continue
        st = parse_stats(r['use'])
        oils.append((r['id'], r['name'], 'mana' if 'Mana Oil' in r['name'] else 'wizard', st, max(1, r['lvl'])))
    out['OILS'] = oils

    # Only one flask can be active. Its spell must count as "a flask is
    # running" even when the flask's effect is no catalog stat (Chromatic
    # Resistance, Petrification).
    out['ALL_FLASK_SPELLS'] = sorted({(r['spell'], r['name']) for r in rows
                                      if r['sub'] == SUB_FLASK and r['spell']})

    out['ZONE_RESTRICTED_ITEMS'] = zone
    return out, skipped


# ------------------------------------------------------------------
# XP food (#19)
# ------------------------------------------------------------------
# Forever's "Nutritious" food and drink add "experience gained from kills is
# increased by 5%" to their Well Fed bonus. The buff is ONE aura named
# "Well Fed" whose spell ID is not the item's; the XP line is in no spell
# text the API returns, only in the live buff's tooltip (docs/FOREVER-PROBE.md,
# 70009). The XP auras are the Well Fed spells in the "nutritious" wording,
# one per stat. The generator checks that every stat an XP food gives has
# one, and that the aura measured in game is among them.
XP_LINE = 'kills is increased by 5%'
XP_AURA_TEXT = re.compile(r'^A (?:nutritious meal|tasty drink) has made you Well Fed, increasing your (.+?)\.*$')
MEASURED_XP_AURAS = [1248422]   # Beer Basted Boar Ribs, eaten on 70009
# Forever's new spells start at 1.22M; XP food exists only on Forever. A
# Well Fed spell below this is a Vanilla one, never XP, even with no text.
FOREVER_SPELLS_FROM = 1000000


def xp_food(rows):
    """Every XP food and drink: (id, name, level, stat or None, value, kind
    of Well Fed as the aura names it). Highest level first."""
    out = []
    for r in rows:
        u = r['use']
        if XP_LINE not in u or kind(r) != 'food':
            continue
        m = re.search(r'well fed and gain (.*?) for \d+ min', u, re.I)
        gain = m.group(1) if m else ''
        stats = parse_stats(u)
        stat = max(stats, key=lambda k: (stats[k], k)) if stats else None
        # The aura names the kind: "Strength", "movement speed" (any zone),
        # "chance to deal a critical strike", "Fishing Skill".
        what = re.sub(r'^[\d%]+\s*', '', gain)
        what = re.sub(r' while in .*$', '', what)
        what = {'critical strike chance': 'chance to deal a critical strike'}.get(what.lower(), what)
        out.append((-max(1, r['lvl']), -(stats[stat] if stat else 0), r['id'], r['name'],
                    max(1, r['lvl']), stat, stats[stat] if stat else 0, what.lower()))
    return sorted(out)


def load_wellfed(path):
    """{spellID: description} from export_wellfed.lua's TSV, refusing an
    INCOMPLETE scan."""
    spells = {}
    with open(path, encoding='utf-8') as f:
        for i, line in enumerate(f):
            line = line.rstrip('\n')
            if i == 0 and not line.startswith('# COMPLETE'):
                sys.exit('%s is not a COMPLETE /apo scan3 export: %s' % (path, line))
            if line.startswith('#') or not line:
                continue
            sid, _, desc = line.partition('\t')
            spells[int(sid)] = desc
    return spells


def xp_auras(spells, foods):
    """The XP Well Fed aura IDs, checked against the XP foods."""
    xp, kinds = [], set()
    for sid, desc in sorted(spells.items()):
        m = XP_AURA_TEXT.match(desc)
        if m:
            xp.append(sid)
            kinds.add(m.group(1).lower())
    missing = sorted({f[7] for f in foods} - kinds)
    if missing:
        sys.exit('XP food gives Well Fed kinds with no XP aura in the Well Fed scan: %s' % missing)
    absent = [a for a in MEASURED_XP_AURAS if a not in xp]
    if absent:
        sys.exit('the XP aura measured in game is not in the XP set: %s' % absent)
    return xp


# ------------------------------------------------------------------
# Rogue poisons (#24)
# ------------------------------------------------------------------
# "Coats a weapon with poison": one family per name ("Instant Poison III"
# is family Instant, rank 3; no numeral is rank 1). Test items in the
# client DB ("Runecarving Test - Crippling Poison") are left out.
POISON_TEXT = 'Coats a weapon with poison'
POISON_NAME = re.compile(r'^([A-Z][\w-]*(?: [A-Z][\w-]*)*?) Poison(?: ([IVX]+))?$')
ROMAN = {'I': 1, 'II': 2, 'III': 3, 'IV': 4, 'V': 5, 'VI': 6, 'VII': 7, 'VIII': 8, 'IX': 9, 'X': 10}
# The order the options list them in: the usual ones first.
POISON_ORDER = ['instant', 'deadly', 'wound', 'crippling', 'mindnumbing', 'occult']


def poisons(rows):
    """{family: [(-rank, id, name, level, rank)]} highest rank first,
    {family: label}, and the skipped poisons with why."""
    fam, labels, skipped = defaultdict(list), {}, []
    for r in rows:
        if POISON_TEXT not in r['use']:
            continue
        if 'Test' in r['name']:
            skipped.append((r['id'], r['name'], 'poison: a test item'))
            continue
        m = POISON_NAME.match(r['name'])
        if not m:
            # Reported, never dropped silently (/code-review of #26).
            skipped.append((r['id'], r['name'], 'poison: name not "<Family> Poison [rank]"'))
            continue
        key = m.group(1).lower().replace('-', '').replace(' ', '')
        rank = ROMAN[m.group(2)] if m.group(2) else 1
        labels[key] = m.group(1) + ' Poison'
        fam[key].append((-rank, r['id'], r['name'], max(1, r['lvl']), rank))
    return {k: sorted(v) for k, v in fam.items()}, labels, skipped


# ------------------------------------------------------------------
# Weapon stones (#32)
# ------------------------------------------------------------------
# Sharpening stones (sharp weapons) and weightstones (blunt weapons) add
# weapon damage; Elemental Sharpening Stone adds melee crit on any melee
# weapon. Their effects are different quantities and are never ranked
# against each other: effect says which. A stone only good "against" a
# creature type (Consecrated) is reported as skipped, not offered.
STONE_NAME = re.compile(r'(Sharpening Stone|Weightstone)$')


def stones(rows):
    """{kind: [(-value, id, name, value, effect, level)]} for kind sharp /
    blunt / any, strongest first, and the skipped stones with why."""
    out, skipped = defaultdict(list), []
    for r in rows:
        # "Craftsman's Writ: Solid Sharpening Stone" (a quest item in the
        # 70009 scan) also ends in "Sharpening Stone": the Writ check is
        # what keeps it out.
        if not STONE_NAME.search(r['name']) or 'Writ' in r['name'] or r['quest']:
            continue
        u = r['use']
        if 'against' in u:
            skipped.append((r['id'], r['name'], 'stone: only against a creature type'))
            continue
        m = re.search(r'Increase sharp weapon damage by (\d+)', u)
        kind, effect = 'sharp', 'weaponDamage'
        if not m:
            m = re.search(r'Increase the damage of a blunt weapon by (\d+)', u)
            kind = 'blunt'
        if not m:
            m = re.search(r'Increase critical chance on a melee weapon by (\d+)%', u)
            kind, effect = 'any', 'meleeCrit'
        if not m:
            skipped.append((r['id'], r['name'], 'stone: effect not recognised'))
            continue
        v = int(m.group(1))
        out[kind].append((-v, r['id'], r['name'], v, effect, max(1, r['lvl'])))
    return {k: sorted(v) for k, v in out.items()}, skipped


def ordinary_well_fed(spells, xp):
    """Well Fed auras known NOT to be XP: a described non-XP one, or a
    Vanilla spell. A Forever spell with no description (1283082 on 70009)
    is left out: it could be the unmeasured drink's XP aura, and at runtime
    a Well Fed in neither list is unknown, which never glows (/code-review
    of #21)."""
    xp = set(xp)
    return [sid for sid, desc in sorted(spells.items())
            if sid not in xp and (desc.strip() or sid < FOREVER_SPELLS_FROM)]


def offered_item_ids(out):
    """Every ITEM id the generated tables can put on a button: only the item
    positions of each collection, never spell IDs, values or map IDs."""
    ids = set()
    for key, pos in (('HEALTH_ITEMS', 2), ('MANA_ITEMS', 2), ('FOOD_ITEMS', 2), ('DRINK_ITEMS', 2),
                     ('MANA_GEMS', 1), ('HEALTHSTONE_ITEMS', 1), ('BANDAGE_ITEMS', 1)):
        ids.update(t[pos] for t in out[key])
    for lst in out['BUFF_FOOD_BY_STAT'].values():
        ids.update(t[2] for t in lst)
    for lst in out['SCROLLS_BY_STAT'].values():
        ids.update(t[1] for t in lst)
    ids.update(t[0] for t in out['ELIXIR_CATALOG'])
    ids.update(t[0] for t in out['OILS'])
    ids.update(t[0] for t in out['PERCENT_POTIONS'])
    ids.update(t[2] for t in out.get('XP_FOOD', []))
    for lst in out.get('POISONS', {}).values():
        ids.update(t[1] for t in lst)
    for lst in out.get('STONES', {}).values():
        ids.update(t[1] for t in lst)
    return ids


# ------------------------------------------------------------------
# Emit Lua
# ------------------------------------------------------------------

def lua_stats(st):
    return '{ ' + ', '.join('%s = %d' % (k, v) for k, v in sorted(st.items())) + ' }'


def emit(out, build_id, src):
    L = []
    w = L.append
    w('-- ============================================================')
    w('-- Apotheca - item data for WoW: Forever')
    w('--')
    w('-- GENERATED by Tools/build_item_tables.py from %s' % src)
    w('-- (client build %s). Do not edit by hand: re-scan in game and' % build_id)
    w('-- regenerate. Every value is what this client\'s own tooltip says.')
    w('-- ============================================================')
    w('')
    w('Apotheca = Apotheca or {}')
    w('local D = {}')
    w('Apotheca.DATA = D')
    w('')

    def id_list(name, items, fmt, comment):
        w('-- ' + comment)
        w('D.%s = {' % name)
        for it in items:
            w(fmt(it))
        w('}')
        w('')

    id_list('HEALTH_ITEMS', out['HEALTH_ITEMS'],
            lambda t: '    %-7s -- %s (%s)' % ('%d,' % t[2], t[3], t[4]),
            'Health potions, strongest first (average of the tooltip range).')
    id_list('MANA_ITEMS', out['MANA_ITEMS'],
            lambda t: '    %-7s -- %s (%s)' % ('%d,' % t[2], t[3], t[4]),
            'Mana potions, strongest first.')
    w('-- The ranking value of each fixed potion (a potion restoring both counts')
    w('-- 25% less), so a percentage potion can be compared with it in game.')
    w('D.POTION_VALUE = {')
    seen = set()
    for t in out['HEALTH_ITEMS'] + out['MANA_ITEMS']:
        key = (t[2], t in out['MANA_ITEMS'])
    for label, lst in (('health', out['HEALTH_ITEMS']), ('mana', out['MANA_ITEMS'])):
        w('    %s = {' % label)
        for t in lst:
            w('        [%d] = %d,  -- %s' % (t[2], int(t[5]), t[3]))
        w('    },')
    w('}')
    w('')
    w('-- Potions restoring a percentage of the maximum: ranked in game against')
    w('-- the best fixed potion held, using the (readable) maximum health / mana.')
    w('D.PERCENT_POTIONS = {')
    for t in out['PERCENT_POTIONS']:
        w('    { id = %d, resource = "%s", percent = %d },  -- %s' % (t[0], t[2], t[3], t[1]))
    w('}')
    w('')
    id_list('MANA_GEMS', out['MANA_GEMS'],
            lambda t: '    %-7s -- %s (%d mana)' % ('%d,' % t[1], t[2], t[3]),
            'Mage mana gems, strongest first: their own cooldown, their own button.')
    w('-- Demonic Rune (12662) and Dark Rune (20520) were NOT in the client scan on')
    w('-- this build. Kept so the button works if they exist; they never match if not.')
    w('D.RUNE_ITEMS = { 20520, 12662 }')
    w('')
    w('-- Items that collapse Food and Drink into one button. Empty on Forever: food')
    w('-- restoring both is listed on both buttons instead (restoresMana / restoresHealth).')
    w('D.CONJURED_ITEMS = {}')
    w('')
    id_list('DRINK_ITEMS', out['DRINK_ITEMS'],
            lambda t: '    { id = %-6d, manaValue = %-5d%s%s },  -- %s' % (
                t[2], t[4], ', conjured = true' if t[5] else '',
                ', restoresHealth = true' if t[6] else '', t[3]),
            'Plain drinks (no Well Fed), strongest first. Conjured = the tooltip says "Conjured Item".')
    id_list('FOOD_ITEMS', out['FOOD_ITEMS'],
            lambda t: '    { id = %-6d, healthValue = %-5d%s%s },  -- %s' % (
                t[2], t[4], ', conjured = true' if t[5] else '',
                ', restoresMana = true' if t[6] else '', t[3]),
            'Plain food (no Well Fed), strongest first.')

    w('-- Well Fed food and drink, by the stat the buff grants. value = stat amount.')
    w('-- Forever buff food also restores health or mana while you eat.')
    w('D.BUFF_FOOD_BY_STAT = {')
    for k in sorted(out['BUFF_FOOD_BY_STAT']):
        w('    %s = {' % k)
        for t in out['BUFF_FOOD_BY_STAT'][k]:
            w('        { id = %-6d, value = %-3d },  -- %s (L%d)' % (t[2], t[4], t[3], t[1]))
        w('    },')
    w('}')
    w('')

    w('-- XP food (#19): "experience gained from kills is increased by 5%" on top')
    w('-- of Well Fed. Highest required level first. stat = the Buff Food stat of')
    w('-- its Well Fed bonus (nil: movement speed, fishing, herbalism).')
    w('D.XP_FOOD = {')
    for t in out['XP_FOOD']:
        w('    { id = %-6d, level = %-2d, stat = %-13s value = %-3d },  -- %s' % (
            t[2], t[4], ('"%s",' % t[5]) if t[5] else 'nil,', t[6], t[3]))
    w('}')
    w('')
    w('-- Rogue poisons (#24) by family, highest rank first. level = required level.')
    w('D.POISONS = {')
    for k in sorted(out['POISONS']):
        w('    %s = {' % k)
        for t in out['POISONS'][k]:
            w('        { id = %-6d, level = %-2d, rank = %d },  -- %s' % (t[1], t[3], t[4], t[2]))
        w('    },')
    w('}')
    order = [k for k in POISON_ORDER if k in out['POISONS']] + \
            sorted(k for k in out['POISONS'] if k not in POISON_ORDER)
    w('-- Weapon stones (#32) by weapon kind, strongest first: sharp (sharpening')
    w('-- stones), blunt (weightstones), any (Elemental: melee crit on any melee')
    w('-- weapon). effect: weaponDamage or meleeCrit, never ranked against each other.')
    w('D.STONES = {')
    for k in sorted(out['STONES']):
        w('    %s = {' % k)
        for t in out['STONES'][k]:
            w('        { id = %-6d, value = %-2d, effect = "%s", level = %-2d },  -- %s' % (
                t[1], t[3], t[4], t[5], t[2]))
        w('    },')
    w('}')
    w('')
    w('-- The families in the order the options list them.')
    w('D.POISON_FAMILIES = {')
    for k in order:
        w('    { key = "%s", label = "%s" },' % (k, out['POISON_LABELS'][k]))
    w('}')
    w('')
    w('-- Well Fed auras (from /apo scan3). XP food gives ONE aura named "Well')
    w('-- Fed", like ordinary food, with its own spell ID: these are the XP ones')
    w('-- ("A nutritious meal / A tasty drink has made you Well Fed").')
    w('D.XP_WELL_FED_SPELLS = { %s }' % ', '.join(str(x) for x in out['XP_WELL_FED_SPELLS']))
    w('-- Well Fed auras known NOT to be XP (described, or Vanilla). A Well Fed')
    w('-- aura in neither list is unknown: a Forever spell with no text, or one')
    w('-- a later build revealed.')
    w('D.ORDINARY_WELL_FED_SPELLS = { %s }' % ', '.join(str(x) for x in out['ORDINARY_WELL_FED_SPELLS']))
    w('-- Every Well Fed aura the scan found (its localized name matches any).')
    w('D.WELL_FED_SPELLS = { %s }' % ', '.join(str(x) for x in out['WELL_FED_SPELLS']))
    w('')

    id_list('HEALTHSTONE_ITEMS', out['HEALTHSTONE_ITEMS'],
            lambda t: '    { id = %-6d, healValue = %-5d },  -- %s' % (t[1], t[3], t[2]),
            'Every healthstone, strongest first. All ranks share one cooldown.')
    id_list('BANDAGE_ITEMS', out['BANDAGE_ITEMS'],
            lambda t: '    %-7s -- %s (%d)' % ('%d,' % t[1], t[2], t[3]),
            'Bandages, strongest first. Battleground ones are gated in ZONE_RESTRICTED_ITEMS.')

    w('-- Buff scrolls by stat, strongest first. spell = the buff\'s spell ID.')
    w('D.SCROLLS_BY_STAT = {')
    for k in sorted(out['SCROLLS_BY_STAT']):
        w('    %s = {' % k)
        for t in out['SCROLLS_BY_STAT'][k]:
            w('        { id = %-6d, value = %-4d, spell = %s },  -- %s' % (t[1], t[3], t[4], t[2]))
        w('    },')
    w('}')
    w('')

    w('-- Every elixir and flask, tagged by stat. spell = the buff\'s spell ID, which')
    w('-- is how an active buff is recognised on any client language.')
    w('D.ELIXIR_CATALOG = {')
    for t in out['ELIXIR_CATALOG']:
        w('    { id = %-6d, spell = %-7s flask = %-5s, level = %-2d, stats = %s },  -- %s' % (
            t[0], '%s,' % t[3], 'true' if t[2] else 'false', t[5], lua_stats(t[4]), t[1]))
    w('}')
    w('')

    w('-- The buff spell of every flask, statless ones included: only one flask can')
    w('-- be active, so any of these means the flask slot is filled.')
    w('D.ALL_FLASK_SPELLS = {')
    for spell, name in out['ALL_FLASK_SPELLS']:
        w('    %-9s -- %s' % ('%d,' % spell, name))
    w('}')
    w('')

    w('-- Weapon oils, strongest first. kind = "mana" or "wizard"; level = required level.')
    w('D.OILS = {')
    for t in sorted(out['OILS'], key=lambda t: -(sum(t[3].values()))):
        w('    { id = %-6d, kind = %-8s level = %-2d, stats = %s },  -- %s' % (
            t[0], '"%s",' % t[2], t[4], lua_stats(t[3]), t[1]))
    w('}')
    w('')

    w('-- Items usable only in battlegrounds. "pvp" = any battleground; otherwise')
    w('-- { map = instance map ID (8th return of GetInstanceInfo), name = enUS name }.')
    w('-- map nil = not measured yet: the name is the only (enUS-only) match.')
    w('D.ZONE_RESTRICTED_ITEMS = {')
    for k in sorted(out['ZONE_RESTRICTED_ITEMS']):
        z = out['ZONE_RESTRICTED_ITEMS'][k]
        if z == 'pvp':
            w('    [%d] = "pvp",' % k)
        else:
            w('    [%d] = { map = %s, name = "%s" },' % (k, z[0] if z[0] else 'nil', z[1]))
    w('}')
    w('')
    return '\n'.join(L)


if __name__ == '__main__':
    # --expect-skipped ID ...: fail unless each ID is in the skipped report.
    # --expect-present ID ...: fail unless each ID is in a generated table.
    # CI uses both: items left out are accounted for, and the items the bar
    # must offer are really there. A scan that missed their tooltip text
    # (70009: every "Other" item) would otherwise drop them silently.
    def take(flag):
        if flag not in sys.argv:
            return []
        i = sys.argv.index(flag)
        vals = []
        j = i + 1
        # Only numbers: the TSV path may come after the flag's IDs.
        while j < len(sys.argv) and sys.argv[j].isdigit():
            vals.append(int(sys.argv[j]))
            j += 1
        del sys.argv[i:j]
        return vals
    expect = take('--expect-skipped')
    present = take('--expect-present')
    src = sys.argv[1]
    build_id = re.search(r'(\d{5,})', src)
    rows = load(src)
    out, skipped = build(rows)
    # The Well Fed scan of the same build, next to the consumables scan.
    wellfed_src = src.replace('forever-consumables-', 'forever-wellfed-')
    if wellfed_src == src or not os.path.exists(wellfed_src):
        sys.exit('no Well Fed scan next to %s (expected %s): run /apo scan3 and Tools/export_wellfed.lua'
                 % (src, wellfed_src))
    wellfed = load_wellfed(wellfed_src)
    out['XP_FOOD'] = xp_food(rows)
    out['POISONS'], out['POISON_LABELS'], poison_skipped = poisons(rows)
    skipped.extend(poison_skipped)
    out['STONES'], stone_skipped = stones(rows)
    skipped.extend(stone_skipped)
    out['XP_WELL_FED_SPELLS'] = xp_auras(wellfed, out['XP_FOOD'])
    out['WELL_FED_SPELLS'] = sorted(wellfed)
    out['ORDINARY_WELL_FED_SPELLS'] = ordinary_well_fed(wellfed, out['XP_WELL_FED_SPELLS'])
    lua = emit(out, build_id.group(1) if build_id else '?', src.replace('\\', '/'))
    open('ApothecaItems.lua', 'w', encoding='utf-8', newline='\r\n').write(lua)
    for k, v in out.items():
        print('%-22s %d' % (k, len(v)))
    print('skipped (review these):')
    for s in skipped:
        print('   ', s)
    reported = {s[0] for s in skipped}
    missing = [x for x in expect if x not in reported]
    if missing:
        print('NOT REPORTED as skipped: %s' % missing)
        sys.exit(1)
    absent = [x for x in present if x not in offered_item_ids(out)]
    if absent:
        print('MISSING from the generated tables: %s' % absent)
        sys.exit(1)
