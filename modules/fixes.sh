# shellcheck shell=bash
# Shared globals are initialized by sunshine-setup.sh before this module is sourced.
# shellcheck disable=SC2154
# ---------- Error 503 ----------
fix_503() {
  if [[ "${XDG_SESSION_TYPE:-}" != wayland ]] || [[ "${XDG_CURRENT_DESKTOP:-}" != *KDE* ]]; then
    echo "  ${yellow}Warning:${normal} this fix assumes KDE Plasma on Wayland (current session: ${XDG_SESSION_TYPE:-?}, desktop: ${XDG_CURRENT_DESKTOP:-?})."
    ask_yes_no "Continue anyway?" || { echo "  Aborted."; return 0; }
  fi
  mkdir -p "$HOME/.config/environment.d"
  local conf="$HOME/.config/environment.d/98-sunshine-setup-503.conf"
  local legacy_conf="$HOME/.config/environment.d/98-kwin-no-permission-checks.conf"
  local status
  if [[ -f $legacy_conf ]]; then
    if contains_503_setting "$legacy_conf"; then
      echo "  Error 503 fix is already present in $legacy_conf."
      echo "  Use '503-reset' to remove this setting."
      return 0
    else
      status=$?
      (( status == 1 )) || return 1
    fi
  fi
  if [[ -e $conf ]]; then
    if contains_503_setting "$conf"; then
      echo "  Error 503 fix is already present in $conf."
    else
      status=$?
      if (( status != 1 )); then return 1; fi
      echo "${red}Refusing to overwrite existing file:${normal} $conf" >&2
      return 1
    fi
  else
    printf 'KWIN_WAYLAND_NO_PERMISSION_CHECKS=1\n' > "$conf"
    echo "  Written to $conf:"
  fi
  sed 's/^/    /' "$conf"
  echo "  ${yellow}Log out and back in (or reboot)${normal} for the variable to take effect in KWin."
}

contains_503_setting() {
  local conf=$1 status
  if grep -Fxq 'KWIN_WAYLAND_NO_PERMISSION_CHECKS=1' "$conf"; then
    return 0
  else
    status=$?
  fi
  if (( status == 1 )); then return 1; fi
  echo "${red}Could not read $conf.${normal}" >&2
  return 2
}

remove_503_setting_from_file() {
  local conf=$1 tmp status
  [[ -f $conf ]] || return 0
  if contains_503_setting "$conf"; then
    :
  else
    status=$?
    if (( status == 1 )); then return 0; fi
    return 1
  fi

  tmp=$(mktemp)
  TEMP_FILES+=("$tmp")
  if grep -Fvx 'KWIN_WAYLAND_NO_PERMISSION_CHECKS=1' "$conf" > "$tmp"; then
    :
  else
    status=$?
    if (( status != 1 )); then
      rm -f -- "$tmp"
      echo "${red}Could not read $conf.${normal}" >&2
      return 1
    fi
  fi
  if [[ -s $tmp ]]; then
    chmod --reference="$conf" "$tmp"
    mv "$tmp" "$conf"
  else
    rm -f -- "$tmp" "$conf"
  fi
}

reset_503() {
  local conf="$HOME/.config/environment.d/98-sunshine-setup-503.conf"
  local legacy_conf="$HOME/.config/environment.d/98-kwin-no-permission-checks.conf"
  local found=0
  local status
  if [[ -f $conf ]]; then
    if contains_503_setting "$conf"; then
      remove_503_setting_from_file "$conf" || return 1
      found=1
      echo "  Removed the Error 503 setting from $conf."
    else
      status=$?
      (( status == 1 )) || return 1
    fi
  fi
  if [[ -f $legacy_conf ]]; then
    if contains_503_setting "$legacy_conf"; then
      remove_503_setting_from_file "$legacy_conf" || return 1
      found=1
      echo "  Removed the Error 503 setting from $legacy_conf."
    else
      status=$?
      (( status == 1 )) || return 1
    fi
  fi
  if (( ! found )); then
    echo "  No Sunshine Error 503 setting to revert."
    return 0
  fi
  echo "  Error 503 fix reverted. Log out and back in (or reboot) for the change to take effect."
}
