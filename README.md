# dotfiles — Hyprland terminal-zen rice

Tek kaynak palette (wallpaper → matugen → palette.sh), tüm app config'leri
`generate-themes.sh` aracılığıyla tek dosyadan üretilir. Cascadia Code NF
her yerde. Her interaktif yüzey bir TUI (kitty + fzf).

## Kurulum (fresh Arch → rice)

```sh
curl -fsSL https://raw.githubusercontent.com/jarnesence/dotfiles/main/install.sh | bash
```

Veya yerel:

```sh
git clone https://github.com/jarnesence/dotfiles ~/Claude/dotfiles
bash ~/Claude/dotfiles/install.sh
```

Opsiyonel bayraklar:
- `--with-plymouth`  — Plymouth boot splash (mkinitcpio hook + theme)
- `--with-autologin` — SDDM autologin (tek kullanıcılı cihazlar için)

Install script şunları yapar:
1. Bootstrap: `git base-devel curl rsync git-lfs`
2. Repo clone (curl-bash varyantı)
3. `paru` (AUR helper) kurulum
4. **GPU otomatik tespit** — nvidia-open / amdgpu / intel → uygun driver + hyprland env
5. Official paketler (`packages/base.pkglist`, 72 paket)
6. AUR paketleri (`packages/aur.pkglist`, 7 paket)
7. Config symlink'leri → `~/.config/`
8. `oh-my-zsh` + zsh default shell
9. Fontconfig + fc-cache
10. Services: bluetooth, NetworkManager, SDDM, snapper timer, power-profiles-daemon
11. **Laptop tespit** — ASUS Zenbook S16 dahil, chassis/vendor'a göre paket
12. Plymouth (opt-in)
13. İlk palette + tema generate

## Güncelleme

```sh
bash ~/Claude/dotfiles/update.sh
```

`git pull` + symlink yenileme + eksik paket kurulumu + tema regen + waybar/hyprland reload.
Yerel değişiklikler varsa stash'e alınır.

## Yapı

```
.
├── install.sh            — tek-tık kurulum
├── update.sh             — tek-tık güncelleme
├── packages/             — pacman + paru listesi
├── install/              — gpu-detect, laptop-detect, plymouth/boot-logo helper
├── hypr/                 — Hyprland config + scripts
├── waybar/               — status bar
├── kitty/                — terminal
├── mako/                 — notifications
├── fastfetch/            — system info preset (groups-hypr)
├── fontconfig/           — Cascadia Code NF system-wide
├── matugen/              — palette generation templates
├── opencode/             — opencode TUI themes
├── palette/              — (live: ~/.config/palette/palette.sh)
├── zsh/ · bash/          — shell init
└── wallpapers/           — video wallpapers (git-lfs)
```

## Temel kısayollar

| Bind | Aksiyon |
|---|---|
| `Super+T` | Terminal (kitty) |
| `Super+A` | Chrome |
| `Super+Space` | App launcher (TUI fzf) |
| `Super+V` | Clipboard history (TUI) |
| `Super+I` | Settings TUI (comprehensive) |
| `Super+S` / `Super+Shift+S` | Screenshot tam ekran / alan |
| `Super+B` | Waybar toggle |
| `Super+Alt+B` | Wallpaper cycle |
| `Super+M` | Palette scheme cycle |
| `Super+Q` | Pencere kapat |
| `Super+W` | Float toggle |
| `Super+F` | Fullscreen |
| `Super+1..9` | Workspace |
| `Super+Shift+M` | Hyprland'den çık |

## Persistence

TUI → Settings'teki ayarlar (gaps, blur, rounding, opacity, cursor, keyboard,
touchpad, monitor, animations, vs.) `~/.config/hypr/overrides.conf`'a yazılır.
`hyprland.conf` bunu en son `source` eder; her reboot'ta son bıraktığın hali
dönüyor.

## Lisans

MIT.
