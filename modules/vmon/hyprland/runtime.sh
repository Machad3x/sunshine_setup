#!/usr/bin/env bash
# Shared helpers for the installed Hyprland virtual-monitor hooks.

# Export a valid HYPRLAND_INSTANCE_SIGNATURE for the running compositor.
# The value inherited by the Sunshine service can be missing or stale (for
# example after a compositor restart), so fall back to the live socket.
hypr_vmon_resolve_session() {
  local runtime="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}" sig sock
  export XDG_RUNTIME_DIR="$runtime"

  if [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} && -S "$runtime/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket.sock" ]]; then
    return 0
  fi

  for sock in "$runtime"/hypr/*/.socket.sock; do
    [[ -S $sock ]] || continue
    sig=${sock#"$runtime"/hypr/}
    sig=${sig%/.socket.sock}
    export HYPRLAND_INSTANCE_SIGNATURE="$sig"
    return 0
  done

  # No socket found (for example a test harness): leave the environment alone
  # and let hyprctl report its own connection error.
  return 0
}

hypr_vmon_capture_physical_monitors() {
  local name=$1 json
  json=$(hyprctl monitors -j) || {
    echo "Could not read Hyprland monitor state." >&2
    return 1
  }
  jq -ce --arg name "$name" '
    if type != "array" then error("monitor list is not an array")
    else [
      .[]
      | select(.name != $name)
      | select(((.description // "") | ascii_downcase | test("headless|virtual")) | not)
      | select((.name | ascii_upcase | test("^(HEADLESS|WL|VIRTUAL)-")) | not)
      | {
          name,
          width,
          height,
          refreshRate,
          x,
          y,
          scale,
          transform: (.transform // 0)
        }
    ]
    end
  ' <<< "$json"
}

hypr_vmon_output_is_active() {
  local name=$1 json
  json=$(hyprctl monitors -j) || {
    echo "Could not read Hyprland monitor state while checking $name." >&2
    return 2
  }
  jq -e 'type == "array"' <<< "$json" >/dev/null || {
    echo "Hyprland returned an invalid monitor list while checking $name." >&2
    return 2
  }
  jq -e --arg name "$name" 'any(.[]; .name == $name)' <<< "$json" >/dev/null
}

hypr_vmon_wait_for_output_disabled() {
  local name=$1 attempt status
  for ((attempt = 0; attempt < 20; attempt++)); do
    if hypr_vmon_output_is_active "$name"; then
      sleep 0.1
      continue
    else
      status=$?
    fi
    (( status == 1 )) && return 0
    return 1
  done
  echo "Hyprland did not disable the physical output $name." >&2
  return 1
}

hypr_vmon_wait_for_output_active() {
  local name=$1 attempt status
  for ((attempt = 0; attempt < 20; attempt++)); do
    if hypr_vmon_output_is_active "$name"; then
      return 0
    else
      status=$?
    fi
    (( status == 1 )) && sleep 0.1 && continue
    return 1
  done
  echo "Hyprland did not restore the physical output $name." >&2
  return 1
}

hypr_vmon_set_monitor() {
  local name=$1 mode=$2 position=$3 scale=$4 transform=$5 result command
  if [[ $mode == disable ]]; then
    printf -v command 'hl.monitor({ output = "%s", disabled = true })' "$name"
  else
    printf -v command \
      'hl.monitor({ output = "%s", mode = "%s", position = "%s", scale = %s, transform = %s, disabled = false })' \
      "$name" "$mode" "$position" "$scale" "$transform"
  fi

  if result=$(hyprctl eval "$command" 2>/dev/null) && [[ $result == ok ]]; then
    return 0
  fi

  if [[ $mode == disable ]]; then
    result=$(hyprctl keyword monitor "$name,disable" 2>/dev/null) || return 1
  else
    result=$(hyprctl keyword monitor "$name,$mode,$position,$scale,$transform" 2>/dev/null) || return 1
  fi
  if [[ $result == ok ]]; then
    return 0
  fi
  return 1
}

hypr_vmon_apply_physical_monitors() {
  local action=$1 state_file=$2 monitor name mode position scale transform failed=0
  local -a monitors fields

  [[ $action == disable || $action == restore ]] || {
    echo "Invalid Hyprland physical-monitor action: $action" >&2
    return 1
  }
  jq -e '
    type == "array" and all(.[];
      (.name | type == "string") and
      (.width | type == "number") and
      (.height | type == "number") and
      (.refreshRate | type == "number") and
      (.x | type == "number") and
      (.y | type == "number") and
      (.scale | type == "number") and
      (.transform | type == "number")
    )
  ' "$state_file" >/dev/null || {
    echo "Invalid Hyprland physical-monitor state in $state_file." >&2
    return 1
  }

  mapfile -t monitors < <(jq -c '.[]' "$state_file")
  for monitor in "${monitors[@]}"; do
    mapfile -t fields < <(
      jq -r '[.name, "\(.width)x\(.height)@\(.refreshRate)", "\(.x)x\(.y)", (.scale | tostring), (.transform | tostring)][]' \
        <<< "$monitor"
    )
    name=${fields[0]}
    if [[ $action == disable ]]; then
      if ! hypr_vmon_set_monitor "$name" disable "${fields[2]}" "${fields[3]}" "${fields[4]}"; then
        echo "Could not disable the Hyprland output $name." >&2
        return 1
      fi
      hypr_vmon_wait_for_output_disabled "$name" || return 1
      continue
    fi

    mode=${fields[1]}
    position=${fields[2]}
    scale=${fields[3]}
    transform=${fields[4]}
    if ! hypr_vmon_set_monitor "$name" "$mode" "$position" "$scale" "$transform"; then
      echo "Could not restore the Hyprland output $name." >&2
      failed=1
      continue
    fi
    hypr_vmon_wait_for_output_active "$name" || {
      echo "Could not restore the Hyprland output $name." >&2
      failed=1
    }
  done
  (( failed == 0 ))
}
