#!/bin/bash
# preview-icons.sh — Render Icon Composer (.icon) files at standard macOS sizes into an HTML preview.
#
# Usage:
#   bash Scripts/preview-icons.sh file1.icon file2.icon ...
#   bash Scripts/preview-icons.sh local-assets/*.icon
#
# Opens the generated HTML file in the default browser when done.

set -euo pipefail

ICTOOL="/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool"

if [[ ! -x "$ICTOOL" ]]; then
  echo "Error: ictool not found. Install Xcode with Icon Composer." >&2
  exit 1
fi

if [[ $# -eq 0 ]]; then
  echo "Usage: $0 <file1.icon> [file2.icon] ..." >&2
  exit 1
fi

# Standard macOS icon sizes (points × scale)
SIZES=(
  "16:1"
  "16:2"
  "32:1"
  "32:2"
  "128:1"
  "128:2"
  "256:1"
  "256:2"
  "512:1"
  "512:2"
)

RENDITIONS=("Default" "Dark")

OUTPUT_DIR=$(mktemp -d)
HTML_FILE="$OUTPUT_DIR/icon-preview.html"

echo "Rendering icons to $OUTPUT_DIR ..."

# Start HTML
cat > "$HTML_FILE" << 'HEADER'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Icon Composer Preview</title>
<style>
  * { margin: 0; padding: 0; box-sizing: border-box; }
  body {
    font-family: -apple-system, BlinkMacSystemFont, "SF Pro", system-ui, sans-serif;
    background: #f5f5f7;
    color: #1d1d1f;
    padding: 40px;
  }
  h1 {
    font-size: 28px;
    font-weight: 600;
    margin-bottom: 8px;
  }
  .subtitle {
    color: #86868b;
    font-size: 14px;
    margin-bottom: 40px;
  }
  .icon-group {
    background: white;
    border-radius: 16px;
    padding: 32px;
    margin-bottom: 32px;
    box-shadow: 0 1px 3px rgba(0,0,0,0.08);
  }
  .icon-group h2 {
    font-size: 20px;
    font-weight: 600;
    margin-bottom: 4px;
  }
  .icon-group .path {
    font-size: 12px;
    color: #86868b;
    font-family: "SF Mono", Menlo, monospace;
    margin-bottom: 24px;
  }
  .rendition-section {
    margin-bottom: 24px;
  }
  .rendition-section:last-child {
    margin-bottom: 0;
  }
  .rendition-label {
    font-size: 13px;
    font-weight: 600;
    color: #6e6e73;
    text-transform: uppercase;
    letter-spacing: 0.5px;
    margin-bottom: 12px;
  }
  .sizes-row {
    display: flex;
    align-items: flex-end;
    gap: 24px;
    flex-wrap: wrap;
    padding: 20px;
    border-radius: 12px;
  }
  .sizes-row.light {
    background: #fafafa;
  }
  .sizes-row.dark {
    background: #1d1d1f;
  }
  .size-cell {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 8px;
  }
  .size-cell img {
    image-rendering: auto;
  }
  .size-label {
    font-size: 11px;
    font-family: "SF Mono", Menlo, monospace;
    text-align: center;
  }
  .light .size-label { color: #86868b; }
  .dark .size-label { color: #98989d; }
  .comparison {
    background: white;
    border-radius: 16px;
    padding: 32px;
    margin-bottom: 32px;
    box-shadow: 0 1px 3px rgba(0,0,0,0.08);
  }
  .comparison h2 {
    font-size: 20px;
    font-weight: 600;
    margin-bottom: 24px;
  }
  .comparison-row {
    display: flex;
    gap: 32px;
    align-items: flex-end;
    flex-wrap: wrap;
    padding: 20px;
    background: #fafafa;
    border-radius: 12px;
  }
  .comparison-cell {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 8px;
  }
  .comparison-cell .name {
    font-size: 12px;
    font-weight: 500;
    color: #1d1d1f;
    max-width: 120px;
    text-align: center;
    word-break: break-word;
  }
</style>
</head>
<body>
<h1>Icon Composer Preview</h1>
HEADER

echo "<p class=\"subtitle\">Generated $(date '+%B %d, %Y at %I:%M %p') — $(echo $# | tr -d ' ') icon(s)</p>" >> "$HTML_FILE"

# Track icon names and 128px paths for comparison section
declare -a ICON_NAMES
declare -a ICON_128_PATHS

for ICON_FILE in "$@"; do
  if [[ ! -d "$ICON_FILE" ]]; then
    echo "Warning: $ICON_FILE not found, skipping." >&2
    continue
  fi

  ICON_NAME=$(basename "$ICON_FILE" .icon)
  ICON_NAMES+=("$ICON_NAME")
  SAFE_NAME=$(echo "$ICON_NAME" | tr ' ' '_' | tr -cd 'A-Za-z0-9_-')
  ICON_DIR="$OUTPUT_DIR/$SAFE_NAME"
  mkdir -p "$ICON_DIR"

  echo "  $ICON_NAME"

  cat >> "$HTML_FILE" << EOF
<div class="icon-group">
  <h2>$ICON_NAME</h2>
  <p class="path">$ICON_FILE</p>
EOF

  for RENDITION in "${RENDITIONS[@]}"; do
    RENDITION_LOWER=$(echo "$RENDITION" | tr '[:upper:]' '[:lower:]')
    BG_CLASS="light"
    if [[ "$RENDITION" == "Dark" ]]; then
      BG_CLASS="dark"
    fi

    cat >> "$HTML_FILE" << EOF
  <div class="rendition-section">
    <div class="rendition-label">$RENDITION</div>
    <div class="sizes-row $BG_CLASS">
EOF

    for SIZE_SPEC in "${SIZES[@]}"; do
      PTS="${SIZE_SPEC%%:*}"
      SCALE="${SIZE_SPEC##*:}"
      PX=$((PTS * SCALE))
      FILENAME="${SAFE_NAME}_${RENDITION_LOWER}_${PTS}pt_${SCALE}x.png"

      "$ICTOOL" "$ICON_FILE" \
        --export-image \
        --output-file "$ICON_DIR/$FILENAME" \
        --platform macOS \
        --rendition "$RENDITION" \
        --width "$PTS" \
        --height "$PTS" \
        --scale "$SCALE" 2>/dev/null || {
          echo "    Warning: Failed to render ${PTS}pt@${SCALE}x $RENDITION" >&2
          continue
        }

      # Track 128pt@1x Default for comparison
      if [[ "$PTS" == "128" && "$SCALE" == "1" && "$RENDITION" == "Default" ]]; then
        ICON_128_PATHS+=("$SAFE_NAME/$FILENAME")
      fi

      # Display at point size (CSS pixels), not pixel size
      DISPLAY_SIZE="$PTS"

      cat >> "$HTML_FILE" << EOF
      <div class="size-cell">
        <img src="$SAFE_NAME/$FILENAME" width="$DISPLAY_SIZE" height="$DISPLAY_SIZE" alt="$ICON_NAME ${PTS}pt@${SCALE}x $RENDITION">
        <span class="size-label">${PTS}pt@${SCALE}x<br>${PX}px</span>
      </div>
EOF
    done

    echo "    </div></div>" >> "$HTML_FILE"
  done

  echo "</div>" >> "$HTML_FILE"
done

# Side-by-side comparison at 128pt
if [[ ${#ICON_NAMES[@]} -gt 1 ]]; then
  cat >> "$HTML_FILE" << 'EOF'
<div class="comparison">
  <h2>Side-by-Side Comparison (128pt)</h2>
  <div class="comparison-row">
EOF

  for i in "${!ICON_NAMES[@]}"; do
    NAME="${ICON_NAMES[$i]}"
    IMG_PATH="${ICON_128_PATHS[$i]}"
    cat >> "$HTML_FILE" << EOF
    <div class="comparison-cell">
      <img src="$IMG_PATH" width="128" height="128" alt="$NAME">
      <span class="name">$NAME</span>
    </div>
EOF
  done

  echo "  </div></div>" >> "$HTML_FILE"
fi

# Close HTML
cat >> "$HTML_FILE" << 'FOOTER'
</body>
</html>
FOOTER

echo ""
echo "Done! Preview: $HTML_FILE"
open "$HTML_FILE"
