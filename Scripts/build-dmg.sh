#!/bin/bash
set -euo pipefail

# Build Present.app and CLI, then package into a signed DMG.
#
# Usage:
#   ./Scripts/build-dmg.sh
#
# Prerequisites:
#   - Xcode 16+ installed
#   - xcodegen installed (brew install xcodegen)
#   - Valid Developer ID certificate in keychain (for signing)
#
# Environment variables:
#   SIGNING_IDENTITY  - Developer ID Application certificate name
#                       (default: "-" for ad-hoc signing)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/build"
APP_NAME="Present"
DMG_NAME="Present.dmg"
SIGNING_IDENTITY="${SIGNING_IDENTITY:--}"

echo "==> Cleaning build directory..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo "==> Generating Xcode project..."
cd "$PROJECT_DIR"
xcodegen generate

echo "==> Building app (Release)..."
xcodebuild build \
    -project Present.xcodeproj \
    -scheme Present \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR/DerivedData" \
    -destination 'platform=macOS' \
    CODE_SIGN_IDENTITY="$SIGNING_IDENTITY"

echo "==> Building CLI (Release)..."
swift build -c release --product present-cli

# Locate built products
APP_PATH=$(find "$BUILD_DIR/DerivedData" -name "Present.app" -type d | head -1)
CLI_PATH="$PROJECT_DIR/.build/release/present-cli"

if [ -z "$APP_PATH" ]; then
    echo "Error: Present.app not found in build output"
    exit 1
fi

echo "==> Preparing DMG contents..."
DMG_STAGING="$BUILD_DIR/dmg-staging"
mkdir -p "$DMG_STAGING"
cp -R "$APP_PATH" "$DMG_STAGING/"
cp "$CLI_PATH" "$DMG_STAGING/present-cli"

# Create Applications symlink for drag-to-install
ln -s /Applications "$DMG_STAGING/Applications"

echo "==> Creating DMG..."
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$DMG_STAGING" \
    -ov \
    -format UDZO \
    "$BUILD_DIR/$DMG_NAME"

if [ "$SIGNING_IDENTITY" != "-" ]; then
    echo "==> Signing DMG..."
    codesign --sign "$SIGNING_IDENTITY" "$BUILD_DIR/$DMG_NAME"
fi

echo "==> Done! DMG created at: $BUILD_DIR/$DMG_NAME"
echo "    App: $DMG_STAGING/Present.app"
echo "    CLI: $DMG_STAGING/present-cli"
