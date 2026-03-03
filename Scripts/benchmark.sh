#!/bin/bash
set -euo pipefail

# Run XCTest performance benchmarks and extract metrics to JSON.
#
# Refuses to run with uncommitted .swift changes to ensure results
# are tied to a clean, reproducible commit.
#
# Usage:
#   ./Scripts/benchmark.sh                        Run benchmarks, save results
#   ./Scripts/benchmark.sh --compare HASH|latest  Run + compare against a baseline
#   ./Scripts/benchmark.sh --compare-only OLD NEW Compare two existing result files
#   ./Scripts/benchmark.sh --baseline REF         Run REF in a worktree, then HEAD, compare
#   ./Scripts/benchmark.sh --dry-run              Show what would run without executing
#
# Options:
#   --compare REF    Compare against a previous result. REF can be:
#                      - A git hash (e.g., 5a8cccb) -- finds matching result file
#                      - A file path (e.g., benchmarks/2026-02-28-5a8cccb.json)
#                      - "latest" -- uses the most recent result (excluding current)
#   --compare-only OLD NEW  Compare two existing results without running benchmarks.
#                           OLD and NEW can be hashes, file paths, or "latest".
#   --baseline REF   Benchmark REF (in a temp worktree) and HEAD, then compare.
#                    REF can be a branch, tag, or commit hash.
#   --dry-run        Show commands without executing
#   -h, --help       Show this help

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
RESULTS_DIR="$PROJECT_DIR/benchmarks"
TEST_TARGET="PresentBenchmarks"
DRY_RUN=false
COMPARE_FILE=""
COMPARE_ONLY_OLD=""
COMPARE_ONLY_NEW=""
BASELINE_REF=""

# ---------- Argument parsing ----------

usage() {
    sed -n '3,25p' "$0" | sed -E 's/^# ?//'
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --compare-only)
            COMPARE_ONLY_OLD="${2:-}"
            COMPARE_ONLY_NEW="${3:-}"
            if [[ -z "$COMPARE_ONLY_OLD" ]] || [[ -z "$COMPARE_ONLY_NEW" ]]; then
                echo "Error: --compare-only requires two arguments: OLD NEW"
                echo "  Each can be a git hash, file path, or 'latest'"
                exit 1
            fi
            shift 3
            ;;
        --compare)
            COMPARE_FILE="${2:-}"
            if [[ -z "$COMPARE_FILE" ]]; then
                echo "Error: --compare requires a hash, file path, or 'latest'"
                exit 1
            fi
            shift 2
            ;;
        --baseline)
            BASELINE_REF="${2:-}"
            if [[ -z "$BASELINE_REF" ]]; then
                echo "Error: --baseline requires a ref (branch, tag, or commit hash)"
                exit 1
            fi
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

# ---------- Validate mutual exclusivity ----------

MODES_SET=0
[[ -n "$COMPARE_ONLY_OLD" ]] && MODES_SET=$((MODES_SET + 1))
[[ -n "$COMPARE_FILE" ]] && MODES_SET=$((MODES_SET + 1))
[[ -n "$BASELINE_REF" ]] && MODES_SET=$((MODES_SET + 1))
if [[ "$MODES_SET" -gt 1 ]]; then
    echo "Error: --compare, --compare-only, and --baseline are mutually exclusive."
    exit 1
fi

# ---------- Resolve a reference to a result file path ----------
# Accepts: file path, git hash, partial hash, or "latest"
# Sets the variable named by $2 to the resolved path, or exits on failure.

resolve_ref() {
    local ref="$1"
    local varname="$2"
    local exclude="${3:-}"  # optional filename to exclude (for "latest")

    if [[ "$ref" == "latest" ]]; then
        local found
        if [[ -n "$exclude" ]]; then
            found=$(ls -t "$RESULTS_DIR"/*.json 2>/dev/null | grep -v "$exclude" | head -1 || true)
        else
            found=$(ls -t "$RESULTS_DIR"/*.json 2>/dev/null | head -1 || true)
        fi
        if [[ -z "$found" ]]; then
            echo "Error: no benchmark results found."
            exit 1
        fi
        eval "$varname='$found'"
    elif [[ -f "$ref" ]]; then
        eval "$varname='$ref'"
    else
        # Treat as a git hash -- search for matching result file
        local found
        found=$(ls "$RESULTS_DIR"/*-"${ref}".json 2>/dev/null | head -1 || true)
        if [[ -z "$found" ]]; then
            found=$(ls "$RESULTS_DIR"/*-"${ref}"*.json 2>/dev/null | head -1 || true)
        fi
        if [[ -z "$found" ]]; then
            echo "Error: no benchmark result found for '$ref'"
            echo ""
            echo "Available results:"
            ls "$RESULTS_DIR"/*.json 2>/dev/null | while read -r f; do
                echo "  $(basename "$f")"
            done
            exit 1
        fi
        eval "$varname='$found'"
    fi
}

# ---------- compare_results() ----------
# Usage: compare_results <old_result_file> <new_result_file> <repo_url>
# Prints a GitHub-flavored markdown comparison table to stdout.

compare_results() {
    local old_file="$1"
    local new_file="$2"
    local repo_url="${3:-}"

    python3 - "$old_file" "$new_file" "$repo_url" <<'COMPARE_SCRIPT'
import json, sys

with open(sys.argv[1]) as f:
    baseline = json.load(f)
with open(sys.argv[2]) as f:
    current = json.load(f)
repo_url = sys.argv[3] if len(sys.argv) > 3 else ""

b_commit = baseline["commit"]
b_date = baseline["date"]
c_commit = current["commit"]
c_date = current["date"]

def commit_ref(sha, date):
    if repo_url:
        return f"[`{sha}`]({repo_url}/commit/{sha}) ({date})"
    return f"`{sha}` ({date})"

all_tests = sorted(set(list(baseline["benchmarks"]) + list(current["benchmarks"])))

key_metrics = [
    ("Clock Monotonic Time", "Clock", "s"),
    ("CPU Time", "CPU", "s"),
    ("Memory Peak Physical", "Mem Peak", "kB"),
]

rows = []
improved = 0
regressed = 0
stable = 0

for test_name in all_tests:
    b_metrics = baseline["benchmarks"].get(test_name, {})
    c_metrics = current["benchmarks"].get(test_name, {})
    if not b_metrics and not c_metrics:
        continue

    display_name = test_name.replace("Performance", "")
    if display_name.startswith("test"):
        display_name = display_name[4:]

    row = {"name": display_name, "cells": []}

    for metric_key, label, unit in key_metrics:
        b = b_metrics.get(metric_key, {})
        c = c_metrics.get(metric_key, {})
        b_avg = b.get("average", 0)
        c_avg = c.get("average", 0)

        if b_avg > 0:
            pct = ((c_avg - b_avg) / b_avg) * 100

            if unit == "s":
                b_str = f"{b_avg * 1000:.1f}ms" if b_avg < 1 else f"{b_avg:.3f}s"
                c_str = f"{c_avg * 1000:.1f}ms" if c_avg < 1 else f"{c_avg:.3f}s"
            elif unit == "kB":
                if b_avg > 1024:
                    b_str = f"{b_avg / 1024:.1f} MB"
                    c_str = f"{c_avg / 1024:.1f} MB"
                else:
                    b_str = f"{b_avg:.0f} kB"
                    c_str = f"{c_avg:.0f} kB"
            else:
                b_str = f"{b_avg:.3f}"
                c_str = f"{c_avg:.3f}"

            if abs(pct) < 2:
                indicator = " :white_circle:"
                stable += 1
            elif pct < -5:
                indicator = " :tada:"
                improved += 1
            elif pct < 0:
                indicator = " :white_check_mark:"
                improved += 1
            elif pct > 10:
                indicator = " :rotating_light:"
                regressed += 1
            elif pct > 5:
                indicator = " :warning:"
                regressed += 1
            else:
                indicator = " :white_circle:"
                stable += 1

            sign = "+" if pct > 0 else ""
            row["cells"].append(f"{c_str} ({sign}{pct:.1f}%){indicator}")
        elif c_avg > 0:
            row["cells"].append(f"{c_avg:.3f} (new)")
        else:
            row["cells"].append("--")

    rows.append(row)

parts = []
if improved > 0:
    parts.append(f"**{improved}** improved")
if regressed > 0:
    parts.append(f"**{regressed}** regressed")
if stable > 0:
    parts.append(f"**{stable}** stable")

print(f"## Benchmark Comparison")
print()
print(f"{commit_ref(b_commit, b_date)} \u2192 {commit_ref(c_commit, c_date)}")
print()
print(" \u00b7 ".join(parts))
print()

header_labels = [m[1] for m in key_metrics]
print("| Benchmark | " + " | ".join(header_labels) + " |")
print("|:--|" + "|".join(["--:" for _ in key_metrics]) + "|")

for row in rows:
    print(f"| **{row['name']}** | " + " | ".join(row["cells"]) + " |")

print()
print("<details>")
print("<summary>Legend</summary>")
print()
print("| Icon | Meaning |")
print("|:--:|:--|")
print("| :tada: | Improvement > 5% |")
print("| :white_check_mark: | Improvement up to 5% |")
print("| :white_circle: | Stable (within \u00b12%) |")
print("| :warning: | Regression > 5% |")
print("| :rotating_light: | Regression > 10% |")
print()
print("</details>")
print()
COMPARE_SCRIPT
}

# ---------- run_benchmarks() ----------
# Usage: run_benchmarks <work_dir> <results_dir>
# Runs benchmarks in <work_dir>, saves JSON to <results_dir>.
# Prints the result file path on the last line of stdout.
# Skips the run if a result file already exists for the commit.

run_benchmarks() {
    local work_dir="$1"
    local results_dir="$2"

    local git_hash
    git_hash=$(git -C "$work_dir" rev-parse --short HEAD)
    local date_stamp
    date_stamp=$(date "+%Y-%m-%d")
    local result_name="${date_stamp}-${git_hash}"
    local result_path="${results_dir}/${result_name}.json"

    # Reuse cached result if it exists
    if [[ -f "$result_path" ]]; then
        echo "Reusing existing result for ${git_hash}: benchmarks/${result_name}.json" >&2
        echo "$result_path"
        return 0
    fi

    echo "Benchmark run: $result_name" >&2
    echo "Commit: $(git -C "$work_dir" log --oneline -1)" >&2
    echo "" >&2

    echo "Running benchmarks in ${work_dir}..." >&2
    echo "" >&2

    local test_output
    test_output=$(cd "$work_dir" && swift test --filter "$TEST_TARGET" 2>&1) || true

    # Check that benchmarks actually ran
    if ! echo "$test_output" | grep -q "measured \["; then
        echo "Error: no benchmark metrics found in test output." >&2
        echo "" >&2
        echo "Test output:" >&2
        echo "$test_output" | tail -20 >&2
        return 1
    fi

    # Check for test failures (excluding performance baseline failures)
    if echo "$test_output" | grep -q "with 0 failures"; then
        echo "All benchmarks passed." >&2
    else
        echo "Warning: some benchmarks may have failed. Check output above." >&2
    fi
    echo "" >&2

    echo "Extracting metrics..." >&2

    local metrics_json
    metrics_json=$(echo "$test_output" | python3 -c '
import sys, json, re, statistics

lines = sys.stdin.readlines()

# Pattern: Test Case ...[TestClass testMethod]... measured [MetricName, unit] average: N, ...values: [v1, v2, ...]...
pattern = re.compile(
    r"Test Case .+-\[.*?\.(\w+)\s+(\w+)\].+measured \[(.+?),\s*(\S+)\]\s+"
    r"average:\s*([\d.]+),\s*relative standard deviation:\s*([\d.]+)%,\s*"
    r"values:\s*\[([\d., ]+)\]"
)

benchmarks = {}

for line in lines:
    m = pattern.search(line)
    if not m:
        continue

    class_name, test_name, metric_name, unit, avg_str, stddev_str, values_str = m.groups()

    values = [float(v.strip()) for v in values_str.split(",") if v.strip()]
    avg = float(avg_str)
    stddev_pct = float(stddev_str)

    if test_name not in benchmarks:
        benchmarks[test_name] = {}

    benchmarks[test_name][metric_name] = {
        "average": round(statistics.mean(values), 6) if values else avg,
        "unit": unit,
        "stddev_pct": round(stddev_pct, 3),
        "samples": len(values),
        "min": round(min(values), 6) if values else 0,
        "max": round(max(values), 6) if values else 0,
        "values": [round(v, 6) for v in values]
    }

result = {
    "date": sys.argv[1],
    "commit": sys.argv[2],
    "benchmarks": benchmarks
}

json.dump(result, sys.stdout, indent=2, sort_keys=True)
print()
' "$date_stamp" "$git_hash")

    if [[ -z "$metrics_json" ]] || [[ "$metrics_json" == '{"benchmarks": {}, '* ]]; then
        echo "Error: failed to extract metrics from test output." >&2
        return 1
    fi

    mkdir -p "$results_dir"
    echo "$metrics_json" > "$result_path"

    local benchmark_count
    benchmark_count=$(echo "$metrics_json" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)["benchmarks"]))')
    echo "Saved $benchmark_count benchmarks to benchmarks/${result_name}.json" >&2
    echo "" >&2

    echo "$result_path"
}

# ---------- Derive GitHub repo URL for commit links ----------

cd "$PROJECT_DIR"

REMOTE_URL=$(git remote get-url origin 2>/dev/null || true)
REPO_URL=""
if [[ "$REMOTE_URL" =~ github\.com[:/](.+)\.git$ ]]; then
    REPO_URL="https://github.com/${BASH_REMATCH[1]}"
elif [[ "$REMOTE_URL" =~ github\.com[:/](.+)$ ]]; then
    REPO_URL="https://github.com/${BASH_REMATCH[1]}"
fi

# ---------- Compare-only mode ----------

if [[ -n "$COMPARE_ONLY_OLD" ]]; then
    resolve_ref "$COMPARE_ONLY_OLD" RESOLVED_OLD || exit 1
    resolve_ref "$COMPARE_ONLY_NEW" RESOLVED_NEW || exit 1

    compare_results "$RESOLVED_OLD" "$RESOLVED_NEW" "$REPO_URL"
    exit 0
fi

# ---------- Dirty tree guard ----------

DIRTY_FILES=$(git status --porcelain -- '*.swift' 2>/dev/null | head -20)
if [[ -n "$DIRTY_FILES" ]]; then
    echo "Error: uncommitted .swift changes detected."
    echo ""
    echo "Benchmark results are named by git commit hash, so all Swift"
    echo "changes must be committed first to ensure reproducibility."
    echo ""
    echo "Changed files:"
    echo "$DIRTY_FILES"
    echo ""
    echo "Commit or stash your changes, then try again."
    exit 1
fi

# ---------- Baseline mode ----------

if [[ -n "$BASELINE_REF" ]]; then
    # Validate the ref exists
    if ! git rev-parse --verify "$BASELINE_REF" >/dev/null 2>&1; then
        echo "Error: '$BASELINE_REF' is not a valid git ref."
        exit 1
    fi

    # Same-commit guard
    BASELINE_HASH=$(git rev-parse "$BASELINE_REF")
    HEAD_HASH=$(git rev-parse HEAD)
    if [[ "$BASELINE_HASH" == "$HEAD_HASH" ]]; then
        echo "Error: --baseline ref resolves to the same commit as HEAD ($HEAD_HASH)."
        echo "Nothing to compare."
        exit 1
    fi

    BASELINE_SHORT=$(git rev-parse --short "$BASELINE_REF")
    HEAD_SHORT=$(git rev-parse --short HEAD)

    # Dry-run path
    if [[ "$DRY_RUN" == true ]]; then
        echo "[dry-run] Baseline mode: $BASELINE_REF ($BASELINE_SHORT) -> HEAD ($HEAD_SHORT)"
        echo "[dry-run] Would create a temporary worktree for $BASELINE_REF"
        echo "[dry-run] Would run: swift test --filter $TEST_TARGET (in worktree)"
        echo "[dry-run] Would run: swift test --filter $TEST_TARGET (in $PROJECT_DIR)"
        echo "[dry-run] Would compare results and print markdown table"
        exit 0
    fi

    echo "Baseline comparison: $BASELINE_REF ($BASELINE_SHORT) -> HEAD ($HEAD_SHORT)"
    echo ""

    # Create temporary worktree
    WORKTREE_DIR=$(mktemp -d)
    git worktree add --detach "$WORKTREE_DIR" "$BASELINE_REF" 2>&1 | head -5

    cleanup_worktree() {
        if [[ -d "$WORKTREE_DIR" ]]; then
            git worktree remove --force "$WORKTREE_DIR" 2>/dev/null || true
        fi
    }
    trap cleanup_worktree EXIT

    echo ""

    # Run baseline benchmarks
    BASELINE_RESULT=$(run_benchmarks "$WORKTREE_DIR" "$RESULTS_DIR")

    # Clean up worktree early to free disk/lock
    cleanup_worktree
    trap - EXIT

    # Run HEAD benchmarks
    HEAD_RESULT=$(run_benchmarks "$PROJECT_DIR" "$RESULTS_DIR")

    # Compare
    compare_results "$BASELINE_RESULT" "$HEAD_RESULT" "$REPO_URL"
    exit 0
fi

# ---------- Standard mode: run benchmarks ----------

GIT_HASH=$(git rev-parse --short HEAD)
DATE_STAMP=$(date "+%Y-%m-%d")
RESULT_NAME="${DATE_STAMP}-${GIT_HASH}"
RESULT_PATH="$RESULTS_DIR/${RESULT_NAME}.json"

echo "Benchmark run: $RESULT_NAME"
echo "Commit: $(git log --oneline -1)"
echo ""

if [[ "$DRY_RUN" == true ]]; then
    echo "[dry-run] Would run: swift test --filter $TEST_TARGET"
    echo "[dry-run] Would save results to: $RESULT_PATH"
    if [[ -n "$COMPARE_FILE" ]]; then
        echo "[dry-run] Would compare against: $COMPARE_FILE"
    fi
    exit 0
fi

RESULT_PATH=$(run_benchmarks "$PROJECT_DIR" "$RESULTS_DIR")

# ---------- Compare (if requested) ----------

if [[ -n "$COMPARE_FILE" ]]; then
    RESULT_NAME=$(basename "$RESULT_PATH")
    resolve_ref "$COMPARE_FILE" COMPARE_FILE "$RESULT_NAME"

    echo "Comparing against: $(basename "$COMPARE_FILE")"
    echo ""

    compare_results "$COMPARE_FILE" "$RESULT_PATH" "$REPO_URL"
fi
