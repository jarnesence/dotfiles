#!/usr/bin/env python3
# ╭────────────────────────────────────────────────────────────╮
# │  tray-hostd — minimal StatusNotifierWatcher + Host           │
# │  Collects system tray (SNI/appindicator) icons.             │
# │  The TUI (tray-tui.py) reads the list from this watcher.     │
# │  Runs as a systemd user unit: tray-hostd.service             │
# ╰────────────────────────────────────────────────────────────╯
# Only COLLECTS: it does not draw a graphical tray. It also registers
# as a "host" so apps (ProtonVPN, etc.) actually publish their icons.
import os
import signal

import dbus
import dbus.service
from dbus.mainloop.glib import DBusGMainLoop
from gi.repository import GLib

WATCHER_BUS  = "org.kde.StatusNotifierWatcher"   # de-facto standard (KDE/libappindicator/Qt)
WATCHER_PATH = "/StatusNotifierWatcher"
PROPS_IFACE  = "org.freedesktop.DBus.Properties"


class Watcher(dbus.service.Object):
    def __init__(self, bus):
        self.bus = bus
        # do_not_queue: if another watcher exists → NameExistsException → no double run
        name = dbus.service.BusName(WATCHER_BUS, bus=bus, do_not_queue=True)
        dbus.service.Object.__init__(self, name, WATCHER_PATH)

        self.items = {}          # key "busname+path" -> (owner_unique, busname, path)
        self.hosts = set()

        # Register ourselves as a host → so IsStatusNotifierHostRegistered=True,
        # otherwise some apps will not publish an icon.
        self._host_name = dbus.service.BusName(
            "org.kde.StatusNotifierHost-%d" % os.getpid(), bus=bus)
        self.hosts.add(str(self._host_name.get_name()))

        # Watch name-ownership changes so we can drop an icon when its app dies
        bus.add_signal_receiver(
            self._name_owner_changed, signal_name="NameOwnerChanged",
            dbus_interface="org.freedesktop.DBus",
            bus_name="org.freedesktop.DBus", path="/org/freedesktop/DBus")

    # ── registration methods ──────────────────────────────────────────────
    @dbus.service.method(WATCHER_BUS, in_signature="s", sender_keyword="sender")
    def RegisterStatusNotifierItem(self, service, sender=None):
        # Compatibility: if the arg starts with "/" it is an OBJECT PATH and the real service is the sender
        # (Ubuntu/libappindicator do this); otherwise it is a bus name, with path /StatusNotifierItem.
        if service and service.startswith("/"):
            busname, path = sender, service
        else:
            busname, path = service, "/StatusNotifierItem"
        try:
            owner = busname if busname.startswith(":") else self.bus.get_name_owner(busname)
        except dbus.DBusException:
            owner = busname
        key = busname + path
        self.items[key] = (owner, busname, path)
        self.StatusNotifierItemRegistered(key)

    @dbus.service.method(WATCHER_BUS, in_signature="s", sender_keyword="sender")
    def RegisterStatusNotifierHost(self, service, sender=None):
        self.hosts.add(service)
        self.StatusNotifierHostRegistered()

    # ── signals ───────────────────────────────────────────────────────────
    @dbus.service.signal(WATCHER_BUS, signature="s")
    def StatusNotifierItemRegistered(self, service):
        pass

    @dbus.service.signal(WATCHER_BUS, signature="s")
    def StatusNotifierItemUnregistered(self, service):
        pass

    @dbus.service.signal(WATCHER_BUS, signature="")
    def StatusNotifierHostRegistered(self):
        pass

    @dbus.service.signal(WATCHER_BUS, signature="")
    def StatusNotifierHostUnregistered(self):
        pass

    # ── properties (org.freedesktop.DBus.Properties) ──────────────────────
    @dbus.service.method(PROPS_IFACE, in_signature="ss", out_signature="v")
    def Get(self, iface, prop):
        return self._prop(prop)

    @dbus.service.method(PROPS_IFACE, in_signature="s", out_signature="a{sv}")
    def GetAll(self, iface):
        return {
            "RegisteredStatusNotifierItems":  self._prop("RegisteredStatusNotifierItems"),
            "IsStatusNotifierHostRegistered": self._prop("IsStatusNotifierHostRegistered"),
            "ProtocolVersion":                self._prop("ProtocolVersion"),
        }

    @dbus.service.method(PROPS_IFACE, in_signature="ssv")
    def Set(self, iface, prop, value):
        pass  # read-only

    def _prop(self, p):
        if p == "RegisteredStatusNotifierItems":
            return dbus.Array(list(self.items.keys()), signature="s")
        if p == "IsStatusNotifierHostRegistered":
            return dbus.Boolean(len(self.hosts) > 0)
        if p == "ProtocolVersion":
            return dbus.Int32(0)
        raise dbus.exceptions.DBusException(
            "org.freedesktop.DBus.Error.UnknownProperty: " + p)

    # ── cleanup on app exit ────────────────────────────────────────────────
    def _name_owner_changed(self, name, old_owner, new_owner):
        if new_owner:           # a name appeared → not interested
            return
        dead = [k for k, (owner, bn, _) in self.items.items()
                if owner == name or bn == name]
        for k in dead:
            del self.items[k]
            self.StatusNotifierItemUnregistered(k)
        if name in self.hosts:
            self.hosts.discard(name)
            self.StatusNotifierHostUnregistered()


def main():
    DBusGMainLoop(set_as_default=True)
    bus = dbus.SessionBus()
    try:
        Watcher(bus)
    except dbus.exceptions.NameExistsException:
        print("tray-hostd: another StatusNotifierWatcher is already running — exiting")
        return
    loop = GLib.MainLoop()
    for sig in (signal.SIGTERM, signal.SIGINT):
        signal.signal(sig, lambda *_: loop.quit())
    loop.run()


if __name__ == "__main__":
    main()
