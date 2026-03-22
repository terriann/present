#!/bin/bash
set -euo pipefail

# Create a production GitHub release: build DMG, tag, and publish.
#
# Usage:
#   ./Scripts/release.sh [version]
#
# Arguments:
#   version  Marketing version (e.g. 0.2.0). Reads project.yml if omitted.
#
# Prerequisites:
#   - On the main branch, up to date with origin/main, with a clean working tree
#   - Version bump already committed (via bump-version.sh)
#   - gh CLI authenticated
#   - Xcode and xcodegen installed

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

# shellcheck source=lib/release-helpers.sh
source "$SCRIPT_DIR/lib/release-helpers.sh"

# ── Pre-flight and version resolution ────────────────────────────────────────

preflight_checks
resolve_version "${1:-}"

TAG="v${VERSION}"

# ── Guard: tag must not already exist ────────────────────────────────────────

if git rev-parse "$TAG" &>/dev/null; then
    echo "Error: tag $TAG already exists. Aborting."
    exit 1
fi

# ── Determine previous stable tag for changelog ─────────────────────────────

PREV_TAG=$(get_last_stable_tag)

if [[ -n "$PREV_TAG" ]]; then
    echo "    Changes: $PREV_TAG..HEAD"
else
    echo "    Changes: (all commits — no previous stable tag found)"
fi

# ── Build DMG ────────────────────────────────────────────────────────────────

build_dmg "$VERSION"

# ── Generate release notes ───────────────────────────────────────────────────

echo "==> Creating release $TAG..."
NOTES_FILE=$(mktemp)
trap "rm -f '$NOTES_FILE'" EXIT

if [[ -n "$PREV_TAG" ]]; then
    generate_changelog "$PREV_TAG" HEAD true false > "$NOTES_FILE"

    echo "" >> "$NOTES_FILE"
    echo "**Full Changelog**: ${REPO_URL}/compare/${PREV_TAG}...${TAG}" >> "$NOTES_FILE"
else
    echo "" > "$NOTES_FILE"
    echo "## Initial Release" >> "$NOTES_FILE"
    echo "" >> "$NOTES_FILE"
    echo "First production release of Present." >> "$NOTES_FILE"
fi

# ── Tag and release ──────────────────────────────────────────────────────────

gh release create "$TAG" \
    "$DMG_PATH" \
    --latest \
    --notes-file "$NOTES_FILE" \
    --title "Present v${VERSION}"

echo ""
echo "==> Done! Released $TAG"
echo "    https://github.com/terriann/present/releases/tag/$TAG"
