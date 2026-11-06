#!/bin/bash
# Package the built app into a compressed DMG.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/cefapp/build/halfbrowser_cef.app"
OUT="$ROOT/Half-Browser-1.5.1-macOS-arm64.dmg"

[ -d "$APP" ] || { echo "Build first: scripts/build.sh"; exit 1; }
rm -f "$OUT"
hdiutil create -volname "Half-Browser" -srcfolder "$APP" -ov -format UDZO "$OUT" >/dev/null
shasum -a 256 "$OUT"
echo "Created: $OUT"
