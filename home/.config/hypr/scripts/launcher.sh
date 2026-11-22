#!/usr/bin/env bash
# ╭────────────────────────────────────────────────────────────╮
# │  TUI application launcher                                    │
# │  fzf over .desktop entries; opens the choice via gtk-launch. │
# │  Invoked by Super+Space inside  kitty --class launcher.      │
# │                                                              │
# │  Açılışta sadece kategoriler (kapalı, ▸). Enter/tık ile      │
# │  kategori açılır (▾), başka kategori açılınca önceki kapanır.│
# │  Harf yazınca → tüm uygulamalarda düz arama (adlarda).       │
# ╰────────────────────────────────────────────────────────────╯
set -euo pipefail

US=$'\x1f'   # fields: display <US> tag <US> key   (key: @N = category N, else desktop-id)
SELF=$(readlink -f "$0")

# ── fzf callbacks (re-invoked by fzf, state lives in $LAUNCHER_TMP) ──────────
if [ "${1:-}" = "--act" ]; then          # enter / click on a row:  --act <key>
    T=$LAUNCHER_TMP; key=${2:-}
    case $key in
        @*) n=${key#@}
            if [ "$(cat "$T/open")" = "$n" ]; then echo 0 > "$T/open"; else echo "$n" > "$T/open"; fi
            echo "reload-sync(cat '$T/view_$(cat "$T/open")')+pos($n)" ;;
        "") echo ignore ;;
        *)  echo accept ;;
    esac
    exit 0
fi
if [ "${1:-}" = "--change" ]; then       # query changed
    T=$LAUNCHER_TMP
    if [ -z "${FZF_QUERY:-}" ]; then
        o=$(cat "$T/open"); echo "reload-sync(cat '$T/view_$o')+pos($([ "$o" = 0 ] && echo 1 || echo "$o"))"
    else
        echo "reload-sync(cat '$T/flat')"
    fi
    exit 0
fi

dirs=(
    "$HOME/.local/share/applications"
    /usr/share/applications
    /usr/local/share/applications
    "$HOME/.local/share/flatpak/exports/share/applications"
    /var/lib/flatpak/exports/share/applications
)

# Kategori tablosu: sıra = ekrandaki sıra.  ad <TAB> Nerd Font ikonu
CATS=(
    $'İnternet\t'
    $'İletişim\t'
    $'Araba\t'
    $'Geliştirme\t'
    $'Grafik & Video\t'
    $'Müzik\t'
    $'Oyun\t'
    $'Ofis\t'
    $'Kimlik & e-Devlet\t'
    $'Sistem\t'
    $'Araçlar\t'
    $'Diğer\t'
)

# Emit "Category <US> Display Name <US> desktop-id" per visible .desktop.
# First pick a SINGLE file per id (user dir first → its override wins), then inspect that file.
# This way a NoDisplay=true override in ~/.local/share actually hides the system entry.
collect() {
    local d f id
    declare -A pick
    for d in "${dirs[@]}"; do
        [ -d "$d" ] || continue
        for f in "$d"/*.desktop; do
            [ -e "$f" ] || continue
            id=$(basename "${f%.desktop}")
            [ -n "${pick[$id]:-}" ] && continue   # a higher-priority dir already won
            pick[$id]=$f
        done
    done
    for id in "${!pick[@]}"; do
        awk -v id="$id" -v US="$US" '
            /^\[/                   { de = ($0 == "[Desktop Entry]") }
            de && /^Name=/ && name==""  { sub(/^Name=/, ""); name=$0 }
            de && /^NoDisplay=true/  { skip=1 }
            de && /^Hidden=true/     { skip=1 }
            de && /^Type=/           { sub(/^Type=/, ""); type=$0 }
            de && /^Categories=/ && cats=="" { sub(/^Categories=/, ""); cats=";" $0 ";" }
            function has(c) { return index(cats, ";" c ";") > 0 }
            END {
                if (name == "" || skip || (type != "" && type != "Application")) exit
                n = tolower(name)
                # elle eşlenenler önce, sonra XDG kategorileri (ilk eşleşen kazanır)
                if      (n ~ /bmw|carplay|e-sys|ista|mgu/ || id ~ /^(esys|mgu-|carplay)/) g="Araba"
                else if (id ~ /^(edevlet|hotp-pin-qr)/ || n ~ /e-devlet|e-imza/)       g="Kimlik & e-Devlet"
                else if (id == "com.anthropic.Claude")                                  g="Geliştirme"
                else if (has("Game"))                                                   g="Oyun"
                else if (has("Settings") || has("DesktopSettings"))                     g="Sistem"
                else if (has("InstantMessaging") || has("Chat") || has("Email") || has("Telephony")) g="İletişim"
                else if (has("WebBrowser") || has("Network"))                           g="İnternet"
                else if (has("Development") || has("IDE"))                              g="Geliştirme"
                else if (has("Viewer"))                                                 g="Araçlar"
                else if (has("Graphics"))                                               g="Grafik & Video"
                else if (has("Video") || has("Player") || has("TV"))                    g="Grafik & Video"
                else if (has("Audio") || has("Music"))                                  g="Müzik"
                else if (has("AudioVideo"))                                             g="Grafik & Video"
                else if (has("Office"))                                                 g="Ofis"
                else if (has("TerminalEmulator") || has("FileManager") || has("System") || has("Monitor") || has("Security")) g="Sistem"
                else if (has("Utility") || has("Education") || has("Science"))          g="Araçlar"
                else                                                                    g="Diğer"
                printf "%s%s%s%s%s\n", g, US, name, US, id
            }
        ' "${pick[$id]}"
    done
}

T=$(mktemp -d "${XDG_RUNTIME_DIR:-/tmp}/launcher.XXXXXX")
trap 'rm -rf "$T"' EXIT
export LAUNCHER_TMP=$T
echo 0 > "$T/open"

collect > "$T/all"

ACC=$'\e[1;36m'; DIM=$'\e[2m'; R=$'\e[0m'
W=24   # kategori adı sütun genişliği (üçgenler hizalı dursun)

# Sadece uygulaması olan kategoriler; i = ekrandaki sıra (pos() ile aynı)
names=(); icons=(); apps=()
for c in "${CATS[@]}"; do
    name=${c%%$'\t'*}; icon=${c#*$'\t'}
    list=$(awk -F "$US" -v g="$name" '$1 == g { print $2 "\x1f" $3 }' "$T/all" | sort -f)
    [ -n "$list" ] || continue
    names+=("$name"); icons+=("$icon"); apps+=("$list")
done

# view_0: hepsi kapalı;  view_i: i. kategori açık
for open in $(seq 0 "${#names[@]}"); do
    for i in "${!names[@]}"; do
        n=$((i + 1))
        arrow="▸"; [ "$n" = "$open" ] && arrow="▾"
        pad=$(( W - ${#names[$i]} )); ((pad < 1)) && pad=1
        printf '%s%s%s  %s%*s%s%s%s@%s\n' "$ACC" "${icons[$i]}" "$R" "${names[$i]}" "$pad" "" "$arrow" "$US" "$US" "$n"
        if [ "$n" = "$open" ]; then
            while IFS="$US" read -r an aid; do
                printf '     %s%s%s%s\n' "$an" "$US" "$US" "$aid"
            done <<< "${apps[$i]}"
        fi
    done > "$T/view_$open"
done

# flat (arama modu): ad + soluk kategori etiketi (etiket aranmaz: --nth=1)
awk -F "$US" -v US="$US" -v D="$DIM" -v R="$R" '
    { printf "%s%s%s· %s%s%s%s\n", $2, US, D, $1, R, US, $3 }
' "$T/all" | sort -f > "$T/flat"

sel=$(fzf --ansi --delimiter="$US" --with-nth=1,2 --nth=1 \
          --prompt="run ❯ " --pointer="▶" --layout=reverse \
          --height=100% --border=none --info=hidden \
          --cycle --tiebreak=begin,length \
          --bind "change:transform:bash '$SELF' --change" \
          --bind "enter:transform:bash '$SELF' --act {3}" \
          --bind "left-click:transform:bash '$SELF' --act {3}" \
          < "$T/view_0") || exit 0

id=${sel##*"$US"}
# setsid -f: keep the app alive after kitty closes (fully detach from the session)
[[ -n "$id" && $id != @* ]] && setsid -f gtk-launch "$id" >/dev/null 2>&1
