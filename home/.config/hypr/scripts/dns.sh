#!/usr/bin/env bash
# ╭──────────────────────────────────────────────────────────────────────╮
# │  DNS TUI  —  one place for every resolver on this machine.            │
# │  Resolver mode (dnscrypt-proxy / resolved+DoT / plain),               │
# │  dnscrypt server picking from the 700+ public list, preset & manual   │
# │  DNS, systemd-resolved tuning, leak/latency tests, health repair.     │
# │  Reached from `settings` (Super+,) → Wi-Fi/Network → DNS, or direct.  │
# ╰──────────────────────────────────────────────────────────────────────╯
set -u

SELF=$(readlink -f "$0")
FZF=(fzf --height 100% --reverse --border --info inline --cycle)

TOML=/etc/dnscrypt-proxy/dnscrypt-proxy.toml
TOMLED=@HOME@/.config/hypr/scripts/dnstoml.py
DNSQ=@HOME@/.config/hypr/scripts/dnsq.py
RDROP=/etc/systemd/resolved.conf.d/00-local.conf
RESLIST=/var/cache/dnscrypt-proxy/public-resolvers.md
RESCACHE="${XDG_CACHE_HOME:-$HOME/.cache}/dns-menu/public-resolvers.md"

# ── small helpers ───────────────────────────────────────────────────────
pause() { printf '\n  %s\n' "${1:-press Enter to continue}"; read -r _; }
# `less` is not installed here; fall back to whatever pager exists.
page()  { if command -v less >/dev/null 2>&1; then less -R
          elif command -v more >/dev/null 2>&1; then more
          else cat; printf '\n  press Enter to continue '; read -r _ </dev/tty; fi; }
head2() { printf '\n  \033[1m%s\033[0m\n  %s\n\n' "$1" "$(printf '─%.0s' $(seq 1 68))"; }
yn()    { printf '  %s [y/N]: ' "$1"; read -r a; [ "${a,,}" = y ]; }

tget()  { sudo python3 "$TOMLED" get "$@" 2>/dev/null; }
tset()  { sudo python3 "$TOMLED" set "$@"; }

# our own drop-in, so the format is known and greppable
rget()  { sudo sed -n "s/^${1}=//p" "$RDROP" 2>/dev/null | head -1; }
rset() {
    local key=$1 val=${2-}
    sudo mkdir -p /etc/systemd/resolved.conf.d
    [ -f "$RDROP" ] || printf '[Resolve]\n' | sudo tee "$RDROP" >/dev/null
    if sudo grep -qE "^${key}=" "$RDROP"; then
        if [ -z "$val" ]; then sudo sed -i "/^${key}=/d" "$RDROP"
        else sudo sed -i "s|^${key}=.*|${key}=${val}|" "$RDROP"; fi
    elif [ -n "$val" ]; then
        printf '%s=%s\n' "$key" "$val" | sudo tee -a "$RDROP" >/dev/null
    fi
}

dc_on()     { systemctl is-active --quiet dnscrypt-proxy && echo on || echo off; }

dns_reaches() { getent hosts cloudflare.com >/dev/null 2>&1; }

apply_resolved() { sudo systemctl restart systemd-resolved && sleep 1; }

# active NM connection profile of the default-route device
active_con() {
    local dev
    dev=$(ip route show default 2>/dev/null | awk '{print $5; exit}')
    nmcli -t -f DEVICE,NAME con show --active 2>/dev/null \
        | awk -F: -v d="$dev" '$1==d{print substr($0, length(d)+2)}' \
        | sed 's/\\:/:/g; s/\\\\/\\/g' | head -1
}

# ── preset public resolvers:  label | plain servers | DoT hostname | flags
# flags "enc" = provider answers ONLY over DoT/DoH. Verified: Mullvad REFUSEs
# and dns0.eu times out on plain UDP/53, so offering them as plain DNS would
# silently kill name resolution.
PRESETS=(
"Cloudflare              — fast, no filtering|1.1.1.1 1.0.0.1|cloudflare-dns.com|"
"Cloudflare Security     — blocks malware|1.1.1.2 1.0.0.2|security.cloudflare-dns.com|"
"Cloudflare Family       — malware + adult|1.1.1.3 1.0.0.3|family.cloudflare-dns.com|"
"Quad9                   — malware block, DNSSEC|9.9.9.9 149.112.112.112|dns.quad9.net|"
"Quad9 Unfiltered        — no blocking|9.9.9.10 149.112.112.10|dns10.quad9.net|"
"AdGuard                 — ads + trackers|94.140.14.14 94.140.15.15|dns.adguard-dns.com|"
"AdGuard Family          — ads + adult|94.140.14.15 94.140.15.16|family.adguard-dns.com|"
"AdGuard Unfiltered      — no blocking|94.140.14.140 94.140.14.141|unfiltered.adguard-dns.com|"
"ControlD Unfiltered     — no blocking|76.76.2.0 76.76.10.0|p0.freedns.controld.com|"
"Google                  — 8.8.8.8|8.8.8.8 8.8.4.4|dns.google|"
"OpenDNS                 — Cisco|208.67.222.222 208.67.220.220|dns.opendns.com|"
"dns0.eu                 — EU, no logs · encrypted only|193.110.81.0 185.253.5.0|dns0.eu|enc"
"dns0.eu Kids            — child safe · encrypted only|193.110.81.1 185.253.5.1|kids.dns0.eu|enc"
"Mullvad                 — no logs · encrypted only|194.242.2.2|dns.mullvad.net|enc"
"Mullvad Adblock         — no logs + ads · encrypted only|194.242.2.3|adblock.dns.mullvad.net|enc"
)

preset_menu() { printf '%s\n' "${PRESETS[@]}" | cut -d'|' -f1; }
preset_find() { printf '%s\n' "${PRESETS[@]}" | grep -F -m1 "$(printf '%s' "$1" | cut -d'|' -f1)"; }

# ═══ 1. status ══════════════════════════════════════════════════════════
status_view() {
    clear
    head2 "DNS chain"
    local rc dc
    rc=$(readlink -f /etc/resolv.conf 2>/dev/null)
    dc=$(dc_on)

    printf '  %-22s %s\n' "/etc/resolv.conf" \
        "$([ -L /etc/resolv.conf ] && echo "symlink → ${rc:-BROKEN}" || echo '⚠ NOT a symlink')"
    printf '  %-22s %s\n' "resolv.conf mode" "$(resolvectl status 2>/dev/null | sed -n 's/.*resolv.conf mode: //p' | head -1)"
    printf '  %-22s %s\n' "dnscrypt-proxy" "$dc  ($(tget server_names | tr -d "[]'"))"
    printf '  %-22s %s\n' "resolved global DNS" "$(rget DNS)"
    printf '  %-22s %s\n' "fallback" "$(rget FallbackDNS)"
    printf '  %-22s %s\n' "DNSOverTLS / DNSSEC" "$(rget DNSOverTLS) / $(rget DNSSEC)"

    printf '\n  \033[1mEffective route\033[0m\n'
    if [ "$dc" = on ] && [ -n "$(rget DNS)" ]; then
        printf '  app → resolved → \033[36mdnscrypt-proxy\033[0m → internet\n'
    else
        printf '  app → resolved → \033[33mlink DNS (router, plaintext)\033[0m\n'
    fi

    printf '\n  \033[1mWho resolves what\033[0m\n'
    resolvectl status 2>/dev/null | awk '
        /^Global/{link="Global"}
        /^Link /{link=$0; sub(/^Link [0-9]+ /,"",link); gsub(/[()]/,"",link)}
        /Current DNS Server:/{sub(/.*Current DNS Server: /,""); printf "  %-22s %s\n", link, $0}
        /DNS Domain: ~\./{printf "  %-22s %s\n", "", "↳ catch-all for every name"}'
    pause
}

# ═══ 2. resolver mode ═══════════════════════════════════════════════════
current_mode_label() {
    local dc; dc=$(dc_on)
    if   [ "$dc" = on ]  && [ -n "$(rget DNS)" ]; then echo "dnscrypt only"
    elif [ "$(rget DNSOverTLS)" = yes ]; then echo "resolved + DoT"
    else echo "plain / router"; fi
}

resolver_mode() {
    local sel
    sel=$(printf '%s\n' \
        "󰒃  dnscrypt only         — encrypted DNS via dnscrypt-proxy" \
        "󰩰  systemd-resolved DoT  — no dnscrypt, resolved talks DNS-over-TLS" \
        "󰅛  Plain / router        — DHCP DNS, unencrypted (captive portals)" \
        "󰌍  Back" \
      | "${FZF[@]}" --prompt "  resolver ❯ " \
            --header "current: $(current_mode_label)   |   changes take effect immediately") || return
    case "$sel" in
        *"dnscrypt only"*)
            sudo systemctl enable --now dnscrypt-proxy >/dev/null 2>&1
            rset DNS 127.0.0.1; apply_resolved
            pause "DNS via dnscrypt-proxy" ;;
        *"DoT"*)
            local p srv host
            p=$(preset_menu | "${FZF[@]}" --prompt "  DoT upstream ❯ ") || return
            p=$(preset_find "$p")
            srv=$(printf '%s' "$p" | cut -d'|' -f2); host=$(printf '%s' "$p" | cut -d'|' -f3)
            local dnsline=""
            for ip in $srv; do dnsline+="${ip}#${host} "; done
            sudo systemctl disable --now dnscrypt-proxy >/dev/null 2>&1
            rset DNS "${dnsline% }"; rset DNSOverTLS yes; apply_resolved
            pause "resolved now speaks DoT to ${host}" ;;
        *"Plain"*)
            if yn "this disables encrypted DNS — sure?"; then
                sudo systemctl stop dnscrypt-proxy >/dev/null 2>&1
                rset DNS ""; rset DNSOverTLS no; apply_resolved
                pause "plain DHCP DNS — remember to switch back"
            fi ;;
        *) return ;;
    esac
}

# ═══ 3. dnscrypt-proxy ══════════════════════════════════════════════════
sync_resolvers() {
    mkdir -p "$(dirname "$RESCACHE")"
    if sudo test -r "$RESLIST"; then
        sudo cat "$RESLIST" > "$RESCACHE" 2>/dev/null && return 0
    fi
    return 1
}

describe() {   # fzf preview: print one resolver's block from the list
    [ -f "$RESCACHE" ] || return 0
    awk -v want="## $1" '
        $0 == want {show=1; print; next}
        show && /^## / {exit}
        show {print}' "$RESCACHE"
}

pick_servers() {
    sync_resolvers || { pause "resolver list not readable — run 'Refresh list' first"; return; }
    local sel names
    sel=$(grep '^## ' "$RESCACHE" | sed 's/^## //' | sort \
        | "${FZF[@]}" --multi --prompt "  dnscrypt servers ❯ " \
              --preview "$SELF --describe {1}" --preview-window 'right:55%:wrap' \
              --header "Tab: multi-select (order = failover priority)   |   Enter: apply") || return
    [ -z "$sel" ] && return
    names=$(printf '%s\n' "$sel" | awk '{printf "%s'\''%s'\''", (NR>1?", ":""), $1}')
    tset server_names "[$names]"
    sudo systemctl restart dnscrypt-proxy
    sleep 3
    pause "$(printf 'servers: [%s]\n\n' "$names"; journalctl -u dnscrypt-proxy -n 6 --no-pager -o cat)"
}

dc_toggle() {  # key  human-name
    local cur; cur=$(tget "$1")
    [ "$cur" = true ] && tset "$1" false || tset "$1" true
    sudo systemctl restart dnscrypt-proxy
    pause "$2: $([ "$cur" = true ] && echo false || echo true)"
}

adblock_menu() {
    local cur sel
    cur=$(tget blocked_names_file --section blocked_names)
    sel=$(printf '%s\n' \
        "󰂭  Enable ad/tracker blocking   (blocked-names.txt)" \
        "󰂲  Disable blocking" \
        "󰏫  Edit block list" \
        "󰌍  Back" \
      | "${FZF[@]}" --prompt "  blocking ❯ " --header "current: ${cur:-disabled}") || return
    case "$sel" in
        *Enable*)  tset blocked_names_file "'/etc/dnscrypt-proxy/blocked-names.txt'" --section blocked_names
                   sudo systemctl restart dnscrypt-proxy; pause "blocking on" ;;
        *Disable*) sudo sed -i "s|^blocked_names_file|# blocked_names_file|" "$TOML"
                   sudo systemctl restart dnscrypt-proxy; pause "blocking off" ;;
        *Edit*)    sudo "${EDITOR:-nano}" /etc/dnscrypt-proxy/blocked-names.txt
                   sudo systemctl restart dnscrypt-proxy ;;
    esac
}

dnscrypt_menu() {
    local sel
    while true; do
        sel=$(printf '%s\n' \
            "󰐥  Service: $(dc_on)   — start / stop / restart" \
            "󰒓  Servers: $(tget server_names | tr -d "[]'" | cut -c1-46)" \
            "󰒔  Pick servers from the public list  (700+)" \
            "󰓅  Benchmark & auto-pick fastest" \
            "󰒃  require_nolog:    $(tget require_nolog)" \
            "󰒃  require_dnssec:   $(tget require_dnssec)" \
            "󰒃  require_nofilter: $(tget require_nofilter)" \
            "󰩠  ipv6_servers:     $(tget ipv6_servers)" \
            "󰆼  cache:            $(tget cache)" \
            "󰂭  Ad / tracker blocking" \
            "󰑓  Refresh resolver list" \
            "󰈙  View log" \
            "󰏫  Edit dnscrypt-proxy.toml" \
            "󰌍  Back" \
          | "${FZF[@]}" --prompt "  dnscrypt-proxy ❯ " \
                --header "$(systemctl is-active dnscrypt-proxy) / $(systemctl is-enabled dnscrypt-proxy 2>&1)") || return
        case "$sel" in
            *Service*)
                local a
                a=$(printf '%s\n' restart start stop "enable at boot" "disable at boot" \
                    | "${FZF[@]}" --prompt "  action ❯ ") || continue
                case "$a" in
                    restart) sudo systemctl restart dnscrypt-proxy ;;
                    start)   sudo systemctl start dnscrypt-proxy ;;
                    stop)    sudo systemctl stop dnscrypt-proxy ;;
                    enable*) sudo systemctl enable dnscrypt-proxy ;;
                    disable*) sudo systemctl disable dnscrypt-proxy ;;
                esac
                sleep 1; pause "$(systemctl status dnscrypt-proxy --no-pager -l | head -4)" ;;
            *"Servers:"*)       pick_servers ;;   # before *cache*: a server name could contain it
            *"Pick servers"*)   pick_servers ;;
            *Benchmark*)        bench_dnscrypt ;;
            *require_nolog*)    dc_toggle require_nolog    "require_nolog" ;;
            *require_dnssec*)   dc_toggle require_dnssec   "require_dnssec" ;;
            *require_nofilter*) dc_toggle require_nofilter "require_nofilter" ;;
            *ipv6_servers*)     dc_toggle ipv6_servers     "ipv6_servers" ;;
            *cache*)            dc_toggle cache            "cache" ;;
            *blocking*)         adblock_menu ;;
            *Refresh*)          sudo systemctl restart dnscrypt-proxy; sleep 4
                                sync_resolvers && pause "list: $(grep -c '^## ' "$RESCACHE") servers" ;;
            *"View log"*)       sudo journalctl -u dnscrypt-proxy -n 200 --no-pager | page ;;
            *Edit*)             sudo "${EDITOR:-nano}" "$TOML"
                                yn "restart dnscrypt-proxy?" && sudo systemctl restart dnscrypt-proxy ;;
            *Back*|"")          return ;;
        esac
    done
}

bench_dnscrypt() {
    clear; head2 "dnscrypt-proxy — measured from its own latency probes"
    sudo journalctl -u dnscrypt-proxy --no-pager | grep -E 'rtt|lowest initial latency' | tail -20
    printf '\n  Server currently serving 127.0.0.1:\n'
    python3 "$DNSQ" query 127.0.0.1 cloudflare.com A
    pause
}

# ═══ 4. preset & manual DNS ═════════════════════════════════════════════
apply_dns() {   # servers  [DoT hostname]  [flags]
    local servers=$1 host=${2-} flags=${3-} target dnsline=""
    target=$(printf '%s\n' \
        "󰒓  systemd-resolved (global — applies everywhere)" \
        "󰖩  This connection only ($(active_con))" \
      | "${FZF[@]}" --prompt "  apply to ❯ ") || return

    case "$target" in
        *global*)
            local usedot=no
            if [ -n "$host" ]; then
                if [ "$flags" = enc ]; then
                    usedot=yes                       # no plain option — it would break DNS
                elif yn "use DNS-over-TLS to $host?"; then
                    usedot=yes
                fi
            fi
            if [ "$usedot" = yes ]; then
                for ip in $servers; do dnsline+="${ip}#${host} "; done
                rset DNSOverTLS yes
            else
                dnsline="$servers "
                rset DNSOverTLS no
            fi
            rset DNS "${dnsline% }"
            apply_resolved
            pause "resolved global DNS = ${dnsline% }$([ "$usedot" = yes ] && echo '  (DoT)')" ;;
        *connection*)
            if [ "$flags" = enc ]; then
                pause "this provider only answers over DoT/DoH — NetworkManager can only set
  plain DNS, so it would break resolution. Apply it globally instead."
                return
            fi
            local con; con=$(active_con)
            [ -z "$con" ] && { pause "no active connection"; return; }
            sudo nmcli con mod "$con" ipv4.dns "$servers" ipv4.ignore-auto-dns yes
            sudo nmcli con up "$con" >/dev/null 2>&1
            pause "$con → $servers" ;;
    esac
}

preset_dns() {
    local sel p
    sel=$(preset_menu | "${FZF[@]}" --prompt "  preset DNS ❯ " \
            --header "these set the upstream; encryption depends on resolver mode") || return
    p=$(preset_find "$sel")
    apply_dns "$(printf '%s' "$p" | cut -d'|' -f2)" \
              "$(printf '%s' "$p" | cut -d'|' -f3)" \
              "$(printf '%s' "$p" | cut -d'|' -f4)"
}

manual_dns() {
    local servers host
    printf '  DNS servers, space separated (IPv4/IPv6): '; read -r servers
    [ -z "$servers" ] && return
    printf '  DoT hostname (optional, empty = plain): '; read -r host
    apply_dns "$servers" "$host"
}

# ═══ 5. systemd-resolved ════════════════════════════════════════════════
resolved_menu() {
    local sel v
    while true; do
        sel=$(printf '%s\n' \
            "󰩰  DNSOverTLS:      $(rget DNSOverTLS)" \
            "󰒃  DNSSEC:          $(rget DNSSEC)" \
            "󰆼  Cache:           $(rget Cache)" \
            "󰑟  DNS (global):    $(rget DNS)" \
            "󰑟  FallbackDNS:     $(rget FallbackDNS)" \
            "󰀂  MulticastDNS / LLMNR" \
            "󰏫  Edit drop-in" \
            "󰑓  Restart systemd-resolved" \
            "󰌍  Back" \
          | "${FZF[@]}" --prompt "  systemd-resolved ❯ " \
                --header "drop-in: $RDROP") || return
        case "$sel" in
            *DNSOverTLS*) v=$(printf '%s\n' no opportunistic yes | "${FZF[@]}" --prompt "  DNSOverTLS ❯ " \
                                --header "yes breaks plain upstreams (incl. dnscrypt on 127.0.0.1)") \
                            && { rset DNSOverTLS "$v"; apply_resolved; pause "DNSOverTLS=$v"; } ;;
            *DNSSEC*)     v=$(printf '%s\n' no allow-downgrade yes | "${FZF[@]}" --prompt "  DNSSEC ❯ ") \
                            && { rset DNSSEC "$v"; apply_resolved; pause "DNSSEC=$v"; } ;;
            *Cache*)      v=$(printf '%s\n' yes no no-negative | "${FZF[@]}" --prompt "  Cache ❯ ") \
                            && { rset Cache "$v"; apply_resolved; pause "Cache=$v"; } ;;
            *"DNS (global)"*)  manual_dns ;;
            *FallbackDNS*)
                printf '  FallbackDNS (space separated, empty = built-in): '; read -r v
                rset FallbackDNS "$v"; apply_resolved; pause "FallbackDNS=${v:-default}" ;;
            *Multicast*)
                v=$(printf '%s\n' "MulticastDNS=yes" "MulticastDNS=no" "LLMNR=yes" "LLMNR=no" \
                    | "${FZF[@]}" --prompt "  discovery ❯ ") \
                  && { rset "${v%%=*}" "${v##*=}"; apply_resolved; pause "$v"; } ;;
            *Edit*)       sudo "${EDITOR:-nano}" "$RDROP"; apply_resolved ;;
            *Restart*)    apply_resolved; pause "restarted" ;;
            *Back*|"")    return ;;
        esac
    done
}

# ═══ 6. tests & repair ══════════════════════════════════════════════════
test_menu() {
    local sel name
    while true; do
        sel=$(printf '%s\n' \
            "󰍉  Look up a name" \
            "󰓅  Benchmark all preset resolvers" \
            "󰈻  Leak test  — which resolver does the world see?" \
            "󰋼  Compare local resolvers  (resolved / dnscrypt)" \
            "󰩹  Flush all DNS caches" \
            "󰐊  Listening on port 53" \
            "󰈙  resolvectl statistics" \
            "󰌍  Back" \
          | "${FZF[@]}" --prompt "  test ❯ ") || return
        case "$sel" in
            *"Look up"*)
                printf '  name [github.com]: '; read -r name; name=${name:-github.com}
                printf '  type [A]: '; read -r t; t=${t:-A}
                clear; head2 "$name  ($t)"
                python3 "$DNSQ" query 127.0.0.53 "$name" "$t"
                pause ;;
            *Benchmark*)
                clear; head2 "latency — lower is better (plain UDP, from this network)"
                local args=() label servers host flags
                while IFS='|' read -r label servers host flags; do
                    [ "$flags" = enc ] && continue     # no plain endpoint to time
                    args+=("$(printf '%s' "$label" | sed 's/ *—.*//; s/ *$//')=$(printf '%s' "$servers" | awk '{print $1}')")
                done < <(printf '%s\n' "${PRESETS[@]}")
                python3 "$DNSQ" bench cloudflare.com "${args[@]}"
                printf '\n  encrypted-only providers (Mullvad, dns0.eu) are excluded — no plain endpoint.\n'
                pause ;;
            *Leak*)
                clear; head2 "who answers for you"
                python3 "$DNSQ" who
                printf '\n'
                curl -s --max-time 10 https://www.cloudflare.com/cdn-cgi/trace \
                    | grep -E '^(ip|loc)=' | sed 's/^/  /'
                pause ;;
            *Compare*)
                clear; head2 "same query, both local resolvers"
                for s in 127.0.0.53 127.0.0.1; do
                    printf '  \033[1m%s\033[0m\n' \
                        "$(case $s in 127.0.0.53) echo 'systemd-resolved (stub)';; \
                                      *)          echo 'dnscrypt-proxy';; esac)"
                    python3 "$DNSQ" query "$s" cloudflare.com A
                    printf '\n'
                done
                pause ;;
            *Flush*)
                sudo resolvectl flush-caches
                systemctl is-active --quiet dnscrypt-proxy && sudo systemctl restart dnscrypt-proxy
                pause "caches flushed" ;;
            *port\ 53*)  clear; head2 "port 53"; sudo ss -lntup 'sport = :53' | sed 's/^/  /'; pause ;;
            *statistics*) clear; head2 "resolvectl statistics"; resolvectl statistics | sed 's/^/  /'; pause ;;
            *Back*|"")   return ;;
        esac
    done
}

health_check() {
    clear; head2 "health check"
    local bad=0

    if [ -L /etc/resolv.conf ]; then
        if [ -e /etc/resolv.conf ]; then
            printf '  ✓ %s\n' "/etc/resolv.conf → $(readlink -f /etc/resolv.conf)"
        else
            printf '  ✗ %s\n' "/etc/resolv.conf is a DANGLING symlink"; bad=1
        fi
    else
        printf '  ✗ %s\n' "/etc/resolv.conf is a regular file, not the resolved symlink"; bad=1
    fi

    grep -q '^nameserver' /etc/resolv.conf 2>/dev/null \
        && printf '  ✓ %s\n' "resolv.conf has a nameserver line" \
        || { printf '  ✗ %s\n' "resolv.conf has NO nameserver line"; bad=1; }

    if ! dns_reaches; then
        printf '  ✗ %s\n' "DNS is not resolving — the encrypted-DNS chain is not working"; bad=1
    fi

    local nmdns; nmdns=$(grep -hs '^dns=' /etc/NetworkManager/conf.d/*.conf | head -1)
    [ "$nmdns" = "dns=systemd-resolved" ] \
        && printf '  ✓ %s\n' "NetworkManager feeds systemd-resolved" \
        || { printf '  ✗ %s\n' "NetworkManager dns setting is '${nmdns:-unset}'"; bad=1; }

    for u in systemd-resolved NetworkManager; do
        systemctl is-active --quiet $u \
            && printf '  ✓ %s\n' "$u running" \
            || { printf '  ✗ %s\n' "$u NOT running"; bad=1; }
    done

    if [ "$(rget DNSOverTLS)" = yes ] && [ "$(rget DNS)" = "127.0.0.1" ]; then
        printf '  ✗ %s\n' "DNSOverTLS=yes with a plain local upstream — this WILL fail"; bad=1
    fi

    local n; n=$(sudo ss -lntH 'sport = :53' 2>/dev/null | awk '{print $4}' | sort -u | wc -l)
    printf '  ℹ %s\n' "$n listener(s) on port 53"

    printf '\n'
    if [ "$bad" = 0 ]; then
        printf '  \033[32mall good\033[0m\n'; pause; return
    fi
    if yn "repair the failed items?"; then
        sudo ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
        sudo mkdir -p /etc/NetworkManager/conf.d
        printf '[main]\ndns=systemd-resolved\nrc-manager=unmanaged\n' \
            | sudo tee /etc/NetworkManager/conf.d/dns.conf >/dev/null
        sudo systemctl daemon-reload
        sudo systemctl restart systemd-resolved
        sudo systemctl reload NetworkManager
        sleep 2
        pause "repaired — re-run the health check to confirm"
    fi
}

# ── preview hook for fzf (must come after describe()) ───────────────────
if [ "${1-}" = "--describe" ]; then describe "${2-}"; exit 0; fi

# ═══ main ═══════════════════════════════════════════════════════════════
while true; do
    choice=$(printf '%s\n' \
        "󰇧  Status / chain" \
        "󰒓  Resolver mode        ($(current_mode_label))" \
        "󰦝  dnscrypt-proxy       ($(dc_on))" \
        "󰩠  Preset DNS servers" \
        "󰌌  Manual DNS entry" \
        "󰑟  systemd-resolved settings" \
        "󰙨  Test & diagnose" \
        "󰜉  Health check & repair" \
        "󰌍  Back" \
      | "${FZF[@]}" --prompt "  DNS  " \
            --header "encrypted DNS, resolvers, presets and diagnostics") || break
    case "$choice" in
        *Status*)           status_view ;;
        *"Resolver mode"*)  resolver_mode ;;
        *dnscrypt*)         dnscrypt_menu ;;
        *Preset*)           preset_dns ;;
        *Manual*)           manual_dns ;;
        *systemd-resolved*) resolved_menu ;;
        *Test*)             test_menu ;;
        *Health*)           health_check ;;
        *Back*|"")          break ;;
    esac
done
