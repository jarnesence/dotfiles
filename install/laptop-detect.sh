#!/bin/bash
# laptop-detect.sh — chassis/vendor/model'e göre paket kur.
# Desktop: hiçbir şey yapmaz. Başka laptop: jenerik laptop paketleri.
# ASUS Zenbook S16 (UM5606): asusctl + NPU (opsiyonel) + howdy (opsiyonel).
#
# Kullanım:  bash laptop-detect.sh            → detect + kur
#            bash laptop-detect.sh --dry-run  → sadece rapor

set -eu

DRY_RUN=0
[ "${1:-}" = "--dry-run" ] && DRY_RUN=1

dmi() { cat "/sys/class/dmi/id/$1" 2>/dev/null | tr -d '\n'; }

CHASSIS=$(dmi chassis_type)
VENDOR=$(dmi sys_vendor)
PRODUCT=$(dmi product_name)
BOARD=$(dmi board_name)

echo "chassis_type  : $CHASSIS"
echo "sys_vendor    : $VENDOR"
echo "product_name  : $PRODUCT"
echo "board_name    : $BOARD"
echo

# Laptop chassis? 8=portable, 9=laptop, 10=notebook, 14=sub-notebook
case "$CHASSIS" in
    8|9|10|14) IS_LAPTOP=1 ;;
    *)         IS_LAPTOP=0 ;;
esac

if [ "$IS_LAPTOP" -eq 0 ]; then
    echo "desktop detected — nothing to install."
    exit 0
fi

# ─── Generic laptop baseline ─────────────────────────────
GENERIC_PKGS="power-profiles-daemon brightnessctl sof-firmware alsa-ucm-conf"

# ─── ASUS specific ───────────────────────────────────────
ASUS_PKGS=""
ZENBOOK_S16_AUR_PKGS=""
case "$VENDOR" in
    *ASUSTeK*|*ASUS*)
        echo "ASUS laptop detected."
        ASUS_PKGS="$GENERIC_PKGS"
        ASUS_AUR="asusctl"
        # Zenbook S16 UM5606 family: WA/KA/MA/CA — AMD Ryzen AI, iGPU only.
        case "$PRODUCT$BOARD" in
            *UM5606*)
                echo "→ Zenbook S16 (UM5606) detected — AMD Ryzen AI, Strix Point."
                # NPU (XDNA) driver: kernel 6.14+ mainline; DKMS fallback for older.
                ZENBOOK_S16_AUR_PKGS="amdxdna-driver-dkms"
                ;;
        esac
        ;;
    *)
        echo "non-ASUS laptop — generic laptop setup."
        ;;
esac

# ─── IR camera → Howdy (Windows Hello) ───────────────────
HOWDY_PKG=""
if lsusb 2>/dev/null | grep -qiE "IR camera|IR 2MP|Chicony.*IR"; then
    echo "IR camera detected — howdy recommended."
    HOWDY_PKG="howdy"
fi

# ─── Fingerprint ────────────────────────────────────────
FP_PKG=""
if lsusb 2>/dev/null | grep -qi fingerprint; then
    echo "fingerprint sensor detected — fprintd."
    FP_PKG="fprintd libfprint"
fi

# ─── Kurulum ────────────────────────────────────────────
PACMAN_PKGS="${ASUS_PKGS:-$GENERIC_PKGS} ${FP_PKG}"
AUR_PKGS="${ASUS_AUR:-} ${ZENBOOK_S16_AUR_PKGS:-} ${HOWDY_PKG:-}"

echo
echo "pacman packages : $PACMAN_PKGS"
echo "AUR packages    : $AUR_PKGS"

if [ "$DRY_RUN" -eq 1 ]; then
    echo "[dry-run] skipping install."
    exit 0
fi

if [ -n "$(echo "$PACMAN_PKGS" | xargs)" ]; then
    sudo pacman -S --noconfirm --needed $PACMAN_PKGS
fi
if [ -n "$(echo "$AUR_PKGS" | xargs)" ]; then
    paru -S --noconfirm --needed $AUR_PKGS
fi

# ─── Enable services ────────────────────────────────────
sudo systemctl enable --now power-profiles-daemon.service 2>/dev/null || true
if [ -n "${ASUS_AUR:-}" ] && systemctl list-unit-files asusd.service >/dev/null 2>&1; then
    sudo systemctl enable --now asusd.service
fi

echo
echo "done. hardware-specific setup complete."
echo "hints:"
echo "  - battery charge limit (ASUS):  asusctl -c 80"
echo "  - power profile:                powerprofilesctl set balanced|performance|power-saver"
echo "  - face recognition (howdy):     sudo howdy add"
