-- ╭──────────────────────────────────────────────────╮
-- │  Custom Hyprland config (Lua)                       │
-- │  2026-05-26                                          │
-- ╰──────────────────────────────────────────────────╯
-- Docs: https://wiki.hypr.land/Configuring/

------------------ MONITORS ------------------
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1.333333 })

------------------ PROGRAMS ------------------
local terminal    = "kitty"
local fileManager = "nautilus"
local browser     = "google-chrome-stable"

------------------ ENVIRONMENT ---------------
hl.env("XCURSOR_THEME", "Bibata-Modern-Ice")
hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")

------------------ AUTOSTART -----------------
-- Doc-canonical autostart: ayrı orkestrasyon scriptine GEREK YOK. Resmi örnek
-- (/usr/share/hypr/hyprland.lua) her programı doğrudan burada, compositor HAZIR
-- olunca tetiklenen "hyprland.start" event'inde hl.exec_cmd ile başlatır.
-- Docs: https://wiki.hypr.land/Configuring/Basics/Autostart/
local scripts   = "@HOME@/.config/hypr/scripts"
hl.on("hyprland.start", function()
    -- systemd/dbus user ortamına Wayland değişkenlerini aktar (portal + user servisleri
    -- WAYLAND_DISPLAY'i görsün; uwsm'siz tty başlatmada kanonik gereklilik).
    hl.exec_cmd("dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP HYPRLAND_INSTANCE_SIGNATURE")
    hl.exec_cmd("systemctl --user import-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP HYPRLAND_INSTANCE_SIGNATURE")
    -- awww-daemon'ı EN BAŞTA ısıt: polkit/mako ile paralel ayağa kalksın, böylece
    -- wallpaper.sh çalıştığında daemon zaten hazır olur (bekleme döngüsüne takılmaz).
    hl.exec_cmd("awww-daemon")
    -- yetki istemleri (polkit agent) + bildirim daemon'ı (mako)
    hl.exec_cmd("/usr/lib/hyprpolkitagent/hyprpolkitagent")
    hl.exec_cmd("mako")
    -- wallpaper (awww) + dinamik palet (matugen); daemon yukarıda ısıtıldı,
    -- script yine de yoksa başlatır (idempotent: ikinci daemon ayağa kalkmaz).
    -- --restore: ~/.cache'teki son aktif wallpaper'ı geri yükler (kapanıştaki versiyon).
    hl.exec_cmd(scripts .. "/wallpaper.sh --restore")
    -- eww saat/batarya widget'ı (daemon yoksa başlat, sonra aç)
    hl.exec_cmd("eww open clock 2>/dev/null || { eww daemon & sleep 1; eww open clock; }")
    -- idle yöneticisi: 3dk karart → 5dk GERÇEK DPMS off (input ile uyanır, donma yok)
    hl.exec_cmd("hypridle")
end)

------------------ DİNAMİK PALET ------------
-- matugen wallpaper'dan üretir → ~/.config/hypr/colors.lua. Her reload'da yeniden
-- okunur, böylece kenarlar HER ZAMAN wallpaper paletine uyar (autoreload bozmaz).
-- colors.lua henüz yoksa (ilk boot) catppuccin fallback kullanılır.
local ok, palette = pcall(dofile, "@HOME@/.config/hypr/colors.lua")
if not ok or type(palette) ~= "table" then
    palette = { primary = "89b4fa", secondary = "cba6f7", outline = "45475a" }
end

------------------ LOOK & FEEL ---------------
hl.config({
    general = {
        gaps_in  = 5,
        gaps_out = 12,
        border_size = 2,
        col = {
            active_border   = { colors = { "rgba(" .. palette.primary .. "ee)", "rgba(" .. palette.secondary .. "ee)" }, angle = 45 },
            inactive_border = "rgba(" .. palette.outline .. "88)",
        },
        resize_on_border = true,
        allow_tearing = false,
        layout = "dwindle",
    },
    decoration = {
        rounding       = 12,
        rounding_power = 2,
        active_opacity   = 1.0,
        inactive_opacity = 1.0, -- diğer uygulamalar tam opak (opak yüzeyde blur da hesaplanmaz)
        shadow = { enabled = true, range = 18, render_power = 3, color = 0x55000000 },
        -- enabled başlangıçta false; aşağıdaki HİBRİT BLUR bloğu aktif workspace'te kitty
        -- varsa açar. Global açık bırakmak tarayıcıyı yavaşlatmıştı (kare başı blur ön-geçişi
        -- + eww layer blur'u her workspace'te hesaplanıyordu).
        blur   = { enabled = false, size = 5, passes = 2, new_optimizations = true, xray = true, ignore_opacity = true },
    },
    animations = { enabled = true },
    dwindle = { preserve_split = true },
    misc = {
        force_default_wallpaper = 0,
        disable_hyprland_logo = true,
        disable_splash_rendering = true,
        background_color = "rgb(000000)",
        -- DPMS'i input ile uyandır (varsayılan false). Bu olmadan bu AMD/eDP panelde
        -- dpms-off sonrası dpms-on DONUYORDU. Bununla fare/klavye DPMS'i süreç-içinde
        -- anında geri açar → daemon yarışı yok, gerçek ekran kapatma güvenli.
        -- (caelestia da tam bunu kullanıyordu; donanım/PSR sorunu DEĞİLDİ.)
        mouse_move_enables_dpms = true,
        key_press_enables_dpms = true,
    },
    -- 20sn hareketsizlikte imleci gizle → 5dk siyah screensaver'da imleç oku görünmez
    -- (0.57+ üst sınır 20; eskiden 30 idi)
    cursor = { inactive_timeout = 20 },
    -- Xwayland uygulamalarını native çözünürlükte render et (1.33 scale'de upscale
    -- bulanıklığını önler). Uygulamalar kendi DPI ölçeğini ayarlamalı
    -- (ör. ONLYOFFICE → QT_SCALE_FACTOR flatpak override).
    xwayland = { force_zero_scaling = true },
})

------------------ ANIMATION CURVES ----------
hl.curve("easeOutQuint",   { type = "bezier", points = { {0.23, 1},    {0.32, 1} } })
hl.curve("almostLinear",   { type = "bezier", points = { {0.5, 0.5},   {0.75, 1} } })
hl.curve("quick",          { type = "bezier", points = { {0.15, 0},    {0.1, 1} } })
hl.curve("easy",           { type = "spring", mass = 1, stiffness = 71.2633, dampening = 15.8273644 })

hl.animation({ leaf = "windows",    enabled = true, speed = 4.79, spring = "easy",        style = "popin 87%" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 1.49, bezier = "almostLinear", style = "popin 87%" })
hl.animation({ leaf = "border",     enabled = true, speed = 5.39, bezier = "easeOutQuint" })
hl.animation({ leaf = "fade",       enabled = true, speed = 3.03, bezier = "quick" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 1.94, bezier = "almostLinear", style = "fade" })

------------------ INPUT ---------------------
hl.config({
    input = {
        kb_layout    = "tr",
        kb_variant   = "",
        follow_mouse = 1,
        sensitivity  = 0,
        touchpad = {
            natural_scroll       = true,
            disable_while_typing = true,
            tap_to_click         = true,
        },
    },
})

hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })
-- 4 parmak yatay kaydırma da workspace değiştirir (3 parmaklıyla aynı; ayrı kayıt, çakışmaz).
hl.gesture({ fingers = 4, direction = "horizontal", action = "workspace" })
-- Super + 3 parmak sürükle: aktif pencereyi taşı (parmakları 1:1 takip eder, her yöne).
-- NOT: libinput 2 parmağı "scroll" sayar, swipe gesture'ı en az 3 parmak ister; o yüzden
-- taşıma 2 parmakla değil 3 parmakla. mods="SUPER" sayesinde mod'suz 3-parmak workspace
-- swipe'ı ile çakışmaz (Super basılıyken taşı, basılı değilken workspace değiştir).
hl.gesture({ fingers = 3, direction = "swipe", mods = "SUPER", action = "move" })
hl.gesture({ fingers = 3, direction = "swipe", mods = "SUPER SHIFT", action = "resize" })

------------------ KEYBINDINGS ---------------
local mod = "SUPER"

-- apps
hl.bind(mod .. " + T",      hl.dsp.exec_cmd(terminal))
hl.bind(mod .. " + Return", hl.dsp.exec_cmd(terminal))
hl.bind(mod .. " + E",      hl.dsp.exec_cmd(fileManager))
hl.bind(mod .. " + A",      hl.dsp.exec_cmd(browser))
-- Spotify TUI (spotify-player): "tui-" öneki → float-tui kuralı (settings/launcher ile aynı: 900x540 ortalı)
hl.bind(mod .. " + N",      hl.dsp.exec_cmd("kitty --class tui-spotify -e spotify_player"))
-- TUI'ler: "tui-" class öneki → tek pencere kuralı hepsini float + 900x540 + ortalı yapar (bkz. WINDOW RULES)
hl.bind(mod .. " + comma",  hl.dsp.exec_cmd("kitty --class tui-settings -e @HOME@/.local/bin/settings"))
hl.bind(mod .. " + Space",  hl.dsp.exec_cmd("kitty --class tui-launcher -e " .. scripts .. "/launcher.sh"))
-- Sistem tepsisi (tray) yöneticisi: ikonları gör / menü-toggle / kapat. tray-hostd servisi toplar.
hl.bind(mod .. " + B",      hl.dsp.exec_cmd("kitty --class tui-tray -e @HOME@/.local/bin/tray"))

-- wallpaper döngüsü: Super+. sonraki, Super+Shift+. önceki (klasörde sıralı gezinir, palet de yenilenir)
hl.bind(mod .. " + period",         hl.dsp.exec_cmd(scripts .. "/wallpaper-cycle.sh next"))
hl.bind(mod .. " + SHIFT + period", hl.dsp.exec_cmd(scripts .. "/wallpaper-cycle.sh prev"))

-- window management
hl.bind(mod .. " + C",         hl.dsp.window.close())
hl.bind(mod .. " + Q",         hl.dsp.window.close())
hl.bind(mod .. " + SHIFT + Q", hl.dsp.exec_cmd("kitty --class tui-power -e " .. scripts .. "/powermenu.sh"))
hl.bind(mod .. " + W",         hl.dsp.window.float({ action = "toggle" }))
hl.bind(mod .. " + F",         hl.dsp.window.fullscreen())
hl.bind(mod .. " + P",         hl.dsp.window.pseudo())
hl.bind(mod .. " + J",         hl.dsp.layout("togglesplit"))
hl.bind(mod .. " + SHIFT + M", hl.dsp.exit())

-- focus
hl.bind(mod .. " + left",  hl.dsp.focus({ direction = "left" }))
hl.bind(mod .. " + right", hl.dsp.focus({ direction = "right" }))
hl.bind(mod .. " + up",    hl.dsp.focus({ direction = "up" }))
hl.bind(mod .. " + down",  hl.dsp.focus({ direction = "down" }))

-- workspaces 1..10  (+ SHIFT = move window there)
for i = 1, 10 do
    local key = i % 10
    hl.bind(mod .. " + " .. key,         hl.dsp.focus({ workspace = i }))
    hl.bind(mod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }))
end

-- scratchpad (Super+S ekran görüntüsüne verildi → scratchpad Super+U'ya taşındı)
hl.bind(mod .. " + U",         hl.dsp.workspace.toggle_special("magic"))
hl.bind(mod .. " + SHIFT + U", hl.dsp.window.move({ workspace = "special:magic" }))

-- scroll & drag
hl.bind(mod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mod .. " + mouse_up",   hl.dsp.focus({ workspace = "e-1" }))
hl.bind(mod .. " + mouse:272",  hl.dsp.window.drag(),   { mouse = true })
hl.bind(mod .. " + mouse:273",  hl.dsp.window.resize(), { mouse = true })

-- color picker
hl.bind(mod .. " + SHIFT + C", hl.dsp.exec_cmd("hyprpicker -a"))

-- screenshots (grim + slurp + swappy)
hl.bind(mod .. " + S",         hl.dsp.exec_cmd("grim - | swappy -f -"))                 -- tüm ekran
hl.bind(mod .. " + SHIFT + S", hl.dsp.exec_cmd("grim -g \"$(slurp)\" - | swappy -f -")) -- seçilen bölge
hl.bind("Print",         hl.dsp.exec_cmd("grim -g \"$(slurp)\" - | swappy -f -"))
hl.bind("SHIFT + Print", hl.dsp.exec_cmd("grim - | swappy -f -"))

------------------ MEDIA / BRIGHTNESS KEYS ---
-- osd.sh hem seviyeyi değiştirir hem orta-alt eww OSD'sini gösterir (temalı, sade)
hl.bind("XF86AudioRaiseVolume",  hl.dsp.exec_cmd(scripts .. "/osd.sh vol-up"),      { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume",  hl.dsp.exec_cmd(scripts .. "/osd.sh vol-down"),    { locked = true, repeating = true })
hl.bind("XF86AudioMute",         hl.dsp.exec_cmd(scripts .. "/osd.sh vol-mute"),    { locked = true })
hl.bind("XF86AudioMicMute",      hl.dsp.exec_cmd(scripts .. "/osd.sh mic-mute"),    { locked = true })
-- Fn+F10 → KEY_CAMERA (212) → xkb XF86WebCam. Windows'taki gibi kamerayı kesip
-- açar: USB aygıtı de-authorize edilir, /dev/video* tamamen kaybolur.
hl.bind("XF86WebCam",            hl.dsp.exec_cmd(scripts .. "/osd.sh cam-mute"),    { locked = true })
hl.bind("XF86MonBrightnessUp",   hl.dsp.exec_cmd(scripts .. "/osd.sh bright-up"),   { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd(scripts .. "/osd.sh bright-down"), { locked = true, repeating = true })

------------------ WINDOW RULES --------------
hl.window_rule({ name = "suppress-maximize", match = { class = ".*" }, suppress_event = "maximize" })
-- VARSAYILAN TILED: pencereler normal dwindle layout'unda döşeli açılır. Tek bir pencereyi
-- float yapmak istersen Super+W ile aç/kapat.
-- Tüm TUI'ler ("tui-" class önekli): float + sabit 900x540 + ortalı. Yeni TUI eklemek için sadece
-- `kitty --class tui-<isim> -e <komut>` ile aç; otomatik bu kurala uyar.
hl.window_rule({ name = "float-tui", match = { class = "tui-.*" }, float = true, size = "900 540", center = true })

------------------ LAYER RULES ---------------
-- eww blur'u KAPATILDI (2026-06-07, performans): OSD/saat artık buzlu cam değil, düz yarı saydam.
-- Geri istenirse: hl.layer_rule({ name = "blur-eww", match = { namespace = "gtk-layer-shell" }, blur = true, ignore_alpha = 0.4 })

------------------ HİBRİT BLUR: kitty'nin olduğu workspace'te ---------------
-- Blur, aktif workspace'te en az bir kitty penceresi varsa açılır; yoksa kapalı →
-- kitty olmayan workspace'lerde (ör. Chrome) blur maliyeti sıfır. Kitty dışı pencereler
-- kitty'li workspace'te de no_blur kuralıyla blur'lanmaz (frost sadece terminalde).
-- Yeni bir uygulamaya blur istenirse: regex'e ekle (^(?!kitty|foo).*$) + BLUR_CLASS'a ekle.
-- RE2 lookahead desteklemediği için "negative:" öneki (eski (?!...) hâli hiç eşleşmiyordu!)
hl.window_rule({ name = "no-blur-others", match = { class = "negative:^kitty$" }, no_blur = true })

local BLUR_CLASS = "^kitty$"
local function blur_recompute(ws, src)
    ws = ws or hl.get_active_workspace()
    if ws == nil then return end
    local want = false
    local n = 0
    for _, w in ipairs(ws:get_windows() or {}) do
        n = n + 1
        if w.class and w.class:match(BLUR_CLASS) then want = true; break end
    end
    -- idempotent set: state tutma (reload'da desenkron oluyordu)
    hl.config({ decoration = { blur = { enabled = want } } })
end
-- Event anında pencere listesi/aktif ws henüz güncel olmayabiliyor (ör. window.close
-- anında pencere hâlâ listede; yeni ws'e geçişte workspace.active hiç gelmiyor, sadece
-- workspace.created geliyor). Bu yüzden her event 80ms sonra tek seferlik recompute planlar.
local function blur_schedule(src)
    hl.timer(function() blur_recompute(nil, src) end, { timeout = 80, type = "oneshot" })
end
hl.on("workspace.active",  function() blur_schedule("wsactive") end)
hl.on("workspace.created", function() blur_schedule("wscreated") end)
hl.on("window.open",  function() blur_schedule("open") end)
hl.on("window.close", function() blur_schedule("close") end)
hl.on("window.move_to_workspace", function() blur_schedule("move") end)
-- başlangıç/reload anında uygula (startup'ta aktif ws nil olabilir → guard)
blur_recompute(nil, "load")
