#!/usr/bin/env bash
set -euo pipefail
umask 077
source "$(dirname -- "${BASH_SOURCE[0]}")/sunshine-hyprland-vmon-runtime.sh"
hypr_vmon_resolve_session

NAME="sunshine-vmon"
STATE_DIR="${XDG_RUNTIME_DIR:-$HOME/.cache}/sunshine-hyprland-vmon-$(id -u)"
PHYSICAL_STATE="$STATE_DIR/physical-monitors.json"
[[ -d $STATE_DIR ]] || exit 0
exec 9>"$STATE_DIR/lock"
flock -x 9
[[ -f $STATE_DIR/state || -f $STATE_DIR/references || -f $PHYSICAL_STATE ]] || exit 0

REFS=""
OWNED=0
STATE_TMP=""
cleanup_state_tmp() {
  [[ -n $STATE_TMP ]] && rm -f -- "$STATE_TMP" || true
}
trap cleanup_state_tmp EXIT

if [[ -f $STATE_DIR/state ]]; then
  local_state=()
  mapfile -t local_state < "$STATE_DIR/state"
  [[ ${#local_state[@]} == 2 ]] || { echo "Invalid Hyprland virtual-monitor state." >&2; exit 1; }
  REFS=${local_state[0]}
  OWNED=${local_state[1]}
else
  IFS= read -r REFS < "$STATE_DIR/references" || true
  if [[ -f $STATE_DIR/owned ]]; then
    IFS= read -r OWNED < "$STATE_DIR/owned" || true
  fi
  if [[ ! -f $STATE_DIR/references && -f $PHYSICAL_STATE ]]; then
    REFS=1
  fi
fi
[[ $REFS =~ ^[0-9]+$ ]] || { echo "Invalid Hyprland virtual-monitor reference state." >&2; exit 1; }
[[ $OWNED == 0 || $OWNED == 1 ]] || { echo "Invalid Hyprland virtual-monitor ownership state." >&2; exit 1; }
(( REFS > 0 )) || { echo "Invalid Hyprland virtual-monitor reference count." >&2; exit 1; }
if (( REFS > 1 )); then
  STATE_TMP=$(mktemp "$STATE_DIR/state.XXXXXX")
  printf '%s\n%s\n' "$((REFS - 1))" "$OWNED" > "$STATE_TMP"
  mv "$STATE_TMP" "$STATE_DIR/state"
  STATE_TMP=""
  rm -f -- "$STATE_DIR/references" "$STATE_DIR/owned" \
    || echo "Warning: legacy Hyprland virtual-monitor state files could not be removed." >&2
  exit 0
fi

if [[ -f $PHYSICAL_STATE ]]; then
  hypr_vmon_apply_physical_monitors restore "$PHYSICAL_STATE"
fi

if (( OWNED )); then
  if hyprctl monitors -j | jq -e --arg name "$NAME" 'type == "array" and any(.[]; .name == $name)' >/dev/null 2>&1; then
    hyprctl output remove "$NAME"
  fi
fi
rm -f -- "$STATE_DIR/state" "$STATE_DIR/references" "$STATE_DIR/owned" "$PHYSICAL_STATE" \
  "$STATE_DIR/references.tmp" "$STATE_DIR/owned.tmp"
rmdir "$STATE_DIR" 2>/dev/null || true
