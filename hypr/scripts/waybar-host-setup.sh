#!/bin/bash
# waybar-host-setup.sh
# Waybar config.jsonc'i host'a göre render eder:
#   - laptop (battery var) → battery + bluetooth + network aktif
#   - desktop (battery yok) → sadece ethernet, bt/battery modülü yok
# config.jsonc __MODULES_RIGHT__ placeholder'ı içerir, burada doldurulur.
#
# Hyprland exec-once ile waybar'dan ÖNCE çalışır.

set -eu

SRC="$HOME/Claude/dotfiles/waybar/config.jsonc"
DEST="$HOME/.config/waybar/config.jsonc"

# Battery yolunda bir dizi var mı? → laptop
if ls /sys/class/power_supply/BAT* >/dev/null 2>&1; then
    MODULES='["mpris","battery","clock"]'
    HOST="laptop"
else
    MODULES='["mpris","clock"]'
    HOST="desktop"
fi

mkdir -p "$(dirname "$DEST")"
# sed ile placeholder'ı değiştir
sed "s|__MODULES_RIGHT__|$MODULES|" "$SRC" > "$DEST"

echo "waybar config rendered for $HOST"
