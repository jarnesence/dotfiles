#!/bin/bash
# apply-plymouth-theme.sh — Plymouth temasını değiştirir ve UKI'yi yeniden build eder.
#
# Kullanım:  bash apply-plymouth-theme.sh <theme-name>
# Örnekler:  spinner, bgrt, fade-in, glow, script, solar, spinfinity, tribar
#
# ASUS Zenbook animasyonu için:
#   1) Custom plymouth theme (örn. plymouth-theme-asus) indir/AUR'dan kur
#   2) ~/Downloads/<theme-name>/ altında .plymouth + resources hazır olsun
#   3) sudo cp -r ~/Downloads/<theme> /usr/share/plymouth/themes/
#   4) bash apply-plymouth-theme.sh <theme>
#
# Varsa ASUS BIOS BGRT logosu kullan: theme = bgrt
# (firmware splash'ını gösterir — BIOS'ta set edilmiş ASUS logosu varsa)

set -eu

THEME="${1:-spinner}"

if [ ! -d "/usr/share/plymouth/themes/$THEME" ]; then
    echo "Hata: /usr/share/plymouth/themes/$THEME bulunamadı."
    echo "Mevcut temalar:"
    ls /usr/share/plymouth/themes/
    exit 1
fi

sudo plymouth-set-default-theme -R "$THEME"
echo "Plymouth default theme: $THEME"
echo "UKI yeniden build edildi. Sonraki boot'ta aktif."
