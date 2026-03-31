# Changelog

## [0.4.1] - 2026-03-31

### Fixed
- Fixed a Lua error on reload caused by the deprecated `OnTooltipSetItem` tooltip hook, which was removed in Dragonflight+. The hook now uses `TooltipDataProcessor.AddTooltipPostCall` and includes error handling to surface any future API failures as a readable message instead of a crash.

---

## [0.4.0]

- Confirmation dialog for dungeon delete
- Dropdown wishlist picker
- Scrollable dungeon list
- Pinned "All Sources" row in sidebar
