#!/bin/bash
# Builds build/Cider.app (Release, arm64) with the Windows runtime inside, signed ad hoc.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/Cider.app"
VERSION="$(cat "$ROOT/VERSION")"
BUILD="$(git -C "$ROOT" rev-list --count HEAD 2>/dev/null || echo 1)"

log() { printf '\033[1;35m==>\033[0m %s\n' "$*"; }

[ -x "$ROOT/build/runtime/wine/bin/wine" ] || "$ROOT/scripts/build-runtime.sh"
[ -f "$ROOT/App/Resources/AppIcon.icns" ] || "$ROOT/scripts/make-icon.sh"

log "Compiling Cider (release, arm64)"
swift build -c release --arch arm64 --package-path "$ROOT/App" 2>&1 | grep -vE "^\[[0-9]+/[0-9]+\]" || true
BIN="$(swift build -c release --arch arm64 --package-path "$ROOT/App" --show-bin-path)/Cider"
[ -x "$BIN" ] || { echo "build failed" >&2; exit 1; }

log "Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
# SwiftPM records the deployment target as the SDK version, which makes macOS treat the app
# as "built for macOS 14" and disables Liquid Glass. Record the real SDK.
vtool -set-build-version macos 14.0 "$(xcrun --show-sdk-version)" -replace -output "$APP/Contents/MacOS/Cider" "$BIN"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" "$ROOT/App/Resources/Info.plist" > "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
cp "$ROOT/App/Resources/AppIcon.icns" "$APP/Contents/Resources/"
cp -R "$ROOT/App/Resources/es.lproj" "$ROOT/App/Resources/en.lproj" "$APP/Contents/Resources/"
cp -cR "$ROOT/build/runtime" "$APP/Contents/Resources/runtime"
# Notices and the source of our own Windows helper
cp "$ROOT"/licenses/*.md "$APP/Contents/Resources/runtime/licenses/"
cp "$ROOT/runtime-src/steamwebhelper/webhelper_wrapper.c" "$APP/Contents/Resources/runtime/licenses/"
cp "$ROOT"/patches/dxmt/*.patch "$ROOT"/patches/wine/*.patch "$APP/Contents/Resources/runtime/licenses/"

log "Signing (ad hoc)"
codesign --force --deep --sign - "$APP/Contents/Resources/runtime/wine/lib/GStreamer.framework" 2>/dev/null || true
codesign --force --deep --sign - --timestamp=none "$APP"
codesign --verify --deep --strict "$APP" && log "Signature OK"
du -sh "$APP"
