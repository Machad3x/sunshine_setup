#!/usr/bin/env bash
# End-to-end CLI smoke suite: runs the real sunshine-setup.sh in a sandboxed
# HOME against controlled PATHs and stub commands. Complements tests/run.sh,
# which exercises the sourced module functions.
set -uo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
S="$ROOT/sunshine-setup.sh"
BASH_BIN=$(command -v bash)
WORK=$(mktemp -d)
trap 'rm -rf -- "$WORK"' EXIT
PASS=0 FAIL=0
ok()  { PASS=$((PASS + 1)); echo "  ok: $1"; }
bad() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }
fakehome() { mktemp -d "$WORK/home.XXXXXX"; }

# T1: virtual-monitor menu reports a configured entry.
H=$(fakehome); mkdir -p "$H/.config/sunshine"
printf '{"apps":[{"name":"Virtual Monitor"}]}\n' > "$H/.config/sunshine/apps.json"
out=$(printf '3\n' | HOME="$H" XDG_CURRENT_DESKTOP=KDE XDG_SESSION_TYPE=wayland "$BASH_BIN" "$S" virtual-monitor 2>&1) \
  && grep -q 'Virtual Monitor is configured.' <<<"$out" \
  && ok "menu reports configured virtual monitor" || bad "menu (configured): $out"

# T2: virtual-monitor menu reports an absent entry.
printf '{"apps":[]}\n' > "$H/.config/sunshine/apps.json"
out=$(printf '3\n' | HOME="$H" "$BASH_BIN" "$S" virtual-monitor 2>&1) \
  && grep -q 'is not configured.' <<<"$out" \
  && ok "menu reports absent virtual monitor" || bad "menu (absent): $out"

# T3: without jq the menu must say it cannot check, not claim absence.
STUB=$(mktemp -d "$WORK/stub.XXXXXX"); ln -s "$(command -v dirname)" "$STUB/dirname"
out=$(printf '3\n' | HOME="$H" PATH="$STUB" "$BASH_BIN" "$S" virtual-monitor 2>&1) \
  && grep -q 'Cannot check the Virtual Monitor state: jq is required' <<<"$out" \
  && ok "menu distinguishes missing jq from absent configuration" || bad "menu (no jq): $out"

# T4: fix_503 fails closed on an unwritable environment.d (skip when root).
if (( EUID != 0 )); then
  H2=$(fakehome); mkdir -p "$H2/.config/environment.d"; chmod 500 "$H2/.config/environment.d"
  if out=$(HOME="$H2" XDG_CURRENT_DESKTOP=KDE XDG_SESSION_TYPE=wayland "$BASH_BIN" "$S" 503 2>&1); then
    chmod 700 "$H2/.config/environment.d"
    bad "503 fix wrote into an unwritable directory"
  else
    chmod 700 "$H2/.config/environment.d"
    [[ $out == *'Could not write'* ]] && ok "503 fix reports write failures" || bad "503 fix message: $out"
  fi
fi

# T5: 503 apply and reset round-trip through the CLI.
H3=$(fakehome)
HOME="$H3" XDG_CURRENT_DESKTOP=KDE XDG_SESSION_TYPE=wayland "$BASH_BIN" "$S" 503 >/dev/null 2>&1 \
  && grep -Fxq 'KWIN_WAYLAND_NO_PERMISSION_CHECKS=1' "$H3/.config/environment.d/98-sunshine-setup-503.conf" \
  && ok "503 fix applied via CLI" || bad "503 apply"
HOME="$H3" "$BASH_BIN" "$S" 503-reset >/dev/null 2>&1 \
  && [[ ! -e "$H3/.config/environment.d/98-sunshine-setup-503.conf" ]] \
  && ok "503 reset removes the setting via CLI" || bad "503 reset"

# T6: --version matches SCRIPT_VERSION.
expected=$(sed -nE 's/^SCRIPT_VERSION="([^"]+)".*/\1/p' "$S")
out=$("$BASH_BIN" "$S" --version 2>&1) \
  && [[ $out == "sunshine-setup.sh $expected" ]] \
  && ok "--version is consistent with SCRIPT_VERSION" || bad "--version: $out"

# T7: repair without Sunshine points at the install command (CLI wording).
H4=$(fakehome)
out=$(HOME="$H4" PATH="$STUB" "$BASH_BIN" "$S" repair 2>&1)
[[ $out == *"Install it first (menu option 1, or the 'install' command)"* ]] \
  && ok "repair guidance names the CLI command" || bad "repair message: $out"

# T8: the Hyprland flock error names util-linux.
H5=$(fakehome); ln -s "$(command -v jq)" "$STUB/jq"
cat > "$STUB/hyprctl" <<'EOF'
#!/usr/bin/env bash
[[ ${1:-} == monitors ]] && echo '[]'
EOF
chmod 755 "$STUB/hyprctl"
out=$(HOME="$H5" PATH="$STUB" HYPRLAND_INSTANCE_SIGNATURE=test "$BASH_BIN" "$S" vmon 2>&1)
[[ $out == *"provided by the 'util-linux' package"* ]] \
  && ok "flock error names util-linux" || bad "flock message: $out"

# T9: unknown CLI flags are rejected with rc 2 before touching anything.
out=$(HOME="$H4" "$BASH_BIN" "$S" install --bogus 2>&1); rc=$?
(( rc == 2 )) && [[ $out == *"Unknown install option"* ]] \
  && ok "install rejects unknown flags" || bad "install --bogus rc=$rc out=$out"
out=$(HOME="$H4" "$BASH_BIN" "$S" service --bogus 2>&1); rc=$?
(( rc == 2 )) && ok "service rejects unknown scopes" || bad "service --bogus rc=$rc out=$out"

# T10: missing /etc/os-release is reported instead of a raw source failure.
if command -v bwrap >/dev/null 2>&1; then
  out=$(bwrap --bind / / --tmpfs /etc --dev /dev --proc /proc "$BASH_BIN" "$S" --version 2>&1); rc=$?
  (( rc == 1 )) && [[ $out == *"Could not read /etc/os-release"* ]] \
    && ok "os-release guard fails with a clear message" || bad "os-release rc=$rc out=$out"
else
  echo "  (bwrap unavailable — os-release guard scenario skipped)"
fi

# T11: kb-locale rewrites an existing sunshine.conf and rejects unknown codes.
H6=$(fakehome); mkdir -p "$H6/.config/sunshine"
printf 'port = 47989\n' > "$H6/.config/sunshine/sunshine.conf"
out=$(HOME="$H6" "$BASH_BIN" "$S" kb-locale pt_BR 2>&1 </dev/null); rc=$?
[[ $rc == 0 ]] && grep -Fxq 'locale = pt_BR' "$H6/.config/sunshine/sunshine.conf" \
  && grep -Fxq 'port = 47989' "$H6/.config/sunshine/sunshine.conf" \
  && ok "kb-locale writes sunshine.conf" || bad "kb-locale: rc=$rc $out"
out=$(HOME="$H6" "$BASH_BIN" "$S" kb-locale xx 2>&1 </dev/null); rc=$?
(( rc != 0 )) && [[ $out == *'Unsupported Sunshine locale'* ]] \
  && ok "kb-locale rejects unknown codes" || bad "kb-locale xx rc=$rc out=$out"

# T12: the keyboard menu opens and backs out cleanly.
out=$(printf '4\n' | HOME="$H6" "$BASH_BIN" "$S" keyboard 2>&1); rc=$?
[[ $rc == 0 ]] && [[ $out == *"Keyboard language"* ]] \
  && ok "keyboard menu opens" || bad "keyboard menu rc=$rc out=$out"

echo "PASS CLI smoke ($PASS checks, $FAIL failures)"
(( FAIL == 0 ))
