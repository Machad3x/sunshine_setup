#!/usr/bin/env bash
# KDE virtual-monitor stop hook (installed as ~/.local/bin/sunshine-stop-vmon).
set -euo pipefail
umask 077
COMMON="${BASH_SOURCE[0]%/*}/sunshine-vmon-common.sh"
# shellcheck source=./runtime.sh
source "$COMMON"
resolve_session_env

cleanup_config_tmp() {
  [[ -n $CONFIG_TMP ]] && rm -f -- "$CONFIG_TMP" || true
}
trap cleanup_config_tmp EXIT

failed=0
had_state=0
had_pid=0
if [[ -f "$VMON_PID" ]]; then had_pid=1; fi
if [[ -d "$VMON_STATE_DIR" ]]; then
  had_state=1
  restore_saved_outputs || failed=1
  restore_saved_config || failed=1
fi

if [[ -f "$VMON_PID" ]]; then
  pid=$(cat "$VMON_PID")
  if is_vmon_process "$pid"; then
    if ! kill "$pid" 2>/dev/null; then
      echo "Could not stop virtual-monitor process $pid." >&2
      failed=1
    else
      for ((attempt = 1; attempt <= 10; attempt++)); do
        is_vmon_process "$pid" || break
        sleep 0.2
      done
      if is_vmon_process "$pid"; then
        if ! kill -KILL "$pid" 2>/dev/null; then
          echo "Could not terminate virtual-monitor process $pid." >&2
          failed=1
        else
          for ((attempt = 1; attempt <= 10; attempt++)); do
            is_vmon_process "$pid" || break
            sleep 0.2
          done
          if is_vmon_process "$pid"; then
            echo "Virtual-monitor process $pid is still running after SIGKILL." >&2
            failed=1
          fi
        fi
      fi
    fi
  elif [[ ! $pid =~ ^[0-9]+$ ]]; then
    echo "Ignoring invalid virtual-monitor PID file." >&2
    failed=1
  elif kill -0 "$pid" 2>/dev/null; then
    echo "PID $pid does not belong to krfb-virtualmonitor; refusing to terminate it." >&2
    failed=1
  fi
  if (( ! failed )); then rm -f -- "$VMON_PID"; fi
fi

if (( failed )); then
  echo "Virtual-monitor cleanup was incomplete; saved state remains in $VMON_STATE_DIR." >&2
  exit 1
fi
if (( had_state )); then remove_saved_state; fi
if (( had_pid && !had_state )); then
  echo "No saved display state was available; existing output states were left unchanged." >&2
fi
