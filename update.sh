#!/usr/bin/env bash
# update.sh — pull latest, re-symlink, install new packages, reload components.
# İdempotent. Yerel değişiklik varsa stash'e alınır.

set -euo pipefail

DEST="$HOME/Claude/dotfiles"
cd "$DEST"

C_OK=$'\033[1;32m'; C_WARN=$'\033[1;33m'; C_ERR=$'\033[1;31m'; C_RESET=$'\033[0m'
log()  { printf '%s==>%s %s\n' "$C_OK" "$C_RESET" "$*"; }
warn() { printf '%s[warn]%s %s\n' "$C_WARN" "$C_RESET" "$*"; }
err()  { printf '%s[err]%s %s\n' "$C_ERR" "$C_RESET" "$*" >&2; exit 1; }

log "Fetching upstream..."
git fetch --prune origin

LOCAL=$(git rev-parse HEAD)
REMOTE=$(git rev-parse '@{u}' 2>/dev/null || echo "")
[ -z "$REMOTE" ] && err "No upstream branch configured."

# Yerel değişiklikleri stash'le
if [ -n "$(git status --porcelain)" ]; then
    warn "Local changes detected — stashing"
    git status --short
    git stash push -u -m "update.sh auto-stash $(date -u +%Y%m%dT%H%M%S)"
fi

if [ "$LOCAL" = "$REMOTE" ]; then
    log "Already up to date (sha $(git rev-parse --short HEAD))."
else
    log "Pulling..."
    git pull --ff-only
    git lfs pull >/dev/null 2>&1 || true
fi

# Re-symlink (yeni dizin eklendiyse yakalanır)
log "Re-applying symlinks..."
for d in hypr kitty waybar mako fastfetch fontconfig matugen opencode; do
    [ -d "$DEST/$d" ] || continue
    ln -sfn "$DEST/$d" "$HOME/.config/$d"
done
ln -sfn "$DEST/zsh/zshrc"    "$HOME/.zshrc"
ln -sfn "$DEST/zsh/p10k.zsh" "$HOME/.p10k.zsh"
[ -f "$DEST/bash/bashrc" ] && ln -sfn "$DEST/bash/bashrc" "$HOME/.bashrc" || true
[ -f "$DEST/fontconfig/fonts.conf" ] && \
    ln -sfn "$DEST/fontconfig/fonts.conf" "$HOME/.config/fontconfig/fonts.conf"

# Paket senkronizasyonu (yeni pkg list girdileri için)
if [ -f "$DEST/packages/base.pkglist" ]; then
    log "Syncing official packages..."
    mapfile -t pkgs < <(grep -Ev '^(#|$)' "$DEST/packages/base.pkglist")
    [ "${#pkgs[@]}" -gt 0 ] && sudo pacman -S --noconfirm --needed "${pkgs[@]}" || true
fi
if [ -f "$DEST/packages/aur.pkglist" ] && command -v paru >/dev/null; then
    log "Syncing AUR packages..."
    mapfile -t pkgs < <(grep -Ev '^(#|$)' "$DEST/packages/aur.pkglist")
    [ "${#pkgs[@]}" -gt 0 ] && paru -S --noconfirm --needed "${pkgs[@]}" || true
fi

# Tema regeneration + reload
log "Regenerating themes & reloading..."
bash "$DEST/hypr/scripts/generate-themes.sh" 2>/dev/null || true
fc-cache -f >/dev/null 2>&1 || true
hyprctl reload >/dev/null 2>&1 || true
pkill -SIGUSR2 waybar 2>/dev/null || true

log "Updated to $(git rev-parse --short HEAD)."
