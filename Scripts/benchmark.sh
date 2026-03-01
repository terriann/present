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
#   ./Scripts/benchmark.sh --dry-run              Show what would run without executing
#
# Options:
#   --compare REF    Compare against a previous result. REF can be:
#                      - A git hash (e.g., 5a8cccb) — finds matching result file
#                      - A file path (e.g., benchmarks/2026-02-28-5a8cccb.json)
#                      - "latest" — uses the most recent result (excluding current)
#   --dry-run        Show commands without executing
#   -h, --help       Show this help

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
RESULTS_DIR="$PROJECT_DIR/benchmarks"
TEST_TARGET="PresentBenchmarks"
DRY_RUN=false
COMPARE_FILE=""

# ---------- Argument parsing ----------

usage() {
    sed -n '3,17p' "$0" | sed -E 's/^# ?//'
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --compare)
            COMPARE_FILE="${2:-}"
            if [[ -z "$COMPARE_FILE" ]]; then
                echo "Error: --compare requires a hash, file path, or 'latest'"
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

# ---------- Dirty tree guard ----------

cd "$PROJECT_DIR"

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

# ---------- Result naming ----------

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

# ---------- Run benchmarks ----------

echo "Running benchmarks..."
echo ""

TEST_OUTPUT=$(swift test --filter "$TEST_TARGET" 2>&1) || true

# Check that benchmarks actually ran
if ! echo "$TEST_OUTPUT" | grep -q "measured \["; then
    echo "Error: no benchmark metrics found in test output."
    echo ""
    echo "Test output:"
    echo "$TEST_OUTPUT" | tail -20
    exit 1
fi

# Check for test failures (excluding performance baseline failures)
FAILURES=$(echo "$TEST_OUTPUT" | grep -c "with [0-9]* failures" | head -1 || true)
if echo "$TEST_OUTPUT" | grep -q "with 0 failures"; then
    echo "All benchmarks passed."
else
    echo "Warning: some benchmarks may have failed. Check output above."
fi
echo ""

# ---------- Extract metrics ----------

echo "Extracting metrics..."

METRICS_JSON=$(echo "$TEST_OUTPUT" | python3 -c '
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
' "$DATE_STAMP" "$GIT_HASH")

if [[ -z "$METRICS_JSON" ]] || [[ "$METRICS_JSON" == '{"benchmarks": {}, '* ]]; then
    echo "Error: failed to extract metrics from test output."
    exit 1
fi

# ---------- Save results ----------

mkdir -p "$RESULTS_DIR"
echo "$METRICS_JSON" > "$RESULT_PATH"

BENCHMARK_COUNT=$(echo "$METRICS_JSON" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)["benchmarks"]))')
echo "Saved $BENCHMARK_COUNT benchmarks to benchmarks/${RESULT_NAME}.json"
echo ""

# ---------- Compare (if requested) ----------

if [[ -n "$COMPARE_FILE" ]]; then
    # Resolve the comparison reference to a file path
    if [[ "$COMPARE_FILE" == "latest" ]]; then
        # Most recent result file, excluding current run
        COMPARE_FILE=$(ls -t "$RESULTS_DIR"/*.json 2>/dev/null | grep -v "$RESULT_NAME" | head -1 || true)
        if [[ -z "$COMPARE_FILE" ]]; then
            echo "No previous benchmark results found for comparison."
            echo "Run benchmarks on a different commit first."
            exit 0
        fi
    elif [[ ! -f "$COMPARE_FILE" ]]; then
        # Not a file path — treat as a git hash and search for matching result
        HASH_QUERY="$COMPARE_FILE"
        COMPARE_FILE=$(ls "$RESULTS_DIR"/*-"${HASH_QUERY}".json 2>/dev/null | head -1 || true)
        if [[ -z "$COMPARE_FILE" ]]; then
            # Try partial match
            COMPARE_FILE=$(ls "$RESULTS_DIR"/*-"${HASH_QUERY}"*.json 2>/dev/null | head -1 || true)
        fi
        if [[ -z "$COMPARE_FILE" ]]; then
            echo "Error: no benchmark result found for hash '$HASH_QUERY'"
            echo ""
            echo "Available results:"
            ls "$RESULTS_DIR"/*.json 2>/dev/null | while read -r f; do
                echo "  $(basename "$f")"
            done
            exit 1
        fi
    fi

    if [[ ! -f "$COMPARE_FILE" ]]; then
        echo "Error: comparison file not found: $COMPARE_FILE"
        exit 1
    fi

    echo "Comparing against: $(basename "$COMPARE_FILE")"
    echo ""

    python3 - "$COMPARE_FILE" "$RESULT_PATH" <<'COMPARE_SCRIPT'
import json, sys

with open(sys.argv[1]) as f:
    baseline = json.load(f)
with open(sys.argv[2]) as f:
    current = json.load(f)

# ---------- GitHub-flavored markdown comparison ----------

b_commit = baseline["commit"]
b_date = baseline["date"]
c_commit = current["commit"]
c_date = current["date"]

all_tests = sorted(set(list(baseline["benchmarks"]) + list(current["benchmarks"])))

# Key metrics to show (most actionable for performance review)
key_metrics = [
    ("Clock Monotonic Time", "Clock", "s"),
    ("CPU Time", "CPU", "s"),
    ("Memory Peak Physical", "Mem Peak", "kB"),
]

# Collect rows and stats
rows = []
improved = 0
regressed = 0
stable = 0

for test_name in all_tests:
    b_metrics = baseline["benchmarks"].get(test_name, {})
    c_metrics = current["benchmarks"].get(test_name, {})
    if not b_metrics and not c_metrics:
        continue

    # Clean up test name for display
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

            # Format values for readability
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

            # Determine indicator
            if abs(pct) < 2:
                indicator = ""
                stable += 1
            elif pct < -5:
                indicator = " :white_check_mark:"
                improved += 1
            elif pct < 0:
                indicator = " :small_blue_diamond:"
                improved += 1
            elif pct > 10:
                indicator = " :rotating_light:"
                regressed += 1
            elif pct > 5:
                indicator = " :warning:"
                regressed += 1
            else:
                indicator = ""
                stable += 1

            sign = "+" if pct > 0 else ""
            row["cells"].append(f"{c_str} ({sign}{pct:.1f}%){indicator}")
        elif c_avg > 0:
            row["cells"].append(f"{c_avg:.3f} (new)")
        else:
            row["cells"].append("--")

    rows.append(row)

# ---------- Output ----------

print(f"## Benchmark Comparison")
print()
print(f"`{b_commit}` ({b_date}) → `{c_commit}` ({c_date})")
print()

# Summary line
parts = []
if improved > 0:
    parts.append(f"**{improved}** improved")
if regressed > 0:
    parts.append(f"**{regressed}** regressed")
if stable > 0:
    parts.append(f"**{stable}** stable")
print(" · ".join(parts))
print()

# Legend
print("> :rotating_light: >10% regression · :warning: >5% regression · :small_blue_diamond: improvement · :white_check_mark: >5% improvement · _blank = within ±2%_")
print()

# Table header
header_labels = [m[1] for m in key_metrics]
print("| Benchmark | " + " | ".join(header_labels) + " |")
print("|:--|" + "|".join(["--:" for _ in key_metrics]) + "|")

# Table rows
for row in rows:
    print(f"| **{row['name']}** | " + " | ".join(row["cells"]) + " |")

print()
COMPARE_SCRIPT
fi
