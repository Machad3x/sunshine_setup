#!/usr/bin/env bash
# Shared helpers for the installed Hyprland virtual-monitor hooks.

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

hypr_vmon_apply_physical_monitors() {
  local action=$1 state_file=$2 monitor name mode position scale transform failed=0 result
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
      if ! result=$(hyprctl keyword monitor "$name,disable") || [[ $result != ok ]]; then
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
    if ! hyprctl keyword monitor "$name,$mode,$position,$scale,$transform" >/dev/null; then
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
