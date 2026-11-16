#!/usr/bin/env bash
# ╭──────────────────────────────────────────────────────────────────────╮
# │  System  —  identity, time, locale, disks, services, logs.            │
# ╰──────────────────────────────────────────────────────────────────────╯
set -u
source @HOME@/.config/hypr/scripts/settings-lib.sh

# ── time & date ─────────────────────────────────────────────────────────
time_menu() {
    local sel
    while true; do
        sel=$(pick "  Time & date ❯ " "$HINT" \
            "$(item tz   "󰃰" "Time zone"          "$(timedatectl show -p Timezone --value)")" \
            "$(item ntp  "󰥔" "Network time (NTP)" "$(timedatectl show -p NTP --value)")" \
            "$(item rtc  "󰥔" "RTC in local time"  "$(timedatectl show -p LocalRTC --value)")" \
            "$(item now  "󰋼" "Current time"       "$(date '+%Y-%m-%d %H:%M:%S %Z')")" \
            "$(r back "󰌍  Back")")
        clear
        case "$sel" in
            tz)  z=$(timedatectl list-timezones | choose "  Time zone ❯ " "current: $(timedatectl show -p Timezone --value)") \
                     && { sudo timedatectl set-timezone "$z"; title "Time"; ok "time zone: $z"; pause; } ;;
            ntp) [ "$(timedatectl show -p NTP --value)" = yes ] \
                     && sudo timedatectl set-ntp false || sudo timedatectl set-ntp true ;;
            rtc) [ "$(timedatectl show -p LocalRTC --value)" = yes ] \
                     && sudo timedatectl set-local-rtc 0 || sudo timedatectl set-local-rtc 1 ;;
            now) show "Time & date" timedatectl status ;;
            back|'') return ;;
        esac
    done
}

# ── locale ──────────────────────────────────────────────────────────────
locale_menu() {
    local sel
    while true; do
        sel=$(pick "  Language & region ❯ " "$HINT" \
            "$(item lang "󰗊" "System language (LANG)" "$(localectl status | sed -n 's/.*LANG=//p' | head -1)")" \
            "$(item kbd  "󰌌" "Console keymap"        "$(localectl status | sed -n 's/.*VC Keymap: //p' | head -1)")" \
            "$(item x11  "󰌓" "X11/Wayland layout"    "$(localectl status | sed -n 's/.*X11 Layout: //p' | head -1)")" \
            "$(item info "󰋼" "Full locale status"    "")" \
            "$(r back "󰌍  Back")")
        clear
        case "$sel" in
            lang) l=$(localectl list-locales | choose "  Language ❯ " "only generated locales are listed") \
                      && { sudo localectl set-locale "LANG=$l"; title "Locale"; ok "LANG=$l"
                           dim "log out and back in for applications to pick it up"; pause; } ;;
            kbd)  k=$(localectl list-keymaps | choose "  Console keymap ❯ " "$HINT") \
                      && { sudo localectl set-keymap "$k"; title "Locale"; ok "keymap: $k"; pause; } ;;
            x11)  dim "the desktop layout is set under Keyboard & Touchpad"; pause ;;
            info) show "Locale" localectl status ;;
            back|'') return ;;
        esac
    done
}

# ── disks ───────────────────────────────────────────────────────────────
disks_menu() {
    local sel rows=() dev size fstype label mnt
    while true; do
        rows=()
        while IFS=$'\x1f' read -r dev size fstype label mnt; do
            rows+=("$(printf '%s%s󰋊  %-14s %-8s %-10s \033[2m%s\033[0m' \
                      "$dev" "$US" "$dev" "$size" "${fstype:-—}" "${mnt:-${label:-not mounted}}")")
        done < <(lsblk -rno NAME,SIZE,FSTYPE,LABEL,MOUNTPOINT 2>/dev/null \
                 | awk '{printf "/dev/%s\x1f%s\x1f%s\x1f%s\x1f%s\n", $1, $2, $3, $4, $5}')
        rows+=("$(sep)" "$(r usage "󰆼  Disk usage")" "$(r back "󰌍  Back")")

        sel=$(pick "  Disks ❯ " "Enter: mount / unmount   ·   Esc: back" "${rows[@]}")
        clear
        case "$sel" in
            usage) show "Disk usage" df -hT -x tmpfs -x devtmpfs ;;
            back|'') return ;;
            -) ;;
            *) mnt=$(lsblk -rno MOUNTPOINT "$sel" 2>/dev/null | head -1)
               title "$sel"
               if [ -n "$mnt" ]; then
                   confirm "Unmount $sel ($mnt)" && { udisksctl unmount -b "$sel" 2>&1 | sed 's/^/  /'; pause; }
               else
                   udisksctl mount -b "$sel" 2>&1 | sed 's/^/  /'; pause
               fi ;;
        esac
    done
}

# ── services ────────────────────────────────────────────────────────────
services_menu() {
    local scope=system sel unit rows=()
    while true; do
        rows=()
        while read -r unit; do
            [ -z "$unit" ] && continue
            rows+=("$(printf '%s%s󰒓  %-42s \033[2m%s · %s\033[0m' "$unit" "$US" "$unit" \
                      "$(systemctl ${scope:+--$scope} is-active "$unit" 2>/dev/null)" \
                      "$(systemctl ${scope:+--$scope} is-enabled "$unit" 2>/dev/null)")")
        done < <(systemctl $([ "$scope" = user ] && echo --user) list-units --type=service --state=running \
                 --no-legend --plain 2>/dev/null | awk '{print $1}' | head -60)

        rows=("$(r _scope "󰓡  Scope: $scope  — switch to $([ "$scope" = system ] && echo user || echo system)")"
              "$(r _failed "󰀪  Show failed units")"
              "$(sep)" "${rows[@]}" "$(sep)" "$(r back "󰌍  Back")")

        sel=$(pick "  Services ($scope) ❯ " "Enter: manage   ·   Esc: back" "${rows[@]}")
        clear
        case "$sel" in
            _scope)  [ "$scope" = system ] && scope=user || scope=system ;;
            _failed) show "Failed units" systemctl $([ "$scope" = user ] && echo --user) --failed ;;
            back|'') return ;;
            -) ;;
            *) service_actions "$sel" "$scope" ;;
        esac
    done
}

service_actions() {
    local unit=$1 scope=$2 act
    local S=(); [ "$scope" = user ] && S=(--user)
    act=$(pick "  $unit ❯ " "$HINT" \
        "$(r status  "󰋼  Status")" \
        "$(r restart "󰑓  Restart")" \
        "$(r stop    "󰓛  Stop")" \
        "$(r start   "󰐊  Start")" \
        "$(r enable  "󰄬  Enable at boot")" \
        "$(r disable "󰅖  Disable at boot")" \
        "$(r log     "󰈙  Log")" \
        "$(r back    "󰌍  Back")")
    clear
    local SUDO=(sudo); [ "$scope" = user ] && SUDO=()
    case "$act" in
        status)  show "$unit" systemctl "${S[@]}" status --no-pager "$unit" ;;
        restart) "${SUDO[@]}" systemctl "${S[@]}" restart "$unit"; title "$unit"; ok restarted; pause ;;
        stop)    confirm "Stop $unit" && { "${SUDO[@]}" systemctl "${S[@]}" stop "$unit"; title "$unit"; ok stopped; pause; } ;;
        start)   "${SUDO[@]}" systemctl "${S[@]}" start "$unit"; title "$unit"; ok started; pause ;;
        enable)  "${SUDO[@]}" systemctl "${S[@]}" enable "$unit" 2>&1 | sed 's/^/  /'; pause ;;
        disable) "${SUDO[@]}" systemctl "${S[@]}" disable "$unit" 2>&1 | sed 's/^/  /'; pause ;;
        log)     journalctl "${S[@]}" -u "$unit" -n 200 --no-pager | page ;;
    esac
}

logs_menu() {
    local sel
    sel=$(pick "  Logs ❯ " "$HINT" \
        "$(r err   "󰀪  Errors since boot")" \
        "$(r boot  "󰜎  This boot, everything")" \
        "$(r prev  "󰜊  Previous boot")" \
        "$(r follow "󰑓  Follow live")" \
        "$(r boots "󰋚  List boots")" \
        "$(r back  "󰌍  Back")")
    case "$sel" in
        err)    journalctl -p err -b --no-pager | page ;;
        boot)   journalctl -b --no-pager | page ;;
        prev)   journalctl -b -1 --no-pager | page ;;
        follow) clear; dim "Ctrl+C to stop"; journalctl -f ;;
        boots)  show "Boots" journalctl --list-boots ;;
    esac
}

sysinfo() {
    clear; title "System"
    kv "Host"       "$(hostnamectl hostname)"
    kv "OS"         "$(sed -n 's/^PRETTY_NAME="\(.*\)"/\1/p' /etc/os-release)"
    kv "Kernel"     "$(uname -r)"
    kv "Uptime"     "$(uptime -p | sed 's/^up //')"
    kv "CPU"        "$(awk -F: '/model name/{print $2; exit}' /proc/cpuinfo | sed 's/^ *//')"
    kv "Cores"      "$(nproc)"
    kv "Memory"     "$(free -h | awk '/^Mem:/{print $3" used of "$2}')"
    kv "Swap"       "$(free -h | awk '/^Swap:/{print $3" used of "$2}')"
    kv "GPU"        "$(lspci 2>/dev/null | grep -iE 'vga|3d' | head -1 | cut -d: -f3- | sed 's/^ *//')"
    kv "Root disk"  "$(df -h / | awk 'NR==2{print $3" used of "$2" ("$5")"}')"
    kv "Shell"      "$SHELL"
    kv "Session"    "${XDG_SESSION_TYPE:-?} · ${XDG_CURRENT_DESKTOP:-?}"
    pause
}

while true; do
    choice=$(pick "  System  " "$HINT" \
        "$(item info  "󰋼" "System information" "$(uname -r)")" \
        "$(item host  "󰒋" "Hostname"           "$(hostnamectl hostname)")" \
        "$(item time  "󰃰" "Time & date"        "$(timedatectl show -p Timezone --value)")" \
        "$(item loc   "󰗊" "Language & region"  "$(localectl status | sed -n 's/.*LANG=//p' | head -1)")" \
        "$(sep)" \
        "$(item disk  "󰋊" "Disks"              "$(df -h / | awk 'NR==2{print $5" of / used"}')")" \
        "$(item svc   "󰒓" "Services"           "$(systemctl --failed --no-legend | wc -l) failed")" \
        "$(item log   "󰈙" "Logs"               "journalctl")" \
        "$(sep)" \
        "$(item sess  "󰀄" "Session"            "$(whoami)")" \
        "$(r back "󰌍  Back")")
    clear
    case "$choice" in
        info) sysinfo ;;
        host) title "Hostname"; ask "Hostname" "$(hostnamectl hostname)" \
                  && { sudo hostnamectl set-hostname "$ANSWER"; ok "hostname: $ANSWER"; }; pause ;;
        time) time_menu ;;
        loc)  locale_menu ;;
        disk) disks_menu ;;
        svc)  services_menu ;;
        log)  logs_menu ;;
        sess) show "Session" loginctl session-status ;;
        -)    ;;
        back|'') break ;;
    esac
done
