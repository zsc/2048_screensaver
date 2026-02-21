#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SAVER="$ROOT_DIR/Build/Screensaver2048.saver"
DEST_DIR="$HOME/Library/Screen Savers"

if [[ ! -d "$SAVER" ]]; then
  echo "Missing $SAVER"
  echo "Run: scripts/build_saver.sh"
  exit 1
fi

mkdir -p "$DEST_DIR"
rm -rf "$DEST_DIR/Screensaver2048.saver"
cp -R "$SAVER" "$DEST_DIR/"

echo "Installed to: $DEST_DIR/Screensaver2048.saver"
echo "Open System Settings → Screen Saver and select “Screensaver2048”."

