#!/usr/bin/env bash
# ╭────────────────────────────────────────────────────────────╮
# │  TUI clipboard history (cliphist + fzf)                    │
# │  Invoked by Super+V inside  kitty --class tui-clipboard.   │
# ╰────────────────────────────────────────────────────────────╯
set -euo pipefail

if ! command -v cliphist >/dev/null 2>&1; then
    echo "cliphist not installed."
    read -rn1 -p "Press any key..."
    exit 1
fi

sel=$(cliphist list \
    | fzf --delimiter=$'\t' --with-nth=2.. \
          --prompt="clip ❯ " --pointer="▶" --layout=reverse \
          --height=100% --border=none --info=inline --cycle \
          --header="Enter: copy   ·   Del: delete   ·   Ctrl+X: wipe all   ·   Esc: close" \
          --preview='cliphist decode <<< {} 2>/dev/null | head -c 2000' \
          --preview-window='down:35%:wrap' \
          --bind='del:execute-silent(cliphist delete <<< {})+reload(cliphist list)' \
          --bind='ctrl-x:execute-silent(cliphist wipe)+reload(cliphist list)') || exit 0

[ -n "$sel" ] && cliphist decode <<< "$sel" | setsid wl-copy >/dev/null 2>&1
