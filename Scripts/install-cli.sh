#!/bin/bash
set -euo pipefail

# Install the Present CLI to /usr/local/bin.
#
# Usage:
#   ./Scripts/install-cli.sh          # Build and install
#   ./Scripts/install-cli.sh --from-dmg /path/to/present  # Install pre-built binary

INSTALL_DIR="/usr/local/bin"
BINARY_NAME="present"

if [ "${1:-}" = "--from-dmg" ] && [ -n "${2:-}" ]; then
    SOURCE="$2"
    if [ ! -f "$SOURCE" ]; then
        echo "Error: Binary not found at $SOURCE"
        exit 1
    fi
else
    echo "==> Building CLI (Release)..."
    SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
    PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
    cd "$PROJECT_DIR"
    swift build -c release --product present
    SOURCE="$PROJECT_DIR/.build/release/present"
fi

echo "==> Installing to $INSTALL_DIR/$BINARY_NAME..."
if [ -w "$INSTALL_DIR" ]; then
    cp "$SOURCE" "$INSTALL_DIR/$BINARY_NAME"
else
    echo "    (requires sudo)"
    sudo cp "$SOURCE" "$INSTALL_DIR/$BINARY_NAME"
fi

chmod +x "$INSTALL_DIR/$BINARY_NAME"

echo "==> Installed! Run 'present --help' to get started."
