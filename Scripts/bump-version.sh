#!/bin/bash
set -euo pipefail

# Bump marketing version and build number, then create a git commit and tag.
#
# Version sources (project.yml is the single source of truth):
#   - project.yml      → MARKETING_VERSION (with -dev suffix during development)
#   - project.yml      → CURRENT_PROJECT_VERSION (build number)
#   - Constants.swift   → appVersion string shown in UI and CLI
#   - Info.plist        → Owned by xcodegen; never edited directly by this script
#
# Usage:
#   ./Scripts/bump-version.sh [major|minor|patch|X.Y.Z]
#
# Examples:
#   ./Scripts/bump-version.sh patch     # 1.0.0 -> 1.0.1
#   ./Scripts/bump-version.sh minor     # 1.0.0 -> 1.1.0
#   ./Scripts/bump-version.sh major     # 1.0.0 -> 2.0.0
#   ./Scripts/bump-version.sh 1.2.3     # Set to an explicit version

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
PROJECT_YML="$PROJECT_DIR/project.yml"
CONSTANTS_SWIFT="$PROJECT_DIR/Sources/PresentCore/Utilities/Constants.swift"

# shellcheck source=lib/release-helpers.sh
source "$SCRIPT_DIR/lib/release-helpers.sh"

# ── Validate arguments ────────────────────────────────────────────────────────

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 [major|minor|patch|X.Y.Z]" >&2
    exit 1
fi

BUMP_ARG="$1"

# ── Guard: dirty working tree ─────────────────────────────────────────────────

cd "$PROJECT_DIR"

if ! git diff --quiet || ! git diff --cached --quiet; then
    echo "Error: working tree is dirty. Commit or stash changes before bumping." >&2
    exit 1
fi

# ── Read current version from project.yml ─────────────────────────────────────

RAW_VERSION=$(grep 'MARKETING_VERSION:' "$PROJECT_YML" | head -1 | sed 's/.*: *"\(.*\)"/\1/')
CURRENT_VERSION="${RAW_VERSION%%-*}"  # Strip -dev suffix
CURRENT_BUILD=$(grep 'CURRENT_PROJECT_VERSION:' "$PROJECT_YML" | head -1 | sed 's/.*: *"\(.*\)"/\1/')
CURRENT_BUILD="${CURRENT_BUILD:-0}"

echo "Current: $CURRENT_VERSION (build $CURRENT_BUILD)"

# Normalize to X.Y.Z (pad missing components with 0)
IFS='.' read -ra PARTS <<< "$CURRENT_VERSION"
MAJOR="${PARTS[0]:-0}"
MINOR="${PARTS[1]:-0}"
PATCH="${PARTS[2]:-0}"

# ── Compute new version ───────────────────────────────────────────────────────

case "$BUMP_ARG" in
    major)
        NEW_VERSION="$((MAJOR + 1)).0.0"
        ;;
    minor)
        NEW_VERSION="$MAJOR.$((MINOR + 1)).0"
        ;;
    patch)
        NEW_VERSION="$MAJOR.$MINOR.$((PATCH + 1))"
        ;;
    [0-9]*.[0-9]*.[0-9]*)
        NEW_VERSION="$BUMP_ARG"
        ;;
    *)
        echo "Invalid argument: '$BUMP_ARG'" >&2
        echo "Usage: $0 [major|minor|patch|X.Y.Z]" >&2
        exit 1
        ;;
esac

NEW_BUILD="$((CURRENT_BUILD + 1))"

echo "New:     $NEW_VERSION (build $NEW_BUILD)"

# ── Update project.yml ───────────────────────────────────────────────────────
# Uses -dev suffix so local Xcode builds are clearly marked as development.
# Release scripts strip -dev at build time via MARKETING_VERSION override.

sed -i '' \
    "s/MARKETING_VERSION: \".*\"/MARKETING_VERSION: \"$NEW_VERSION-dev\"/" \
    "$PROJECT_YML"
sed -i '' \
    "s/CURRENT_PROJECT_VERSION: \".*\"/CURRENT_PROJECT_VERSION: \"$NEW_BUILD\"/" \
    "$PROJECT_YML"
echo "Updated project.yml"

# ── Update Constants.swift ────────────────────────────────────────────────────

sed -i '' \
    "s/public static let appVersion = \".*\"/public static let appVersion = \"$NEW_VERSION ($NEW_BUILD)\"/" \
    "$CONSTANTS_SWIFT"
echo "Updated Constants.swift"

# ── Update CHANGELOG.md ───────────────────────────────────────────────────────

CHANGELOG="$PROJECT_DIR/CHANGELOG.md"
TODAY=$(date +%Y-%m-%d)

# Determine baseline tag for changelog
LAST_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "")

# Generate Keep a Changelog sections via shared helper.
# When no tags exist, use --root range to include the initial commit.
CHANGELOG_BODY=""
if [[ -n "$LAST_TAG" ]]; then
    CHANGELOG_BODY=$(generate_keepachangelog "$LAST_TAG" HEAD)
else
    CHANGELOG_BODY=$(generate_keepachangelog_all HEAD)
fi

# Build the new changelog section
NEW_SECTION="## [$NEW_VERSION] - $TODAY"$'\n'
if [[ -n "$CHANGELOG_BODY" ]]; then
    NEW_SECTION+="$CHANGELOG_BODY"$'\n'
else
    NEW_SECTION+=$'\n'"No user-facing changes."$'\n'
fi

# Prepend the new section after the [Unreleased] header.
# Write the section to a temp file first — BSD awk on macOS cannot handle
# literal newlines passed via -v.
if [[ -f "$CHANGELOG" ]]; then
    SECTION_FILE=$(mktemp)
    printf '%s' "$NEW_SECTION" > "$SECTION_FILE"
    TEMP_FILE=$(mktemp)
    awk -v sfile="$SECTION_FILE" '
        /^## \[Unreleased\]/ {
            print
            print ""
            while ((getline line < sfile) > 0) print line
            close(sfile)
            next
        }
        { print }
    ' "$CHANGELOG" > "$TEMP_FILE"
    mv "$TEMP_FILE" "$CHANGELOG"
    rm -f "$SECTION_FILE"
else
    # Create a minimal changelog if none exists
    cat > "$CHANGELOG" << EOF
# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

$NEW_SECTION
EOF
fi

echo "Updated CHANGELOG.md"

# ── Commit and tag ────────────────────────────────────────────────────────────

git add "$PROJECT_YML" "$CONSTANTS_SWIFT" "$CHANGELOG"
git commit -m "chore(build): bump version to $NEW_VERSION"
git tag "v$NEW_VERSION"

echo "Created commit and tag v$NEW_VERSION"
