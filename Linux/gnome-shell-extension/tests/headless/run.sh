#!/bin/bash
# End-to-end check of the Necaramba GNOME Shell extension in an isolated,
# headless gnome-shell. Keys are injected through mutter's RemoteDesktop API
# into focused clients — a Wayland GTK4 text field, a VTE terminal and a GTK4
# text field through XWayland — and the typed text proves the result.
#
# Isolation: a temporary HOME/XDG tree, GSETTINGS_BACKEND=keyfile and a private
# D-Bus session. The user's dconf database, extensions and input sources are
# never touched.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
UUID=necaramba@local.necaramba.app

if [ "${NECARAMBA_HEADLESS_INNER:-}" != 1 ]; then
    WORK="$(mktemp -d "${XDG_RUNTIME_DIR:-/tmp}/necaramba-e2e.XXXXXX")"  # short path: unix sockets (IBus) need it
    EXTENSIONS="$WORK/home/.local/share/gnome-shell/extensions"
    mkdir -p "$EXTENSIONS"
    cp -r "$HERE/hide-overview@necaramba.test" "$EXTENSIONS/"
    # Test exactly what users install: the packed zip.
    NECARAMBA_BUILD_DIR="$WORK/build" "$HERE/../../install.sh" >/dev/null || exit 1
    echo "work dir: $WORK"
    env -u DBUS_SESSION_BUS_ADDRESS -u WAYLAND_DISPLAY -u DISPLAY \
        HOME="$WORK/home" XDG_CONFIG_HOME="$WORK/home/.config" \
        XDG_DATA_HOME="$WORK/home/.local/share" XDG_CACHE_HOME="$WORK/home/.cache" \
        GSETTINGS_BACKEND=keyfile NECARAMBA_HEADLESS_INNER=1 NECARAMBA_WORK="$WORK" \
        timeout 420 dbus-run-session -- "$HERE/run.sh"
    status=$?
    [ "$status" = 0 ] && rm -rf "$WORK"
    exit "$status"
fi

# ---- inside the private session -------------------------------------------
case "$HOME" in "$NECARAMBA_WORK"/*) ;; *) echo "refusing: HOME is not isolated"; exit 2;; esac
[ "${GSETTINGS_BACKEND:-}" = keyfile ] || { echo "refusing: GSETTINGS_BACKEND is not keyfile"; exit 2; }

gnome-extensions install --force "$NECARAMBA_WORK/build/$UUID.shell-extension.zip" || exit 1
SCHEMAS="$XDG_DATA_HOME/gnome-shell/extensions/$UUID/schemas"
ours() { gsettings --schemadir "$SCHEMAS" set org.gnome.shell.extensions.necaramba "$@"; }
gsettings set org.gnome.shell welcome-dialog-last-shown-version '999'  # no first-run dialog stealing focus
gsettings set org.gnome.shell enabled-extensions "['$UUID', 'hide-overview@necaramba.test']"
gsettings set org.gnome.desktop.input-sources sources "[('xkb', 'us'), ('xkb', 'ru')]"
gsettings set org.gnome.desktop.input-sources mru-sources "[('xkb', 'us'), ('xkb', 'ru')]"
gsettings set org.gnome.desktop.input-sources xkb-options "[]"
ours layout-switch-shortcut singleShift

LOG="$NECARAMBA_WORK"
XAUTH_BEFORE="$(ls "$XDG_RUNTIME_DIR"/.mutter-Xwaylandauth.* 2>/dev/null)"
gnome-shell --headless --virtual-monitor 1024x768 --wayland \
    --wayland-display necaramba-headless > "$LOG/shell.log" 2>&1 &
SHELL_PID=$!
trap 'kill $SHELL_PID $CLIENT_PID 2>/dev/null' EXIT
sleep 6
GTK_A11Y=none WAYLAND_DISPLAY=necaramba-headless GDK_BACKEND=wayland \
    gjs "$HERE/client.js" > "$LOG/client.log" 2>&1 &
CLIENT_PID=$!
sleep 3

text() { grep '^TEXT ' "$LOG/client.log" | tail -1 | sed 's/^TEXT //' | python3 -I -c 'import json,sys; print(json.loads(sys.stdin.read() or "\"\""), end="")'; }
coproc INJECTOR { gjs "$HERE/inject.js"; }
keys() {
    local reply
    echo "$1" >&"${INJECTOR[1]}"
    read -r -t 30 reply <&"${INJECTOR[0]}" || { echo "injector did not answer"; exit 3; }
    sleep 0.3
}

keys "sleep:500 30:1 30:0 sleep:300"   # warm-up: the first key after focus may be dropped
failures=0
# scenario <name> <keys> <expected typed text>
scenario() {
    local before after delta
    before="$(text)"
    keys "$2"
    after="$(text)"
    delta="${after:${#before}}"
    if [ "$delta" = "$3" ]; then echo "PASS $1 -> '$delta'"
    else echo "FAIL $1: expected '$3', got '$delta'"; failures=$((failures + 1)); fi
}
A="30:1 30:0"          # types a (us) / ф (ru)
LSHIFT_TAP="42:1 42:0"; RSHIFT_TAP="54:1 54:0"

scenario "Shift tap switches us->ru"            "$LSHIFT_TAP sleep:200 $A" "ф"
scenario "right Shift tap switches ru->us"      "$RSHIFT_TAP sleep:200 $A" "a"
scenario "Shift+a types capital, no switch"     "42:1 $A 42:0 sleep:200 $A" "Aa"
scenario "Shift held 800ms then released"       "42:1 sleep:800 42:0 sleep:200 $A" "ф"
scenario "both Shifts together do not switch"   "42:1 54:1 54:0 42:0 sleep:200 $A" "ф"

ours layout-switch-shortcut altShift; sleep 1
scenario "Shift tap ignored for Alt+Shift"      "$LSHIFT_TAP sleep:200 $A" "ф"
scenario "Alt+Shift switches"                   "56:1 42:1 42:0 56:0 sleep:200 $A" "a"
scenario "Shift+Alt (reverse order) switches"   "42:1 56:1 56:0 42:0 sleep:200 $A" "ф"
scenario "Alt+Shift released in press order"    "56:1 42:1 56:0 42:0 sleep:200 $A" "a"
scenario "Alt+Shift+S does not switch"          "56:1 42:1 31:1 31:0 42:0 56:0 sleep:200 $A" "a"

ours layout-switch-shortcut controlShift; sleep 1
scenario "Ctrl+Shift switches"                  "29:1 42:1 42:0 29:0 sleep:200 $A" "ф"
scenario "Ctrl+Shift+T does not switch"         "29:1 42:1 20:1 20:0 42:0 29:0 sleep:200 $A" "ф"

ours layout-switch-shortcut commandShift; sleep 1
scenario "Super+Shift switches"                 "125:1 42:1 42:0 125:0 sleep:400 $A" "a"

ours layout-switch-shortcut disabled; sleep 1
scenario "Off: Shift tap does nothing"          "$LSHIFT_TAP sleep:200 $A" "a"

ours layout-switch-shortcut altShift
gsettings set org.gnome.desktop.input-sources xkb-options "['grp:alt_shift_toggle']"; sleep 1
scenario "native grp:alt_shift_toggle wins, single switch" "56:1 42:1 42:0 56:0 sleep:300 $A" "ф"

ours layout-switch-shortcut singleShift
gsettings set org.gnome.desktop.input-sources xkb-options "[]"; sleep 1
scenario "Shift tap after restoring options"     "$LSHIFT_TAP sleep:200 $A" "a"
gsettings set org.gnome.shell enabled-extensions "['hide-overview@necaramba.test']"; sleep 1
scenario "disabled extension leaves Shift alone" "$LSHIFT_TAP sleep:200 42:1 $A 42:0 sleep:200 $A" "Aa"
gsettings set org.gnome.shell enabled-extensions "['$UUID', 'hide-overview@necaramba.test']"; sleep 1
scenario "re-enabled extension switches again"   "$LSHIFT_TAP sleep:200 $A" "ф"

# ---- double Shift: convert the last word ------------------------------------
# full_scenario <name> <keys> <expected whole field text>; the field is cleared first.
full_scenario() {
    local after
    keys "29:1 30:1 30:0 29:0 14:1 14:0 sleep:200"
    keys "$2"
    after="$(text)"
    if [ "$after" = "$3" ]; then echo "PASS $1 -> '$after'"
    else echo "FAIL $1: expected '$3', got '$after'"; failures=$((failures + 1)); fi
}
GHBDTN="34:1 34:0 35:1 35:0 48:1 48:0 32:1 32:0 20:1 20:0 49:1 49:0"
VBH="47:1 47:0 48:1 48:0 35:1 35:0"
DOUBLE_SHIFT="sleep:200 42:1 42:0 sleep:100 42:1 42:0 sleep:300"
# layout is ru here
full_scenario "double Shift: привет -> ghbdtn, selects us"   "$GHBDTN $DOUBLE_SHIFT $A" "ghbdtna"
full_scenario "double Shift: ghbdtn -> привет, selects ru"   "$GHBDTN $DOUBLE_SHIFT $A" "приветф"
full_scenario "double Shift keeps the space after the word"  "$GHBDTN 57:1 57:0 $DOUBLE_SHIFT $A" "ghbdtn a"
full_scenario "double Shift converts the selection"          "$VBH 57:1 57:0 $GHBDTN sleep:100 42:1 102:1 102:0 42:0 $DOUBLE_SHIFT $A" "мир приветф"
full_scenario "double Shift twice toggles back"              "$GHBDTN $DOUBLE_SHIFT sleep:200 $DOUBLE_SHIFT $A" "приветф"
ours double-shift-conversion false; sleep 1
full_scenario "conversion off: double Shift only switches"   "$GHBDTN $DOUBLE_SHIFT $A" "приветф"
ours double-shift-conversion true
ours layout-switch-shortcut altShift; sleep 1
full_scenario "Alt+Shift setting: double Shift still converts" "$GHBDTN $DOUBLE_SHIFT $A" "ghbdtna"
full_scenario "Alt+Shift setting: single Shift does nothing"   "$GHBDTN sleep:200 42:1 42:0 sleep:400 $A" "ghbdtna"
ours layout-switch-shortcut singleShift; sleep 1

# ---- clients without surrounding text: erase and retype --------------------
# start_client <description> <command...>: replaces the focused test client.
start_client() {
    local name="$1"; shift
    kill "$CLIENT_PID" 2>/dev/null; wait "$CLIENT_PID" 2>/dev/null
    : > "$LOG/client.log"
    GTK_A11Y=none WAYLAND_DISPLAY=necaramba-headless "$@" > "$LOG/client.log" 2>&1 &
    CLIENT_PID=$!
    sleep 3
    keys "sleep:300 1:1 1:0 sleep:200"   # warm-up with Escape
    echo "client: $name"
}
# term_scenario: like full_scenario, but a terminal line is cleared with Enter.
term_scenario() {
    local after
    keys "28:1 28:0 sleep:200"
    keys "$2"
    after="$(text)"
    if [ "$after" = "$3" ]; then echo "PASS $1 -> '$after'"
    else echo "FAIL $1: expected '$3', got '$after'"; failures=$((failures + 1)); fi
}
SHIFT_G="42:1 34:1 34:0 42:0"
HBDTN="35:1 35:0 48:1 48:0 32:1 32:0 20:1 20:0 49:1 49:0"

# layout is us here
start_client "VTE terminal" env GDK_BACKEND=wayland gjs "$HERE/terminal-client.js"
term_scenario "terminal: ghbdtn -> привет"                "$GHBDTN $DOUBLE_SHIFT $A" "приветф"
term_scenario "terminal: привет -> ghbdtn"                "$GHBDTN $DOUBLE_SHIFT $A" "ghbdtna"
term_scenario "terminal: keeps the space after the word"  "$GHBDTN 57:1 57:0 $DOUBLE_SHIFT $A" "привет ф"
term_scenario "terminal: keeps a capital letter"          "$SHIFT_G $HBDTN $DOUBLE_SHIFT $A" "Ghbdtna"
term_scenario "terminal: BackSpace while typing"          "34:1 34:0 35:1 35:0 45:1 45:0 14:1 14:0 48:1 48:0 32:1 32:0 20:1 20:0 49:1 49:0 $DOUBLE_SHIFT $A" "приветф"
term_scenario "terminal: double Shift twice toggles back" "$GHBDTN $DOUBLE_SHIFT sleep:200 $DOUBLE_SHIFT $A" "приветф"
term_scenario "terminal: only the last word"              "$VBH 57:1 57:0 $GHBDTN $DOUBLE_SHIFT $A" "мир ghbdtna"

# layout is us here
XAUTH="$(comm -13 <(echo "$XAUTH_BEFORE") <(ls "$XDG_RUNTIME_DIR"/.mutter-Xwaylandauth.* 2>/dev/null) | head -1)"
XDISPLAY="$(grep -oE 'public X11 display :[0-9]+' "$LOG/shell.log" | head -1 | grep -oE ':[0-9]+')"
start_client "GTK through XWayland" env GDK_BACKEND=x11 DISPLAY="$XDISPLAY" XAUTHORITY="$XAUTH" gjs "$HERE/client.js"
full_scenario "XWayland: ghbdtn -> привет"                "$GHBDTN $DOUBLE_SHIFT $A" "приветф"
full_scenario "XWayland: привет -> ghbdtn"                "$GHBDTN $DOUBLE_SHIFT $A" "ghbdtna"
full_scenario "XWayland: keeps a capital letter"          "$SHIFT_G $HBDTN $DOUBLE_SHIFT $A" "Приветф"
# the word is forgotten: the first tap switches ru->us, the second finds nothing to convert
full_scenario "XWayland: arrow key forgets the word"      "$GHBDTN 105:1 105:0 $DOUBLE_SHIFT $A" "привеaт"

GTK_A11Y=none WAYLAND_DISPLAY=necaramba-headless GDK_BACKEND=wayland \
    gjs -m "$HERE/prefs-smoke.js" "$SCHEMAS" 2>"$LOG/prefs.log" || failures=$((failures + 1))

if grep -E "JS ERROR|$UUID.*(Error|error)" "$LOG/shell.log"; then
    echo "FAIL shell reported extension errors"; failures=$((failures + 1))
fi
echo "headless: $failures failure(s)"
[ "$failures" = 0 ]
