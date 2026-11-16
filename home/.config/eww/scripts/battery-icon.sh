#!/usr/bin/env bash
# Kapasite + duruma göre nerd-font batarya ikonu basar.
cap=$(cat /sys/class/power_supply/BAT0/capacity 2>/dev/null || echo 0)
stat=$(cat /sys/class/power_supply/BAT0/status 2>/dev/null)

if [ "$stat" = "Charging" ] || [ "$stat" = "Full" ]; then
    echo "󰂄"; exit 0
fi
if   [ "$cap" -ge 90 ]; then echo "󰁹"
elif [ "$cap" -ge 70 ]; then echo "󰂀"
elif [ "$cap" -ge 50 ]; then echo "󰁾"
elif [ "$cap" -ge 30 ]; then echo "󰁼"
elif [ "$cap" -ge 10 ]; then echo "󰁺"
else                         echo "󰂎"
fi
