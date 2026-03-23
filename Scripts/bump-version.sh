#!/bin/bash
set -euo pipefail

# Bump marketing version and build number in Info.plist and Constants.swift,
# then create a git commit and tag.
#
# Usage:
#   ./Scripts/bump-version.sh [major|minor|patch|X.Y.Z]
#
# Examples:
#   ./Scripts/bump-version.sh patch     # 1.0.0 -> 1.0.1
#   ./Scripts/bump-version.sh minor     # 1.0.0 -> 1.1.0
#   ./Scripts/bump-version.sh major     # 1.0.0 -> 2.0.0
#   ./Scripts/bump-version.sh 1.2.3     # Set to an explicit version
#
# What it does:
#   1. Reads CFBundleShortVersionString and CFBundleVersion from Info.plist
#   2. Computes the new marketing version (bump type or explicit semver)
#   3. Increments the build number by 1
#   4. Writes both values back to Info.plist via plutil
#   5. Updates Constants.appVersion in Constants.swift
#   6. Stages the changed files and creates a commit + git tag

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
INFO_PLIST="$PROJECT_DIR/PresentApp/Info.plist"
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

# ── Read current version ──────────────────────────────────────────────────────

CURRENT_VERSION=$(plutil -extract CFBundleShortVersionString raw "$INFO_PLIST")
CURRENT_BUILD=$(plutil -extract CFBundleVersion raw "$INFO_PLIST")

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

# ── Update Info.plist ─────────────────────────────────────────────────────────

plutil -replace CFBundleShortVersionString -string "$NEW_VERSION" "$INFO_PLIST"
plutil -replace CFBundleVersion -string "$NEW_BUILD" "$INFO_PLIST"
echo "Updated Info.plist"

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

# Prepend the new section after the [Unreleased] header
if [[ -f "$CHANGELOG" ]]; then
    TEMP_FILE=$(mktemp)
    awk -v section="$NEW_SECTION" '
        /^## \[Unreleased\]/ {
            print
            print ""
            printf "%s", section
            next
        }
        { print }
    ' "$CHANGELOG" > "$TEMP_FILE"
    mv "$TEMP_FILE" "$CHANGELOG"
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

git add "$INFO_PLIST" "$CONSTANTS_SWIFT" "$CHANGELOG"
git commit -m "chore(build): bump version to $NEW_VERSION"
git tag "v$NEW_VERSION"

echo "Created commit and tag v$NEW_VERSION"
