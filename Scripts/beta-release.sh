#!/bin/bash
set -euo pipefail

# Create a beta pre-release: build DMG, tag, and publish to GitHub.
#
# Usage:
#   ./Scripts/beta-release.sh [version]
#
# Arguments:
#   version  Marketing version (e.g. 0.1.0). Reads project.yml if omitted.
#
# Prerequisites:
#   - On the main branch, up to date with origin/main, with a clean working tree
#   - gh CLI authenticated
#   - Xcode and xcodegen installed

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

# shellcheck source=lib/release-helpers.sh
source "$SCRIPT_DIR/lib/release-helpers.sh"

# ── Shared pre-flight and version resolution ─────────────────────────────────

preflight_checks
resolve_version "${1:-}"

# ── Compute beta tag ─────────────────────────────────────────────────────────

BETA_NUM=1
LAST=$(git tag -l "v${VERSION}-beta.*" | sed 's/.*-beta\.//' | sort -n | tail -1)
if [[ -n "$LAST" ]]; then
    BETA_NUM=$((LAST + 1))
fi
BETA_TAG="v${VERSION}-beta.${BETA_NUM}"
echo "    Tag:     $BETA_TAG"

# ── Determine previous tag for changelog ─────────────────────────────────────

if [[ "$BETA_NUM" -gt 1 ]]; then
    PREV_TAG="v${VERSION}-beta.${LAST}"
else
    # First beta — use the most recent tag before HEAD
    PREV_TAG=$(get_last_tag)
fi

if [[ -n "$PREV_TAG" ]]; then
    echo "    Changes: $PREV_TAG..HEAD"
fi

# ── Build DMG ────────────────────────────────────────────────────────────────

build_dmg "${BETA_TAG#v}"

# ── Tag and release ──────────────────────────────────────────────────────────

echo "==> Creating pre-release $BETA_TAG..."
DMG_FILENAME="Present-${BETA_TAG#v}.dmg"
NOTES_FILE=$(mktemp)
sed "s/{{DMG_FILENAME}}/$DMG_FILENAME/g" "$SCRIPT_DIR/beta-release-header.md" > "$NOTES_FILE"
trap "rm -f '$NOTES_FILE'" EXIT

if [[ -n "${PREV_TAG:-}" ]]; then
    generate_changelog "$PREV_TAG" HEAD true false >> "$NOTES_FILE"

    echo "" >> "$NOTES_FILE"
    echo "**Full Changelog**: ${REPO_URL}/compare/${PREV_TAG}...${BETA_TAG}" >> "$NOTES_FILE"
fi

gh release create "$BETA_TAG" \
    "$DMG_PATH" \
    --prerelease \
    --notes-file "$NOTES_FILE" \
    --title "Present $BETA_TAG"

echo ""
echo "==> Done! Released $BETA_TAG"
echo "    https://github.com/terriann/present/releases/tag/$BETA_TAG"
