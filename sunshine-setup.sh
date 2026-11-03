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

# Used by sourced feature modules.
# shellcheck disable=SC2034
BIN_DIR=/usr/local/bin
FLATPAK_ID=dev.lizardbyte.app.Sunshine
# Used by sourced feature modules.
# shellcheck disable=SC2034
FLATPAK_UNIT=app-dev.lizardbyte.app.Sunshine.service

# Debian releases that support native .deb installation.
# Only Debian 13 (trixie) is supported: the official .deb is built against
# trixie's libminiupnpc18 and libicu76. Debian 14+ (forky) ships newer
# incompatible ABI versions; Debian 12 and older are out of support scope.
DEBIAN_NATIVE_SUPPORTED_ID="13"
# Used by sourced feature modules.
# shellcheck disable=SC2034
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

# ---------- module loading ----------
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=modules/service.sh
source "$SCRIPT_DIR/modules/service.sh"
# shellcheck source=modules/install.sh
source "$SCRIPT_DIR/modules/install.sh"
# shellcheck source=modules/virtual-monitor-add.sh
source "$SCRIPT_DIR/modules/virtual-monitor-add.sh"
# shellcheck source=modules/virtual-monitor-remove.sh
source "$SCRIPT_DIR/modules/virtual-monitor-remove.sh"
# shellcheck source=modules/fixes.sh
source "$SCRIPT_DIR/modules/fixes.sh"
# shellcheck source=modules/firewall.sh
source "$SCRIPT_DIR/modules/firewall.sh"

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
  if [[ -n $imm_marker ]]; then echo "  ${dim}Mode:${normal}     $imm_marker"; fi
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
    virtual-monitor                                      Open virtual monitor menu
    vmon                                                  Add/configure virtual monitor
    remove                                                Remove virtual monitor
    fixes                                                 Open Error 503 fixes menu
    503                                                   Apply the Error 503 fix
    503-reset                                             Revert the Error 503 fix
    firewall                                              Configure Sunshine firewall ports
    service                                               Interactive service menu

  ${bold}Service control:${normal}
    start|stop|restart|enable|disable|status|logs|follow [--native|--flatpak]
    repair [--native|--flatpak]

  ${bold}Options:${normal}
    -h, --help        Show this help
    -v, --version     Show version

  With no arguments, an interactive menu is shown.
  Virtual Monitor and Error 503 actions are grouped in their own menus.

  ${bold}Notes:${normal}
    - Arch uses yay or paru for AUR (sunshine-bin).
    - CachyOS uses pacman (repo package 'sunshine').
    - Ubuntu uses the upstream .deb (best effort; Flatpak as fallback).
    - Debian 13 (trixie): native via upstream .deb; Debian 12 and 14+: Flatpak only.
    - Immutable systems support Flatpak best; native package installation is disabled.
    - Firewall rules can optionally be restricted to an IPv4/IPv6 CIDR.
    - Run as a normal user (sudo is requested only when needed).
EOF
}

virtual_monitor_menu() {
  local choice
  while true; do
    echo
    echo "  ${bold}Virtual Monitor${normal}"
    if is_vmon_configured; then
      echo "  ${green}Virtual Monitor is configured.${normal}"
    else
      echo "  ${yellow}Virtual Monitor is not configured.${normal}"
    fi
    printf "  ${cyan}1${normal})  Add / configure Virtual Monitor\n"
    printf "  ${cyan}2${normal})  Remove Virtual Monitor\n"
    printf "  ${cyan}3${normal})  Back\n\n"
    printf "  ${bold}Select [1-3]:${normal} "
    if ! read -r choice; then echo; return 0; fi
    case "$choice" in
      1) setup_vmon || true ;;
      2) remove_vmon || true ;;
      3|q|Q|back) return 0 ;;
      "") continue ;;
      *) printf "  ${red}Invalid option '%s'.${normal}\n" "$choice" ;;
    esac
  done
}

fixes_menu() {
  local choice
  while true; do
    echo
    echo "  ${bold}Error 503 Fixes${normal}"
    printf "  ${cyan}1${normal})  Apply Error 503 fix\n"
    printf "  ${cyan}2${normal})  Revert Error 503 fix\n"
    printf "  ${cyan}3${normal})  Back\n\n"
    printf "  ${bold}Select [1-3]:${normal} "
    if ! read -r choice; then echo; return 0; fi
    case "$choice" in
      1) fix_503 || true ;;
      2) reset_503 || true ;;
      3|q|Q|back) return 0 ;;
      "") continue ;;
      *) printf "  ${red}Invalid option '%s'.${normal}\n" "$choice" ;;
    esac
  done
}

run_action() {
  case "${1:-}" in
    install) action_install "${2:-}" ;;
    virtual-monitor|vmon-menu) virtual_monitor_menu ;;
    vmon|virtual-monitor-add) setup_vmon ;;
    remove|virtual-monitor-remove) remove_vmon ;;
    fixes|error-503) fixes_menu ;;
    503|fix-503) fix_503 ;;
    503-reset|reset-503) reset_503 ;;
    firewall) open_firewall ;;
    service) manage_service ;;
    start|stop|restart|enable|disable|status|logs|follow)
      service_action "$1" "${2:-}" ;;
    repair) repair_startup "${2:-}" ;;
    *)
      echo "Invalid action: ${1:-}" >&2
      echo "Run 'bash $0 --help' for usage." >&2
      return 1
      ;;
  esac
}

main_menu() {
  local choice
  print_banner
  while true; do
    print_system_info
    echo
    printf "  ${cyan}1${normal})  Install Sunshine\n"
    printf "  ${cyan}2${normal})  Virtual Monitor\n"
    printf "  ${cyan}3${normal})  Error 503 Fixes\n"
    printf "  ${cyan}4${normal})  Configure firewall\n"
    printf "  ${cyan}5${normal})  Manage Sunshine service\n"
    printf "  ${cyan}6${normal})  Exit\n\n"
    printf "  ${bold}Select [1-6]:${normal} "
    if ! read -r choice; then echo; return 0; fi
    echo
    case "$choice" in
      1) run_action install || true ;;
      2) virtual_monitor_menu ;;
      3) fixes_menu ;;
      4) run_action firewall || true ;;
      5) run_action service || true ;;
      6|q|Q|quit|exit) return 0 ;;
      "") continue ;;
      *) printf "  ${red}Invalid option '%s'.${normal}\n" "$choice" ;;
    esac
  done
}

if [[ $# -ge 1 ]]; then
  case "$1" in
    -h|--help|help) usage; exit 0 ;;
    -v|--version) echo "sunshine-setup.sh $SCRIPT_VERSION"; exit 0 ;;
  esac
  run_action "$@"
  exit $?
fi

main_menu
