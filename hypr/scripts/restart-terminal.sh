#!/bin/bash
# Kitty'ye SIGUSR1 gönder → kitty.conf + include'ları (colors.conf) yeniden okur.
# Açık kitty pencereleri canlı renk değişimi yapar.
pkill -SIGUSR1 -x kitty 2>/dev/null || true
