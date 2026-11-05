#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source "$ROOT/modules/common.sh"
source "$ROOT/modules/firewall.sh"
source "$ROOT/modules/fixes.sh"
source "$ROOT/modules/service.sh"
source "$ROOT/modules/install.sh"
source "$ROOT/modules/vmon/dispatch.sh"

red='' green='' yellow='' cyan='' dim='' normal='' bold=''
fail() {
  echo "FAIL: $*" >&2
  exit 1
}

for distro in fedora arch cachyos ubuntu debian opensuse-microos; do
  detect_distro "$distro" || fail "distro ID $distro was not recognized"
  [[ $DISTRO == "$distro" ]] || fail "distro ID $distro mapped to $DISTRO"
done
detect_distro custom "vendor debian arch" || fail "ID_LIKE fallback failed"
[[ $DISTRO == debian ]] || fail "ID_LIKE precedence changed"
detect_distro cachyos fedora || fail "exact distro ID failed"
[[ $DISTRO == cachyos ]] || fail "exact ID should take precedence over ID_LIKE"
if detect_distro unsupported unknown; then fail "unsupported distro was accepted as a supported family"; fi
echo "PASS distro detection"

for cidr in \
  0.0.0.0/0 \
  192.168.1.1/24 \
  255.255.255.255/32 \
  ::/0 \
  fd00::/64 \
  2001:db8::1/128 \
  ::ffff:192.168.1.1/128 \
  1:2:3:4:5:6:192.168.1.1/120; do
  valid_cidr_syntax "$cidr" || fail "valid CIDR rejected: $cidr"
done
for cidr in \
  256.0.0.1/24 \
  192.168.1/24 \
  192.168.1.1/33 \
  1::2::3/64 \
  1:2:3:4:5:6:7:8:9/64 \
  2001:db8::1/129 \
  ::ffff:999.2.3.4/128 \
  1.2.3.4./24 \
  192.168.1.1./32 \
  ::ffff:1.2.3.4./120 \
  010.1.1.1/24 \
  ::ffff:010.1.1.1/120 \
  1.2.3.4/024 \
  1.2.3.4/1234; do
  if valid_cidr_syntax "$cidr"; then fail "invalid CIDR accepted: $cidr"; fi
done
echo "PASS firewall CIDR validation"

HYPRLAND_INSTANCE_SIGNATURE=test-instance
XDG_CURRENT_DESKTOP=KDE
[[ $(virtual_monitor_backend) == hyprland ]] || fail "Hyprland should take precedence in its session"
unset HYPRLAND_INSTANCE_SIGNATURE
[[ $(virtual_monitor_backend) == kde ]] || fail "KDE session was not recognized"
XDG_CURRENT_DESKTOP=GNOME
unset KDE_FULL_SESSION
if virtual_monitor_backend >/dev/null 2>&1; then fail "unsupported desktop was accepted"; fi
echo "PASS virtual-monitor backend selection"

TEST_HOME=$(mktemp -d)
trap 'rm -rf -- "$TEST_HOME"' EXIT
HOME=$TEST_HOME
FLATPAK_ID=dev.lizardbyte.app.Sunshine
FLATPAK_UNIT=app-dev.lizardbyte.app.Sunshine.service
BIN_DIR="$TEST_HOME/bin"
mkdir -p "$HOME/.config/sunshine" "$BIN_DIR"

UNSUPPORTED_DISTRO=1
DISTRO=unsupported
ID=customlinux
PRETTY_NAME="Custom Linux"
XDG_CURRENT_DESKTOP=KDE
XDG_SESSION_TYPE=wayland
print_desktop_options() {
  printf '%s\n' "Desktop-specific options:" "Virtual Monitor: KDE Plasma (Wayland)"
}
choose() { REPLY=2; }
FLATPAK_SCOPE=""
install_flatpak() {
  case ${1:-} in
    system|user) FLATPAK_SCOPE=$1 ;;
    *) return 2 ;;
  esac
}
action_install > "$TEST_HOME/unsupported-install.log" 2>&1
[[ $FLATPAK_SCOPE == user ]] || fail "unsupported distro did not allow Flatpak installation"
grep -q 'not a supported distribution' "$TEST_HOME/unsupported-install.log" \
  || fail "unsupported distro warning was not shown"
grep -q 'Virtual Monitor: KDE Plasma' "$TEST_HOME/unsupported-install.log" \
  || fail "desktop-specific options were not shown"
if install_native >/dev/null 2>&1; then fail "native installation was allowed on unsupported distro"; fi
echo "PASS unsupported distro Flatpak options"
source "$ROOT/modules/common.sh"   # restore the real choose() after the scenario stub
source "$ROOT/modules/install.sh"
if action_install --bogus >/dev/null 2>&1; then fail "unknown install flag was accepted"; fi
action_install --bogus 2>"$TEST_HOME/install-bogus.log" || true
grep -q 'Unknown install option' "$TEST_HOME/install-bogus.log" \
  || fail "unknown install flag did not report the problem"
UNSUP_RC=0; action_install --bogus >/dev/null 2>&1 || UNSUP_RC=$?
(( UNSUP_RC == 2 )) || fail "unknown install flag returned $UNSUP_RC, expected 2"
UNSUPPORTED_DISTRO=0
DISTRO=debian

got=$(ID=ubuntu VERSION_ID=24.04 ubuntu_version)
[[ $got == 24.04 ]] || fail "ubuntu VERSION_ID passthrough failed ($got)"
got=$(ID=ubuntu VERSION_ID=22.04.4 UBUNTU_CODENAME=jammy ubuntu_version)
[[ $got == 22.04 ]] || fail "invalid VERSION_ID should fall back to codename ($got)"
got=$(ID=pop VERSION_ID=22.04.5 UBUNTU_CODENAME=jammy ubuntu_version)
[[ $got == 22.04 ]] || fail "derivative should use UBUNTU_CODENAME ($got)"
got=$(ID=pop VERSION_ID=24.10 UBUNTU_CODENAME=oracular ubuntu_version)
[[ $got == 24.10 ]] || fail "oracular mapping failed ($got)"
got=$(ID=pop VERSION_ID=25.10 UBUNTU_CODENAME=questing ubuntu_version)
[[ $got == 25.10 ]] || fail "questing mapping failed ($got)"
got=$(ID=pop VERSION_ID=26.04 UBUNTU_CODENAME=resolute ubuntu_version)
[[ $got == 26.04 ]] || fail "resolute mapping failed ($got)"
got=$(ID=pop VERSION_ID=26.10 UBUNTU_CODENAME=stonking ubuntu_version)
[[ $got == 26.10 ]] || fail "stonking mapping failed ($got)"
got=$(ID=ubuntu VERSION_ID=26.10 ubuntu_version)
[[ $got == 26.10 ]] || fail "Ubuntu 26.10 VERSION_ID passthrough failed ($got)"
got=$(ID=debian VERSION_ID=13 ubuntu_version)
[[ -z $got ]] || fail "non-Ubuntu should return empty ($got)"
echo "PASS Ubuntu release mapping"

FIREWALL_LOG="$TEST_HOME/firewall.log"
firewall-cmd() { :; }
systemctl() {
  # Only firewalld is active in this scenario; ufw must not trigger a sudo probe.
  [[ ${1:-} == is-active && ${3:-} == firewalld ]]
}
sudo() {
  [[ ${1:-} == firewall-cmd ]] && printf '%s\n' "$*" >> "$FIREWALL_LOG"
}
FIREWALL_ANSWER_INDEX=0
FIREWALL_ANSWERS=(no yes)
ask_yes_no() {
  local answer=${FIREWALL_ANSWERS[$FIREWALL_ANSWER_INDEX]}
  FIREWALL_ANSWER_INDEX=$((FIREWALL_ANSWER_INDEX + 1))
  [[ $answer == yes ]]
}
open_firewall <<< "" >/dev/null || fail "firewalld configuration failed"
grep -Fq -- '--add-port=47984/tcp' "$FIREWALL_LOG" || fail "firewalld TCP port was not added"
grep -Fq -- '--add-port=47998/udp' "$FIREWALL_LOG" || fail "firewalld UDP port was not added"
grep -Fq -- '--add-service=mdns' "$FIREWALL_LOG" || fail "firewalld mDNS service was not added"
grep -Fxq -- 'firewall-cmd --reload' "$FIREWALL_LOG" || fail "firewalld rules were not reloaded"
echo "PASS firewalld rule configuration"

: > "$FIREWALL_LOG"
FIREWALL_ANSWER_INDEX=0
FIREWALL_ANSWERS=(no yes)
open_firewall <<< "fd00::/64" >/dev/null || fail "IPv6 CIDR firewall configuration failed"
grep -Fq -- 'family="ipv6" source address="fd00::/64"' "$FIREWALL_LOG" \
  || fail "IPv6 CIDR was not applied to firewalld rules"
: > "$FIREWALL_LOG"
FIREWALL_ANSWER_INDEX=0
FIREWALL_ANSWERS=(no)
if open_firewall <<< "not-a-cidr" >/dev/null 2>&1; then fail "invalid firewall CIDR was accepted"; fi
[[ ! -s $FIREWALL_LOG ]] || fail "invalid firewall CIDR changed firewall rules"
echo "PASS firewall source restriction and invalid-input protection"

INSTALL_LOG="$TEST_HOME/flatpak.log"
# New scenario: install_flatpak calls systemctl heavily; the firewall mock
# above deliberately fails everything but the firewalld probe, so replace it.
systemctl() { return 0; }
flatpak() {
  printf '%s\n' "$*" >> "$INSTALL_LOG"
  if [[ ${1:-} == install ]]; then
    mkdir -p "$HOME/.var/app/$FLATPAK_ID/config/sunshine"
    touch "$HOME/.var/app/$FLATPAK_ID/config/sunshine/sunshine.conf"
  fi
}
flatpak_installed() { return 0; }
IMMUTABLE=0
if install_flatpak invalid >/dev/null 2>&1; then fail "invalid Flatpak scope was accepted"; fi
install_flatpak user >/dev/null || fail "Flatpak user installation failed"
grep -Fxq "remote-add --if-not-exists --user flathub https://dl.flathub.org/repo/flathub.flatpakrepo" "$INSTALL_LOG" \
  || fail "Flatpak remote did not use the requested user scope"
grep -Fxq "install --user -y --or-update flathub $FLATPAK_ID" "$INSTALL_LOG" \
  || fail "Flatpak install did not use the requested user scope"
grep -Fxq "run --user --command=additional-install.sh $FLATPAK_ID" "$INSTALL_LOG" \
  || fail "Flatpak additional installer did not use the requested user scope"
echo "PASS Flatpak installation scope"

DISTRO=opensuse-microos
if install_native >/dev/null 2>&1; then fail "native installation claimed success on a distro without a native method"; fi
DISTRO=debian

printf '{"apps":[{"name":"Virtual Monitor"},{"name":"Virtual Monitor (Hyprland)"}]}\n' \
  > "$HOME/.config/sunshine/apps.json"
hypr_vmon_state_dir() { printf '%s\n' "$HOME/.config/sunshine-setup/hyprland-vmon"; }
remove_vmon_hyprland() { printf 'hyprland ' >> "$TEST_HOME/removed"; }
remove_vmon_kde() { printf 'kde ' >> "$TEST_HOME/removed"; }
remove_vmon
[[ $(<"$TEST_HOME/removed") == 'hyprland kde ' ]] || fail "removal did not clean configured backends outside a desktop session"
echo "PASS inactive-session backend removal"

printf '{"env":{}}\n' > "$HOME/.config/sunshine/apps.json"
if vmon_app_configured "$HOME/.config/sunshine/apps.json" "Virtual Monitor"; then
  fail "apps-less config was treated as containing the app"
else
  rc=$?
fi
[[ $rc -eq 1 ]] || fail "apps-less config should be inspectable but missing the app (rc=$rc)"
echo "PASS apps-less Sunshine config handling"

TEMP_FILES=()
XDG_CURRENT_DESKTOP=KDE
XDG_SESSION_TYPE=wayland
configure_startup_dropin sunshine.service 5 >/dev/null
DROPIN="$HOME/.config/systemd/user/sunshine.service.d/00-sunshine-setup.conf"
grep -q '^ExecStartPre=/bin/sleep 5$' "$DROPIN" || fail "native service delay was not written"
configure_startup_dropin app-dev.lizardbyte.app.Sunshine.service 0 >/dev/null
! grep -q '^ExecStartPre=' "$HOME/.config/systemd/user/app-dev.lizardbyte.app.Sunshine.service.d/00-sunshine-setup.conf" \
  || fail "Flatpak service unexpectedly received a startup delay"
fix_503 >/dev/null
grep -Fxq 'KWIN_WAYLAND_NO_PERMISSION_CHECKS=1' "$HOME/.config/environment.d/98-sunshine-setup-503.conf" \
  || fail "Error 503 setting was not created"
printf 'OTHER=1\nKWIN_WAYLAND_NO_PERMISSION_CHECKS=1\nOTHER=2\n' \
  > "$HOME/.config/environment.d/98-sunshine-setup-503.conf"
reset_503 >/dev/null
[[ $(<"$HOME/.config/environment.d/98-sunshine-setup-503.conf") == $'OTHER=1\nOTHER=2' ]] \
  || fail "Error 503 reset did not preserve unrelated settings"
echo "PASS service drop-ins and Error 503 settings"

if (( EUID != 0 )); then
  # reset_503 keeps the file (it holds foreign settings); remove it so the
  # next fix_503 run takes the create path and hits the write guard.
  rm -f "$HOME/.config/environment.d/98-sunshine-setup-503.conf"
  chmod 500 "$HOME/.config/environment.d"
  if fix_503 >"$TEST_HOME/503-ro.log" 2>&1; then
    chmod 700 "$HOME/.config/environment.d"
    fail "Error 503 fix wrote into an unwritable directory"
  fi
  chmod 700 "$HOME/.config/environment.d"
  grep -q 'Could not write' "$TEST_HOME/503-ro.log" \
    || fail "Error 503 fix did not report the write failure"
  echo "PASS Error 503 unwritable-directory protection"
fi

# fix_503 must refuse to overwrite a pre-existing file that lacks the setting.
printf 'OTHER=1\n' > "$HOME/.config/environment.d/98-sunshine-setup-503.conf"
if fix_503 >"$TEST_HOME/503-exists.log" 2>&1; then fail "fix_503 overwrote a pre-existing config file"; fi
grep -q 'Refusing to overwrite' "$TEST_HOME/503-exists.log" \
  || fail "fix_503 did not report the refusal"
grep -Fxq 'OTHER=1' "$HOME/.config/environment.d/98-sunshine-setup-503.conf" \
  || fail "fix_503 modified the file it refused to overwrite"

# reset_503 must clean the current and the legacy file in one run.
printf 'KWIN_WAYLAND_NO_PERMISSION_CHECKS=1\n' > "$HOME/.config/environment.d/98-kwin-no-permission-checks.conf"
printf 'KEEP=1\nKWIN_WAYLAND_NO_PERMISSION_CHECKS=1\n' > "$HOME/.config/environment.d/98-sunshine-setup-503.conf"
reset_503 >/dev/null
[[ ! -e "$HOME/.config/environment.d/98-kwin-no-permission-checks.conf" ]] \
  || fail "legacy file holding only the setting was not removed"
[[ $(<"$HOME/.config/environment.d/98-sunshine-setup-503.conf") == 'KEEP=1' ]] \
  || fail "reset_503 did not clean both current and legacy files"
echo "PASS Error 503 overwrite protection and legacy reset"

SYSTEMCTL_LOG=$(mktemp)
systemctl() {
  printf '%s\n' "$*" >> "$SYSTEMCTL_LOG"
  [[ ${SYSTEMCTL_FAIL:-} != "${2:-}" ]]
}
journalctl() { return 0; }
native_installed() { return 0; }
native_unit() { printf '%s\n' sunshine.service; }
flatpak_installed() { return 1; }
service_action restart --native >/dev/null || fail "service restart action failed"
[[ $(<"$SYSTEMCTL_LOG") == '--user restart sunshine.service' ]] || fail "service action arguments changed"
if service_action invalid --native >/dev/null 2>&1; then fail "invalid service action was accepted"; fi
SYSTEMCTL_FAIL=restart
if service_action restart --native >/dev/null 2>&1; then fail "service failure was ignored"; fi
if repair_startup --invalid >/dev/null 2>&1; then fail "invalid repair scope was accepted"; fi
rm -f -- "$SYSTEMCTL_LOG"
echo "PASS service action validation"

systemctl() { return 0; }
menu_err=$(printf '08\n10\n' | LC_ALL=C manage_service 2>&1 >/dev/null) \
  || fail "service menu rejected leading-zero choice"
[[ $menu_err != *'too great for base'* ]] || fail "leading-zero menu choice caused an arithmetic error"
echo "PASS service menu leading-zero input"

if manage_service --bogus >/dev/null 2>&1; then fail "unknown service scope accepted"; fi
if manage_service --flatpak >/dev/null 2>&1; then fail "flatpak scope was allowed without a flatpak install"; fi
printf '10\n' | manage_service --native >/dev/null 2>&1 || fail "service --native menu did not open"
echo "PASS service scope selection"

bash "$ROOT/tests/kde.sh"
bash "$ROOT/tests/hyprland.sh"

# End-to-end CLI checks run against the real interpreter; skip when uid 0
# (container jobs) because chmod-based scenarios cannot fail closed there.
if [[ $EUID -ne 0 ]]; then
  bash "$ROOT/tests/cli-smoke.sh"
fi
