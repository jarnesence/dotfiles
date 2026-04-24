#!/bin/bash
# swayosd-server'ı restart — tema değişince yeni renkleri alsın.
pkill -x swayosd-server 2>/dev/null
sleep 0.1
setsid -f swayosd-server >/dev/null 2>&1
