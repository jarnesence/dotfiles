# dotfiles — Hyprland terminal-zen

<p>
  <img src="https://img.shields.io/badge/Arch%20Linux-Hyprland-231f28?style=flat-square&logo=archlinux&logoColor=f3b8c8" alt="Arch Linux Hyprland">
  <img src="https://img.shields.io/badge/Config-Lua%20(hl.*)-231f28?style=flat-square&logo=lua&logoColor=f3b8c8" alt="Lua">
  <img src="https://img.shields.io/badge/Setup-Claude%20Code%20%7C%20AGY-231f28?style=flat-square&logoColor=f3b8c8" alt="Claude Code or AGY">
</p>

Arch Linux + Hyprland (**Lua config**, `hl.*` API) üzerinde, her etkileşimli yüzeyi
bir `fzf` TUI olan sade bir masaüstü. Renkler aktif duvar kağıdından `matugen` ile üretilir
(Hyprland kenarları, `kitty`, `eww`, GTK3/4, `mako` aynı paleti kullanır).

![wallpaper](wallpaper/z4-4.png)

## Kurulum — Kendin Uğraşma, Agent'a Kurdur

Burada her makinede patlayan tek-tık kurulum betikleri yok.
Önce **[Claude Code](https://docs.anthropic.com/en/docs/claude-code)** ya da **[Antigravity (`agy`)](https://antigravity.google)** kur, bu repoyu önüne bırak — hedef makinenin donanımını (GPU, CPU, pil, Wi-Fi, ekran çözünürlüğü, ses kartı) kendisi tespit edip bütün sistemi senin yerine eksiksiz ayağa kaldırsın:

```sh
git clone https://github.com/jarnesence/dotfiles ~/dotfiles
cd ~/dotfiles

# Claude Code ile:
claude "INSTALL.md'yi oku ve bu makineye eksiksiz uygula"

# veya Antigravity CLI (agy) ile:
agy "INSTALL.md'yi oku ve bu makineye eksiksiz uygula"
```

Ayrıntılı adımlar, koşullu sistem ayarları ve dahil edilmeyenler: [INSTALL.md](INSTALL.md).

## İçerik

```
home/        $HOME aynası (@HOME@/@USER@ tokenlı) — hypr, kitty, eww, matugen, zsh, TUI'ler…
system/      / aynası — DNS zinciri (resolved → dnscrypt), güç/pil servisleri, sysctl, zram…
packages/    base · apps · aur · flatpak · dev (opsiyonel)
wallpaper/   aktif duvar kağıdı
INSTALL.md   AI agent için kurulum talimatı
```

## Kısayollar (özet)

`Super+T` terminal · `Super+Space` başlatıcı · `Super+,` ayarlar · `Super+B` tepsi ·
`Super+N` Spotify · `Super+.` duvar kağıdı · `Super+Shift+Q` güç menüsü · `Super+S` ekran görüntüsü.
Tam liste INSTALL.md §8'de.

MIT.
