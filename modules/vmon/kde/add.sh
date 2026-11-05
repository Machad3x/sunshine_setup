# shellcheck shell=bash
# Shared globals are initialized by sunshine-setup.sh before this module is sourced.
# shellcheck disable=SC2154
# ---------- virtual monitor ----------
vmon_kde_require_tools() {
  local cmd pkg missing=0
  for cmd in krfb-virtualmonitor kscreen-doctor jq; do
    command -v "$cmd" >/dev/null 2>&1 && continue
    missing=1
    case $cmd in
      krfb-virtualmonitor)
        echo "${red}krfb-virtualmonitor not found.${normal} It is provided by the 'krfb' package." >&2
        pkg=krfb
        ;;
      kscreen-doctor)
        echo "${red}kscreen-doctor not found.${normal} It ships with KDE's kscreen/libkscreen package; is Plasma installed?" >&2
        pkg=libkscreen
        ;;
      jq)
        echo "${red}jq not found.${normal} Install 'jq' with your package manager." >&2
        pkg=jq
        ;;
    esac
    if (( IMMUTABLE )); then
      if [[ $DISTRO == opensuse-microos ]]; then
        echo "  Install via 'transactional-update pkg install $pkg' (requires reboot)." >&2
      else
        echo "  Install via 'rpm-ostree install $pkg' (requires reboot)." >&2
      fi
    fi
  done
  (( missing == 0 ))
}

setup_vmon_kde() {
  if [[ "${XDG_CURRENT_DESKTOP:-}" != *KDE* ]]; then
    echo "  ${yellow}Warning:${normal} the virtual monitor only works on KDE Plasma (KWin, Wayland)."
    echo "  Current desktop: ${XDG_CURRENT_DESKTOP:-unknown}."
  fi
  if [[ ${XDG_SESSION_TYPE:-} != wayland ]]; then
    echo "${red}The KDE virtual monitor requires a Wayland session.${normal}" >&2
    echo "  Current session type: ${XDG_SESSION_TYPE:-unknown}. Log in to Plasma (Wayland) and retry." >&2
    return 1
  fi
  pick_mode || return 1

  if (( IMMUTABLE )); then
    vmon_kde_require_tools || return 1
  elif (( UNSUPPORTED_DISTRO )); then
    # Unsupported distributions use the Flatpak Sunshine build; the host tools
    # must be installed manually, but they are enough to set the monitor up.
    if ! vmon_kde_require_tools; then
      echo "  Install these tools manually with your distro's package manager; Sunshine itself can stay on Flatpak." >&2
      return 1
    fi
  else
    case $DISTRO in
      fedora)        pkg_install krfb jq libkscreen || return 1 ;;
      arch|cachyos)  pkg_install krfb jq libkscreen || return 1 ;;
      ubuntu|debian) pkg_install krfb jq libkscreen-bin || return 1 ;;
      *)
        echo "  ${yellow}No automatic package mapping is available for '$DISTRO'.${normal}" >&2
        echo "  Install 'krfb', 'libkscreen' and 'jq' manually, then re-run." >&2
        vmon_kde_require_tools || return 1
        ;;
    esac
    vmon_kde_require_tools || return 1
  fi

  # The hook scripts live in this repository as real files (so CI can lint
  # them) and are installed next to sunshine-vmon-common.sh, which they
  # source from their own directory at runtime.
  mkdir -p "$BIN_DIR" || return 1
  if ! install -m 644 "$SCRIPT_DIR/modules/vmon/kde/runtime.sh" "$BIN_DIR/sunshine-vmon-common.sh" \
      || ! install -m 755 "$SCRIPT_DIR/modules/vmon/kde/start.sh" "$BIN_DIR/sunshine-start-vmon" \
      || ! install -m 755 "$SCRIPT_DIR/modules/vmon/kde/stop.sh" "$BIN_DIR/sunshine-stop-vmon"; then
    echo "${red}Could not install the virtual-monitor hooks to $BIN_DIR.${normal}" >&2
    return 1
  fi
  command -v restorecon >/dev/null && restorecon "$BIN_DIR/sunshine-vmon-common.sh" "$BIN_DIR/sunshine-start-vmon" "$BIN_DIR/sunshine-stop-vmon" || true

  local DO UNDO start_script_q stop_script_q
  printf -v start_script_q '%q' "$BIN_DIR/sunshine-start-vmon"
  printf -v stop_script_q '%q' "$BIN_DIR/sunshine-stop-vmon"
  if [[ $MODE == flatpak ]]; then
    # Forward only the client geometry. The hook resolves WAYLAND_DISPLAY,
    # XDG_RUNTIME_DIR and DBUS_SESSION_BUS_ADDRESS at runtime so a reboot or a
    # session restart does not leave stale values in apps.json.
    DO="flatpak-spawn --host --env=SUNSHINE_VMON_MODE=flatpak --env=SUNSHINE_CLIENT_WIDTH --env=SUNSHINE_CLIENT_HEIGHT --env=SUNSHINE_CLIENT_FPS $start_script_q"
    UNDO="flatpak-spawn --host $stop_script_q"
  else
    DO="env SUNSHINE_VMON_MODE=native $start_script_q"
    UNDO="$stop_script_q"
  fi

  vmon_write_app "$APP_CONF" "Virtual Monitor" "$DO" "$UNDO" || return 1
  echo "  'Virtual Monitor' app written to $APP_CONF"

  local DROPIN="$HOME/.config/systemd/user/${UNIT}.d"
  mkdir -p "$DROPIN"
  # Quotes keep the drop-in valid when $HOME contains spaces.
  printf '[Service]\nExecStopPost="%s/sunshine-stop-vmon"\n' "$BIN_DIR" > "$DROPIN/vmon.conf"
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
