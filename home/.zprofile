export NO_AT_BRIDGE=1 GTK_A11Y=none
if [ -z "$WAYLAND_DISPLAY" ] && [ "$(tty)" = "/dev/tty1" ]; then
    exec start-hyprland >/dev/null 2>&1
fi
