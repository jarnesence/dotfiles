#!/usr/bin/env bash
# ╭──────────────────────────────────────────────────────────────────────╮
# │  Settings  —  Super + ,                                               │
# │                                                                       │
# │  Top block: the switches worth flipping without reading anything,     │
# │  each showing its current state. Below: one entry per area, ordered   │
# │  by how often it gets touched. Everything else lives inside those.    │
# ╰──────────────────────────────────────────────────────────────────────╯
set -u
source @HOME@/.config/hypr/scripts/settings-lib.sh

toggle_wifi() {
    if [ "$(wifi_radio)" = enabled ]; then nmcli radio wifi off
    else nmcli radio wifi on; fi
}

toggle_bt() {
    if [ "$(bt_state)" = on ]; then rfkill block bluetooth
    else rfkill unblock bluetooth; fi
}

toggle_dnd() {
    if [ "$(dnd_state)" = on ]; then makoctl mode -r do-not-disturb >/dev/null
    else makoctl mode -a do-not-disturb >/dev/null; fi
}

cycle_profile() {
    local cur next
    cur=$(powerprofilesctl get 2>/dev/null)
    next=$(powerprofilesctl list 2>/dev/null | sed -n 's/^[ *]*\([a-z-]\+\):$/\1/p' \
           | awk -v c="$cur" '{a[NR]=$0} END{for(i=1;i<=NR;i++) if(a[i]==c){print a[i%NR+1]; exit} print a[1]}')
    [ -n "$next" ] && powerprofilesctl set "$next"
}

wifi_label() {
    [ "$(wifi_radio)" != enabled ] && { echo "off"; return; }
    local s; s=$(current_ssid "$(wifi_device)")
    echo "${s:-not connected}"
}

while true; do
    choice=$(pick "  Settings  " "Enter: open   ·   Esc: quit" \
        "$(item wifi    "󰖩" "Wi-Fi"                "$(wifi_label)")" \
        "$(item bt      "󰂯" "Bluetooth"            "$(bt_state)")" \
        "$(item dnd     "󰂛" "Do not disturb"       "$(dnd_state)")" \
        "$(item profile "󰓅" "Power profile"        "$(powerprofilesctl get 2>/dev/null)")" \
        "$(sep)" \
        "$(item network "󰤨" "Network & DNS"        "Wi-Fi, IP, DNS")" \
        "$(item sound   "󰕾" "Sound"                "devices, volume, mixer")" \
        "$(item display "󰍹" "Display & Brightness" "monitors, scale, VRR")" \
        "$(item appear  "󰸌" "Appearance"           "wallpaper, theme, fonts")" \
        "$(item input   "󰌌" "Keyboard & Touchpad"  "layout, repeat, gestures")" \
        "$(item power   "󰂄" "Power & Battery"      "profile, idle, battery")" \
        "$(item notify  "󰂚" "Notifications"        "mako, do not disturb")" \
        "$(item btdev   "󰂱" "Bluetooth devices"    "pair, connect, trust")" \
        "$(item system  "󰒓" "System"               "time, locale, disks, services")" \
        "$(item soft    "󰏔" "Software & Updates"   "packages, cache, orphans")" \
        "$(item secure  "󰦝" "Security & Privacy"   "firewall, keys, sockets")" \
        "$(item hypr    "󰖯" "Hyprland"             "keybindings, monitors, reload")" \
        "$(sep)" \
        "$(item tray    "󰂜" "Tray applets"         "")" \
        "$(item netfix  "󰜉" "Reset network"        "fix connectivity")" \
        "$(item pmenu   "󰐥" "Power menu"           "shut down, restart, sleep")" \
        "$(item quit    "󰗼" "Quit"                 "")")

    case "$choice" in
        wifi)     toggle_wifi ;;
        bt)       toggle_bt ;;
        dnd)      toggle_dnd ;;
        profile)  cycle_profile ;;
        network)  "$SCRIPTS/network.sh" ;;
        sound)    "$SCRIPTS/sound.sh" ;;
        display)  "$SCRIPTS/display.sh" ;;
        appear)   "$SCRIPTS/appearance.sh" ;;
        input)    "$SCRIPTS/input.sh" ;;
        power)    "$SCRIPTS/power.sh" ;;
        notify)   "$SCRIPTS/notifications.sh" ;;
        btdev)    bluetuith ;;
        system)   "$SCRIPTS/system.sh" ;;
        soft)     "$SCRIPTS/software.sh" ;;
        secure)   "$SCRIPTS/security.sh" ;;
        hypr)     "$SCRIPTS/hyprland-settings.sh" ;;
        tray)     # tray-tui.py needs python-dbus, which is not installed here;
                  # without this guard the entry just dumps a traceback.
                  if python3 -c 'import dbus' 2>/dev/null; then
                      @HOME@/.local/bin/tray
                  else
                      clear; title "Tray applets"
                      err "tray-tui needs the python dbus module, which is not installed"
                      dim "install it with:  paru -S python-dbus"
                      pause
                  fi ;;
        netfix)   "$SCRIPTS/net-reset.sh" ;;
        pmenu)    "$SCRIPTS/powermenu.sh" ;;
        -)        ;;                      # divider row
        quit|"")  break ;;
    esac
done
