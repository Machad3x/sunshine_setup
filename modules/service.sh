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
  local unit=$1 delay=${2:-5} dropin file
  dropin="$HOME/.config/systemd/user/${unit}.d"
  file="$dropin/00-sunshine-setup.conf"
  mkdir -p "$dropin"
  {
    echo "[Unit]"
    echo "After=graphical-session.target"
    echo "Wants=graphical-session.target"
    echo
    echo "[Service]"
    if [[ -n $delay && $delay != 0 ]]; then
      echo "ExecStartPre=/bin/sleep $delay"
    fi
    echo "Environment=XDG_CURRENT_DESKTOP=${XDG_CURRENT_DESKTOP:-KDE}"
    echo "Environment=XDG_SESSION_TYPE=${XDG_SESSION_TYPE:-wayland}"
    if [[ -n ${WAYLAND_DISPLAY:-} ]]; then
      echo "Environment=WAYLAND_DISPLAY=$WAYLAND_DISPLAY"
    fi
  } > "$file"
  echo "  ${dim}drop-in:${normal}  $file"
}

repair_native_startup() {
  if ! native_installed; then
    echo "${red}Native Sunshine is not installed.${normal}" >&2
    return 1
  fi

  local bin unit
  bin=$(readlink -f "$(command -v sunshine)")

  if command -v setcap >/dev/null 2>&1; then
    sudo setcap cap_sys_admin+p "$bin" 2>/dev/null \
      || echo "  ${yellow}Warning:${normal} setcap failed; KMS capture may not work."
    echo "  ${dim}setcap:${normal}  $(getcap "$bin" 2>/dev/null || echo 'not applied')"
  else
    echo "  ${yellow}Warning:${normal} setcap not found. Install 'libcap' (Fedora/Arch) or 'libcap2-bin' (Debian)."
  fi

  unit=$(native_unit)
  configure_startup_dropin "$unit" 5

  systemctl --user disable --now sunshine.service 2>/dev/null || true
  systemctl --user daemon-reload
  systemctl --user enable "$unit" 2>/dev/null || true
  if systemctl --user restart "$unit" 2>/dev/null; then
    echo "  ${green}Service restarted.${normal}"
  else
    echo "  ${yellow}Configured but failed to restart. Check: journalctl --user -u $unit -n 50${normal}"
  fi
}

repair_flatpak_startup() {
  if ! flatpak_installed; then
    echo "${red}Sunshine Flatpak is not installed.${normal}" >&2
    return 1
  fi

  configure_startup_dropin "$FLATPAK_UNIT" 0

  systemctl --user disable --now sunshine.service 2>/dev/null || true
  systemctl --user daemon-reload
  systemctl --user enable "$FLATPAK_UNIT" 2>/dev/null || true
  if systemctl --user restart "$FLATPAK_UNIT" 2>/dev/null; then
    echo "  ${green}Flatpak service restarted.${normal}"
  else
    echo "  ${yellow}Configured but failed to restart. Check: journalctl --user -u $FLATPAK_UNIT -n 50${normal}"
  fi
}

repair_startup() {
  local scope="${1:-}"
  case $scope in
    --native)  repair_native_startup;  return ;;
    --flatpak) repair_flatpak_startup; return ;;
  esac
  if native_installed && flatpak_installed; then
    pick_mode || return 1
    if [[ $MODE == flatpak ]]; then repair_flatpak_startup; else repair_native_startup; fi
  elif native_installed; then
    repair_native_startup
  elif flatpak_installed; then
    repair_flatpak_startup
  else
    echo "${red}Sunshine is not installed.${normal}" >&2
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
    start)   systemctl --user start   "$unit" && echo "  ${green}Started${normal} $unit"   || { echo "  ${red}Failed to start $unit${normal}" >&2;   return 1; } ;;
    stop)    systemctl --user stop    "$unit" && echo "  ${green}Stopped${normal} $unit"   || { echo "  ${red}Failed to stop $unit${normal}" >&2;    return 1; } ;;
    restart) systemctl --user restart "$unit" && echo "  ${green}Restarted${normal} $unit" || { echo "  ${red}Failed to restart $unit${normal}" >&2; return 1; } ;;
    enable)  systemctl --user enable  "$unit" && echo "  ${green}Enabled${normal} $unit (auto-start at login)" || { echo "  ${red}Failed to enable${normal}" >&2; return 1; } ;;
    disable) systemctl --user disable "$unit" && echo "  ${green}Disabled${normal} $unit" || { echo "  ${red}Failed to disable${normal}" >&2; return 1; } ;;
    status)  systemctl --user status "$unit" --no-pager || true ;;
    logs)    journalctl --user -u "$unit" -n 50 --no-pager || true ;;
    follow)  journalctl --user -u "$unit" -n 50 -f ;;
  esac
}

manage_service() {
  pick_mode || return 1
  local unit
  if [[ $MODE == flatpak ]]; then unit=$FLATPAK_UNIT; else unit=$(native_unit); fi

  local back_num=9
  [[ $MODE == native ]] && back_num=10

  while true; do
    echo
    echo "  ${bold}Sunshine service${normal}  ${dim}($MODE)${normal}"
    print_service_status "$unit" || true
    echo
    printf "  ${cyan}1${normal})  Start\n"
    printf "  ${cyan}2${normal})  Stop\n"
    printf "  ${cyan}3${normal})  Restart\n"
    printf "  ${cyan}4${normal})  Enable  (auto-start at login)\n"
    printf "  ${cyan}5${normal})  Disable (no auto-start)\n"
    printf "  ${cyan}6${normal})  Show status  (systemctl --user status)\n"
    printf "  ${cyan}7${normal})  Show logs    (last 50 lines)\n"
    printf "  ${cyan}8${normal})  Follow logs  (live, Ctrl+C to stop)\n"
    if [[ $MODE == native ]]; then
      printf "  ${cyan}9${normal})  Repair native startup (setcap + drop-in)\n"
    fi
    printf "  ${cyan}%d${normal})  Back\n" "$back_num"
    echo
    printf "  ${bold}Select [1-%d]:${normal} " "$back_num"

    local choice
    if ! read -r choice; then echo; return 0; fi
    [[ -z $choice ]] && continue
    if [[ ! $choice =~ ^[0-9]+$ ]]; then
      printf "  ${red}Invalid option '%s'.${normal}\n" "$choice"; sleep 1; continue
    fi
    if (( choice == back_num )); then return 0; fi
    case "$choice" in
      1) systemctl --user start   "$unit" && echo "  ${green}Started${normal}"   || echo "  ${red}Failed to start${normal}" ;;
      2) systemctl --user stop    "$unit" && echo "  ${green}Stopped${normal}"   || echo "  ${red}Failed to stop${normal}" ;;
      3) systemctl --user restart "$unit" && echo "  ${green}Restarted${normal}" || echo "  ${red}Failed to restart${normal}" ;;
      4) systemctl --user enable  "$unit" && echo "  ${green}Enabled${normal}"   || echo "  ${red}Failed to enable${normal}" ;;
      5) systemctl --user disable "$unit" && echo "  ${green}Disabled${normal}"  || echo "  ${red}Failed to disable${normal}" ;;
      6) systemctl --user status "$unit" --no-pager || true ;;
      7) journalctl --user -u "$unit" -n 50 --no-pager || true ;;
      8) journalctl --user -u "$unit" -n 50 -f ;;
      9) if [[ $MODE == native ]]; then repair_native_startup; fi ;;
      *) printf "  ${red}Invalid option '%s'.${normal}\n" "$choice"; sleep 1 ;;
    esac
  done
}
