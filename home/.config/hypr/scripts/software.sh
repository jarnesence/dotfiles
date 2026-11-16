#!/usr/bin/env bash
# ╭──────────────────────────────────────────────────────────────────────╮
# │  Software & Updates  —  pacman/AUR through paru.                      │
# │  Anything that installs or removes asks first and shows paru's own    │
# │  output; nothing here runs unattended.                                │
# ╰──────────────────────────────────────────────────────────────────────╯
set -u
source @HOME@/.config/hypr/scripts/settings-lib.sh

CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/settings-updates"

repo_count() { checkupdates 2>/dev/null | wc -l; }
aur_count()  { paru -Qua 2>/dev/null | wc -l; }
orphans()    { pacman -Qdtq 2>/dev/null; }

count_cached() {                     # counting updates is slow; cache it 15 min
    if [ -f "$CACHE" ] && [ $(( $(date +%s) - $(stat -c %Y "$CACHE") )) -lt 900 ]; then
        cat "$CACHE"; return
    fi
    printf '%s repo · %s AUR' "$(repo_count)" "$(aur_count)" | tee "$CACHE"
}

list_updates() {
    clear; title "Available updates"
    say "checking…"
    local repo aur
    repo=$(checkupdates 2>/dev/null); aur=$(paru -Qua 2>/dev/null)
    clear; title "Available updates"
    printf '  \033[1mrepo (%s)\033[0m\n' "$(printf '%s' "$repo" | grep -c . )"
    printf '%s\n' "${repo:-  none}" | sed 's/^/  /' | head -60
    printf '\n  \033[1mAUR (%s)\033[0m\n' "$(printf '%s' "$aur" | grep -c . )"
    printf '%s\n' "${aur:-  none}" | sed 's/^/  /'
    rm -f "$CACHE"
    pause
}

search_install() {
    clear; title "Search packages"
    ask "Search for" || return
    local q=$ANSWER rows=() line name desc
    say "searching…"
    while IFS= read -r line; do
        name=${line%% *}
        rows+=("$(printf '%s%s󰏔  %s' "$name" "$US" "$line")")
    done < <(paru -Ss --sortby popularity "$q" 2>/dev/null | paste - - | sed 's/\t\+/  —  /' | head -60)
    [ ${#rows[@]} -eq 0 ] && { clear; err "nothing found for \"$q\""; pause; return; }
    local sel; sel=$(pick "  Install ❯ " "Enter: install   ·   Esc: back" "${rows[@]}")
    [ -z "$sel" ] && return
    sel=${sel#*/}                                   # strip repo/ prefix
    clear; title "Install $sel"
    confirm "Install $sel" || return
    paru -S --needed "$sel"
    pause
}

remove_pkg() {
    clear; title "Remove a package"
    ask "Package name (leave empty to browse explicitly installed)"
    local target=$ANSWER
    if [ -z "$target" ]; then
        target=$(pacman -Qeq 2>/dev/null | choose "  Remove ❯ " "explicitly installed packages") || return
    fi
    [ -z "$target" ] && return
    clear; title "Remove $target"
    pacman -Qi "$target" >/dev/null 2>&1 || { err "$target is not installed"; pause; return; }
    pactree -r "$target" 2>/dev/null | tail -n +2 | head -10 | sed 's/^/  needed by: /'
    confirm "Remove $target and its unused dependencies" || return
    sudo pacman -Rns "$target"
    pause
}

clean_menu() {
    local sel n
    while true; do
        n=$(orphans | wc -l)
        sel=$(pick "  Cleanup ❯ " "$HINT" \
            "$(item orph  "󰩹" "Orphaned packages"  "$n")" \
            "$(item cache "󰆼" "Package cache"      "$(du -sh /var/cache/pacman/pkg 2>/dev/null | cut -f1)")" \
            "$(item diff  "󰦓" "Config file updates" "pacdiff")" \
            "$(r back "󰌍  Back")")
        clear
        case "$sel" in
            orph)  if [ "$n" -eq 0 ]; then title "Cleanup"; ok "no orphans"; pause; continue; fi
                   title "Orphaned packages"; orphans | sed 's/^/  /'
                   confirm "Remove these $n packages" && { sudo pacman -Rns $(orphans); pause; } ;;
            cache) title "Package cache"
                   dim "keeps the 2 most recent versions of each package"
                   confirm "Clean the cache" && { sudo paccache -rk2 2>&1 | sed 's/^/  /'; pause; } ;;
            diff)  sudo DIFFPROG="${EDITOR:-nano}" pacdiff ;;
            back|'') return ;;
        esac
    done
}

while true; do
    choice=$(pick "  Software & Updates  " "$HINT" \
        "$(item list   "󰏔" "Available updates"   "$(count_cached)")" \
        "$(item up     "󰚰" "Update everything"   "paru -Syu")" \
        "$(item aur    "󰣇" "Update AUR only"     "$(aur_count) packages")" \
        "$(sep)" \
        "$(item search "󰍉" "Search & install"    "")" \
        "$(item rm     "󰆴" "Remove a package"    "")" \
        "$(item info   "󰋼" "Package information" "")" \
        "$(sep)" \
        "$(item clean  "󰩹" "Cleanup"             "orphans, cache, pacdiff")" \
        "$(item inst   "󰋚" "Explicitly installed" "$(pacman -Qeq 2>/dev/null | wc -l) packages")" \
        "$(r back "󰌍  Back")")
    clear
    case "$choice" in
        list)   list_updates ;;
        up)     title "System update"
                confirm "Update all packages now" || continue
                rm -f "$CACHE"; paru -Syu; pause ;;
        aur)    title "AUR update"; confirm "Update AUR packages" || continue
                rm -f "$CACHE"; paru -Sua; pause ;;
        search) search_install ;;
        rm)     remove_pkg ;;
        info)   title "Package information"
                ask "Package name" || continue
                clear; title "$ANSWER"
                pacman -Qi "$ANSWER" 2>/dev/null | sed 's/^/  /' \
                    || paru -Si "$ANSWER" 2>/dev/null | sed 's/^/  /' \
                    || err "not found"
                pause ;;
        clean)  clean_menu ;;
        inst)   pacman -Qeq | page ;;
        -)      ;;
        back|'') break ;;
    esac
done
