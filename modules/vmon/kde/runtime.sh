#!/usr/bin/env bash
# Shared state and helpers for the installed KDE virtual-monitor hooks
# (installed as ~/.local/bin/sunshine-vmon-common.sh and sourced by
# sunshine-start-vmon / sunshine-stop-vmon).
# shellcheck disable=SC2034  # variables are consumed by the sourcing hooks
VMON_BASE="${XDG_RUNTIME_DIR:-$HOME/.cache}/sunshine-vmon-$(id -u)"
VMON_PID="${VMON_BASE}.pid"
VMON_STATE_DIR="${VMON_BASE}.state"
SUNSHINE_FLATPAK_CONF="${HOME}/.var/app/dev.lizardbyte.app.Sunshine/config/sunshine/sunshine.conf"
SUNSHINE_CONF="${HOME}/.config/sunshine/sunshine.conf"
CONFIG_TMP=""

# The environment inherited from the Sunshine service (or from flatpak-spawn)
# can be stale after a reboot. Fill in the live session values when missing.
resolve_session_env() {
  local runtime="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}" sock
  export XDG_RUNTIME_DIR="$runtime"
  export QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-wayland}"
  if [[ -z ${WAYLAND_DISPLAY:-} || ! -S "$runtime/${WAYLAND_DISPLAY:-}" ]]; then
    for sock in "$runtime"/wayland-*; do
      [[ -S $sock ]] || continue
      export WAYLAND_DISPLAY="${sock##*/}"
      break
    done
  fi
  if [[ -z ${DBUS_SESSION_BUS_ADDRESS:-} && -S "$runtime/bus" ]]; then
    export DBUS_SESSION_BUS_ADDRESS="unix:path=$runtime/bus"
  fi
}

restore_saved_outputs() {
  local output failed=0
  [[ -f "$VMON_STATE_DIR/enabled-outputs" ]] || return 0
  while IFS= read -r output; do
    [[ -n $output ]] || continue
    if ! kscreen-doctor "output.${output}.enable"; then
      echo "Could not restore display output '$output'." >&2
      failed=1
    fi
  done < "$VMON_STATE_DIR/enabled-outputs"
  return "$failed"
}

restore_saved_config() {
  local conf tmp
  [[ -f "$VMON_STATE_DIR/config-path" && -f "$VMON_STATE_DIR/output-name.original" ]] || return 0
  IFS= read -r conf < "$VMON_STATE_DIR/config-path" || return 1
  case "$conf" in "$SUNSHINE_FLATPAK_CONF"|"$SUNSHINE_CONF") ;; *) return 1 ;; esac
  [[ -f $conf ]] || return 0
  tmp=$(mktemp "${conf}.sunshine-vmon.XXXXXX") || return 1
  CONFIG_TMP=$tmp
  if ! sed -E '/^[[:space:]]*output_name[[:space:]]*(=|$)/d' "$conf" > "$tmp" \
      || ! { if [[ -s "$VMON_STATE_DIR/output-name.original" && -s $tmp ]] \
        && [[ $(tail -c1 "$tmp" | wc -l) -eq 0 ]]; then printf '\n' >> "$tmp"; fi; } \
      || ! cat "$VMON_STATE_DIR/output-name.original" >> "$tmp" \
      || ! chmod --reference="$conf" "$tmp" \
      || ! mv "$tmp" "$conf"; then
    rm -f -- "$tmp"
    CONFIG_TMP=""
    return 1
  fi
  CONFIG_TMP=""
}

is_vmon_process() {
  local pid=$1 process_command=""
  [[ $pid =~ ^[0-9]+$ && -r /proc/$pid/cmdline ]] || return 1
  IFS= read -r -d '' process_command < "/proc/$pid/cmdline" || true
  [[ ${process_command##*/} == krfb-virtualmonitor ]]
}

remove_saved_state() {
  rm -f -- "$VMON_STATE_DIR/enabled-outputs" \
    "$VMON_STATE_DIR/output-name.original" \
    "$VMON_STATE_DIR/config-path" \
    "$VMON_STATE_DIR/outputs.json"
  rmdir "$VMON_STATE_DIR" 2>/dev/null || true
}
