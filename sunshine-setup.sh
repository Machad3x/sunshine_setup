#!/usr/bin/env bash
# Sunshine setup for Fedora, Arch, CachyOS, Ubuntu and Debian
# (KDE Plasma, Wayland for the virtual monitor).
# Ported from the Bazzite "setup-sunshine" ujust recipe and its virtual monitor scripts.
#
# Distro notes:
#   - Fedora:    native via COPR lizardbyte/stable
#   - Arch:      native via AUR (sunshine-bin) using yay or paru
#   - CachyOS:   native via pacman (repo package 'sunshine')
#   - Ubuntu:    native via upstream .deb (best-effort, falls back to Flatpak)
#   - Debian 13 (trixie):  native via upstream .deb
#   - Debian 12 or 14+:    Flatpak only (native .deb deps are incompatible)
#   - Immutable systems:   Flatpak only.
#
# Interactive:  bash sunshine-setup.sh
# Direct:       see `bash sunshine-setup.sh --help`
set -euo pipefail

SCRIPT_VERSION="2.0.3"
TEMP_FILES=()

cleanup_temp_files() {
  local file
  for file in "${TEMP_FILES[@]}"; do
    [[ -e $file ]] && rm -f -- "$file" || true
  done
}
trap cleanup_temp_files EXIT

# ---------- colors ----------
bold=$'\e[1m';  dim=$'\e[2m'
red=$'\e[31m';  green=$'\e[32m';  yellow=$'\e[33m';  cyan=$'\e[36m'
normal=$'\e[0m'

BIN_DIR=/usr/local/bin
FLATPAK_ID=dev.lizardbyte.app.Sunshine
FLATPAK_UNIT=app-dev.lizardbyte.app.Sunshine.service

# Debian releases that support native .deb installation.
# Only Debian 13 (trixie) is supported: the official .deb is built against
# trixie's libminiupnpc18 and libicu76. Debian 14+ (forky) ships newer
# incompatible ABI versions; Debian 12 and older are out of support scope.
DEBIAN_NATIVE_SUPPORTED_ID="13"
DEBIAN_NATIVE_SUPPORTED_CODENAME="trixie"

[[ $EUID -eq 0 ]] && { echo "Do not run this script as root." >&2; exit 1; }

# ---------- distro detection ----------
. /etc/os-release
case " ${ID:-} ${ID_LIKE:-} " in
  *" cachyos "*) DISTRO=cachyos ;;
  *" fedora "*)  DISTRO=fedora ;;
  *" arch "*)    DISTRO=arch ;;
  *" ubuntu "*)  DISTRO=ubuntu ;;
  *" debian "*)  DISTRO=debian ;;
  *) echo "${red}Unsupported distro (${ID:-?}). Only Fedora, Arch, CachyOS, Ubuntu and Debian (and derivatives).${normal}" >&2; exit 1 ;;
esac

# ---------- immutable detection ----------
is_immutable() {
  [[ -e /run/ostree-booted ]] && return 0
  command -v rpm-ostree >/dev/null 2>&1 && rpm-ostree status >/dev/null 2>&1 && return 0
  command -v bootc >/dev/null 2>&1 && bootc status >/dev/null 2>&1 && return 0
  command -v transactional-update >/dev/null 2>&1 && return 0
  [[ "${ID:-}" == steamos ]] || [[ "${VARIANT_ID:-}" == steamos ]] && return 0
  case "${VARIANT_ID:-}" in
    silverblue|kinoite|sericea|onyx|bazzite|bluefin|aurora|ucore|steamos|steamdeck|holoiso) return 0 ;;
  esac
  case "${ID:-}" in
    bazzite|steamos|steamdeck|holoiso|silverblue|kinoite|sericea|onyx|bluefin|aurora|ucore) return 0 ;;
  esac
  return 1
}

IMMUTABLE=0
if is_immutable; then IMMUTABLE=1; fi

# Returns 0 when this Debian system may use native .deb installation.
debian_native_ok() {
  [[ $DISTRO == debian ]] || return 0
  [[ "${VERSION_ID:-}" == "$DEBIAN_NATIVE_SUPPORTED_ID" ]]
}

# ---------- helpers ----------
apt_update_once() {
  [[ -n ${APT_UPDATED:-} ]] && return
  command -v apt-get >/dev/null || return 0
  sudo apt-get update -qq
  APT_UPDATED=1
}

pkg_install() {
  if (( IMMUTABLE )); then
    echo "${red}Package installation is not supported on immutable systems.${normal}" >&2
    echo "Use Flatpak or install packages via 'rpm-ostree install <package>' (requires reboot)." >&2
    return 1
  fi
  case $DISTRO in
    fedora)        sudo dnf install -y "$@" ;;
    arch|cachyos)  sudo pacman -S --needed --noconfirm "$@" ;;
    ubuntu|debian) apt_update_once; sudo apt-get install -y "$@" ;;
  esac
}

native_installed()  { command -v sunshine >/dev/null 2>&1; }
flatpak_installed() { command -v flatpak >/dev/null 2>&1 && flatpak info "$FLATPAK_ID" >/dev/null 2>&1; }

# Returns the actual systemd user unit name for a native Sunshine install.
native_unit() {
  local d
  for d in /usr/lib/systemd/user /etc/systemd/user "$HOME/.config/systemd/user"; do
    [[ -f "$d/app-dev.lizardbyte.app.Sunshine.service" ]] && { echo "app-dev.lizardbyte.app.Sunshine.service"; return 0; }
  done
  for d in /usr/lib/systemd/user /etc/systemd/user "$HOME/.config/systemd/user"; do
    [[ -f "$d/sunshine.service" ]] && { echo "sunshine.service"; return 0; }
  done
  echo "app-dev.lizardbyte.app.Sunshine.service"
}

is_vmon_configured() {
  command -v jq >/dev/null || return 1
  local conf
  for conf in "$HOME/.config/sunshine/apps.json" \
              "$HOME/.var/app/$FLATPAK_ID/config/sunshine/apps.json"; do
    if [[ -f $conf ]] && jq -e '.apps[]? | select(.name == "Virtual Monitor")' "$conf" &>/dev/null; then
      return 0
    fi
  done
  return 1
}

ubuntu_version() {
  if [[ ${ID:-} == ubuntu ]]; then echo "${VERSION_ID:-}"; return; fi
  case "${UBUNTU_CODENAME:-}" in
    jammy)  echo 22.04 ;;
    noble)  echo 24.04 ;;
    plucky) echo 25.04 ;;
    questing) echo 25.10 ;;
    *)      echo "" ;;
  esac
}

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

# ---------- visual ----------
print_banner() {
  local line="  ────────────────────────────────────────────────────────"
  echo
  echo "$line"
  echo "  ${bold}Sunshine Setup${normal}  ${dim}v${SCRIPT_VERSION}${normal}"
  echo "  ${dim}Fedora · Arch · CachyOS · Ubuntu · Debian · Immutable systems${normal}"
  echo "$line"
}

print_system_info() {
  local n=0 f=0 sun_status imm_marker=""
  native_installed  && n=1
  flatpak_installed && f=1
  if   (( n && f )); then sun_status="${green}native + flatpak${normal}"
  elif (( n ));      then sun_status="${green}native${normal}"
  elif (( f ));      then sun_status="${green}flatpak${normal}"
  else                    sun_status="${yellow}not installed${normal}"
  fi
  (( IMMUTABLE )) && imm_marker=" ${yellow}(immutable — Flatpak recommended)${normal}"
  echo
  echo "  ${dim}System:${normal}   ${PRETTY_NAME:-$DISTRO}"
  echo "  ${dim}Desktop:${normal}  ${XDG_CURRENT_DESKTOP:-unknown}"
  echo "  ${dim}Sunshine:${normal} $sun_status"
  if [[ -n $imm_marker ]]; then
    echo "  ${dim}Mode:${normal}     $imm_marker"
  fi
  return 0
}

print_main_menu() {
  local kde_marker vmon_marker=""
  if [[ "${XDG_CURRENT_DESKTOP:-}" == *KDE* ]]; then
    kde_marker="${dim}(KDE Plasma)${normal}"
  else
    kde_marker="${yellow}(KDE Plasma required)${normal}"
  fi
  if is_vmon_configured; then vmon_marker=" ${green}(configured)${normal}"; fi

  echo
  printf "  ${cyan}1${normal})  Install Sunshine\n"
  printf "  ${cyan}2${normal})  Set up Virtual Monitor  %s%s\n" "$kde_marker" "$vmon_marker"
  printf "  ${cyan}3${normal})  Fix Error 503\n"
  printf "  ${cyan}4${normal})  Remove Virtual Monitor\n"
  printf "  ${cyan}5${normal})  Open firewall ports\n"
  printf "  ${cyan}6${normal})  Manage Sunshine service (start/stop/restart/logs)\n"
  printf "  ${cyan}7${normal})  Revert Error 503 fix\n"
  printf "  ${cyan}8${normal})  Exit\n"
  echo
  return 0
}

usage() {
  cat <<EOF
  ${bold}Sunshine Setup${normal}  ${dim}v${SCRIPT_VERSION}${normal}
  Fedora · Arch · CachyOS · Ubuntu · Debian · Immutable systems

  ${bold}Usage:${normal}
    bash $0 [command] [args...]

  ${bold}Commands:${normal}
    install [--flatpak-system|--flatpak-user|--native]   Install Sunshine
    vmon                                                  Set up the virtual monitor (KDE Plasma, Wayland)
    503                                                   Fix Moonlight's "Error 503"
    503-reset                                             Revert the Error 503 environment setting
    remove                                                Remove the virtual monitor
    firewall                                              Open Sunshine's firewall ports
    service                                               Interactive service menu

  ${bold}Service control:${normal}
    start    [--native|--flatpak]   Start service
    stop     [--native|--flatpak]   Stop service
    restart  [--native|--flatpak]   Restart service
    enable   [--native|--flatpak]   Enable auto-start at login
    disable  [--native|--flatpak]   Disable auto-start at login
    status   [--native|--flatpak]   Show systemctl status
    logs     [--native|--flatpak]   Show last 50 log lines
    follow   [--native|--flatpak]   Follow logs live (Ctrl+C to stop)
    repair   [--native|--flatpak]   Apply startup fixes (setcap + drop-in)

  ${bold}Options:${normal}
    -h, --help        Show this help
    -v, --version     Show version

  With no arguments, an interactive menu is shown.

  ${bold}Notes:${normal}
    - Arch uses yay or paru for AUR (sunshine-bin).
    - CachyOS uses pacman (repo package 'sunshine').
    - Ubuntu uses the upstream .deb (best effort; Flatpak as fallback).
    - Debian 13 (trixie): native via upstream .deb.
    - Debian 12 and 14+: Flatpak only. The official .deb is built against
      trixie's library ABI (libminiupnpc18, libicu76); Debian 14+ (forky)
      ships incompatible newer ABIs, and 12 is out of support.
    - Immutable systems (Silverblue, Kinoite, Bazzite, SteamOS, MicroOS, bootc, etc.)
      support Flatpak best. The native option is disabled.
    - '503-reset' removes the Error 503 environment setting added by this script.
    - Firewall rules can optionally be restricted to an IPv4/IPv6 CIDR.
    - Run as a normal user (sudo is requested only when needed).
EOF
}

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

# ---------- pick which installed Sunshine to configure ----------
pick_mode() {
  local n=0 f=0
  native_installed  && n=1
  flatpak_installed && f=1

  if (( IMMUTABLE )); then
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
    echo "  ${dim}(Tip: use --native or --flatpak on the command line to skip this prompt.)${normal}"
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
  command -v curl >/dev/null || pkg_install curl
  tmp=$(mktemp --suffix=.deb)
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

  apt_update_once
  sudo apt-get install -y "$tmp" || {
    echo "${red}apt could not install the package (dependency mismatch?).${normal} Use the Flatpak option instead." >&2
    return 1
  }
}

install_flatpak() {
  local scope="${1:-system}"
  echo "  Installing Sunshine (${bold}Flatpak — $scope${normal})..."

  if (( IMMUTABLE )); then
    if ! command -v flatpak >/dev/null 2>&1; then
      echo "${red}Flatpak is not installed.${normal} On immutable systems, Flatpak is pre-installed; if missing, add it via 'rpm-ostree install flatpak' (requires reboot)." >&2
      return 1
    fi
  else
    command -v flatpak >/dev/null || pkg_install flatpak
  fi

  flatpak remote-add --if-not-exists --"$scope" flathub https://dl.flathub.org/repo/flathub.flatpakrepo
  flatpak install --"$scope" -y --or-update flathub "$FLATPAK_ID"
  flatpak run --command=additional-install.sh "$FLATPAK_ID" \
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

action_install() {
  case "${1:-}" in
    --flatpak-system) install_flatpak system; return ;;
    --flatpak-user)   install_flatpak user;   return ;;
    --flatpak)        install_flatpak system; return ;;
    --native)         install_native;         return ;;
  esac

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

# ---------- virtual monitor ----------
setup_vmon() {
  if [[ "${XDG_CURRENT_DESKTOP:-}" != *KDE* ]]; then
    echo "  ${yellow}Warning:${normal} the virtual monitor only works on KDE Plasma (KWin, Wayland)."
    echo "  Current desktop: ${XDG_CURRENT_DESKTOP:-unknown}."
  fi
  pick_mode || return 1

  if (( IMMUTABLE )); then
    local missing=0
    for cmd in krfb-virtualmonitor kscreen-doctor jq; do
      if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "${red}'$cmd' not found.${normal}" >&2
        case $cmd in
          krfb-virtualmonitor) echo "  Install via 'rpm-ostree install krfb' (requires reboot)." >&2 ;;
          kscreen-doctor)      echo "  Install via 'rpm-ostree install kscreen' (requires reboot)." >&2 ;;
          jq)                  echo "  Install via 'rpm-ostree install jq' (requires reboot)." >&2 ;;
        esac
        missing=1
      fi
    done
    (( missing )) && return 1
  else
    case $DISTRO in
      fedora)        pkg_install krfb jq ;;
      arch|cachyos)  pkg_install krfb jq libkscreen ;;
      ubuntu|debian)
        for p in krfb jq kscreen; do
          pkg_install "$p" 2>/dev/null || echo "  ${yellow}Warning:${normal} could not install '$p'."
        done
        ;;
    esac
    command -v kscreen-doctor >/dev/null || {
      echo "${red}kscreen-doctor not found.${normal} It ships with KDE's kscreen/libkscreen package; is Plasma installed?" >&2; return 1; }
    command -v krfb-virtualmonitor >/dev/null || {
      echo "${red}krfb-virtualmonitor not found.${normal} Requires a recent krfb release." >&2; return 1; }
    command -v jq >/dev/null || {
      echo "${red}jq not found.${normal} Install 'jq' manually and re-run." >&2; return 1; }
  fi

  sudo mkdir -p "$BIN_DIR"
  sudo tee "$BIN_DIR/sunshine-start-vmon" >/dev/null <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
umask 077
WIDTH="${SUNSHINE_CLIENT_WIDTH:-1920}"
HEIGHT="${SUNSHINE_CLIENT_HEIGHT:-1080}"
FPS="${SUNSHINE_CLIENT_FPS%.*}"
FPS="${FPS:-60}"
[[ $WIDTH  =~ ^[0-9]+$ ]] || WIDTH=1920
[[ $HEIGHT =~ ^[0-9]+$ ]] || HEIGHT=1080
[[ $FPS    =~ ^[0-9]+$ ]] || FPS=60
FPS_MHZ=$(( FPS * 1000 ))
RES="${WIDTH}x${HEIGHT}"
NAME="sunshine-vmon"

VMON_BASE="${XDG_RUNTIME_DIR:-/tmp}/sunshine-vmon-$(id -u)"
VMON_PID="${VMON_BASE}.pid"
VMON_STATE_DIR="${VMON_BASE}.state"
OUTPUTS_JSON="$VMON_STATE_DIR/outputs.json"
VMON_MODE="${SUNSHINE_VMON_MODE:-}"
SUNSHINE_FLATPAK_CONF="${HOME}/.var/app/dev.lizardbyte.app.Sunshine/config/sunshine/sunshine.conf"
SUNSHINE_CONF="${HOME}/.config/sunshine/sunshine.conf"
STARTED_PID=""
CONFIG_TMP=""
SETUP_COMPLETE=0

restore_saved_outputs() {
  local output failed=0
  [[ -f "$VMON_STATE_DIR/enabled-outputs" ]] || return 0
  while IFS= read -r output; do
    [[ -n $output ]] || continue
    if ! kscreen-doctor "output.${output}.enable"; then
      echo "Could not restore display output '$output'." >&2
      failed=1
    fi
  done < "$VMON_STATE_DIR/enabled-outputs"
  return "$failed"
}

restore_saved_config() {
  local conf tmp
  [[ -f "$VMON_STATE_DIR/config-path" && -f "$VMON_STATE_DIR/output-name.original" ]] || return 0
  IFS= read -r conf < "$VMON_STATE_DIR/config-path" || return 1
  case "$conf" in "$SUNSHINE_FLATPAK_CONF"|"$SUNSHINE_CONF") ;; *) return 1 ;; esac
  [[ -f $conf ]] || return 0
  tmp=$(mktemp "${conf}.sunshine-vmon.XXXXXX") || return 1
  CONFIG_TMP=$tmp
  if ! sed -E '/^[[:space:]]*output_name[[:space:]]*(=|$)/d' "$conf" > "$tmp" \
      || ! { if [[ -s "$VMON_STATE_DIR/output-name.original" && -s $tmp ]] \
        && [[ $(tail -c1 "$tmp" | wc -l) -eq 0 ]]; then printf '\n' >> "$tmp"; fi; } \
      || ! cat "$VMON_STATE_DIR/output-name.original" >> "$tmp" \
      || ! chmod --reference="$conf" "$tmp" \
      || ! mv "$tmp" "$conf"; then
    rm -f -- "$tmp"
    CONFIG_TMP=""
    return 1
  fi
  CONFIG_TMP=""
}

is_vmon_process() {
  local pid=$1 process_command=""
  [[ $pid =~ ^[0-9]+$ && -r /proc/$pid/cmdline ]] || return 1
  IFS= read -r -d '' process_command < "/proc/$pid/cmdline" || true
  [[ ${process_command##*/} == krfb-virtualmonitor ]]
}

process_is_running() {
  local pid=$1 stat_line state
  [[ -r /proc/$pid/stat ]] || return 1
  IFS= read -r stat_line < "/proc/$pid/stat" || return 1
  stat_line=${stat_line##*) }
  state=${stat_line%% *}
  [[ -n $state && $state != Z ]]
}

remove_saved_state() {
  rm -f -- "$VMON_STATE_DIR/enabled-outputs" \
    "$VMON_STATE_DIR/output-name.original" \
    "$VMON_STATE_DIR/config-path" \
    "$VMON_STATE_DIR/outputs.json"
  rmdir "$VMON_STATE_DIR" 2>/dev/null || true
}

cleanup_failed_start() {
  local status=$1 failed=0
  trap - EXIT
  if (( ! SETUP_COMPLETE )); then
    set +e
    restore_saved_outputs || failed=1
    restore_saved_config || failed=1
    [[ -n $CONFIG_TMP ]] && rm -f -- "$CONFIG_TMP"
    if [[ -n $STARTED_PID ]]; then
      kill -TERM "$STARTED_PID" 2>/dev/null
      for attempt in $(seq 1 10); do
        process_is_running "$STARTED_PID" || break
        sleep 0.2
      done
      if process_is_running "$STARTED_PID"; then
        kill -KILL "$STARTED_PID" 2>/dev/null
        sleep 0.2
      fi
      if process_is_running "$STARTED_PID"; then
        echo "Could not terminate virtual-monitor process $STARTED_PID." >&2
        failed=1
      else
        wait "$STARTED_PID" 2>/dev/null
        rm -f -- "$VMON_PID"
      fi
    fi
    rm -f -- "$OUTPUTS_JSON"
    if (( failed )); then
      echo "Virtual monitor rollback was incomplete; saved state remains in $VMON_STATE_DIR." >&2
    else
      remove_saved_state
    fi
  fi
  exit "$status"
}
trap 'cleanup_failed_start $?' EXIT

if [[ $VMON_MODE == flatpak ]]; then
  CONF="$SUNSHINE_FLATPAK_CONF"
elif [[ $VMON_MODE == native ]]; then
  CONF="$SUNSHINE_CONF"
elif [[ -f "$SUNSHINE_FLATPAK_CONF" ]]; then
  CONF="$SUNSHINE_FLATPAK_CONF"
elif [[ -f "$SUNSHINE_CONF" ]]; then
  CONF="$SUNSHINE_CONF"
else
  echo "No sunshine.conf found!" >&2; exit 1
fi
if [[ ! -f "$CONF" ]]; then
  echo "Sunshine config not found at $CONF (mode: ${VMON_MODE:-auto})." >&2
  exit 1
fi

mkdir -p "$VMON_STATE_DIR"
chmod 700 "$VMON_STATE_DIR"

if [[ -f "$VMON_PID" ]]; then
  existing_pid=$(cat "$VMON_PID")
  if is_vmon_process "$existing_pid"; then
    SETUP_COMPLETE=1
    echo "sunshine-vmon already running (pid $existing_pid)."
    exit 0
  fi
  if [[ $existing_pid =~ ^[0-9]+$ ]] && kill -0 "$existing_pid" 2>/dev/null; then
    echo "Ignoring stale virtual-monitor PID file that points to another process." >&2
  fi
  rm -f -- "$VMON_PID"
fi

if [[ -f "$VMON_STATE_DIR/enabled-outputs" || -f "$VMON_STATE_DIR/config-path" ]]; then
  recovery_failed=0
  restore_saved_outputs || recovery_failed=1
  restore_saved_config || recovery_failed=1
  if (( recovery_failed )); then
    SETUP_COMPLETE=1
    echo "Could not recover the previous virtual monitor state; saved state remains in $VMON_STATE_DIR." >&2
    exit 1
  fi
  remove_saved_state
fi

pick_free_port() {
  local p
  if ! command -v ss >/dev/null 2>&1; then
    echo "ss is unavailable; trying virtual-monitor port 5905." >&2
    echo 5905
    return 0
  fi
  for p in 5905 5906 5907 5908 5909; do
    if ! ss -H -ltn 2>/dev/null | awk -v suffix=":$p" '$4 ~ (suffix "$") { found=1 } END { exit found ? 0 : 1 }'; then
      echo "$p"; return 0
    fi
  done
  return 1
}
if ! PORT=$(pick_free_port); then
  echo "Could not find a free virtual-monitor port (5905-5909)." >&2
  exit 1
fi

echo "Creating virtual display: $RES @ ${FPS}Hz"
VNC_PASS=$(head -c 24 /dev/urandom | base64 | tr -dc A-Za-z0-9)
krfb-virtualmonitor --resolution "$RES" --name "$NAME" --password "$VNC_PASS" --port "$PORT" &
STARTED_PID=$!
printf '%s\n' "$STARTED_PID" > "$VMON_PID"

found=0
for attempt in $(seq 1 20); do
  if ! kill -0 "$STARTED_PID" 2>/dev/null; then
    echo "krfb-virtualmonitor exited before creating the virtual display." >&2
    exit 1
  fi
  if kscreen-doctor --json > "$OUTPUTS_JSON" 2>/dev/null \
      && jq -e --arg v "Virtual-$NAME" '.outputs[]? | select(.name == $v)' "$OUTPUTS_JSON" >/dev/null 2>&1; then
    found=1
    break
  fi
  sleep 0.5
done
if (( ! found )); then
  echo "The virtual display did not appear within 10 seconds." >&2
  exit 1
fi

kscreen-doctor "output.Virtual-${NAME}.addCustomMode.${WIDTH}.${HEIGHT}.${FPS_MHZ}.full"
if ! kscreen-doctor --json > "$OUTPUTS_JSON" \
    || ! jq -e --arg v "Virtual-$NAME" \
      '(.outputs | type == "array") and any(.outputs[]; .name == $v and .enabled == true)' \
      "$OUTPUTS_JSON" >/dev/null; then
  echo "Could not read the display configuration from kscreen-doctor." >&2
  exit 1
fi

jq -r --arg v "Virtual-$NAME" \
  '.outputs[]? | select(.name != $v and .enabled == true) | .name' \
  "$OUTPUTS_JSON" > "$VMON_STATE_DIR/enabled-outputs"
printf '%s\n' "$CONF" > "$VMON_STATE_DIR/config-path"
awk '/^[[:space:]]*output_name[[:space:]]*(=|$)/' "$CONF" \
  > "$VMON_STATE_DIR/output-name.original"

while IFS= read -r output; do
  [[ -n $output ]] || continue
  kscreen-doctor "output.${output}.disable"
  sleep 0.5
done < "$VMON_STATE_DIR/enabled-outputs"

tmp=$(mktemp "${CONF}.sunshine-vmon.XXXXXX")
CONFIG_TMP=$tmp
if ! sed -E '/^[[:space:]]*output_name[[:space:]]*(=|$)/d' "$CONF" > "$tmp" \
    || ! { if [[ -s $tmp ]] && [[ $(tail -c1 "$tmp" | wc -l) -eq 0 ]]; then printf '\n' >> "$tmp"; fi; } \
    || ! printf 'output_name = Virtual-%s\n' "$NAME" >> "$tmp" \
    || ! chmod --reference="$CONF" "$tmp" \
    || ! mv "$tmp" "$CONF"; then
  rm -f -- "$tmp"
  CONFIG_TMP=""
  echo "Could not set output_name in $CONF." >&2
  exit 1
fi
CONFIG_TMP=""

rm -f -- "$OUTPUTS_JSON"
SETUP_COMPLETE=1
EOF

  sudo tee "$BIN_DIR/sunshine-stop-vmon" >/dev/null <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
umask 077
VMON_BASE="${XDG_RUNTIME_DIR:-/tmp}/sunshine-vmon-$(id -u)"
VMON_PID="${VMON_BASE}.pid"
VMON_STATE_DIR="${VMON_BASE}.state"
SUNSHINE_FLATPAK_CONF="${HOME}/.var/app/dev.lizardbyte.app.Sunshine/config/sunshine/sunshine.conf"
SUNSHINE_CONF="${HOME}/.config/sunshine/sunshine.conf"
CONFIG_TMP=""

restore_saved_outputs() {
  local output failed=0
  [[ -f "$VMON_STATE_DIR/enabled-outputs" ]] || return 0
  while IFS= read -r output; do
    [[ -n $output ]] || continue
    if ! kscreen-doctor "output.${output}.enable"; then
      echo "Could not restore display output '$output'." >&2
      failed=1
    fi
  done < "$VMON_STATE_DIR/enabled-outputs"
  return "$failed"
}

restore_saved_config() {
  local conf tmp
  [[ -f "$VMON_STATE_DIR/config-path" && -f "$VMON_STATE_DIR/output-name.original" ]] || return 0
  IFS= read -r conf < "$VMON_STATE_DIR/config-path" || return 1
  case "$conf" in "$SUNSHINE_FLATPAK_CONF"|"$SUNSHINE_CONF") ;; *) return 1 ;; esac
  [[ -f $conf ]] || return 0
  tmp=$(mktemp "${conf}.sunshine-vmon.XXXXXX") || return 1
  CONFIG_TMP=$tmp
  if ! sed -E '/^[[:space:]]*output_name[[:space:]]*(=|$)/d' "$conf" > "$tmp" \
      || ! { if [[ -s "$VMON_STATE_DIR/output-name.original" && -s $tmp ]] \
        && [[ $(tail -c1 "$tmp" | wc -l) -eq 0 ]]; then printf '\n' >> "$tmp"; fi; } \
      || ! cat "$VMON_STATE_DIR/output-name.original" >> "$tmp" \
      || ! chmod --reference="$conf" "$tmp" \
      || ! mv "$tmp" "$conf"; then
    rm -f -- "$tmp"
    CONFIG_TMP=""
    return 1
  fi
  CONFIG_TMP=""
}

cleanup_config_tmp() {
  [[ -n $CONFIG_TMP ]] && rm -f -- "$CONFIG_TMP" || true
}
trap cleanup_config_tmp EXIT

is_vmon_process() {
  local pid=$1 process_command=""
  [[ $pid =~ ^[0-9]+$ && -r /proc/$pid/cmdline ]] || return 1
  IFS= read -r -d '' process_command < "/proc/$pid/cmdline" || true
  [[ ${process_command##*/} == krfb-virtualmonitor ]]
}

remove_saved_state() {
  rm -f -- "$VMON_STATE_DIR/enabled-outputs" \
    "$VMON_STATE_DIR/output-name.original" \
    "$VMON_STATE_DIR/config-path" \
    "$VMON_STATE_DIR/outputs.json"
  rmdir "$VMON_STATE_DIR" 2>/dev/null || true
}

failed=0
had_state=0
had_pid=0
if [[ -f "$VMON_PID" ]]; then had_pid=1; fi
if [[ -d "$VMON_STATE_DIR" ]]; then
  had_state=1
  restore_saved_outputs || failed=1
  restore_saved_config || failed=1
fi

if [[ -f "$VMON_PID" ]]; then
  pid=$(cat "$VMON_PID")
  if is_vmon_process "$pid"; then
    if ! kill "$pid" 2>/dev/null; then
      echo "Could not stop virtual-monitor process $pid." >&2
      failed=1
    else
      for attempt in $(seq 1 10); do
        is_vmon_process "$pid" || break
        sleep 0.2
      done
      if is_vmon_process "$pid"; then
        if ! kill -KILL "$pid" 2>/dev/null; then
          echo "Could not terminate virtual-monitor process $pid." >&2
          failed=1
        else
          for attempt in $(seq 1 10); do
            is_vmon_process "$pid" || break
            sleep 0.2
          done
          if is_vmon_process "$pid"; then
            echo "Virtual-monitor process $pid is still running after SIGKILL." >&2
            failed=1
          fi
        fi
      fi
    fi
  elif [[ ! $pid =~ ^[0-9]+$ ]]; then
    echo "Ignoring invalid virtual-monitor PID file." >&2
    failed=1
  elif kill -0 "$pid" 2>/dev/null; then
    echo "PID $pid does not belong to krfb-virtualmonitor; refusing to terminate it." >&2
    failed=1
  fi
  if (( ! failed )); then rm -f -- "$VMON_PID"; fi
fi

if (( failed )); then
  echo "Virtual-monitor cleanup was incomplete; saved state remains in $VMON_STATE_DIR." >&2
  exit 1
fi
if (( had_state )); then remove_saved_state; fi
if (( had_pid && !had_state )); then
  echo "No saved display state was available; existing output states were left unchanged." >&2
fi
EOF

  sudo chmod 755 "$BIN_DIR/sunshine-start-vmon" "$BIN_DIR/sunshine-stop-vmon"
  command -v restorecon >/dev/null && sudo restorecon "$BIN_DIR/sunshine-start-vmon" "$BIN_DIR/sunshine-stop-vmon" || true

  local DO UNDO RT
  if [[ $MODE == flatpak ]]; then
    local uid; uid=$(id -u)
    local wl_display="${WAYLAND_DISPLAY:-}"
    if [[ -z $wl_display ]]; then
      wl_display=$(ls "/run/user/$uid"/wayland-* 2>/dev/null | head -1)
      wl_display="${wl_display##*/}"
    fi
    wl_display="${wl_display:-wayland-0}"
    local xdg_rt="${XDG_RUNTIME_DIR:-/run/user/$uid}"
    local dbus_a="${DBUS_SESSION_BUS_ADDRESS:-unix:path=/run/user/$uid/bus}"
    RT="QT_QPA_PLATFORM=wayland WAYLAND_DISPLAY=$wl_display XDG_RUNTIME_DIR=$xdg_rt DBUS_SESSION_BUS_ADDRESS=$dbus_a"
    DO="sh -c \"flatpak-spawn --host --env=SUNSHINE_CLIENT_WIDTH=\$SUNSHINE_CLIENT_WIDTH --env=SUNSHINE_CLIENT_HEIGHT=\$SUNSHINE_CLIENT_HEIGHT --env=SUNSHINE_CLIENT_FPS=\$SUNSHINE_CLIENT_FPS --env=SUNSHINE_VMON_MODE=flatpak --env=${RT// / --env=} $BIN_DIR/sunshine-start-vmon\""
    UNDO="flatpak-spawn --host env $RT $BIN_DIR/sunshine-stop-vmon"
  else
    DO="env SUNSHINE_VMON_MODE=native $BIN_DIR/sunshine-start-vmon"
    UNDO="$BIN_DIR/sunshine-stop-vmon"
  fi

  mkdir -p "$(dirname "$APP_CONF")"
  [[ -f "$APP_CONF" ]] || echo '{"env":{},"apps":[]}' > "$APP_CONF"
  local TMP; TMP=$(mktemp)
  TEMP_FILES+=("$TMP")
  if jq --arg cmd_do "$DO" --arg cmd_undo "$UNDO" '
    {
      "name": "Virtual Monitor", "cmd": "", "output": "", "image-path": "",
      "auto-detach": true, "elevated": false, "exclude-global-prep-cmd": false,
      "exit-timeout": 5, "wait-all": true,
      "prep-cmd": [{"do": $cmd_do, "undo": $cmd_undo}]
    } as $app
    | .apps = ((.apps // []) | map(select(.name != $app.name)) + [$app])
  ' "$APP_CONF" > "$TMP"; then
    mv "$TMP" "$APP_CONF"
    echo "  'Virtual Monitor' app written to $APP_CONF"
  else
    rm -f "$TMP"
    echo "${red}Could not update $APP_CONF (invalid JSON?).${normal}" >&2
    return 1
  fi

  local DROPIN="$HOME/.config/systemd/user/${UNIT}.d"
  mkdir -p "$DROPIN"
  printf '[Service]\nExecStopPost=%s/sunshine-stop-vmon\n' "$BIN_DIR" > "$DROPIN/vmon.conf"
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

# ---------- remove virtual monitor ----------
remove_vmon() {
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
      local TMP; TMP=$(mktemp)
      TEMP_FILES+=("$TMP")
      if jq '.apps |= map(select(.name != "Virtual Monitor"))' "$conf" > "$TMP"; then
        mv "$TMP" "$conf"; echo "  Entry removed from $conf"
      else
        rm -f "$TMP"
        echo "${red}Could not update $conf (invalid JSON?). Leaving virtual-monitor files in place.${normal}" >&2
        return 1
      fi
    fi
    rm -f "$HOME/.config/systemd/user/${unit}.d/vmon.conf"
  done
  systemctl --user daemon-reload
  sudo rm -f "$BIN_DIR/sunshine-start-vmon" "$BIN_DIR/sunshine-stop-vmon"
  echo "  Virtual monitor removed. (The Error 503 fix was left untouched.)"
}

# ---------- firewall ----------
SUNSHINE_TCP=(47984 47989 48010)
SUNSHINE_UDP=(47998 47999 48000 48002)
WEBUI_PORT=47990

valid_cidr_syntax() {
  local cidr=$1 address prefix octet
  local -a octets
  [[ $cidr =~ ^[0-9A-Fa-f:.]+/[0-9]{1,3}$ ]] || return 1
  address=${cidr%/*}
  prefix=${cidr#*/}
  if [[ $address == *:* ]]; then
    (( 10#$prefix <= 128 ))
    return
  fi
  (( 10#$prefix <= 32 )) || return 1
  IFS=. read -r -a octets <<< "$address"
  (( ${#octets[@]} == 4 )) || return 1
  for octet in "${octets[@]}"; do
    [[ $octet =~ ^[0-9]{1,3}$ ]] || return 1
    (( 10#$octet <= 255 )) || return 1
  done
}

detect_firewall() {
  FW_BACKEND=""
  local fwd=0 ufw=0 fwd_installed=0 ufw_installed=0
  if command -v firewall-cmd >/dev/null; then
    fwd_installed=1
    systemctl is-active --quiet firewalld && fwd=1
  fi
  if command -v ufw >/dev/null; then
    ufw_installed=1
    local st; st=$(sudo env LC_ALL=C ufw status 2>/dev/null || true)
    [[ $st == *"Status: active"* ]] && ufw=1
  fi

  if (( fwd && ufw )); then
    echo
    echo "  ${yellow}Both firewalld and ufw are active.${normal} Which one should be configured?"
    choose "Firewall" "firewalld" "ufw" || return 1
    case "$REPLY" in 1) FW_BACKEND=firewalld ;; 2) FW_BACKEND=ufw ;; esac
  elif (( fwd )); then FW_BACKEND=firewalld
  elif (( ufw )); then FW_BACKEND=ufw
  else
    (( fwd_installed )) && echo "  firewalld is installed but not running."
    (( ufw_installed )) && echo "  ufw is installed but inactive."
  fi
  return 0
}

open_firewall() {
  detect_firewall || return 1
  local backend=$FW_BACKEND

  local tcp=("${SUNSHINE_TCP[@]}") udp=("${SUNSHINE_UDP[@]}")
  if [[ -z $backend ]]; then
    echo "  ${yellow}No active firewall (firewalld/ufw) detected.${normal}"
    echo "  If you use nftables/iptables or a router/cloud firewall, open these manually:"
    echo "    TCP: ${tcp[*]} (+ $WEBUI_PORT for the web UI)"
    echo "    UDP: ${udp[*]} (+ 5353 for mDNS discovery)"
    return 0
  fi

  echo "  Detected firewall: ${bold}${backend}${normal} (active)"
  if ask_yes_no "Also expose the web UI port ($WEBUI_PORT) to the network? (not needed if you only use https://localhost:$WEBUI_PORT)"; then
    tcp+=("$WEBUI_PORT")
  fi
  local source_cidr=""
  echo "  Optional: restrict access to a LAN IPv4/IPv6 CIDR (for example 192.168.1.0/24 or fd00::/64)."
  printf "  Leave blank to allow these ports from any source: "
  if ! read -r source_cidr; then
    echo
    echo "  Aborted."
    return 1
  fi
  if [[ -n $source_cidr ]] && ! valid_cidr_syntax "$source_cidr"; then
    echo "${red}Invalid CIDR syntax:${normal} $source_cidr" >&2
    return 1
  fi
  if [[ -n $source_cidr ]]; then
    echo "  This will allow: TCP ${tcp[*]} | UDP ${udp[*]} 5353 (mDNS), source $source_cidr"
    echo "  ${yellow}Existing unrestricted firewall rules are not removed and may still allow broader access.${normal}"
  else
    echo "  This will allow: TCP ${tcp[*]} | UDP ${udp[*]} 5353 (mDNS), from any source"
  fi
  echo "  ${yellow}These ports become reachable on your network; use a trusted LAN.${normal}"
  ask_yes_no "Proceed?" || { echo "  Aborted."; return 0; }

  local p family
  if [[ $backend == firewalld ]]; then
    if [[ -n $source_cidr ]]; then
      family=ipv4
      [[ $source_cidr == *:*/* ]] && family=ipv6
      for p in "${tcp[@]}"; do
        sudo firewall-cmd --permanent --add-rich-rule="rule family=\"$family\" source address=\"$source_cidr\" port port=\"$p\" protocol=\"tcp\" accept"
      done
      for p in "${udp[@]}"; do
        sudo firewall-cmd --permanent --add-rich-rule="rule family=\"$family\" source address=\"$source_cidr\" port port=\"$p\" protocol=\"udp\" accept"
      done
      sudo firewall-cmd --permanent --add-rich-rule="rule family=\"$family\" source address=\"$source_cidr\" port port=\"5353\" protocol=\"udp\" accept"
    else
      for p in "${tcp[@]}"; do sudo firewall-cmd --permanent --add-port="$p/tcp"; done
      for p in "${udp[@]}"; do sudo firewall-cmd --permanent --add-port="$p/udp"; done
      sudo firewall-cmd --permanent --add-service=mdns
    fi
    sudo firewall-cmd --reload
    echo "  ${dim}Current firewall rules:${normal}"
    sudo firewall-cmd --list-all | sed 's/^/    /' || true
  else
    if [[ -n $source_cidr ]]; then
      for p in "${tcp[@]}"; do sudo ufw allow from "$source_cidr" to any port "$p" proto tcp comment 'Sunshine'; done
      for p in "${udp[@]}"; do sudo ufw allow from "$source_cidr" to any port "$p" proto udp comment 'Sunshine'; done
      sudo ufw allow from "$source_cidr" to any port 5353 proto udp comment 'Sunshine mDNS'
    else
      for p in "${tcp[@]}"; do sudo ufw allow "$p/tcp" comment 'Sunshine'; done
      for p in "${udp[@]}"; do sudo ufw allow "$p/udp" comment 'Sunshine'; done
      sudo ufw allow 5353/udp comment 'Sunshine mDNS'
    fi
    echo "  ${dim}Current rules:${normal}"
    sudo ufw status | grep -i sunshine | sed 's/^/    /' || true
  fi
  echo "  ${bold}Firewall ports opened.${normal}"
}

# ---------- dispatch ----------
run_action() {
  case "$1" in
    install)  action_install "${2:-}" ;;
    vmon)     setup_vmon ;;
    503)      fix_503 ;;
    503-reset) reset_503 ;;
    remove)   remove_vmon ;;
    firewall) open_firewall ;;
    service)  manage_service ;;
    start|stop|restart|enable|disable|status|logs|follow)
      service_action "$1" "${2:-}" ;;
    repair)   repair_startup "${2:-}" ;;
    *) echo "Invalid action: $1" >&2; echo "Run 'bash $0 --help' for usage." >&2; exit 1 ;;
  esac
}

main_menu() {
  print_banner
  while true; do
    print_system_info
    print_main_menu
    printf "  ${bold}Select [1-8]:${normal} "
    if ! read -r choice; then echo; exit 0; fi
    echo
    case "$choice" in
      1) run_action install  || true ;;
      2) run_action vmon     || true ;;
      3) run_action 503      || true ;;
      4) run_action remove   || true ;;
      5) run_action firewall || true ;;
      6) run_action service  || true ;;
      7) run_action 503-reset || true ;;
      8|q|Q|quit|exit) exit 0 ;;
      "") continue ;;
      *) printf "  ${red}Invalid option '%s'.${normal}\n" "$choice"; sleep 1; continue ;;
    esac
    echo
  done
}

if [[ $# -ge 1 ]]; then
  case "$1" in
    -h|--help|help) usage; exit 0 ;;
    -v|--version)   echo "sunshine-setup.sh $SCRIPT_VERSION"; exit 0 ;;
  esac
  run_action "$@"
  exit 0
fi

main_menu