#!/usr/bin/env bash
# ╭──────────────────────────────────────────────────────────────────────╮
# │  Notifications  —  mako.                                              │
# ╰──────────────────────────────────────────────────────────────────────╯
set -u
source @HOME@/.config/hypr/scripts/settings-lib.sh

CONF=@HOME@/.config/mako/config

history_view() {
    clear; title "Notification history"
    local n
    n=$(makoctl history 2>/dev/null | grep -c '^Notification' || echo 0)
    if [ "${n:-0}" -eq 0 ]; then
        dim "nothing in history"
    else
        makoctl history 2>/dev/null | sed 's/^/  /' | head -80
    fi
    pause
}

while true; do
    choice=$(pick "  Notifications  " "$HINT" \
        "$(item dnd   "󰂛" "Do not disturb"    "$(dnd_state)")" \
        "$(item dismiss "󰆴" "Dismiss all"     "")" \
        "$(item restore "󰕌" "Restore the last dismissed" "")" \
        "$(item hist  "󰋚" "History"           "")" \
        "$(sep)" \
        "$(item test  "󰂚" "Send a test notification" "")" \
        "$(item edit  "󰏫" "Edit mako config"  "$( [ -f "$CONF" ] && echo "$CONF" || echo 'not created yet')")" \
        "$(item reload "󰑓" "Reload mako"      "$(pgrep -x mako >/dev/null && echo running || echo 'not running')")" \
        "$(r back "󰌍  Back")")
    clear
    case "$choice" in
        dnd)     if [ "$(dnd_state)" = on ]; then makoctl mode -r do-not-disturb >/dev/null
                 else makoctl mode -a do-not-disturb >/dev/null; fi ;;
        dismiss) makoctl dismiss --all >/dev/null 2>&1; title "Notifications"; ok "all dismissed"; pause ;;
        restore) makoctl restore >/dev/null 2>&1; title "Notifications"; ok "restored"; pause ;;
        hist)    history_view ;;
        test)    notify-send -a Settings "Test notification" "If you can read this, mako is working."
                 title "Notifications"; ok "sent"; pause ;;
        edit)    mkdir -p "$(dirname "$CONF")"; "${EDITOR:-nano}" "$CONF"; makoctl reload >/dev/null 2>&1 ;;
        reload)  makoctl reload 2>&1 | sed 's/^/  /'; title "Notifications"; ok "reloaded"; pause ;;
        -)       ;;
        back|'') break ;;
    esac
done
