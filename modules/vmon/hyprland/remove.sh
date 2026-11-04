# shellcheck shell=bash
# Hyprland virtual-monitor removal.
# shellcheck disable=SC2154

remove_vmon_hyprland() {
  local state_dir app_conf tmp start_script stop_script runtime_script runtime_state refs=0
  state_dir=$(hypr_vmon_state_dir)
  for app_conf in "$HOME/.config/sunshine/apps.json" \
                  "$HOME/.var/app/$FLATPAK_ID/config/sunshine/apps.json"; do
    [[ -f $app_conf ]] || continue
    if ! jq -e '(.apps // []) | type == "array"' "$app_conf" >/dev/null 2>&1; then
      echo "${red}Could not update $app_conf (invalid JSON or apps list).${normal}" >&2
      return 1
    fi
  done
  if ! hypr_vmon_restore_config; then
    echo "${red}Could not safely restore the previous Sunshine configuration; leaving the app entry in place.${normal}" >&2
    return 1
  fi

  for app_conf in "$HOME/.config/sunshine/apps.json" \
                  "$HOME/.var/app/$FLATPAK_ID/config/sunshine/apps.json"; do
    [[ -f $app_conf ]] || continue
    tmp=$(mktemp "${app_conf}.sunshine-vmon.XXXXXX") || return 1
    if ! jq '.apps = ((.apps // []) | map(select(.name != "Virtual Monitor (Hyprland)")))' "$app_conf" > "$tmp"; then
      rm -f -- "$tmp"
      echo "${red}Could not update $app_conf (invalid JSON?).${normal}" >&2
      return 1
    fi
    if ! mv "$tmp" "$app_conf"; then
      rm -f -- "$tmp"
      return 1
    fi
    echo "  Hyprland app entry removed from $app_conf"
  done

  runtime_state="${XDG_RUNTIME_DIR:-/tmp}/sunshine-hyprland-vmon-$(id -u)"
  if [[ -f $runtime_state/state ]]; then
    IFS= read -r refs < "$runtime_state/state" || true
    [[ $refs =~ ^[0-9]+$ ]] || refs=1
  elif [[ -f $runtime_state/references ]]; then
    IFS= read -r refs < "$runtime_state/references" || true
    [[ $refs =~ ^[0-9]+$ ]] || refs=1
  fi
  if (( refs > 0 )); then
    echo "  An active Sunshine session still uses the Hyprland scripts; they were kept for its undo hook."
  else
    start_script="$HOME/.local/bin/sunshine-start-hyprland-vmon"
    stop_script="$HOME/.local/bin/sunshine-stop-hyprland-vmon"
    runtime_script="$HOME/.local/bin/sunshine-hyprland-vmon-runtime.sh"
    rm -f -- "$start_script" "$stop_script" "$runtime_script"
  fi

  if [[ -d $state_dir ]]; then
    rm -f -- "$state_dir/config-path" "$state_dir/capture.original" "$state_dir/output-name.original"
    rmdir "$state_dir" 2>/dev/null || true
  fi
  echo "  Hyprland virtual-monitor configuration removed."
}
