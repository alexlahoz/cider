# Changelog

All notable changes to Cider are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and versions follow [Semantic Versioning](https://semver.org/).

## [1.3.0] — 2026-11-25

### Added
- In-app updates: Cider checks GitHub Releases, downloads the new DMG, verifies it, replaces itself and relaunches.
- English source strings with Spanish as the default app language.

### Changed
- Build scripts no longer assume machine-specific toolchain paths (`scripts/local.env.example`).

## [1.2.1] — 2026-11-25

### Fixed
- Cider used ~45 % CPU in the background while a game was running because of a looping status animation. Status indicators are now static and decorative animations pause when Cider is not in front.

### Added
- *Hide Cider while playing* (on by default): Cider steps aside when a game starts and comes back when it closes.

## [1.2.0] — 2026-11-25

### Added
- Steam is optional during setup ("Not now, continue without Steam") and can be installed later from the Steam section.
- *Settings* button in each game's header that scrolls to that game's settings.

### Changed
- Friendlier wording everywhere; the automatic-tuning card explains what Cider does in plain language.
- Removed advanced options (launch arguments, MSync toggle) from the UI.

## [1.1.1] — 2026-11-25

### Fixed
- Steam's first-run updater could hang on "Checking for available updates"; a watchdog now restarts it after two minutes without progress.

## [1.1.0] — 2026-11-25

### Added
- Games from outside Steam: add a `.exe` (button, drag and drop, *Open With*), or run an installer and pick the game it installed. Artwork is matched on the Steam store automatically.

## [1.0.0] — 2026-11-25

### Added
- First release: guided setup (Rosetta 2, game engine, Steam), Steam library with artwork, Direct3D 10/11 → Metal via DXMT, per-game fixes, macOS window controls for games, render resolution, anti-cheat-free launch for supported games.
