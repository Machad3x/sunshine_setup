# shellcheck shell=bash
# Shared helpers for the Hyprland backend.
# shellcheck disable=SC2154

hypr_vmon_state_dir() {
  printf '%s\n' "$HOME/.config/sunshine-setup/hyprland-vmon"
}

hypr_vmon_native_config() {
  printf '%s\n' "$HOME/.config/sunshine/sunshine.conf"
}

hypr_vmon_flatpak_config() {
  printf '%s\n' "$HOME/.var/app/$FLATPAK_ID/config/sunshine/sunshine.conf"
}

hypr_vmon_prepare_config() {
  local conf=$1 state_dir tmp saved_conf
  state_dir=$(hypr_vmon_state_dir)
  mkdir -p "$state_dir"
  chmod 700 "$state_dir"

  if [[ -f $state_dir/config-path ]]; then
    IFS= read -r saved_conf < "$state_dir/config-path" || return 1
    if [[ $saved_conf != "$conf" ]]; then
      echo "Hyprland virtual-monitor backup belongs to a different Sunshine config: $saved_conf" >&2
      return 1
    fi
  else
    if [[ -e $state_dir/capture.original || -e $state_dir/output-name.original ]]; then
      echo "Incomplete Hyprland virtual-monitor backup state in $state_dir." >&2
      return 1
    fi
    awk '/^[[:space:]]*capture[[:space:]]*(=|$)/' "$conf" > "$state_dir/capture.original" || return 1
    awk '/^[[:space:]]*output_name[[:space:]]*(=|$)/' "$conf" > "$state_dir/output-name.original" || return 1
    printf '%s\n' "$conf" > "$state_dir/config-path"
  fi

  tmp=$(mktemp "${conf}.sunshine-vmon.XXXXXX") || return 1
  if ! sed -E '/^[[:space:]]*(capture|output_name)[[:space:]]*(=|$)/d' "$conf" > "$tmp" \
      || ! { if [[ -s $tmp ]] && [[ $(tail -c1 "$tmp" | wc -l) -eq 0 ]]; then printf '\n' >> "$tmp"; fi; } \
      || ! printf 'capture = wlr\noutput_name = sunshine-vmon\n' >> "$tmp" \
      || ! chmod --reference="$conf" "$tmp" \
      || ! mv "$tmp" "$conf"; then
    rm -f -- "$tmp"
    return 1
  fi
}

hypr_vmon_restore_config() {
  local state_dir conf tmp original
  state_dir=$(hypr_vmon_state_dir)
  [[ -f $state_dir/config-path ]] || return 0
  [[ -f $state_dir/capture.original && -f $state_dir/output-name.original ]] || {
    echo "Hyprland virtual-monitor config backup is incomplete in $state_dir." >&2
    return 1
  }
  IFS= read -r conf < "$state_dir/config-path" || return 1
  case "$conf" in
    "$(hypr_vmon_native_config)"|"$(hypr_vmon_flatpak_config)") ;;
    *)
      echo "Refusing to restore an unexpected Sunshine config path: $conf" >&2
      return 1
      ;;
  esac
  [[ -f $conf ]] || return 0

  tmp=$(mktemp "${conf}.sunshine-vmon.XXXXXX") || return 1
  if ! sed -E '/^[[:space:]]*(capture|output_name)[[:space:]]*(=|$)/d' "$conf" > "$tmp"; then
    rm -f -- "$tmp"
    return 1
  fi
  for original in "$state_dir/capture.original" "$state_dir/output-name.original"; do
    if [[ -s $original && -s $tmp ]] && [[ $(tail -c1 "$tmp" | wc -l) -eq 0 ]]; then
      printf '\n' >> "$tmp" || { rm -f -- "$tmp"; return 1; }
    fi
    if ! cat "$original" >> "$tmp"; then
      rm -f -- "$tmp"
      return 1
    fi
  done
  if ! chmod --reference="$conf" "$tmp" || ! mv "$tmp" "$conf"; then
    rm -f -- "$tmp"
    return 1
  fi

  rm -f -- "$state_dir/config-path" "$state_dir/capture.original" "$state_dir/output-name.original"
  rmdir "$state_dir" 2>/dev/null || true
}
