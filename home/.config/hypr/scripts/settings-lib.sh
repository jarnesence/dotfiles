#!/usr/bin/env bash
# ╭──────────────────────────────────────────────────────────────────────╮
# │  Shared UI for the settings TUIs.                                     │
# │                                                                       │
# │  Every menu row is "token<US>visible text": fzf shows column 2 and we │
# │  dispatch on column 1. Matching an exact token instead of a substring │
# │  of the label means labels can be reworded or contain each other      │
# │  ("Connect" / "Disconnect") without the dispatch silently misfiring.  │
# ╰──────────────────────────────────────────────────────────────────────╯

US=$'\x1f'
SCRIPTS=@HOME@/.config/hypr/scripts

FZF_BASE=(--height 100% --layout=reverse --border=none --info=inline --cycle --no-sort --ansi)
HINT="Enter: select   ·   Esc: back"

# ── row builders ────────────────────────────────────────────────────────
# r TOKEN TEXT                     one menu row
# item TOKEN ICON LABEL [VALUE]    aligned row: icon, padded label, value
# sep                              non-selectable-looking divider
r()    { printf '%s%s%s\n' "$1" "$US" "$2"; }
item() { printf '%s%s%s  %-26s \033[2m%s\033[0m\n' "$1" "$US" "$2" "$3" "${4-}"; }
sep()  { printf '%s%s\033[2m%s\033[0m\n' '-' "$US" "────────────────────────────────────────────────"; }

# ── pickers ─────────────────────────────────────────────────────────────
# pick PROMPT HEADER ROWS...       -> selected token ("" if cancelled)
pick() {
    local prompt=$1 header=$2; shift 2
    printf '%s\n' "$@" \
      | fzf "${FZF_BASE[@]}" --prompt "$prompt" --header "$header" \
            --delimiter "$US" --with-nth 2 \
      | cut -d "$US" -f1
}

# pick_many PROMPT HEADER ROWS...  -> selected tokens, one per line
pick_many() {
    local prompt=$1 header=$2; shift 2
    printf '%s\n' "$@" \
      | fzf "${FZF_BASE[@]}" --multi --prompt "$prompt" --header "$header" \
            --delimiter "$US" --with-nth 2 \
      | cut -d "$US" -f1
}

# choose PROMPT HEADER LINES...    -> plain line picker (no token column)
choose() {
    local prompt=$1 header=$2; shift 2
    printf '%s\n' "$@" | fzf "${FZF_BASE[@]}" --prompt "$prompt" --header "$header"
}

# ── prompts ─────────────────────────────────────────────────────────────
confirm() {                       # confirm "Forget qweif"
    local what=$1
    [ "$(pick "  $what?  " "Enter: confirm   ·   Esc: cancel" \
         "$(r no  "󰜺  No, cancel")" \
         "$(r yes "  Yes, $what")")" = yes ]
}

ask() {                           # ask "New hostname" [default] -> $ANSWER
    local q=$1 def=${2-}
    printf '  %s%s: ' "$q" "${def:+ [$def]}"
    read -r ANSWER
    [ -z "$ANSWER" ] && ANSWER=$def
    [ -n "$ANSWER" ]
}

askpw() {                         # masked, with a visible length counter
    local q=$1 ch pw=''
    printf '  %s: ' "$q"
    while IFS= read -rsn1 ch; do
        case "$ch" in
            '')   break ;;
            $'\177'|$'\b')
                  [ -n "$pw" ] && { pw=${pw%?}; printf '\b \b'; } ;;
            *)    pw+=$ch; printf '•' ;;
        esac
    done
    printf '\n'
    PASSWORD=$pw
    [ -n "$pw" ]
}

# ── output ──────────────────────────────────────────────────────────────
say()   { printf '  %s\n' "$*"; }
ok()    { printf '  \033[32m%s\033[0m\n' "$*"; }
warn()  { printf '  \033[33m%s\033[0m\n' "$*"; }
err()   { printf '  \033[31m%s\033[0m\n' "$*"; }
dim()   { printf '  \033[2m%s\033[0m\n' "$*"; }
title() { printf '\n  \033[1m%s\033[0m\n  \033[2m%s\033[0m\n\n' "$1" "──────────────────────────────────────────────────────────────"; }
kv()    { printf '  %-24s %s\n' "$1" "${2:-—}"; }
pause() { printf '\n  \033[2m%s\033[0m ' "${1:-press Enter to continue}"; read -r _; }

# Pager. `less` is NOT installed on this machine — piping to it silently threw
# the output away and made menu entries look like they did nothing. Use
# whatever is actually present, and fall back to printing plus a keypress.
page() {
    if   command -v less >/dev/null 2>&1; then less -R
    elif command -v more >/dev/null 2>&1; then more
    else cat; printf '\n  \033[2mpress Enter to continue\033[0m '; read -r _ </dev/tty; fi
}

# show COMMAND...   run it, page the output, come back
show() { clear; title "$1"; shift; "$@" 2>&1 | sed 's/^/  /'; pause; }

# note TITLE [BODY]   desktop notification when a daemon is around
note() { command -v notify-send >/dev/null 2>&1 && notify-send -a Settings -t 3000 "$1" "${2-}"; }

# ── state probes shared by several menus ────────────────────────────────
onoff()      { [ "$1" = 0 ] && echo on || echo off; }
svc_state()  { systemctl is-active --quiet "$1" && echo active || echo inactive; }
wifi_radio() { nmcli radio wifi 2>/dev/null; }
bt_state()   { rfkill list bluetooth 2>/dev/null | grep -q 'Soft blocked: yes' && echo off || echo on; }
dnd_state()  { makoctl mode 2>/dev/null | grep -qx 'do-not-disturb' && echo on || echo off; }

# nmcli -t escapes ':' and '\' inside fields; undo it
unesc() { sed 's/\\:/:/g; s/\\\\/\\/g'; }

# ── persisting Hyprland settings ────────────────────────────────────────
HYPRCONF=@HOME@/.config/hypr/hyprland.lua

# Reading options: `hyprctl getoption` prints a typed prefix, and not always a
# scalar — gaps come back as "css gap data: 5 5 5 5" and unset strings as
# "[[EMPTY]]". Normalise all of that to a bare value.
opt() {
    local v
    v=$(hyprctl getoption "$1" 2>/dev/null | head -1)
    case "$v" in
        'css gap data: '*) printf '%s' "${v#css gap data: }" | awk '{print $1}' ;;
        *': [[EMPTY]]')    printf '' ;;
        *': '*)            printf '%s' "${v#*: }" ;;
        *)                 printf '%s' "$v" ;;
    esac
}

# Writing options: this config is Lua, and `hyprctl keyword` refuses to touch
# it ("keyword can't work with non-legacy parsers. Use eval."). Live changes
# go through hyprctl eval with the hl.* API instead.
#   hy_set  general:gaps_in 6        -> hl.config({ general = { gaps_in = 6 } })
#   hy_sets input:kb_layout "tr"     -> same, with the value quoted
hy_set() {
    local key=$1 val=$2 lua parts i
    IFS=: read -ra parts <<< "$key"
    lua=$val
    for (( i=${#parts[@]}-1; i>=0; i-- )); do
        lua="{ ${parts[i]//-/_} = $lua }"
    done
    hyprctl eval "hl.config($lua)" >/dev/null 2>&1
}
hy_sets() { hy_set "$1" "\"$2\""; }

# hy_monitor "output = \"eDP-1\", mode = ..."   apply one monitor rule live
hy_monitor() { hyprctl eval "hl.monitor({ $1 })" >/dev/null 2>&1; }

# lua_block NAME  <<'LUA' ... LUA
# Keeps one script-owned, clearly marked block at the end of hyprland.lua —
# appended last so it wins over the hand-written config above it. The file is
# backed up first and restored if Hyprland refuses to load the result, so a
# bad value can never leave the desktop with a broken config.
lua_block() {
    local name=$1 body backup out
    body=$(cat)
    backup=$(mktemp) || return 1
    cp "$HYPRCONF" "$backup"

    python3 - "$HYPRCONF" "$name" "$body" <<'PY'
import re, sys
path, name, body = sys.argv[1], sys.argv[2], sys.argv[3]
start, end = f"-- >>> settings:{name} >>>", f"-- <<< settings:{name} <<<"
text  = open(path, encoding="utf-8").read()
block = f"{start}\n{body}\n{end}\n"
pat   = re.compile(re.escape(start) + r".*?" + re.escape(end) + r"\n?", re.S)
open(path, "w", encoding="utf-8").write(
    pat.sub(lambda _: block, text) if pat.search(text)
    else text.rstrip("\n") + "\n\n" + block)
PY

    if ! command -v hyprctl >/dev/null 2>&1 || ! hyprctl version >/dev/null 2>&1; then
        rm -f "$backup"; warn "saved — Hyprland is not running, it will apply next start"; return 0
    fi
    out=$(hyprctl reload 2>&1)
    if printf '%s' "$out" | grep -qiE 'error|invalid|failed'; then
        cp "$backup" "$HYPRCONF"; hyprctl reload >/dev/null 2>&1
        rm -f "$backup"
        err "Hyprland rejected the change — rolled back"; dim "$out"; return 1
    fi
    rm -f "$backup"; ok "saved to hyprland.lua and reloaded"; return 0
}

# SSID of the connected AP without touching the radio. `nmcli device wifi
# list` forces a scan and blocks ~8 s; the active profile knows it in ~25 ms.
current_ssid() {
    local dev=${1-} prof
    [ -z "$dev" ] && return
    prof=$(nmcli -t -f GENERAL.CONNECTION device show "$dev" 2>/dev/null | cut -d: -f2- | unesc)
    [ -z "$prof" ] || [ "$prof" = '--' ] && return
    nmcli -t -f 802-11-wireless.ssid con show "$prof" 2>/dev/null | cut -d: -f2- | unesc
}

wifi_device() { nmcli -t -f DEVICE,TYPE device status 2>/dev/null | awk -F: '$2=="wifi"{print $1; exit}'; }
eth_device()  { nmcli -t -f DEVICE,TYPE device status 2>/dev/null | awk -F: '$2=="ethernet"{print $1; exit}'; }

