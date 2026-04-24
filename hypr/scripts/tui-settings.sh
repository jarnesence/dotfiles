#!/bin/bash
# Comprehensive TUI settings — every system control in one place.
# Nav: ↑↓ pick, Enter open, Esc back / quit at top.

set -eu

FZF_BASE='
    --pointer ▶
    --height  100%
    --layout  reverse
    --border  none
    --info    inline
    --color   gutter:-1,bg:-1,bg+:-1,fg+:4:bold,hl+:4:bold,hl:4,prompt:2:bold,pointer:2,info:8
'
export FZF_DEFAULT_OPTS="$FZF_BASE --prompt=settings>\040"

pause() { printf '\n[enter] continue… '; read -r _; }

# ─── Persistence helper ──────────────────────────
# Her TUI değişikliği hem runtime (hyprctl) hem diske (overrides.conf).
OVERRIDES="$HOME/.config/hypr/overrides.conf"
mkdir -p "$(dirname "$OVERRIDES")"; touch "$OVERRIDES"

persist() {
    # usage: persist <hypr-keyword-key> <value>
    local key="$1" val="$2"
    hyprctl keyword "$key" "$val" >/dev/null 2>&1 || true
    local escaped
    escaped=$(printf '%s' "$key" | sed 's|[.*[]|\\&|g')
    grep -v "^${escaped}[[:space:]]*=" "$OVERRIDES" > "$OVERRIDES.tmp" || true
    mv "$OVERRIDES.tmp" "$OVERRIDES"
    echo "$key = $val" >> "$OVERRIDES"
}

persist_env() {
    # usage: persist_env <NAME> <value>   → "env = NAME,value"
    local name="$1" val="$2"
    hyprctl keyword env "$name,$val" >/dev/null 2>&1 || true
    grep -v "^env[[:space:]]*=[[:space:]]*${name}," "$OVERRIDES" > "$OVERRIDES.tmp" || true
    mv "$OVERRIDES.tmp" "$OVERRIDES"
    echo "env = $name,$val" >> "$OVERRIDES"
}

# ─── AUDIO ────────────────────────────────────
audio_menu() {
    while true; do
        c=$(printf '%s\n' \
            "mixer              — pulsemixer TUI" \
            "default sink       — pick output" \
            "default source     — pick input" \
            "mute sink toggle   — master mute" \
            "mute source toggle — mic mute" \
            "volume +5" \
            "volume -5" \
            "←                  — back" \
        | fzf --prompt='audio> ') || return
        case "${c%% *}" in
            mixer)  pulsemixer ;;
            default) case "$c" in
                *sink*)   s=$(pactl list sinks   short | fzf) && pactl set-default-sink   "$(echo "$s" | awk '{print $2}')" ;;
                *source*) s=$(pactl list sources short | fzf) && pactl set-default-source "$(echo "$s" | awk '{print $2}')" ;;
            esac ;;
            mute) case "$c" in
                *sink*)   pactl set-sink-mute   @DEFAULT_SINK@   toggle ;;
                *source*) pactl set-source-mute @DEFAULT_SOURCE@ toggle ;;
            esac ;;
            volume) case "$c" in
                *+5*) pactl set-sink-volume @DEFAULT_SINK@ +5% ;;
                *-5*) pactl set-sink-volume @DEFAULT_SINK@ -5% ;;
            esac ;;
            ←) return ;;
        esac
    done
}

# ─── DISPLAY ──────────────────────────────────
display_menu() {
    while true; do
        c=$(printf '%s\n' \
            "monitors          — list state" \
            "vrr toggle        — Adaptive Sync" \
            "refresh rate      — pick Hz (DP-1)" \
            "resolution        — DP-1 resolution" \
            "scale             — monitor scale" \
            "←                 — back" \
        | fzf --prompt='display> ') || return
        case "${c%% *}" in
            monitors) hyprctl monitors ; pause ;;
            vrr) cur=$(hyprctl getoption misc:vrr | awk '/^int/{print $2}')
                 persist misc:vrr $((cur==0?1:0)) ; echo "vrr toggled"; pause ;;
            refresh) hz=$(printf '60\n120\n144\n165\n240\n' | fzf) || continue
                     persist monitor "DP-1, 2560x1440@${hz}, 0x0, 1" ;;
            resolution) r=$(printf '2560x1440\n1920x1080\n1680x1050\n1280x720\n' | fzf) || continue
                     persist monitor "DP-1, ${r}@239.97, 0x0, 1" ;;
            scale) s=$(printf '1\n1.25\n1.5\n1.75\n2\n' | fzf) || continue
                     persist monitor "DP-1, preferred, 0x0, ${s}" ;;
            ←) return ;;
        esac
    done
}

# ─── APPEARANCE ───────────────────────────────
appearance_menu() {
    while true; do
        c=$(printf '%s\n' \
            "wallpaper cycle   — next video" \
            "palette cycle     — next scheme" \
            "plymouth theme    — boot splash" \
            "waybar toggle     — hide/show" \
            "rounding          — window radius" \
            "gaps              — in + out" \
            "blur toggle       — on/off" \
            "blur size         — strength" \
            "border size       — 0/1/2" \
            "opacity           — active/inactive" \
            "shadow toggle     — window shadow" \
            "dim inactive      — dim unfocused" \
            "animations toggle — on/off" \
            "←                 — back" \
        | fzf --prompt='appearance> ') || return
        case "${c%% *}" in
            wallpaper) ~/.config/hypr/scripts/live-wallpaper-next.sh ; pause ;;
            palette)   ~/.config/hypr/scripts/palette-scheme-next.sh ; pause ;;
            plymouth)  t=$(ls /usr/share/plymouth/themes | fzf) || continue
                       sudo plymouth-set-default-theme -R "$t" ; pause ;;
            waybar)    pkill -SIGUSR1 waybar ;;
            rounding)  v=$(printf '0\n2\n5\n10\n' | fzf) || continue
                       persist decoration:rounding "$v" ;;
            gaps)      g=$(printf '0\n5\n10\n15\n' | fzf --prompt='gaps_in> ') || continue
                       persist general:gaps_in "$g"
                       g=$(printf '0\n5\n10\n15\n20\n' | fzf --prompt='gaps_out> ') || continue
                       persist general:gaps_out "$g" ;;
            blur) case "$c" in
                *toggle*) cur=$(hyprctl getoption decoration:blur:enabled | awk '/^int/{print $2}')
                          persist decoration:blur:enabled $((cur==0?1:0)) ;;
                *size*)   v=$(printf '2\n4\n6\n8\n10\n' | fzf) || continue
                          persist decoration:blur:size "$v" ;;
            esac ;;
            border) v=$(printf '0\n1\n2\n3\n' | fzf) || continue
                    persist general:border_size "$v" ;;
            opacity) a=$(printf '0.70\n0.80\n0.88\n1.00\n' | fzf --prompt='active> ') || continue
                     persist decoration:active_opacity "$a"
                     i=$(printf '0.60\n0.70\n0.80\n0.90\n1.00\n' | fzf --prompt='inactive> ') || continue
                     persist decoration:inactive_opacity "$i" ;;
            shadow) cur=$(hyprctl getoption decoration:shadow:enabled | awk '/^int/{print $2}')
                    persist decoration:shadow:enabled $((cur==0?1:0)) ;;
            dim) cur=$(hyprctl getoption decoration:dim_inactive | awk '/^int/{print $2}')
                 persist decoration:dim_inactive $((cur==0?1:0)) ;;
            animations) cur=$(hyprctl getoption animations:enabled | awk '/^int/{print $2}')
                 persist animations:enabled $((cur==0?1:0)) ;;
            ←) return ;;
        esac
    done
}

# ─── INPUT (mouse + cursor + keyboard + touchpad) ─────
input_menu() {
    while true; do
        c=$(printf '%s\n' \
            "cursor theme      — pick icon set" \
            "cursor size       — px" \
            "mouse sensitivity — -1..1" \
            "mouse accel       — adaptive/flat" \
            "natural scroll    — toggle" \
            "scroll factor     — speed" \
            "keyboard layout   — tr/us/…" \
            "keyboard repeat   — rate + delay" \
            "touchpad tap      — toggle" \
            "touchpad disable-while-typing — toggle" \
            "binds list        — show active" \
            "←                 — back" \
        | fzf --prompt='input> ') || return
        case "${c%% *}" in
            cursor) case "$c" in
                *theme*) t=$(ls ~/.local/share/icons /usr/share/icons 2>/dev/null | \
                             grep -v ':$' | grep -v '^$' | sort -u | fzf) || continue
                         s=$(printenv XCURSOR_SIZE 2>/dev/null || echo 29)
                         hyprctl setcursor "$t" "$s"
                         persist_env XCURSOR_THEME   "$t"
                         persist_env HYPRCURSOR_THEME "$t" ;;
                *size*)  s=$(printf '16\n20\n24\n29\n32\n40\n48\n' | fzf) || continue
                         t=$(printenv XCURSOR_THEME 2>/dev/null || echo Future-dark-cursors)
                         hyprctl setcursor "$t" "$s"
                         persist_env XCURSOR_SIZE    "$s"
                         persist_env HYPRCURSOR_SIZE "$s" ;;
            esac ;;
            mouse) case "$c" in
                *sensitivity*) v=$(printf -- '-0.8\n-0.4\n-0.2\n0\n0.2\n0.4\n0.8\n' | fzf) || continue
                               persist input:sensitivity "$v" ;;
                *accel*)       v=$(printf 'adaptive\nflat\n' | fzf) || continue
                               persist input:accel_profile "$v" ;;
            esac ;;
            natural) cur=$(hyprctl getoption input:natural_scroll | awk '/^int/{print $2}')
                     persist input:natural_scroll $((cur==0?1:0)) ;;
            scroll) v=$(printf '0.5\n1.0\n1.5\n2.0\n' | fzf) || continue
                     persist input:scroll_factor "$v" ;;
            keyboard) case "$c" in
                *layout*) l=$(printf 'tr\nus\nus,tr\ntr,us\nde\nfr\n' | fzf) || continue
                          persist input:kb_layout "$l" ;;
                *repeat*) r=$(printf '25\n30\n40\n50\n' | fzf --prompt='rate> ') || continue
                          persist input:repeat_rate "$r"
                          d=$(printf '200\n300\n400\n600\n' | fzf --prompt='delay> ') || continue
                          persist input:repeat_delay "$d" ;;
            esac ;;
            touchpad) case "$c" in
                *tap*) cur=$(hyprctl getoption input:touchpad:tap-to-click | awk '/^int/{print $2}')
                       persist input:touchpad:tap-to-click $((cur==0?1:0)) ;;
                *disable-while-typing*) cur=$(hyprctl getoption input:touchpad:disable_while_typing | awk '/^int/{print $2}')
                       persist input:touchpad:disable_while_typing $((cur==0?1:0)) ;;
            esac ;;
            binds) hyprctl binds | less ;;
            ←) return ;;
        esac
    done
}

# ─── NOTIFICATIONS ───────────────────────────
notifications_menu() {
    while true; do
        c=$(printf '%s\n' \
            "dnd toggle       — do not disturb" \
            "dismiss all      — clear current" \
            "history          — recent" \
            "restore last     — bring back" \
            "←                — back" \
        | fzf --prompt='notifications> ') || return
        case "${c%% *}" in
            dnd) cur=$(makoctl mode 2>/dev/null | head -1)
                 [ "$cur" = "do-not-disturb" ] && makoctl mode -s default || makoctl mode -s do-not-disturb ;;
            dismiss) makoctl dismiss --all ;;
            history) makoctl history | head -50 ; pause ;;
            restore) makoctl restore ;;
            ←) return ;;
        esac
    done
}

# ─── CLIPBOARD ───────────────────────────────
clipboard_menu() {
    while true; do
        c=$(printf '%s\n' \
            "view history — pick + copy back" \
            "clear        — wipe cliphist" \
            "←            — back" \
        | fzf --prompt='clipboard> ') || return
        case "${c%% *}" in
            view)  cliphist list | fzf | cliphist decode | wl-copy ;;
            clear) cliphist wipe ; echo "cleared." ; pause ;;
            ←) return ;;
        esac
    done
}

# ─── SYSTEM ──────────────────────────────────
system_menu() {
    while true; do
        c=$(printf '%s\n' \
            "monitor     — btop" \
            "disk        — duf / df" \
            "services    — systemctl failed" \
            "journal     — live tail" \
            "kernel      — uname -a" \
            "memory      — free -h" \
            "processes   — ps aux" \
            "←           — back" \
        | fzf --prompt='system> ') || return
        case "${c%% *}" in
            monitor)   btop ;;
            disk)      command -v duf >/dev/null && duf || df -h ; pause ;;
            services)  systemctl --failed ; pause ;;
            journal)   journalctl -f ;;
            kernel)    uname -a ; pause ;;
            memory)    free -h ; pause ;;
            processes) ps aux | less ;;
            ←) return ;;
        esac
    done
}

# ─── POWER ───────────────────────────────────
power_menu() {
    c=$(printf '%s\n' \
        "lock         — hyprlock" \
        "suspend      — sleep" \
        "hibernate    — to disk" \
        "reboot" \
        "shutdown     — poweroff" \
        "exit         — close Hyprland" \
        "←            — back" \
    | fzf --prompt='power> ') || return
    case "${c%% *}" in
        lock)      command -v hyprlock >/dev/null && hyprlock || { echo "hyprlock not installed"; pause; } ;;
        suspend)   systemctl suspend ;;
        hibernate) systemctl hibernate ;;
        reboot)    systemctl reboot ;;
        shutdown)  systemctl poweroff ;;
        exit)      hyprctl dispatch exit ;;
    esac
}

# ─── UPDATES ─────────────────────────────────
updates_menu() {
    while true; do
        c=$(printf '%s\n' \
            "check     — no download" \
            "system    — pacman -Syu" \
            "aur       — paru -Syu" \
            "orphans   — remove unused deps" \
            "cache     — clean pacman cache" \
            "←         — back" \
        | fzf --prompt='updates> ') || return
        case "${c%% *}" in
            check)   command -v checkupdates >/dev/null && checkupdates || pacman -Qu ; pause ;;
            system)  sudo pacman -Syu ; pause ;;
            aur)     paru -Syu ; pause ;;
            orphans) pacman -Qdtq | xargs -r sudo pacman -Rns ; pause ;;
            cache)   sudo paccache -r 2>/dev/null || sudo pacman -Sc ; pause ;;
            ←) return ;;
        esac
    done
}

# ─── DEFAULT APPS (xdg-mime) ─────────────────
apps_menu() {
    while true; do
        c=$(printf '%s\n' \
            "browser   — default web browser" \
            "terminal  — default terminal" \
            "editor    — \$EDITOR via /etc/environment" \
            "image     — default image viewer" \
            "video     — default video player" \
            "←         — back" \
        | fzf --prompt='default apps> ') || return
        case "${c%% *}" in
            browser) d=$(ls /usr/share/applications/*.desktop | xargs -I{} basename {} | fzf) || continue
                     xdg-mime default "$d" x-scheme-handler/http x-scheme-handler/https ;;
            terminal) d=$(printf 'kitty.desktop\nalacritty.desktop\nfoot.desktop\n' | fzf) || continue
                     xdg-mime default "$d" application/x-terminal ;;
            editor)  e=$(printf 'nvim\nvim\nnano\nmicro\n' | fzf) || continue
                     sudo sh -c "grep -q '^EDITOR=' /etc/environment && sed -i 's|^EDITOR=.*|EDITOR=$e|' /etc/environment || echo 'EDITOR=$e' >> /etc/environment" ;;
            image)   d=$(ls /usr/share/applications/*.desktop | xargs -I{} basename {} | fzf) || continue
                     xdg-mime default "$d" image/png image/jpeg image/gif ;;
            video)   d=$(ls /usr/share/applications/*.desktop | xargs -I{} basename {} | fzf) || continue
                     xdg-mime default "$d" video/mp4 video/x-matroska video/webm ;;
            ←) return ;;
        esac
    done
}

# ─── INFO (read-only) ────────────────────────
info_menu() {
    while true; do
        c=$(printf '%s\n' \
            "hostname     — $(hostnamectl hostname 2>/dev/null)" \
            "kernel       — $(uname -r)" \
            "uptime       — $(uptime -p)" \
            "arch         — $(uname -m)" \
            "user         — $(id -un)" \
            "locale       — $(localectl status 2>/dev/null | awk '/System Locale/{print $NF}')" \
            "timezone     — $(timedatectl show --value -p Timezone 2>/dev/null)" \
            "gpu          — $(lspci | grep -iE 'vga|3d' | head -1 | sed 's/.*: //' | cut -c1-40)" \
            "←            — back" \
        | fzf --prompt='info> ' --header='read-only · esc back') || return
        [ "${c%% *}" = "←" ] && return
    done
}

# ─── BRIGHTNESS ──────────────────────────────
brightness_menu() {
    if [ ! -d /sys/class/backlight ] || [ -z "$(ls /sys/class/backlight 2>/dev/null)" ]; then
        echo "no backlight (desktop monitor — use OSD buttons or ddcutil)"; pause; return
    fi
    command -v brightnessctl >/dev/null || { echo "install brightnessctl first"; pause; return; }
    c=$(printf '10\n25\n50\n75\n100\n' | fzf --prompt='brightness %> ') || return
    brightnessctl set "${c}%"
}

# ─── SCREENSHOT ──────────────────────────────
screenshot_menu() {
    c=$(printf '%s\n' \
        "area  — select region" \
        "full  — entire screen" \
        "←     — back" \
    | fzf --prompt='screenshot> ') || return
    case "${c%% *}" in
        area) ~/.config/hypr/scripts/screenshot.sh area ;;
        full) ~/.config/hypr/scripts/screenshot.sh full ;;
    esac
}

# ─── MAIN ────────────────────────────────────
main() {
    while true; do
        c=$(printf '%s\n' \
            "network       — nmtui" \
            "bluetooth     — bluetuith" \
            "audio         — volume, sinks, sources" \
            "display       — monitors, vrr, refresh" \
            "brightness    — screen brightness" \
            "appearance    — wallpaper, gaps, blur, rounding, opacity, shadow, animations" \
            "input         — cursor, mouse, keyboard, touchpad" \
            "apps          — default browser / terminal / editor" \
            "notifications — dnd, history, clear" \
            "clipboard     — history, clear" \
            "system        — btop, disk, services, journal, info" \
            "updates       — pacman, aur, orphans, cache" \
            "screenshot    — area / full" \
            "info          — hostname, kernel, uptime, locale, timezone" \
            "power         — lock, suspend, reboot, shutdown, exit" \
        | fzf --prompt='settings> ' --header='Settings · esc quit') || exit 0
        case "${c%% *}" in
            network)       nmtui ;;
            bluetooth)     bluetuith ;;
            audio)         audio_menu ;;
            display)       display_menu ;;
            brightness)    brightness_menu ;;
            appearance)    appearance_menu ;;
            input)         input_menu ;;
            apps)          apps_menu ;;
            notifications) notifications_menu ;;
            clipboard)     clipboard_menu ;;
            system)        system_menu ;;
            updates)       updates_menu ;;
            screenshot)    screenshot_menu ;;
            info)          info_menu ;;
            power)         power_menu ;;
        esac
    done
}

main
