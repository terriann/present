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

# ── Determine previous tag for changelog ────────────────────────────

if [[ "$BETA_NUM" -gt 1 ]]; then
    PREV_TAG="v${VERSION}-beta.${LAST}"
else
    # First beta — use the most recent tag before HEAD
    PREV_TAG=$(git describe --tags --abbrev=0 HEAD~1 2>/dev/null || echo "")
fi

if [[ -n "$PREV_TAG" ]]; then
    echo "    Changes: $PREV_TAG..HEAD"
fi

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

# ── Generate changelog ─────────────────────────────────────────────

if [[ -n "${PREV_TAG:-}" ]]; then
    REPO_URL="https://github.com/terriann/present"

    # Generate categorized changelog from conventional commit subjects
    # Uses temp files per category (bash 3.2 / macOS awk compatible)
    TMPDIR_CL=$(mktemp -d)
    trap "rm -rf '$TMPDIR_CL' '$NOTES_FILE'" EXIT

    git log "$PREV_TAG"..HEAD --no-merges --format="%s" | while IFS= read -r line; do
        # Extract type and format entry from conventional commit prefix
        type=""
        entry=""
        case "$line" in
            # type(scope): description
            *\(*\):\ *)
                type="${line%%(*}"
                rest="${line#*(}"
                scope="${rest%%)*}"
                desc="${rest#*): }"
                entry="- **${scope}**: ${desc}"
                ;;
            # type: description
            *:\ *)
                type="${line%%:*}"
                desc="${line#*: }"
                # Only treat as conventional commit if type is lowercase alpha
                case "$type" in
                    *[!a-z]*) type="other"; entry="- ${line}" ;;
                    *)        entry="- ${desc}" ;;
                esac
                ;;
            *)
                type="other"
                entry="- ${line}"
                ;;
        esac

        case "$type" in
            feat)     echo "$entry" >> "$TMPDIR_CL/1-feat" ;;
            fix)      echo "$entry" >> "$TMPDIR_CL/2-fix" ;;
            refactor) echo "$entry" >> "$TMPDIR_CL/3-refactor" ;;
            perf)     echo "$entry" >> "$TMPDIR_CL/4-perf" ;;
            docs)     echo "$entry" >> "$TMPDIR_CL/5-docs" ;;
            *)        echo "$entry" >> "$TMPDIR_CL/6-maint" ;;
        esac
    done

    # Build changelog from category files
    append_changelog_section() {
        local file="$1" heading="$2" outfile="$3"
        if [[ -f "$file" ]]; then
            echo "" >> "$outfile"
            echo "### ${heading}" >> "$outfile"
            cat "$file" >> "$outfile"
        fi
    }

    echo "" >> "$NOTES_FILE"
    echo "## What's Changed" >> "$NOTES_FILE"

    append_changelog_section "$TMPDIR_CL/1-feat"     "New Features"   "$NOTES_FILE"
    append_changelog_section "$TMPDIR_CL/2-fix"       "Bug Fixes"      "$NOTES_FILE"
    append_changelog_section "$TMPDIR_CL/3-refactor"  "Improvements"   "$NOTES_FILE"
    append_changelog_section "$TMPDIR_CL/4-perf"      "Performance"    "$NOTES_FILE"
    append_changelog_section "$TMPDIR_CL/5-docs"      "Documentation"  "$NOTES_FILE"
    append_changelog_section "$TMPDIR_CL/6-maint"     "Maintenance"    "$NOTES_FILE"

    # Extract unique issue references from commit bodies
    ISSUES=$(git log "$PREV_TAG"..HEAD --no-merges --format="%b" \
        | grep -oE '#[0-9]+' 2>/dev/null | sort -t'#' -k2 -n -u | paste -sd',' - | sed 's/,/, /g')

    if [[ -n "$ISSUES" ]]; then
        {
            echo ""
            echo "### Referenced Issues"
            echo "Closes ${ISSUES}"
        } >> "$NOTES_FILE"
    fi

    echo "" >> "$NOTES_FILE"
    echo "**Full Changelog**: ${REPO_URL}/compare/${PREV_TAG}...${BETA_TAG}" >> "$NOTES_FILE"

    rm -rf "$TMPDIR_CL"
fi

gh release create "$BETA_TAG" \
    "$DMG_PATH" \
    --prerelease \
    --notes-file "$NOTES_FILE" \
    --title "Present $BETA_TAG"

echo ""
echo "==> Done! Released $BETA_TAG"
echo "    https://github.com/terriann/present/releases/tag/$BETA_TAG"
