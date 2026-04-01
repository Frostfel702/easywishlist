# Changelog

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
