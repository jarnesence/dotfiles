#!/bin/bash
# palette-scheme-next.sh
# Matugen şemaları arasında döner, paleti yeniden üretir, mako bildirim gösterir.
# Keybind: Super + M
set -u

STATE="$HOME/.config/hypr/scripts/palette-scheme.current"

# Cycle order — her Super+M basışında sıradakine geçer.
SCHEMES=(
    scheme-neutral      # pastel, düşük chroma
    scheme-fidelity     # wallpaper hue'suna sadık, yumuşak
    scheme-expressive   # dark ama hue varyasyonlu
    scheme-tonal-spot   # Material You default, dengeli
    scheme-vibrant      # daha doygun, enerjik
    scheme-monochrome   # tek hue, gri ağırlıklı
)

# İnsan-okunur isimler
declare -A LABEL=(
    [scheme-neutral]="Pastel"
    [scheme-fidelity]="Sadık"
    [scheme-expressive]="Ekspresif"
    [scheme-tonal-spot]="Dengeli"
    [scheme-vibrant]="Canlı"
    [scheme-monochrome]="Tek-ton"
)

# Şu anki şemayı oku
CURRENT=""
[ -s "$STATE" ] && CURRENT="$(<"$STATE")"

# Sırada gelecek şema
NEXT=""
for i in "${!SCHEMES[@]}"; do
    if [ "${SCHEMES[$i]}" = "$CURRENT" ]; then
        NEXT="${SCHEMES[$(( (i + 1) % ${#SCHEMES[@]} ))]}"
        break
    fi
done
[ -z "$NEXT" ] && NEXT="${SCHEMES[0]}"

# Kaydet
echo "$NEXT" > "$STATE"

# Paleti yeniden üret (dynamic-colors.sh STATE'i okuyacak)
"$HOME/.config/hypr/scripts/dynamic-colors.sh"

# Kullanıcıya feedback
notify-send -t 2500 -i preferences-color "Palette: ${LABEL[$NEXT]:-$NEXT}" "Şema: $NEXT"
