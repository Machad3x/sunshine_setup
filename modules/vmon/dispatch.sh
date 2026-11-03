# shellcheck shell=bash
# KDE and Hyprland virtual-monitor backend dispatcher.
# shellcheck disable=SC2154

virtual_monitor_backend() {
  if [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} || ${XDG_CURRENT_DESKTOP:-} == *Hyprland* ]]; then
    printf '%s\n' hyprland
  elif [[ ${XDG_CURRENT_DESKTOP:-} == *KDE* || ${KDE_FULL_SESSION:-} == true ]]; then
    printf '%s\n' kde
  else
    echo "Could not identify a supported desktop session. Virtual monitors require KDE Plasma (Wayland) or Hyprland." >&2
    return 1
  fi
}

setup_vmon() {
  local backend
  backend=$(virtual_monitor_backend) || return 1
  case $backend in
    kde) setup_vmon_kde ;;
    hyprland) setup_vmon_hyprland ;;
  esac
}

vmon_app_configured() {
  local conf=$1 name=$2
  [[ -f $conf ]] || return 1
  if ! command -v jq >/dev/null 2>&1; then
    echo "'jq' is required to inspect $conf." >&2
    return 2
  fi
  if ! jq -e '.apps | type == "array"' "$conf" >/dev/null 2>&1; then
    echo "Could not inspect $conf (invalid JSON or apps list)." >&2
    return 2
  fi
  jq -e --arg name "$name" 'any(.apps[]; .name == $name)' "$conf" >/dev/null
}

remove_vmon() {
  local backend conf status kde_configured=0 hyprland_configured=0
  for conf in "$HOME/.config/sunshine/apps.json" \
              "$HOME/.var/app/$FLATPAK_ID/config/sunshine/apps.json"; do
    if vmon_app_configured "$conf" "Virtual Monitor"; then
      kde_configured=1
    else
      status=$?
      (( status == 1 )) || return "$status"
    fi
    if vmon_app_configured "$conf" "Virtual Monitor (Hyprland)"; then
      hyprland_configured=1
    else
      status=$?
      (( status == 1 )) || return "$status"
    fi
  done
  [[ -f $(hypr_vmon_state_dir)/config-path ]] && hyprland_configured=1
  [[ -f $BIN_DIR/sunshine-vmon-common.sh ]] && kde_configured=1

  if (( hyprland_configured || kde_configured )); then
    if (( hyprland_configured )); then
      remove_vmon_hyprland || return 1
    fi
    if (( kde_configured )); then
      remove_vmon_kde || return 1
    fi
    return 0
  fi

  backend=$(virtual_monitor_backend) || return 1
  case $backend in
    kde) remove_vmon_kde ;;
    hyprland) remove_vmon_hyprland ;;
  esac
}
