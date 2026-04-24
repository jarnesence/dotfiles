#!/bin/bash
# Live wallpaper launcher. Reads the current video from a pointer file so the
# cycler can change it without touching this script, and merges a per-video
# .opts sidecar (e.g. 4k-wallpaper.opts for the zoom/crop on that specific
# video) on top of the global mpv options.
set -u

DIR="${LIVE_WALLPAPER_DIR:-$HOME/Wallpapers}"
POINTER="$HOME/.config/hypr/scripts/live-wallpaper.current"
OUTPUT="${LIVE_WALLPAPER_OUTPUT:-*}"

# Resolve which video to play
if [ -n "${1:-}" ]; then
    VIDEO="$1"
elif [ -n "${LIVE_WALLPAPER:-}" ]; then
    VIDEO="$LIVE_WALLPAPER"
elif [ -s "$POINTER" ] && [ -f "$(cat "$POINTER")" ]; then
    VIDEO="$(cat "$POINTER")"
else
    VIDEO="$(find "$DIR" -maxdepth 1 -type f \( -iname '*.mp4' -o -iname '*.mkv' -o -iname '*.webm' -o -iname '*.mov' \) | sort | head -n1)"
fi

[ -n "$VIDEO" ] && [ -f "$VIDEO" ] || { notify-send "Live wallpaper missing" "$VIDEO" -t 4000; exit 1; }

# Persist the selection
echo "$VIDEO" > "$POINTER"

# Regenerate theme colors from this wallpaper (async so launch isn't blocked).
( "$HOME/.config/hypr/scripts/dynamic-colors.sh" >/dev/null 2>&1 & )

# Global mpv options (no per-video tweaks here)
BASE_OPTS="no-audio loop hwdec=auto vo=gpu-next no-osc no-input-default-bindings video-sync=display-resample interpolation=no"

# Per-video sidecar (<video>.opts) — each line is extra mpv flags
EXTRA_OPTS=""
SIDECAR="${VIDEO%.*}.opts"
if [ -f "$SIDECAR" ]; then
    EXTRA_OPTS="$(grep -v '^\s*#' "$SIDECAR" | tr '\n' ' ')"
fi

pkill -x swaybg 2>/dev/null || true
pkill -x mpvpaper 2>/dev/null || true

setsid -f uwsm-app -- mpvpaper -f -o "$BASE_OPTS $EXTRA_OPTS" "$OUTPUT" "$VIDEO" >/dev/null 2>&1
