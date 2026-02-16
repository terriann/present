#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_DIR"

echo "Building present-cli..."
swift build --product present-cli 2>/dev/null

echo "Generating CLI reference..."
mkdir -p "$PROJECT_DIR/docs"
.build/debug/present-cli --experimental-dump-help \
  | python3 "$SCRIPT_DIR/generate-cli-docs.py" \
  > "$PROJECT_DIR/docs/cli-reference.md"

echo "Generated docs/cli-reference.md"
