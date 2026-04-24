#!/bin/bash
# TUI clipboard geçmiş — cliphist list → fzf → wl-copy.

set -eu

export FZF_DEFAULT_OPTS='
    --prompt  clip>\040
    --pointer ▶
    --height  100%
    --layout  reverse
    --border  none
    --info    inline
    --color   gutter:-1,bg:-1,bg+:-1,fg+:4:bold,hl+:4:bold,hl:4,prompt:2:bold,pointer:2,info:8
'

cliphist list | fzf --no-sort | cliphist decode | wl-copy
