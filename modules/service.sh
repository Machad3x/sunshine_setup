# shellcheck shell=bash
# Shared globals are initialized by sunshine-setup.sh before this module is sourced.
# shellcheck disable=SC2154
# ---------- service status / repair helpers ----------
unit_exists() {
  systemctl --user cat "$1" >/dev/null 2>&1
}

print_service_status() {
  local unit=$1 enabled active
  if ! unit_exists "$unit"; then
    echo "  ${red}Unit not found:${normal} $unit"
    return 1
  fi
  systemctl --user is-enabled --quiet "$unit" 2>/dev/null \
    && enabled="${green}enabled${normal}" || enabled="${dim}disabled${normal}"
  systemctl --user is-active --quiet "$unit" 2>/dev/null \
    && active="${green}active (running)${normal}" || active="${red}inactive${normal}"
  echo "  ${dim}Unit:${normal}    $unit"
  echo "  ${dim}Enabled:${normal} $enabled"
  echo "  ${dim}Active:${normal}  $active"
  return 0
}

configure_startup_dropin() {
  local unit=$1 delay=${2:-5} dropin file tmp
  dropin="$HOME/.config/systemd/user/${unit}.d"
  file="$dropin/00-sunshine-setup.conf"
  mkdir -p "$dropin" || return 1
  tmp=$(mktemp "$dropin/.00-sunshine-setup.XXXXXX") || return 1
  if ! {
    printf '[Unit]\nAfter=graphical-session.target\nWants=graphical-session.target\n\n[Service]\n'
    if [[ -n $delay && $delay != 0 ]]; then
      printf 'ExecStartPre=/bin/sleep %s\n' "$delay"
    fi
    printf 'Environment=XDG_CURRENT_DESKTOP=%s\n' "${XDG_CURRENT_DESKTOP:-KDE}"
    printf 'Environment=XDG_SESSION_TYPE=%s\n' "${XDG_SESSION_TYPE:-wayland}"
    if [[ -n ${WAYLAND_DISPLAY:-} ]]; then
      printf 'Environment=WAYLAND_DISPLAY=%s\n' "$WAYLAND_DISPLAY"
    fi
  } > "$tmp" || ! mv -f -- "$tmp" "$file"; then
    rm -f -- "$tmp"
    echo "${red}Could not write the systemd user drop-in $file.${normal}" >&2
    return 1
  fi
  echo "  ${dim}drop-in:${normal}  $file"
}

# Common core of the two repair paths: writes the startup drop-in, disables
# the other flavor's unit so autostart does not fight, then enables+restarts.
apply_startup_fix() {
  local unit=$1 delay=$2 other_unit=$3 ok_label=$4
  configure_startup_dropin "$unit" "$delay" || return 1
  systemctl --user disable --now "$other_unit" 2>/dev/null || true
  systemctl --user daemon-reload
  systemctl --user enable "$unit" 2>/dev/null || true
  if systemctl --user restart "$unit" 2>/dev/null; then
    echo "  ${green}${ok_label} restarted.${normal}"
  else
    echo "  ${yellow}Configured but failed to restart. Check: journalctl --user -u $unit -n 50${normal}"
  fi
}

repair_native_startup() {
  if ! native_installed; then
    echo "${red}Native Sunshine is not installed.${normal}" >&2
    return 1
  fi

  local bin unit
  bin=$(readlink -f "$(command -v sunshine)") || return 1
  [[ -n $bin && -x $bin ]] || {
    echo "${red}Could not resolve the native Sunshine executable.${normal}" >&2
    return 1
  }

  if command -v setcap >/dev/null 2>&1; then
    sudo setcap cap_sys_admin+p "$bin" 2>/dev/null \
      || echo "  ${yellow}Warning:${normal} setcap failed; KMS capture may not work."
    echo "  ${dim}setcap:${normal}  $(getcap "$bin" 2>/dev/null || echo 'not applied')"
  else
    echo "  ${yellow}Warning:${normal} setcap not found. Install 'libcap' (Fedora/Arch) or 'libcap2-bin' (Debian)."
  fi

  unit=$(native_unit)
  apply_startup_fix "$unit" 5 "sunshine.service" "Service"
}

repair_flatpak_startup() {
  if ! flatpak_installed; then
    echo "${red}Sunshine Flatpak is not installed.${normal}" >&2
    return 1
  fi
  apply_startup_fix "$FLATPAK_UNIT" 0 "sunshine.service" "Flatpak service"
}

repair_startup() {
  local scope="${1:-}"
  case $scope in
    --native)  repair_native_startup;  return ;;
    --flatpak) repair_flatpak_startup; return ;;
    "") ;;
    *)
      echo "Unknown Sunshine installation scope: $scope" >&2
      return 2
      ;;
  esac
  if native_installed && flatpak_installed; then
    pick_mode || return 1
    if [[ $MODE == flatpak ]]; then repair_flatpak_startup; else repair_native_startup; fi
  elif native_installed; then
    repair_native_startup
  elif flatpak_installed; then
    repair_flatpak_startup
  else
    echo "${red}Sunshine is not installed.${normal} Install it first (menu option 1, or the 'install' command)." >&2
    return 1
  fi
}

service_action() {
  local action=$1 scope="${2:-}" unit
  case $scope in
    --native)
      if ! native_installed; then
        echo "${red}Native Sunshine is not installed.${normal} Use 'install --native' first." >&2
        return 1
      fi
      unit=$(native_unit)
      ;;
    --flatpak)
      if ! flatpak_installed; then
        echo "${red}Sunshine Flatpak is not installed.${normal} Use 'install --flatpak-system' or 'install --flatpak-user' first." >&2
        return 1
      fi
      unit=$FLATPAK_UNIT
      ;;
    "")
      pick_mode || return 1
      if [[ $MODE == flatpak ]]; then unit=$FLATPAK_UNIT; else unit=$(native_unit); fi
      ;;
    *)
      echo "Unknown scope: $scope" >&2
      return 1
      ;;
  esac
  case $action in
    start)
      if systemctl --user start "$unit"; then
        echo "  ${green}Started${normal} $unit"
      else
        echo "  ${red}Failed to start $unit${normal}" >&2
        return 1
      fi
      ;;
    stop)
      if systemctl --user stop "$unit"; then
        echo "  ${green}Stopped${normal} $unit"
      else
        echo "  ${red}Failed to stop $unit${normal}" >&2
        return 1
      fi
      ;;
    restart)
      if systemctl --user restart "$unit"; then
        echo "  ${green}Restarted${normal} $unit"
      else
        echo "  ${red}Failed to restart $unit${normal}" >&2
        return 1
      fi
      ;;
    enable)
      if systemctl --user enable "$unit"; then
        echo "  ${green}Enabled${normal} $unit (auto-start at login)"
      else
        echo "  ${red}Failed to enable $unit${normal}" >&2
        return 1
      fi
      ;;
    disable)
      if systemctl --user disable "$unit"; then
        echo "  ${green}Disabled${normal} $unit"
      else
        echo "  ${red}Failed to disable $unit${normal}" >&2
        return 1
      fi
      ;;
    status)  systemctl --user status "$unit" --no-pager || true ;;
    logs)    journalctl --user -u "$unit" -n 50 --no-pager || true ;;
    follow)  journalctl --user -u "$unit" -n 50 -f ;;
    *)
      echo "Unknown Sunshine service action: $action" >&2
      return 2
      ;;
  esac
}

# manage_service [scope]: optional --native/--flatpak skips mode detection.
manage_service() {
  local scope="${1:-}" unit label
  case $scope in
    --native)
      if ! native_installed; then
        echo "${red}Native Sunshine is not installed.${normal} Use 'install --native' first." >&2
        return 1
      fi
      MODE=native; unit=$(native_unit)
      ;;
    --flatpak)
      if ! flatpak_installed; then
        echo "${red}Sunshine Flatpak is not installed.${normal} Use 'install --flatpak-system' or 'install --flatpak-user' first." >&2
        return 1
      fi
      MODE=flatpak; unit=$FLATPAK_UNIT
      ;;
    "")
      pick_mode || return 1
      if [[ $MODE == flatpak ]]; then unit=$FLATPAK_UNIT; else unit=$(native_unit); fi
      ;;
    *)
      echo "Unknown scope: $scope" >&2
      return 2
      ;;
  esac
  if [[ $MODE == flatpak ]]; then label=--flatpak; else label=--native; fi

  local -a options=(
    "Start"
    "Stop"
    "Restart"
    "Enable  (auto-start at login)"
    "Disable (no auto-start)"
    "Show status  (systemctl --user status)"
    "Show logs    (last 50 lines)"
    "Follow logs  (live, Ctrl+C to stop)"
  )
  [[ $MODE == native ]] && options+=("Repair native startup (setcap + drop-in)")
  options+=("Back")

  local action
  while true; do
    echo
    echo "  ${bold}Sunshine service${normal}  ${dim}($MODE)${normal}"
    print_service_status "$unit" || true
    echo
    choose "Select" "${options[@]}" || { echo; return 0; }
    action=$REPLY
    if (( action == ${#options[@]} )); then return 0; fi
    case $action in
      1) service_action start "$label" || true ;;
      2) service_action stop "$label" || true ;;
      3) service_action restart "$label" || true ;;
      4) service_action enable "$label" || true ;;
      5) service_action disable "$label" || true ;;
      6) service_action status "$label" || true ;;
      7) service_action logs "$label" || true ;;
      8) service_action follow "$label" || true ;;
      9) if [[ $MODE == native ]]; then repair_native_startup; fi ;;
    esac
  done
}
