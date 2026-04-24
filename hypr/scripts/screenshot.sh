#!/bin/bash
# Screenshot — area (default) veya full mode.
# Dosyaya kaydeder + panoya kopyalar + notification.
# Canlı path: ~/.config/hypr/scripts/screenshot-area.sh (symlink)

set -eu

MODE="${1:-area}"          # area | full

SCREENSHOT_DIR="$HOME/Pictures/Screenshots"
mkdir -p "$SCREENSHOT_DIR"
FILE="$SCREENSHOT_DIR/$(date +%Y-%m-%d_%H%M%S).png"

if [ "$MODE" = "full" ]; then
    # Full screen — no geometry.
    grim - | tee "$FILE" | wl-copy --type image/png
    LABEL="Full screen"
else
    # Area select — slurp overlay colors from palette.sh.
    PAL="$HOME/.config/palette/palette.sh"
    # shellcheck disable=SC1090
    [ -f "$PAL" ] && . "$PAL"
    ACCENT="${P_PRIMARY:-#88c0d0}"
    ACCENT="${ACCENT#\#}"

    GEO=$(slurp \
        -b "00000080" \
        -c "${ACCENT}FF" \
        -s "${ACCENT}33" \
        -w 2) || exit 0

    grim -g "$GEO" - | tee "$FILE" | wl-copy --type image/png
    LABEL="Area"
fi

notify-send -a "Screenshot" -i camera-photo \
    "$LABEL — copied to clipboard" \
    "$(basename "$FILE")"
