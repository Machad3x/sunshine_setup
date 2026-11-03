#!/usr/bin/env bash
set -euo pipefail
umask 077

NAME="sunshine-vmon"
STATE_DIR="${XDG_RUNTIME_DIR:-/tmp}/sunshine-hyprland-vmon-$(id -u)"
WIDTH="${SUNSHINE_CLIENT_WIDTH:-1920}"
HEIGHT="${SUNSHINE_CLIENT_HEIGHT:-1080}"
FPS="${SUNSHINE_CLIENT_FPS:-60}"
FPS="${FPS%.*}"
[[ $WIDTH =~ ^[1-9][0-9]{0,4}$ ]] && (( WIDTH <= 16384 )) || WIDTH=1920
[[ $HEIGHT =~ ^[1-9][0-9]{0,4}$ ]] && (( HEIGHT <= 16384 )) || HEIGHT=1080
[[ $FPS =~ ^[1-9][0-9]{0,3}$ ]] && (( FPS <= 1000 )) || FPS=60
RES="${WIDTH}x${HEIGHT}@${FPS}"
CREATED_NOW=0
STATE_COMMITTED=0
STATE_TMP=""

monitor_json() {
  hyprctl monitors -j
}

monitor_exists() {
  local json
  json=$(monitor_json) || return 1
  jq -e --arg name "$NAME" 'type == "array" and any(.[]; .name == $name)' <<< "$json" >/dev/null
}

configure_monitor() {
  local result
  if result=$(hyprctl eval "hl.monitor({ output = \"$NAME\", mode = \"$RES\", position = \"9999x0\", scale = 1 })" 2>/dev/null) \
      && [[ $result == ok ]]; then
    return 0
  fi
  hyprctl keyword monitor "$NAME,$RES,9999x0,1" >/dev/null
}

cleanup_partial_start() {
  local status=$?
  trap - EXIT
  [[ -n $STATE_TMP ]] && rm -f -- "$STATE_TMP"
  if (( ! STATE_COMMITTED && CREATED_NOW )) && monitor_exists; then
    hyprctl output remove "$NAME" >/dev/null || {
      echo "Could not remove the incomplete Hyprland headless output $NAME." >&2
      status=1
    }
  fi
  exit "$status"
}

trap cleanup_partial_start EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

mkdir -p "$STATE_DIR"
chmod 700 "$STATE_DIR"
exec 9>"$STATE_DIR/lock"
flock -x 9

REFS=0
OWNED=0
if [[ -f $STATE_DIR/state ]]; then
  local_state=()
  mapfile -t local_state < "$STATE_DIR/state"
  [[ ${#local_state[@]} == 2 ]] || { echo "Invalid Hyprland virtual-monitor state." >&2; exit 1; }
  REFS=${local_state[0]}
  OWNED=${local_state[1]}
else
  if [[ -f $STATE_DIR/references ]]; then
    IFS= read -r REFS < "$STATE_DIR/references" || true
  fi
  if [[ -f $STATE_DIR/owned ]]; then
    IFS= read -r OWNED < "$STATE_DIR/owned" || true
  fi
fi
[[ $REFS =~ ^[0-9]+$ ]] || { echo "Invalid Hyprland virtual-monitor reference state." >&2; exit 1; }
[[ $OWNED == 0 || $OWNED == 1 ]] || { echo "Invalid Hyprland virtual-monitor ownership state." >&2; exit 1; }

if (( REFS == 0 )); then
  if [[ -e $STATE_DIR/owned || $OWNED == 1 ]]; then
    echo "A stale Hyprland virtual-monitor state exists; remove it before starting again." >&2
    exit 1
  fi
  if monitor_exists; then
    echo "An unmanaged output named $NAME already exists; refusing to alter it." >&2
    exit 1
  fi
fi

if ! monitor_exists; then
  if ! hyprctl output create headless "$NAME"; then
    if ! monitor_exists; then
      echo "Hyprland could not create the headless output $NAME." >&2
      exit 1
    fi
  else
    CREATED_NOW=1
    OWNED=1
  fi
  FOUND=0
  for ((attempt = 0; attempt < 20; attempt++)); do
    if monitor_exists; then FOUND=1; break; fi
    sleep 0.25
  done
  if (( ! FOUND )); then
    echo "The Hyprland headless output did not appear." >&2
    exit 1
  fi
fi

if ! configure_monitor; then
  echo "Could not configure the Hyprland headless output mode ($RES)." >&2
  exit 1
fi

STATE_TMP=$(mktemp "$STATE_DIR/state.XXXXXX")
printf '%s\n%s\n' "$((REFS + 1))" "$OWNED" > "$STATE_TMP"
mv "$STATE_TMP" "$STATE_DIR/state"
STATE_TMP=""
STATE_COMMITTED=1
rm -f -- "$STATE_DIR/references" "$STATE_DIR/owned" \
  || echo "Warning: legacy Hyprland virtual-monitor state files could not be removed." >&2
