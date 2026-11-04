# shellcheck shell=bash
# Hyprland virtual-monitor setup.
# shellcheck disable=SC2154

setup_vmon_hyprland() {
  local conf start_script stop_script runtime_script app_name do_cmd undo_cmd session_env_args flatpak_env_args
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
  runtime_script="$HOME/.local/bin/sunshine-hyprland-vmon-runtime.sh"
  mkdir -p "$HOME/.local/bin" || return 1
  if ! install -m 755 "$SCRIPT_DIR/modules/vmon/hyprland/start.sh" "$start_script" \
      || ! install -m 755 "$SCRIPT_DIR/modules/vmon/hyprland/stop.sh" "$stop_script" \
      || ! install -m 755 "$SCRIPT_DIR/modules/vmon/hyprland/runtime.sh" "$runtime_script"; then
    echo "${red}Could not install the Hyprland virtual-monitor hooks.${normal}" >&2
    return 1
  fi

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
    if jq --arg name "$app_name" '.apps = ((.apps // []) | map(select(.name != $name)))' "$APP_CONF" > "$tmp"; then
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
  after the session. Physical displays are disabled for the session and restored afterward.
  Capture method 'wlr' and output_name 'sunshine-vmon' were set.
  Restart Sunshine to load these settings.
MSG
}
