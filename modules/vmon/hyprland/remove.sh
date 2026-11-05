# shellcheck shell=bash
# Hyprland virtual-monitor removal.
# shellcheck disable=SC2154

remove_vmon_hyprland() {
  local state_dir app_conf refs=0 start_script stop_script runtime_script
  state_dir=$(hypr_vmon_state_dir)
  # Validate every apps.json first so a broken file cannot leave the Sunshine
  # config restored while app entries stay behind.
  while IFS= read -r app_conf; do
    [[ -f $app_conf ]] || continue
    if ! jq -e '(.apps // []) | type == "array"' "$app_conf" >/dev/null 2>&1; then
      echo "${red}Could not update $app_conf (invalid JSON or apps list).${normal}" >&2
      return 1
    fi
  done < <(apps_conf_paths)
  if ! hypr_vmon_restore_config; then
    echo "${red}Could not safely restore the previous Sunshine configuration; leaving the app entry in place.${normal}" >&2
    return 1
  fi
  while IFS= read -r app_conf; do
    vmon_remove_app "$app_conf" "Virtual Monitor (Hyprland)" || return 1
  done < <(apps_conf_paths)

  local runtime_state
  runtime_state="${XDG_RUNTIME_DIR:-$HOME/.cache}/sunshine-hyprland-vmon-$(id -u)"
  if [[ -f $runtime_state/state ]]; then
    IFS= read -r refs < "$runtime_state/state" || true
    [[ $refs =~ ^[0-9]+$ ]] || refs=1
  fi
  if (( refs > 0 )); then
    echo "  An active Sunshine session still uses the Hyprland scripts; they were kept for its undo hook."
  else
    start_script="$BIN_DIR/sunshine-start-hyprland-vmon"
    stop_script="$BIN_DIR/sunshine-stop-hyprland-vmon"
    runtime_script="$BIN_DIR/sunshine-hyprland-vmon-runtime.sh"
    rm -f -- "$start_script" "$stop_script" "$runtime_script"
  fi

  if [[ -d $state_dir ]]; then
    rm -f -- "$state_dir/config-path" "$state_dir/capture.original" "$state_dir/output-name.original"
    rmdir "$state_dir" 2>/dev/null || true
  fi
  echo "  Hyprland virtual-monitor configuration removed."
}
