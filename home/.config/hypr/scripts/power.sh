#!/usr/bin/env bash
# ╭──────────────────────────────────────────────────────────────────────╮
# │  Power & Battery  —  profile, charge limit, idle timings, diagnostics │
# ╰──────────────────────────────────────────────────────────────────────╯
set -u
source @HOME@/.config/hypr/scripts/settings-lib.sh

BAT=/sys/class/power_supply/BAT0
IDLE=@HOME@/.config/hypr/hypridle.conf

bat()      { cat "$BAT/$1" 2>/dev/null; }
profile()  { powerprofilesctl get 2>/dev/null; }
charge_cap() { bat charge_control_end_threshold; }

# Idle timings live in hypridle.conf as `timeout = N` inside listener blocks,
# in file order: dim backlight, screen off, suspend.
idle_timeouts() { grep -oP '^\s*timeout\s*=\s*\K[0-9]+' "$IDLE" 2>/dev/null; }
idle_nth()      { idle_timeouts | sed -n "${1}p"; }

fmt_secs() {
    local s=${1:-0}
    if [ "$s" -ge 60 ]; then printf '%d min' $((s / 60)); else printf '%d s' "$s"; fi
}

set_idle_nth() {                     # set_idle_nth INDEX SECONDS
    local idx=$1 val=$2
    python3 - "$IDLE" "$idx" "$val" <<'PY'
import re, sys
path, idx, val = sys.argv[1], int(sys.argv[2]), sys.argv[3]
lines = open(path, encoding='utf-8').read().splitlines(keepends=True)
n = 0
for i, ln in enumerate(lines):
    if re.match(r'^\s*timeout\s*=', ln):
        n += 1
        if n == idx:
            lines[i] = re.sub(r'(timeout\s*=\s*)\d+', r'\g<1>' + val, ln)
            break
open(path, 'w', encoding='utf-8').writelines(lines)
PY
    pkill -x hypridle >/dev/null 2>&1
    setsid hypridle >/dev/null 2>&1 &
}

idle_menu() {
    local sel
    while true; do
        sel=$(pick "  Screen & sleep ❯ " "hypridle — timers start after the last input" \
            "$(item dim   "󰃞" "Dim the backlight after"  "$(fmt_secs "$(idle_nth 1)")")" \
            "$(item blank "󰶐" "Turn the screen off after" "$(fmt_secs "$(idle_nth 2)")")" \
            "$(item susp  "󰒲" "Suspend after"            "$(fmt_secs "$(idle_nth 3)")")" \
            "$(sep)" \
            "$(item nowoff "󰤄" "Turn the screen off now" "")" \
            "$(item edit  "󰏫" "Edit hypridle.conf"       "")" \
            "$(r back "󰌍  Back")")
        clear
        case "$sel" in
            dim|blank|susp)
                local n=1; [ "$sel" = blank ] && n=2; [ "$sel" = susp ] && n=3
                title "Idle timer"
                ask "Minutes" "$(( $(idle_nth $n) / 60 ))" || continue
                set_idle_nth "$n" "$((ANSWER * 60))"
                ok "set to $ANSWER min — hypridle restarted"; pause ;;
            nowoff)  hyprctl dispatch dpms off >/dev/null 2>&1; return ;;
            edit)    "${EDITOR:-nano}" "$IDLE"; pkill -x hypridle; setsid hypridle >/dev/null 2>&1 & ;;
            back|'') return ;;
        esac
    done
}

battery_info() {
    clear; title "Battery"
    kv "Charge"      "$(bat capacity)%  ($(bat status))"
    kv "Charge limit" "$(charge_cap)%"
    kv "Health"      "$(python3 -c "
try:
    f=int(open('$BAT/charge_full').read()); d=int(open('$BAT/charge_full_design').read())
    print('%.0f%% of design' % (100*f/d))
except Exception: print('unknown')" 2>/dev/null)"
    kv "Cycles"      "$(bat cycle_count)"
    kv "Power draw"  "$(python3 -c "
try: print('%.1f W' % (int(open('$BAT/power_now').read())/1e6))
except Exception: print('n/a')" 2>/dev/null)"
    kv "Technology"  "$(bat technology)"
    printf '\n'
    upower -i /org/freedesktop/UPower/devices/battery_BAT0 2>/dev/null \
        | grep -E 'time to|state|percentage' | sed 's/^ */  /'
    pause
}

while true; do
    choice=$(pick "  Power & Battery  " "$HINT" \
        "$(item prof  "󰓅" "Power profile"        "$(profile)")" \
        "$(item cap   "󰂅" "Charge limit"         "$(charge_cap)%")" \
        "$(item idle  "󰒲" "Screen & sleep timers" "$(fmt_secs "$(idle_nth 2)") to screen off")" \
        "$(sep)" \
        "$(item info  "󰁹" "Battery details"      "$(bat capacity)%  $(bat status)")" \
        "$(item top   "󰍛" "Resource monitor"     "btop")" \
        "$(item ptop  "󱐋" "Power consumption"    "powertop")" \
        "$(sep)" \
        "$(item susp  "󰤄" "Suspend now"          "")" \
        "$(item pmenu "󰐥" "Power menu"           "shut down, restart…")" \
        "$(r back "󰌍  Back")")
    clear
    case "$choice" in
        prof) p=$(powerprofilesctl list 2>/dev/null | sed -n 's/^[ *]*\([a-z-]\+\):$/\1/p' \
                  | choose "  Power profile ❯ " "current: $(profile)") \
              && { powerprofilesctl set "$p"; title "Power"; ok "profile: $p"; pause; } ;;
        cap)  title "Charge limit"
              dim "stopping around 80% is much gentler on the cell than charging to 100%"
              ask "Stop charging at %" "$(charge_cap)" || continue
              if printf '%s' "$ANSWER" | sudo tee "$BAT/charge_control_end_threshold" >/dev/null 2>&1; then
                  ok "charge limit: $(charge_cap)%"
                  dim "the kernel forgets this on reboot unless a service re-applies it"
              else err "this battery rejected the value"; fi
              pause ;;
        idle) idle_menu ;;
        info) battery_info ;;
        top)  btop ;;
        ptop) sudo powertop ;;
        susp) confirm "Suspend now" && systemctl suspend && break ;;
        pmenu) "$SCRIPTS/powermenu.sh" ;;
        -)    ;;
        back|'') break ;;
    esac
done
