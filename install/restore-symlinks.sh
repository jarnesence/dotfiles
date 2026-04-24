#!/usr/bin/env bash
# restore-symlinks.sh
# Bir başka tool/elle dosyalar kopyalandıysa → ~/.config'teki kopyaları sil,
# dotfiles'a symlink'i yeniden kur. Sonra generate-themes + waybar reload.
# İdempotent: tekrar çalıştırmak zararsız.

set -euo pipefail

DEST="$HOME/Claude/dotfiles"
C_OK=$'\033[1;32m'; C_WARN=$'\033[1;33m'; C_RESET=$'\033[0m'
log()  { printf '%s==>%s %s\n' "$C_OK"   "$C_RESET" "$*"; }
warn() { printf '%s[warn]%s %s\n' "$C_WARN" "$C_RESET" "$*"; }

[ -d "$DEST" ] || { echo "dotfiles not at $DEST"; exit 1; }
mkdir -p "$HOME/.config"

# ── Standart dizin symlink'leri ────────────────────────
# Bu dizinler TAMAMEN dotfiles tarafından yönetilir; ~/.config/<d> yerine
# simgesel link. Mevcut içerik (Gemini vb. kopyası) timestamp'li backup'a gider.
STAMP=$(date +%s)
for d in hypr kitty waybar mako fastfetch fontconfig matugen; do
    [ -d "$DEST/$d" ] || continue
    target="$HOME/.config/$d"
    if [ -L "$target" ]; then
        if [ "$(readlink "$target")" = "$DEST/$d" ]; then
            continue                       # zaten doğru — atla
        fi
        rm -f "$target"
    elif [ -d "$target" ]; then
        warn "$target düz dizin → backup: ${target}.bak-${STAMP}"
        mv "$target" "${target}.bak-${STAMP}"
    fi
    ln -sfn "$DEST/$d" "$target"
    log "symlink: $target → $DEST/$d"
done

# ── opencode özel: runtime state (node_modules vs.) KORUNUR ───────
# Sadece themes/ alt dizinini symlink et.
if [ -d "$DEST/opencode/themes" ]; then
    mkdir -p "$HOME/.config/opencode"
    target="$HOME/.config/opencode/themes"
    if [ -L "$target" ] && [ "$(readlink "$target")" = "$DEST/opencode/themes" ]; then
        :                                  # doğru, atla
    else
        [ -e "$target" ] && mv "$target" "${target}.bak-${STAMP}"
        ln -sfn "$DEST/opencode/themes" "$target"
        log "symlink: $target → $DEST/opencode/themes"
    fi
fi

# ── fastfetch config.jsonc → bir preset'e symlink (aktif tema) ────
# Varsayılan: groups-hypr. fastfetch-theme.sh ile değiştirilebilir.
FF_ACTIVE="$HOME/.config/fastfetch/config.jsonc"
if [ ! -L "$FF_ACTIVE" ] || [ ! -e "$FF_ACTIVE" ]; then
    PRESET="$DEST/fastfetch/presets/groups-hypr.jsonc"
    [ -f "$PRESET" ] && ln -sfn "$PRESET" "$FF_ACTIVE" && log "fastfetch preset: groups-hypr"
fi

# ── Shell init ─────────────────────────────────────────
ln -sfn "$DEST/zsh/zshrc"    "$HOME/.zshrc"
ln -sfn "$DEST/zsh/p10k.zsh" "$HOME/.p10k.zsh"
[ -f "$DEST/bash/bashrc" ] && ln -sfn "$DEST/bash/bashrc" "$HOME/.bashrc"

# ── Wallpapers ─────────────────────────────────────────
if [ -d "$DEST/wallpapers" ]; then
    if [ -L "$HOME/Wallpapers" ] || [ ! -e "$HOME/Wallpapers" ]; then
        ln -sfn "$DEST/wallpapers" "$HOME/Wallpapers"
    elif [ -d "$HOME/Wallpapers" ]; then
        warn "~/Wallpapers düz dizin — mevcut dosyalar kalır; dotfiles'a taşımak istersen el ile yap"
    fi
fi

# ── Chrome flags ──────────────────────────────────────
if [ -f "$DEST/chrome/chrome-flags.conf" ]; then
    ln -sfn "$DEST/chrome/chrome-flags.conf" "$HOME/.config/chrome-flags.conf"
fi

# ── Palette bootstrap: yoksa ilk wallpaper'dan üret ────
if [ ! -f "$HOME/.config/palette/palette.sh" ] && [ -d "$HOME/Wallpapers" ]; then
    first=$(find "$HOME/Wallpapers" -maxdepth 1 -type f \( -iname '*.mp4' -o -iname '*.mkv' -o -iname '*.png' -o -iname '*.jpg' \) | sort | head -1 || true)
    if [ -n "$first" ]; then
        mkdir -p "$HOME/.config/hypr/scripts" "$HOME/.config/palette"
        echo "$first" > "$HOME/.config/hypr/scripts/live-wallpaper.current"
        bash "$HOME/.config/hypr/scripts/dynamic-colors.sh" 2>/dev/null || true
    fi
fi

# ── Tema regenerate ────────────────────────────────────
bash "$DEST/hypr/scripts/generate-themes.sh" 2>/dev/null || true

# ── Waybar config render + reload ──────────────────────
if [ -x "$DEST/hypr/scripts/waybar-host-setup.sh" ]; then
    bash "$DEST/hypr/scripts/waybar-host-setup.sh" >/dev/null 2>&1 || true
fi
pkill -x waybar 2>/dev/null && sleep 0.3 || true
if command -v waybar >/dev/null 2>&1; then
    waybar >/tmp/waybar.log 2>&1 &
    disown
fi

# ── Hyprland reload (oturum varsa) ─────────────────────
hyprctl reload >/dev/null 2>&1 || true

log "Restore complete. Yeni sistemde reboot önerilir."
