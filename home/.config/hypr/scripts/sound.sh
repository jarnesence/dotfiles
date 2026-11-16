#!/usr/bin/env bash
# ╭──────────────────────────────────────────────────────────────────────╮
# │  Sound  —  PipeWire via wpctl/pactl, per-app mixing via wiremix.      │
# ╰──────────────────────────────────────────────────────────────────────╯
set -u
source @HOME@/.config/hypr/scripts/settings-lib.sh

SINK='@DEFAULT_AUDIO_SINK@'
SRC='@DEFAULT_AUDIO_SOURCE@'

vol()   { wpctl get-volume "$1" 2>/dev/null | awk '{printf "%d%%", $2*100 + 0.5}'; }
muted() { wpctl get-volume "$1" 2>/dev/null | grep -q MUTED && echo "muted" || echo ""; }
label() { printf '%s %s' "$(vol "$1")" "$(muted "$1")"; }

# name -> human description, so the picker is readable
device_rows() {
    local kind=$1 default cur=''
    default=$(pactl "get-default-$kind" 2>/dev/null)
    pactl list "${kind}s" 2>/dev/null | awk -v US="$US" -v def="$default" '
        /^(Sink|Source) #/      { name=""; desc="" }
        /^\tName:/              { name=$2 }
        /^\tDescription:/       { sub(/^\tDescription: /,""); desc=$0
                                  if (name ~ /\.monitor$/) next
                                  mark = (name==def) ? "󰄬" : " "
                                  printf "%s%s%s  %s\n", name, US, mark, desc }'
}

pick_device() {                     # pick_device sink|source
    local kind=$1 rows sel
    mapfile -t rows < <(device_rows "$kind")
    [ ${#rows[@]} -eq 0 ] && { clear; err "no $kind found"; pause; return; }
    sel=$(pick "  ${kind^} ❯ " "Enter: make default   ·   Esc: back" "${rows[@]}")
    [ -z "$sel" ] && return
    pactl "set-default-$kind" "$sel" && { clear; title "Sound"; ok "default $kind: $sel"; pause; }
}

# Card profiles decide which physical outputs exist. surround-* profiles are
# filtered out: on this laptop they enumerate fine and then play silence.
card_profile() {
    local card rows=() sel line
    card=$(pactl list short cards 2>/dev/null | awk 'NR==1{print $2}')
    [ -z "$card" ] && { clear; err "no sound card"; pause; return; }
    while read -r line; do
        local name desc
        name=${line%%:*}; desc=${line#*: }
        case "$name" in *surround*) continue ;; esac
        rows+=("$(printf '%s%s%s' "$name" "$US" "$desc")")
    done < <(pactl list cards 2>/dev/null | sed -n '/Profiles:/,/Active Profile:/p' \
             | grep -E '^\t\t[a-z]' | sed 's/^\t\t//')
    [ ${#rows[@]} -eq 0 ] && { clear; err "no profiles"; pause; return; }
    sel=$(pick "  Card profile ❯ " "surround profiles are hidden — they are silent on this machine" "${rows[@]}")
    [ -n "$sel" ] && { pactl set-card-profile "$card" "$sel"; clear; title "Sound"; ok "profile: $sel"; pause; }
}

status() {
    clear; title "Sound"
    kv "Output"        "$(pactl get-default-sink)"
    kv "Output volume" "$(label "$SINK")"
    kv "Input"         "$(pactl get-default-source)"
    kv "Input volume"  "$(label "$SRC")"
    kv "Card"          "$(pactl list short cards | awk 'NR==1{print $2}')"
    kv "Profile"       "$(pactl list cards | sed -n 's/^\tActive Profile: //p' | head -1)"
    printf '\n'
    dim "streams"
    pactl list short sink-inputs 2>/dev/null | awk '{print "  "$0}' | head -10
    pause
}

while true; do
    choice=$(pick "  Sound  " "$HINT" \
        "$(item outvol "󰕾" "Output volume"   "$(label "$SINK")")" \
        "$(item outmut "󰝟" "Mute output"     "$(muted "$SINK" || echo)")" \
        "$(item invol  "󰍬" "Input volume"    "$(label "$SRC")")" \
        "$(item inmut  "󰍭" "Mute microphone" "$(muted "$SRC" || echo)")" \
        "$(sep)" \
        "$(item outdev "󰓃" "Output device"   "$(pactl get-default-sink | cut -c1-38)")" \
        "$(item indev  "󰻐" "Input device"    "$(pactl get-default-source | cut -c1-38)")" \
        "$(item prof   "󰤽" "Card profile"    "$(pactl list cards | sed -n 's/^\tActive Profile: //p' | head -1)")" \
        "$(sep)" \
        "$(item mixer  "󰡱" "Per-app mixer"   "wiremix")" \
        "$(item stat   "󰋼" "Status"          "")" \
        "$(r back "󰌍  Back")")

    case "$choice" in
        outvol) clear; title "Output volume"; ask "Volume % (0-150)" "$(vol "$SINK" | tr -d %)" \
                    && wpctl set-volume -l 1.5 "$SINK" "${ANSWER}%"; pause ;;
        outmut) wpctl set-mute "$SINK" toggle ;;
        invol)  clear; title "Input volume"; ask "Volume % (0-150)" \
                    && wpctl set-volume -l 1.5 "$SRC" "${ANSWER}%"; pause ;;
        inmut)  wpctl set-mute "$SRC" toggle ;;
        outdev) pick_device sink ;;
        indev)  pick_device source ;;
        prof)   card_profile ;;
        mixer)  wiremix ;;
        stat)   status ;;
        -)      ;;
        back|'') break ;;
    esac
done
