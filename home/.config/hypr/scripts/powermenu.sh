#!/usr/bin/env bash
# Power menu - fzf TUI. Shutdown / restart / suspend / hibernate / logout ...
# Run with: Super + Shift + Q  (kitty --class tui-power -e powermenu.sh)
set -u

US=$'\x1f'   # fzf: delimiter — splits visible text from the hidden command

# fzf picker: rows are "command<US>display" — returns the selected command
pick() {
    local prompt="$1" header="$2"; shift 2
    printf '%s\n' "$@" \
      | fzf --prompt "$prompt" --height 100% --layout=reverse --border=none \
            --info=inline --cycle --no-sort \
            --delimiter "$US" --with-nth 2 --header "$header" \
      | cut -d "$US" -f1
}

# Confirm destructive actions (Yes/No)
confirm() {
    local what="$1" ans
    ans=$(pick "  $what?  " "Enter: confirm   Esc: cancel" \
        "no${US}󰜺  No, cancel" \
        "yes${US}  Yes, $what")
    [ "$ans" = "yes" ]
}

while true; do
    choice=$(pick "  ⏻ Power  " "Enter: select   |   Esc: close" \
        "poweroff${US}󰐥  Shut down          (poweroff)" \
        "reboot${US}󰜉  Restart            (reboot)" \
        "suspend${US}󰒲  Suspend            (sleep)" \
        "hibernate${US}󰍃  Hibernate          (hibernate)" \
        "logout${US}󰗽  Log out            (Hyprland exit)" \
        "firmware${US}󰒓  UEFI / firmware    (reboot to setup)" \
        "lockscreen${US}󰷛  Screen off         (DPMS off)" \
        "quit${US}󰗼  Quit")

    case "$choice" in
        poweroff)   confirm "Shut down" && systemctl poweroff ;;
        reboot)     confirm "Restart"   && systemctl reboot ;;
        suspend)    systemctl suspend; break ;;
        hibernate)  confirm "Hibernate" && systemctl hibernate; break ;;
        logout)     confirm "Log out"   && hyprctl dispatch exit ;;
        firmware)   confirm "Reboot to UEFI setup" && systemctl reboot --firmware-setup ;;
        lockscreen) hyprctl dispatch dpms off; break ;;
        quit|"")    break ;;
    esac
done
