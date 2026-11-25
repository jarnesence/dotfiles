#!/usr/bin/env bash
# ╭──────────────────────────────────────────────────────────────────────╮
# │  Security & Privacy  —  what is listening, who can get in, and keys.  │
# │  Read-heavy on purpose: it reports the real state instead of hiding   │
# │  it behind toggles that pretend to be a firewall.                     │
# ╰──────────────────────────────────────────────────────────────────────╯
set -u
source @HOME@/.config/hypr/scripts/settings-lib.sh

firewall_state() {
    local n
    n=$(sudo nft list ruleset 2>/dev/null | grep -c '^table') || n=0
    [ "${n:-0}" -eq 0 ] && { echo "no rules"; return; }
    sudo nft list ruleset 2>/dev/null | grep -qE 'policy drop' \
        && echo "$n tables, dropping" || echo "$n tables, permissive"
}

listening() {
    clear; title "Listening sockets"
    dim "anything on 0.0.0.0 or :: is reachable from the network"
    sudo ss -lntupH 2>/dev/null | awk '{printf "  %-6s %-24s %s\n", $1, $5, $7}' | sort -u
    pause
}

ssh_keys() {
    local sel rows=() f
    while true; do
        rows=()
        for f in "$HOME"/.ssh/*.pub; do
            [ -e "$f" ] || continue
            rows+=("$(printf '%s%s󰌆  %-24s \033[2m%s\033[0m' "$f" "$US" "$(basename "$f")" \
                      "$(ssh-keygen -lf "$f" 2>/dev/null | awk '{print $1"-bit "$4" "$3}')")")
        done
        [ ${#rows[@]} -eq 0 ] && rows=("$(r _none "no keys in ~/.ssh")")
        rows+=("$(sep)" "$(r _new "󰐕  Generate a new ed25519 key")" \
               "$(r _agent "󰌾  Keys loaded in the agent")" "$(r back "󰌍  Back")")

        sel=$(pick "  SSH keys ❯ " "Enter: show the public key   ·   Esc: back" "${rows[@]}")
        clear
        case "$sel" in
            _new)   title "New SSH key"
                    ask "File name" "id_ed25519" || continue
                    ask "Comment" "$(whoami)@$(hostnamectl hostname)"
                    ssh-keygen -t ed25519 -f "$HOME/.ssh/$ANSWER" -C "$ANSWER" 2>&1 | sed 's/^/  /'
                    pause ;;
            _agent) show "ssh-agent" ssh-add -l ;;
            _none|-) ;;
            back|'') return ;;
            *)      title "$(basename "$sel")"
                    fold -w 68 "$sel" | sed 's/^/  /'
                    command -v wl-copy >/dev/null && { wl-copy < "$sel"; ok "copied to the clipboard"; }
                    pause ;;
        esac
    done
}

overview() {
    clear; title "Security overview"
    kv "Firewall (nftables)" "$(firewall_state)"
    kv "Open to the network" "$(sudo ss -lntH 2>/dev/null | awk '$4 !~ /^127\.|^\[::1\]/ {n++} END{print n+0" sockets"}')"
    kv "SSH server"          "$(svc_state sshd)"
    kv "Screen lock"         "$(command -v hyprlock >/dev/null && echo hyprlock || echo 'none installed — screen off only')"
    kv "sudo"                "$(sudo -n true 2>/dev/null && echo 'passwordless (NOPASSWD)' || echo 'password required')"
    kv "Automatic login"     "$(grep -rqs '^ExecStart.*autologin' /etc/systemd/system/getty@*.service.d 2>/dev/null && echo yes || echo no)"
    printf '\n'
    dim "failed login attempts, last 24 h"
    journalctl -q --since '24 hours ago' _COMM=sudo -g 'authentication failure' --no-pager 2>/dev/null \
        | tail -5 | sed 's/^/  /' || true
    pause
}

while true; do
    choice=$(pick "  Security & Privacy  " "$HINT" \
        "$(item over  "󰦝" "Overview"          "")" \
        "$(item fw    "󰞀" "Firewall rules"    "$(firewall_state)")" \
        "$(item listen "󰛳" "Listening sockets" "")" \
        "$(sep)" \
        "$(item keys  "󰌆" "SSH keys"          "$(ls "$HOME"/.ssh/*.pub 2>/dev/null | wc -l) keys")" \
        "$(item gpg   "󰢬" "GPG keys"          "$(gpg --list-secret-keys --with-colons 2>/dev/null | grep -c '^sec') secret")" \
        "$(sep)" \
        "$(item lock  "󰷛" "Lock the screen now" "")" \
        "$(r back "󰌍  Back")")
    clear
    case "$choice" in
        over)   overview ;;
        fw)     show "nftables ruleset" sudo nft list ruleset ;;
        listen) listening ;;
        keys)   ssh_keys ;;
        gpg)    show "GPG keys" gpg --list-keys ;;
        lock)   hyprctl dispatch dpms off >/dev/null 2>&1; break ;;
        -)      ;;
        back|'') break ;;
    esac
done
