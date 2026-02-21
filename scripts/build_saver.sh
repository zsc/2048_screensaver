#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CORE_DIR="$ROOT_DIR/Core2048"
SAVER_DIR="$ROOT_DIR/Screensaver2048"
OUT_DIR="$ROOT_DIR/Build/Screensaver2048.saver"

BIN_DIR="$OUT_DIR/Contents/MacOS"
RES_DIR="$OUT_DIR/Contents/Resources"

rm -rf "$OUT_DIR"
mkdir -p "$BIN_DIR" "$RES_DIR"

cp "$SAVER_DIR/Resources/Info.plist" "$OUT_DIR/Contents/Info.plist"
cp "$SAVER_DIR/Resources/weights.json" "$RES_DIR/weights.json"

CORE_BUILD_DIR="$(cd "$CORE_DIR" && swift build -c release --show-bin-path)"

swiftc -O -module-name Screensaver2048 -emit-library \
  -o "$BIN_DIR/Screensaver2048" \
  -I "$CORE_BUILD_DIR/Modules" \
  "$SAVER_DIR/Sources"/*.swift \
  "$CORE_BUILD_DIR"/Core2048.build/*.o \
  -framework ScreenSaver -framework AppKit \
  -Xlinker -bundle

if command -v codesign >/dev/null 2>&1; then
  # Ad-hoc sign to reduce load warnings on newer macOS versions.
  codesign --force --sign - "$OUT_DIR" >/dev/null 2>&1 || true
fi

echo "Built: $OUT_DIR"

