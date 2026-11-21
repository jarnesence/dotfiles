# dotfiles — Hyprland terminal-zen

<p>
  <img src="https://img.shields.io/badge/Arch%20Linux-Hyprland-231f28?style=flat-square&logo=archlinux&logoColor=f3b8c8" alt="Arch Linux Hyprland">
  <img src="https://img.shields.io/badge/Config-Lua%20(hl.*)-231f28?style=flat-square&logo=lua&logoColor=f3b8c8" alt="Lua">
  <img src="https://img.shields.io/badge/Setup-Claude%20Code%20%7C%20AGY-231f28?style=flat-square&logoColor=f3b8c8" alt="Claude Code or AGY">
</p>

A minimal desktop on **Arch Linux + Hyprland** (Lua config via `hl.*` API) where every interactive surface is an `fzf` TUI. Colors are dynamically generated from the active wallpaper using `matugen` (Hyprland borders, `kitty`, `eww`, GTK3/4, and `mako` all share the exact same palette).

![wallpaper](wallpaper/z4.png)

## Installation — Don't Install It Yourself, Let an Agent Build It

There are no brittle one-click install scripts here that break on different hardware.
Install **[Claude Code](https://docs.anthropic.com/en/docs/claude-code)** or **[Antigravity (`agy`)](https://antigravity.google)** first, point it at this repository, and let it detect your machine's hardware (GPU, CPU, battery, Wi-Fi, display resolution, audio) and configure the entire system for you:

```sh
git clone https://github.com/jarnesence/dotfiles ~/dotfiles
cd ~/dotfiles

# With Claude Code:
claude "Read INSTALL.md and set up this machine completely"

# Or with Antigravity CLI (agy):
agy "Read INSTALL.md and set up this machine completely"
```

Detailed steps, conditional system settings, and exclusions: [INSTALL.md](INSTALL.md).

## Structure

```
home/        $HOME mirror (tokenized with @HOME@/@USER@) — hypr, kitty, eww, matugen, zsh, TUIs…
system/      / mirror — DNS chain (resolved → dnscrypt), power/battery services, sysctl, zram…
packages/    base · apps · aur · flatpak · dev (optional)
wallpaper/   active wallpaper
INSTALL.md   AI agent installation specification
```

## Keybinds (Summary)

`Super+T` terminal · `Super+Space` launcher · `Super+,` settings · `Super+B` tray ·
`Super+N` Spotify · `Super+.` wallpaper · `Super+Shift+Q` power menu · `Super+S` screenshot.
Full list in `INSTALL.md` §8.

MIT.
