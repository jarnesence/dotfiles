# INSTALL.md — Claude Code kurulum talimatı

Bu dosya **Claude Code'un okuyup uygulaması için** yazıldı. Kurulum betiği yok:
hedef makinenin donanımını sen tespit edeceksin, bu repodaki ayarları o donanıma
uyarlayarak kuracaksın. Amaç: kaynak makinenin (Arch + Hyprland Lua, terminal-zen
rice) **birebir kullanım deneyimini** yeni bir Arch kurulumunda yeniden üretmek.

Kaynak makine referans olarak: ASUS Zenbook S 16 (Ryzen AI 7 350, Radeon 860M
iGPU, 2880×1800 @120 Hz OLED eDP), Arch, `linux`, btrfs, Limine + UKI.
Hedef makine farklı olabilir; aşağıdaki **tespit tablosu** neyin nereye uyarlanacağını söyler.

---

## 0. Çalışma kuralları

- Hedef: taze ya da az kurulu bir **Arch Linux**. Arch değilse dur ve kullanıcıya söyle.
- Kullanıcıyla Türkçe konuş. Kurulum açıkça istendiyse soru yağdırma; yalnız
  aşağıda **[SOR]** ile işaretli noktalarda sor.
- Hiçbir kullanıcı dosyasını doğrudan `rm` etme. Var olan bir dosyanın üzerine
  yazmadan önce `<dosya>.pre-dotfiles` olarak yedekle (ya da `trash-put`).
- `/etc` altındaki pacman'e ait dosyaların (dnscrypt-proxy.toml, mkinitcpio.conf)
  **tamamını körlemesine kopyalama**; farkı göster, yalnız ilgili ayarları birleştir.
- Bootloader'a, bölümlemeye, fstab'a, kernel komut satırına **sormadan dokunma**.
- Her fazdan sonra kısa ilerleme notu ver; sonunda §9'daki doğrulamayı koş ve
  sonucu dürüstçe raporla (çalışmayanı "çalışıyor" diye yazma).

### Yer tutucular
Repodaki dosyalarda kullanıcıya özel değerler token olarak durur:

| Token | Yerine |
|---|---|
| `@HOME@` | hedef kullanıcının ev dizini (`$HOME`, ör. `/home/ali`) |
| `@USER@` | hedef kullanıcı adı (`$USER`) |

Kopyalarken **her metin dosyasında** bu tokenları değiştir
(`grep -rlI '@HOME@\|@USER@' … | xargs sed -i …`). Kopyalanmış dosyada token kalmamalı.

---

## 1. Donanım tespiti (önce bunu yap, sonuçları kullanıcıya tablo olarak göster)

```sh
grep -m1 vendor_id /proc/cpuinfo                       # AuthenticAMD | GenuineIntel
lspci -nnk | grep -EA3 'VGA|3D|Display'                # GPU(lar) + kullanılan sürücü
lspci -nnk | grep -EA3 'Audio'                         # ses denetleyicisi + sürücü (snd_hda_intel / snd_sof_*)
cat /sys/class/dmi/id/{chassis_type,sys_vendor,product_name}
ls /sys/class/power_supply/                            # BAT0 / BAT1 / BATT … yoksa masaüstü
ls /sys/class/power_supply/BAT*/charge_control_end_threshold 2>/dev/null
ls /sys/devices/system/cpu/cpufreq/policy0/boost 2>/dev/null
cat /sys/devices/system/cpu/cpufreq/policy0/scaling_driver
ls /sys/class/net/ ; nmcli -t -f DEVICE,TYPE device    # wifi var mı
ls /sys/class/drm/ ; cat /sys/class/drm/card*-eDP-*/modes 2>/dev/null | head -1   # dahili panel + çözünürlük
cat /sys/class/drm/card*-*/modes 2>/dev/null | sort -u | head                      # harici monitörler
bluetoothctl list 2>/dev/null ; findmnt -no FSTYPE /
bootctl status 2>/dev/null | head -5 ; ls /boot /boot/EFI 2>/dev/null              # hangi bootloader
```

Türetilecek değişkenler:

- **CPU** = amd | intel
- **GPU** = amd | intel | nvidia | hibrit (iGPU + nvidia)
- **LAPTOP** = chassis_type ∈ {8,9,10,14} **veya** `/sys/class/power_supply/BAT*` var
- **BAT** = pil düğümünün adı (kaynakta `BAT0`)
- **CHARGE_LIMIT** = `charge_control_end_threshold` var mı
- **BOOST** = `policy*/boost` per-policy düğümü var mı
- **WIFI**, **BT** = cihaz var mı
- **PANEL** = dahili panelin native çözünürlüğü (yoksa harici ana monitör)
- **AUDIO_HDA** = ses sürücüsü `snd_hda_intel` mi

---

## 2. Paketler

1. `pacman.conf`: `Color`, `ParallelDownloads = 5` açık ve `[multilib]` etkin olsun
   (yalnız bu satırları düzenle, dosyayı değiştirme).
2. `sudo pacman -Syu --needed - < <(grep -v '^#' packages/base.txt)`
   ve aynısını `packages/apps.txt` için.
3. **Donanım paketleri** (tespite göre):

   | Koşul | Paketler |
   |---|---|
   | CPU=amd | `amd-ucode` |
   | CPU=intel | `intel-ucode` |
   | GPU=amd | `mesa vulkan-radeon` |
   | GPU=intel | `mesa vulkan-intel intel-media-driver` |
   | GPU=nvidia (Turing+) | `nvidia-open nvidia-utils egl-wayland libva-nvidia-driver` (Turing öncesiyse dur, kullanıcıya söyle) |
   | GPU=hibrit | iGPU paketleri + nvidia paketleri |
   | ses sürücüsü `snd_sof*` ya da LAPTOP | `sof-firmware alsa-ucm-conf` |

4. `paru` yoksa AUR'dan bootstrap et (`git clone https://aur.archlinux.org/paru-bin` + `makepkg -si`),
   sonra `paru -S --needed - < <(grep -v '^#' packages/aur.txt)`.
5. Flathub: `flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo`
   ve `packages/flatpak.txt` içindekileri `flatpak install -y flathub …`.
6. **[SOR]** "Geliştirici araçları da kurulsun mu? (`packages/dev.txt`: go, zig, jdk, dotnet, podman, tectonic…)"
   Evet ise kur. Hayır ise atla.
7. Claude Code CLI yoksa resmi yükleyiciyle kur (`curl -fsSL https://claude.ai/install.sh | bash`).

---

## 3. Ev dizini dosyaları (`home/` → `$HOME`)

`home/` klasörü `$HOME`'un birebir aynasıdır. Hepsini kopyala, tokenları değiştir:

```sh
rsync -a --backup --suffix=.pre-dotfiles home/ "$HOME"/
grep -rlI '@HOME@\|@USER@' "$HOME"/.config "$HOME"/.local/bin "$HOME"/.z* "$HOME"/.bash* 2>/dev/null \
  | xargs -r sed -i "s#@HOME@#$HOME#g; s#@USER@#$USER#g"
```

- `~/.local/bin/settings` ve `~/.local/bin/tray` **göreli symlink**; korunmalı.
- `~/.local/bin/chromium → /usr/bin/google-chrome-stable` symlink'i **kasıtlı**
  (Chromium bekleyen araçlar Chrome'u kullanır); silme.
- Üretilmiş dosyalar repoda YOK, matugen ilk duvar kağıdında yazar:
  `~/.config/hypr/colors.lua`, `kitty/colors.conf`, `eww/colors.scss`,
  `gtk-3.0/gtk.css`, `gtk-4.0/gtk.css`, `mako/config`.
- Kullanıcı servisi: `systemctl --user enable tray-hostd.service`.
- Varsayılan kabuk: `chsh -s /usr/bin/zsh`. oh-my-zsh yoksa:
  `RUNZSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"`
  (repodaki `.zshrc`'nin üzerine yazmamalı — `KEEP_ZSHRC=yes`).
- `xdg-user-dirs-update` çalıştır (Desktop/Downloads/Pictures… klasörleri).

---

## 4. Görünüm: duvar kağıdı, GTK, imleç

```sh
mkdir -p ~/Pictures/Wallpapers ~/Pictures/Screenshots
cp wallpaper/z4-4.png ~/Pictures/Wallpapers/
printf '%s' "$HOME/Pictures/Wallpapers/z4-4.png" > ~/.cache/active-wallpaper-src
cp wallpaper/z4-4.png ~/.cache/active-wallpaper.png
matugen image ~/Pictures/Wallpapers/z4-4.png --mode dark --prefer saturation   # renk dosyalarını üretir

gsettings set org.gnome.desktop.interface gtk-theme    'adw-gtk3-dark'
gsettings set org.gnome.desktop.interface icon-theme   'Papirus-Dark'
gsettings set org.gnome.desktop.interface cursor-theme 'Bibata-Modern-Ice'
gsettings set org.gnome.desktop.interface cursor-size  24
gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
gsettings set org.gnome.desktop.session idle-delay 0
gsettings set org.gnome.nautilus.preferences default-folder-viewer 'icon-view'
gsettings set org.gnome.nautilus.icon-view default-zoom-level 'large'
```

`gsettings` grafik oturum dışında hata verirse dconf ile yaz
(`dconf write /org/gnome/desktop/interface/gtk-theme "'adw-gtk3-dark'"` …).
Açılışta `wallpaper.sh --restore` bu duvar kağıdını geri yükler; `Super+.` ile klasörde gezilir.

---

## 5. Sistem dosyaları (`system/` → `/`) — koşullu

`system/` klasörü `/`'un aynasıdır. Her dosyayı **koşuluna göre** kur
(`sudo install -D -m <mod> system/<yol> /<yol>`), tokenları değiştir.

| Dosya | Koşul / uyarlama |
|---|---|
| `etc/systemd/zram-generator.conf` | her zaman |
| `etc/sysctl.d/99-net.conf` (bbr + cake) | her zaman |
| `etc/systemd/system.conf.d/no-watchdog.conf` | her zaman |
| `etc/systemd/resolved.conf.d/00-local.conf` | her zaman (DNS zinciri, §6) |
| `etc/NetworkManager/conf.d/dns.conf` | her zaman (DNS zinciri) |
| `etc/dnscrypt-proxy/dnscrypt-proxy.toml` | pacman sürümüyle **birleştir**: `server_names`, `listen_addresses = ['127.0.0.1:53']`, `ipv6_servers=false`, `doh_servers=true`, `require_nolog=true`, `require_nofilter=false`, `lb_strategy='p2'`, `lb_estimator=true`, cache ayarları |
| `etc/vconsole.conf`, `etc/X11/xorg.conf.d/00-keyboard.conf` | her zaman (Türkçe Q klavye) |
| `etc/locale.conf` (`LANG=en_US.UTF-8`) | her zaman; `/etc/locale.gen`'de `en_US.UTF-8` ve `tr_TR.UTF-8` açık olsun → `locale-gen` |
| `etc/modprobe.d/gereksiz.conf` | her zaman (pcspkr, mac_hid, serio_raw, **kvm**). CPU=intel ise `kvm_amd` satırlarını `kvm_intel` yap. **[SOR]** kullanıcı sanal makine çalıştıracaksa kvm satırlarını çıkar |
| `etc/modprobe.d/no-watchdog.conf` (`sp5100_tco`) | yalnız CPU=amd |
| `etc/sysctl.d/99-powersave.conf` | yalnız LAPTOP |
| `etc/udev/rules.d/99-pci-runtime-pm.rules` | yalnız LAPTOP |
| `etc/tmpfiles.d/pcie-aspm-powersave.conf` | yalnız LAPTOP |
| `etc/NetworkManager/conf.d/wifi-powersave.conf` | yalnız LAPTOP ve WIFI |
| `etc/modprobe.d/99-audio-powersave.conf` | yalnız LAPTOP ve AUDIO_HDA |
| `etc/systemd/system/battery-charge-limit.service` | yalnız CHARGE_LIMIT; `BAT0`'ı gerçek pil adıyla değiştir. Limit %80 (kullanıcı tercihi) |
| `etc/systemd/system/ppd-default-profile.service` | yalnız LAPTOP (açılışta `power-saver`, prizde de — kullanıcı tercihi). Masaüstünde kurma |
| `usr/local/bin/ppd-boost-sync` + `ppd-boost-sync.service` | yalnız BOOST (per-policy `policy*/boost` var). Yoksa (ör. intel_pstate) kurma |
| `usr/local/bin/wifi-band-prefer` + `wifi-band-prefer.service` | yalnız WIFI |
| `etc/systemd/system/getty@tty1.service.d/autologin.conf` | **[SOR]** "tty1'de otomatik giriş (şifresiz açılış → doğrudan Hyprland) istiyor musun?" Kaynakta açık. `@USER@`'ı değiştir |
| `etc/mkinitcpio.conf` | **körlemesine kopyalama.** Kaynak: `HOOKS=(base systemd autodetect microcode modconf kms keyboard sd-vconsole block filesystems)`, `COMPRESSION="lz4"`. Hedefte şifreli disk / LVM / farklı bootloader varsa hook'ları koru. GPU=nvidia ise `kms` hook'unu çıkar, `MODULES`'e `nvidia nvidia_modeset nvidia_uvm nvidia_drm` ekle. `MODULES=(vfat …)` yalnız UKI'yı ESP'den okuyan kurulumlar içindir; hedefte gerek yoksa ekleme. Değişirse `mkinitcpio -P` |

Sonra: `sudo systemctl daemon-reload && sudo sysctl --system && sudo udevadm control --reload`.

---

## 6. Servisler ve DNS zinciri

```sh
sudo systemctl enable --now NetworkManager systemd-resolved dnscrypt-proxy \
     power-profiles-daemon ananicy-cpp systemd-timesyncd
# BT varsa:            bluetooth
# koşullu kurulanlar:  battery-charge-limit ppd-default-profile ppd-boost-sync wifi-band-prefer
sudo ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
```

DNS zinciri: uygulama → `/etc/resolv.conf` (**symlink**) → systemd-resolved →
`DNS=127.0.0.1` (+ düz 1.1.1.1 / 9.9.9.9 yedek), `Domains=~.` → dnscrypt-proxy (Mullvad DoH + Quad9 + Cloudflare).
- `Domains=~.` şart: yoksa Wi-Fi'nin modem DNS'i de varsayılan rota olur, sorgular operatöre sızar ve DNS engelleri geri gelir.
- `resolv.conf` **düz dosya olmayacak**, symlink kalacak.
- resolved katmanında **DoT/DNSSEC açma** (dnscrypt zaten şifreli; açmak zinciri kırar).
- NM bağlantı-başı DNS'e yazma. Mullvad düz UDP/53'e cevap vermez.
- Doğrula: `resolvectl query archlinux.org` ve `journalctl -u dnscrypt-proxy -n 20`.
  DNS kırılırsa internetsiz kalınır: dnscrypt çalışmıyorsa `resolved.conf.d/00-local.conf`'u
  geçici olarak kaldırıp kullanıcıya bildir.

---

## 7. Hyprland'ı donanıma uyarla

Config **Lua**'dır (`~/.config/hypr/hyprland.lua`, `hl.*` API, Hyprland ≥ 0.55).
Eski hyprlang (`monitor=…`, `bind=…`) sözdizimi **yazma**. API'den emin değilsen
`/usr/share/hypr/hyprland.lua` örneğine ve wiki.hypr.land'e bak. Çalışma anında
ayar değiştirmek için `hyprctl keyword` **çalışmaz**; `hyprctl eval 'hl.config({...})'` kullan.

1. **Monitör ölçeği** — satır: `hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1.333333 })`
   - PANEL 2880×1800 ise 1.333333 kalsın.
   - Değilse, mantıksal genişlik ≈ 1920–2200 px olacak ve fiziksel çözünürlüğü **tam bölen**
     bir ölçek seç (1, 1.25, 1.333333, 1.5, 1.6, 1.666667, 2). Örn. 1920×1080 → 1,
     2560×1600 → 1.25 ya da 1.333333, 3840×2160 → 1.5 ya da 2. Emin değilsen `scale = "auto"`.
   - Kurulumdan sonra Hyprland'da `hyprctl monitors` ile ölçeğin reddedilmediğini doğrula.
2. **GPU=nvidia/hibrit** — `hyprland.lua`'daki ENVIRONMENT bloğunun altına işaretli blok ekle:
   ```lua
   -- >>> gpu (dotfiles install) >>>
   hl.env("LIBVA_DRIVER_NAME", "nvidia")
   hl.env("__GLX_VENDOR_LIBRARY_NAME", "nvidia")
   hl.env("NVD_BACKEND", "direct")
   hl.env("ELECTRON_OZONE_PLATFORM_HINT", "auto")
   -- <<< gpu <<<
   ```
   Hibritte ayrıca `AQ_DRM_DEVICES` ile iGPU'yu birincil yap (`/dev/dri/by-path` üzerinden kartları belirle).
   AMD/Intel'de ek env **gerekmez**.
3. **Dokunmatik yüzey jestleri / pil / parlaklık / kamera tuşu** — masaüstünde de zararsız;
   `osd.sh` kamera ya da parlaklık yoksa sessizce çıkar. Dokunma.
4. **Pil adı** BAT0 değilse şu dosyalarda değiştir: `~/.config/eww/eww.yuck`,
   `~/.config/eww/scripts/battery-icon.sh`, `~/.config/hypr/scripts/power.sh`.
   Pil **yoksa** (masaüstü) `eww.yuck`'taki batarya etiketlerini (`bat-text`, `bat-icon`
   ve `BAT`/`BATIC` defpoll'ları) kaldır; saat kalsın.
5. **Blur** — config, blur'u yalnız kitty içeren workspace'te açan hibrit bir mantık içerir.
   Global blur'u **açma** (kaynak makinedeki iGPU kaldıramıyordu). Güçlü harici GPU'da
   bile kullanıcı istemedikçe değiştirme.
6. **DPMS** — `misc.mouse_move_enables_dpms` ve `key_press_enables_dpms = true` kalmalı;
   ekran kapatma donmasının çözümü budur. "Siyah shader" gibi hack'ler ekleme.

### Kernel komut satırı (yalnız öneri — **[SOR]**, uygulamadan önce onay al)
Kaynakta: `quiet splash loglevel=0 systemd.show_status=false rd.systemd.show_status=false
rd.udev.log_level=3 vt.global_cursor_default=0 zswap.enabled=0 nmi_watchdog=0`
(zswap kapalı çünkü zram var). Yalnız **AMD iGPU + eDP panel** ve DPMS/ekran uyanma donması
görülürse: `amdgpu.dcdebugmask=0xc10` (PSR/Replay kapatır). GPU=nvidia ise `nvidia_drm.modeset=1`.
Bu parametreler bootloader'a göre farklı yere yazılır (Limine/UKI: `/etc/kernel/cmdline` +
`mkinitcpio -P`; systemd-boot: entry dosyası; GRUB: `GRUB_CMDLINE_LINUX_DEFAULT` + `grub-mkconfig`).
`root=` parametresine asla dokunma.

---

## 8. Kısayollar ve TUI'ler (kurulumdan sonra kullanıcıya özetle)

| Kısayol | Ne yapar |
|---|---|
| `Super+T` / `Super+Return` | kitty |
| `Super+A` | Chrome · `Super+E` Nautilus |
| `Super+Space` | uygulama başlatıcı (fzf TUI) |
| `Super+,` | **Ayarlar TUI** (Wi-Fi, Bluetooth, DND, güç profili, ağ & DNS, ses, ekran, görünüm, giriş, güç, bildirim, sistem, yazılım, güvenlik, Hyprland) |
| `Super+B` | sistem tepsisi TUI (tray-hostd servisi) |
| `Super+N` | Spotify (resmi uygulama, Flathub) |
| `Super+.` / `Super+Shift+.` | sonraki/önceki duvar kağıdı (palet de yenilenir) |
| `Super+Shift+Q` | güç menüsü TUI |
| `Super+Q` / `Super+C` | pencere kapat · `Super+W` float · `Super+F` tam ekran · `Super+J` split |
| `Super+S` / `Super+Shift+S` / `Print` | ekran görüntüsü (tam / alan) → swappy |
| `Super+Shift+C` | renk seçici |
| `Super+U` | scratchpad |
| `Super+1..0` (+Shift) | workspace (pencereyi taşı) |
| 3/4 parmak yatay | workspace · `Super`+3 parmak taşı · `Super+Shift`+3 parmak boyutlandır |
| `Super+Shift+M` | Hyprland'den çık |

Tüm TUI'ler `kitty --class tui-<ad>` ile açılır; `tui-.*` kuralı onları 900×540 ortalı float yapar.
Ayarlar TUI'si kalıcı değişiklikleri `hyprland.lua` sonuna işaretli `lua_block` olarak yazar.

---

## 9. Doğrulama (hepsini koş, sonucu raporla)

```sh
# tokenlar kalmadı
grep -rIl '@HOME@\|@USER@' ~/.config ~/.local/bin ~/.zshrc ~/.zprofile 2>/dev/null   # boş olmalı
# script sözdizimi
for f in ~/.config/hypr/scripts/*.sh; do bash -n "$f" || echo "HATA $f"; done
python3 -m py_compile ~/.config/hypr/scripts/*.py
# eksik komutlar (TUI'lerin çağırdığı her araç kurulu mu)
for c in hyprctl awww matugen eww mako makoctl kitty fzf jq nmcli wpctl brightnessctl \
         powerprofilesctl grim slurp swappy hyprpicker hypridle wiremix bluetuith btop \
         nautilus google-chrome-stable fastfetch zoxide trash-put; do
  command -v $c >/dev/null || echo "EKSİK: $c"; done
systemctl --failed ; systemctl --user --failed
ls -l /etc/resolv.conf ; resolvectl query archlinux.org | tail -2
```

Hyprland'ı başlatabiliyorsan (oturum içindeysen) ayrıca:
`hyprctl reload` → `hyprctl configerrors` boş olmalı; `hyprctl monitors` ölçek doğru;
duvar kağıdı + renkli kenarlar + eww saati görünüyor; `Super+,` açılıyor.
Değilse kullanıcıya "tty1'de giriş yap / yeniden başlat; Hyprland `.zprofile` ile kendiliğinden açılır" de.

---

## 10. Kasıtlı olarak DAHİL EDİLMEYENLER

Kurma, önerme:
- Kaynak makineye özel/standart dışı yazılımlar: BMW E-Sys (ve onun Java 11 / libxcrypt-compat
  bağımlılıkları), Unity Hub / Unity editörü, Android DHU kuralı, Antigravity CLI,
  elle kurulu `biber`, BMW ENET udev/NM dispatcher kuralları.
- Kaynak makinenin boot zinciri: Limine hook'u, UKI kontrol hook'u (`acilis-kontrol`),
  `root=PARTUUID` — hedefin kendi bootloader'ı kullanılır.
- snapper yapılandırması (btrfs alt birim düzenine bağlı). Kullanıcı isterse ayrıca kurulur.
- sudoers NOPASSWD. **[SOR]** kullanıcı açıkça isterse `/etc/sudoers.d/00_$USER` ile ekle (`visudo -c` ile doğrula).
- VPN/WARP/tailscale: kaynakta bilerek yok; ekleme.
- Ses: stok PipeWire. EasyEffects vb. ekleme; kartın `surround*` profillerini seçme.

---

## 11. Bu repoyu kaynak makineden güncellemek (bakım)

Kullanıcı "dotfiles'ı güncelle" derse ters yön uygulanır: canlı sistemden repoya kopyala,
`$HOME` yolunu `@HOME@`, kullanıcı adını `@USER@` yap, yukarıdaki hariç listesine uy,
matugen çıktıları ve `hyprland-before-*.lua` yedekleri gibi üretilmiş dosyaları alma,
`~/.cache/active-wallpaper-src`'deki **yalnız aktif** duvar kağıdını `wallpaper/` altına koy
(eskisini çıkar ve §4'teki dosya adını güncelle), paket listelerini `pacman -Qqen` / `-Qqem` /
`flatpak list --app` ile karşılaştırıp katmanlara (base/apps/aur/flatpak/dev/donanım/hariç) dağıt,
sır taraması yap (token, şifre, client_id, e-posta), sonra commit + push.
