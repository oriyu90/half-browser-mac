#!/bin/bash
# Build the Rust core and the CEF application, then ad-hoc sign the bundle.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export PATH="$HOME/.cargo/bin:/opt/homebrew/bin:$PATH"

echo "== Rust core =="
(cd "$ROOT/core" && cargo build --release && cbindgen --config cbindgen.toml \
    --crate half-browser-core --output ../cefapp/src/half_browser_core.h)

echo "== CEF app =="
mkdir -p "$ROOT/cefapp/build"
(cd "$ROOT/cefapp/build" && cmake -G Ninja .. -DCMAKE_BUILD_TYPE=Release >/dev/null && ninja)

APP="$ROOT/cefapp/build/halfbrowser_cef.app"
echo "== Sign helpers and app =="
find "$APP/Contents/Frameworks" -maxdepth 1 -name "*Helper*.app" -print0 |
  while IFS= read -r -d '' h; do
    cp "$APP/Contents/MacOS/halfbrowser_cef" "$h/Contents/MacOS/$(basename "$h" .app)"
    codesign --force --deep --sign - "$h"
  done
codesign --force --deep --sign - "$APP"

echo "== Self-test =="
"$APP/Contents/MacOS/halfbrowser_cef" --self-test
echo "Built: $APP"
