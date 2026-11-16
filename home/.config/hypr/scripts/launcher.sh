#!/usr/bin/env bash
# ╭────────────────────────────────────────────────────────────╮
# │  TUI application launcher                                    │
# │  fzf over .desktop entries; opens the choice via gtk-launch. │
# │  Invoked by Super+Space inside  kitty --class launcher.      │
# ╰────────────────────────────────────────────────────────────╯
set -euo pipefail

US=$'\x1f'   # unit separator: splits the display name from the desktop-id

dirs=(
    "$HOME/.local/share/applications"
    /usr/share/applications
    /usr/local/share/applications
    "$HOME/.local/share/flatpak/exports/share/applications"
    /var/lib/flatpak/exports/share/applications
)

# Emit "Display Name <US> desktop-id" for each .desktop (NoDisplay/Hidden and non-Application are skipped).
# First pick a SINGLE file per id (user dir first → its override wins), then inspect that file.
# This way a NoDisplay=true override in ~/.local/share actually hides the system entry.
collect() {
    local d f id
    declare -A pick
    for d in "${dirs[@]}"; do
        [ -d "$d" ] || continue
        for f in "$d"/*.desktop; do
            [ -e "$f" ] || continue
            id=$(basename "${f%.desktop}")
            [ -n "${pick[$id]:-}" ] && continue   # a higher-priority dir already won
            pick[$id]=$f
        done
    done
    for id in "${!pick[@]}"; do
        awk -v id="$id" -v US="$US" '
            /^\[/                   { de = ($0 == "[Desktop Entry]") }
            de && /^Name=/ && name==""  { sub(/^Name=/, ""); name=$0 }
            de && /^NoDisplay=true/  { skip=1 }
            de && /^Hidden=true/     { skip=1 }
            de && /^Type=/           { sub(/^Type=/, ""); type=$0 }
            END {
                if (name != "" && !skip && (type=="" || type=="Application"))
                    printf "%s%s%s\n", name, US, id
            }
        ' "${pick[$id]}"
    done
}

# sort by name (dedup is now done per-id inside collect)
sel=$(collect | sort -f \
    | fzf --delimiter="$US" --with-nth=1 \
          --prompt="run ❯ " --pointer="▶" --layout=reverse \
          --height=100% --border=none --info=inline \
          --cycle) || exit 0

id=${sel##*"$US"}
# setsid -f: keep the app alive after kitty closes (fully detach from the session)
[ -n "$id" ] && setsid -f gtk-launch "$id" >/dev/null 2>&1
