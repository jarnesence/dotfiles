#!/usr/bin/env bash
# Hyprland terminal-zen dotfiles installer for Arch Linux.
#
# Curl-to-bash:
#   curl -fsSL https://raw.githubusercontent.com/jarnesence/dotfiles/main/install.sh | bash
# Yerel:
#   ./install.sh [--with-plymouth] [--with-autologin]
#
# İlkeler: idempotent (tekrar çalıştırmak güvenli), desktop/laptop farkındalığı,
# GPU otomatik tespit, paket kurulumu --needed, tüm symlink'ler -sfn.

set -euo pipefail

REPO_OWNER="jarnesence"
REPO_NAME="dotfiles"
REPO_URL="https://github.com/${REPO_OWNER}/${REPO_NAME}.git"
DEST="$HOME/Claude/dotfiles"

WITH_PLYMOUTH=0
WITH_AUTOLOGIN=0
for arg in "$@"; do
    case "$arg" in
        --with-plymouth)  WITH_PLYMOUTH=1 ;;
        --with-autologin) WITH_AUTOLOGIN=1 ;;
        -h|--help)
            grep -E '^#' "$0" | head -12; exit 0 ;;
    esac
done

# ── helpers ─────────────────────────────────────
C_RESET=$'\033[0m'; C_OK=$'\033[1;32m'; C_WARN=$'\033[1;33m'
C_ERR=$'\033[1;31m'; C_INFO=$'\033[1;34m'; C_STEP=$'\033[1;35m'
step() { printf '\n%s▶ %s%s\n' "$C_STEP" "$*" "$C_RESET"; }
log()  { printf '%s==>%s %s\n' "$C_OK" "$C_RESET" "$*"; }
warn() { printf '%s[warn]%s %s\n' "$C_WARN" "$C_RESET" "$*"; }
err()  { printf '%s[err]%s %s\n' "$C_ERR" "$C_RESET" "$*" >&2; exit 1; }
info() { printf '%s[i]%s %s\n' "$C_INFO" "$C_RESET" "$*"; }

# ── sanity ─────────────────────────────────────
[ -f /etc/arch-release ] || err "Only Arch Linux supported."
[ "$(id -u)" -ne 0 ]     || err "Don't run as root. Use a user with sudo."
command -v sudo >/dev/null || err "sudo not installed."

# ── phase 1: bootstrap prereqs ─────────────────
step "Phase 1/13 · prerequisites"
sudo pacman -Sy --noconfirm --needed git base-devel curl rsync git-lfs

# ── phase 2: clone repo (for curl-to-bash) ─────
step "Phase 2/13 · clone repo"
if [ ! -d "$DEST/.git" ]; then
    mkdir -p "$(dirname "$DEST")"
    if [ -d "$DEST" ] && [ -n "$(ls -A "$DEST" 2>/dev/null)" ]; then
        backup="${DEST}.bak-$(date +%s)"
        warn "$DEST non-empty — moving to $backup"
        mv "$DEST" "$backup"
    fi
    git clone "$REPO_URL" "$DEST"
fi
cd "$DEST"
git lfs install --local >/dev/null 2>&1 || true
git lfs pull          >/dev/null 2>&1 || true

# ── phase 3: paru (AUR helper) ─────────────────
step "Phase 3/13 · paru (AUR helper)"
if ! command -v paru >/dev/null 2>&1; then
    tmp=$(mktemp -d)
    git clone --depth 1 https://aur.archlinux.org/paru.git "$tmp"
    (cd "$tmp" && makepkg -si --noconfirm)
    rm -rf "$tmp"
else
    info "paru already installed"
fi

# ── phase 4: GPU detection + driver ────────────
step "Phase 4/13 · GPU detection"
if [ -x "$DEST/install/gpu-detect.sh" ]; then
    bash "$DEST/install/gpu-detect.sh" install || warn "gpu-detect.sh failed (non-fatal)"
fi

# ── phase 5: official packages ─────────────────
step "Phase 5/13 · official packages"
if [ -f "$DEST/packages/base.pkglist" ]; then
    mapfile -t pkgs < <(grep -Ev '^(#|$)' "$DEST/packages/base.pkglist")
    [ "${#pkgs[@]}" -gt 0 ] && sudo pacman -S --noconfirm --needed "${pkgs[@]}"
fi

# ── phase 6: AUR packages ──────────────────────
step "Phase 6/13 · AUR packages"
if [ -f "$DEST/packages/aur.pkglist" ]; then
    mapfile -t pkgs < <(grep -Ev '^(#|$)' "$DEST/packages/aur.pkglist")
    [ "${#pkgs[@]}" -gt 0 ] && paru -S --noconfirm --needed "${pkgs[@]}"
fi

# ── phase 7: symlink configs ───────────────────
step "Phase 7/13 · symlink configs"
mkdir -p "$HOME/.config"
# Her dizin tek başına ~/.config/<name>'e symlink edilir
for d in hypr kitty waybar mako fastfetch fontconfig matugen opencode; do
    [ -d "$DEST/$d" ] || continue
    if [ -e "$HOME/.config/$d" ] && [ ! -L "$HOME/.config/$d" ]; then
        warn "\$HOME/.config/$d exists (not symlink) — moving to backup"
        mv "$HOME/.config/$d" "$HOME/.config/${d}.bak-$(date +%s)"
    fi
    ln -sfn "$DEST/$d" "$HOME/.config/$d"
done
# Shell init
ln -sfn "$DEST/zsh/zshrc"    "$HOME/.zshrc"
ln -sfn "$DEST/zsh/p10k.zsh" "$HOME/.p10k.zsh"
[ -f "$DEST/bash/bashrc" ] && ln -sfn "$DEST/bash/bashrc" "$HOME/.bashrc" || true
# Wallpapers symlink
if [ ! -e "$HOME/Wallpapers" ] || [ -L "$HOME/Wallpapers" ]; then
    ln -sfn "$DEST/wallpapers" "$HOME/Wallpapers"
fi

# ── phase 8: oh-my-zsh ─────────────────────────
step "Phase 8/13 · oh-my-zsh + zsh default"
if [ ! -d "$HOME/.oh-my-zsh" ]; then
    RUNZSH=no CHSH=no sh -c \
        "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
fi
# Default shell zsh
if [ "${SHELL:-}" != "/usr/bin/zsh" ] && command -v zsh >/dev/null; then
    sudo chsh -s /usr/bin/zsh "$(id -un)" 2>/dev/null || warn "chsh failed — run manually"
fi

# ── phase 9: fontconfig + cache ────────────────
# Not: ~/.config/fontconfig zaten Phase 7'de $DEST/fontconfig'e symlink edildi,
# dolayısıyla fonts.conf ayrıca ele alınmasın (self-link hatası verir).
step "Phase 9/13 · fonts"
fc-cache -f >/dev/null 2>&1 || true

# ── phase 10: services ─────────────────────────
step "Phase 10/13 · enable services"
for svc in bluetooth.service NetworkManager.service sddm.service \
           snapper-timeline.timer snapper-cleanup.timer \
           power-profiles-daemon.service ufw.service; do
    systemctl list-unit-files "$svc" >/dev/null 2>&1 && \
        sudo systemctl enable "$svc" 2>/dev/null || true
done

# ── phase 11: laptop hardware ──────────────────
step "Phase 11/13 · laptop hardware detect"
if [ -x "$DEST/install/laptop-detect.sh" ]; then
    bash "$DEST/install/laptop-detect.sh" || warn "laptop-detect non-fatal failure"
fi

# ── phase 12: plymouth (opt-in) ────────────────
if [ "$WITH_PLYMOUTH" -eq 1 ]; then
    step "Phase 12/13 · plymouth (opt-in)"
    sudo pacman -S --noconfirm --needed plymouth
    if ! grep -q "plymouth" /etc/mkinitcpio.conf; then
        sudo sed -i 's/^HOOKS=(base udev /HOOKS=(base udev plymouth /' /etc/mkinitcpio.conf
    fi
    if [ -f /etc/kernel/cmdline ] && ! grep -q "quiet splash" /etc/kernel/cmdline; then
        sudo sed -i '1 s/$/ quiet splash/' /etc/kernel/cmdline
    fi
    sudo plymouth-set-default-theme -R spinner
else
    step "Phase 12/13 · plymouth (skipped — pass --with-plymouth to enable)"
fi

# ── phase 13: palette + themes + autologin ─────
step "Phase 13/13 · palette + generate-themes + autologin"
# Palette ilk kurulum
mkdir -p "$HOME/.config/palette" "$HOME/.config/hypr/scripts"
if [ ! -f "$HOME/.config/palette/palette.sh" ] && [ -d "$HOME/Wallpapers" ]; then
    first=$(find "$HOME/Wallpapers" -maxdepth 1 -type f \( -iname '*.mp4' -o -iname '*.mkv' -o -iname '*.png' -o -iname '*.jpg' \) | sort | head -1)
    if [ -n "$first" ]; then
        echo "$first" > "$HOME/.config/hypr/scripts/live-wallpaper.current"
        bash "$HOME/.config/hypr/scripts/dynamic-colors.sh" 2>/dev/null || true
    fi
fi
bash "$DEST/hypr/scripts/generate-themes.sh" 2>/dev/null || true

# Autologin (opt-in) — SDDM
if [ "$WITH_AUTOLOGIN" -eq 1 ]; then
    sudo install -Dm644 /dev/stdin /etc/sddm.conf.d/autologin.conf <<EOF
[Autologin]
User=$(id -un)
Session=hyprland
EOF
    sudo groupadd -f autologin
    sudo gpasswd -a "$(id -un)" autologin >/dev/null
fi

# ── done ───────────────────────────────────────
log ""
log "Installation complete."
echo
info "Next steps:"
info "  1. Reboot:             sudo reboot"
info "  2. Login → SDDM → Hyprland session"
info "  3. Keybinds: Super+T terminal · Super+Space launcher · Super+I settings TUI"
echo
info "Optional helpers:"
info "  bash $DEST/install/apply-boot-logo.sh <png>"
info "  bash $DEST/install/apply-plymouth-theme.sh <theme>"
info "  bash $DEST/update.sh            # pull + re-apply"
