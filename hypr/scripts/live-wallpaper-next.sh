#!/bin/bash
# Cycle to the next video wallpaper in ~/Wallpapers (sorted alphabetically).
set -u

DIR="${LIVE_WALLPAPER_DIR:-$HOME/Wallpapers}"
POINTER="$HOME/.config/hypr/scripts/live-wallpaper.current"
LAUNCHER="$HOME/.config/hypr/scripts/live-wallpaper.sh"

mapfile -t VIDEOS < <(find "$DIR" -maxdepth 1 -type f \( -iname '*.mp4' -o -iname '*.mkv' -o -iname '*.webm' -o -iname '*.mov' \) | sort)
[ "${#VIDEOS[@]}" -gt 0 ] || { notify-send "No wallpapers in $DIR" -t 3000; exit 1; }

CURRENT="$([ -s "$POINTER" ] && cat "$POINTER" || echo '')"
NEXT=""
for i in "${!VIDEOS[@]}"; do
    if [ "${VIDEOS[$i]}" = "$CURRENT" ]; then
        NEXT="${VIDEOS[$(( (i + 1) % ${#VIDEOS[@]} ))]}"
        break
    fi
done
[ -n "$NEXT" ] || NEXT="${VIDEOS[0]}"

exec "$LAUNCHER" "$NEXT"
