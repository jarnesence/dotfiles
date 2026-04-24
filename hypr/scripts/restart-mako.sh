#!/bin/bash
# Mako config'i yeniden okumasını sağla. Çalışmıyorsa başlat.
if pgrep -x mako >/dev/null; then
    makoctl reload 2>/dev/null || { pkill -x mako; sleep 0.1; setsid -f mako >/dev/null 2>&1; }
else
    setsid -f mako >/dev/null 2>&1
fi
