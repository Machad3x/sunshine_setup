#!/usr/bin/env bash
# Sunshine setup for Fedora, Arch, CachyOS, Ubuntu and Debian
# (KDE Plasma or Hyprland, Wayland for the virtual monitor).
# Ported from the Bazzite "setup-sunshine" ujust recipe and its virtual monitor scripts.
#
# Distro notes:
#   - Fedora:    native via COPR lizardbyte/stable
#   - Arch:      native via AUR (sunshine-bin) using yay or paru
#   - CachyOS:   native via pacman (repo package 'sunshine')
#   - Ubuntu:    native via upstream .deb (best-effort, falls back to Flatpak)
#   - Debian 13 (trixie):  native via upstream .deb
#   - Debian 12 and older or 14+: Flatpak only (native .deb deps are incompatible)
#   - Immutable systems:   Flatpak only.
#
# Interactive:  bash sunshine-setup.sh
# Direct:       see `bash sunshine-setup.sh --help`
set -euo pipefail

SCRIPT_VERSION="3.3.0"
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

# Virtual-monitor helper scripts live in the user's home so the setup also works
# on immutable systems where /usr/local is read-only.
# Used by sourced feature modules.
# shellcheck disable=SC2034
BIN_DIR="$HOME/.local/bin"
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

# ---------- shared helpers ----------
# Resolve SCRIPT_DIR without external commands (PATH may be minimal at bootstrap).
_src=${BASH_SOURCE[0]}
if [[ $_src == */* ]]; then _srcdir=${_src%/*}; else _srcdir=.; fi
SCRIPT_DIR=$(cd -- "$_srcdir" && pwd)
unset _src _srcdir
# shellcheck source=modules/common.sh
source "$SCRIPT_DIR/modules/common.sh"

# ---------- distro detection ----------
[[ -r /etc/os-release ]] || { echo "Could not read /etc/os-release; it is required for distro detection." >&2; exit 1; }
. /etc/os-release
UNSUPPORTED_DISTRO=0
if ! detect_distro "${ID:-}" "${ID_LIKE:-}"; then
  DISTRO=unsupported
  UNSUPPORTED_DISTRO=1
fi

# ---------- immutable detection ----------
is_immutable() {
  local id=${ID:-} variant=${VARIANT_ID:-}
  id=${id,,}
  variant=${variant,,}
  [[ $DISTRO == opensuse-microos ]] && return 0
  [[ -e /run/ostree-booted ]] && return 0
  command -v rpm-ostree >/dev/null 2>&1 && rpm-ostree status >/dev/null 2>&1 && return 0
  command -v bootc >/dev/null 2>&1 && bootc status >/dev/null 2>&1 && return 0
  command -v transactional-update >/dev/null 2>&1 && return 0
  [[ $id == steamos || $variant == steamos ]] && return 0
  case $variant in
    silverblue|kinoite|sericea|onyx|bazzite|bluefin|aurora|ucore|steamos|steamdeck|holoiso) return 0 ;;
  esac
  case $id in
    bazzite|steamos|steamdeck|holoiso|silverblue|kinoite|sericea|onyx|bluefin|aurora|ucore) return 0 ;;
  esac
  return 1
}

IMMUTABLE=0
if is_immutable; then IMMUTABLE=1; fi

# Returns 0 when the upstream .deb may be installed natively: only on Debian
# 13 (trixie). Non-Debian systems always pass this check (callers gate on
# DISTRO before calling it).
debian_native_ok() {
  [[ $DISTRO != debian ]] || [[ "${VERSION_ID:-}" == "$DEBIAN_NATIVE_SUPPORTED_ID" ]]
}

# ---------- helpers ----------
apt_update_once() {
  [[ -n ${APT_UPDATED:-} ]] && return 0
  if ! command -v apt-get >/dev/null 2>&1; then
    echo "${red}apt-get was not found on this Debian/Ubuntu system.${normal}" >&2
    return 1
  fi
  sudo apt-get update -qq || return 1
  APT_UPDATED=1
}

pkg_install() {
  if (( IMMUTABLE )); then
    echo "${red}Package installation is not supported on immutable systems.${normal}" >&2
    if [[ $DISTRO == opensuse-microos ]]; then
      echo "Use Flatpak or install packages via 'transactional-update pkg install <package>' (requires reboot)." >&2
    else
      echo "Use Flatpak or install packages via 'rpm-ostree install <package>' (requires reboot)." >&2
    fi
    return 1
  fi
  case $DISTRO in
    fedora)        sudo dnf install -y "$@" ;;
    arch|cachyos)  sudo pacman -S --needed --noconfirm "$@" ;;
    ubuntu|debian) apt_update_once || return 1; sudo apt-get install -y "$@" ;;
    *)
      if (( UNSUPPORTED_DISTRO )); then
        echo "${red}Cannot install packages automatically on unsupported distro '${ID:-unknown}'.${normal}" >&2
        echo "Install the required package manually with your distro's package manager." >&2
        return 1
      fi
      echo "${red}No supported package manager is configured for '$DISTRO'.${normal}" >&2
      return 1
      ;;
  esac
}

# Returns the actual systemd user unit name for a native Sunshine install.
# Flatpak-generated app-dev...service units only ever appear under
# ~/.config/systemd/user, so just sunshine.service paths are probed here;
# the app unit name remains the fallback for unusual native packaging.
native_unit() {
  local d
  for d in /usr/lib/systemd/user /etc/systemd/user; do
    [[ -f "$d/sunshine.service" ]] && { echo "sunshine.service"; return 0; }
  done
  if [[ -f "$HOME/.config/systemd/user/sunshine.service" ]]; then
    echo "sunshine.service"; return 0
  fi
  echo "app-dev.lizardbyte.app.Sunshine.service"
}

# Detects a configured virtual monitor.
# Returns 0 (configured), 1 (not configured) or 2 (cannot check: jq missing).
is_vmon_configured() {
  command -v jq >/dev/null || return 2
  local conf
  while IFS= read -r conf; do
    [[ -f $conf ]] || continue
    if jq -e '.apps[]?
      | select(.name == "Virtual Monitor" or .name == "Virtual Monitor (Hyprland)")' "$conf" &>/dev/null; then
      return 0
    fi
  done < <(apps_conf_paths)
  return 1
}

# ---------- module loading ----------
# shellcheck source=modules/service.sh
source "$SCRIPT_DIR/modules/service.sh"
# shellcheck source=modules/install.sh
source "$SCRIPT_DIR/modules/install.sh"
# shellcheck source=modules/vmon/kde/add.sh
source "$SCRIPT_DIR/modules/vmon/kde/add.sh"
# shellcheck source=modules/vmon/kde/remove.sh
source "$SCRIPT_DIR/modules/vmon/kde/remove.sh"
# shellcheck source=modules/vmon/hyprland/common.sh
source "$SCRIPT_DIR/modules/vmon/hyprland/common.sh"
# shellcheck source=modules/vmon/hyprland/add.sh
source "$SCRIPT_DIR/modules/vmon/hyprland/add.sh"
# shellcheck source=modules/vmon/hyprland/remove.sh
source "$SCRIPT_DIR/modules/vmon/hyprland/remove.sh"
# shellcheck source=modules/vmon/dispatch.sh
source "$SCRIPT_DIR/modules/vmon/dispatch.sh"
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
  if (( UNSUPPORTED_DISTRO )); then
    imm_marker=" ${yellow}(unsupported distro — Flatpak only; failures are possible)${normal}"
  elif (( IMMUTABLE )); then
    imm_marker=" ${yellow}(immutable — Flatpak recommended)${normal}"
  fi
  echo
  echo "  ${dim}System:${normal}   ${PRETTY_NAME:-$DISTRO}"
  echo "  ${dim}Desktop:${normal}  ${XDG_CURRENT_DESKTOP:-unknown}"
  echo "  ${dim}Sunshine:${normal} $sun_status"
  if [[ -n $imm_marker ]]; then echo "  ${dim}Mode:${normal}     $imm_marker"; fi
  return 0
}

print_desktop_options() {
  local backend
  echo "  ${bold}Desktop-specific options:${normal}"
  if backend=$(virtual_monitor_backend 2>/dev/null); then
    case $backend in
      kde)
        if [[ ${XDG_SESSION_TYPE:-} == wayland ]]; then
          echo "    Virtual Monitor: KDE Plasma (Wayland)"
        else
          echo "    Virtual Monitor: requires KDE Plasma on Wayland (current session: ${XDG_SESSION_TYPE:-unknown})"
        fi
        if (( UNSUPPORTED_DISTRO || IMMUTABLE )); then
          echo "    ${dim}Host packages required for the virtual monitor: krfb, libkscreen and jq.${normal}"
          echo "    ${dim}They are not installed automatically; install them with the system's package manager.${normal}"
        fi
        echo "    Error 503 fix: available, intended for KDE Plasma (Wayland)"
        ;;
      hyprland)
        echo "    Virtual Monitor: Hyprland (Wayland)"
        if (( UNSUPPORTED_DISTRO || IMMUTABLE )); then
          echo "    ${dim}Host packages required for the virtual monitor: jq and util-linux (flock).${normal}"
          echo "    ${dim}They are not installed automatically; install them with the system's package manager.${normal}"
        fi
        echo "    Error 503 fix: available, but intended for KDE Plasma (Wayland)"
        ;;
    esac
  else
    echo "    Virtual Monitor: unavailable for ${XDG_CURRENT_DESKTOP:-unknown} (supports KDE Plasma and Hyprland on Wayland)"
    echo "    Error 503 fix: available, but intended for KDE Plasma (Wayland)"
  fi
  echo "    Firewall and Sunshine service management are also available."
}

usage() {
  cat <<EOF
  ${bold}Sunshine Setup${normal}  ${dim}v${SCRIPT_VERSION}${normal}
  Fedora · Arch · CachyOS · Ubuntu · Debian · Immutable systems

  ${bold}Usage:${normal}
    bash $0 [command] [args...]

  ${bold}Commands:${normal}
    install [--flatpak-system|--flatpak-user|--flatpak|--native]
                                          Install Sunshine (unknown flags are rejected)
    virtual-monitor | vmon-menu           Open virtual monitor menu
    vmon | virtual-monitor-add            Add/configure monitor for KDE Plasma or Hyprland
    remove | virtual-monitor-remove       Remove virtual monitor
    fixes | error-503                     Open Error 503 fixes menu
    503 | fix-503                         Apply the Error 503 fix
    503-reset | reset-503                 Revert the Error 503 fix
    firewall                              Configure Sunshine firewall ports
    service [--native|--flatpak]          Interactive service menu (scope skips detection)

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
    - Ubuntu uses the upstream .deb (best-effort; Flatpak as fallback).
    - Debian 13 (trixie): native via upstream .deb; Debian 12 and older or 14+: Flatpak only.
    - Immutable systems support Flatpak best; native package installation is disabled.
    - Firewall rules can optionally be restricted to an IPv4/IPv6 CIDR.
    - Run as a normal user (sudo is requested only when needed).
EOF
}

virtual_monitor_menu() {
  local choice status
  while true; do
    echo
    echo "  ${bold}Virtual Monitor${normal}"
    status=0
    is_vmon_configured || status=$?
    case $status in
      0) echo "  ${green}Virtual Monitor is configured.${normal}" ;;
      2) echo "  ${yellow}Cannot check the Virtual Monitor state: jq is required to inspect apps.json.${normal}" ;;
      *) echo "  ${yellow}Virtual Monitor is not configured.${normal}" ;;
    esac
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
    service) manage_service "${2:-}" ;;
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
  exit
fi

main_menu
