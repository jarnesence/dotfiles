#!/usr/bin/env bash
# Volume / brightness OSD — uses the already-running eww (NO NEW PROGRAM).
# Themed (matugen colors.scss), minimal, bottom-center; closes ~1.1s after the last press.
# Usage: osd.sh vol-up | vol-down | vol-mute | mic-mute | bright-up | bright-down
set -euo pipefail

sink="@DEFAULT_AUDIO_SINK@"
mic="@DEFAULT_AUDIO_SOURCE@"
genf="$HOME/.cache/osd-gen"

vol_pct()  { wpctl get-volume "$1" | awk '{print int($2*100 + 0.5)}'; }
is_muted() { wpctl get-volume "$1" | grep -q MUTED; }

# ---- webcam (Fn+F10 sends KEY_CAMERA → XF86WebCam) ----
# The built-in camera is a USB device; de-authorising it cuts it off from every
# application and survives as a plain sysfs toggle. asus-nb-wmi exposes no
# camera LED (only kbd_backlight and micmute), so there is nothing to light by
# hand — if the bezel lamp reacts, the EC is doing it off the camera's power.
cam_dev() {
    local d
    for d in /sys/bus/usb/devices/[0-9]*-[0-9]*; do
        [ -r "$d/product" ] || continue
        case "$(tr '[:upper:]' '[:lower:]' < "$d/product")" in
            *webcam*|*camera*) printf '%s' "$d"; return 0 ;;
        esac
    done
    return 1
}
cam_on()     { [ "$(cat "$(cam_dev)/authorized" 2>/dev/null)" = 1 ]; }
cam_toggle() {
    local d; d=$(cam_dev) || return 1
    if cam_on; then printf '0' | sudo tee "$d/authorized" >/dev/null
    else            printf '1' | sudo tee "$d/authorized" >/dev/null; fi
}

# ---- action ----
case "${1:-}" in
    vol-up)      wpctl set-volume -l 1.5 "$sink" 5%+ ;;   # max 150% (boost)
    vol-down)    wpctl set-volume "$sink" 5%- ;;
    vol-mute)    wpctl set-mute "$sink" toggle ;;
    mic-mute)    wpctl set-mute "$mic" toggle ;;
    cam-mute)    cam_toggle || { echo "osd.sh: no webcam found" >&2; exit 1; } ;;
    bright-up)   brightnessctl set 5%+ >/dev/null ;;        # linear → clean 5% steps
    bright-down)                                            # exact 5% step, 5% floor (screen not fully black)
        b=$(brightnessctl -m | cut -d, -f4 | tr -d '%'); n=$((b - 5)); (( n < 5 )) && n=5
        brightnessctl set "${n}%" >/dev/null ;;
    *) echo "usage: osd.sh vol-up|vol-down|vol-mute|mic-mute|cam-mute|bright-up|bright-down" >&2; exit 1 ;;
esac

# ---- content: icon / bar value (0-100) / right label ----
case "$1" in
    vol-*)
        if is_muted "$sink"; then icon="󰝟"; val=0; text="Off"
        else
            val=$(vol_pct "$sink"); text="${val}%"
            if   (( val >= 66 )); then icon="󰕾"
            elif (( val >= 33 )); then icon="󰖀"
            else                       icon="󰕿"; fi
        fi ;;
    mic-mute)
        if is_muted "$mic"; then icon="󰍭"; val=0; text="Off"
        else                     icon="󰍬"; val=100; text="On"; fi ;;
    cam-mute)
        if cam_on; then icon="󰄀"; val=100; text="Camera on"
        else            icon="󰄁"; val=0;   text="Camera off"; fi ;;
    bright-*)
        val=$(brightnessctl -m | cut -d, -f4 | tr -d '%'); text="${val}%"; icon="󰃟" ;;
esac

# clip the bar to 0-100; flag volume above 100 (boost) -> different color
barval=$val; boost=false; (( val > 100 )) && { barval=100; boost=true; }

# ---- eww: write values → open → debounced close ----
# UNINTERRUPTED: if the window is already open DON'T REOPEN — just update values in place (no flicker/
# re-trigger). If not open, open once. Close 1.1s after the last press → layer goes away, clicks not blocked.
eww active-windows 2>/dev/null | grep -q 'osd' || eww open osd >/dev/null 2>&1 || true
eww update osd_icon="$icon" osd_val="$barval" osd_text="$text" osd_boost="$boost" >/dev/null 2>&1 || true

gen=$(( $(cat "$genf" 2>/dev/null || echo 0) + 1 )); echo "$gen" > "$genf"
setsid -f bash -c 'sleep 1.1; [ "$(cat "$1" 2>/dev/null)" = "$2" ] && eww close osd >/dev/null 2>&1' \
    _ "$genf" "$gen"
