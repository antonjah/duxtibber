#!/bin/sh
# Renders the plugin headless with the real Dux components against a mock Tibber server.
# Writes PNGs per scene plus quickshell.log to tests/render-output and checks the logged state.
# Needs: dms (or DMS_SHELL_DIR), qs, dbus-run-session, python3, Xvfb (or nix to fetch it). Runs in a
# private X server with temp XDG dirs and its own D-Bus session, so the running shell is untouched.
# Qt's offscreen platform cannot be used: Dux 2.1 needs a PanelWindow backend, which X11 provides.
set -eu

repo=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
out="${DUXTIBBER_OUT:-$repo/tests/render-output}"

shell_dir="${DMS_SHELL_DIR:-}"
if [ -z "$shell_dir" ]; then
    shell_dir="$(dirname "$(dirname "$(readlink -f "$(command -v dms)")")")/share/quickshell/dms"
fi
[ -f "$shell_dir/shell.qml" ] || { echo "Dux shell dir not found; set DMS_SHELL_DIR" >&2; exit 2; }

work=$(mktemp -d)
server_pid=
xvfb_pid=
cleanup() {
    [ -n "$server_pid" ] && kill "$server_pid" 2>/dev/null
    [ -n "$xvfb_pid" ] && kill "$xvfb_pid" 2>/dev/null
    rm -rf "$work"
}
trap cleanup EXIT HUP INT TERM

mkdir -p "$out" "$work/harness/Modules/Plugins" "$work/config/dms" "$work/config/tibber" "$work/cache" "$work/state" "$work/data" "$work/runtime" "$work/tokens"
chmod 700 "$work/runtime"
rm -f "$out"/*.png "$out"/*.log

# Harness shell dir: the real one with our shell.qml and a PluginComponent whose layer-shell popout is stubbed.
for e in "$shell_dir"/*; do
    case "${e##*/}" in shell.qml|Modules) ;; *) ln -s "$e" "$work/harness/" ;; esac
done
for e in "$shell_dir"/Modules/*; do
    [ "${e##*/}" = Plugins ] || ln -s "$e" "$work/harness/Modules/"
done
for e in "$shell_dir"/Modules/Plugins/*; do
    [ "${e##*/}" = PluginComponent.qml ] || ln -s "$e" "$work/harness/Modules/Plugins/"
done
awk '
    /^    PluginPopout \{/ { print "    QtObject { id: pluginPopout; property bool shouldBeVisible: false; function toggle() {} function close() {} function setTriggerPosition() {} }"; skip = 1; next }
    skip && /^    \}/ { skip = 0; next }
    !skip
' "$shell_dir/Modules/Plugins/PluginComponent.qml" > "$work/harness/Modules/Plugins/PluginComponent.qml"
grep -q 'id: pluginPopout' "$work/harness/Modules/Plugins/PluginComponent.qml" || { echo "PluginPopout stub failed; PluginComponent changed upstream" >&2; exit 2; }
cp "$repo/tests/render/shell.qml" "$work/harness/shell.qml"

printf good > "$work/tokens/good"
printf negative > "$work/tokens/negative"
printf expired > "$work/tokens/expired"
printf sekret > "$work/tokens/carsecret"
mkdir -p "$work/state/duxtibber"

demo_token=$(sed -n 's/^var DEMO_TOKEN = "\(.*\)"/\1/p' "$repo/Tibber.js")
port=$(python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')
python3 "$repo/tests/server.py" "$port" "$repo/tests/fixtures/demo.json" "$work/requests.log" "$demo_token" &
server_pid=$!
sleep 1

xvfb=$(command -v Xvfb || printf '%s/bin/Xvfb' "$(nix build nixpkgs#xvfb --no-link --print-out-paths)")
"$xvfb" -displayfd 3 -screen 0 1280x1300x24 -nolisten tcp 3> "$work/display" 2> /dev/null &
xvfb_pid=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do [ -s "$work/display" ] && break; sleep 0.5; done
[ -s "$work/display" ] || { echo "Xvfb did not start" >&2; exit 2; }
display=":$(cat "$work/display")"

# Reuse the local theme so the images look like the real bar.
cp "${XDG_CONFIG_HOME:-$HOME/.config}/dms/settings.json" "$work/config/dms/" 2>/dev/null || true
cp "${XDG_CACHE_HOME:-$HOME/.cache}/dms/dms-colors.json" "$work/cache/" 2>/dev/null || true
printf '%s\n' '{"duxTibber":{"enabled":true}}' > "$work/config/dms/plugin_settings.json"

env -u WAYLAND_DISPLAY -u NIRI_SOCKET -u DMS_SOCKET -u QT_QPA_PLATFORMTHEME \
    QT_QPA_PLATFORM=xcb DISPLAY="$display" \
    XDG_RUNTIME_DIR="$work/runtime" XDG_CONFIG_HOME="$work/config" XDG_CACHE_HOME="$work/cache" \
    XDG_STATE_HOME="$work/state" XDG_DATA_HOME="$work/data" \
    DUXTIBBER_DIR="$repo" DUXTIBBER_SHOTS="$out" DUXTIBBER_TOKENS="$work/tokens" DUXTIBBER_API="http://127.0.0.1:$port/" \
    timeout 120 dbus-run-session -- qs --log-rules 'scene.warning=true;qml.warning=true;js.warning=true' -p "$work/harness" \
    > "$out/quickshell.log" 2>&1 || true
cp "$work/requests.log" "$out/requests.log" 2>/dev/null || true

fail() {
    printf '%s\n' "$1" >&2
    grep -E "TIBBER|$repo" "$out/quickshell.log" >&2 || tail -n 20 "$out/quickshell.log" >&2
    exit 1
}

grep -q 'TIBBER done' "$out/quickshell.log" || fail 'The render did not finish.'
if grep -E "TIBBER ERROR|$repo/[^ ]*: .*(Error|is not defined|Cannot read|Unable to assign|ReferenceError|TypeError)" "$out/quickshell.log" >&2; then
    fail 'QML errors in plugin files.'
fi

scene() { sed -n "s/.*TIBBER $1 //p" "$out/quickshell.log"; }
price='pill=-?[0-9]*\.[0-9][0-9] '
for s in demo token negative stale twoscreens; do
    scene "$s" | grep -Eq "^$price" || fail "Scene $s: pill is not a price: $(scene "$s")"
done
scene demo | grep -q 'demo=true' || fail 'demo scene is not flagged as demo'
scene token | grep -q 'demo=false' || fail 'token scene is flagged as demo'
scene token | grep -q 'model=192' || fail 'token scene should have today and tomorrow (192 slots)'
scene demo | grep -q 'model=96' || fail 'demo scene should have only today (96 slots)'
scene stale | grep -Eq 'error="Invalid token"' || fail 'stale scene should report Invalid token'
scene stale | grep -q 'model=192' || fail 'stale scene should keep the last data'
scene error | grep -Eq '^pill=! .*error="Invalid token" model=0' || fail "error scene unexpected: $(scene error)"
scene twoscreens | grep -q 'twinSame=true' || fail 'two instances do not share state'
scene spot | grep -Eq '^pill=[0-9]+ öre level=.*demo=false error="" model=192' || fail "spot scene should show whole-ore prices with the unit for today and tomorrow: $(scene spot)"
scene nounit | grep -Eq '^pill=[0-9]+ level=' || fail "nounit scene should show the bare number: $(scene nounit)"
scene spotno | grep -Eq '^pill=[0-9]+\.[0-9][0-9] .*demo=false error="" model=24 ' || fail "spotno scene should show hourly prices for today only: $(scene spotno)"
scene declared | grep -Eq '^pill=[0-9]+ .*demo=false error="" model=192' || fail "declared scene: config.json should override the settings page (SE3, whole ore): $(scene declared)"
carscene() { scene "$1" | grep -Eq "$2" || fail "$1 scene: expected /$2/ in: $(scene "$1")"; }
carscene car 'carstate=car car=Škoda Enyaq/70/80/256 tok=r-ok redirect=cleared'
carscene carOff 'carstate=off car=none'
carscene carSetup 'carstate=setup car=none'
carscene carNoSecret 'carstate=setup car=none'
carscene carConnect 'carstate=connect car=none tok=none'
carscene carPaste 'carstate=car car=Škoda Enyaq/70/80/256 tok=r1 redirect=cleared'
carscene carBadPaste 'carstate=connect car=none tok=none redirect=cleared msg=Tibber rejected the login'
carscene carRefresh 'carstate=car car=Škoda Enyaq/70/80/256 tok=r-next'
carscene carRevoked 'carstate=reconnect car=none'
carscene carSelect 'carstate=car car=Volvo Family car/40/90/120'
carscene carMiss 'carstate=notfound car=none'
scene demo | grep -q 'carstate=off ' || fail 'scenes without the car tile enabled must not show a car'

# demo, token, negative, stale (good + expired), error, twoscreens: one request each; each area scene: 3 past days, today, tomorrow;
# car scenes: the demo price plus, when tokens exist, token exchange/refresh (1) and homes + devices + 3 device details (5).
[ "$(wc -l < "$out/requests.log")" = 67 ] || fail "Expected 67 requests, got $(wc -l < "$out/requests.log"): two screens must share one fetch"
for n in demo token negative stale error twoscreens spot spotno declared nounit car carOff carSetup carNoSecret carConnect carPaste carBadPaste carRefresh carRevoked carSelect carMiss; do
    [ -s "$out/$n.png" ] || fail "Missing $n.png"
done
printf '%s\n' "Render checks passed. Images are in $out."
