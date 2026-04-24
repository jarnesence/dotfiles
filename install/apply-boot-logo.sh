#!/bin/bash
# apply-boot-logo.sh — kullanıcının verdiği PNG'yi boot menü background'u yapar.
#
# Kullanım:    bash apply-boot-logo.sh <path-to-image.png>
# Varsayılan:  bash apply-boot-logo.sh  →  ~/Downloads/boot-logo.png aranır
#
# Ne yapar:
#   1) PNG'yi /boot/limine-splash.png olarak kopyalar (sudo)
#   2) /boot/limine/limine.conf'a `term_wallpaper:` ekler (yoksa)
#   3) Telif: KULLANICININ SAĞLADIĞI imaj. Üçüncü parti markaların
#      logolarını kopyalamak bu script'in sorumluluğunda değil.

set -eu

SRC="${1:-$HOME/Downloads/boot-logo.png}"
DST="/boot/limine-splash.png"
CFG="/boot/limine/limine.conf"

[ -f "$SRC" ] || { echo "Kaynak yok: $SRC"; echo "İmajı ~/Downloads/boot-logo.png'ye koy."; exit 1; }

# Kopyala
sudo cp "$SRC" "$DST"
sudo chmod 644 "$DST"
echo "Kopyalandı: $DST"

# limine.conf'a wallpaper satırı ekle (idempotent)
if ! sudo grep -q "^term_wallpaper:" "$CFG"; then
    sudo sed -i '1i term_wallpaper: boot():/limine-splash.png\nterm_wallpaper_style: stretched\n' "$CFG"
    echo "limine.conf güncellendi."
else
    echo "limine.conf zaten wallpaper referanslı — sadece PNG yenilendi."
fi

echo
echo "Sonraki boot'ta aktif olacak. Test için: sistemi yeniden başlat."
