#!/usr/bin/env python3
# ╭────────────────────────────────────────────────────────────╮
# │  tray-tui — fzf TUI for the system tray                      │
# │  Reads icons from the tray-hostd watcher; per icon:          │
# │    • left/middle click (Activate / SecondaryActivate)        │
# │    • the app's menu (DBusMenu) → change/toggle               │
# │    • close: Quit in the menu, else SIGTERM the process       │
# │  Launch:  kitty --class tui-tray -e ~/.local/bin/tray        │
# ╰────────────────────────────────────────────────────────────╯
import os
import re
import signal
import subprocess
import sys
import time

import dbus

WATCHER_BUS  = "org.kde.StatusNotifierWatcher"
WATCHER_PATH = "/StatusNotifierWatcher"
SNI          = "org.kde.StatusNotifierItem"
DM           = "com.canonical.dbusmenu"
PROPS        = "org.freedesktop.DBus.Properties"
US           = "\x1f"   # fzf: splits the visible text from a hidden key

# Matches the app's own "quit" entry in its menu. Localized (Turkish) keywords
# are kept too so closing also works for non-English app menus.
QUIT_RX = re.compile(r"\b(quit|exit|close|çıkış|çık|kapat|kapan)\b", re.IGNORECASE)

STATUS_GLYPH = {"Active": "", "Passive": "", "NeedsAttention": ""}


# ── fzf helper ─────────────────────────────────────────────────────────────
def fzf(rows, prompt, header=""):
    """rows: list of (key, display). Returns the selected key or None."""
    if not rows:
        return None
    inp = "\n".join("%s%s%s" % (k, US, d) for k, d in rows)
    p = subprocess.run(
        ["fzf", "--prompt", prompt, "--height", "100%", "--layout=reverse",
         "--border=none", "--info=inline", "--cycle", "--no-sort",
         "--delimiter", US, "--with-nth", "2", "--header", header],
        input=inp, capture_output=True, text=True)
    if p.returncode != 0 or not p.stdout.strip():
        return None
    return p.stdout.strip().split(US, 1)[0]


def msg(text):
    fzf([("ok", text)], "tray ❯ ", "Enter / Esc to continue")


# ── DBus helpers ───────────────────────────────────────────────────────────
def split_service(key):
    """'busname+/path' → (busname, path)"""
    i = key.index("/")
    return key[:i], key[i:]


def read_item(bus, busname, path):
    pi = dbus.Interface(bus.get_object(busname, path), PROPS)

    def g(name, default=""):
        try:
            return pi.Get(SNI, name)
        except dbus.DBusException:
            return default

    return {
        "Id":       str(g("Id")),
        "Title":    str(g("Title")),
        "Status":   str(g("Status", "Active")),
        "IconName": str(g("IconName")),
        "Menu":     str(g("Menu", "")),
    }


def list_items(bus):
    try:
        pi = dbus.Interface(bus.get_object(WATCHER_BUS, WATCHER_PATH), PROPS)
        keys = pi.Get(WATCHER_BUS, "RegisteredStatusNotifierItems")
    except dbus.DBusException:
        return None  # no watcher
    out = []
    for key in keys:
        busname, path = split_service(str(key))
        try:
            out.append((busname, path, read_item(bus, busname, path)))
        except dbus.DBusException:
            continue
    return out


def get_pid(bus, busname):
    try:
        d = dbus.Interface(bus.get_object("org.freedesktop.DBus",
                                          "/org/freedesktop/DBus"),
                           "org.freedesktop.DBus")
        return int(d.GetConnectionUnixProcessID(busname))
    except dbus.DBusException:
        return None


# ── DBusMenu (com.canonical.dbusmenu) ──────────────────────────────────────
def menu_iface(bus, busname, menupath):
    return dbus.Interface(bus.get_object(busname, menupath), DM)


def clean_label(props):
    return str(props.get("label", "")).replace("_", "").strip()


def walk_for_quit(node):
    """Walk the whole tree, return the id of an enabled Quit/Exit-like leaf."""
    _id, props, children = node[0], node[1], node[2]
    if not children:
        label = clean_label(props)
        if label and QUIT_RX.search(label) and props.get("enabled", True):
            return int(_id)
        return None
    for child in children:
        found = walk_for_quit(child)
        if found is not None:
            return found
    return None


def trigger(mi, item_id):
    mi.Event(dbus.Int32(item_id), "clicked",
             dbus.String("", variant_level=1), dbus.UInt32(int(time.time())))


def get_layout(mi, parent=0):
    try:
        mi.AboutToShow(dbus.Int32(parent))
    except dbus.DBusException:
        pass
    _rev, layout = mi.GetLayout(dbus.Int32(parent), dbus.Int32(-1),
                                dbus.Array([], signature="s"))
    return layout  # (id, props, [children])


# ── menu navigation ────────────────────────────────────────────────────────
def browse_menu(bus, busname, menupath, title):
    mi = menu_iface(bus, busname, menupath)
    stack = []  # (node, title)
    try:
        stack.append((get_layout(mi, 0), title))
    except dbus.DBusException as e:
        msg("  Could not read menu: %s" % e.get_dbus_message())
        return

    while stack:
        node, crumb = stack[-1]
        rows = []
        kids = node[2]
        for child in kids:
            cid, props = int(child[0]), child[1]
            if str(props.get("type", "")) == "separator":
                continue
            if not props.get("visible", True):
                continue
            label = clean_label(props) or "—"
            enabled = bool(props.get("enabled", True))
            submenu = str(props.get("children-display", "")) == "submenu"
            tt = str(props.get("toggle-type", ""))
            mark = ""
            if tt == "checkmark":
                mark = " " if int(props.get("toggle-state", 0)) == 1 else " "
            elif tt == "radio":
                mark = " " if int(props.get("toggle-state", 0)) == 1 else " "
            arrow = "  " if submenu else ""
            dim = "" if enabled else "  (disabled)"
            rows.append((str(cid), "%s%s%s%s" % (mark, label, arrow, dim)))
        rows.append(("..back", "  Back"))

        key = fzf(rows, "%s ❯ " % crumb,
                  "Enter: click/open   Esc: exit")
        if key is None or key == "..back":
            stack.pop()
            continue

        cid = int(key)
        child = next(c for c in kids if int(c[0]) == cid)
        props = child[1]
        if str(props.get("children-display", "")) == "submenu":
            try:
                sub = get_layout(mi, cid)
            except dbus.DBusException:
                sub = child
            stack.append((sub, clean_label(props) or crumb))
        else:
            if not props.get("enabled", True):
                continue
            try:
                trigger(mi, cid)
            except dbus.DBusException as e:
                msg("  Click failed: %s" % e.get_dbus_message())
            return  # close the menu after clicking


# ── closing ──────────────────────────────────────────────────────────────
def close_item(bus, busname, item):
    menupath = item["Menu"]
    if menupath:
        try:
            mi = menu_iface(bus, busname, menupath)
            quit_id = walk_for_quit(get_layout(mi, 0))
            if quit_id is not None:
                trigger(mi, quit_id)
                return "  clicked Quit in the menu"
        except dbus.DBusException:
            pass
    pid = get_pid(bus, busname)
    if pid:
        try:
            os.kill(pid, signal.SIGTERM)
            return "  sent SIGTERM to process %d" % pid
        except OSError as e:
            return "  could not close: %s" % e
    return "  could not close (no menu, no PID)"


# ── action menu for a single icon ────────────────────────────────────────────
def item_actions(bus, busname, path, item):
    while True:
        item = read_item(bus, busname, path)  # read fresh
        name = item["Title"] or item["Id"] or busname
        rows = [
            ("activate",  "  Left click (Activate)"),
            ("secondary", "  Middle click (SecondaryActivate)"),
        ]
        if item["Menu"]:
            rows.append(("menu", "  Menu / change"))
        rows += [
            ("close",   "  Close"),
            ("refresh", "  Refresh"),
            ("..back",  "  Back"),
        ]
        header = "%s   |   status: %s   icon: %s" % (
            name, item["Status"], item["IconName"] or "—")
        key = fzf(rows, "%s ❯ " % name, header)

        obj = dbus.Interface(bus.get_object(busname, path), SNI)
        if key is None or key == "..back":
            return
        elif key == "activate":
            try: obj.Activate(0, 0)
            except dbus.DBusException as e: msg("  Activate: %s" % e.get_dbus_message())
        elif key == "secondary":
            try: obj.SecondaryActivate(0, 0)
            except dbus.DBusException as e: msg("  SecondaryActivate: %s" % e.get_dbus_message())
        elif key == "menu":
            browse_menu(bus, busname, item["Menu"], name)
        elif key == "close":
            msg(close_item(bus, busname, item))
            return
        elif key == "refresh":
            continue


# ── offer to start the service if no watcher ──────────────────────────────────
def ensure_watcher(bus):
    if list_items(bus) is not None:
        return True
    key = fzf([("start", "  Start tray-hostd (systemctl --user start)"),
               ("..back", "  Exit")],
              "tray ❯ ", "tray-hostd is not running — tray not collected")
    if key != "start":
        return False
    subprocess.run(["systemctl", "--user", "start", "tray-hostd.service"])
    time.sleep(1.0)  # short wait so apps re-register with the watcher
    return list_items(bus) is not None


# ── main loop ──────────────────────────────────────────────────────────────────
def main():
    bus = dbus.SessionBus()
    if not ensure_watcher(bus):
        return
    while True:
        items = list_items(bus)
        if items is None:
            return
        if not items:
            key = fzf([("refresh", "  Refresh"), ("quit", "  Exit")],
                      "tray ❯ ", "No tray icons registered right now")
            if key == "refresh":
                continue
            return
        rows = []
        for idx, (busname, path, it) in enumerate(items):
            glyph = STATUS_GLYPH.get(it["Status"], "")
            name = it["Title"] or it["Id"] or busname
            rows.append((str(idx), "%s  %s   [%s]" % (glyph, name, it["Status"])))
        rows.append(("quit", "  Exit"))
        key = fzf(rows, "tray ❯ ",
                  "%d icons   |   Enter: open   Esc/Exit: close" % len(items))
        if key is None or key == "quit":
            return
        busname, path, it = items[int(key)]
        item_actions(bus, busname, path, it)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit(0)
