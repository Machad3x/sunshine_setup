# shellcheck shell=bash
# Shared globals are initialized by sunshine-setup.sh before this module is sourced.
# shellcheck disable=SC2034,SC2154
detect_distro() {
  local id=${1:-} like=${2:-} family
  local -a like_ids

  id=${id,,}
  like=${like,,}
  DISTRO=""
  case $id in
    cachyos|fedora|arch|ubuntu|debian|opensuse-microos)
      DISTRO=$id
      return 0
      ;;
  esac

  read -r -a like_ids <<< "$like"
  for family in "${like_ids[@]}"; do
    case $family in
      cachyos|fedora|arch|ubuntu|debian)
        DISTRO=$family
        return 0
        ;;
    esac
  done
  return 1
}

pick_mode() {
  local n=0 f=0
  native_installed  && n=1
  flatpak_installed && f=1

  if (( ${UNSUPPORTED_DISTRO:-0} )); then
    # Native installation is blocked on unsupported distributions, so prefer
    # the Flatpak build when it is available.
    if (( f )); then
      MODE=flatpak
      echo "  Unsupported distribution detected. Using Sunshine: ${bold}flatpak${normal}"
    elif (( n )); then
      MODE=native
    else
      echo "${red}Sunshine is not installed.${normal} Install the Flatpak build first (menu option 1, or 'install --flatpak-system' / 'install --flatpak-user')." >&2
      return 1
    fi
  elif (( IMMUTABLE )); then
    if (( f )); then
      MODE=flatpak
      echo "  Immutable system detected. Using Sunshine: ${bold}flatpak${normal}"
    else
      echo "${red}Sunshine Flatpak is not installed.${normal} Install it first (menu option 1, or 'install --flatpak-system' / 'install --flatpak-user')." >&2
      return 1
    fi
  elif (( n && f )); then
    echo
    echo "  ${bold}Both native and Flatpak Sunshine are installed. Which one?${normal}"
    choose "Mode" "Native" "Flatpak" || return 1
    case "$REPLY" in 1) MODE=native ;; 2) MODE=flatpak ;; esac
  elif (( n )); then MODE=native
  elif (( f )); then MODE=flatpak
  else
    echo "${red}Sunshine is not installed.${normal} Install it first (menu option 1, or the 'install' command)." >&2
    return 1
  fi

  if [[ $MODE == flatpak ]]; then
    APP_CONF="$HOME/.var/app/$FLATPAK_ID/config/sunshine/apps.json"
    UNIT="$FLATPAK_UNIT"
  else
    APP_CONF="$HOME/.config/sunshine/apps.json"
    UNIT="$(native_unit)"
  fi
}

# Paths of every Sunshine apps.json the script may touch (native + Flatpak).
apps_conf_paths() {
  printf '%s\n' "$HOME/.config/sunshine/apps.json" \
    "$HOME/.var/app/$FLATPAK_ID/config/sunshine/apps.json"
}

# Writes (or replaces) a virtual-monitor app entry in an apps.json file.
# Arguments: conf name do_cmd undo_cmd
vmon_write_app() {
  local conf=$1 name=$2 do_cmd=$3 undo_cmd=$4 tmp
  mkdir -p "$(dirname "$conf")"
  [[ -f $conf ]] || printf '{"env":{},"apps":[]}\n' > "$conf"
  tmp=$(mktemp "${conf}.sunshine-vmon.XXXXXX") || return 1
  TEMP_FILES+=("$tmp")
  if ! jq --arg name "$name" --arg cmd_do "$do_cmd" --arg cmd_undo "$undo_cmd" '
    {
      "name": $name, "cmd": "", "output": "", "image-path": "",
      "auto-detach": true, "elevated": false, "exclude-global-prep-cmd": false,
      "exit-timeout": 5, "wait-all": true,
      "prep-cmd": [{"do": $cmd_do, "undo": $cmd_undo}]
    } as $app
    | .apps = ((.apps // []) | map(select(.name != $app.name)) + [$app])
  ' "$conf" > "$tmp"; then
    rm -f -- "$tmp"
    echo "${red}Could not update $conf (invalid JSON?).${normal}" >&2
    return 1
  fi
  if ! chmod --reference="$conf" "$tmp" || ! mv -f -- "$tmp" "$conf"; then
    rm -f -- "$tmp"
    echo "${red}Could not replace $conf.${normal}" >&2
    return 1
  fi
}

# Removes a virtual-monitor app entry from an apps.json file. Prints nothing
# when the entry is absent, and keeps the file mode. Returns non-zero only
# when the file could not be inspected or updated.
vmon_remove_app() {
  local conf=$1 name=$2 tmp
  [[ -f $conf ]] || return 0
  if ! jq -e --arg name "$name" '(.apps // []) | type == "array"' "$conf" >/dev/null 2>&1; then
    echo "${red}Could not update $conf (invalid JSON or apps list).${normal}" >&2
    return 1
  fi
  if ! jq -e --arg name "$name" 'any((.apps // [])[]; .name == $name)' "$conf" >/dev/null; then
    return 0
  fi
  tmp=$(mktemp "${conf}.sunshine-vmon.XXXXXX") || return 1
  TEMP_FILES+=("$tmp")
  if ! jq --arg name "$name" '.apps = ((.apps // []) | map(select(.name != $name)))' "$conf" > "$tmp"; then
    rm -f -- "$tmp"
    echo "${red}Could not update $conf (invalid JSON?).${normal}" >&2
    return 1
  fi
  if ! chmod --reference="$conf" "$tmp" || ! mv -f -- "$tmp" "$conf"; then
    rm -f -- "$tmp"
    echo "${red}Could not replace $conf.${normal}" >&2
    return 1
  fi
  echo "  Entry removed from $conf"
}

# Ubuntu release (XX.YY) for .deb selection: VERSION_ID when usable, then the
# UBUNTU_CODENAME map for derivatives; empty when unknown.
ubuntu_version() {
  if [[ ${ID:-} == ubuntu && ${VERSION_ID:-} =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
    echo "${VERSION_ID}"
    return
  fi
  case "${UBUNTU_CODENAME:-}" in
    jammy)     echo 22.04 ;;
    noble)     echo 24.04 ;;
    oracular)  echo 24.10 ;;
    plucky)    echo 25.04 ;;
    questing)  echo 25.10 ;;
    resolute)  echo 26.04 ;;
    stonking)  echo 26.10 ;;
    *)         echo "" ;;
  esac
}

# Install probes spawn processes and menus re-run them often, so results are
# cached for the run. Every installer must call invalidate_install_cache()
# when it changes the set of Sunshine installations.
invalidate_install_cache() { _NATIVE_INSTALLED=""; _FLATPAK_INSTALLED=""; }

native_installed() {
  if [[ -z ${_NATIVE_INSTALLED:-} ]]; then
    _NATIVE_INSTALLED=1
    command -v sunshine >/dev/null 2>&1 && _NATIVE_INSTALLED=0
  fi
  return "$_NATIVE_INSTALLED"
}

flatpak_installed() {
  if [[ -z ${_FLATPAK_INSTALLED:-} ]]; then
    _FLATPAK_INSTALLED=1
    if command -v flatpak >/dev/null 2>&1 \
        && { flatpak info --user "$FLATPAK_ID" >/dev/null 2>&1 \
          || flatpak info --system "$FLATPAK_ID" >/dev/null 2>&1; }; then
      _FLATPAK_INSTALLED=0
    fi
  fi
  return "$_FLATPAK_INSTALLED"
}

# Interactive selectors used by every module (colors are provided by the
# sourcing script). choose() sets REPLY to the selected 1-based number.
choose() {
  local prompt=$1; shift
  local -a opts=("$@")
  local n=${#opts[@]}
  local i choice
  echo
  for i in "${!opts[@]}"; do
    printf "  ${cyan}%d${normal})  %s\n" "$((i+1))" "${opts[$i]}"
  done
  echo
  while true; do
    printf "  ${bold}%s [1-%d]:${normal} " "$prompt" "$n"
    if ! read -r choice; then echo; return 1; fi
    if [[ $choice =~ ^[0-9]+$ ]] && (( 10#$choice >= 1 && 10#$choice <= n )); then
      REPLY=$((10#$choice))
      return 0
    fi
    printf "  ${red}Choose a number from 1 to %d.${normal}\n" "$n"
  done
}

ask_yes_no() {
  local reply=""
  printf "  ${bold}%s${normal} (y/N) " "$1"
  read -r reply || return 1
  [[ "${reply,,}" =~ ^y ]]
}
