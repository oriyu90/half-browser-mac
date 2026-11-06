#!/bin/bash
# Download the pinned CEF binary distribution for macOS arm64.
set -euo pipefail
CEF_VERSION="156.0.15+gcf671c0+chromium-156.0.8078.80"
ARCHIVE="cef_binary_${CEF_VERSION}_macosarm64_minimal.tar.bz2"
URL="https://cef-builds.spotifycdn.com/${ARCHIVE}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="${ROOT}/cef"

mkdir -p "$DEST"
if [ -d "${DEST}/cef_binary_${CEF_VERSION}_macosarm64_minimal" ]; then
  echo "CEF already present: ${DEST}/cef_binary_${CEF_VERSION}_macosarm64_minimal"
  exit 0
fi
echo "Downloading ${URL}"
curl -L -o "${DEST}/${ARCHIVE}" "$URL"
tar -xjf "${DEST}/${ARCHIVE}" -C "$DEST"
rm -f "${DEST}/${ARCHIVE}"
echo "CEF ready."
