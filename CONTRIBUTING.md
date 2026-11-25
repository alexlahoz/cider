# Contributing to Cider

Thanks for your interest in Cider! Bug reports, game compatibility notes and pull requests are all welcome.

## Reporting a problem

Please open an issue with:

- your Mac model and macOS version,
- the Cider version (*Settings → About*),
- the game and where it comes from (Steam or added manually),
- what you expected and what happened,
- the log from *Diagnostics → Open logs* if the problem is a crash or a game that won't start.

## Development

1. Install the prerequisites listed in the [README](README.md#building-from-source).
2. `make runtime` once (it is cached), then `make app` for each change.
3. Run `build/Cider.app`. `CIDER_DATA_DIR=/tmp/cider-dev` keeps your real data untouched; `-CiderDemo YES` shows a sample library without running any game.

### Guidelines

- **Keep the app friendly.** Cider is for people who just want to play: no jargon in the UI, sensible defaults, advanced behaviour automated rather than exposed.
- **UI text is English in the source.** Add the Spanish translation to `scripts/l10n/es.py` and regenerate the string files (see the README).
- **Runtime changes are patches.** Changes to Wine or DXMT go in `patches/wine` or `patches/dxmt` with a short header explaining why, so the build stays reproducible and license-compliant.
- **Test on a clean data folder** when touching setup or Steam handling.

## Releasing

1. Bump `VERSION` and add an entry to `CHANGELOG.md`.
2. `make release` (builds from scratch) and test the DMG.
3. `make publish` creates the `v<version>` tag and GitHub release with the DMG. Installed copies of Cider pick it up automatically.
