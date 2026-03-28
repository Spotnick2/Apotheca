# Apotheca

**Smart consumable action bars for WoW Classic (TBC)**

Apotheca is a lightweight addon that creates dynamic action bar buttons for your consumables.
It automatically selects the **best available item** from your bags — no macros, no micromanagement.

---

## ✨ Features

### 🧠 Smart Selection Engine

* Automatically picks the highest priority consumable available
* Supports:

  * Mana potions
  * Healing potions
  * Runes (Demonic Rune / Dark Rune)
* Falls back to lower-tier or previous-expansion items when needed

---

### ⚡ Dynamic Buttons

* Action bar-style buttons that update in real time
* Displays:

  * Icon
  * Stack count
  * Cooldown
* Automatically hides when no item is available

---

### 🔥 Context-Aware Logic

* Tempest Keep consumables handled automatically

  * Bottled Nethergon Energy only appears in TK instances
* Prioritizes appropriate items (e.g. Demonic Rune before Dark Rune)

---

### 🧪 Debug Mode

Safe testing mode to validate behavior without consuming items.

```lua
/run Apotheca.SetDebug(true)
/run Apotheca.SetDebug(false)
```

When enabled:

* Buttons do not consume items
* Clicking shows what would be used
* Debug indicator is displayed

---

### 🖱️ Simple UI

* Move the bar with **Shift + Left Click**
* Position is saved per character
* Minimal, unobtrusive design

---

## 📦 Installation

1. Download or clone this repository
2. Place the folder inside:

```
World of Warcraft/_classic_/Interface/AddOns/
```

3. Ensure the folder name is:

```
Apotheca
```

4. Reload UI:

```
/reload
```

---

## 🧩 Supported Consumables (Phase 1)

### Mana

* Bottled Nethergon Energy (TK only)
* Cenarion Mana Salve
* Auchenai Mana Potion
* Super Mana Potion
* Mana Potion Injector
* Classic fallback potions

### Healing

* Auchenai Healing Potion
* Super Healing Potion
* Fel Blossom
* Nightmare Seed
* Classic fallback potions

### Runes

* Demonic Rune
* Dark Rune

---

## 🧱 Project Structure

```
Apotheca/
 ├── Apotheca.lua
 └── Apotheca.toc
```

---

## ⚙️ Technical Notes

* Uses `SecureActionButtonTemplate` for combat-safe interaction
* Handles combat lockdown correctly (updates deferred until leaving combat)
* Compatible with both legacy and `C_Container` APIs
* Optimized bag scanning using a single-pass map

---

## 🔮 Roadmap

### Phase 2

* Smart food & drink system
* Config options (slash commands / UI)

### Phase 3

* Manual override (TotemTimers-style selection)
* Advanced customization

---

## 💬 Contributing / Feedback

Suggestions, ideas, and feedback are welcome.

---

## 🧠 Philosophy

Apotheca focuses on:

* Automation without loss of control
* Minimal UI, maximum efficiency
* Smart defaults that “just work”

---

## 📜 License

Add your preferred license here (MIT recommended).
