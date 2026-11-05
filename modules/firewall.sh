# shellcheck shell=bash
# Shared globals are initialized by sunshine-setup.sh before this module is sourced.
# shellcheck disable=SC2154
# ---------- firewall ----------
SUNSHINE_TCP=(47984 47989 48010)
SUNSHINE_UDP=(47998 47999 48000 48002)
WEBUI_PORT=47990

valid_cidr_syntax() {
  local cidr=$1 address prefix octet part left right compressed=0 groups=0 ipv4=""
  local -a octets ipv6_groups
  # Octets and prefixes must not carry redundant leading zeros: tools like
  # Python's ipaddress (firewalld) and ufw reject or misparse forms such as
  # "010.1.1.1" or "/024".
  local ipv4_re='^(0|[1-9][0-9]{0,2})(\.(0|[1-9][0-9]{0,2})){3}$'
  [[ $cidr =~ ^[0-9A-Fa-f:.]+/(0|[1-9][0-9]{0,2})$ ]] || return 1
  address=${cidr%/*}
  prefix=${cidr#*/}
  if [[ $address == *:* ]]; then
    (( 10#$prefix <= 128 )) || return 1
    if [[ $address == *.* ]]; then
      [[ $address == *::* ]] && compressed=1
      ipv4=${address##*:}
      [[ $address == *:"$ipv4" ]] || return 1
      address=${address%:"$ipv4"}
      if (( compressed )) && [[ $address != *::* ]]; then address="${address}:"; fi
      [[ $ipv4 =~ $ipv4_re ]] || return 1
      IFS=. read -r -a octets <<< "$ipv4"
      for octet in "${octets[@]}"; do
        (( 10#$octet <= 255 )) || return 1
      done
    fi
    if [[ $address == *::* ]]; then
      right=${address#*::}
      [[ $right != *::* ]] || return 1
      left=${address%%::*}
      compressed=1
    else
      left=$address
      right=""
    fi
    IFS=: read -r -a ipv6_groups <<< "$left"
    for part in "${ipv6_groups[@]}"; do
      [[ $part =~ ^[0-9A-Fa-f]{1,4}$ ]] || return 1
      ((groups += 1))
    done
    IFS=: read -r -a ipv6_groups <<< "$right"
    for part in "${ipv6_groups[@]}"; do
      [[ $part =~ ^[0-9A-Fa-f]{1,4}$ ]] || return 1
      ((groups += 1))
    done
    [[ -z $ipv4 ]] || ((groups += 2))
    if (( compressed )); then
      (( groups < 8 ))
    else
      (( groups == 8 ))
    fi
    return
  fi
  (( 10#$prefix <= 32 )) || return 1
  [[ $address =~ $ipv4_re ]] || return 1
  IFS=. read -r -a octets <<< "$address"
  for octet in "${octets[@]}"; do
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
    # `ufw status` needs root, so only ask for sudo when firewalld is not the
    # active backend; otherwise an active firewalld would trigger a password
    # prompt just to decide between the two.
    if systemctl is-active --quiet ufw 2>/dev/null; then
      ufw=1
    elif (( ! fwd )); then
      local st; st=$(sudo env LC_ALL=C ufw status 2>/dev/null || true)
      [[ $st == *"Status: active"* ]] && ufw=1
    fi
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

  local p family failed=0
  if [[ $backend == firewalld ]]; then
    if [[ -n $source_cidr ]]; then
      family=ipv4
      [[ $source_cidr == *:*/* ]] && family=ipv6
      for p in "${tcp[@]}"; do
        sudo firewall-cmd --permanent --add-rich-rule="rule family=\"$family\" source address=\"$source_cidr\" port port=\"$p\" protocol=\"tcp\" accept" \
          || failed=$((failed + 1))
      done
      for p in "${udp[@]}"; do
        sudo firewall-cmd --permanent --add-rich-rule="rule family=\"$family\" source address=\"$source_cidr\" port port=\"$p\" protocol=\"udp\" accept" \
          || failed=$((failed + 1))
      done
      sudo firewall-cmd --permanent --add-rich-rule="rule family=\"$family\" source address=\"$source_cidr\" port port=\"5353\" protocol=\"udp\" accept" \
        || failed=$((failed + 1))
    else
      for p in "${tcp[@]}"; do sudo firewall-cmd --permanent --add-port="$p/tcp" || failed=$((failed + 1)); done
      for p in "${udp[@]}"; do sudo firewall-cmd --permanent --add-port="$p/udp" || failed=$((failed + 1)); done
      sudo firewall-cmd --permanent --add-service=mdns || failed=$((failed + 1))
    fi
    if (( failed )); then
      echo "${red}${failed} firewalld rule(s) could not be added.${normal}" >&2
      echo "  The rules above that succeeded are kept; existing rules were not rolled back." >&2
    fi
    sudo firewall-cmd --reload || failed=$((failed + 1))
    echo "  ${dim}Current firewall rules:${normal}"
    sudo firewall-cmd --list-all | sed 's/^/    /' || true
    (( failed == 0 )) || return 1
  else
    if [[ -n $source_cidr ]]; then
      for p in "${tcp[@]}"; do sudo ufw allow from "$source_cidr" to any port "$p" proto tcp comment 'Sunshine' || failed=$((failed + 1)); done
      for p in "${udp[@]}"; do sudo ufw allow from "$source_cidr" to any port "$p" proto udp comment 'Sunshine' || failed=$((failed + 1)); done
      sudo ufw allow from "$source_cidr" to any port 5353 proto udp comment 'Sunshine mDNS' || failed=$((failed + 1))
    else
      for p in "${tcp[@]}"; do sudo ufw allow "$p/tcp" comment 'Sunshine' || failed=$((failed + 1)); done
      for p in "${udp[@]}"; do sudo ufw allow "$p/udp" comment 'Sunshine' || failed=$((failed + 1)); done
      sudo ufw allow 5353/udp comment 'Sunshine mDNS' || failed=$((failed + 1))
    fi
    if (( failed )); then
      echo "${red}${failed} ufw rule(s) could not be added.${normal}" >&2
      echo "  The rules above that succeeded are kept; existing rules were not rolled back." >&2
      return 1
    fi
    echo "  ${dim}Current rules:${normal}"
    sudo ufw status | grep -i sunshine | sed 's/^/    /' || true
  fi
  echo "  ${bold}Firewall ports opened.${normal}"
}
