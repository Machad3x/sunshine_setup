# shellcheck shell=bash
# Shared globals are initialized by sunshine-setup.sh before this module is sourced.
# shellcheck disable=SC2154
# ---------- virtual monitor ----------
setup_vmon_kde() {
  if [[ "${XDG_CURRENT_DESKTOP:-}" != *KDE* ]]; then
    echo "  ${yellow}Warning:${normal} the virtual monitor only works on KDE Plasma (KWin, Wayland)."
    echo "  Current desktop: ${XDG_CURRENT_DESKTOP:-unknown}."
  fi
  pick_mode || return 1

  if (( IMMUTABLE )); then
    local missing=0
    for cmd in krfb-virtualmonitor kscreen-doctor jq; do
      if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "${red}'$cmd' not found.${normal}" >&2
        case $cmd in
          krfb-virtualmonitor)
            if [[ $DISTRO == opensuse-microos ]]; then
              echo "  Install via 'transactional-update pkg install krfb' (requires reboot)." >&2
            else
              echo "  Install via 'rpm-ostree install krfb' (requires reboot)." >&2
            fi
            ;;
          kscreen-doctor)
            if [[ $DISTRO == opensuse-microos ]]; then
              echo "  Install via 'transactional-update pkg install libkscreen' (requires reboot)." >&2
            else
              echo "  Install via 'rpm-ostree install libkscreen' (requires reboot)." >&2
            fi
            ;;
          jq)
            if [[ $DISTRO == opensuse-microos ]]; then
              echo "  Install via 'transactional-update pkg install jq' (requires reboot)." >&2
            else
              echo "  Install via 'rpm-ostree install jq' (requires reboot)." >&2
            fi
            ;;
        esac
        missing=1
      fi
    done
    (( missing )) && return 1
  else
    case $DISTRO in
      fedora)        pkg_install krfb jq libkscreen || return 1 ;;
      arch|cachyos)  pkg_install krfb jq libkscreen || return 1 ;;
      ubuntu|debian) pkg_install krfb jq libkscreen-bin || return 1 ;;
      *)
        echo "${red}No supported package mapping is available for '$DISTRO'.${normal}" >&2
        return 1
        ;;
    esac
    command -v kscreen-doctor >/dev/null || {
      echo "${red}kscreen-doctor not found.${normal} It ships with KDE's kscreen/libkscreen package; is Plasma installed?" >&2; return 1; }
    command -v krfb-virtualmonitor >/dev/null || {
      echo "${red}krfb-virtualmonitor not found.${normal} Requires a recent krfb release." >&2; return 1; }
    command -v jq >/dev/null || {
      echo "${red}jq not found.${normal} Install 'jq' manually and re-run." >&2; return 1; }
  fi

  sudo mkdir -p "$BIN_DIR"
  sudo tee "$BIN_DIR/sunshine-vmon-common.sh" >/dev/null <<'EOF'
#!/usr/bin/env bash
VMON_BASE="${XDG_RUNTIME_DIR:-/tmp}/sunshine-vmon-$(id -u)"
VMON_PID="${VMON_BASE}.pid"
VMON_STATE_DIR="${VMON_BASE}.state"
SUNSHINE_FLATPAK_CONF="${HOME}/.var/app/dev.lizardbyte.app.Sunshine/config/sunshine/sunshine.conf"
SUNSHINE_CONF="${HOME}/.config/sunshine/sunshine.conf"
CONFIG_TMP=""

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
EOF

  sudo tee "$BIN_DIR/sunshine-start-vmon" >/dev/null <<'EOF'
#!/usr/bin/env bash
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
source "$COMMON"
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
      for attempt in $(seq 1 10); do
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
VNC_PASS=$(head -c 24 /dev/urandom | base64 | tr -dc A-Za-z0-9)
krfb-virtualmonitor --resolution "$RES" --name "$NAME" --password "$VNC_PASS" --port "$PORT" &
STARTED_PID=$!
printf '%s\n' "$STARTED_PID" > "$VMON_PID"

found=0
for attempt in $(seq 1 20); do
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
      '(.outputs | type == "array") and any(.outputs[]; .name == $v and .enabled == true)' \
      "$OUTPUTS_JSON" >/dev/null; then
  echo "Could not read the display configuration from kscreen-doctor." >&2
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
EOF

  sudo tee "$BIN_DIR/sunshine-stop-vmon" >/dev/null <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
umask 077
COMMON="${BASH_SOURCE[0]%/*}/sunshine-vmon-common.sh"
source "$COMMON"

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
      for attempt in $(seq 1 10); do
        is_vmon_process "$pid" || break
        sleep 0.2
      done
      if is_vmon_process "$pid"; then
        if ! kill -KILL "$pid" 2>/dev/null; then
          echo "Could not terminate virtual-monitor process $pid." >&2
          failed=1
        else
          for attempt in $(seq 1 10); do
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
EOF

  sudo chmod 644 "$BIN_DIR/sunshine-vmon-common.sh"
  sudo chmod 755 "$BIN_DIR/sunshine-start-vmon" "$BIN_DIR/sunshine-stop-vmon"
  command -v restorecon >/dev/null && sudo restorecon "$BIN_DIR/sunshine-vmon-common.sh" "$BIN_DIR/sunshine-start-vmon" "$BIN_DIR/sunshine-stop-vmon" || true

  local DO UNDO env_name env_value quoted start_script_q stop_script_q flatpak_env_args
  if [[ $MODE == flatpak ]]; then
    local uid; uid=$(id -u)
    local wl_display="${WAYLAND_DISPLAY:-}"
    if [[ -z $wl_display ]]; then
      local wl_socket
      wl_socket=$(find "/run/user/$uid" -maxdepth 1 -type s -name 'wayland-*' -print -quit 2>/dev/null || true)
      wl_display="${wl_socket##*/}"
    fi
    wl_display="${wl_display:-wayland-0}"
    local xdg_rt="${XDG_RUNTIME_DIR:-/run/user/$uid}"
    local dbus_a="${DBUS_SESSION_BUS_ADDRESS:-unix:path=/run/user/$uid/bus}"
    flatpak_env_args=""
    for env_name in QT_QPA_PLATFORM WAYLAND_DISPLAY XDG_RUNTIME_DIR DBUS_SESSION_BUS_ADDRESS; do
      case $env_name in
        QT_QPA_PLATFORM) env_value=wayland ;;
        WAYLAND_DISPLAY) env_value=$wl_display ;;
        XDG_RUNTIME_DIR) env_value=$xdg_rt ;;
        DBUS_SESSION_BUS_ADDRESS) env_value=$dbus_a ;;
      esac
      printf -v quoted '%q' "--env=$env_name=$env_value"
      flatpak_env_args+=" $quoted"
    done
    printf -v start_script_q '%q' "$BIN_DIR/sunshine-start-vmon"
    printf -v stop_script_q '%q' "$BIN_DIR/sunshine-stop-vmon"
    DO="flatpak-spawn --host$flatpak_env_args --env=SUNSHINE_CLIENT_WIDTH=\$SUNSHINE_CLIENT_WIDTH --env=SUNSHINE_CLIENT_HEIGHT=\$SUNSHINE_CLIENT_HEIGHT --env=SUNSHINE_CLIENT_FPS=\$SUNSHINE_CLIENT_FPS --env=SUNSHINE_VMON_MODE=flatpak $start_script_q"
    UNDO="flatpak-spawn --host$flatpak_env_args env $stop_script_q"
  else
    printf -v start_script_q '%q' "$BIN_DIR/sunshine-start-vmon"
    printf -v stop_script_q '%q' "$BIN_DIR/sunshine-stop-vmon"
    DO="env SUNSHINE_VMON_MODE=native $start_script_q"
    UNDO="$stop_script_q"
  fi

  mkdir -p "$(dirname "$APP_CONF")"
  [[ -f "$APP_CONF" ]] || echo '{"env":{},"apps":[]}' > "$APP_CONF"
  local TMP; TMP=$(mktemp)
  TEMP_FILES+=("$TMP")
  if jq --arg cmd_do "$DO" --arg cmd_undo "$UNDO" '
    {
      "name": "Virtual Monitor", "cmd": "", "output": "", "image-path": "",
      "auto-detach": true, "elevated": false, "exclude-global-prep-cmd": false,
      "exit-timeout": 5, "wait-all": true,
      "prep-cmd": [{"do": $cmd_do, "undo": $cmd_undo}]
    } as $app
    | .apps = ((.apps // []) | map(select(.name != $app.name)) + [$app])
  ' "$APP_CONF" > "$TMP"; then
    mv "$TMP" "$APP_CONF"
    echo "  'Virtual Monitor' app written to $APP_CONF"
  else
    rm -f "$TMP"
    echo "${red}Could not update $APP_CONF (invalid JSON?).${normal}" >&2
    return 1
  fi

  local DROPIN="$HOME/.config/systemd/user/${UNIT}.d"
  mkdir -p "$DROPIN"
  printf '[Service]\nExecStopPost=%s/sunshine-stop-vmon\n' "$BIN_DIR" > "$DROPIN/vmon.conf"
  systemctl --user daemon-reload

  cat <<MSG

  ${bold}Virtual monitor configured.${normal}
  If Moonlight shows "Error 503", use option 3.

  ${yellow}${bold}IMPORTANT:${normal}${yellow} the virtual monitor only works if Sunshine uses KWin Screencast.${normal}
    In the Sunshine web UI (https://localhost:47990), go to
    Configuration > Audio/Video and set ${bold}Capture Method = KWin Screencast${normal},
    then save and restart Sunshine (systemctl --user restart ${UNIT}).
MSG
}
