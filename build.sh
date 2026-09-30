#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="${CLIPSHELF_BUILD_DIR:-$PROJECT_DIR/.build-local}"
DESTINATION="${1:-$PROJECT_DIR/.build-output/ClipShelf.app}"
mkdir -p "$BUILD_DIR"
export CLANG_MODULE_CACHE_PATH="$BUILD_DIR/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$BUILD_DIR/module-cache"
BUILD_FLAGS=(--build-system native --package-path "$PROJECT_DIR" --scratch-path "$BUILD_DIR/build" --cache-path "$BUILD_DIR/cache" --config-path "$BUILD_DIR/config" --security-path "$BUILD_DIR/security" --disable-sandbox -c release)
swift build "${BUILD_FLAGS[@]}"
BIN_DIR="$(swift build "${BUILD_FLAGS[@]}" --show-bin-path)"
"$BIN_DIR/ClipShelfChecks"
if [[ "${CLIPSHELF_GUI_CHECKS:-0}" == "1" ]]; then
  "$BIN_DIR/ClipShelf" --self-test
fi
mkdir -p "$DESTINATION/Contents/MacOS" "$DESTINATION/Contents/Resources"
cp "$BIN_DIR/ClipShelf" "$DESTINATION/Contents/MacOS/ClipShelf"
cp "$PROJECT_DIR/Resources/Info.plist" "$DESTINATION/Contents/Info.plist"
if [[ -f "$PROJECT_DIR/Resources/AppIcon.icns" ]]; then
  cp "$PROJECT_DIR/Resources/AppIcon.icns" "$DESTINATION/Contents/Resources/AppIcon.icns"
fi
codesign --force --sign - "$DESTINATION"
codesign --verify --strict "$DESTINATION"
echo "Ready: $DESTINATION"
