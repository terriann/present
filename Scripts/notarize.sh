#!/bin/bash
set -euo pipefail

# Notarize a signed DMG with Apple.
#
# Usage:
#   ./Scripts/notarize.sh
#
# Prerequisites:
#   - DMG built and signed via build-dmg.sh
#   - Apple Developer account credentials stored in keychain
#
# Environment variables (required):
#   APPLE_ID          - Apple ID email
#   TEAM_ID           - Apple Developer Team ID
#   APP_PASSWORD      - App-specific password (or keychain profile name)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/build"
DMG_PATH="$BUILD_DIR/Present.dmg"

if [ ! -f "$DMG_PATH" ]; then
    echo "Error: DMG not found at $DMG_PATH"
    echo "Run ./Scripts/build-dmg.sh first."
    exit 1
fi

: "${APPLE_ID:?Set APPLE_ID environment variable}"
: "${TEAM_ID:?Set TEAM_ID environment variable}"
: "${APP_PASSWORD:?Set APP_PASSWORD environment variable}"

echo "==> Submitting for notarization..."
xcrun notarytool submit "$DMG_PATH" \
    --apple-id "$APPLE_ID" \
    --team-id "$TEAM_ID" \
    --password "$APP_PASSWORD" \
    --wait

echo "==> Stapling notarization ticket..."
xcrun stapler staple "$DMG_PATH"

echo "==> Verifying..."
spctl --assess --type open --context context:primary-signature "$DMG_PATH"

echo "==> Notarization complete: $DMG_PATH"
