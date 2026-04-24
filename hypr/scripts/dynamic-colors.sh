#!/bin/bash
# Regenerate theme colors from the current live-wallpaper video.
# Extracts a representative frame, feeds it to matugen, applies to waybar +
# hyprland borders + theme colors.toml, then reloads affected components.
# Safe to call repeatedly; safe if wallpaper pointer missing (no-op).

set -e

POINTER="$HOME/.config/hypr/scripts/live-wallpaper.current"
FRAME="${XDG_RUNTIME_DIR:-/tmp}/wp-frame.jpg"

[[ -s $POINTER ]] || exit 0
WALL=$(<"$POINTER")
[[ -f $WALL ]] || exit 0

# Sample a frame ~1 second in (avoids the black first frame in most videos).
ffmpeg -y -loglevel error -ss 1 -i "$WALL" -frames:v 1 -q:v 3 "$FRAME"

# Palette üretimi — şema state dosyasından okunur (Super+M ile döndürülür).
#   --prefer less-saturation → kaynak rengin daha sakin versiyonunu seç
#   --lightness-dark -0.3    → dark mode surface'leri daha koyu yap
#   -t <SCHEME>              → palette-scheme-next.sh'ın set ettiği şema
SCHEME_STATE="$HOME/.config/hypr/scripts/palette-scheme.current"
SCHEME="scheme-neutral"
[ -s "$SCHEME_STATE" ] && SCHEME="$(<"$SCHEME_STATE")"
matugen -t "$SCHEME" --prefer less-saturation --lightness-dark -0.3 image "$FRAME" >/dev/null

# matugen yalnızca tek source-of-truth palette dosyasını yazar.
# generate-themes.sh oradan okuyup app-specific config'leri üretir.
"$HOME/.config/hypr/scripts/generate-themes.sh" >/dev/null

# Reload visible components that read the theme files.
if pgrep -x waybar >/dev/null; then
  STATE="${XDG_RUNTIME_DIR:-/tmp}/hypr-mode"
  MODE="flat"; [[ -f $STATE ]] && MODE=$(<"$STATE")
  "$HOME/.config/hypr/scripts/mode-toggle.sh" "$MODE"
fi
hyprctl reload >/dev/null 2>&1 || true

# Optional downstream refreshes — silent if the target script is missing.
# PATH gerekmez; absolute path ile çağırıyoruz.
SD="$HOME/.config/hypr/scripts"
[ -x "$SD/restart-terminal.sh" ] && "$SD/restart-terminal.sh" >/dev/null 2>&1 &
[ -x "$SD/restart-mako.sh"     ] && "$SD/restart-mako.sh"     >/dev/null 2>&1 &
[ -x "$SD/restart-swayosd.sh"  ] && "$SD/restart-swayosd.sh"  >/dev/null 2>&1 &
wait 2>/dev/null || true
