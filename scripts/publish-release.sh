#!/bin/bash
# Publishes dist/Cider-<VERSION>.dmg as GitHub release v<VERSION>, with notes from CHANGELOG.md.
# Installed copies of Cider find it through the GitHub Releases API (in-app updates).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(cat "$ROOT/VERSION")"
DMG="$ROOT/dist/Cider-$VERSION.dmg"
REPO="$(/usr/libexec/PlistBuddy -c 'Print CiderUpdateRepository' "$ROOT/App/Resources/Info.plist")"
[ -f "$DMG" ] || { echo "Missing $DMG — run make release first" >&2; exit 1; }

# Release notes: the CHANGELOG section for this version.
NOTES="$(awk -v v="$VERSION" '
  $0 ~ "^## \\[" v "\\]" { on = 1; next }
  on && /^## \[/ { exit }
  on { print }' "$ROOT/CHANGELOG.md")"
[ -n "$NOTES" ] || NOTES="Cider $VERSION"

gh release create "v$VERSION" "$DMG" --repo "$REPO" --title "Cider $VERSION" --notes "$NOTES" \
  --target main
echo "Published https://github.com/$REPO/releases/tag/v$VERSION"
