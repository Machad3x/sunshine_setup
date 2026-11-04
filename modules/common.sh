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
      echo "${red}Sunshine is not installed.${normal} Use option 1 to install the Flatpak build." >&2
      return 1
    fi
  elif (( IMMUTABLE )); then
    if (( f )); then
      MODE=flatpak
      echo "  Immutable system detected. Using Sunshine: ${bold}flatpak${normal}"
    else
      echo "${red}Sunshine Flatpak is not installed.${normal} Use option 1 first." >&2
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
    echo "${red}Sunshine is not installed.${normal} Use option 1 first." >&2
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
