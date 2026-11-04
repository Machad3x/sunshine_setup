# shellcheck shell=bash
# Shared globals are initialized by sunshine-setup.sh before this module is sourced.
# shellcheck disable=SC2154
# ---------- install ----------
# Downloads the official .deb from the latest GitHub release.
# URL pattern: sunshine_{version}-1+{os}{rel}_{arch}.deb
#   - Debian 13:  sunshine_{v}-1+debiantrixie_amd64.deb
#   - Ubuntu:     sunshine_{v}-1+ubuntu24.04_amd64.deb
# `first` is the caller's preferred release (used only for a friendly warning).
# Remaining arguments are fallback releases, tried in order.
install_deb() {
  if (( IMMUTABLE )); then
    echo "${red}Native .deb installation is not supported on immutable systems.${normal}" >&2
    echo "Use the Flatpak option instead." >&2
    return 1
  fi
  local os=$1 first=$2 rel used="" seen=" " url tmp arch version release_json
  local base=https://github.com/LizardByte/Sunshine/releases/latest/download
  arch=$(dpkg --print-architecture)
  command -v curl >/dev/null || pkg_install curl || return 1
  tmp=$(mktemp --suffix=.deb) || return 1
  TEMP_FILES+=("$tmp")
  shift

  # Fetch the release once so network and parsing failures can be reported clearly.
  if ! release_json=$(curl -fsSL https://api.github.com/repos/LizardByte/Sunshine/releases/latest); then
    echo "${red}Could not query the latest Sunshine release.${normal}" >&2
    echo "Check your connection and try again, or use the Flatpak option." >&2
    return 1
  fi

  if command -v jq >/dev/null 2>&1; then
    if ! version=$(printf '%s' "$release_json" | jq -er '.tag_name // empty' | sed 's/^v//'); then
      version=""
    fi
  else
    version=$(printf '%s' "$release_json" \
      | grep -oP '"tag_name"\s*:\s*"\K[^"]+' | sed 's/^v//' || true)
  fi

  if [[ -z $version ]]; then
    rm -f "$tmp"
    echo "${red}Could not determine the latest Sunshine version.${normal}" >&2
    echo "Check your connection and try again, or use the Flatpak option." >&2
    return 1
  fi

  echo "  ${dim}Latest Sunshine version:${normal} $version"

  for rel in "$@"; do
    if [[ -z $rel || $seen == *" $rel "* ]]; then continue; fi
    seen+="$rel "
    url="$base/sunshine_${version}-1+${os}${rel}_${arch}.deb"
    echo "  Trying $url"
    if curl -fsSL "$url" -o "$tmp"; then used=$rel; break; fi
  done

  if [[ -z $used ]]; then
    rm -f "$tmp"
    echo "${red}No matching .deb found for version $version.${normal}" >&2
    echo "  Check https://github.com/LizardByte/Sunshine/releases or use the Flatpak option." >&2
    return 1
  fi

  if [[ -z $first ]]; then
    echo "  ${yellow}Could not determine your release; using the '$used' build.${normal} If dependencies fail, use the Flatpak option."
  elif [[ $used != "$first" ]]; then
    echo "  ${yellow}No .deb for your release; using the '$used' build.${normal} If dependencies fail, use the Flatpak option."
  fi

  if ! dpkg-deb --info "$tmp" >/dev/null 2>&1; then
    rm -f "$tmp"
    echo "${red}The downloaded file is not a valid .deb package.${normal}" >&2
    echo "  Download it manually from https://github.com/LizardByte/Sunshine/releases or use the Flatpak option." >&2
    return 1
  fi

  apt_update_once
  sudo apt-get install -y "$tmp" || {
    echo "${red}apt could not install the package (dependency mismatch?).${normal} Use the Flatpak option instead." >&2
    return 1
  }
}

install_flatpak() {
  local scope="${1:-system}"
  case $scope in
    system|user) ;;
    *)
      echo "${red}Invalid Flatpak installation scope: $scope${normal}" >&2
      return 2
      ;;
  esac
  echo "  Installing Sunshine (${bold}Flatpak — $scope${normal})..."

  if (( UNSUPPORTED_DISTRO )); then
    if ! command -v flatpak >/dev/null 2>&1; then
      echo "${red}Flatpak is not installed on unsupported distro '${ID:-unknown}'.${normal}" >&2
      echo "Install Flatpak manually with your distro's package manager, then retry." >&2
      return 1
    fi
  elif (( IMMUTABLE )); then
    if ! command -v flatpak >/dev/null 2>&1; then
      echo "${red}Flatpak is not installed.${normal} Install it with the system's supported method and retry:" >&2
      if [[ $DISTRO == opensuse-microos ]] || command -v transactional-update >/dev/null 2>&1; then
        echo "  sudo transactional-update pkg install flatpak   # requires reboot" >&2
      elif command -v rpm-ostree >/dev/null 2>&1; then
        echo "  sudo rpm-ostree install flatpak                 # requires reboot" >&2
      else
        echo "  Use your distro's package manager (Flatpak is usually pre-installed on immutable systems)." >&2
      fi
      return 1
    fi
  else
    command -v flatpak >/dev/null || pkg_install flatpak || return 1
  fi

  flatpak remote-add --if-not-exists --"$scope" flathub https://dl.flathub.org/repo/flathub.flatpakrepo || return 1
  flatpak install --"$scope" -y --or-update flathub "$FLATPAK_ID" || return 1
  flatpak run --"$scope" --command=additional-install.sh "$FLATPAK_ID" \
    || echo "  ${yellow}Warning:${normal} additional-install.sh returned non-zero (udev/input rules may need manual setup)."

  repair_flatpak_startup

  local conf="$HOME/.var/app/$FLATPAK_ID/config/sunshine/sunshine.conf"
  local found=0
  for _ in $(seq 1 30); do
    [[ -f "$conf" ]] && { found=1; break; }
    sleep 1
  done
  if (( ! found )); then
    echo "  ${yellow}Warning:${normal} Sunshine did not create its config (service may not have started — no graphical session?)."
    mkdir -p "$(dirname "$conf")"
    touch "$conf"
  fi

  echo
  echo "  ${bold}Flatpak installed ($scope).${normal} Web UI: https://localhost:47990"
  echo
  print_service_status "$FLATPAK_UNIT" || true
}

install_native() {
  if (( UNSUPPORTED_DISTRO )); then
    echo "${red}Native Sunshine installation is not supported on distro '${ID:-unknown}'.${normal}" >&2
    echo "Choose one of the Flatpak installation scopes instead." >&2
    return 1
  fi
  if (( IMMUTABLE )); then
    echo "${red}Native installation is not supported on immutable systems.${normal}" >&2
    echo "Use Flatpak instead." >&2
    return 1
  fi

  # Debian: only 13 (trixie) supports native .deb.
  if [[ $DISTRO == debian ]] && ! debian_native_ok; then
    local dver="${VERSION_ID:-unknown}"
    echo
    echo "  ${red}Native Sunshine is not available on Debian ${dver}.${normal}"
    echo
    echo "  The official .deb is built against Debian 13 (trixie)'s library ABI"
    echo "  (libminiupnpc18, libicu76). Debian 14+ (forky) ships newer,"
    echo "  incompatible versions, and Debian 12 and older are out of scope."
    echo
    echo "  ${bold}Use the Flatpak installation instead:${normal}"
    echo "    bash $0 install --flatpak-system   # system-wide"
    echo "    bash $0 install --flatpak-user     # per-user"
    return 1
  fi

  echo "  Installing Sunshine (${bold}native${normal})..."
  case $DISTRO in
    fedora)
      sudo dnf copr enable -y lizardbyte/stable
      sudo dnf install -y sunshine
      ;;
    cachyos)
      if ! sudo pacman -S --needed --noconfirm sunshine; then
        echo "${red}Could not install 'sunshine' via pacman on CachyOS.${normal}" >&2
        echo "  Check: ${bold}pacman -Ss sunshine${normal}" >&2
        echo "  Alternatives: Flatpak or AUR (yay -S sunshine-bin)." >&2
        return 1
      fi
      ;;
    arch)
      local helper=""
      for h in yay paru; do command -v "$h" >/dev/null && { helper=$h; break; }; done
      if [[ -z $helper ]]; then
        echo "${red}No AUR helper (yay/paru) found.${normal}" >&2
        echo "  Install yay or paru, or choose the Flatpak option." >&2
        return 1
      fi
      if ! "$helper" -S --needed --noconfirm sunshine-bin; then
        echo "${red}Failed to install sunshine-bin via $helper.${normal}" >&2
        echo "  Try another AUR helper or choose the Flatpak option." >&2
        return 1
      fi
      ;;
    ubuntu)
      # Same URL scheme as Debian 13, with numeric Ubuntu releases as fallbacks.
      install_deb ubuntu "$(ubuntu_version)" 26.10 26.04 24.04 22.04
      ;;
    debian)
      # Debian 13 only: upstream .deb is built against trixie's ABI.
      install_deb debian "$DEBIAN_NATIVE_SUPPORTED_CODENAME" "$DEBIAN_NATIVE_SUPPORTED_CODENAME"
      ;;
  esac

  flatpak_installed && systemctl --user disable --now "$FLATPAK_UNIT" 2>/dev/null || true

  repair_native_startup

  echo
  echo "  ${bold}Native Sunshine installed.${normal} Web UI: https://localhost:47990"
  echo
  print_service_status "$(native_unit)" || true
}

warn_unsupported_distro() {
  echo
  echo "  ${yellow}Warning: ${PRETTY_NAME:-${ID:-Unknown distro}} is not a supported distribution.${normal}"
  echo "  Native installation is unavailable. Flatpak may work, but failures are possible."
  if ! command -v flatpak >/dev/null 2>&1; then
    echo "  Flatpak is not installed; install it manually with your distro's package manager before continuing."
  fi
  print_desktop_options
  echo
}

action_install() {
  case "${1:-}" in
    --flatpak-system) install_flatpak system; return ;;
    --flatpak-user)   install_flatpak user;   return ;;
    --flatpak)        install_flatpak system; return ;;
    --native)         install_native;         return ;;
  esac

  if (( UNSUPPORTED_DISTRO )); then
    warn_unsupported_distro
    choose "Flatpak scope" "System (--system)" "User (--user)" "Back" || return 0
    case "$REPLY" in
      1) install_flatpak system ;;
      2) install_flatpak user   ;;
      3) return 0               ;;
    esac
    return
  fi

  if (( IMMUTABLE )); then
    echo
    echo "  ${bold}Immutable system detected.${normal} Flatpak is recommended."
    choose "Flatpak scope" "System (--system)" "User (--user)" "Back" || return 0
    case "$REPLY" in
      1) install_flatpak system ;;
      2) install_flatpak user   ;;
      3) return 0               ;;
    esac
    return
  fi

  # Debian other than 13 → Flatpak only.
  if [[ $DISTRO == debian ]] && ! debian_native_ok; then
    echo
    echo "  ${yellow}Native Sunshine is not available on Debian ${VERSION_ID:-unknown}.${normal}"
    echo "  Only Flatpak is supported on this Debian version."
    echo "  ${dim}(See https://github.com/LizardByte/Sunshine for the upstream build matrix.)${normal}"
    echo
    choose "Method" "Flatpak (System scope)" "Flatpak (User scope)" "Back" || return 1
    case "$REPLY" in
      1) install_flatpak system ;;
      2) install_flatpak user   ;;
      3) return 0               ;;
    esac
    return
  fi

  local source_name
  case $DISTRO in
    fedora)        source_name=COPR ;;
    arch)          source_name="AUR (yay/paru)" ;;
    cachyos)       source_name="pacman (CachyOS)" ;;
    ubuntu)        source_name=".deb" ;;
    debian)        source_name=".deb (Debian 13 trixie)" ;;
  esac

  echo
  echo "  ${bold}How do you want to install Sunshine?${normal}"
  choose "Method" "Flatpak (System scope)" "Flatpak (User scope)" "Native ($source_name)" "Back" || return 1
  case "$REPLY" in
    1) install_flatpak system ;;
    2) install_flatpak user   ;;
    3) install_native         ;;
    4) return 0               ;;
  esac
}
