#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf -- "$TMP"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

export HOME="$TMP/home"
export XDG_RUNTIME_DIR="$TMP/runtime"
export KD_STATE="$TMP/kscreen.json"
export PATH="$TMP/bin:$PATH"
export FLATPAK_ID=dev.lizardbyte.app.Sunshine

mkdir -p "$HOME/.config/sunshine" \
  "$HOME/.var/app/$FLATPAK_ID/config/sunshine" \
  "$TMP/bin" "$XDG_RUNTIME_DIR"
printf '[{"name":"DP-1","enabled":true,"connected":true}]\n' > "$KD_STATE"

cat > "$TMP/bin/kscreen-doctor" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
state="${KD_STATE:?}"
if [[ ${1:-} == --json ]]; then
  jq -c '{outputs: .}' "$state"
  exit 0
fi
arg=${1:-}
if [[ $arg == output.*.addCustomMode.* ]]; then
  exit 0
fi
if [[ $arg =~ ^output\.(.+)\.enable$ ]]; then
  name=${BASH_REMATCH[1]}
  jq --arg name "$name" \
    'if any(.[]; .name == $name) then map(if .name == $name then .enabled = true else . end) else . + [{name:$name,enabled:true,connected:true}] end' \
    "$state" > "$state.tmp"
  mv "$state.tmp" "$state"
  exit 0
fi
if [[ $arg =~ ^output\.(.+)\.disable$ ]]; then
  name=${BASH_REMATCH[1]}
  jq --arg name "$name" 'map(if .name == $name then .enabled = false else . end)' \
    "$state" > "$state.tmp"
  mv "$state.tmp" "$state"
  exit 0
fi
exit 0
MOCK

cat > "$TMP/bin/krfb-virtualmonitor" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
state="${KD_STATE:?}"
jq '. + [{name:"Virtual-sunshine-vmon",enabled:true,connected:true}]' \
  "$state" > "$state.tmp"
mv "$state.tmp" "$state"
exec -a krfb-virtualmonitor sleep 300
MOCK

cat > "$TMP/bin/flatpak-spawn" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
while (($#)); do
  case $1 in
    --host) shift ;;
    --env=*) export "${1#--env=}"; shift ;;
    *) break ;;
  esac
done
exec "$@"
MOCK

cat > "$TMP/bin/ss" <<'MOCK'
#!/usr/bin/env bash
exit 0
MOCK

cat > "$TMP/bin/systemctl" <<'MOCK'
#!/usr/bin/env bash
exit 0
MOCK

chmod 755 "$TMP/bin/"*

source "$ROOT/modules/common.sh"
source "$ROOT/modules/vmon/kde/add.sh"
source "$ROOT/modules/vmon/kde/remove.sh"
source "$ROOT/modules/vmon/hyprland/common.sh"
source "$ROOT/modules/vmon/dispatch.sh"

native_unit() { printf '%s\n' sunshine.service; }

red='' yellow='' bold='' normal=''
IMMUTABLE=0
UNSUPPORTED_DISTRO=1
DISTRO=unsupported
FLATPAK_UNIT=app-dev.lizardbyte.app.Sunshine.service
BIN_DIR="$HOME/.local/bin"
TEMP_FILES=()
XDG_CURRENT_DESKTOP=KDE
XDG_SESSION_TYPE=wayland

APP_CONF="$HOME/.var/app/$FLATPAK_ID/config/sunshine/apps.json"
UNIT=$FLATPAK_UNIT
CONF="$HOME/.var/app/$FLATPAK_ID/config/sunshine/sunshine.conf"
printf 'capture = kwin\noutput_name = physical-old\nport = 47990\n' > "$CONF"

pkg_install() {
  echo "unexpected package installation on an unsupported distro" >&2
  return 1
}
native_installed() { return 1; }
flatpak_installed() { return 0; }

# An unsupported distro with the host tools already available must be able to
# configure the KDE monitor for a Flatpak Sunshine install.
setup_vmon_kde >/dev/null
[[ -f "$BIN_DIR/sunshine-vmon-common.sh" && -x "$BIN_DIR/sunshine-start-vmon" && -x "$BIN_DIR/sunshine-stop-vmon" ]] \
  || fail "KDE virtual-monitor hooks were not installed for the Flatpak setup"
jq -e '.apps | any(.[]; .name == "Virtual Monitor")' "$APP_CONF" >/dev/null \
  || fail "Virtual Monitor app was not written"

DO_CMD=$(jq -r '.apps[] | select(.name == "Virtual Monitor") | .["prep-cmd"][0].do' "$APP_CONF")
UNDO_CMD=$(jq -r '.apps[] | select(.name == "Virtual Monitor") | .["prep-cmd"][0].undo' "$APP_CONF")
[[ $DO_CMD == flatpak-spawn\ --host* ]] || fail "Flatpak hook was not generated"

SUNSHINE_CLIENT_WIDTH=2560 SUNSHINE_CLIENT_HEIGHT=1440 SUNSHINE_CLIENT_FPS=90 bash -c "$DO_CMD"
grep -q '^output_name = Virtual-sunshine-vmon$' "$CONF" || fail "output_name was not switched"
jq -e 'any(.[]; .name == "Virtual-sunshine-vmon" and .enabled == true)' "$KD_STATE" >/dev/null \
  || fail "virtual output was not enabled"
jq -e 'any(.[]; .name == "DP-1" and .enabled == false)' "$KD_STATE" >/dev/null \
  || fail "physical output was not disabled"

bash -c "$UNDO_CMD"
grep -q '^output_name = physical-old$' "$CONF" || fail "output_name was not restored"
jq -e 'any(.[]; .name == "DP-1" and .enabled == true)' "$KD_STATE" >/dev/null \
  || fail "physical output was not restored"
echo "PASS KDE Flatpak virtual-monitor lifecycle"

# Sunshine accepts a config without an "apps" key; removal must handle it.
printf '{"env":{}}\n' > "$APP_CONF"
remove_vmon || fail "removal failed on an apps-less config"
jq -e '.apps == []' "$APP_CONF" >/dev/null || fail "apps-less config was not normalized"
[[ ! -e "$BIN_DIR/sunshine-start-vmon" ]] || fail "KDE hooks were not removed"
echo "PASS KDE virtual-monitor removal with an apps-less config"
