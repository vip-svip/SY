#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
PATCHER="$ROOT/fx-patches/patch_vpn_tun_external_fallback.py"
fail(){ echo "FAIL: $*" >&2; exit 1; }
[ -s "$PATCHER" ] || fail "guarded TUN-to-REDIRECT patcher missing"
python3 -m py_compile "$PATCHER" || fail "patcher Python syntax invalid"
T=$(mktemp -d "${TMPDIR:-/tmp}/fx-vpn-tun-fallback.XXXXXX")
trap 'rm -rf "$T"' EXIT HUP INT TERM
MOD="$T/module"
mkdir -p "$MOD/scripts"
cat > "$MOD/scripts/vpncore.sh" <<'VPNCORE'
#!/system/bin/sh
pg_get(){ printf '%s\\n' "${2:-direct}"; }
a=$(pg_get vpn_mode direct 2>/dev/null)
b=$(pg_get vpn_mode direct 2>/dev/null)
c=$(pg_get vpn_mode direct 2>/dev/null)
d=$(pg_get vpn_mode direct 2>/dev/null)
e=$(pg_get vpn_mode direct)
f=$(pg_get vpn_mode direct)
vpncore_outer_tunnel_interface() { :; }
VPNCORE
cat > "$MOD/scripts/apply.sh" <<'APPLY'
#!/system/bin/sh
VPN_MODE=$(pg_get vpn_mode direct)
# Root-managed sing-box TUN cannot safely stack with an active/uncertain Android VPN.
# Fail closed before core startup and let direct cleanup remove stale FX interception.
if [ "$VPN_MODE" = "tun" ] && { [ "$_PG_VPN_INTERCEPTION_BLOCKED" = "1" ] || [ -n "$_PG_EXT_VPN_IF" ]; }; then
  pg_fail vpn "TUN 模式不能与已检测到/状态不明的外部 Android VPN 叠加；已回退直连以保护联网"
  pg_log "vpn: refusing TUN mode while an external VPN is active or uncertain"
  VPN_MODE=direct
fi
VPN_ON=0
VPN_LP=""
# ---------- 独立第三方 VPN 隐藏（FX 直连模式也可用） ----------
APPLY
cat > "$MOD/scripts/status.sh" <<'STATUS'
#!/system/bin/sh
VPN_MODE=${VPN_MODE:-direct}
VPN_NODE=$(grep -m1 '^vpn_node=' "$PG/settings.conf" 2>/dev/null | cut -d= -f2-)
vpn_status_text(){ printf '%s' stopped; }
  echo "VPN: $(vpn_status_text) (规则=$VPN_RULES_ACTIVE 监听=$VPN_LISTENER_ON:$VPN_LISTENER_PORT)"
printf '{"vpn_mode":"%s","vpn_on":%s}\\n' \\
  "$VPN_MODE" \\
  "$VPN_ON" \\
STATUS
chmod 0755 "$MOD/scripts/"*.sh
python3 "$PATCHER" "$MOD" >/dev/null || fail "patcher rejected canonical VPN anchors"
for f in "$MOD/scripts/vpncore.sh" "$MOD/scripts/apply.sh" "$MOD/scripts/status.sh"; do
  sh -n "$f" || fail "patched shell syntax invalid: $f"
done
grep -Fq 'case "${PG_VPN_MODE_OVERRIDE:-}" in' "$MOD/scripts/vpncore.sh" || fail "vpncore ignores the effective mode override"
grep -Fq 'PG_VPN_MODE_OVERRIDE=$VPN_MODE' "$MOD/scripts/apply.sh" || fail "apply does not pass the effective mode to vpncore"
grep -Fq 'external_android_vpn_tun_to_redirect' "$MOD/scripts/apply.sh" || fail "fallback reason is not recorded"
grep -Fq '"vpn_effective_mode":"%s"' "$MOD/scripts/status.sh" || fail "status JSON omits effective VPN mode"
grep -Fq '"vpn_mode_fallback_reason":"%s"' "$MOD/scripts/status.sh" || fail "status JSON omits fallback reason"
python3 - "$MOD/scripts/vpncore.sh" "$MOD/scripts/apply.sh" "$T/mode-functions.sh" <<'PY'
from pathlib import Path
import sys
vpncore, apply, output = map(Path, sys.argv[1:])
v = vpncore.read_text(encoding="utf-8")
a = apply.read_text(encoding="utf-8")
v_start = v.index("vpncore_effective_mode() {")
v_end = v.index("\n}\n", v_start) + 3
a_start = a.index("fx_select_vpn_effective_mode() {")
a_end = a.index("\n}\n", a_start) + 3
functions = """pg_get(){ printf '%s\\n' "${PG_SAVED_MODE:-direct}"; }\n"""
functions += v[v_start:v_end] + "\n" + a[a_start:a_end] + "\n"
output.write_text(functions, encoding="utf-8")
PY
sh -c '
  set -eu
  . "$1"
  PG_VPN_MODE_OVERRIDE=redirect
  [ "$(vpncore_effective_mode)" = redirect ]
  unset PG_VPN_MODE_OVERRIDE
  PG_SAVED_MODE=tun
  [ "$(vpncore_effective_mode)" = tun ]
  [ "$(fx_select_vpn_effective_mode tun 1 tun0 0 10042 1 1)" = redirect ]
  [ "$(fx_select_vpn_effective_mode tun 1 tun0 1 10042 1 1)" = direct ]
  [ "$(fx_select_vpn_effective_mode tun 1 tun0 0 "" 1 1)" = direct ]
  [ "$(fx_select_vpn_effective_mode tun 0 "" 0 "" 1 0)" = tun ]
  [ "$(fx_select_vpn_effective_mode rule 1 tun0 0 10042 1 1)" = rule ]
' sh "$T/mode-functions.sh" || fail "effective-mode selection violated coexistence gates"
# The patcher must be safe to rerun on a restored/rebuilt module tree.
python3 "$PATCHER" "$MOD" >/dev/null || fail "patcher is not idempotent"
for f in "$MOD/scripts/vpncore.sh" "$MOD/scripts/apply.sh" "$MOD/scripts/status.sh"; do
  sh -n "$f" || fail "idempotent patch shell syntax invalid: $f"
done
[ "$(grep -Fc 'fx_select_vpn_effective_mode() {' "$MOD/scripts/apply.sh")" -eq 1 ] || fail "apply helper duplicated on rerun"
[ "$(grep -Fc 'vpncore_effective_mode() {' "$MOD/scripts/vpncore.sh")" -eq 1 ] || fail "vpncore helper duplicated on rerun"
echo "PASS: TUN-to-REDIRECT fallback requires verified outer VPN interface, owner UID, explicit compatibility and route proof; status distinguishes requested/effective mode."
