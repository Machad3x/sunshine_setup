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

remove_vmon() {
  local backend
  backend=$(virtual_monitor_backend) || return 1
  case $backend in
    kde) remove_vmon_kde ;;
    hyprland) remove_vmon_hyprland ;;
  esac
}
