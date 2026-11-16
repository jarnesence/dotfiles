#!/usr/bin/env bash
# Apply the wallpaper + generate the palette from it + refresh widgets.
# Usage: wallpaper.sh /path/to/image   |   wallpaper.sh --restore
# --restore: re-applies the last cached active wallpaper (used at startup).
#            If the original file is gone, falls back to the cached COPY in
#            ~/.cache → every boot brings back the version from shutdown.
set -u
img="${1:-}"
if [ "$img" = "--restore" ]; then
    src=$(cat "$HOME/.cache/active-wallpaper-src" 2>/dev/null || true)
    if [ -n "$src" ] && [ -f "$src" ]; then
        img="$src"
    else
        img=$(ls "$HOME"/.cache/active-wallpaper.* 2>/dev/null | head -1)
    fi
    # no cache at all -> default
    [ -n "$img" ] && [ -f "$img" ] || img="$HOME/Pictures/Wallpapers/city-horizon-4k-detailed.png"
fi
[ -n "$img" ] && [ -f "$img" ] || { echo "usage: wallpaper.sh <image>|--restore" >&2; exit 1; }

# 0) If the awww (swww) daemon isn't ready, start it and wait until it is.
#    (desktop-init.sh used to do this; the script is now self-sufficient.)
if ! awww query >/dev/null 2>&1; then
    awww-daemon >/dev/null 2>&1 &
    for _ in $(seq 1 30); do awww query >/dev/null 2>&1 && break; sleep 0.1; done
fi

# 1) put it on screen. Boot path uses NO transition → the wallpaper appears the
#    instant the daemon is ready (no 1s fade-in). Cycling (wallpaper-cycle.sh)
#    keeps its own fade; this script is only the startup path.
awww img "$img" --transition-type none 2>/dev/null \
  || awww img "$img" 2>/dev/null

# 1.5) cache the active wallpaper: path + the file itself (survives deletion of the original)
printf '%s' "$img" > "$HOME/.cache/active-wallpaper-src"
rm -f "$HOME"/.cache/active-wallpaper.*
cp -f "$img" "$HOME/.cache/active-wallpaper.${img##*.}" 2>/dev/null || true

# 2) generate the palette from the image → matugen writes ALL targets (hypr/eww/kitty/gtk3/gtk4)
#    and each template's post_hook refreshes the matching app (config.toml).
#    --prefer saturation: auto-picks the most vivid candidate color in a TTY-less environment.
#    Hyprland borders: matugen writes ~/.config/hypr/colors.lua + triggers the 'hyprctl reload'
#    post_hook; hyprland.lua reads that file and applies the borders (reload-safe).
matugen image "$img" --mode dark --prefer saturation >/dev/null 2>&1
