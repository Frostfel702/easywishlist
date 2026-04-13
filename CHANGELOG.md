# Changelog

## [0.6.0] - 2026-04-13

### Added
- Secondary stat filters (Haste, Mastery, Crit, Vers) in the item list. Toggle one or more stat buttons to narrow the list to gear that has all selected stats. Stats are loaded in the background via the WoW item API and cached per session; the list updates live as data arrives.

---

## [0.5.0] - 2026-04-01

### Added
- Per-character wishlists: importing a sim for a different character now stores data under that character's key; the wishlist popup shows other characters' wishlists grouped by character.
- QE Live compact format (sources[].items) is now supported alongside Raidbots.
- Delete option for other characters' wishlists, with a confirmation dialog.
- Group-by-boss mode in the item list, alongside the existing By Source and By Slot views.

### Fixed
- Minimap button now uses LibDBIcon-1.0 for correct placement on all minimap shapes, including ElvUI's square minimap.
- Import now uses the in-game character key when the sim's player matches the logged-in character, fixing tooltip lookups on realms with special characters (e.g. Zul'jin).
- Delete button now always appears for the selected wishlist, even when only one wishlist exists.

---

## [0.4.2] - 2026-03-31

### Fixed
- Fixed minimap button placement on non-circular minimaps (e.g. ElvUI square minimap). Position is now calculated dynamically based on the actual minimap dimensions instead of a hardcoded radius.

---

## [0.4.1] - 2026-03-31

### Added
- Item tooltips now show the upgrade percentage per wishlist (up to 3), so you can see at a glance which of your wishlists benefits from an item and by how much.

### Fixed
- Fixed a Lua error on reload caused by the deprecated `OnTooltipSetItem` tooltip hook, which was removed in Dragonflight+. The hook now uses `TooltipDataProcessor.AddTooltipPostCall` and includes error handling to surface any future API failures as a readable message instead of a crash.

---

## [0.4.0]

- Confirmation dialog for dungeon delete
- Dropdown wishlist picker
- Scrollable dungeon list
- Pinned "All Sources" row in sidebar
