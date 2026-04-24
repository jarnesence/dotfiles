#!/bin/bash
# Waybar görünüm modunu state dosyasına yaz ve CSS reload'u tetikle.
# Kullanım: mode-toggle.sh [mode]   (varsayılan: flat)
#
# Bu, orijinal backup'taki aynı isimli script'in yeniden yazılmış minimal
# versiyonudur. Orijinal dosya backup'ta yoktu, mantık dynamic-colors.sh'taki
# çağrıdan çıkarıldı: state file oku, waybar'ı CSS reload yap (SIGUSR2).
set -u

MODE="${1:-flat}"
STATE="${XDG_RUNTIME_DIR:-/tmp}/hypr-mode"
echo "$MODE" > "$STATE"

# Waybar SIGUSR2 → style.css + @import'ları (colors.css dahil) yeniden okur
pkill -SIGUSR2 -x waybar 2>/dev/null || true
