# shellcheck shell=bash
# Shared globals are initialized by sunshine-setup.sh before this module is sourced.
# shellcheck disable=SC2154

# ---------- Keyboard layout / Sunshine UI locale ----------
# Sunshine no longer has a `keyboard_language` option (it was removed
# upstream): key events reach the host as physical keycodes, and the
# characters they produce depend on the *session* keyboard layout of the
# desktop (KWin/Xorg/Hyprland). Sunshine's `locale` option only translates
# the Web UI. This module keeps both in sync with the user's real keyboard.

# Values accepted by sunshine.conf's `locale` option.
SUNSHINE_LOCALES=(bg cs de en en_GB en_US es fr hu it ja ko pl pt pt_BR ru sv tr uk vi zh zh_TW)

# XKB layouts offered by the picker, as "<code>  <label>" pairs.
KEYBOARD_LAYOUTS=(
  "br  Brazilian (ABNT2)"
  "us  English (US)"
  "gb  English (UK)"
  "de  German"
  "at  German (Austria)"
  "ch  German (Swiss)"
  "es  Spanish"
  "fr  French"
  "be  French (Belgian)"
  "it  Italian"
  "pt  Portuguese"
  "pl  Polish"
  "cz  Czech"
  "hu  Hungarian"
  "sv  Swedish"
  "ru  Russian"
  "ua  Ukrainian"
  "tr  Turkish"
  "bg  Bulgarian"
  "ja  Japanese"
  "ko  Korean"
  "zh  Chinese"
  "tw  Chinese (Traditional)"
)

is_sunshine_locale() {
  local candidate=$1 lc
  for lc in "${SUNSHINE_LOCALES[@]}"; do
    [[ $lc == "$candidate" ]] && return 0
  done
  return 1
}

# Sunshine UI locale that matches an XKB layout name. Returns 1 for layouts
# Sunshine has no locale for (the UI language is then left unchanged).
locale_for_layout() {
  case "${1:-}" in
    br)        echo pt_BR ;;
    pt)        echo pt ;;
    de|at|ch)  echo de ;;
    fr|be)     echo fr ;;
    it)        echo it ;;
    es)        echo es ;;
    ja)        echo ja ;;
    ko)        echo ko ;;
    pl)        echo pl ;;
    ru|by)     echo ru ;;
    se)        echo sv ;;
    cz)        echo cs ;;
    hu)        echo hu ;;
    tr)        echo tr ;;
    ua)        echo uk ;;
    bg)        echo bg ;;
    vn)        echo vi ;;
    cn|zh)     echo zh ;;
    tw)        echo zh_TW ;;
    gb)        echo en_GB ;;
    us)        echo en ;;
    *)         return 1 ;;
  esac
}

# Paths of every Sunshine sunshine.conf the script may touch (native + Flatpak).
sunshine_conf_paths() {
  printf '%s\n' "$HOME/.config/sunshine/sunshine.conf" \
    "$HOME/.var/app/$FLATPAK_ID/config/sunshine/sunshine.conf"
}

# Prints the active (uncommented) value of a sunshine.conf key. The first
# assignment wins, mirroring Sunshine's own parser. Returns 1 when unset.
read_conf_value() {
  local conf=$1 key=$2 line value
  [[ -f $conf ]] || return 1
  line=$(grep -E "^[[:space:]]*${key}[[:space:]]*=" "$conf" | head -n 1) || true
  [[ -n ${line:-} ]] || return 1
  value=${line#*=}
  value=${value%%#*}
  value=${value#"${value%%[![:space:]]*}"}
  value=${value%"${value##*[![:space:]]}"}
  [[ -n $value ]] || return 1
  printf '%s\n' "$value"
}

# Writes "key = value" into a sunshine.conf: every existing active assignment
# is replaced by a single new line (Sunshine only honors the first value),
# the key is appended when absent, and comments/other lines are preserved.
write_conf_value() {
  local conf=$1 key=$2 value=$3 tmp line found=0
  if [[ ! -f $conf ]]; then
    mkdir -p "${conf%/*}" || return 1
    printf '%s = %s\n' "$key" "$value" > "$conf"
    return $?
  fi
  tmp=$(mktemp "${conf}.sunshine-setup.XXXXXX") || return 1
  TEMP_FILES+=("$tmp")
  while IFS= read -r line || [[ -n $line ]]; do
    if [[ $line =~ ^[[:space:]]*${key}[[:space:]]*= ]]; then
      if (( ! found )); then
        printf '%s = %s\n' "$key" "$value" >> "$tmp"
        found=1
      fi
    else
      printf '%s\n' "$line" >> "$tmp"
    fi
  done < "$conf"
  (( found )) || printf '%s = %s\n' "$key" "$value" >> "$tmp"
  if ! chmod --reference="$conf" "$tmp" || ! mv -f -- "$tmp" "$conf"; then
    rm -f -- "$tmp"
    echo "${red}Could not update $conf.${normal}" >&2
    return 1
  fi
}

# Reads a key from the [Layout] section of KDE's kxkbrc.
kxkb_get() {
  local key=$1 val
  [[ -f $HOME/.config/kxkbrc ]] || return 1
  val=$(awk -v key="$key" '
    /^[ \t]*\[/     { inl = ($0 ~ /^[ \t]*\[Layout\]/) }
    inl && $0 ~ "^[ \t]*" key "=" { sub("^[ \t]*" key "=", ""); print; exit }
  ' "$HOME/.config/kxkbrc")
  [[ -n $val ]] || return 1
  printf '%s\n' "$val"
}

# The keyboard layout the user configured on this machine. Priority: the DE's
# own session settings, then X11/console configuration files. Prints the
# first layout of a comma-separated list; returns 1 when undetectable.
system_keyboard_layout() {
  local v dir
  if [[ -f $HOME/.config/kxkbrc ]] \
      && [[ $(kxkb_get Enabled || true) == true ]]; then
    v=$(kxkb_get LayoutList || true)
    v=${v%%,*}
    [[ -n $v ]] && { printf '%s\n' "$v"; return 0; }
  fi
  if command -v gsettings >/dev/null 2>&1; then
    v=$(gsettings get org.gnome.desktop.input-sources sources 2>/dev/null \
        | sed -nE "s/.*\('xkb', ?'([^']+)'.*/\1/p" | head -n 1) || true
    [[ -n ${v:-} ]] && { printf '%s\n' "$v"; return 0; }
  fi
  if [[ -r /etc/default/keyboard ]]; then
    v=$(sed -nE 's/^[[:space:]]*XKBLAYOUT="([^",[:space:]]+).*/\1/p' /etc/default/keyboard | head -n 1) || true
    [[ -n ${v:-} ]] && { printf '%s\n' "$v"; return 0; }
  fi
  if [[ -r /etc/vconsole.conf ]]; then
    v=$(sed -nE 's/^[[:space:]]*XKBLAYOUT="?([^",[:space:]]+).*/\1/p' /etc/vconsole.conf | head -n 1) || true
    [[ -n ${v:-} ]] && { printf '%s\n' "$v"; return 0; }
    # Arch console keymaps start with the layout code: br-abnt2 -> br.
    v=$(sed -nE 's/^[[:space:]]*KEYMAP="?([a-z]{2})(-[a-z0-9]+)*"?[[:space:]]*$/\1/p' /etc/vconsole.conf | head -n 1) || true
    [[ $v == uk ]] && v=gb
    [[ -n ${v:-} ]] && { printf '%s\n' "$v"; return 0; }
  fi
  for dir in "$HOME/.config/hypr" "$HOME/.config/hyprland"; do
    if [[ -f $dir/hyprland.conf ]]; then
      v=$(sed -nE 's/^[[:space:]]*kb_layout[[:space:]]*=[[:space:]]*([A-Za-z0-9_-]+).*/\1/p' "$dir/hyprland.conf" | head -n 1) || true
      [[ -n ${v:-} ]] && { printf '%s\n' "$v"; return 0; }
    fi
  done
  return 1
}

# The layout KWin actually types with, asked from the compositor itself.
# On KDE/Wayland setxkbmap only reflects the XWayland mirror, which KWin may
# leave on the US default while Wayland devices use the configured layout.
kde_active_layout() {
  local list idx want
  local -a strs=()
  list=$(busctl --user call org.kde.KWin /Layouts org.kde.KeyboardLayouts getLayoutsList 2>/dev/null) || return 1
  [[ ${list:0:6} == 'a(sss)' ]] || return 1
  idx=$(busctl --user call org.kde.KWin /Layouts org.kde.KeyboardLayouts getLayout 2>/dev/null) || return 1
  idx=${idx//[!0-9]/}
  [[ -n $idx ]] || idx=0
  while IFS= read -r s; do strs+=("$s"); done < <(printf '%s\n' "$list" | grep -oE '"[^"]*"')
  want=$((idx * 3))
  (( want < ${#strs[@]} )) || return 1
  printf '%s\n' "${strs[$want]//\"/}"
}

# The layout the running session actually uses to produce characters, when it
# can be observed (KWin D-Bus on KDE Wayland; X11 tools elsewhere — XWayland
# mirrors the compositor's layout outside KDE too).
effective_xkb_layout() {
  local v
  if [[ ${XDG_CURRENT_DESKTOP:-} == *KDE* ]] && v=$(kde_active_layout); then
    printf '%s\n' "$v"
    return 0
  fi
  if command -v setxkbmap >/dev/null 2>&1; then
    v=$(setxkbmap -query 2>/dev/null | awk '/^layout:/ { print $2 }') || true
    [[ -n ${v:-} ]] && { printf '%s\n' "$v"; return 0; }
  fi
  command -v localectl >/dev/null 2>&1 || return 1
  v=$(localectl status 2>/dev/null | sed -nE 's/.*X11 Layout:[[:space:]]*([A-Za-z0-9_-]+).*/\1/p' | head -n 1) || true
  [[ -n ${v:-} ]] && { printf '%s\n' "$v"; return 0; }
  return 1
}

# Sets the KDE session keyboard layout through kxkbrc, the file behind
# System Settings > Input Devices > Keyboard > Layouts. kwriteconfig keeps
# the rest of the file intact; without kde-cli-tools a minimal file is only
# created when none exists (an existing one is never rewritten blind).
kde_set_layout() {
  local layout=$1 variant=${2:-} tool="" tc dbus_tool="" f="$HOME/.config/kxkbrc"
  for tc in kwriteconfig6 kwriteconfig5 kwriteconfig; do
    command -v "$tc" >/dev/null 2>&1 && { tool=$tc; break; }
  done
  if [[ -n $tool ]]; then
    "$tool" --file kxkbrc --group Layout --key Enabled true \
      && "$tool" --file kxkbrc --group Layout --key LayoutList "$layout" \
      && "$tool" --file kxkbrc --group Layout --key VariantList "$variant" \
      && "$tool" --file kxkbrc --group Layout --key ResetOldOptions true || {
        echo "${red}Could not update $f.${normal}" >&2
        return 1
      }
  elif [[ -e $f ]]; then
    echo "${red}Refusing to rewrite $f without kwriteconfig.${normal}" >&2
    echo "${dim}Install 'kde-cli-tools' or change the layout in System Settings.${normal}" >&2
    return 1
  else
    mkdir -p "${f%/*}" || return 1
    printf '[Layout]\nEnabled=true\nLayoutList=%s\nVariantList=%s\nResetOldOptions=true\n' \
      "$layout" "$variant" > "$f" || return 1
  fi
  # Ask KWin to re-read kxkbrc; the change lands on next login otherwise.
  for tc in qdbus6 qdbus-qt6 qdbus qdbus5; do
    command -v "$tc" >/dev/null 2>&1 && { dbus_tool=$tc; break; }
  done
  if [[ -n $dbus_tool ]]; then
    "$dbus_tool" org.kde.KWin /KWin reconfigure >/dev/null 2>&1 || true
  fi
  echo "  ${green}KDE session layout set to '$layout'.${normal}"
  echo "  ${dim}If the keyboard does not change immediately, log out and back in.${normal}"
}

# Guidance for desktops whose layout this script does not edit automatically.
layout_hint_for_desktop() {
  local layout=$1
  if [[ ${XDG_SESSION_TYPE:-} == wayland ]] && grep -q Hyprland <<<"${XDG_CURRENT_DESKTOP:-}"; then
    echo "  ${dim}In hyprland.conf set: input { kb_layout = $layout }${normal}"
  else
    echo "  ${dim}Set the keyboard layout to '$layout' in your desktop's${normal}"
    echo "  ${dim}keyboard settings (e.g. GNOME Tweaks > Keyboard > Input Sources).${normal}"
  fi
}

# Writes `locale = <code>` into every sunshine.conf that exists (native and
# Flatpak). When Sunshine is installed but never started, the native file is
# created so the setting is already in place on first launch.
set_sunshine_locale() {
  local code=${1:-} conf written=0
  if ! is_sunshine_locale "$code"; then
    echo "${red}Unsupported Sunshine locale: '${code}'${normal}" >&2
    echo "${dim}Choices: ${SUNSHINE_LOCALES[*]}${normal}" >&2
    return 1
  fi
  while IFS= read -r conf; do
    [[ -d ${conf%/*} ]] || continue
    write_conf_value "$conf" locale "$code" || return 1
    echo "  ${green}locale = $code${normal}  ${dim}in $conf${normal}"
    written=1
  done < <(sunshine_conf_paths)
  (( written )) && return 0
  if native_installed || flatpak_installed; then
    conf="$HOME/.config/sunshine/sunshine.conf"
    write_conf_value "$conf" locale "$code" || return 1
    echo "  ${green}locale = $code${normal}  ${dim}created in $conf${normal}"
    return 0
  fi
  echo "${red}Sunshine is not installed.${normal} Install it first (menu option 1, or the 'install' command)." >&2
  return 1
}

# Restarts Sunshine only when it is running, so the new locale takes effect.
restart_active_sunshine() {
  local -a units=()
  local u
  native_installed && systemctl --user is-active --quiet "$(native_unit)" 2>/dev/null \
    && units+=("$(native_unit)")
  flatpak_installed && systemctl --user is-active --quiet "$FLATPAK_UNIT" 2>/dev/null \
    && units+=("$FLATPAK_UNIT")
  if (( ! ${#units[@]} )); then
    echo "  ${dim}Sunshine is not running; the new setting applies on next start.${normal}"
    return 0
  fi
  if ! ask_yes_no "Restart Sunshine now to apply the changes?"; then
    echo "  ${dim}Skipped. Restart later from the service menu (option 5).${normal}"
    return 0
  fi
  for u in "${units[@]}"; do
    if systemctl --user restart "$u"; then
      echo "  ${green}Restarted${normal} $u"
    else
      echo "  ${red}Failed to restart $u.${normal}" >&2
    fi
  done
}

# Shared tail of the detected/picked flows: fix the session layout, then sync
# Sunshine's UI locale with the same keyboard.
apply_keyboard_layout() {
  local layout=$1 locale_code
  echo
  echo "  ${bold}Applying keyboard layout '$layout'${normal}"
  if [[ ${XDG_CURRENT_DESKTOP:-} == *KDE* ]]; then
    kde_set_layout "$layout" || return 1
  else
    echo "  ${yellow}Automatic session-layout changes support KDE Plasma${normal}"
    echo "  ${dim}(current desktop: ${XDG_CURRENT_DESKTOP:-unknown}).${normal}"
    layout_hint_for_desktop "$layout"
  fi
  if locale_code=$(locale_for_layout "$layout"); then
    set_sunshine_locale "$locale_code" || return 1
    restart_active_sunshine
  else
    echo "  ${dim}No Sunshine UI locale matches '$layout'; locale left unchanged.${normal}"
  fi
}

keyboard_apply_detected() {
  local layout
  if ! layout=$(system_keyboard_layout); then
    echo "  ${red}Could not detect a keyboard layout on this system.${normal}" >&2
    echo "  ${dim}Use the keyboard menu to pick the layout manually.${normal}"
    return 1
  fi
  apply_keyboard_layout "$layout"
}

keyboard_pick_layout() {
  local sel code label
  choose "Keyboard layout" "${KEYBOARD_LAYOUTS[@]}" || return 0
  sel=${KEYBOARD_LAYOUTS[$((REPLY - 1))]}
  code=${sel%%[[:space:]]*}
  label=${sel#*  }
  echo "  Selected: $label"
  apply_keyboard_layout "$code"
}

keyboard_pick_locale() {
  local code
  choose "Sunshine UI locale" "${SUNSHINE_LOCALES[@]}" || return 0
  code=${SUNSHINE_LOCALES[$((REPLY - 1))]}
  set_sunshine_locale "$code" || return 0
  restart_active_sunshine
}

print_keyboard_status() {
  local conf configured effective loc
  configured=$(system_keyboard_layout) || configured=""
  effective=$(effective_xkb_layout) || effective=""
  echo "  ${dim}Configured keyboard:${normal} ${configured:-unknown}"
  if [[ -n $effective && $effective != "$configured" ]]; then
    echo "  ${dim}Session layout:${normal}      ${yellow}$effective${normal}"
    if [[ -n $configured ]]; then
      echo "  ${red}The session types with '$effective' while the system says '$configured'.${normal}"
    fi
  elif [[ -n $effective ]]; then
    echo "  ${dim}Session layout:${normal}      ${green}$effective${normal}"
  fi
  while IFS= read -r conf; do
    [[ -f $conf ]] || continue
    loc=$(read_conf_value "$conf" locale) || loc="en (default)"
    echo "  ${dim}Sunshine locale:${normal}      $loc  ${dim}$conf${normal}"
  done < <(sunshine_conf_paths)
  echo
  echo "  ${dim}Sunshine sends physical keycodes: the characters follow the session${normal}"
  echo "  ${dim}layout. 'locale' only translates the Web UI.${normal}"
  if [[ ${effective:-} == br || ${configured:-} == br ]]; then
    echo "  ${yellow}ABNT2 note:${normal} the dedicated ${bold}/ ?${normal} key (VK_ABNT_C1) is not sent by"
    echo "  ${dim}Moonlight for Windows and not mapped by Sunshine's Linux backend yet;${normal}"
    echo "  ${dim}on ABNT2 layouts AltGr+Q = / and AltGr+W = ?.${normal}"
  fi
}

keyboard_menu() {
  local choice
  while true; do
    echo
    echo "  ${bold}Keyboard language${normal}"
    print_keyboard_status
    echo
    printf "  ${cyan}1${normal})  Use my current keyboard layout\n"
    printf "  ${cyan}2${normal})  Choose the keyboard layout\n"
    printf "  ${cyan}3${normal})  Choose the Sunshine UI language only\n"
    printf "  ${cyan}4${normal})  Back\n\n"
    printf "  ${bold}Select [1-4]:${normal} "
    if ! read -r choice; then echo; return 0; fi
    echo
    case "$choice" in
      1) keyboard_apply_detected || true ;;
      2) keyboard_pick_layout || true ;;
      3) keyboard_pick_locale || true ;;
      4|q|Q|back) return 0 ;;
      "") continue ;;
      *) printf "  ${red}Invalid option '%s'.${normal}\n" "$choice" ;;
    esac
  done
}
