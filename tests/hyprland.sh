#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf -- "$TMP"' EXIT

export HOME="$TMP/home"
export XDG_RUNTIME_DIR="$TMP/runtime"
export FLATPAK_ID=dev.lizardbyte.app.Sunshine
export HYPR_MOCK_STATE="$TMP/monitors.json"
export HYPR_MOCK_CALLS="$TMP/calls.log"
export HYPR_MOCK_ENV="$TMP/hook-env"
export PATH="$TMP/bin:$PATH"
mkdir -p "$HOME/.config/sunshine" "$HOME/.var/app/$FLATPAK_ID/config/sunshine" \
  "$TMP/bin" "$XDG_RUNTIME_DIR"
printf '[]\n' > "$HYPR_MOCK_STATE"
: > "$HYPR_MOCK_CALLS"

cat > "$TMP/bin/hyprctl" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
case ${1:-} in
  monitors)
    [[ ${2:-} == -j ]] || exit 2
    cat "$HYPR_MOCK_STATE"
    ;;
  output)
    case ${2:-} in
      create)
        [[ ${3:-} == headless ]] || exit 2
        jq --arg name "${4:?}" '. + [{name:$name}]' "$HYPR_MOCK_STATE" > "$HYPR_MOCK_STATE.tmp"
        mv "$HYPR_MOCK_STATE.tmp" "$HYPR_MOCK_STATE"
        ;;
      remove)
        jq --arg name "${3:?}" '[.[] | select(.name != $name)]' "$HYPR_MOCK_STATE" > "$HYPR_MOCK_STATE.tmp"
        mv "$HYPR_MOCK_STATE.tmp" "$HYPR_MOCK_STATE"
        ;;
      *) exit 2 ;;
    esac
    ;;
  eval)
    printf '%s\n' "$2" >> "$HYPR_MOCK_CALLS"
    printf '%s' "${WAYLAND_DISPLAY:-}" > "$HYPR_MOCK_ENV"
    [[ ${HYPR_MOCK_EVAL_FAIL:-0} == 1 ]] && exit 1
    if [[ $2 =~ output[[:space:]]*=[[:space:]]*\"([^\"]+)\" ]]; then
      monitor_name=${BASH_REMATCH[1]}
      if [[ $2 =~ mode[[:space:]]*=[[:space:]]*\"([^\"]+)\" ]]; then
        mode=${BASH_REMATCH[1]}
        if [[ $monitor_name == "${HYPR_MOCK_EVAL_FAIL_NAME:-}" ]]; then
          exit 1
        elif [[ $mode == disable ]]; then
          if [[ $monitor_name != "${HYPR_MOCK_EVAL_NOOP_NAME:-}" ]]; then
            jq --arg name "$monitor_name" '[.[] | select(.name != $name)]' "$HYPR_MOCK_STATE" > "$HYPR_MOCK_STATE.tmp"
            mv "$HYPR_MOCK_STATE.tmp" "$HYPR_MOCK_STATE"
          fi
        elif [[ $monitor_name == "${HYPR_MOCK_EVAL_RESTORE_FAIL_NAME:-}" ]]; then
          jq --arg name "$monitor_name" 'map(select(.name != $name))' "$HYPR_MOCK_STATE" > "$HYPR_MOCK_STATE.tmp"
          mv "$HYPR_MOCK_STATE.tmp" "$HYPR_MOCK_STATE"
        elif [[ $monitor_name == DP-1 || $monitor_name == HDMI-A-1 ]]; then
          if [[ $2 =~ position[[:space:]]*=[[:space:]]*\"([^\"]+)\" ]]; then
            position=${BASH_REMATCH[1]}
          fi
          if [[ $2 =~ scale[[:space:]]*=[[:space:]]*([0-9.]+) ]]; then
            scale=${BASH_REMATCH[1]}
          fi
          if [[ $2 =~ transform[[:space:]]*=[[:space:]]*([0-9]+) ]]; then
            transform=${BASH_REMATCH[1]}
          fi
          resolution=${mode%@*}
          refresh=${mode#*@}
          width=${resolution%x*}
          height=${resolution#*x}
          x=${position%x*}
          y=${position#*x}
          jq --arg name "$monitor_name" --argjson width "$width" --argjson height "$height" \
            --argjson refresh "$refresh" --argjson x "$x" --argjson y "$y" \
            --argjson scale "$scale" --argjson transform "$transform" \
            'map(select(.name != $name)) + [{name:$name,description:($name + " Physical Monitor"),width:$width,height:$height,refreshRate:$refresh,x:$x,y:$y,scale:$scale,transform:$transform}]' \
            "$HYPR_MOCK_STATE" > "$HYPR_MOCK_STATE.tmp"
          mv "$HYPR_MOCK_STATE.tmp" "$HYPR_MOCK_STATE"
        fi
      fi
    fi
    printf 'ok\n'
    ;;
  keyword)
    printf 'keyword %s\n' "$*" >> "$HYPR_MOCK_CALLS"
    [[ ${HYPR_MOCK_KEYWORD_FAIL:-0} == 1 ]] && exit 1
    [[ ${3:-} == *,disable && ${3%,disable} == "${HYPR_MOCK_KEYWORD_FAIL_NAME:-}" ]] && exit 1
    if [[ ${3:-} == *,disable ]]; then
      monitor_name=${3%,disable}
      if [[ $monitor_name != "${HYPR_MOCK_KEYWORD_NOOP_NAME:-}" ]]; then
        jq --arg name "$monitor_name" '[.[] | select(.name != $name)]' "$HYPR_MOCK_STATE" > "$HYPR_MOCK_STATE.tmp"
        mv "$HYPR_MOCK_STATE.tmp" "$HYPR_MOCK_STATE"
      fi
    elif [[ ${3:-} == DP-1,* || ${3:-} == HDMI-A-1,* ]]; then
      IFS=, read -r monitor_name mode position scale transform <<< "$3"
      resolution=${mode%@*}
      refresh=${mode#*@}
      width=${resolution%x*}
      height=${resolution#*x}
      x=${position%x*}
      y=${position#*x}
      if [[ $monitor_name == "${HYPR_MOCK_KEYWORD_RESTORE_FAIL_NAME:-}" ]]; then
        jq --arg name "$monitor_name" 'map(select(.name != $name))' "$HYPR_MOCK_STATE" > "$HYPR_MOCK_STATE.tmp"
        mv "$HYPR_MOCK_STATE.tmp" "$HYPR_MOCK_STATE"
      else
        jq --arg name "$monitor_name" --argjson width "$width" --argjson height "$height" \
          --argjson refresh "$refresh" --argjson x "$x" --argjson y "$y" \
          --argjson scale "$scale" --argjson transform "$transform" \
          'map(select(.name != $name)) + [{name:$name,description:($name + " Physical Monitor"),width:$width,height:$height,refreshRate:$refresh,x:$x,y:$y,scale:$scale,transform:$transform}]' \
          "$HYPR_MOCK_STATE" > "$HYPR_MOCK_STATE.tmp"
        mv "$HYPR_MOCK_STATE.tmp" "$HYPR_MOCK_STATE"
      fi
    fi
    printf 'ok\n'
    ;;
  *) printf 'Unexpected hyprctl args: %s\n' "$*" >&2; exit 2 ;;
esac
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
chmod 755 "$TMP/bin/hyprctl" "$TMP/bin/flatpak-spawn"

source "$ROOT/modules/vmon/hyprland/common.sh"
source "$ROOT/modules/vmon/hyprland/add.sh"
source "$ROOT/modules/vmon/hyprland/remove.sh"
red='' normal='' bold='' IMMUTABLE=0
SCRIPT_DIR=$ROOT
TEST_MODE=native
pick_mode() {
  MODE=$TEST_MODE
  if [[ $MODE == native ]]; then
    APP_CONF="$HOME/.config/sunshine/apps.json"
  else
    APP_CONF="$HOME/.var/app/$FLATPAK_ID/config/sunshine/apps.json"
  fi
}

NATIVE_CONF="$HOME/.config/sunshine/sunshine.conf"
NATIVE_APPS="$HOME/.config/sunshine/apps.json"
printf 'capture = x11\noutput_name = old-output\nport = 47990\n' > "$NATIVE_CONF"
printf '{"env":{},"apps":[]}\n' > "$NATIVE_APPS"
setup_vmon_hyprland >/dev/null
grep -q '^capture = wlr$' "$NATIVE_CONF" || { echo "Native capture config not set" >&2; exit 1; }
grep -q '^output_name = sunshine-vmon$' "$NATIVE_CONF" || { echo "Native output name not set" >&2; exit 1; }
jq -e '.apps | any(.[]; .name == "Virtual Monitor (Hyprland)")' "$NATIVE_APPS" >/dev/null

START="$HOME/.local/bin/sunshine-start-hyprland-vmon"
STOP="$HOME/.local/bin/sunshine-stop-hyprland-vmon"
RUNTIME="$HOME/.local/bin/sunshine-hyprland-vmon-runtime.sh"
[[ -x $START && -x $STOP && -x $RUNTIME ]] || { echo "Lifecycle hooks were not installed" >&2; exit 1; }

SUNSHINE_CLIENT_WIDTH=2560 SUNSHINE_CLIENT_HEIGHT=1440 SUNSHINE_CLIENT_FPS=90 "$START"
grep -q '2560x1440@90' "$HYPR_MOCK_CALLS" || { echo "Client mode was not applied" >&2; exit 1; }
SUNSHINE_CLIENT_WIDTH=2560 SUNSHINE_CLIENT_HEIGHT=1440 SUNSHINE_CLIENT_FPS=90 "$START"
STATE_DIR="$XDG_RUNTIME_DIR/sunshine-hyprland-vmon-$(id -u)"
[[ $(sed -n '1p' "$STATE_DIR/state") == 2 ]] || { echo "Reference count did not increment" >&2; exit 1; }
"$STOP"
[[ $(sed -n '1p' "$STATE_DIR/state") == 1 ]] || { echo "Reference count did not decrement" >&2; exit 1; }
jq -e 'length == 1 and .[0].name == "sunshine-vmon"' "$HYPR_MOCK_STATE" >/dev/null
"$STOP"
jq -e 'length == 0' "$HYPR_MOCK_STATE" >/dev/null
[[ ! -e $STATE_DIR/state ]] || { echo "State was not removed after final stop" >&2; exit 1; }
echo "PASS Hyprland native lifecycle and reference counting"

printf '[{"name":"DP-1","description":"Dell Inc. Physical Monitor","width":2560,"height":1440,"refreshRate":59.95,"x":0,"y":0,"scale":1,"transform":0},{"name":"HDMI-A-1","width":1920,"height":1080,"refreshRate":60,"x":2560,"y":0,"scale":1,"transform":0},{"name":"HEADLESS-1","description":"Headless monitor","width":1920,"height":1080,"refreshRate":60,"x":4480,"y":0,"scale":1,"transform":0}]\n' \
  > "$HYPR_MOCK_STATE"
HYPR_MOCK_EVAL_FAIL=1 "$START"
jq -e 'length == 2 and any(.[]; .name == "sunshine-vmon") and any(.[]; .name == "HEADLESS-1") and all(.[]; .name != "DP-1")' \
  "$HYPR_MOCK_STATE" >/dev/null || { echo "Physical output was not disabled selectively" >&2; exit 1; }
grep -q 'hl.monitor({ output = "DP-1", mode = "disable"' "$HYPR_MOCK_CALLS" \
  || { echo "Physical output disable command was not issued" >&2; exit 1; }
grep -q 'hl.monitor({ output = "HDMI-A-1", mode = "disable"' "$HYPR_MOCK_CALLS" \
  || { echo "Physical output without a description was not disabled" >&2; exit 1; }
grep -q 'keyword monitor DP-1,disable' "$HYPR_MOCK_CALLS" \
  || { echo "Legacy physical output disable fallback was not used" >&2; exit 1; }
HYPR_MOCK_EVAL_FAIL=1 "$STOP"
jq -e 'length == 3 and any(.[]; .name == "DP-1") and any(.[]; .name == "HDMI-A-1") and any(.[]; .name == "HEADLESS-1") and all(.[]; .name != "sunshine-vmon")' \
  "$HYPR_MOCK_STATE" >/dev/null || { echo "Physical output was not restored" >&2; exit 1; }
grep -q 'hl.monitor({ output = "DP-1", mode = "2560x1440@59.95", position = "0x0", scale = 1, transform = 0 })' "$HYPR_MOCK_CALLS" \
  || { echo "Physical output mode was not restored" >&2; exit 1; }
grep -q 'hl.monitor({ output = "HDMI-A-1", mode = "1920x1080@60", position = "2560x0", scale = 1, transform = 0 })' "$HYPR_MOCK_CALLS" \
  || { echo "Physical output without a description was not restored" >&2; exit 1; }
grep -q 'keyword monitor DP-1,2560x1440@59.95,0x0,1,0' "$HYPR_MOCK_CALLS" \
  || { echo "Legacy physical output restore fallback was not used" >&2; exit 1; }
printf '[]\n' > "$HYPR_MOCK_STATE"
echo "PASS Hyprland physical output suspend and restore"

printf '[{"name":"DP-1","description":"Dell Inc. Physical Monitor","width":2560,"height":1440,"refreshRate":59.95,"x":0,"y":0,"scale":1,"transform":0},{"name":"HDMI-A-1","description":"Dell Inc. Physical Monitor","width":1920,"height":1080,"refreshRate":60,"x":2560,"y":0,"scale":1,"transform":0}]\n' \
  > "$HYPR_MOCK_STATE"
HYPR_MOCK_EVAL_RESTORE_FAIL_NAME=HDMI-A-1 "$START" >/dev/null
if HYPR_MOCK_EVAL_RESTORE_FAIL_NAME=HDMI-A-1 "$STOP" >/dev/null 2>&1; then
  echo "Monitor restoration failure was ignored" >&2
  exit 1
fi
jq -e 'length == 2 and any(.[]; .name == "sunshine-vmon") and any(.[]; .name == "DP-1") and all(.[]; .name != "HDMI-A-1")' \
  "$HYPR_MOCK_STATE" >/dev/null || { echo "Failed restore left the physical monitor state inconsistent" >&2; exit 1; }
[[ -e $STATE_DIR/state && -e $STATE_DIR/physical-monitors.json ]] \
  || { echo "Failed restore did not leave state intact for recovery" >&2; exit 1; }
rm -f -- "$STATE_DIR/state" "$STATE_DIR/physical-monitors.json" "$STATE_DIR/references" "$STATE_DIR/owned"
rmdir "$STATE_DIR" 2>/dev/null || true
printf '[]\n' > "$HYPR_MOCK_STATE"
echo "PASS Hyprland physical-output restore verification"

printf '[{"name":"DP-1","description":"Dell Inc. Physical Monitor","width":2560,"height":1440,"refreshRate":59.95,"x":0,"y":0,"scale":1,"transform":0}]\n' \
  > "$HYPR_MOCK_STATE"
if HYPR_MOCK_EVAL_NOOP_NAME=DP-1 "$START" >/dev/null 2>&1; then
  echo "Silent physical-output disable failure was not detected" >&2
  exit 1
fi
jq -e 'length == 1 and .[0].name == "DP-1"' "$HYPR_MOCK_STATE" >/dev/null \
  || { echo "Silent disable failure did not roll back cleanly" >&2; exit 1; }
[[ ! -e $STATE_DIR/state && ! -e $STATE_DIR/physical-monitors.json ]] \
  || { echo "Silent disable failure left active lifecycle state behind" >&2; exit 1; }
printf '[]\n' > "$HYPR_MOCK_STATE"
echo "PASS Hyprland silent physical-output disable failure"

printf '[{"name":"DP-1","description":"DP-1 Physical Monitor","width":2560,"height":1440,"refreshRate":59.95,"x":0,"y":0,"scale":1,"transform":0},{"name":"HDMI-A-1","description":"HDMI-A-1 Physical Monitor","width":1920,"height":1080,"refreshRate":60,"x":2560,"y":0,"scale":1,"transform":0}]\n' \
  > "$HYPR_MOCK_STATE"
if HYPR_MOCK_EVAL_FAIL_NAME=HDMI-A-1 HYPR_MOCK_KEYWORD_FAIL_NAME=HDMI-A-1 \
    "$START" >/dev/null 2>&1; then
  echo "Partial physical-output disable failure was ignored" >&2
  exit 1
fi
jq -e 'length == 2 and any(.[]; .name == "DP-1") and any(.[]; .name == "HDMI-A-1")' \
  "$HYPR_MOCK_STATE" >/dev/null || {
    echo "Failed start did not restore disabled physical outputs: $(<"$HYPR_MOCK_STATE")" >&2
    exit 1
  }
[[ ! -e $STATE_DIR/state && ! -e $STATE_DIR/physical-monitors.json ]] \
  || { echo "Failed start left active lifecycle state behind" >&2; exit 1; }
printf '[]\n' > "$HYPR_MOCK_STATE"
echo "PASS Hyprland failed-start physical output rollback"

printf '[{"name":"sunshine-vmon"}]\n' > "$HYPR_MOCK_STATE"
printf '1\n' > "$STATE_DIR/references"
printf '1\n' > "$STATE_DIR/owned"
"$START"
[[ $(sed -n '1p' "$STATE_DIR/state") == 2 && $(sed -n '2p' "$STATE_DIR/state") == 1 ]] \
  || { echo "Legacy lifecycle state was not migrated" >&2; exit 1; }
[[ ! -e $STATE_DIR/references && ! -e $STATE_DIR/owned ]] \
  || { echo "Legacy lifecycle state files were not removed" >&2; exit 1; }
"$STOP"
"$STOP"
jq -e 'length == 0' "$HYPR_MOCK_STATE" >/dev/null
echo "PASS Hyprland legacy state migration"

HYPR_MOCK_EVAL_FAIL=1 SUNSHINE_CLIENT_WIDTH=1920 SUNSHINE_CLIENT_HEIGHT=1080 \
  SUNSHINE_CLIENT_FPS=75 "$START"
grep -q 'keyword keyword monitor sunshine-vmon,1920x1080@75,9999x0,1' "$HYPR_MOCK_CALLS" \
  || { echo "Keyword fallback or custom FPS failed" >&2; exit 1; }
"$STOP"

if HYPR_MOCK_EVAL_FAIL=1 HYPR_MOCK_KEYWORD_FAIL=1 "$START" >/dev/null 2>&1; then
  echo "Monitor configuration failure was ignored" >&2
  exit 1
fi
jq -e 'length == 0' "$HYPR_MOCK_STATE" >/dev/null \
  || { echo "Failed start left a headless output behind" >&2; exit 1; }
[[ ! -e $STATE_DIR/state ]] || { echo "Failed start committed reference state" >&2; exit 1; }
echo "PASS Hyprland fallback and failed-start cleanup"

printf '[{"name":"sunshine-vmon"}]\n' > "$HYPR_MOCK_STATE"
if "$START" >/dev/null 2>&1; then
  echo "Existing unmanaged output was altered" >&2
  exit 1
fi
jq -e 'length == 1 and .[0].name == "sunshine-vmon"' "$HYPR_MOCK_STATE" >/dev/null
printf '[]\n' > "$HYPR_MOCK_STATE"

remove_vmon_hyprland >/dev/null
grep -q '^capture = x11$' "$NATIVE_CONF" || { echo "Native capture setting was not restored" >&2; exit 1; }
grep -q '^output_name = old-output$' "$NATIVE_CONF" || { echo "Native output name was not restored" >&2; exit 1; }
[[ ! -e $START && ! -e $STOP ]] || { echo "Native hooks were not removed" >&2; exit 1; }
[[ ! -e $RUNTIME ]] || { echo "Native runtime helper was not removed" >&2; exit 1; }
echo "PASS Hyprland unmanaged-output protection and native restore"

FLATPAK_CONF="$HOME/.var/app/$FLATPAK_ID/config/sunshine/sunshine.conf"
FLATPAK_APPS="$HOME/.var/app/$FLATPAK_ID/config/sunshine/apps.json"
printf 'capture = wayland\noutput_name = original-flatpak\n' > "$FLATPAK_CONF"
printf '{"env":{},"apps":[]}\n' > "$FLATPAK_APPS"
TEST_MODE=flatpak
export WAYLAND_DISPLAY='wayland test display'
setup_vmon_hyprland >/dev/null
DO_CMD=$(jq -r '.apps[] | select(.name == "Virtual Monitor (Hyprland)") | .["prep-cmd"][0].do' "$FLATPAK_APPS")
UNDO_CMD=$(jq -r '.apps[] | select(.name == "Virtual Monitor (Hyprland)") | .["prep-cmd"][0].undo' "$FLATPAK_APPS")
[[ $DO_CMD == flatpak-spawn\ --host* ]] || { echo "Flatpak host hook was not generated" >&2; exit 1; }
SUNSHINE_CLIENT_WIDTH=1600 SUNSHINE_CLIENT_HEIGHT=900 SUNSHINE_CLIENT_FPS=120 bash -c "$DO_CMD"
grep -q '1600x900@120' "$HYPR_MOCK_CALLS" || { echo "Flatpak client mode was not passed to host" >&2; exit 1; }
[[ $(<"$HYPR_MOCK_ENV") == 'wayland test display' ]] \
  || { echo "Flatpak command environment was not preserved" >&2; exit 1; }
bash -c "$UNDO_CMD"
jq -e 'length == 0' "$HYPR_MOCK_STATE" >/dev/null
remove_vmon_hyprland >/dev/null
grep -q '^capture = wayland$' "$FLATPAK_CONF" || { echo "Flatpak capture setting was not restored" >&2; exit 1; }
grep -q '^output_name = original-flatpak$' "$FLATPAK_CONF" || { echo "Flatpak output name was not restored" >&2; exit 1; }
echo "PASS Hyprland Flatpak hooks and config restore"
