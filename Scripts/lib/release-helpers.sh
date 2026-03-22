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

# Most recent tag of any kind
get_last_tag() {
    git describe --tags --abbrev=0 HEAD 2>/dev/null || echo ""
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

    git log "${prev_tag}..${head_ref}" --no-merges --format="%s" | while IFS= read -r line; do
        local type="" entry=""

        case "$line" in
            # type(scope): description
            *\(*\):\ *)
                type="${line%%(*}"
                local rest="${line#*(}"
                local scope="${rest%%)*}"
                local desc="${rest#*): }"
                if [[ "$include_scope" == "true" ]]; then
                    entry="- **${scope}**: ${desc}"
                else
                    entry="- ${desc}"
                fi
                ;;
            # type: description
            *:\ *)
                type="${line%%:*}"
                local desc="${line#*: }"
                case "$type" in
                    *[!a-z]*) type="other"; entry="- ${line}" ;;
                    *)
                        if [[ "$include_scope" == "true" ]]; then
                            entry="- ${desc}"
                        else
                            entry="- ${desc}"
                        fi
                        ;;
                esac
                ;;
            *)
                type="other"
                entry="- ${line}"
                ;;
        esac

        # Skip internal types when requested
        if [[ "$skip_internal" == "true" ]]; then
            case "$type" in
                chore|build|ci|test|docs) continue ;;
            esac
        fi

        case "$type" in
            feat)     echo "$entry" >> "$tmpdir/1-feat" ;;
            fix)      echo "$entry" >> "$tmpdir/2-fix" ;;
            refactor) echo "$entry" >> "$tmpdir/3-refactor" ;;
            perf)     echo "$entry" >> "$tmpdir/4-perf" ;;
            docs)     echo "$entry" >> "$tmpdir/5-docs" ;;
            *)        echo "$entry" >> "$tmpdir/6-maint" ;;
        esac
    done

    # Emit categorized sections
    _emit_section() {
        local file="$1" heading="$2"
        if [[ -f "$file" ]]; then
            echo ""
            echo "### ${heading}"
            cat "$file"
        fi
    }

    echo ""
    echo "## What's Changed"

    _emit_section "$tmpdir/1-feat"     "New Features"
    _emit_section "$tmpdir/2-fix"      "Bug Fixes"
    _emit_section "$tmpdir/3-refactor" "Improvements"
    _emit_section "$tmpdir/4-perf"     "Performance"
    _emit_section "$tmpdir/5-docs"     "Documentation"
    _emit_section "$tmpdir/6-maint"    "Maintenance"

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
    local prev_tag="$1"
    local head_ref="${2:-HEAD}"

    local section_added="" section_changed="" section_fixed="" section_other=""
    local commits
    commits=$(git log --pretty=format:"%s" "${prev_tag}..${head_ref}")

    # Store regexes in variables for bash 3.2 compatibility
    local re_feat='^feat(\([^)]+\))?!?:[[:space:]](.+)$'
    local re_fix='^fix(\([^)]+\))?!?:[[:space:]](.+)$'
    local re_refactor='^refactor(\([^)]+\))?!?:[[:space:]](.+)$'
    local re_perf_style='^(perf|style)(\([^)]+\))?!?:[[:space:]](.+)$'
    local re_internal='^(chore|build|ci|test|docs)(\([^)]+\))?!?:[[:space:]].+$'

    while IFS= read -r commit; do
        [[ -z "$commit" ]] && continue
        if [[ "$commit" =~ $re_feat ]]; then
            section_added+="- ${BASH_REMATCH[2]}"$'\n'
        elif [[ "$commit" =~ $re_fix ]]; then
            section_fixed+="- ${BASH_REMATCH[2]}"$'\n'
        elif [[ "$commit" =~ $re_refactor ]]; then
            section_changed+="- ${BASH_REMATCH[2]}"$'\n'
        elif [[ "$commit" =~ $re_perf_style ]]; then
            section_changed+="- ${BASH_REMATCH[3]}"$'\n'
        elif [[ "$commit" =~ $re_internal ]]; then
            : # skip internal/meta commits
        else
            section_other+="- $commit"$'\n'
        fi
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
