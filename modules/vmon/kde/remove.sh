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
  for m in native flatpak; do
    local conf unit
    if [[ $m == flatpak ]]; then
      conf="$HOME/.var/app/$FLATPAK_ID/config/sunshine/apps.json"; unit="$FLATPAK_UNIT"
    else
      conf="$HOME/.config/sunshine/apps.json"; unit="$(native_unit)"
    fi
    if [[ -f $conf ]]; then
      local TMP; TMP=$(mktemp "${conf}.sunshine-vmon.XXXXXX") || return 1
      TEMP_FILES+=("$TMP")
      if jq '.apps = ((.apps // []) | map(select(.name != "Virtual Monitor")))' "$conf" > "$TMP"; then
        if ! chmod --reference="$conf" "$TMP" || ! mv -f -- "$TMP" "$conf"; then
          rm -f -- "$TMP"
          echo "${red}Could not replace $conf. Leaving virtual-monitor files in place.${normal}" >&2
          return 1
        fi
        echo "  Entry removed from $conf"
      else
        rm -f "$TMP"
        echo "${red}Could not update $conf (invalid JSON?). Leaving virtual-monitor files in place.${normal}" >&2
        return 1
      fi
    fi
    rm -f "$HOME/.config/systemd/user/${unit}.d/vmon.conf"
  done
  systemctl --user daemon-reload
  sudo rm -f -- "$BIN_DIR/sunshine-vmon-common.sh" "$BIN_DIR/sunshine-start-vmon" "$BIN_DIR/sunshine-stop-vmon"
  echo "  Virtual monitor removed. (The Error 503 fix was left untouched.)"
}
