# shellcheck shell=bash
# Shared globals are initialized by sunshine-setup.sh before this module is sourced.
# shellcheck disable=SC2154
# ---------- remove virtual monitor ----------
remove_vmon_kde() {
  if [[ -x "$BIN_DIR/sunshine-stop-vmon" ]]; then
    if ! "$BIN_DIR/sunshine-stop-vmon"; then
      echo "${red}Could not safely restore the virtual-monitor state; leaving its configuration in place.${normal}" >&2
      return 1
    fi
  fi
  local m conf unit
  for m in native flatpak; do
    if [[ $m == flatpak ]]; then
      conf="$HOME/.var/app/$FLATPAK_ID/config/sunshine/apps.json"; unit="$FLATPAK_UNIT"
    else
      conf="$HOME/.config/sunshine/apps.json"; unit="$(native_unit)"
    fi
    vmon_remove_app "$conf" "Virtual Monitor" || return 1
    rm -f "$HOME/.config/systemd/user/${unit}.d/vmon.conf"
  done
  systemctl --user daemon-reload
  rm -f -- "$BIN_DIR/sunshine-vmon-common.sh" "$BIN_DIR/sunshine-start-vmon" "$BIN_DIR/sunshine-stop-vmon"
  echo "  Virtual monitor removed. (The Error 503 fix was left untouched.)"
}
