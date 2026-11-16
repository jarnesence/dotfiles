#!/usr/bin/env bash
# ╭──────────────────────────────────────────────────────────────────────╮
# │  Network  —  Wi-Fi, IP and DNS, over nmcli.                           │
# │  Encrypted DNS lives in dns.sh.                                       │
# ╰──────────────────────────────────────────────────────────────────────╯
set -u
source @HOME@/.config/hypr/scripts/settings-lib.sh

# ── helpers ─────────────────────────────────────────────────────────────
bars() {
    local s=${1:-0}
    if   [ "$s" -ge 75 ]; then echo "▂▄▆█"
    elif [ "$s" -ge 50 ]; then echo "▂▄▆_"
    elif [ "$s" -ge 25 ]; then echo "▂▄__"
    else                       echo "▂___"; fi
}

saved_profiles() { nmcli -t -f NAME,TYPE con show | awk -F: '$2 ~ /wireless/' | sed 's/:[^:]*$//' | unesc; }
is_saved()       { saved_profiles | grep -Fxq "$1"; }

active_con_for() {
    nmcli -t -f DEVICE,NAME con show --active 2>/dev/null \
        | awk -F: -v d="$1" '$1==d{print substr($0, length(d)+2)}' | unesc | head -1
}

status_line() {
    local dev ssid ip eth line
    dev=$(wifi_device)
    line="󰖩  Wi-Fi: "
    if [ "$(wifi_radio)" != enabled ]; then
        line+="radio off"
    else
        ssid=$(current_ssid "$dev")
        if [ -n "$ssid" ]; then
            ip=$(nmcli -t -f IP4.ADDRESS device show "$dev" 2>/dev/null | cut -d: -f2- | head -1)
            line+="$ssid${ip:+   $ip}"
        else
            line+="not connected"
        fi
    fi
    eth=$(eth_device)
    [ -n "$eth" ] && line+="      󰈀  Ethernet: $(nmcli -t -f DEVICE,STATE device status | awk -F: -v d="$eth" '$1==d{print $2}')"
    printf '%s' "$line"
}

# ── connecting ──────────────────────────────────────────────────────────
# Ask for a password and connect, retrying while the AP rejects the secret.
connect_secured() {
    local ssid=$1 dev=$2 out
    while true; do
        askpw "Password for \"$ssid\"" || { say "cancelled"; return 1; }
        say "connecting…"
        if out=$(nmcli device wifi connect "$ssid" password "$PASSWORD" ifname "$dev" 2>&1); then
            ok "connected to $ssid"; return 0
        fi
        case "$out" in
            *[Ss]ecrets*|*[Pp]assword*|*not\ correct*|*802.1X\ supplicant*)
                err "wrong password"
                confirm "Try again" || return 1 ;;
            *)
                err "${out#Error: }"; return 1 ;;
        esac
    done
}

connect_ssid() {
    local ssid=$1 secured=$2 dev out
    dev=$(wifi_device) || true
    [ -z "$dev" ] && { err "no Wi-Fi device"; return 1; }

    if is_saved "$ssid"; then
        say "connecting to \"$ssid\"…"
        if out=$(nmcli con up id "$ssid" 2>&1); then ok "connected to $ssid"; return 0; fi
        warn "the saved profile failed: ${out#Error: }"
        [ "$secured" = yes ] && { confirm "Re-enter the password" && connect_secured "$ssid" "$dev"; return; }
        return 1
    fi

    if [ "$secured" = yes ]; then
        connect_secured "$ssid" "$dev"
    else
        say "connecting…"
        out=$(nmcli device wifi connect "$ssid" ifname "$dev" 2>&1) \
            && ok "connected to $ssid" || err "${out#Error: }"
    fi
}

wifi_list() {
    local dev rows=() sel ssid secured
    dev=$(wifi_device)
    [ -z "$dev" ] && { clear; err "no Wi-Fi device found"; pause; return; }

    if [ "$(wifi_radio)" != enabled ]; then
        confirm "Wi-Fi radio is off — turn it on" || return
        nmcli radio wifi on; sleep 1
    fi

    clear; title "Wi-Fi"; say "scanning…"
    nmcli device wifi rescan ifname "$dev" >/dev/null 2>&1
    sleep 2

    # --rescan no: the rescan above already ran; letting `list` scan again
    # costs another ~8 s for identical results.
    # nmcli lists one row per access point (BSSID). Dual-band routers and
    # mesh nodes broadcast the same SSID from several BSSIDs, which would show
    # one network as duplicate rows. A single NM profile already covers every
    # BSSID of an SSID (the driver roams between bands/APs on its own), so
    # merge by SSID: connected if any BSSID is in use, strongest signal,
    # union of bands.
    while IFS=$'\x1f' read -r inuse sig sec band ssid; do
        [ -z "$ssid" ] && continue
        local mark=' ' lock='  ' tag=''
        [ "$inuse" = '*' ] && mark='󰄬'
        [ -n "$sec" ] && [ "$sec" != '--' ] && lock=''
        is_saved "$ssid" && tag='saved'
        rows+=("$(printf '%s%s%s %s %s  %-28s \033[2m%-7s %s\033[0m' \
                  "$ssid" "$US" "$mark" "$(bars "$sig")" "$lock" "$ssid" "$band" "$tag")")
    done < <(nmcli -t -f IN-USE,SIGNAL,SECURITY,FREQ,SSID device wifi list ifname "$dev" --rescan no \
             | awk -F: '{ iu=$1; sig=$2+0; sec=$3; fr=$4+0; ssid=$0;
                          sub(/^[^:]*:[^:]*:[^:]*:[^:]*:/,"",ssid);
                          if (ssid=="") next;
                          if (!(ssid in best)) { order[++n]=ssid; best[ssid]=-1 }
                          if (iu=="*") use[ssid]="*";
                          if (sig>best[ssid]) { best[ssid]=sig; secs[ssid]=sec }
                          if (fr>=5925) b6[ssid]=1; else if (fr>=4900) b5[ssid]=1; else if (fr>0) b2[ssid]=1 }
                    END { for (i=1;i<=n;i++) { s=order[i]; bd="";
                            if (b2[s]) bd="2.4";
                            if (b5[s]) bd=bd (bd?"+":"") "5";
                            if (b6[s]) bd=bd (bd?"+":"") "6";
                            if (bd!="") bd=bd "G";
                            printf "%s\x1f%d\x1f%s\x1f%s\x1f%s\n", use[s], best[s], secs[s], bd, s } }' \
             | sort -t$'\x1f' -k2 -nr \
             | sed 's/\\:/:/g; s/\\\\/\\/g')

    [ ${#rows[@]} -eq 0 ] && { err "no networks in range"; pause; return; }

    sel=$(pick "  Wi-Fi ❯ " "Enter: connect   ·   Esc: back      󰄬 connected    locked" "${rows[@]}")
    [ -z "$sel" ] && return

    secured=no
    nmcli -t -f SSID,SECURITY device wifi list ifname "$dev" --rescan no \
        | sed 's/\\:/:/g' | awk -F: -v s="$sel" '$1==s && $2!="" && $2!="--"{f=1} END{exit !f}' && secured=yes

    clear; title "$sel"
    connect_ssid "$sel" "$secured"
    pause
}

hidden_network() {
    local dev out
    dev=$(wifi_device); [ -z "$dev" ] && { err "no Wi-Fi device"; pause; return; }
    clear; title "Hidden network"
    ask "SSID" || return
    local ssid=$ANSWER
    if askpw "Password (empty for an open network)"; then
        out=$(nmcli device wifi connect "$ssid" password "$PASSWORD" ifname "$dev" hidden yes 2>&1)
    else
        out=$(nmcli device wifi connect "$ssid" ifname "$dev" hidden yes 2>&1)
    fi
    [ $? -eq 0 ] && ok "connected to $ssid" || err "${out#Error: }"
    pause
}

# ── saved networks ──────────────────────────────────────────────────────
saved_menu() {
    local rows=() name sel act
    while true; do
        rows=()
        while read -r name; do
            [ -z "$name" ] && continue
            local auto prio tag=''
            auto=$(nmcli -t -f connection.autoconnect con show "$name" 2>/dev/null | cut -d: -f2)
            prio=$(nmcli -t -f connection.autoconnect-priority con show "$name" 2>/dev/null | cut -d: -f2)
            [ "$auto" = no ] && tag='autoconnect off' || tag="priority $prio"
            rows+=("$(printf '%s%s󰤨  %-30s \033[2m%s\033[0m' "$name" "$US" "$name" "$tag")")
        done < <(saved_profiles)

        [ ${#rows[@]} -eq 0 ] && { clear; say "no saved Wi-Fi networks"; pause; return; }
        rows+=("$(sep)" "$(r back "󰌍  Back")")

        sel=$(pick "  Saved networks ❯ " "Enter: manage   ·   Esc: back" "${rows[@]}")
        case "$sel" in back|'') return ;; -) continue ;; esac

        act=$(pick "  $sel ❯ " "$HINT" \
            "$(r up      "󰄬  Connect now")" \
            "$(r auto    "󰑓  Toggle autoconnect")" \
            "$(r prio    "󰒺  Set autoconnect priority")" \
            "$(r pw      "󰌆  Change password")" \
            "$(r ip      "󰩠  IP / DNS settings")" \
            "$(r forget  "󰅖  Forget this network")" \
            "$(r back    "󰌍  Back")")
        clear
        case "$act" in
            up)     title "$sel"; nmcli con up id "$sel" 2>&1 | sed 's/^/  /'; pause ;;
            auto)   local a; a=$(nmcli -t -f connection.autoconnect con show "$sel" | cut -d: -f2)
                    [ "$a" = yes ] && a=no || a=yes
                    nmcli con mod "$sel" connection.autoconnect "$a"
                    title "$sel"; ok "autoconnect: $a"; pause ;;
            prio)   title "$sel"; dim "higher wins when several networks are in range"
                    ask "Priority (integer, e.g. 10)" "0" && nmcli con mod "$sel" connection.autoconnect-priority "$ANSWER"
                    ok "priority: $ANSWER"; pause ;;
            pw)     title "$sel"
                    if askpw "New password"; then
                        nmcli con mod "$sel" wifi-sec.psk "$PASSWORD" && ok "password updated — reconnect to use it"
                    fi; pause ;;
            ip)     ip_settings "$sel" ;;
            forget) confirm "Forget \"$sel\"" && { nmcli con delete id "$sel" >/dev/null 2>&1; clear; title "Saved networks"; ok "forgot $sel"; pause; } ;;
        esac
    done
}

# ── IP configuration ────────────────────────────────────────────────────
ip_settings() {
    local con=$1 sel
    [ -z "$con" ] && { clear; err "no connection selected"; pause; return; }
    while true; do
        local m4 a4 g4 d4 m6
        m4=$(nmcli -t -f ipv4.method    con show "$con" 2>/dev/null | cut -d: -f2)
        a4=$(nmcli -t -f ipv4.addresses con show "$con" 2>/dev/null | cut -d: -f2)
        g4=$(nmcli -t -f ipv4.gateway   con show "$con" 2>/dev/null | cut -d: -f2)
        d4=$(nmcli -t -f ipv4.dns       con show "$con" 2>/dev/null | cut -d: -f2)
        m6=$(nmcli -t -f ipv6.method    con show "$con" 2>/dev/null | cut -d: -f2)

        sel=$(pick "  $con ❯ " "IPv4 $m4   ·   Esc: back" \
            "$(item dhcp   "󰓢" "IPv4 method"        "$m4")" \
            "$(item static "󰩠" "Static IP address"  "${a4:-—}")" \
            "$(item gw     "󰅧" "Gateway"            "${g4:-—}")" \
            "$(item dns    "󰮏" "DNS servers"        "${d4:-automatic}")" \
            "$(item m6     "󰩠" "IPv6 method"        "$m6")" \
            "$(sep)" \
            "$(r reset "󰜉  Reset to automatic (DHCP + auto DNS)")" \
            "$(r apply "󰌽  Apply now (reactivate connection)")" \
            "$(r back  "󰌍  Back")")
        clear
        case "$sel" in
            dhcp)   local v; v=$(choose "  IPv4 method ❯ " "$HINT" auto manual disabled link-local shared) \
                        && { nmcli con mod "$con" ipv4.method "$v"; title "$con"; ok "ipv4.method=$v"; pause; } ;;
            static) title "$con"
                    ask "IP address (e.g. 192.168.1.50)" || continue
                    local ip=$ANSWER; ask "Prefix length" "24"; local pfx=$ANSWER
                    ask "Gateway (empty to skip)"; local gw=$ANSWER
                    nmcli con mod "$con" ipv4.method manual ipv4.addresses "$ip/$pfx" ${gw:+ipv4.gateway "$gw"} 2>&1 | sed 's/^/  /'
                    ok "set — choose Apply to activate"; pause ;;
            gw)     title "$con"; ask "Gateway" "$g4" && nmcli con mod "$con" ipv4.gateway "$ANSWER"; pause ;;
            dns)    title "$con"; dim "space separated; empty = whatever DHCP hands out"
                    ask "DNS servers" "$d4"
                    if [ -z "$ANSWER" ]; then nmcli con mod "$con" ipv4.dns "" ipv4.ignore-auto-dns no
                    else nmcli con mod "$con" ipv4.dns "$ANSWER" ipv4.ignore-auto-dns yes; fi
                    ok "set — choose Apply to activate"; pause ;;
            m6)     local v; v=$(choose "  IPv6 method ❯ " "$HINT" auto dhcp manual ignore disabled link-local) \
                        && { nmcli con mod "$con" ipv6.method "$v"; title "$con"; ok "ipv6.method=$v"; pause; } ;;
            reset)  nmcli con mod "$con" ipv4.method auto ipv4.addresses "" ipv4.gateway "" \
                        ipv4.dns "" ipv4.ignore-auto-dns no
                    title "$con"; ok "reset — choose Apply to activate"; pause ;;
            apply)  title "$con"; nmcli con up "$con" 2>&1 | sed 's/^/  /'; pause ;;
            back|'') return ;;
        esac
    done
}

pick_connection() {
    local rows=() name type
    while IFS=: read -r name type; do
        rows+=("$(printf '%s%s󰌘  %-30s \033[2m%s\033[0m' "$name" "$US" "$name" "$type")")
    done < <(nmcli -t -f NAME,TYPE con show | awk -F: '$NF ~ /wireless|ethernet/ {t=$NF; sub(/:[^:]*$/,""); print $0":"t}' | unesc)
    [ ${#rows[@]} -eq 0 ] && { clear; say "no connections"; pause; return; }
    local sel; sel=$(pick "  Connection ❯ " "pick a profile to edit" "${rows[@]}")
    [ -n "$sel" ] && ip_settings "$sel"
}

# ── details ─────────────────────────────────────────────────────────────
details() {
    clear; title "Connection details"
    local dev; dev=$(ip route show default 2>/dev/null | awk '{print $5; exit}')
    kv "Default route via" "$(ip route show default | awk '{print $3" ("$5")"}' | head -1)"
    kv "Interface"        "$dev"
    kv "IPv4"             "$(nmcli -t -f IP4.ADDRESS device show "$dev" 2>/dev/null | cut -d: -f2- | paste -sd' ')"
    kv "IPv6"             "$(nmcli -t -f IP6.ADDRESS device show "$dev" 2>/dev/null | cut -d: -f2- | head -1)"
    kv "Gateway"          "$(nmcli -t -f IP4.GATEWAY device show "$dev" 2>/dev/null | cut -d: -f2-)"
    kv "DNS in use"       "$(resolvectl status 2>/dev/null | sed -n 's/.*Current DNS Server: //p' | paste -sd' ')"
    kv "MAC"              "$(cat "/sys/class/net/$dev/address" 2>/dev/null)"
    kv "MTU"              "$(cat "/sys/class/net/$dev/mtu" 2>/dev/null)"
    [ "$(wifi_device)" = "$dev" ] && {
        kv "Signal"       "$(nmcli -t -f IN-USE,SIGNAL device wifi list --rescan no | awk -F: '$1=="*"{print $2"%"; exit}')"
        kv "Rate"         "$(nmcli -t -f IN-USE,RATE device wifi list --rescan no | awk -F: '$1=="*"{print $2; exit}')"
    }
    pause
}

hotspot() {
    local dev; dev=$(wifi_device); [ -z "$dev" ] && { clear; err "no Wi-Fi device"; pause; return; }
    clear; title "Wi-Fi hotspot"
    dim "shares this machine's connection over Wi-Fi; disconnects you from the current AP"
    confirm "Start a hotspot" || return
    ask "Network name (SSID)" "$(hostnamectl hostname)" || return
    local ssid=$ANSWER
    askpw "Password (at least 8 characters)" || return
    if [ ${#PASSWORD} -lt 8 ]; then err "too short"; pause; return; fi
    nmcli device wifi hotspot ifname "$dev" ssid "$ssid" password "$PASSWORD" 2>&1 | sed 's/^/  /'
    ok "hotspot \"$ssid\" is up"
    pause
}

# ── main ────────────────────────────────────────────────────────────────
while true; do
    wdev=$(wifi_device); edev=$(eth_device)
    radio=$(wifi_radio)

    rows=(
        "$(item scan   "󰖩" "Wi-Fi networks"        "scan & connect")"
        "$(item saved  "󰋙" "Saved networks"        "$(saved_profiles | wc -l) saved")"
        "$(item hidden "󰘓" "Hidden network"        "connect by name")"
        "$(sep)"
        "$(item dns    "󰦝" "DNS & encrypted DNS"   "dnscrypt, presets, tests")"
        "$(item ipcfg  "󰩠" "IP configuration"      "DHCP or static")"
        "$(item info   "󰋼" "Connection details"    "")"
        "$(sep)"
        "$(item radio  "󰤨" "Wi-Fi radio"           "$radio")"
        "$(item plane  "󰀝" "Airplane mode"         "$( [ "$(nmcli radio all)" = "disabled" ] && echo on || echo off)")"
        "$(item spot   "󰢹" "Wi-Fi hotspot"         "share this connection")"
    )
    [ -n "$wdev" ] && rows+=("$(item disc "󰚦" "Disconnect Wi-Fi" "$wdev")")
    [ -n "$edev" ] && rows+=("$(item ethip "󰈀" "Ethernet settings" "$edev")")
    rows+=("$(sep)" "$(r nmtui "󰒓  Advanced (nmtui)")" "$(r back "󰌍  Back")")

    choice=$(pick "  Network  " "$(status_line)" "${rows[@]}")
    case "$choice" in
        scan)   wifi_list ;;
        saved)  saved_menu ;;
        hidden) hidden_network ;;
        dns)    "$SCRIPTS/dns.sh" ;;
        ipcfg)  pick_connection ;;
        info)   details ;;
        radio)  [ "$radio" = enabled ] && nmcli radio wifi off || nmcli radio wifi on ;;
        plane)  if [ "$(nmcli radio all)" = disabled ]; then nmcli radio all on; else nmcli radio all off; fi ;;
        spot)   hotspot ;;
        disc)   clear; title "Wi-Fi"; nmcli device disconnect "$wdev" 2>&1 | sed 's/^/  /'; pause ;;
        ethip)  ip_settings "$(active_con_for "$edev")" ;;
        netfix) "$SCRIPTS/net-reset.sh" ;;
        nmtui)  nmtui ;;
        -)      ;;
        back|'') break ;;
    esac
done
