# shellcheck shell=bash
# Hyprland virtual-monitor setup.
# shellcheck disable=SC2154

setup_vmon_hyprland() {
  local conf start_script stop_script app_name do_cmd undo_cmd session_env_args flatpak_env_args
  local env_name env_value quoted start_script_q stop_script_q
  app_name="Virtual Monitor (Hyprland)"

  if ! command -v hyprctl >/dev/null 2>&1; then
    echo "${red}hyprctl was not found. Run this from an active Hyprland session.${normal}" >&2
    return 1
  fi
  if ! command -v jq >/dev/null 2>&1; then
    if (( IMMUTABLE )); then
      echo "${red}jq is required on the host. Install it through the system's supported layering method.${normal}" >&2
      return 1
    fi
    pkg_install jq || return 1
  fi
  if ! command -v flock >/dev/null 2>&1; then
    echo "${red}'flock' is required for safe Hyprland monitor lifecycle handling.${normal}" >&2
    return 1
  fi
  if ! hyprctl monitors -j | jq -e 'type == "array"' >/dev/null 2>&1; then
    echo "${red}Could not connect to the active Hyprland compositor.${normal}" >&2
    return 1
  fi

  pick_mode || return 1
  if [[ $MODE == flatpak ]]; then
    conf=$(hypr_vmon_flatpak_config)
  else
    conf=$(hypr_vmon_native_config)
  fi
  if [[ ! -f $conf ]]; then
    echo "${red}Sunshine configuration not found at $conf. Start Sunshine once, then retry.${normal}" >&2
    return 1
  fi

  start_script="$HOME/.local/bin/sunshine-start-hyprland-vmon"
  stop_script="$HOME/.local/bin/sunshine-stop-hyprland-vmon"
  mkdir -p "$HOME/.local/bin"
  cat > "$start_script" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

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

mkdir -p "$STATE_DIR"
chmod 700 "$STATE_DIR"
exec 9>"$STATE_DIR/lock"
flock -x 9

REFS=0
OWNED=0
if [[ -f $STATE_DIR/references ]]; then
  IFS= read -r REFS < "$STATE_DIR/references" || true
  [[ $REFS =~ ^[0-9]+$ ]] || { echo "Invalid Hyprland virtual-monitor reference state." >&2; exit 1; }
fi
if [[ -f $STATE_DIR/owned ]]; then
  IFS= read -r OWNED < "$STATE_DIR/owned" || true
  [[ $OWNED == 0 || $OWNED == 1 ]] || { echo "Invalid Hyprland virtual-monitor ownership state." >&2; exit 1; }
fi

if (( REFS == 0 )); then
  if [[ -e $STATE_DIR/owned ]]; then
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
  for attempt in $(seq 1 20); do
    if monitor_exists; then FOUND=1; break; fi
    sleep 0.25
  done
  if (( ! FOUND )); then
    (( CREATED_NOW )) && hyprctl output remove "$NAME" >/dev/null 2>&1 || true
    echo "The Hyprland headless output did not appear." >&2
    exit 1
  fi
fi

if ! configure_monitor; then
  if (( CREATED_NOW )); then hyprctl output remove "$NAME" >/dev/null 2>&1 || true; fi
  echo "Could not configure the Hyprland headless output mode ($RES)." >&2
  exit 1
fi

printf '%s\n' "$((REFS + 1))" > "$STATE_DIR/references.tmp"
printf '%s\n' "$OWNED" > "$STATE_DIR/owned.tmp"
mv "$STATE_DIR/references.tmp" "$STATE_DIR/references"
mv "$STATE_DIR/owned.tmp" "$STATE_DIR/owned"
EOF
  cat > "$stop_script" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

NAME="sunshine-vmon"
STATE_DIR="${XDG_RUNTIME_DIR:-/tmp}/sunshine-hyprland-vmon-$(id -u)"
[[ -d $STATE_DIR ]] || exit 0
exec 9>"$STATE_DIR/lock"
flock -x 9
[[ -f $STATE_DIR/references ]] || exit 0

REFS=""
OWNED=0
IFS= read -r REFS < "$STATE_DIR/references" || true
[[ $REFS =~ ^[0-9]+$ ]] || { echo "Invalid Hyprland virtual-monitor reference state." >&2; exit 1; }
if [[ -f $STATE_DIR/owned ]]; then
  IFS= read -r OWNED < "$STATE_DIR/owned" || true
fi
(( REFS > 0 )) || { echo "Invalid Hyprland virtual-monitor reference count." >&2; exit 1; }
if (( REFS > 1 )); then
  printf '%s\n' "$((REFS - 1))" > "$STATE_DIR/references.tmp"
  mv "$STATE_DIR/references.tmp" "$STATE_DIR/references"
  exit 0
fi

if (( OWNED )); then
  if hyprctl monitors -j | jq -e --arg name "$NAME" 'type == "array" and any(.[]; .name == $name)' >/dev/null 2>&1; then
    hyprctl output remove "$NAME"
  fi
fi
rm -f -- "$STATE_DIR/references" "$STATE_DIR/owned" "$STATE_DIR/references.tmp" "$STATE_DIR/owned.tmp"
rmdir "$STATE_DIR" 2>/dev/null || true
EOF
  chmod 755 "$start_script" "$stop_script"

  session_env_args=""
  flatpak_env_args=""
  for env_name in HYPRLAND_INSTANCE_SIGNATURE WAYLAND_DISPLAY XDG_RUNTIME_DIR DBUS_SESSION_BUS_ADDRESS; do
    env_value=${!env_name:-}
    [[ -n $env_value ]] || continue
    printf -v quoted '%q' "$env_value"
    session_env_args+=" $env_name=$quoted"
    flatpak_env_args+=" --env=$env_name=$quoted"
  done
  printf -v start_script_q '%q' "$start_script"
  printf -v stop_script_q '%q' "$stop_script"

  if [[ $MODE == flatpak ]]; then
    do_cmd="flatpak-spawn --host$flatpak_env_args env SUNSHINE_CLIENT_WIDTH=\"\${SUNSHINE_CLIENT_WIDTH:-}\" SUNSHINE_CLIENT_HEIGHT=\"\${SUNSHINE_CLIENT_HEIGHT:-}\" SUNSHINE_CLIENT_FPS=\"\${SUNSHINE_CLIENT_FPS:-}\" $start_script_q"
    undo_cmd="flatpak-spawn --host$flatpak_env_args env $stop_script_q"
  else
    do_cmd="env$session_env_args $start_script_q"
    undo_cmd="env$session_env_args $stop_script_q"
  fi

  mkdir -p "$(dirname "$APP_CONF")"
  [[ -f $APP_CONF ]] || printf '{"env":{},"apps":[]}\n' > "$APP_CONF"
  local tmp
  tmp=$(mktemp "${APP_CONF}.sunshine-vmon.XXXXXX") || return 1
  if ! jq --arg name "$app_name" --arg cmd_do "$do_cmd" --arg cmd_undo "$undo_cmd" '
    {
      "name": $name, "cmd": "", "output": "", "image-path": "",
      "auto-detach": true, "elevated": false, "exclude-global-prep-cmd": false,
      "exit-timeout": 5, "wait-all": true,
      "prep-cmd": [{"do": $cmd_do, "undo": $cmd_undo}]
    } as $app
    | .apps = ((.apps // []) | map(select(.name != $app.name)) + [$app])
  ' "$APP_CONF" > "$tmp"; then
    rm -f -- "$tmp"
    echo "${red}Could not update $APP_CONF (invalid JSON?).${normal}" >&2
    return 1
  fi
  if ! mv "$tmp" "$APP_CONF"; then
    rm -f -- "$tmp"
    return 1
  fi

  if ! hypr_vmon_prepare_config "$conf"; then
    tmp=$(mktemp "${APP_CONF}.sunshine-vmon.XXXXXX") || return 1
    if jq --arg name "$app_name" '.apps |= map(select(.name != $name))' "$APP_CONF" > "$tmp"; then
      mv "$tmp" "$APP_CONF" || {
        rm -f -- "$tmp"
        echo "${red}Could not roll back the Hyprland app entry in $APP_CONF.${normal}" >&2
        return 1
      }
    else
      rm -f -- "$tmp"
      echo "${red}Could not roll back the Hyprland app entry in $APP_CONF.${normal}" >&2
      return 1
    fi
    echo "${red}Could not configure capture=wlr and output_name in $conf.${normal}" >&2
    return 1
  fi

  cat <<MSG

  ${bold}Hyprland virtual monitor configured (created on demand).${normal}
  The Sunshine app '$app_name' creates a headless output before capture and removes it
  after the session. Capture method 'wlr' and output_name 'sunshine-vmon' were set.
  Restart Sunshine to load these settings.
MSG
}
