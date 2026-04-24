#!/bin/bash
# TUI app launcher — kitty --class=tui-launcher içinde fzf.
# .desktop dosyalarını adla listeler, seçilenini gio launch ile açar.

set -eu

FZF_OPTS='
    --prompt  run>\040
    --pointer ▶
    --marker  +
    --height  100%
    --layout  reverse
    --border  none
    --info    inline
    --color   gutter:-1,bg:-1,bg+:-1,fg+:4:bold,hl+:4:bold,hl:4,prompt:2:bold,pointer:2,marker:1,info:8
'
export FZF_DEFAULT_OPTS="$FZF_OPTS"

# .desktop dosyalarını oku → "Name\tpath" formatında tablo
list_desktops() {
    for dir in /usr/share/applications /usr/local/share/applications "$HOME/.local/share/applications"; do
        [ -d "$dir" ] || continue
        for f in "$dir"/*.desktop; do
            [ -f "$f" ] || continue
            # NoDisplay=true olanları atla
            grep -q '^NoDisplay=true' "$f" && continue
            name=$(awk -F= '/^Name=/ {print $2; exit}' "$f")
            [ -n "$name" ] && printf '%s\t%s\n' "$name" "$f"
        done
    done | sort -uf
}

pick=$(list_desktops | fzf --with-nth=1 --delimiter=$'\t') || exit 0
desktop=${pick##*$'\t'}
[ -n "$desktop" ] && gio launch "$desktop" >/dev/null 2>&1 &
