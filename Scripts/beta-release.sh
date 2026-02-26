#!/bin/bash
set -euo pipefail

# Create a beta pre-release: build DMG, tag, and publish to GitHub.
#
# Usage:
#   ./Scripts/beta-release.sh [version]
#
# Arguments:
#   version  Marketing version (e.g. 0.1.0). Reads Info.plist if omitted.
#
# Prerequisites:
#   - On the main branch, up to date with origin/main, with a clean working tree
#   - gh CLI authenticated
#   - Xcode and xcodegen installed

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

# ── Pre-flight checks ───────────────────────────────────────────────

echo "==> Pre-flight checks..."

if [[ -n "$(git status --porcelain)" ]]; then
    echo "Error: working tree is not clean. Commit or stash changes first."
    exit 1
fi

BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [[ "$BRANCH" != "main" ]]; then
    echo "Error: must be on main branch (currently on $BRANCH)."
    exit 1
fi

if ! command -v gh &>/dev/null; then
    echo "Error: gh CLI not found. Install with: brew install gh"
    exit 1
fi

# ── Sync with remote ───────────────────────────────────────────────

git fetch --all --tags --quiet

LOCAL_HEAD=$(git rev-parse HEAD)
REMOTE_HEAD=$(git rev-parse origin/main)

if [[ "$LOCAL_HEAD" != "$REMOTE_HEAD" ]]; then
    echo "Error: local main ($LOCAL_HEAD) does not match origin/main ($REMOTE_HEAD)."
    echo "       Run 'git pull' first to ensure you're building the latest code."
    exit 1
fi

# ── Resolve version ─────────────────────────────────────────────────

if [[ -n "${1:-}" ]]; then
    VERSION="$1"
else
    # Read MARKETING_VERSION from project.yml and strip any pre-release suffix
    # (e.g. "0.1.0-dev" → "0.1.0"). Info.plist has the unexpanded Xcode variable.
    RAW_VERSION=$(grep 'MARKETING_VERSION:' project.yml | head -1 | sed 's/.*: *"\(.*\)"/\1/')
    VERSION="${RAW_VERSION%%-*}"
    if [[ -z "$VERSION" ]]; then
        echo "Error: could not read MARKETING_VERSION from project.yml"
        exit 1
    fi
fi
echo "    Version: $VERSION"

# ── Compute beta tag ────────────────────────────────────────────────

BETA_NUM=1
LAST=$(git tag -l "v${VERSION}-beta.*" | sed 's/.*-beta\.//' | sort -n | tail -1)
if [[ -n "$LAST" ]]; then
    BETA_NUM=$((LAST + 1))
fi
BETA_TAG="v${VERSION}-beta.${BETA_NUM}"
echo "    Tag:     $BETA_TAG"

# ── Build DMG ───────────────────────────────────────────────────────

echo ""
DMG_FILENAME="Present-${BETA_TAG#v}.dmg"
"$SCRIPT_DIR/build-dmg.sh" "${BETA_TAG#v}"
echo ""

DMG_PATH="$PROJECT_DIR/build/$DMG_FILENAME"
if [[ ! -f "$DMG_PATH" ]]; then
    echo "Error: DMG not found at $DMG_PATH"
    exit 1
fi

# ── Tag and release ─────────────────────────────────────────────────

echo "==> Creating pre-release $BETA_TAG..."
NOTES_FILE=$(mktemp)
sed "s/{{DMG_FILENAME}}/$DMG_FILENAME/g" "$SCRIPT_DIR/beta-release-header.md" > "$NOTES_FILE"
trap "rm -f '$NOTES_FILE'" EXIT

gh release create "$BETA_TAG" \
    "$DMG_PATH" \
    --prerelease \
    --generate-notes \
    --notes-file "$NOTES_FILE" \
    --title "Present $BETA_TAG"

echo ""
echo "==> Done! Released $BETA_TAG"
echo "    https://github.com/terriann/present/releases/tag/$BETA_TAG"
