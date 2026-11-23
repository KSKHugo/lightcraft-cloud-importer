#!/bin/bash
# Builds "LightCraft Cloud Importer.app" from the Swift package into dist/.
# Signed ad hoc for use on this Mac, with the hardened runtime. The app is not meant for
# the Mac App Store and therefore runs without the App Sandbox.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXECUTABLE="LightCraftCloudImporter"
APP_DIR="$ROOT/dist/LightCraft Cloud Importer.app"
SCRATCH="$HOME/Library/Caches/LightCraftCloudImporter-build"

echo "==> Building (release)"
swift build --package-path "$ROOT" -c release --scratch-path "$SCRATCH" --product "$EXECUTABLE"
BIN_DIR="$(swift build --package-path "$ROOT" -c release --scratch-path "$SCRATCH" --show-bin-path)"

echo "==> Assembling the app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
cp "$BIN_DIR/$EXECUTABLE" "$APP_DIR/Contents/MacOS/$EXECUTABLE"
cp "$ROOT/AppPackaging/Info.plist" "$APP_DIR/Contents/Info.plist"
printf 'APPL????' > "$APP_DIR/Contents/PkgInfo"

echo "==> Code signing (ad hoc)"
codesign --force --options runtime --sign - "$APP_DIR"
codesign --verify --strict "$APP_DIR"

echo "Built: $APP_DIR"
