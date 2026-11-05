#!/usr/bin/env bash
# KDE virtual-monitor start hook (installed as ~/.local/bin/sunshine-start-vmon).
set -euo pipefail
umask 077
WIDTH="${SUNSHINE_CLIENT_WIDTH:-1920}"
HEIGHT="${SUNSHINE_CLIENT_HEIGHT:-1080}"
FPS="${SUNSHINE_CLIENT_FPS:-60}"
FPS="${FPS%.*}"
[[ $WIDTH =~ ^[1-9][0-9]{0,4}$ ]] && (( WIDTH <= 16384 )) || WIDTH=1920
[[ $HEIGHT =~ ^[1-9][0-9]{0,4}$ ]] && (( HEIGHT <= 16384 )) || HEIGHT=1080
[[ $FPS =~ ^[1-9][0-9]{0,3}$ ]] && (( FPS <= 1000 )) || FPS=60
FPS_MHZ=$(( 10#$FPS * 1000 ))
RES="${WIDTH}x${HEIGHT}"
NAME="sunshine-vmon"

COMMON="${BASH_SOURCE[0]%/*}/sunshine-vmon-common.sh"
# shellcheck source=./runtime.sh
source "$COMMON"
resolve_session_env
OUTPUTS_JSON="$VMON_STATE_DIR/outputs.json"
VMON_MODE="${SUNSHINE_VMON_MODE:-}"
STARTED_PID=""
SETUP_COMPLETE=0

process_is_running() {
  local pid=$1 stat_line state
  [[ -r /proc/$pid/stat ]] || return 1
  IFS= read -r stat_line < "/proc/$pid/stat" || return 1
  stat_line=${stat_line##*) }
  state=${stat_line%% *}
  [[ -n $state && $state != Z ]]
}

cleanup_failed_start() {
  local status=$1 failed=0
  trap - EXIT
  if (( ! SETUP_COMPLETE )); then
    set +e
    restore_saved_outputs || failed=1
    restore_saved_config || failed=1
    [[ -n $CONFIG_TMP ]] && rm -f -- "$CONFIG_TMP"
    if [[ -n $STARTED_PID ]]; then
      kill -TERM "$STARTED_PID" 2>/dev/null
      for ((attempt = 1; attempt <= 10; attempt++)); do
        process_is_running "$STARTED_PID" || break
        sleep 0.2
      done
      if process_is_running "$STARTED_PID"; then
        kill -KILL "$STARTED_PID" 2>/dev/null
        sleep 0.2
      fi
      if process_is_running "$STARTED_PID"; then
        echo "Could not terminate virtual-monitor process $STARTED_PID." >&2
        failed=1
      else
        wait "$STARTED_PID" 2>/dev/null
        rm -f -- "$VMON_PID"
      fi
    fi
    rm -f -- "$OUTPUTS_JSON"
    if (( failed )); then
      echo "Virtual monitor rollback was incomplete; saved state remains in $VMON_STATE_DIR." >&2
    else
      remove_saved_state
    fi
  fi
  exit "$status"
}
trap 'cleanup_failed_start $?' EXIT

if [[ $VMON_MODE == flatpak ]]; then
  CONF="$SUNSHINE_FLATPAK_CONF"
elif [[ $VMON_MODE == native ]]; then
  CONF="$SUNSHINE_CONF"
elif [[ -f "$SUNSHINE_FLATPAK_CONF" ]]; then
  CONF="$SUNSHINE_FLATPAK_CONF"
elif [[ -f "$SUNSHINE_CONF" ]]; then
  CONF="$SUNSHINE_CONF"
else
  echo "No sunshine.conf found!" >&2; exit 1
fi
if [[ ! -f "$CONF" ]]; then
  echo "Sunshine config not found at $CONF (mode: ${VMON_MODE:-auto})." >&2
  exit 1
fi

mkdir -p "$VMON_STATE_DIR"
chmod 700 "$VMON_STATE_DIR"

if [[ -f "$VMON_PID" ]]; then
  existing_pid=$(cat "$VMON_PID")
  if is_vmon_process "$existing_pid"; then
    SETUP_COMPLETE=1
    echo "sunshine-vmon already running (pid $existing_pid)."
    exit 0
  fi
  if [[ $existing_pid =~ ^[0-9]+$ ]] && kill -0 "$existing_pid" 2>/dev/null; then
    echo "Ignoring stale virtual-monitor PID file that points to another process." >&2
  fi
  rm -f -- "$VMON_PID"
fi

if [[ -f "$VMON_STATE_DIR/enabled-outputs" || -f "$VMON_STATE_DIR/config-path" ]]; then
  recovery_failed=0
  restore_saved_outputs || recovery_failed=1
  restore_saved_config || recovery_failed=1
  if (( recovery_failed )); then
    SETUP_COMPLETE=1
    echo "Could not recover the previous virtual monitor state; saved state remains in $VMON_STATE_DIR." >&2
    exit 1
  fi
  remove_saved_state
fi

pick_free_port() {
  local p
  if ! command -v ss >/dev/null 2>&1; then
    echo "ss is unavailable; trying virtual-monitor port 5905." >&2
    echo 5905
    return 0
  fi
  for p in 5905 5906 5907 5908 5909; do
    if ! ss -H -ltn 2>/dev/null | awk -v suffix=":$p" '$4 ~ (suffix "$") { found=1 } END { exit found ? 0 : 1 }'; then
      echo "$p"; return 0
    fi
  done
  return 1
}
if ! PORT=$(pick_free_port); then
  echo "Could not find a free virtual-monitor port (5905-5909)." >&2
  exit 1
fi

echo "Creating virtual display: $RES @ ${FPS}Hz"
# VNC passwords are truncated to 8 characters by krfb anyway; keep exactly
# that many random characters so nothing is promised beyond what is applied.
VNC_RAW=$(head -c 24 /dev/urandom | base64 | tr -dc A-Za-z0-9)
VNC_PASS=${VNC_RAW:0:8}
krfb-virtualmonitor --resolution "$RES" --name "$NAME" --password "$VNC_PASS" --port "$PORT" &
STARTED_PID=$!
printf '%s\n' "$STARTED_PID" > "$VMON_PID"

found=0
for ((attempt = 1; attempt <= 20; attempt++)); do
  if ! kill -0 "$STARTED_PID" 2>/dev/null; then
    echo "krfb-virtualmonitor exited before creating the virtual display." >&2
    exit 1
  fi
  if kscreen-doctor --json > "$OUTPUTS_JSON" 2>/dev/null \
      && jq -e --arg v "Virtual-$NAME" '.outputs[]? | select(.name == $v)' "$OUTPUTS_JSON" >/dev/null 2>&1; then
    found=1
    break
  fi
  sleep 0.5
done
if (( ! found )); then
  echo "The virtual display did not appear within 10 seconds." >&2
  exit 1
fi

kscreen-doctor "output.Virtual-${NAME}.addCustomMode.${WIDTH}.${HEIGHT}.${FPS_MHZ}.full"
if ! kscreen-doctor --json > "$OUTPUTS_JSON" \
    || ! jq -e --arg v "Virtual-$NAME" \
      '(.outputs | type == "array") and any(.outputs[];
        .name == $v and (.enabled == true or (.enabled == null and .connected == true)))' \
      "$OUTPUTS_JSON" >/dev/null; then
  echo "Virtual display Virtual-$NAME is missing or not connected in kscreen-doctor output." >&2
  exit 1
fi

jq -r --arg v "Virtual-$NAME" \
  '.outputs[]? | select(.name != $v and .enabled == true) | .name' \
  "$OUTPUTS_JSON" > "$VMON_STATE_DIR/enabled-outputs"
printf '%s\n' "$CONF" > "$VMON_STATE_DIR/config-path"
awk '/^[[:space:]]*output_name[[:space:]]*(=|$)/' "$CONF" \
  > "$VMON_STATE_DIR/output-name.original"

while IFS= read -r output; do
  [[ -n $output ]] || continue
  kscreen-doctor "output.${output}.disable"
  sleep 0.5
done < "$VMON_STATE_DIR/enabled-outputs"

tmp=$(mktemp "${CONF}.sunshine-vmon.XXXXXX")
CONFIG_TMP=$tmp
if ! sed -E '/^[[:space:]]*output_name[[:space:]]*(=|$)/d' "$CONF" > "$tmp" \
    || ! { if [[ -s $tmp ]] && [[ $(tail -c1 "$tmp" | wc -l) -eq 0 ]]; then printf '\n' >> "$tmp"; fi; } \
    || ! printf 'output_name = Virtual-%s\n' "$NAME" >> "$tmp" \
    || ! chmod --reference="$CONF" "$tmp" \
    || ! mv "$tmp" "$CONF"; then
  rm -f -- "$tmp"
  CONFIG_TMP=""
  echo "Could not set output_name in $CONF." >&2
  exit 1
fi
CONFIG_TMP=""

rm -f -- "$OUTPUTS_JSON"
SETUP_COMPLETE=1
