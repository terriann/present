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
CHANGELOG="$PROJECT_DIR/CHANGELOG.md"

# ── Guard: GitHub release must not already exist ─────────────────────────────
# The git tag is expected to exist (created by bump-version.sh). Only block if
# a GitHub release has already been published for this tag.

if gh release view "$TAG" &>/dev/null; then
    echo "Error: GitHub release $TAG already exists. Aborting."
    exit 1
fi

# ── Determine previous stable tag for changelog ─────────────────────────────
# Exclude the current tag so the range covers what's new in this release.

PREV_TAG=$(git tag -l 'v[0-9]*.[0-9]*.[0-9]*' | grep -v '-' | grep -v "^${TAG}$" | sort -V | tail -1 || true)

# If no previous stable tag, fall back to any tag (including betas) so
# the changelog is scoped to this milestone rather than all commits.
if [[ -z "$PREV_TAG" ]]; then
    PREV_TAG=$(git tag -l 'v[0-9]*' | grep -v "^${TAG}$" | sort -V | tail -1 || true)
fi

if [[ -n "$PREV_TAG" ]]; then
    echo "    Changes: $PREV_TAG..HEAD"
else
    echo "    Changes: (all commits — no previous tag found)"
fi

# ── Regenerate CHANGELOG.md ──────────────────────────────────────────────────
# The bump script creates an initial changelog section at milestone start, but
# more commits land during the milestone. Regenerate the section now so it
# captures everything.

echo "==> Updating CHANGELOG.md..."
TODAY=$(date +%Y-%m-%d)

CHANGELOG_BODY=""
if [[ -n "$PREV_TAG" ]]; then
    CHANGELOG_BODY=$(generate_keepachangelog "$PREV_TAG" HEAD)
else
    CHANGELOG_BODY=$(generate_keepachangelog_all HEAD)
fi

NEW_SECTION="## [$VERSION] - $TODAY"$'\n'
if [[ -n "$CHANGELOG_BODY" ]]; then
    NEW_SECTION+="$CHANGELOG_BODY"$'\n'
else
    NEW_SECTION+=$'\n'"No user-facing changes."$'\n'
fi

if [[ -f "$CHANGELOG" ]]; then
    SECTION_FILE=$(mktemp)
    printf '%s' "$NEW_SECTION" > "$SECTION_FILE"
    TEMP_FILE=$(mktemp)

    # If a section for this version already exists (from bump-version.sh),
    # replace it. Otherwise insert after [Unreleased].
    if grep -q "^## \[$VERSION\]" "$CHANGELOG"; then
        # Replace: skip lines from the existing version header until the next
        # ## header (or EOF), inserting the new section in its place.
        awk -v sfile="$SECTION_FILE" -v ver="$VERSION" '
            $0 ~ "^## \\[" ver "\\]" {
                while ((getline line < sfile) > 0) print line
                close(sfile)
                skip = 1
                next
            }
            /^## / && skip { skip = 0 }
            !skip { print }
        ' "$CHANGELOG" > "$TEMP_FILE"
    else
        # Insert after [Unreleased]
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
    fi

    mv "$TEMP_FILE" "$CHANGELOG"
    rm -f "$SECTION_FILE"
fi

# ── Commit changelog and update tag ─────────────────────────────────────────

if [[ -n "$(git diff -- "$CHANGELOG")" ]]; then
    git add "$CHANGELOG"
    git commit -m "docs(build): regenerate CHANGELOG.md for v${VERSION} release"
    echo "    CHANGELOG.md updated and committed."
fi

# Move tag to current HEAD (it may have been created by bump-version at an
# earlier commit). Force-update is safe because the GitHub release hasn't
# been created yet.
if git rev-parse "$TAG" &>/dev/null; then
    git tag -f "$TAG"
    git push origin "$TAG" --force
    echo "    Tag $TAG moved to $(git rev-parse --short HEAD)."
else
    git tag "$TAG"
    git push origin "$TAG"
    echo "    Tag $TAG created at $(git rev-parse --short HEAD)."
fi

git push

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

# ── Publish GitHub release ───────────────────────────────────────────────────

gh release create "$TAG" \
    "$DMG_PATH" \
    --latest \
    --notes-file "$NOTES_FILE" \
    --title "Present v${VERSION}"

echo ""
echo "==> Done! Released $TAG"
echo "    https://github.com/terriann/present/releases/tag/$TAG"
