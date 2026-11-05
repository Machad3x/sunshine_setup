# shellcheck shell=bash
# Hyprland virtual-monitor setup.
# shellcheck disable=SC2154

setup_vmon_hyprland() {
  local conf start_script stop_script runtime_script app_name do_cmd undo_cmd
  local start_script_q stop_script_q
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
    echo "  It is provided by the 'util-linux' package." >&2
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

  start_script="$BIN_DIR/sunshine-start-hyprland-vmon"
  stop_script="$BIN_DIR/sunshine-stop-hyprland-vmon"
  runtime_script="$BIN_DIR/sunshine-hyprland-vmon-runtime.sh"
  mkdir -p "$BIN_DIR" || return 1
  if ! install -m 755 "$SCRIPT_DIR/modules/vmon/hyprland/start.sh" "$start_script" \
      || ! install -m 755 "$SCRIPT_DIR/modules/vmon/hyprland/stop.sh" "$stop_script" \
      || ! install -m 755 "$SCRIPT_DIR/modules/vmon/hyprland/runtime.sh" "$runtime_script"; then
    echo "${red}Could not install the Hyprland virtual-monitor hooks.${normal}" >&2
    return 1
  fi

  # Do not bake the session environment (HYPRLAND_INSTANCE_SIGNATURE,
  # WAYLAND_DISPLAY, ...) into apps.json: those values go stale after a reboot
  # or a compositor restart. The installed hooks resolve them at runtime.
  printf -v start_script_q '%q' "$start_script"
  printf -v stop_script_q '%q' "$stop_script"

  if [[ $MODE == flatpak ]]; then
    do_cmd="flatpak-spawn --host --env=SUNSHINE_CLIENT_WIDTH --env=SUNSHINE_CLIENT_HEIGHT --env=SUNSHINE_CLIENT_FPS $start_script_q"
    undo_cmd="flatpak-spawn --host $stop_script_q"
  else
    do_cmd="$start_script_q"
    undo_cmd="$stop_script_q"
  fi

  vmon_write_app "$APP_CONF" "$app_name" "$do_cmd" "$undo_cmd" || return 1

  if ! hypr_vmon_prepare_config "$conf"; then
    vmon_remove_app "$APP_CONF" "$app_name"
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
