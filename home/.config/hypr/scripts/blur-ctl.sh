#!/usr/bin/env bash
# Cycle or set Hyprland blur mode (no | hybrid | full) and level (0 | az | orta | cok),
# persist into hyprland.lua + gtk-4.0/blur-mode.css, reload Hyprland, and show eww OSD.
set -euo pipefail

HYPRCONF="@HOME@/.config/hypr/hyprland.lua"
GTK_BLUR="@HOME@/.config/gtk-4.0/blur-mode.css"
GENF="$HOME/.cache/osd-gen"

get_var() {
    sed -n "s/^local $1 = \"\([^\"]*\)\".*/\1/p" "$HYPRCONF" | head -1
}

write_gtk_blur() {
    local mode=$1
    mkdir -p "$(dirname "$GTK_BLUR")"
    if [ "$mode" = full ]; then
        cat > "$GTK_BLUR" <<'CSS'
/* full blur mode: 0.86 opacity on GTK4/libadwaita named colors */
@define-color window_bg_color alpha(@gtk_blur_bg, 0.86);
@define-color view_bg_color alpha(@gtk_blur_bg, 0.86);
@define-color sidebar_bg_color alpha(@gtk_blur_sidebar, 0.86);
@define-color headerbar_bg_color alpha(@gtk_blur_sidebar, 0.86);
@define-color headerbar_backdrop_color alpha(@gtk_blur_bg, 0.86);
@define-color sidebar_backdrop_color alpha(@gtk_blur_bg, 0.86);
CSS
    else
        printf '/* %s blur mode: opaque GTK4 surfaces */\n' "$mode" > "$GTK_BLUR"
    fi
}

apply_lua() {
    local var=$1 val=$2 mode_for_sync=${3-}
    local backup out opac=""
    if [ "$var" = BLUR_MODE ]; then
        [ "$val" = full ] && opac="0.86" || opac="1.0"
    fi

    backup=$(mktemp) || return 1
    cp "$HYPRCONF" "$backup"

    python3 - "$HYPRCONF" "$var" "$val" "$opac" <<'PY'
import re, sys
path, var, val, opac = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
text = open(path, encoding="utf-8").read()
text, n = re.subn(
    rf'^(local {re.escape(var)} = )"[^"]*"',
    rf'\1"{val}"',
    text,
    count=1,
    flags=re.M,
)
if n == 0:
    sys.exit(1)
if opac:
    start, end = "-- >>> settings:look >>>", "-- <<< settings:look <<<"
    pat = re.compile(re.escape(start) + r".*?" + re.escape(end), re.S)
    m = pat.search(text)
    if m:
        blk = re.sub(r'(inactive_opacity\s*=\s*)[0-9.]+', rf'\g<1>{opac}', m.group(0))
        text = text[:m.start()] + blk + text[m.end():]
open(path, "w", encoding="utf-8").write(text)
PY

    if command -v hyprctl >/dev/null 2>&1 && hyprctl version >/dev/null 2>&1; then
        out=$(hyprctl reload 2>&1)
        if printf '%s' "$out" | grep -qiE 'error|invalid|failed'; then
            cp "$backup" "$HYPRCONF"
            hyprctl reload >/dev/null 2>&1 || true
            rm -f "$backup"
            echo "blur-ctl: hyprland rejected change: $out" >&2
            return 1
        fi
    fi
    rm -f "$backup"
    if [ "$var" = BLUR_MODE ]; then
        write_gtk_blur "$val"
        local kitty_opac="0.75"
        [ "$val" = no ] && kitty_opac="1.0"
        if [ -f "$HOME/.config/kitty/kitty.conf" ]; then
            sed -i "s/^background_opacity[[:space:]]\+[0-9.]\+/background_opacity         $kitty_opac/" "$HOME/.config/kitty/kitty.conf"
            pkill -USR1 kitty 2>/dev/null || true
        fi
    fi
    return 0
}

show_osd() {
    local icon=$1 val=$2 text=$3
    eww active-windows 2>/dev/null | grep -q 'osd' || eww open osd >/dev/null 2>&1 || true
    eww update osd_icon="$icon" osd_val="$val" osd_text="$text" osd_boost=false >/dev/null 2>&1 || true
    local gen=$(( $(cat "$GENF" 2>/dev/null || echo 0) + 1 ))
    echo "$gen" > "$GENF"
    setsid -f bash -c 'sleep 1.1; [ "$(cat "$1" 2>/dev/null)" = "$2" ] && eww close osd >/dev/null 2>&1' \
        _ "$GENF" "$gen"
}

osd_for_mode() {
    case "$1" in
        no)     show_osd "󰂵" 0   "No blur" ;;
        hybrid) show_osd "󰂷" 50  "Hybrid blur" ;;
        full)   show_osd "󰂸" 100 "Full blur" ;;
    esac
}

osd_for_level() {
    case "$1" in
        0)    show_osd "󰂵" 0   "Blur: 0" ;;
        az)   show_osd "󰂷" 33  "Blur: Az" ;;
        orta) show_osd "󰂷" 66  "Blur: Orta" ;;
        cok)  show_osd "󰂸" 100 "Blur: Çok" ;;
    esac
}

cmd=${1:-}
case "$cmd" in
    get-mode)  get_var BLUR_MODE ;;
    get-level) get_var BLUR_LEVEL ;;
    set-mode)
        mode=${2:-}
        case "$mode" in no|hybrid|full) ;; *) exit 1 ;; esac
        apply_lua BLUR_MODE "$mode"
        ;;
    cycle-mode)
        cur=$(get_var BLUR_MODE)
        case "$cur" in
            no)     next="hybrid" ;;
            hybrid) next="full" ;;
            *)      next="no" ;;
        esac
        apply_lua BLUR_MODE "$next"
        osd_for_mode "$next"
        ;;
    set-level)
        lvl=${2:-}
        case "$lvl" in 0|az|orta|cok) ;; *) exit 1 ;; esac
        apply_lua BLUR_LEVEL "$lvl"
        ;;
    cycle-level)
        cur=$(get_var BLUR_LEVEL)
        case "$cur" in
            0)    next="az" ;;
            az)   next="orta" ;;
            orta) next="cok" ;;
            *)    next="0" ;;
        esac
        apply_lua BLUR_LEVEL "$next"
        osd_for_level "$next"
        ;;
    *)
        echo "usage: blur-ctl.sh get-mode|get-level|set-mode <no|hybrid|full>|cycle-mode|set-level <0|az|orta|cok>|cycle-level" >&2
        exit 1
        ;;
esac
