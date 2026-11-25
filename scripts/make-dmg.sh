#!/bin/bash
# Packs build/Cider.app into dist/Cider-<version>.dmg with a background and an Applications link.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/Cider.app"
VERSION="$(cat "$ROOT/VERSION")"
DIST="$ROOT/dist"
DMG="$DIST/Cider-$VERSION.dmg"
VOL="Cider"
[ -d "$APP" ] || "$ROOT/scripts/build-app.sh"
mkdir -p "$DIST"
STAGE="$(mktemp -d)"; RW="$(mktemp -u).dmg"
trap 'rm -rf "$STAGE" "$RW"' EXIT

echo "==> Staging"
cp -cR "$APP" "$STAGE/Cider.app"
ln -s /Applications "$STAGE/Applications"
mkdir "$STAGE/.background"
rsvg-convert -w 920 -h 400 "$ROOT/assets/dmg/background.svg" -o "$STAGE/.background/bg1x.png"
rsvg-convert -w 1840 -h 800 "$ROOT/assets/dmg/background.svg" -o "$STAGE/.background/bg2x.png"
tiffutil -cathidpicheck "$STAGE/.background/bg1x.png" "$STAGE/.background/bg2x.png" -out "$STAGE/.background/background.tiff" >/dev/null
rm "$STAGE/.background/"bg*.png
cp "$ROOT/App/Resources/AppIcon.icns" "$STAGE/.VolumeIcon.icns"

echo "==> Creating disk image"
SIZE=$(( $(du -sm "$STAGE" | cut -f1) + 120 ))
hdiutil create -quiet -srcfolder "$STAGE" -volname "$VOL" -fs HFS+ -format UDRW -size ${SIZE}m "$RW"
MNT="$(hdiutil attach -readwrite -noverify -noautoopen "$RW" | awk -F'\t' '/\/Volumes\//{print $NF; exit}')"
SetFile -a C "$MNT" 2>/dev/null || true
# Window layout (best effort: needs Finder automation permission).
osascript <<OSA || echo "   (Finder layout skipped)"
tell application "Finder"
  tell disk "$(basename "$MNT")"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 1120, 520}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 112
    set text size of opts to 13
    set background picture of opts to file ".background:background.tiff"
    set position of item "Cider.app" of container window to {290, 195}
    set position of item "Applications" of container window to {630, 195}
    update without registering applications
    delay 1
    close
  end tell
end tell
OSA
sync
hdiutil detach -quiet "$MNT" || { sleep 3; hdiutil detach -force -quiet "$MNT"; }

echo "==> Compressing"
rm -f "$DMG"
hdiutil convert -quiet "$RW" -format ULMO -o "$DMG"
codesign --force --sign - "$DMG"
ls -lh "$DMG"
