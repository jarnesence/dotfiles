#!/usr/bin/env bash
# ╭──────────────────────────────────────────────────────────────────────╮
# │  Keyboard & Touchpad  —  applied live with hyprctl eval, persisted     │
# │  into a managed block at the end of hyprland.lua.                      │
# ╰──────────────────────────────────────────────────────────────────────╯
set -u
source @HOME@/.config/hypr/scripts/settings-lib.sh

# opt / hy_set / hy_sets come from settings-lib.sh — this config is Lua, so
# writes go through `hyprctl eval` and not `hyprctl keyword`.
set_opt()   { hy_set  "$1" "$2"; }    # numbers and booleans
set_str()   { hy_sets "$1" "$2"; }    # quoted strings
toggle_opt(){ [ "$(opt "$1")" = true ] && set_opt "$1" false || set_opt "$1" true; }

persist() {
    clear; title "Save input settings"
    local body
    body=$(cat <<LUA
hl.config({
    input = {
        kb_layout    = "$(opt input:kb_layout)",
        kb_variant   = "$(opt input:kb_variant)",
        kb_options   = "$(opt input:kb_options)",
        repeat_rate  = $(opt input:repeat_rate),
        repeat_delay = $(opt input:repeat_delay),
        numlock_by_default = $(opt input:numlock_by_default),
        follow_mouse = $(opt input:follow_mouse),
        sensitivity  = $(opt input:sensitivity),
        accel_profile = "$(opt input:accel_profile)",
        touchpad = {
            natural_scroll       = $(opt input:touchpad:natural_scroll),
            disable_while_typing = $(opt input:touchpad:disable_while_typing),
            tap_to_click         = $(opt input:touchpad:tap-to-click),
            drag_lock            = $(opt input:touchpad:drag_lock),
            scroll_factor        = $(opt input:touchpad:scroll_factor),
        },
    },
})
LUA
)
    printf '%s\n\n' "$body" | sed 's/^/  /'
    confirm "Write this into hyprland.lua" || return
    printf '%s\n' "$body" | lua_block input
    pause
}

layout_menu() {
    clear; title "Keyboard layout"
    dim "current: $(opt input:kb_layout)   ·   comma-separated for several, e.g. \"tr,us\""
    local l
    l=$(localectl list-x11-keymap-layouts 2>/dev/null | choose "  Layout ❯ " "Enter: pick   ·   Esc: type it yourself")
    if [ -z "$l" ]; then ask "Layout(s)" "$(opt input:kb_layout)" || return; l=$ANSWER; fi
    set_str input:kb_layout "$l"
    clear; title "Keyboard layout"; ok "layout: $l"
    case "$l" in
        *,*) dim "several layouts set — pick a switch shortcut below"
             local o; o=$(choose "  Switch with ❯ " "$HINT" \
                 "grp:alt_shift_toggle" "grp:win_space_toggle" "grp:caps_toggle" "grp:shifts_toggle" "none")
             [ -n "$o" ] && { [ "$o" = none ] && o=''; set_str input:kb_options "$o"; ok "switch: ${o:-none}"; } ;;
    esac
    dim "live now — use \"Save to config\" to keep it after a reload"
    pause
}

SD_FLAG="$HOME/.config/hypr/showdesktop.enabled"
LP_FLAG="$HOME/.config/hypr/launchpad.enabled"
flag_state() { [ -f "$1" ] && [ "$(cat "$1" 2>/dev/null)" = "1" ] && echo on || echo off; }
toggle_flag() {
    if [ "$(flag_state "$1")" = on ]; then
        printf '0\n' > "$1"
    else
        printf '1\n' > "$1"
    fi
}

touchpad_menu() {
    local sel
    while true; do
        sel=$(pick "  Touchpad ❯ " "$HINT" \
            "$(item nat  "󰜎" "Natural scrolling"     "$(opt input:touchpad:natural_scroll)")" \
            "$(item tap  "󰆾" "Tap to click"          "$(opt input:touchpad:tap-to-click)")" \
            "$(item dwt  "󰌌" "Disable while typing"  "$(opt input:touchpad:disable_while_typing)")" \
            "$(item drag "󰩰" "Drag lock"             "$( [ "$(opt input:touchpad:drag_lock)" = 0 ] && echo off || echo on)")" \
            "$(item sf   "󰈈" "Scroll speed"          "$(opt input:touchpad:scroll_factor)")" \
            "$(sep)" \
            "$(item sd   "󰍹" "Show Desktop (pinch out)" "$(flag_state "$SD_FLAG")")" \
            "$(item lp   "󰀻" "Launchpad (pinch in)"     "$(flag_state "$LP_FLAG")")" \
            "$(sep)" \
            "$(r save "󰆓  Save to config")" \
            "$(r back "󰌍  Back")")
        clear
        case "$sel" in
            nat)  toggle_opt input:touchpad:natural_scroll ;;
            tap)  toggle_opt input:touchpad:tap-to-click ;;
            dwt)  toggle_opt input:touchpad:disable_while_typing ;;
            drag) [ "$(opt input:touchpad:drag_lock)" = 0 ] \
                      && set_opt input:touchpad:drag_lock 1 || set_opt input:touchpad:drag_lock 0 ;;
            sf)   title "Scroll speed"; dim "1.0 = default, lower is slower"
                  ask "scroll_factor" "$(opt input:touchpad:scroll_factor)" \
                      && set_opt input:touchpad:scroll_factor "$ANSWER"; pause ;;
            sd)   toggle_flag "$SD_FLAG" ;;
            lp)   toggle_flag "$LP_FLAG"
                  if [ "$(flag_state "$LP_FLAG")" = on ]; then
                      pgrep -f "@HOME@/.config/hypr/scripts/launchpad.py" >/dev/null 2>&1 \
                          || setsid -f @HOME@/.config/hypr/scripts/launchpad.py >/dev/null 2>&1
                  else
                      pkill -f "@HOME@/.config/hypr/scripts/launchpad.py" 2>/dev/null || true
                  fi ;;
            save) persist ;;
            back|'') return ;;
        esac
    done
}

while true; do
    choice=$(pick "  Keyboard & Touchpad  " "$HINT" \
        "$(item layout "󰌌" "Keyboard layout"      "$(opt input:kb_layout)$( [ -n "$(opt input:kb_variant)" ] && echo " ($(opt input:kb_variant))")")" \
        "$(item rate   "󰑐" "Key repeat rate"      "$(opt input:repeat_rate)/s")" \
        "$(item delay  "󰔟" "Repeat delay"         "$(opt input:repeat_delay) ms")" \
        "$(item numlk  "󰎠" "Num lock at start"    "$(opt input:numlock_by_default)")" \
        "$(sep)" \
        "$(item touch  "󰟸" "Touchpad"             "tap, scroll, gestures")" \
        "$(item sens   "󰍽" "Pointer sensitivity"  "$(opt input:sensitivity)")" \
        "$(item accel  "󰡉" "Acceleration profile" "$(opt input:accel_profile)")" \
        "$(item follow "󰦺" "Focus follows mouse"  "$(opt input:follow_mouse)")" \
        "$(sep)" \
        "$(item gest   "󰽉" "Gestures"             "read-only")" \
        "$(r save "󰆓  Save all to hyprland.lua")" \
        "$(r back "󰌍  Back")")
    clear
    case "$choice" in
        layout) layout_menu ;;
        rate)   title "Key repeat rate"; dim "keys per second while held (default 25)"
                ask "repeat_rate" "$(opt input:repeat_rate)" && set_opt input:repeat_rate "$ANSWER"; pause ;;
        delay)  title "Repeat delay"; dim "milliseconds before repeating starts (default 600)"
                ask "repeat_delay" "$(opt input:repeat_delay)" && set_opt input:repeat_delay "$ANSWER"; pause ;;
        numlk)  toggle_opt input:numlock_by_default ;;
        touch)  touchpad_menu ;;
        sens)   title "Pointer sensitivity"; dim "-1.0 … 1.0, 0 is untouched libinput default"
                ask "sensitivity" "$(opt input:sensitivity)" && set_opt input:sensitivity "$ANSWER"; pause ;;
        accel)  p=$(choose "  Acceleration ❯ " "flat = no acceleration" adaptive flat) \
                    && { set_str input:accel_profile "$p"; title "Input"; ok "accel_profile: $p"; pause; } ;;
        follow) f=$(choose "  Focus follows mouse ❯ " "0 off · 1 on · 2 on, keep focus on click" 0 1 2) \
                    && { set_opt input:follow_mouse "$f"; title "Input"; ok "follow_mouse: $f"; pause; } ;;
        gest)   title "Gestures"; grep -n 'hl.gesture' "$HYPRCONF" | sed 's/^/  /'
                printf '\n'; dim "edit hyprland.lua to change these"; pause ;;
        save)   persist ;;
        -)      ;;
        back|'') break ;;
    esac
done
