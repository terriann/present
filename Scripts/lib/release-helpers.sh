#!/bin/bash
# Shared helper functions for release scripts.
# Source this file; do not execute directly.
#
# Requires: set -euo pipefail in the sourcing script.
# Expects: SCRIPT_DIR and PROJECT_DIR set before sourcing.

REPO_URL="https://github.com/terriann/present"

# ── Pre-flight checks ────────────────────────────────────────────────────────

preflight_checks() {
    echo "==> Pre-flight checks..."

    if [[ -n "$(git status --porcelain)" ]]; then
        echo "Error: working tree is not clean. Commit or stash changes first."
        exit 1
    fi

    local branch
    branch=$(git rev-parse --abbrev-ref HEAD)
    if [[ "$branch" != "main" ]]; then
        echo "Error: must be on main branch (currently on $branch)."
        exit 1
    fi

    if ! command -v gh &>/dev/null; then
        echo "Error: gh CLI not found. Install with: brew install gh"
        exit 1
    fi

    git fetch --all --tags --quiet

    local local_head remote_head
    local_head=$(git rev-parse HEAD)
    remote_head=$(git rev-parse origin/main)

    if [[ "$local_head" != "$remote_head" ]]; then
        echo "Error: local main ($local_head) does not match origin/main ($remote_head)."
        echo "       Run 'git pull' first to ensure you're building the latest code."
        exit 1
    fi
}

# ── Resolve version ──────────────────────────────────────────────────────────
# Sets global: VERSION
# Args: optional explicit version string

resolve_version() {
    if [[ -n "${1:-}" ]]; then
        VERSION="$1"
    else
        local raw_version
        raw_version=$(grep 'MARKETING_VERSION:' "$PROJECT_DIR/project.yml" | head -1 | sed 's/.*: *"\(.*\)"/\1/')
        VERSION="${raw_version%%-*}"
        if [[ -z "$VERSION" ]]; then
            echo "Error: could not read MARKETING_VERSION from project.yml"
            exit 1
        fi
    fi
    echo "    Version: $VERSION"
}

# ── Build DMG ────────────────────────────────────────────────────────────────
# Sets global: DMG_PATH
# Args: version label (used in filename)

build_dmg() {
    local version_label="$1"
    local dmg_filename="Present-${version_label}.dmg"

    echo ""
    "$SCRIPT_DIR/build-dmg.sh" "$version_label"
    echo ""

    DMG_PATH="$PROJECT_DIR/build/$dmg_filename"
    if [[ ! -f "$DMG_PATH" ]]; then
        echo "Error: DMG not found at $DMG_PATH"
        exit 1
    fi
}

# ── Tag helpers ──────────────────────────────────────────────────────────────

# Most recent vX.Y.Z tag (excludes pre-release suffixes like -beta.N)
get_last_stable_tag() {
    git tag -l 'v[0-9]*.[0-9]*.[0-9]*' \
        | grep -v '-' \
        | sort -V \
        | tail -1
}

# Most recent tag at or before the commit before HEAD.
# Used by beta-release to find the previous tag when HEAD itself may be untagged
# but we want the tag *before* the current set of commits.
get_last_tag() {
    git describe --tags --abbrev=0 HEAD~1 2>/dev/null || echo ""
}

# ── Shared commit classifier ─────────────────────────────────────────────────
# Parses a conventional commit subject line and sets globals:
#   _CC_TYPE   — commit type (feat, fix, refactor, etc.) or "other"
#   _CC_SCOPE  — scope string (empty if none)
#   _CC_DESC   — description text
#
# Args: $1 — single commit subject line

_classify_commit() {
    local line="$1"
    _CC_TYPE="" _CC_SCOPE="" _CC_DESC=""

    case "$line" in
        # type(scope): description
        *\(*\):\ *)
            _CC_TYPE="${line%%(*}"
            local rest="${line#*(}"
            _CC_SCOPE="${rest%%)*}"
            _CC_DESC="${rest#*): }"
            ;;
        # type: description
        *:\ *)
            _CC_TYPE="${line%%:*}"
            _CC_DESC="${line#*: }"
            # Only treat as conventional commit if type is lowercase alpha
            case "$_CC_TYPE" in
                *[!a-z]*) _CC_TYPE="other"; _CC_DESC="$line" ;;
            esac
            ;;
        *)
            _CC_TYPE="other"
            _CC_DESC="$line"
            ;;
    esac
}

# Map a commit type to a category file suffix.
# Args: $1 — commit type
# Prints: category key (e.g., "1-feat", "6-maint")
_commit_category() {
    case "$1" in
        feat)     echo "1-feat" ;;
        fix)      echo "2-fix" ;;
        refactor) echo "3-refactor" ;;
        perf)     echo "4-perf" ;;
        docs)     echo "5-docs" ;;
        *)        echo "6-maint" ;;
    esac
}

# ── Changelog generation ────────────────────────────────────────────────────
# Writes changelog markdown to stdout.
#
# Args:
#   $1  PREV_TAG       — baseline tag (commits after this are included)
#   $2  HEAD_REF       — end ref (default: HEAD)
#   $3  INCLUDE_SCOPE  — "true" to show **scope**: prefix in entries
#   $4  SKIP_INTERNAL  — "true" to omit chore/build/ci/test/docs types

generate_changelog() {
    local prev_tag="$1"
    local head_ref="${2:-HEAD}"
    local include_scope="${3:-true}"
    local skip_internal="${4:-false}"

    local tmpdir
    tmpdir=$(mktemp -d)
    # Ensure tmpdir is cleaned up even if the caller is interrupted.
    # Append to any existing EXIT trap rather than replacing it.
    trap "rm -rf '$tmpdir'; $(trap -p EXIT | sed "s/^trap -- '//;s/' EXIT$//")" EXIT

    git log "${prev_tag}..${head_ref}" --no-merges --format="%s" | while IFS= read -r line; do
        _classify_commit "$line"

        # Skip internal types when requested
        if [[ "$skip_internal" == "true" ]]; then
            case "$_CC_TYPE" in
                chore|build|ci|test|docs) continue ;;
            esac
        fi

        local entry
        if [[ -n "$_CC_SCOPE" && "$include_scope" == "true" ]]; then
            entry="- **${_CC_SCOPE}**: ${_CC_DESC}"
        else
            entry="- ${_CC_DESC}"
        fi

        echo "$entry" >> "$tmpdir/$(_commit_category "$_CC_TYPE")"
    done

    # Check if any category files were created
    local has_entries=false
    for f in "$tmpdir"/[1-6]-*; do
        if [[ -f "$f" ]]; then
            has_entries=true
            break
        fi
    done

    if [[ "$has_entries" == "true" ]]; then
        echo ""
        echo "## What's Changed"

        local file heading
        for file_heading in \
            "$tmpdir/1-feat:New Features" \
            "$tmpdir/2-fix:Bug Fixes" \
            "$tmpdir/3-refactor:Improvements" \
            "$tmpdir/4-perf:Performance" \
            "$tmpdir/5-docs:Documentation" \
            "$tmpdir/6-maint:Maintenance"; do
            file="${file_heading%%:*}"
            heading="${file_heading#*:}"
            if [[ -f "$file" ]]; then
                echo ""
                echo "### ${heading}"
                cat "$file"
            fi
        done
    fi

    # Issue references from commit bodies
    local issues
    issues=$(git log "${prev_tag}..${head_ref}" --no-merges --format="%b" \
        | grep -oE '#[0-9]+' 2>/dev/null | sort -t'#' -k2 -n -u | paste -sd',' - | sed 's/,/, /g') || true

    if [[ -n "$issues" ]]; then
        echo ""
        echo "### Referenced Issues"
        echo "Closes ${issues}"
    fi

    rm -rf "$tmpdir"
}

# ── Changelog for Keep a Changelog format ────────────────────────────────────
# Writes Keep a Changelog sections (Added/Changed/Fixed) to stdout.
# Omits scope prefixes and internal commit types.
#
# Args:
#   $1  PREV_TAG   — baseline tag
#   $2  HEAD_REF   — end ref (default: HEAD)

generate_keepachangelog() {
    _keepachangelog_from_commits "$(git log --pretty=format:"%s" "${1}..${2:-HEAD}")"
}

# Variant that includes all commits up to HEAD_REF (no baseline tag).
# Used when no tags exist yet.
generate_keepachangelog_all() {
    _keepachangelog_from_commits "$(git log --pretty=format:"%s" "${1:-HEAD}")"
}

# Internal: classify commits and emit Keep a Changelog sections.
# Args: $1 — newline-separated commit subjects
_keepachangelog_from_commits() {
    local commits="$1"

    local section_added="" section_changed="" section_fixed="" section_other=""

    while IFS= read -r commit; do
        [[ -z "$commit" ]] && continue
        _classify_commit "$commit"

        case "$_CC_TYPE" in
            feat)                section_added+="- ${_CC_DESC}"$'\n' ;;
            fix)                 section_fixed+="- ${_CC_DESC}"$'\n' ;;
            refactor|perf|style) section_changed+="- ${_CC_DESC}"$'\n' ;;
            chore|build|ci|test|docs) : ;; # skip internal
            *)                   section_other+="- ${_CC_DESC}"$'\n' ;;
        esac
    done <<< "$commits"

    if [[ -n "$section_added" ]]; then
        printf '\n### Added\n%s' "$section_added"
    fi
    if [[ -n "$section_changed" ]]; then
        printf '\n### Changed\n%s' "$section_changed"
    fi
    if [[ -n "$section_fixed" ]]; then
        printf '\n### Fixed\n%s' "$section_fixed"
    fi
    if [[ -n "$section_other" ]]; then
        printf '\n### Other\n%s' "$section_other"
    fi
}
