#!/usr/bin/env bash
# Cycles through the wallpaper folder in order (wrapping: last→first, first→last).
# Re-scans the folder on every call → newly added images join the rotation automatically.
#
# Even on fast repeated presses, each press advances EXACTLY one step:
#   • the critical section (read current → compute target → set image) is SERIALIZED with flock
#     → two instances won't compute the same step and collide; the image changes instantly (awww ~260ms).
#   • the heavy palette generation (matugen ~1.1s) runs in the background, DEBOUNCED + with its own lock
#     → when cycling fast it runs once, only for the LAST wallpaper (no flicker/collision).
#
# Usage: wallpaper-cycle.sh next | prev
set -euo pipefail

dir="$HOME/Pictures/Wallpapers"
op="${1:-next}"
cache="$HOME/.cache"
lock="$cache/wallpaper-cycle.lock"        # step serialization
mlock="$cache/wallpaper-matugen.lock"     # matugen serialization (no overlap)
pending="$cache/wallpaper-pending"         # latest target (for debounce)
mkdir -p "$cache"

# ---------------- critical section (serialized, fast) ----------------
exec 9>"$lock"
flock 9

mapfile -t imgs < <(find "$dir" -maxdepth 1 -type f \
    \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' \) | sort)
n=${#imgs[@]}
[ "$n" -gt 0 ] || { echo "no wallpaper: $dir" >&2; exit 1; }

cur="$(awww query 2>/dev/null | grep -oP 'image: \K.*' | head -1 || true)"
idx=-1
for i in "${!imgs[@]}"; do
    [ "${imgs[$i]}" = "$cur" ] && { idx=$i; break; }
done
case "$op" in
    prev) step=-1 ;;
    next) step=1 ;;
    *)    echo "usage: wallpaper-cycle.sh next|prev" >&2; exit 1 ;;
esac

# Find the next VALID image + set it IMMEDIATELY. If awww can't decode an image
# (corrupt/partial PNG) SKIP it → a single bad file won't lock up cycling.
# (idx=-1 at start: next→first, prev→last.)
target=""
for _ in $(seq 1 "$n"); do
    idx=$(( (idx + step + n) % n ))
    cand="${imgs[$idx]}"
    if awww img "$cand" --transition-type fade --transition-duration 1 2>/dev/null \
       || awww img "$cand" 2>/dev/null; then
        target="$cand"; break
    fi
    echo "skipped (could not decode): $cand" >&2
done
[ -n "$target" ] || { echo "no valid wallpaper found: $dir" >&2; exit 1; }
printf '%s' "$target" > "$pending"

# cache the active wallpaper: path + copy → wallpaper.sh --restore brings it back at startup
printf '%s' "$target" > "$HOME/.cache/active-wallpaper-src"
rm -f "$HOME"/.cache/active-wallpaper.*
cp -f "$target" "$HOME/.cache/active-wallpaper.${target##*.}" 2>/dev/null || true
flock -u 9

# ---------------- palette (background, debounce + serialization) ----------------
# Wait 0.3s; if a newer press arrives in that window "pending" changes and this run cancels itself.
# The matugen lock prevents overlap; once acquired, re-check → only the most recent target runs.
setsid -f bash -c '
    sleep 0.3
    [ "$(cat "$1" 2>/dev/null)" = "$2" ] || exit 0
    exec 8>"$3"; flock 8
    [ "$(cat "$1" 2>/dev/null)" = "$2" ] || exit 0
    matugen image "$2" --mode dark --prefer saturation >/dev/null 2>&1
' _ "$pending" "$target" "$mlock" >/dev/null 2>&1
