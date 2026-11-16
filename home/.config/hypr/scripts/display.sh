#!/usr/bin/env bash
# ╭──────────────────────────────────────────────────────────────────────╮
# │  Display  —  monitors through hyprctl, backlight through brightnessctl│
# │  Changes apply live; "Save layout" writes them into hyprland.lua.     │
# ╰──────────────────────────────────────────────────────────────────────╯
set -u
source @HOME@/.config/hypr/scripts/settings-lib.sh

mon_names() { hyprctl -j monitors 2>/dev/null | grep '"name"' | cut -d'"' -f4; }
mon_get()   { hyprctl -j monitors 2>/dev/null | python3 -c '
import json,sys
name=sys.argv[1]; key=sys.argv[2]
for m in json.load(sys.stdin):
    if m["name"]==name: print(m.get(key,"")); break' "$1" "$2"; }

mon_summary() {
    hyprctl -j monitors 2>/dev/null | python3 -c '
import json,sys
for m in json.load(sys.stdin):
    print("%s\x1f%dx%d@%.0f  scale %.2f  %s" % (
        m["name"], m["width"], m["height"], m["refreshRate"], m["scale"],
        "VRR" if m.get("vrr") else ""))'
}

brightness() { brightnessctl -m 2>/dev/null | cut -d, -f4; }

# `hyprctl keyword` refuses to touch a Lua config, so monitor rules are
# applied with hl.monitor through hyprctl eval (see hy_monitor in the lib).
apply_monitor() {
    local name=$1 mode=$2 pos=$3 scale=$4
    hy_monitor "output = \"$name\", mode = \"$mode\", position = \"$pos\", scale = $scale"
}

modes_for() {
    hyprctl -j monitors 2>/dev/null | python3 -c '
import json,sys
name=sys.argv[1]
for m in json.load(sys.stdin):
    if m["name"]==name:
        seen=[]
        for s in m.get("availableModes",[]):
            if s not in seen: seen.append(s)
        print("\n".join(seen)); break' "$1"
}

monitor_menu() {
    local name=$1 sel
    while true; do
        local w h rr sc tr vrr dis
        w=$(mon_get "$name" width); h=$(mon_get "$name" height)
        rr=$(mon_get "$name" refreshRate); sc=$(mon_get "$name" scale)
        tr=$(mon_get "$name" transform); vrr=$(mon_get "$name" vrr)
        dis=$(mon_get "$name" disabled)

        sel=$(pick "  $name ❯ " "$HINT" \
            "$(item mode  "󰍹" "Resolution & refresh" "${w}x${h}@${rr%.*}")" \
            "$(item scale "󰘖" "Scale"                "$sc")" \
            "$(item rot   "󰑧" "Rotation"             "$(case $tr in 0) echo normal;; 1) echo 90°;; 2) echo 180°;; 3) echo 270°;; *) echo "$tr";; esac)")" \
            "$(item vrr   "󰓅" "Variable refresh"     "$vrr")" \
            "$(item off   "󰶐" "Disabled"             "$dis")" \
            "$(sep)" \
            "$(r save "󰆓  Save current layout to hyprland.lua")" \
            "$(r back "󰌍  Back")")
        clear
        case "$sel" in
            mode)  m=$(modes_for "$name" | choose "  Mode ❯ " "applies immediately") \
                       && { apply_monitor "$name" "$m" auto "$sc"; title "$name"; ok "mode: $m"; pause; } ;;
            scale) title "$name"; dim "1 = native · 1.333333 = current · fractional scales must divide the pixel size evenly"
                   ask "Scale" "$sc" && { apply_monitor "$name" preferred auto "$ANSWER"
                       [ "$(mon_get "$name" scale)" = "$sc" ] && err "Hyprland kept $sc — that scale does not fit this panel" || ok "scale: $ANSWER"; }
                   pause ;;
            rot)   t=$(choose "  Rotation ❯ " "$HINT" "0  normal" "1  90°" "2  180°" "3  270°") \
                       && { hy_monitor "output = \"$name\", mode = \"preferred\", position = \"auto\", scale = $sc, transform = ${t%% *}"
                            title "$name"; ok "rotation: ${t#* }"; pause; } ;;
            vrr)   v=1; [ "$vrr" = true ] && v=0
                   hy_monitor "output = \"$name\", mode = \"preferred\", position = \"auto\", scale = $sc, vrr = $v"
                   title "$name"; ok "vrr: $v"; pause ;;
            off)   if [ "$dis" = true ]; then hy_monitor "output = \"$name\", mode = \"preferred\", position = \"auto\", scale = $sc"
                   else
                       [ "$(mon_names | wc -l)" -le 1 ] && { title "$name"; err "this is the only display — refusing to disable it"; pause; continue; }
                       confirm "Disable $name" && hy_monitor "output = \"$name\", disabled = true"
                   fi ;;
            save)  save_layout ;;
            back|'') return ;;
        esac
    done
}

# hyprctl reports the scale rounded to two decimals (1.33 for a configured
# 1.333333). Writing that back would hand Hyprland a scale that does not divide
# this panel evenly, so prefer the value already in the config when the two
# agree once rounded.
configured_scale() {
    local name=$1 cfg
    cfg=$(grep -oE "hl\.monitor\(\{[^}]*output *= *\"($name|)\"[^}]*\}" "$HYPRCONF" 2>/dev/null \
          | grep -oE 'scale *= *[0-9.]+' | grep -oE '[0-9.]+' | tail -1)
    [ -n "$cfg" ] && printf '%s' "$cfg"
}

save_layout() {
    clear; title "Save display layout"
    local lines='' name w h rr x y sc cfg
    while IFS=$'\x1f' read -r name w h rr x y sc; do
        cfg=$(configured_scale "$name")
        if [ -n "$cfg" ] && [ "$(printf '%.2f' "$cfg")" = "$(printf '%.2f' "$sc")" ]; then
            sc=$cfg                       # same scale, keep the precise value
        fi
        lines+=$(printf 'hl.monitor({ output = "%s", mode = "%sx%s@%s", position = "%sx%s", scale = %s })\n' \
                 "$name" "$w" "$h" "$rr" "$x" "$y" "$sc")
        lines+=$'\n'
    done < <(hyprctl -j monitors 2>/dev/null | python3 -c '
import json,sys
for m in json.load(sys.stdin):
    print("%s\x1f%d\x1f%d\x1f%.5f\x1f%d\x1f%d\x1f%s" % (
        m["name"], m["width"], m["height"], m["refreshRate"], m["x"], m["y"], m["scale"]))')

    printf '%s\n' "$lines" | sed 's/^/  /'
    dim "scale is taken from the config when it matches, because hyprctl rounds it to 2 decimals"
    confirm "Write this into hyprland.lua" || return
    printf '%s' "$lines" | lua_block monitors
    pause
}

while true; do
    rows=()
    while IFS=$'\x1f' read -r name info; do
        rows+=("$(printf '%s%s󰍹  %-14s \033[2m%s\033[0m' "mon:$name" "$US" "$name" "$info")")
    done < <(mon_summary)
    [ ${#rows[@]} -eq 0 ] && rows=("$(r none "no monitors reported by hyprctl")")

    choice=$(pick "  Display  " "$HINT" \
        "${rows[@]}" \
        "$(sep)" \
        "$(item bright "󰃟" "Brightness"        "$(brightness)")" \
        "$(item bup    "󰃠" "Brightness +10%"   "")" \
        "$(item bdown  "󰃞" "Brightness -10%"   "")" \
        "$(sep)" \
        "$(item wall   "󰸉" "Wallpaper"         "appearance")" \
        "$(item idle   "󰒲" "Screen blank & sleep" "power")" \
        "$(item save   "󰆓" "Save layout to config" "")" \
        "$(r back "󰌍  Back")")

    case "$choice" in
        mon:*)  monitor_menu "${choice#mon:}" ;;
        bright) clear; title "Brightness"; ask "Brightness %" "$(brightness | tr -d %)" \
                    && brightnessctl set "${ANSWER}%" >/dev/null; pause ;;
        bup)    brightnessctl set 10%+ >/dev/null ;;
        bdown)  brightnessctl set 10%- >/dev/null ;;
        wall)   "$SCRIPTS/appearance.sh" ;;
        idle)   "$SCRIPTS/power.sh" ;;
        save)   save_layout ;;
        -|none) ;;
        back|'') break ;;
    esac
done
