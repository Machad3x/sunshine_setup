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
      | select((.description // "") != "")
      | select(((.description // "") | ascii_downcase | test("headless|virtual")) | not)
      | select((.name | ascii_upcase | test("^(HEADLESS|WL)-")) | not)
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
      if ! hyprctl keyword monitor "$name,disable" >/dev/null; then
        echo "Could not disable the Hyprland output $name." >&2
        return 1
      fi
      continue
    fi

    mode=${fields[1]}
    position=${fields[2]}
    scale=${fields[3]}
    transform=${fields[4]}
    if ! hyprctl keyword monitor "$name,$mode,$position,$scale,$transform" >/dev/null; then
      echo "Could not restore the Hyprland output $name." >&2
      failed=1
    fi
  done
  (( failed == 0 ))
}
