#!/usr/bin/env bash
# Sunshine setup for Fedora, Arch, CachyOS, Ubuntu and Debian (KDE Plasma, Wayland for the virtual monitor).
# Ported from the Bazzite "setup-sunshine" ujust recipe and its virtual monitor scripts.
#
# Distro notes:
#   - Fedora:    native via COPR lizardbyte/stable
#   - Arch:      native via AUR (sunshine-bin) using yay or paru
#   - CachyOS:   native via pacman (repo package 'sunshine')
#   - Ubuntu/Debian: native via upstream .deb (best-effort, falls back to Flatpak on mismatch)
#   - Immutable systems (Silverblue, Kinoite, Bazzite, SteamOS, MicroOS, bootc, etc.):
#       Flatpak only. Native package installation is not supported.
#
# Interactive:  bash sunshine-setup.sh
# Direct:       bash sunshine-setup.sh install [--flatpak-system|--flatpak-user|--native]
#               bash sunshine-setup.sh vmon
#               bash sunshine-setup.sh 503
#               bash sunshine-setup.sh remove
#               bash sunshine-setup.sh firewall   (standalone; never run by the other actions)
# Run as a normal user (sudo is requested only when needed).
set -euo pipefail

# ---------- colors ----------
bold=$'\e[1m';  dim=$'\e[2m'
red=$'\e[31m';  green=$'\e[32m';  yellow=$'\e[33m';  cyan=$'\e[36m'
normal=$'\e[0m'

BIN_DIR=/usr/local/bin
FLATPAK_ID=dev.lizardbyte.app.Sunshine
FLATPAK_UNIT=app-dev.lizardbyte.app.Sunshine

[[ $EUID -eq 0 ]] && { echo "Do not run this script as root." >&2; exit 1; }

# ---------- distro detection ----------
. /etc/os-release
# NOTE: cachyos carries ID_LIKE=arch, so it must be matched *before* arch.
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
  if [[ -e /run/ostree-booted ]]; then
    return 0
  fi
  if command -v rpm-ostree >/dev/null 2>&1 && rpm-ostree status >/dev/null 2>&1; then
    return 0
  fi
  if command -v bootc >/dev/null 2>&1 && bootc status >/dev/null 2>&1; then
    return 0
  fi
  if command -v transactional-update >/dev/null 2>&1; then
    return 0
  fi
  if [[ "${ID:-}" == steamos ]] || [[ "${VARIANT_ID:-}" == steamos ]]; then
    return 0
  fi
  case "${VARIANT_ID:-}" in
    silverblue|kinoite|sericea|onyx|bazzite|bluefin|aurora|ucore|steamos|steamdeck|holoiso)
      return 0 ;;
  esac
  case "${ID:-}" in
    bazzite|steamos|steamdeck|holoiso|silverblue|kinoite|sericea|onyx|bluefin|aurora|ucore)
      return 0 ;;
  esac
  return 1
}

IMMUTABLE=0
if is_immutable; then
  IMMUTABLE=1
fi

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
    jammy) echo 22.04 ;;
    noble) echo 24.04 ;;
    *)     echo "" ;;
  esac
}

# choose <prompt> <option> [option...] — sets REPLY to 1..N
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

ask_yes_no() {   # default: No
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
  echo "  ${bold}Sunshine Setup${normal}"
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
  printf "  ${cyan}6${normal})  Exit\n"
  echo
}

usage() {
  cat <<EOF
  ${bold}Sunshine Setup${normal} — Fedora · Arch · CachyOS · Ubuntu · Debian · Immutable systems

  ${bold}Usage:${normal}
    bash $0 [command] [args...]

  ${bold}Commands:${normal}
    install [--flatpak-system|--flatpak-user|--native]   Install Sunshine (interactive if no flag)
    vmon                                                  Set up the virtual monitor (KDE Plasma, Wayland)
    503                                                   Fix Moonlight's "Error 503"
    remove                                                Remove the virtual monitor
    firewall                                              Open Sunshine's firewall ports (standalone)

  With no arguments, an interactive menu is shown.

  ${bold}Notes:${normal}
    - Arch uses yay or paru for AUR (sunshine-bin).
    - CachyOS uses pacman (repo package 'sunshine').
    - Debian/Ubuntu use the upstream .deb (best effort; Flatpak as fallback).
    - Immutable systems (Silverblue, Kinoite, Bazzite, SteamOS, MicroOS, bootc, etc.)
      support Flatpak best. The native option is disabled.
    - Run as a normal user (sudo is requested only when needed).
EOF
}

# ---------- option 1: install Sunshine ----------
install_deb() {
  if (( IMMUTABLE )); then
    echo "${red}Native .deb installation is not supported on immutable systems.${normal}" >&2
    echo "Use the Flatpak option instead." >&2
    return 1
  fi
  local os=$1 first=$2 rel used="" seen=" " url tmp arch
  local base=https://github.com/LizardByte/Sunshine/releases/latest/download
  arch=$(dpkg --print-architecture)
  command -v curl >/dev/null || pkg_install curl
  tmp=$(mktemp --suffix=.deb)
  shift
  for rel in "$@"; do
    if [[ -z $rel || $seen == *" $rel "* ]]; then continue; fi
    seen+="$rel "
    url="$base/sunshine-$os-$rel-$arch.deb"
    echo "  Trying $url"
    if curl -fsSL "$url" -o "$tmp"; then used=$rel; break; fi
  done
  if [[ -z $used ]]; then
    rm -f "$tmp"
    echo "${red}No matching .deb found.${normal} See https://github.com/LizardByte/Sunshine/releases or use the Flatpak option." >&2
    return 1
  fi
  if [[ -z $first ]]; then
    echo "  ${yellow}Could not determine your release; using the '$used' build.${normal} If dependencies fail, use the Flatpak option."
  elif [[ $used != "$first" ]]; then
    echo "  ${yellow}No .deb for your release; using the '$used' build.${normal} If dependencies fail, use the Flatpak option."
  fi
  apt_update_once
  sudo apt-get install -y "$tmp" || {
    rm -f "$tmp"
    echo "${red}apt could not install the package (dependency mismatch?).${normal} Use the Flatpak option instead." >&2
    return 1
  }
  rm -f "$tmp"
}

install_flatpak() {
  local scope="${1:-system}" # system or user
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
  
  # Avoid multiple Sunshine instances fighting over ports
  systemctl --user disable --now sunshine.service 2>/dev/null || true
  systemctl --user daemon-reload
  systemctl --user enable "$FLATPAK_UNIT" 2>/dev/null || true
  systemctl --user start  "$FLATPAK_UNIT" 2>/dev/null \
    || echo "  ${yellow}Sunshine service not started (no graphical session?).${normal}"

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
  echo "  ${bold}Flatpak installed ($scope).${normal} Web UI: https://localhost:47990"
}

install_native() {
  if (( IMMUTABLE )); then
    echo "${red}Native installation is not supported on immutable systems.${normal}" >&2
    echo "Use Flatpak instead." >&2
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
    ubuntu) install_deb ubuntu "$(ubuntu_version)" 24.04 22.04 ;;
    debian) install_deb debian "${VERSION_CODENAME:-${DEBIAN_CODENAME:-}}" trixie bookworm ;;
  esac
  flatpak_installed && systemctl --user disable --now "$FLATPAK_UNIT" 2>/dev/null || true
  systemctl --user daemon-reload
  systemctl --user enable sunshine.service 2>/dev/null || true
  systemctl --user start  sunshine.service 2>/dev/null \
    || echo "  ${yellow}Sunshine service not started (no graphical session?).${normal}"
  echo "  ${bold}Native Sunshine installed.${normal} Web UI: https://localhost:47990"
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

  local source_name
  case $DISTRO in
    fedora)        source_name=COPR ;;
    arch)          source_name="AUR (yay/paru)" ;;
    cachyos)       source_name="pacman (CachyOS)" ;;
    ubuntu|debian) source_name=".deb" ;;
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

# ---------- pick which installed Sunshine to configure (option 2) ----------
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
    choose "Mode" "Native" "Flatpak" || return 1
    case "$REPLY" in 1) MODE=native ;; 2) MODE=flatpak ;; esac
  elif (( n )); then MODE=native
  elif (( f )); then MODE=flatpak
  else
    echo "${red}Sunshine is not installed.${normal} Use option 1 first." >&2
    return 1
  fi

  if [[ $MODE == flatpak ]]; then
    APP_CONF="$HOME/.var/app/$FLATPAK_ID/config/sunshine/apps.json"; UNIT=$FLATPAK_UNIT
  else
    APP_CONF="$HOME/.config/sunshine/apps.json"; UNIT=sunshine
  fi
}

# ---------- option 2: virtual monitor ----------
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
  fi

  sudo mkdir -p "$BIN_DIR"
  sudo tee "$BIN_DIR/sunshine-start-vmon" >/dev/null <<'EOF'
#!/usr/bin/env bash
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

VMON_PID="${XDG_RUNTIME_DIR:-/tmp}/sunshine-vmon-$(id -u).pid"
VMON_MODE="${SUNSHINE_VMON_MODE:-}"
SUNSHINE_FLATPAK_CONF="${HOME}/.var/app/dev.lizardbyte.app.Sunshine/config/sunshine/sunshine.conf"
SUNSHINE_CONF="${HOME}/.config/sunshine/sunshine.conf"

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

if [[ -f "$VMON_PID" ]] && kill -0 "$(cat "$VMON_PID")" 2>/dev/null; then
  echo "sunshine-vmon already running (pid $(cat "$VMON_PID"))."
  exit 0
fi

pick_free_port() {
  local p
  if command -v ss >/dev/null 2>&1; then
    for p in 5905 5906 5907 5908 5909; do
      if ! ss -ltn 2>/dev/null | awk '{print $4}' | grep -qE ":${p}$"; then
        echo "$p"; return 0
      fi
    done
  fi
  echo 5905
}
PORT=$(pick_free_port)

echo "Creating virtual display: $RES @ ${FPS}Hz"
VNC_PASS=$(head -c 24 /dev/urandom | base64 | tr -dc A-Za-z0-9)
krfb-virtualmonitor --resolution "$RES" --name "$NAME" --password "$VNC_PASS" --port "$PORT" &
echo $! > "$VMON_PID"

sleep 3

kscreen-doctor "output.Virtual-${NAME}.addCustomMode.${WIDTH}.${HEIGHT}.${FPS_MHZ}.full"

kscreen-doctor --json |
  jq -r --arg v "Virtual-$NAME" '.outputs[] | select(.name != $v) | .name' |
  while read -r output; do
    kscreen-doctor "output.${output}.disable"
    sleep 0.5
  done

sed -i -E '/^[[:space:]]*output_name[[:space:]]*(=|$)/d' "$CONF"
[[ -s "$CONF" && $(tail -c1 "$CONF" | wc -l) -eq 0 ]] && echo >> "$CONF"
printf 'output_name = Virtual-%s\n' "$NAME" >> "$CONF"
EOF

  sudo tee "$BIN_DIR/sunshine-stop-vmon" >/dev/null <<'EOF'
#!/usr/bin/env bash
VMON_PID="${XDG_RUNTIME_DIR:-/tmp}/sunshine-vmon-$(id -u).pid"
SUNSHINE_FLATPAK_CONF="${HOME}/.var/app/dev.lizardbyte.app.Sunshine/config/sunshine/sunshine.conf"
SUNSHINE_CONF="${HOME}/.config/sunshine/sunshine.conf"

kscreen-doctor --json | jq -r '.outputs[].name' | while read -r output; do
  kscreen-doctor "output.${output}.enable"
  sleep 0.5
done

if [[ -f "$VMON_PID" ]]; then
  kill "$(cat "$VMON_PID")" 2>/dev/null || true
  rm -f "$VMON_PID"
fi

for CONF in "$SUNSHINE_FLATPAK_CONF" "$SUNSHINE_CONF"; do
  [[ -f "$CONF" ]] && sed -i -E '/^[[:space:]]*output_name[[:space:]]*(=|$)/d' "$CONF"
done
exit 0
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

  local DROPIN="$HOME/.config/systemd/user/${UNIT}.service.d"
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

# ---------- option 3: fix Error 503 ----------
fix_503() {
  if [[ "${XDG_SESSION_TYPE:-}" != wayland ]] || [[ "${XDG_CURRENT_DESKTOP:-}" != *KDE* ]]; then
    echo "  ${yellow}Warning:${normal} this fix assumes KDE Plasma on Wayland (current session: ${XDG_SESSION_TYPE:-?}, desktop: ${XDG_CURRENT_DESKTOP:-?})."
    ask_yes_no "Continue anyway?" || { echo "  Aborted."; return 0; }
  fi
  mkdir -p "$HOME/.config/environment.d"
  echo "KWIN_WAYLAND_NO_PERMISSION_CHECKS=1" > "$HOME/.config/environment.d/98-kwin-no-permission-checks.conf"
  echo "  Written to ~/.config/environment.d/98-kwin-no-permission-checks.conf:"
  sed 's/^/    /' "$HOME/.config/environment.d/98-kwin-no-permission-checks.conf"
  echo "  ${yellow}Log out and back in (or reboot)${normal} for the variable to take effect in KWin."
}

# ---------- option 4: remove the virtual monitor ----------
remove_vmon() {
  if [[ -x "$BIN_DIR/sunshine-stop-vmon" ]]; then
    "$BIN_DIR/sunshine-stop-vmon" 2>/dev/null || true
  fi
  for m in native flatpak; do
    local conf unit
    if [[ $m == flatpak ]]; then
      conf="$HOME/.var/app/$FLATPAK_ID/config/sunshine/apps.json"; unit=$FLATPAK_UNIT
    else
      conf="$HOME/.config/sunshine/apps.json"; unit=sunshine
    fi
    if [[ -f $conf ]]; then
      local TMP; TMP=$(mktemp)
      if jq '.apps |= map(select(.name != "Virtual Monitor"))' "$conf" > "$TMP"; then
        mv "$TMP" "$conf"; echo "  Entry removed from $conf"
      else
        rm -f "$TMP"; echo "${red}Could not update $conf (invalid JSON?).${normal}" >&2
      fi
    fi
    rm -f "$HOME/.config/systemd/user/${unit}.service.d/vmon.conf"
  done
  systemctl --user daemon-reload
  sudo rm -f "$BIN_DIR/sunshine-start-vmon" "$BIN_DIR/sunshine-stop-vmon"
  echo "  Virtual monitor removed. (The Error 503 fix was left untouched.)"
}

# ---------- option 5: open firewall ports (standalone) ----------
SUNSHINE_TCP=(47984 47989 48010)
SUNSHINE_UDP=(47998 47999 48000 48002)
WEBUI_PORT=47990

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
  echo "  This will allow: TCP ${tcp[*]} | UDP ${udp[*]} 5353 (mDNS)"
  echo "  ${yellow}These ports become reachable from your network, use it on a trusted LAN.${normal}"
  ask_yes_no "Proceed?" || { echo "  Aborted."; return 0; }

  local p
  if [[ $backend == firewalld ]]; then
    for p in "${tcp[@]}"; do sudo firewall-cmd --permanent --add-port="$p/tcp"; done
    for p in "${udp[@]}"; do sudo firewall-cmd --permanent --add-port="$p/udp"; done
    sudo firewall-cmd --permanent --add-service=mdns
    sudo firewall-cmd --reload
  else
    for p in "${tcp[@]}"; do sudo ufw allow "$p/tcp" comment 'Sunshine'; done
    for p in "${udp[@]}"; do sudo ufw allow "$p/udp" comment 'Sunshine'; done
    sudo ufw allow 5353/udp comment 'Sunshine mDNS'
  fi
  echo "  ${bold}Firewall ports opened.${normal}"
}

# ---------- dispatch ----------
run_action() {
  case "$1" in
    install)  action_install "${2:-}" ;;
    vmon)     setup_vmon ;;
    503)      fix_503 ;;
    remove)   remove_vmon ;;
    firewall) open_firewall ;;
    *) echo "Invalid action: $1" >&2; echo "Run 'bash $0 --help' for usage." >&2; exit 1 ;;
  esac
}

main_menu() {
  print_banner
  while true; do
    print_system_info
    print_main_menu
    printf "  ${bold}Select [1-6]:${normal} "
    if ! read -r choice; then echo; exit 0; fi
    echo
    case "$choice" in
      1) run_action install  || true ;;
      2) run_action vmon     || true ;;
      3) run_action 503      || true ;;
      4) run_action remove   || true ;;
      5) run_action firewall || true ;;
      6) exit 0 ;;
      *) printf "  ${red}Invalid option '%s'.${normal}\n" "$choice"; sleep 1; continue ;;
    esac
    echo
  done
}

if [[ $# -ge 1 ]]; then
  case "$1" in
    -h|--help|help) usage; exit 0 ;;
  esac
  run_action "$@"
  exit 0
fi

main_menu