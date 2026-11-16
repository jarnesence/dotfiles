#!/usr/bin/env python3
"""macOS-style Launchpad overlay daemon for Hyprland (GTK3 + gtk-layer-shell)."""

import math
import os
import socket
import sys
import gi

gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
gi.require_version("GtkLayerShell", "0.1")
from gi.repository import Gdk, Gio, GLib, Gtk, GtkLayerShell, Pango  # noqa: E402

RUNTIME_DIR = os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")
SOCK_PATH = os.path.join(RUNTIME_DIR, "hypr-launchpad.sock")
STATE_PATH = os.path.join(RUNTIME_DIR, "hypr-launchpad.state")

COLS = 6
ROWS = 4
PER_PAGE = COLS * ROWS
ICON_SIZE = 76

CSS = """
window#launchpad-window,
#launchpad-bg {
    background-image: none;
    background-color: rgba(10, 12, 18, 0.84);
}

#launchpad-search {
    background-image: none;
    background-color: rgba(255, 255, 255, 0.12);
    color: rgba(255, 255, 255, 0.96);
    border: 1px solid rgba(255, 255, 255, 0.22);
    border-radius: 12px;
    padding: 8px 16px;
    font-size: 15px;
    caret-color: rgba(255, 255, 255, 0.95);
    box-shadow: 0 4px 16px rgba(0, 0, 0, 0.25);
}

#launchpad-search:focus {
    background-image: none;
    background-color: rgba(255, 255, 255, 0.18);
    border-color: rgba(255, 255, 255, 0.45);
}

.app-tile {
    background-color: transparent;
    border: 1px solid transparent;
    border-radius: 18px;
    padding: 14px 10px 12px 10px;
    transition: background-color 140ms ease, border-color 140ms ease;
}

.app-tile:hover,
.app-tile:focus {
    background-color: rgba(255, 255, 255, 0.13);
    border-color: rgba(255, 255, 255, 0.16);
}

.app-tile:active {
    background-color: rgba(255, 255, 255, 0.22);
}

.app-label {
    color: rgba(255, 255, 255, 0.94);
    font-size: 13px;
    font-weight: 500;
    text-shadow: 0 1px 4px rgba(0, 0, 0, 0.75);
}

.page-dot {
    background-color: rgba(255, 255, 255, 0.28);
    border-radius: 999px;
    border: none;
    padding: 0;
    min-width: 8px;
    min-height: 8px;
    transition: background-color 160ms ease;
}

.page-dot.active {
    background-color: rgba(255, 255, 255, 0.95);
}

.empty-label {
    color: rgba(255, 255, 255, 0.55);
    font-size: 18px;
    font-weight: 500;
}
"""


def write_state(is_open: bool) -> None:
    try:
        with open(STATE_PATH, "w", encoding="utf-8") as f:
            f.write("1" if is_open else "0")
    except OSError:
        pass


class LaunchpadWindow(Gtk.Window):
    def __init__(self) -> None:
        super().__init__(type=Gtk.WindowType.TOPLEVEL)
        self.set_name("launchpad-window")
        self.set_decorated(False)

        screen = self.get_screen()
        visual = screen.get_rgba_visual()
        if visual is not None:
            self.set_visual(visual)

        GtkLayerShell.init_for_window(self)
        GtkLayerShell.set_namespace(self, "hypr-launchpad")
        GtkLayerShell.set_layer(self, GtkLayerShell.Layer.OVERLAY)
        GtkLayerShell.set_exclusive_zone(self, -1)
        for edge in (
            GtkLayerShell.Edge.TOP,
            GtkLayerShell.Edge.BOTTOM,
            GtkLayerShell.Edge.LEFT,
            GtkLayerShell.Edge.RIGHT,
        ):
            GtkLayerShell.set_anchor(self, edge, True)
        GtkLayerShell.set_keyboard_mode(self, GtkLayerShell.KeyboardMode.NONE)

        self.is_open = False
        self.progress = 0.0
        self.target_progress = 0.0
        self.anim_id = 0
        self.current_page = 0
        self.num_pages = 1
        self.all_apps: list[Gio.AppInfo] = []
        self.filtered_apps: list[Gio.AppInfo] = []
        self.icon_cache: dict[str, Gdk.cairo_surface_create_from_pixbuf] = {}

        self._build_ui()
        self._load_apps()

        self.app_monitor = Gio.AppInfoMonitor.get()
        self.app_monitor.connect("changed", lambda *_: GLib.idle_add(self._refresh_apps))

        self.connect("key-press-event", self._on_key_press)
        self.connect("scroll-event", self._on_scroll)
        self.add_events(Gdk.EventMask.SCROLL_MASK | Gdk.EventMask.SMOOTH_SCROLL_MASK)

        write_state(False)

    def _build_ui(self) -> None:
        # Outer event box to catch clicks on empty background and paint dark backdrop
        bg_box = Gtk.EventBox()
        bg_box.set_name("launchpad-bg")
        bg_box.set_visible_window(True)
        bg_box.connect("button-press-event", self._on_bg_click)
        self.add(bg_box)

        root = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=18)
        root.set_margin_top(48)
        root.set_margin_bottom(36)
        root.set_margin_start(64)
        root.set_margin_end(64)
        bg_box.add(root)

        # Top Search Bar
        search_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL)
        search_row.set_halign(Gtk.Align.CENTER)
        root.pack_start(search_row, False, False, 0)

        self.search_entry = Gtk.SearchEntry()
        self.search_entry.set_name("launchpad-search")
        self.search_entry.set_placeholder_text("Search")
        self.search_entry.set_size_request(340, 40)
        self.search_entry.connect("search-changed", self._on_search_changed)
        self.search_entry.connect("activate", self._on_search_activate)
        search_row.pack_start(self.search_entry, False, False, 0)

        # Center Stack for pages
        self.stack = Gtk.Stack()
        self.stack.set_transition_type(Gtk.StackTransitionType.SLIDE_LEFT_RIGHT)
        self.stack.set_transition_duration(240)
        self.stack.set_vexpand(True)
        self.stack.set_hexpand(True)
        self.stack.set_valign(Gtk.Align.CENTER)
        self.stack.set_halign(Gtk.Align.CENTER)
        root.pack_start(self.stack, True, True, 0)

        # Bottom Page Dots
        self.dots_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        self.dots_box.set_halign(Gtk.Align.CENTER)
        root.pack_end(self.dots_box, False, False, 0)

    def _load_apps(self) -> None:
        apps = [a for a in Gio.AppInfo.get_all() if a.should_show()]
        apps.sort(key=lambda a: (a.get_name() or "").casefold())
        self.all_apps = apps
        self._apply_filter(self.search_entry.get_text())

    def _refresh_apps(self) -> bool:
        self.icon_cache.clear()
        self._load_apps()
        return False

    def _get_icon_surface(self, app: Gio.AppInfo):
        scale = max(1, self.get_scale_factor())
        icon = app.get_icon()
        key = f"{icon.to_string() if icon else 'none'}@{scale}"
        if key in self.icon_cache:
            return self.icon_cache[key]

        theme = Gtk.IconTheme.get_default()
        pixbuf = None
        target_px = ICON_SIZE * scale
        flags = Gtk.IconLookupFlags.FORCE_SIZE

        if icon is not None:
            info = theme.lookup_by_gicon_for_scale(icon, ICON_SIZE, scale, flags)
            if info is not None:
                try:
                    pixbuf = info.load_icon()
                except Exception:
                    pixbuf = None

        if pixbuf is None:
            try:
                pixbuf = theme.load_icon_for_scale("application-x-executable", ICON_SIZE, scale, flags)
            except Exception:
                try:
                    pixbuf = theme.load_icon("application-x-executable", target_px, flags)
                except Exception:
                    pixbuf = None

        surf = None
        if pixbuf is not None:
            surf = Gdk.cairo_surface_create_from_pixbuf(pixbuf, scale, None)

        self.icon_cache[key] = surf
        return surf

    def _make_app_tile(self, app: Gio.AppInfo) -> Gtk.Button:
        btn = Gtk.Button()
        btn.get_style_context().add_class("app-tile")
        btn.set_relief(Gtk.ReliefStyle.NONE)
        btn.set_size_request(156, 138)
        btn.connect("clicked", lambda *_: self._launch_app(app))

        vbox = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        vbox.set_halign(Gtk.Align.CENTER)
        vbox.set_valign(Gtk.Align.CENTER)
        btn.add(vbox)

        icon = app.get_icon()
        if icon is not None:
            img = Gtk.Image.new_from_gicon(icon, Gtk.IconSize.DIALOG)
        else:
            img = Gtk.Image.new_from_icon_name("application-x-executable", Gtk.IconSize.DIALOG)
        img.set_pixel_size(ICON_SIZE)
        img.set_size_request(ICON_SIZE, ICON_SIZE)
        vbox.pack_start(img, False, False, 0)

        lbl = Gtk.Label(label=app.get_name() or "")
        lbl.get_style_context().add_class("app-label")
        lbl.set_ellipsize(Pango.EllipsizeMode.END)
        lbl.set_max_width_chars(16)
        lbl.set_justify(Gtk.Justification.CENTER)
        vbox.pack_start(lbl, False, False, 0)

        return btn

    def _rebuild_grid(self) -> None:
        for child in self.stack.get_children():
            self.stack.remove(child)
            child.destroy()

        for child in self.dots_box.get_children():
            self.dots_box.remove(child)
            child.destroy()

        if not self.filtered_apps:
            empty = Gtk.Label(label="No applications found")
            empty.get_style_context().add_class("empty-label")
            self.stack.add_named(empty, "empty")
            self.num_pages = 1
            self.current_page = 0
            self.stack.show_all()
            return

        self.num_pages = max(1, math.ceil(len(self.filtered_apps) / PER_PAGE))
        if self.current_page >= self.num_pages:
            self.current_page = 0

        for page_idx in range(self.num_pages):
            chunk = self.filtered_apps[page_idx * PER_PAGE : (page_idx + 1) * PER_PAGE]
            grid = Gtk.Grid()
            grid.set_row_spacing(18)
            grid.set_column_spacing(26)
            grid.set_halign(Gtk.Align.CENTER)
            grid.set_valign(Gtk.Align.CENTER)

            for i, app in enumerate(chunk):
                row = i // COLS
                col = i % COLS
                tile = self._make_app_tile(app)
                grid.attach(tile, col, row, 1, 1)

            self.stack.add_named(grid, f"page-{page_idx}")

        if self.num_pages > 1:
            for page_idx in range(self.num_pages):
                dot = Gtk.Button()
                dot.get_style_context().add_class("page-dot")
                if page_idx == self.current_page:
                    dot.get_style_context().add_class("active")
                dot.set_size_request(8, 8)
                dot.connect("clicked", lambda *_, p=page_idx: self._go_to_page(p))
                self.dots_box.pack_start(dot, False, False, 0)

        self.stack.show_all()
        self.dots_box.show_all()
        self.stack.set_visible_child_name(f"page-{self.current_page}")

    def _go_to_page(self, page_idx: int) -> None:
        if page_idx < 0 or page_idx >= self.num_pages or page_idx == self.current_page:
            return
        self.current_page = page_idx
        self.stack.set_visible_child_name(f"page-{page_idx}")
        for i, dot in enumerate(self.dots_box.get_children()):
            ctx = dot.get_style_context()
            if i == page_idx:
                ctx.add_class("active")
            else:
                ctx.remove_class("active")

    def _apply_filter(self, query: str) -> None:
        q = (query or "").strip().casefold()
        if not q:
            self.filtered_apps = list(self.all_apps)
        else:
            self.filtered_apps = [
                a
                for a in self.all_apps
                if q in (a.get_name() or "").casefold()
                or q in (a.get_description() or "").casefold()
                or q in (a.get_id() or "").casefold()
            ]
        self.current_page = 0
        self._rebuild_grid()

    def _on_search_changed(self, entry: Gtk.SearchEntry) -> None:
        self._apply_filter(entry.get_text())

    def _on_search_activate(self, _entry: Gtk.SearchEntry) -> None:
        if self.filtered_apps:
            self._launch_app(self.filtered_apps[0])

    def _launch_app(self, app: Gio.AppInfo) -> None:
        self.hide_immediate()
        try:
            app.launch([], None)
        except Exception as exc:
            print(f"Launch error: {exc}", file=sys.stderr)

    def _on_bg_click(self, _widget, event) -> bool:
        if event.button == 1:
            self.animate_to(0.0)
            return True
        return False

    def _on_key_press(self, _widget, event) -> bool:
        key = event.keyval
        if key == Gdk.KEY_Escape:
            if self.search_entry.get_text():
                self.search_entry.set_text("")
            else:
                self.animate_to(0.0)
            return True
        if key == Gdk.KEY_Left and not self.search_entry.get_text():
            self._go_to_page(self.current_page - 1)
            return True
        if key == Gdk.KEY_Right and not self.search_entry.get_text():
            self._go_to_page(self.current_page + 1)
            return True
        if not self.search_entry.has_focus() and event.string and event.string.isprintable():
            self.search_entry.grab_focus()
        return False

    def _on_scroll(self, _widget, event) -> bool:
        dx = 0.0
        dy = 0.0
        if event.direction == Gdk.ScrollDirection.SMOOTH:
            _, dx, dy = event.get_scroll_deltas()
        elif event.direction in (Gdk.ScrollDirection.LEFT, Gdk.ScrollDirection.UP):
            dx = -1.0
        elif event.direction in (Gdk.ScrollDirection.RIGHT, Gdk.ScrollDirection.DOWN):
            dx = 1.0

        delta = dx if abs(dx) > abs(dy) else dy
        if delta > 0.3:
            self._go_to_page(self.current_page + 1)
        elif delta < -0.3:
            self._go_to_page(self.current_page - 1)
        return True

    def _stop_anim(self) -> None:
        if self.anim_id:
            GLib.source_remove(self.anim_id)
            self.anim_id = 0

    def set_progress(self, p: float) -> None:
        self._stop_anim()
        p = max(0.0, min(1.0, p))
        self.progress = p

        if p > 0.005:
            if not self.is_visible():
                self.search_entry.set_text("")
                self.show_all()
                GtkLayerShell.set_keyboard_mode(self, GtkLayerShell.KeyboardMode.EXCLUSIVE)
                self.search_entry.grab_focus()
            self.set_opacity(p)
            if not self.is_open:
                self.is_open = True
                write_state(True)
        else:
            self.hide_immediate()

    def hide_immediate(self) -> None:
        self._stop_anim()
        self.progress = 0.0
        self.target_progress = 0.0
        self.is_open = False
        write_state(False)
        GtkLayerShell.set_keyboard_mode(self, GtkLayerShell.KeyboardMode.NONE)
        if self.is_visible():
            self.hide()

    def animate_to(self, target: float) -> None:
        self._stop_anim()
        self.target_progress = max(0.0, min(1.0, target))

        if self.target_progress > 0.5 and not self.is_visible():
            self.search_entry.set_text("")
            self.show_all()
            GtkLayerShell.set_keyboard_mode(self, GtkLayerShell.KeyboardMode.EXCLUSIVE)
            self.search_entry.grab_focus()
            self.is_open = True
            write_state(True)

        if self.target_progress <= 0.01:
            self.is_open = False
            write_state(False)

        def step() -> bool:
            diff = self.target_progress - self.progress
            self.progress += diff * 0.28
            if abs(self.target_progress - self.progress) < 0.015:
                self.progress = self.target_progress
                if self.progress <= 0.01:
                    self.hide_immediate()
                else:
                    self.set_opacity(1.0)
                    self.is_open = True
                    write_state(True)
                self.anim_id = 0
                return False

            self.set_opacity(max(0.0, min(1.0, self.progress)))
            return True

        self.anim_id = GLib.timeout_add(8, step)


def send_cmd(cmd: str) -> None:
    if not os.path.exists(SOCK_PATH):
        return
    s = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
    try:
        s.sendto(cmd.encode("utf-8"), SOCK_PATH)
    finally:
        s.close()


def run_daemon() -> None:
    provider = Gtk.CssProvider()
    provider.load_from_data(CSS.encode("utf-8"))
    Gtk.StyleContext.add_provider_for_screen(
        Gdk.Screen.get_default(), provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
    )

    win = LaunchpadWindow()

    if os.path.exists(SOCK_PATH):
        os.unlink(SOCK_PATH)
    srv = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
    srv.bind(SOCK_PATH)
    srv.setblocking(False)

    def on_socket_readable(_source, _cond) -> bool:
        while True:
            try:
                data = srv.recv(256).decode("utf-8", errors="ignore").strip()
            except BlockingIOError:
                break
            if not data:
                break
            for line in data.splitlines():
                parts = line.strip().split()
                if not parts:
                    continue
                op = parts[0]
                if op == "p" and len(parts) >= 2:
                    try:
                        win.set_progress(float(parts[1]))
                    except ValueError:
                        pass
                elif op == "anim" and len(parts) >= 2:
                    try:
                        win.animate_to(float(parts[1]))
                    except ValueError:
                        pass
                elif op == "open":
                    win.animate_to(1.0)
                elif op == "close":
                    win.animate_to(0.0)
                elif op == "toggle":
                    win.animate_to(0.0 if win.is_open else 1.0)
        return True

    GLib.io_add_watch(srv.fileno(), GLib.IO_IN, on_socket_readable)
    Gtk.main()


if __name__ == "__main__":
    if len(sys.argv) > 1:
        arg = sys.argv[1].lstrip("-")
        if arg in ("open", "close", "toggle"):
            send_cmd(arg)
            sys.exit(0)
    run_daemon()
