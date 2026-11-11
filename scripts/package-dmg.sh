#!/bin/bash
# Package the built app into a compressed DMG.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/cefapp/build/halfbrowser_cef.app"
# Version comes from Info.plist so the artifact name can never drift from the
# bundle it contains.
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$ROOT/cefapp/Info.plist")
OUT="$ROOT/Half-Browser-${VERSION}-macOS-arm64.dmg"

[ -d "$APP" ] || { echo "Build first: scripts/build.sh"; exit 1; }
rm -f "$OUT"
hdiutil create -volname "Half-Browser" -srcfolder "$APP" -ov -format UDZO "$OUT" >/dev/null
shasum -a 256 "$OUT"
echo "Created: $OUT (version $VERSION)"
