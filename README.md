# EasyWishlist

A World of Warcraft addon that displays your gear upgrade rankings inside the game, imported from simulation tools like **Questionably Epic** and **Raidbots**.

Instead of alt-tabbing to a website to check what items to target, EasyWishlist puts your ranked upgrade list directly in your WoW UI — sorted by biggest DPS or healing gain, with item level, upgrade percentage, and content source shown at a glance.

---

## Features

- Import upgrade reports from **Questionably Epic** (paste JSON) or **Raidbots Droptimizer** (via the web extractor)
- Ranked list sorted by upgrade percentage
- Shows item icon, name, ilvl, % gain, and content source (e.g. Dungeon M+10, Raid Mythic)
- Item tooltip on hover with sim data
- Minimap button for quick access
- Per-character storage — each character keeps their own report

---

## How to Use

### Questionably Epic

1. Run an upgrade report on [questionablyepic.com](https://questionablyepic.com)
2. Export the JSON from the report page
3. In WoW, click the minimap button or type `/ewl` → click **Import** → paste the JSON

### Raidbots Droptimizer

Raidbots reports are too large to paste directly into WoW, so use the companion web tool first:

1. Run a **Droptimizer** on [raidbots.com](https://www.raidbots.com/simbot/droptimizer)
2. Open the **[EasyWishlist Extractor](https://alvadin.github.io/easywishlist/)** in your browser
3. Paste your Raidbots report URL → click **Extract** → copy the compact output
4. In WoW, click the minimap button or type `/ewl` → click **Import** → paste the output

---

## Slash Commands

| Command | Action |
|---|---|
| `/ewl` | Toggle the main window |
| `/ewl import` | Open the import dialog |

---

## Installation

1. Download the latest release from [Releases](../../releases)
2. Extract to `World of Warcraft/_retail_/Interface/AddOns/EasyWishlist`
3. Reload WoW or enable the addon from the AddOns menu

---

## Contributing

Found a bug or have a feature request? **[Open an issue](../../issues/new)** — that's the best way to contribute right now.

When opening an issue please include:
- What you expected to happen
- What actually happened
- Your WoW version and addon version (shown in the addon tooltip in-game)
- If it's an import issue, which tool you used (QE or Raidbots) and any error message shown

---

## Project Structure

```
EasyWishlist/          ← WoW addon files
  EasyWishlist.toc
  Core.lua             ← Global namespace, SavedVariables, data model
  JSON.lua             ← JSON parser
  RaidbotsImport.lua   ← Raidbots compact format detection and normalisation
  Import.lua           ← Import dialog, format routing
  Minimap.lua          ← Minimap button
  UI.lua               ← Main window, item list, tooltips

docs/                  ← GitHub Pages companion tool
  index.html           ← Raidbots/QE URL extractor (no install needed)
```
