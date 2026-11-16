# dotfiles — Hyprland terminal-zen

Arch Linux + Hyprland (**Lua config**, `hl.*` API) üzerinde, her etkileşimli yüzeyi
bir fzf TUI olan sade bir masaüstü. Renkler aktif duvar kağıdından matugen ile üretilir
(Hyprland kenarları, kitty, eww, GTK3/4, mako aynı paleti kullanır).

![wallpaper](wallpaper/z4-4.png)

## Kurulum

Kurulum betiği yok. Kurulumu **Claude Code** yapar ve hedef makinenin donanımına
(GPU, CPU, pil, Wi-Fi, ekran çözünürlüğü, ses kartı) göre uyarlar:

```sh
git clone https://github.com/jarnesence/dotfiles ~/dotfiles
cd ~/dotfiles && claude "INSTALL.md'yi uygula"
```

Ayrıntılı adımlar, koşullu sistem ayarları ve dahil edilmeyenler: [INSTALL.md](INSTALL.md).

## İçerik

```
home/        $HOME aynası (@HOME@/@USER@ tokenlı) — hypr, kitty, eww, matugen, zsh, TUI'ler…
system/      / aynası — DNS zinciri (resolved → dnscrypt), güç/pil servisleri, sysctl, zram…
packages/    base · apps · aur · flatpak · dev (opsiyonel)
wallpaper/   aktif duvar kağıdı
INSTALL.md   Claude Code için kurulum talimatı
```

## Kısayollar (özet)

`Super+T` terminal · `Super+Space` başlatıcı · `Super+,` ayarlar · `Super+B` tepsi ·
`Super+N` Spotify · `Super+.` duvar kağıdı · `Super+Shift+Q` güç menüsü · `Super+S` ekran görüntüsü.
Tam liste INSTALL.md §8'de.

MIT.
