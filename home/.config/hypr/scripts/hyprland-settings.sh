#!/usr/bin/env bash
# ╭──────────────────────────────────────────────────────────────────────╮
# │  Hyprland  —  keybindings, look & feel, reload.                       │
# │  Look & feel changes apply live and can be written into a managed     │
# │  block at the end of hyprland.lua.                                    │
# ╰──────────────────────────────────────────────────────────────────────╯
set -u
source @HOME@/.config/hypr/scripts/settings-lib.sh

# opt / hy_set live in settings-lib.sh: this config is Lua, so writes go
# through `hyprctl eval`, not `hyprctl keyword`.
set_opt() { hy_set "$1" "$2"; }

# Read the bindings straight out of the config so the sheet can never drift
# away from what is actually bound.
keybindings() {
    clear
    python3 - "$HYPRCONF" <<'PY' | page
import re, sys

text = open(sys.argv[1], encoding="utf-8").read()
# local terminal = "kitty"  →  resolve those names inside bind actions
consts = dict(re.findall(r'^local\s+(\w+)\s*=\s*"([^"]*)"', text, re.M))

def lua_str(expr):
    """Flatten a Lua string expression: "a" .. scripts .. "/b" -> a/home/.../b"""
    out = []
    for part in expr.split(".."):
        part = part.strip()
        m = re.fullmatch(r'"(.*)"', part, re.S)
        if m:
            out.append(m.group(1).replace('\\"', '"'))
        elif part in consts:
            out.append(consts[part])
        elif part:
            out.append(part)
    return "".join(out)

def action(a):
    a = a.strip().rstrip(",")
    m = re.fullmatch(r'hl\.dsp\.exec_cmd\((.*)\)', a, re.S)
    if m:
        cmd = lua_str(m.group(1))
        # the TUIs are all "kitty --class tui-x -e <script>" — show the script
        m2 = re.search(r'-e\s+(\S+)', cmd)
        if m2 and cmd.startswith("kitty"):
            return m2.group(1).split("/")[-1]
        return cmd
    a = re.sub(r'^hl\.dsp\.', '', a)
    a = re.sub(r'\(\s*\)$', '', a)
    a = re.sub(r'\(\{\s*(.*?)\s*\}\)', r' \1', a, flags=re.S)
    return re.sub(r'\s+', ' ', a).replace('"', '')

def split_args(s):
    """Split a Lua argument list on commas that are at bracket depth 0."""
    args, depth, cur, quote = [], 0, "", None
    for i, ch in enumerate(s):
        if quote:
            cur += ch
            if ch == quote and s[i - 1] != "\\":
                quote = None
            continue
        if ch in "\"'":
            quote = ch; cur += ch
        elif ch in "([{":
            depth += 1; cur += ch
        elif ch in ")]}":
            depth -= 1; cur += ch
        elif ch == "," and depth == 0:
            args.append(cur); cur = ""
        else:
            cur += ch
    if cur.strip():
        args.append(cur)
    return args

def strip_comment(line):
    """Drop a trailing -- comment, ignoring -- that sits inside a string."""
    quote = None
    for i, ch in enumerate(line):
        if quote:
            if ch == quote and line[i - 1] != "\\":
                quote = None
        elif ch in "\"'":
            quote = ch
        elif ch == "-" and line[i:i + 2] == "--":
            return line[:i]
    return line

clean = "\n".join(strip_comment(l).rstrip() for l in text.splitlines())

rows = []
for line in re.findall(r'^\s*hl\.bind\((.*)\)\s*$', clean, re.M):
    parts = split_args(line)
    if len(parts) < 2:
        continue
    keyexpr, act = parts[0], parts[1]
    key = lua_str(keyexpr)
    key = re.sub(r'^SUPER\s*', 'Super ', key)
    key = re.sub(r'\s*\+\s*', ' + ', key).strip(" +")
    if not key.startswith(("Super", "Print", "SHIFT", "XF86")):
        key = "Super + " + key
    rows.append((key, action(act)))

print("\n  \033[1mKeybindings\033[0m  \033[2m(%d bound · read from hyprland.lua)\033[0m\n" % len(rows))
for k, a in rows:
    print("  %-24s \033[2m%s\033[0m" % (k, a[:60]))
print("\n  \033[2mSuper + 1…0 switch workspace · add Shift to move the window there\033[0m")
PY
}

BLUR_CTL="$SCRIPTS/blur-ctl.sh"

blur_mode_get()  { "$BLUR_CTL" get-mode; }
blur_level_get() { "$BLUR_CTL" get-level; }

blur_menu() {
    local cur sel
    cur=$(blur_mode_get)
    sel=$(pick "  Blur mode ($cur) ❯ " "applies & saves to hyprland.lua" \
        "$(item no     "󰂵" "No blur"     "blur off · opaque (1.0)")" \
        "$(item hybrid "󰂷" "Hybrid blur" "kitty only · others opaque (1.0)")" \
        "$(item full   "󰂸" "Full blur"   "all apps · opacity 0.86")" \
        "$(sep)" \
        "$(r back "󰌍  Back")")
    case "$sel" in
        no|hybrid|full) "$BLUR_CTL" set-mode "$sel" ;;
    esac
}

blur_level_menu() {
    local cur sel
    cur=$(blur_level_get)
    sel=$(pick "  Blur level ($cur) ❯ " "applies & saves to hyprland.lua" \
        "$(item 0    "󰂵" "0"    "no blur (size 0, passes 0)")" \
        "$(item az   "󰂷" "Az"   "light (size 2, passes 1)")" \
        "$(item orta "󰂷" "Orta" "medium (size 4, passes 2)")" \
        "$(item cok  "󰂸" "Çok"  "strong (size 7, passes 3)")" \
        "$(sep)" \
        "$(r back "󰌍  Back")")
    case "$sel" in
        0|az|orta|cok) "$BLUR_CTL" set-level "$sel" ;;
    esac
}

look_menu() {
    local sel
    while true; do
        sel=$(pick "  Look & feel ❯ " "applies live · save to keep it" \
            "$(item blur  "󰂷" "Blur mode"        "$(blur_mode_get)")" \
            "$(item blvl  "󰂸" "Blur level"       "$(blur_level_get)")" \
            "$(item gin   "󰃑" "Inner gaps"    "$(opt general:gaps_in)")" \
            "$(item gout  "󰃐" "Outer gaps"        "$(opt general:gaps_out)")" \
            "$(item bord  "󰃞" "Border width"      "$(opt general:border_size)")" \
            "$(item round "󰀽" "Corner rounding"   "$(opt decoration:rounding)")" \
            "$(item shadow "󰊠" "Window shadow"    "$(opt decoration:shadow:enabled)")" \
            "$(item anim  "󰐎" "Animations"        "$(opt animations:enabled)")" \
            "$(item opac  "󰗌" "Inactive opacity" "$(opt decoration:inactive_opacity)")" \
            "$(sep)" \
            "$(r save "󰆓  Save to hyprland.lua")" \
            "$(r back "󰌍  Back")")
        clear
        case "$sel" in
            blur)  blur_menu ;;
            blvl)  blur_level_menu ;;
            gin)   title "Inner gaps";  ask "gaps_in"  "$(opt general:gaps_in)"  && set_opt general:gaps_in  "$ANSWER"; pause ;;
            gout)  title "Outer gaps";  ask "gaps_out" "$(opt general:gaps_out)" && set_opt general:gaps_out "$ANSWER"; pause ;;
            bord)  title "Border width"; ask "border_size" "$(opt general:border_size)" && set_opt general:border_size "$ANSWER"; pause ;;
            round) title "Rounding";    ask "rounding" "$(opt decoration:rounding)" && set_opt decoration:rounding "$ANSWER"; pause ;;
            shadow) [ "$(opt decoration:shadow:enabled)" = true ] \
                        && set_opt decoration:shadow:enabled false || set_opt decoration:shadow:enabled true ;;
            anim)  [ "$(opt animations:enabled)" = true ] \
                        && set_opt animations:enabled false || set_opt animations:enabled true ;;
            opac)  title "Inactive opacity"; dim "1.0 = opaque"
                   ask "inactive_opacity" "$(opt decoration:inactive_opacity)" \
                       && set_opt decoration:inactive_opacity "$ANSWER"; pause ;;
            save)  save_look ;;
            back|'') return ;;
        esac
    done
}

save_look() {
    clear; title "Save look & feel"
    local body
    body=$(cat <<LUA
hl.config({
    general = {
        gaps_in     = $(opt general:gaps_in),
        gaps_out    = $(opt general:gaps_out),
        border_size = $(opt general:border_size),
    },
    decoration = {
        rounding         = $(opt decoration:rounding),
        inactive_opacity = $(opt decoration:inactive_opacity),
        shadow = { enabled = $(opt decoration:shadow:enabled) },
    },
    animations = { enabled = $(opt animations:enabled) },
})
LUA
)
    printf '%s\n\n' "$body" | sed 's/^/  /'
    dim "border colours stay under the palette block above — they follow the wallpaper"
    confirm "Write this into hyprland.lua" || return
    printf '%s\n' "$body" | lua_block look
    pause
}

while true; do
    choice=$(pick "  Hyprland  " "$HINT" \
        "$(item keys  "󰌌" "Keybindings"        "$(grep -cE '^\s*hl\.bind\(' "$HYPRCONF") bound")" \
        "$(item look  "󰸌" "Look & feel"        "gaps, borders, rounding")" \
        "$(item mon   "󰍹" "Monitors"           "$(hyprctl -j monitors 2>/dev/null | grep -c '"name"') connected")" \
        "$(item inp   "󰌏" "Input"              "keyboard, touchpad")" \
        "$(sep)" \
        "$(item rules "󰖯" "Window rules"       "read-only")" \
        "$(item auto  "󰐊" "Autostart"          "read-only")" \
        "$(item ver   "󰋼" "Version & status"   "")" \
        "$(sep)" \
        "$(item reload "󰑓" "Reload config"     "")" \
        "$(item edit  "󰏫" "Edit hyprland.lua"  "")" \
        "$(r back "󰌍  Back")")
    clear
    case "$choice" in
        keys)   keybindings ;;
        look)   look_menu ;;
        mon)    "$SCRIPTS/display.sh" ;;
        inp)    "$SCRIPTS/input.sh" ;;
        rules)  title "Window rules"; grep -nE 'hl\.(windowrule|layerrule)' "$HYPRCONF" | sed 's/^/  /' | page ;;
        auto)   title "Autostart"; grep -nE 'exec_cmd|hl\.exec' "$HYPRCONF" | sed 's/^/  /' | page ;;
        ver)    show "Hyprland" hyprctl version ;;
        reload) title "Reload"; hyprctl reload 2>&1 | sed 's/^/  /'; ok "reloaded"; pause ;;
        edit)   "${EDITOR:-nano}" "$HYPRCONF"
                confirm "Reload Hyprland now" && hyprctl reload >/dev/null 2>&1 ;;
        -)      ;;
        back|'') break ;;
    esac
done
