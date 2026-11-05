#!/usr/bin/env bash
set -euo pipefail
umask 077
source "${BASH_SOURCE[0]%/*}/sunshine-hyprland-vmon-runtime.sh"
hypr_vmon_resolve_session

NAME=$HYPR_VMON_NAME
STATE_DIR=$(hypr_vmon_runtime_state_dir)
PHYSICAL_STATE="$STATE_DIR/physical-monitors.json"
[[ -d $STATE_DIR ]] || exit 0
exec 9>"$STATE_DIR/lock"
flock -x 9
[[ -f $STATE_DIR/state || -f $PHYSICAL_STATE ]] || exit 0

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
elif [[ -f $PHYSICAL_STATE ]]; then
  # Orphan from a start interrupted before the state was committed: treat
  # the physical snapshot as one active session needing restoration.
  REFS=1
fi
[[ $REFS =~ ^[0-9]+$ ]] || { echo "Invalid Hyprland virtual-monitor reference state." >&2; exit 1; }
[[ $OWNED == 0 || $OWNED == 1 ]] || { echo "Invalid Hyprland virtual-monitor ownership state." >&2; exit 1; }
(( REFS > 0 )) || { echo "Invalid Hyprland virtual-monitor reference count." >&2; exit 1; }
if (( REFS > 1 )); then
  STATE_TMP=$(mktemp "$STATE_DIR/state.XXXXXX")
  printf '%s\n%s\n' "$((REFS - 1))" "$OWNED" > "$STATE_TMP"
  mv "$STATE_TMP" "$STATE_DIR/state"
  STATE_TMP=""
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
rm -f -- "$STATE_DIR/state" "$PHYSICAL_STATE" "$STATE_DIR/lock"
rmdir "$STATE_DIR" 2>/dev/null || true
