#!/usr/bin/env bash
# ╭──────────────────────────────────────────────────────────────────────╮
# │  Appearance  —  wallpaper (drives the matugen palette), GTK theme,    │
# │  cursor and fonts. Window borders/gaps live under Hyprland.           │
# ╰──────────────────────────────────────────────────────────────────────╯
set -u
source @HOME@/.config/hypr/scripts/settings-lib.sh

WALLDIR=@HOME@/Pictures/Wallpapers
IFACE=org.gnome.desktop.interface

gs()     { gsettings get "$IFACE" "$1" 2>/dev/null | tr -d "'"; }
gs_set() { gsettings set "$IFACE" "$1" "$2" 2>/dev/null; }

current_wallpaper() {
    cat @HOME@/.cache/active-wallpaper-src 2>/dev/null \
        || ls @HOME@/.cache/active-wallpaper.* 2>/dev/null | head -1
}

pick_wallpaper() {
    local rows=() f sel
    [ -d "$WALLDIR" ] || { clear; err "$WALLDIR does not exist"; pause; return; }
    while IFS= read -r f; do
        rows+=("$(printf '%s%s󰸉  %s' "$f" "$US" "$(basename "$f")")")
    done < <(find "$WALLDIR" -maxdepth 1 -type f \
                  \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' \) | sort)
    [ ${#rows[@]} -eq 0 ] && { clear; err "no images in $WALLDIR"; pause; return; }
    sel=$(pick "  Wallpaper ❯ " "Enter: apply (the palette follows)   ·   Esc: back" "${rows[@]}")
    [ -z "$sel" ] && return
    clear; title "Wallpaper"; say "applying $(basename "$sel")…"
    "$SCRIPTS/wallpaper.sh" "$sel" >/dev/null 2>&1 && ok "applied — palette regenerated" || err "failed"
    pause
}

theme_pick() {                       # theme_pick KEY  DIR...
    local key=$1; shift
    local rows=() d n sel
    for d in "$@"; do
        [ -d "$d" ] || continue
        while IFS= read -r n; do rows+=("$(printf '%s%s󰸌  %s' "$n" "$US" "$n")"); done \
            < <(find "$d" -maxdepth 1 -mindepth 1 -type d -printf '%f\n' 2>/dev/null)
    done
    mapfile -t rows < <(printf '%s\n' "${rows[@]}" | sort -u -t"$US" -k1,1)
    [ ${#rows[@]} -eq 0 ] && { clear; err "nothing installed for $key"; pause; return; }
    sel=$(pick "  ${key} ❯ " "current: $(gs "$key")" "${rows[@]}")
    [ -n "$sel" ] && { gs_set "$key" "$sel"; clear; title "Appearance"; ok "$key: $sel"; pause; }
}

font_pick() {
    local sel
    sel=$(fc-list : family 2>/dev/null | tr ',' '\n' | sort -u | grep -v '^$' \
          | choose "  Font family ❯ " "current: $(gs font-name)")
    [ -z "$sel" ] && return
    clear; title "Font"
    ask "Size" "$(gs font-name | awk '{print $NF}')" || return
    gs_set font-name "$sel $ANSWER"
    ok "font: $sel $ANSWER"; pause
}

while true; do
    choice=$(pick "  Appearance  " "$HINT" \
        "$(item wall   "󰸉" "Wallpaper"          "$(basename "$(current_wallpaper 2>/dev/null)" 2>/dev/null)")" \
        "$(item next   "󰒭" "Next wallpaper"     "Super + .")" \
        "$(item prev   "󰒮" "Previous wallpaper" "Super + Shift + .")" \
        "$(item repal  "󰏘" "Regenerate palette" "matugen")" \
        "$(sep)" \
        "$(item scheme "󰔎" "Color scheme"       "$(gs color-scheme)")" \
        "$(item gtk    "󰸌" "GTK theme"          "$(gs gtk-theme)")" \
        "$(item icons  "󰀻" "Icon theme"         "$(gs icon-theme)")" \
        "$(item cursor "󰇀" "Cursor theme"       "$(gs cursor-theme)  $(gs cursor-size)px")" \
        "$(item font   "󰛖" "Interface font"     "$(gs font-name)")" \
        "$(sep)" \
        "$(item hypr   "󰖯" "Borders, gaps, rounding" "Hyprland")" \
        "$(r back "󰌍  Back")")
    clear
    case "$choice" in
        wall)   pick_wallpaper ;;
        next)   "$SCRIPTS/wallpaper-cycle.sh" next >/dev/null 2>&1 ;;
        prev)   "$SCRIPTS/wallpaper-cycle.sh" prev >/dev/null 2>&1 ;;
        repal)  title "Palette"; w=$(current_wallpaper)
                [ -n "$w" ] && { "$SCRIPTS/wallpaper.sh" "$w" >/dev/null 2>&1 && ok "palette regenerated"; } \
                            || err "no active wallpaper"
                pause ;;
        scheme) s=$(choose "  Color scheme ❯ " "$HINT" prefer-dark prefer-light default) \
                    && { gs_set color-scheme "$s"; title "Appearance"; ok "color-scheme: $s"; pause; } ;;
        gtk)    theme_pick gtk-theme  /usr/share/themes "$HOME/.themes" "$HOME/.local/share/themes" ;;
        icons)  theme_pick icon-theme /usr/share/icons  "$HOME/.icons"  "$HOME/.local/share/icons" ;;
        cursor) theme_pick cursor-theme /usr/share/icons "$HOME/.icons" "$HOME/.local/share/icons"
                title "Cursor size"; ask "Size in px" "$(gs cursor-size)" \
                    && gsettings set "$IFACE" cursor-size "$ANSWER"; pause ;;
        font)   font_pick ;;
        hypr)   "$SCRIPTS/hyprland-settings.sh" ;;
        -)      ;;
        back|'') break ;;
    esac
done
