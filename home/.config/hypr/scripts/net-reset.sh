#!/usr/bin/env bash
# ╭──────────────────────────────────────────────────────────────────────╮
# │  Network reset  —  the "get me back online, whatever happened" button.│
# │  Tears down every tunnel, unblocks the radios, puts the DNS chain     │
# │  back to its known-good shape and reconnects Wi-Fi. Needs no network  │
# │  to run, and never deletes a saved Wi-Fi profile.                     │
# ╰──────────────────────────────────────────────────────────────────────╯
set -u
source @HOME@/.config/hypr/scripts/settings-lib.sh

step() { printf '  \033[2m%-38s\033[0m' "$1"; }
done_() { printf '\033[32mok\033[0m\n'; }
skip_() { printf '\033[2m%s\033[0m\n' "${1:-nothing to do}"; }

online() { getent hosts cloudflare.com >/dev/null 2>&1; }

reset_now() {
    clear; title "Network reset"

    # 1. every VPN-ish connection down, and stop it coming back by itself
    step "tunnels down"
    local n=0 name type
    while IFS=: read -r name type; do
        case "$type" in
            wireguard|vpn|tun)
                nmcli con down "$name" >/dev/null 2>&1
                nmcli con mod "$name" connection.autoconnect no >/dev/null 2>&1
                n=$((n + 1)) ;;
        esac
    done < <(nmcli -t -f NAME,TYPE con show 2>/dev/null | sed 's/\(.*\):\([^:]*\)$/\1:\2/')
    [ "$n" -gt 0 ] && printf '\033[32m%d down\033[0m\n' "$n" || skip_ "none active"

    # any stray wireguard link the tools left behind
    local l
    for l in $(ip -br link show type wireguard 2>/dev/null | awk '{print $1}'); do
        sudo ip link delete "$l" >/dev/null 2>&1
    done

    step "radios unblocked";   sudo rfkill unblock all >/dev/null 2>&1; nmcli radio all on >/dev/null 2>&1; done_

    # 2. the DNS chain, back to the shape the rest of the system expects
    step "resolv.conf symlink"
    sudo ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf; done_

    step "NetworkManager DNS"
    sudo mkdir -p /etc/NetworkManager/conf.d
    printf '[main]\ndns=systemd-resolved\nrc-manager=unmanaged\n' \
        | sudo tee /etc/NetworkManager/conf.d/dns.conf >/dev/null; done_

    step "resolver restart"
    sudo systemctl restart systemd-resolved >/dev/null 2>&1; sleep 1; done_

    # 3. NetworkManager itself, then bring the wireless back
    step "NetworkManager restart"
    sudo systemctl restart NetworkManager >/dev/null 2>&1
    local i=0
    while [ "$i" -lt 20 ] && ! systemctl is-active --quiet NetworkManager; do sleep 0.5; i=$((i + 1)); done
    done_

    step "Wi-Fi reconnect"
    local dev prof
    dev=$(wifi_device)
    if [ -n "$dev" ]; then
        nmcli device connect "$dev" >/dev/null 2>&1
        i=0
        while [ "$i" -lt 30 ] && [ -z "$(current_ssid "$dev")" ]; do sleep 0.5; i=$((i + 1)); done
        prof=$(current_ssid "$dev")
        [ -n "$prof" ] && printf '\033[32m%s\033[0m\n' "$prof" || skip_ "not connected — pick a network below"
    else
        skip_ "no Wi-Fi device"
    fi

    step "DNS caches flushed"
    sudo resolvectl flush-caches >/dev/null 2>&1; done_

    # 4. tell the truth about whether it worked
    printf '\n'
    i=0
    while [ "$i" -lt 16 ] && ! online; do sleep 0.5; i=$((i + 1)); done
    if online; then
        ok "back online"
        kv "address"  "$(getent hosts github.com | awk '{print $1; exit}')"
        kv "route"    "$(ip route show default | head -1)"
        kv "resolver" "$(resolvectl status 2>/dev/null | sed -n 's/.*Current DNS Server: //p' | head -1)"
    else
        err "still offline"
        dim "next: Network → Wi-Fi networks, or check that the router is up"
        kv "radio"    "$(nmcli radio wifi)"
        kv "device"   "$(nmcli -t -f DEVICE,STATE device status | head -3 | tr '\n' ' ')"
    fi
    note "Network reset" "$(online && echo 'back online' || echo 'still offline')"
    pause
}

case "${1-}" in
    --now|-y) reset_now ;;
    *)
        clear; title "Network reset"
        dim "Brings the network back to a known-good state:"
        say "· every VPN / WireGuard tunnel down, autoconnect disabled"
        say "· Wi-Fi and Bluetooth radios unblocked"
        say "· /etc/resolv.conf symlink and NetworkManager DNS restored"
        say "· systemd-resolved and NetworkManager restarted"
        say "· Wi-Fi reconnected"
        printf '\n'
        dim "Saved Wi-Fi networks and their passwords are NOT touched."
        printf '\n'
        confirm "Reset the network now" && reset_now ;;
esac
