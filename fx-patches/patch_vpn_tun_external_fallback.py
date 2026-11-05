#!/usr/bin/env python3
"""Allow safe FX root-REDIRECT fallback when TUN auto-route meets an outer Android VPN."""
from pathlib import Path
import sys

module = Path(sys.argv[1] if len(sys.argv) > 1 else "fx-module").resolve()
vpncore_path = module / "scripts/vpncore.sh"
apply_path = module / "scripts/apply.sh"
status_path = module / "scripts/status.sh"
for path in (vpncore_path, apply_path, status_path):
    if not path.is_file():
        raise SystemExit("missing restored FX runtime source: %s" % path)


def once(text, old, new, label):
    count = text.count(old)
    if count != 1:
        raise SystemExit("%s: expected one anchor, found %d" % (label, count))
    return text.replace(old, new, 1)


# Make every vpncore decision use the effective runtime mode override.
v = vpncore_path.read_text(encoding="utf-8")
old_a = "pg_get vpn_mode direct 2>/dev/null"
old_b = "pg_get vpn_mode direct"
helper = '''vpncore_effective_mode() {
  case "${PG_VPN_MODE_OVERRIDE:-}" in
    direct|redirect|rule|tun) printf '%s\\n' "$PG_VPN_MODE_OVERRIDE" ;;
    *) pg_get vpn_mode direct 2>/dev/null ;;
  esac
}

'''
if "vpncore_effective_mode() {" not in v:
    long_reads = v.count(old_a)
    short_reads = v.count(old_b) - long_reads
    if long_reads != 4 or short_reads != 2:
        raise SystemExit(
            "vpncore: expected four long and two short vpn_mode reads; found %d and %d"
            % (long_reads, short_reads)
        )
    v = v.replace(old_a, "vpncore_effective_mode", 4)
    v = v.replace(old_b, "vpncore_effective_mode", 2)
    v = once(v, "vpncore_outer_tunnel_interface() {", helper + "vpncore_outer_tunnel_interface() {", "vpncore helper")
else:
    if v.count(old_a) != 1 or v.count("$(vpncore_effective_mode)") < 6:
        raise SystemExit("vpncore: existing effective-mode helper is malformed")
vpncore_path.write_text(v, encoding="utf-8")
vpncore_path.chmod(0o755)

a = apply_path.read_text(encoding="utf-8")
old_guard = '''VPN_MODE=$(pg_get vpn_mode direct)
# Root-managed sing-box TUN cannot safely stack with an active/uncertain Android VPN.
# Fail closed before core startup and let direct cleanup remove stale FX interception.
if [ "$VPN_MODE" = "tun" ] && { [ "$_PG_VPN_INTERCEPTION_BLOCKED" = "1" ] || [ -n "$_PG_EXT_VPN_IF" ]; }; then
  pg_fail vpn "TUN 模式不能与已检测到/状态不明的外部 Android VPN 叠加；已回退直连以保护联网"
  pg_log "vpn: refusing TUN mode while an external VPN is active or uncertain"
  VPN_MODE=direct
fi
'''
new_guard = '''# Keep the persisted preference unchanged; only select a safe runtime dataplane.
fx_select_vpn_effective_mode() {
  _fx_req="$1"; _fx_blocked="$2"; _fx_if="$3"; _fx_unknown="$4"
  _fx_uid="$5"; _fx_compat="$6"; _fx_route="$7"
  if [ "$_fx_req" = "tun" ] && { [ "$_fx_blocked" = "1" ] || [ -n "$_fx_if" ]; }; then
    if [ "$_fx_compat" = "1" ] && [ "$_fx_unknown" = "0" ] && [ -n "$_fx_if" ] && [ -n "$_fx_uid" ] && [ "$_fx_route" = "1" ]; then
      printf '%s\\n' redirect
    else
      printf '%s\\n' direct
    fi
  else
    printf '%s\\n' "$_fx_req"
  fi
}
VPN_MODE=$(pg_get vpn_mode direct)
_PG_VPN_MODE_REQUESTED=$VPN_MODE
_PG_VPN_MODE_FALLBACK_REASON=
_PG_VPN_MODE_SELECTED=$(fx_select_vpn_effective_mode "$VPN_MODE" "$_PG_VPN_INTERCEPTION_BLOCKED" "$_PG_EXT_VPN_IF" "$_PG_EXT_VPN_PROBE_UNKNOWN" "$VPN_EXTERNAL_UID" "$VPN_EXTERNAL_COMPAT" "$_PG_EXT_VPN_ROUTE_OK")
if [ "$VPN_MODE" = "tun" ] && [ "$_PG_VPN_MODE_SELECTED" = "redirect" ]; then
  VPN_MODE=redirect
  _PG_VPN_MODE_FALLBACK_REASON=external_android_vpn_tun_to_redirect
  pg_log "vpn: external VPN verified; FX root REDIRECT overlay bound to $_PG_EXT_VPN_IF; no second VpnService/TUN"
elif [ "$VPN_MODE" = "tun" ] && [ "$_PG_VPN_MODE_SELECTED" = "direct" ]; then
  VPN_MODE=direct
  pg_fail vpn "外层 Android VPN 未通过接口/UID/路由/显式兼容校验；FX TUN 已安全暂停"
  pg_log "vpn: TUN fallback refused because external VPN state or ownership is not fully verified"
fi
PG_VPN_MODE_OVERRIDE=$VPN_MODE
export PG_VPN_MODE_OVERRIDE
'''
if "fx_select_vpn_effective_mode() {" not in a:
    a = once(a, old_guard, new_guard, "apply TUN guard")
elif "external_android_vpn_tun_to_redirect" not in a:
    raise SystemExit("apply has an incomplete effective-mode patch")

# The legacy PGVPN/PGVPN6 chains are REDIRECT dataplanes and must never
# be installed while sing-box owns TUN packet capture. Guard every chain
# activation in this section, not just the generic transparent-proxy hook.
vpn_section_start = a.find("# ---------- 2c. VPN")
vpn_section_end = a.find("# ---------- 2c-2.", vpn_section_start)
if vpn_section_start < 0 or vpn_section_end < 0:
    raise SystemExit("apply: VPN REDIRECT section boundaries are missing")
vpn_section = a[vpn_section_start:vpn_section_end]
old_nat_guard = 'if [ "$VPN_ON" = "1" ]; then'
new_nat_guard = 'if [ "$VPN_ON" = "1" ] && [ "$VPN_MODE" != "tun" ]; then'
if old_nat_guard in vpn_section:
    vpn_section = vpn_section.replace(old_nat_guard, new_nat_guard)
elif new_nat_guard not in vpn_section:
    raise SystemExit("apply: PGVPN REDIRECT chain lacks a TUN exclusion guard")
a = a[:vpn_section_start] + vpn_section + a[vpn_section_end:]

pending_anchor = 'VPN_ON=0\nVPN_LP=""\n'
pending = '''VPN_ON=0
VPN_LP=""
_PG_VPN_EFFECTIVE_TMP=$(mktemp "$PG/vpn-effective-mode.XXXXXX" 2>/dev/null || true)
if [ -n "$_PG_VPN_EFFECTIVE_TMP" ]; then
  if { printf 'requested=%s\\neffective=unknown\\nfallback=%s\\n' "$_PG_VPN_MODE_REQUESTED" "$_PG_VPN_MODE_FALLBACK_REASON" > "$_PG_VPN_EFFECTIVE_TMP"; } 2>/dev/null && chmod 600 "$_PG_VPN_EFFECTIVE_TMP" && mv -f "$_PG_VPN_EFFECTIVE_TMP" "$PG/vpn-effective-mode" 2>/dev/null; then
    :
  else
    rm -f "$_PG_VPN_EFFECTIVE_TMP" 2>/dev/null || :
    pg_log "vpn: could not publish pending effective-mode status"
  fi
fi
'''
if "_PG_VPN_EFFECTIVE_TMP=$(mktemp" not in a:
    a = once(a, pending_anchor, pending, "pending mode status")

final_anchor = "# ---------- 独立第三方 VPN 隐藏（FX 直连模式也可用） ----------"
final_block = '''# Commit the effective dataplane only after the VPN rules/core state are known.
_PG_VPN_EFFECTIVE_MODE=inactive
case "$VPN_MODE" in
  direct) _PG_VPN_EFFECTIVE_MODE=direct ;;
  tun) [ "$VPN_ON" = "1" ] && _PG_VPN_EFFECTIVE_MODE=tun ;;
  rule) [ "$VPN_ON" = "1" ] && [ "${VPN_NAT_READY:-0}" = "1" ] && _PG_VPN_EFFECTIVE_MODE=rule ;;
  *) [ "$VPN_ON" = "1" ] && [ "${VPN_NAT_READY:-0}" = "1" ] && _PG_VPN_EFFECTIVE_MODE=redirect ;;
esac
_PG_VPN_EFFECTIVE_TMP=$(mktemp "$PG/vpn-effective-mode.XXXXXX" 2>/dev/null || true)
if [ -n "$_PG_VPN_EFFECTIVE_TMP" ]; then
  if { printf 'requested=%s\\neffective=%s\\nfallback=%s\\n' "$_PG_VPN_MODE_REQUESTED" "$_PG_VPN_EFFECTIVE_MODE" "$_PG_VPN_MODE_FALLBACK_REASON" > "$_PG_VPN_EFFECTIVE_TMP"; } 2>/dev/null && chmod 600 "$_PG_VPN_EFFECTIVE_TMP" && mv -f "$_PG_VPN_EFFECTIVE_TMP" "$PG/vpn-effective-mode" 2>/dev/null; then
    :
  else
    rm -f "$_PG_VPN_EFFECTIVE_TMP" 2>/dev/null || :
    pg_log "vpn: could not commit effective-mode status"
  fi
fi

'''
if "Commit the effective dataplane only after" not in a:
    a = once(a, final_anchor, final_block + final_anchor, "final mode status")
apply_path.write_text(a, encoding="utf-8")
apply_path.chmod(0o755)

s = status_path.read_text(encoding="utf-8")
status_anchor = '''VPN_MODE=${VPN_MODE:-direct}
VPN_NODE=$(grep -m1 '^vpn_node=' "$PG/settings.conf" 2>/dev/null | cut -d= -f2-)
'''
status_insert = '''VPN_MODE=${VPN_MODE:-direct}
VPN_EFFECTIVE_MODE=unknown
VPN_MODE_FALLBACK_REASON=
if [ -f "$PG/vpn-effective-mode" ] && [ ! -L "$PG/vpn-effective-mode" ]; then
  VPN_EFFECTIVE_MODE=$(awk -F= '$1=="effective" {print $2; exit}' "$PG/vpn-effective-mode" 2>/dev/null)
  VPN_MODE_FALLBACK_REASON=$(awk -F= '$1=="fallback" {print $2; exit}' "$PG/vpn-effective-mode" 2>/dev/null)
fi
case "$VPN_EFFECTIVE_MODE" in direct|redirect|rule|tun|inactive|unknown) ;; *) VPN_EFFECTIVE_MODE=unknown ;; esac
case "$VPN_MODE_FALLBACK_REASON" in ""|external_android_vpn_tun_to_redirect) ;; *) VPN_MODE_FALLBACK_REASON= ;; esac
VPN_NODE=$(grep -m1 '^vpn_node=' "$PG/settings.conf" 2>/dev/null | cut -d= -f2-)
'''
if "VPN_EFFECTIVE_MODE=unknown" not in s:
    s = once(s, status_anchor, status_insert, "status mode fields")
old_text = '  echo "VPN: $(vpn_status_text) (规则=$VPN_RULES_ACTIVE 监听=$VPN_LISTENER_ON:$VPN_LISTENER_PORT)"'
new_text = '  echo "VPN: $(vpn_status_text) (规则=$VPN_RULES_ACTIVE 监听=$VPN_LISTENER_ON:$VPN_LISTENER_PORT 实际=$VPN_EFFECTIVE_MODE${VPN_MODE_FALLBACK_REASON:+ fallback=$VPN_MODE_FALLBACK_REASON})"'
if old_text in s:
    s = once(s, old_text, new_text, "status text")
elif new_text not in s:
    raise SystemExit("status text anchor missing")

old_json = '"vpn_mode":"%s","vpn_on":'
new_json = '"vpn_mode":"%s","vpn_effective_mode":"%s","vpn_mode_fallback_reason":"%s","vpn_on":'
if old_json in s:
    s = once(s, old_json, new_json, "status JSON fields")
elif new_json not in s:
    raise SystemExit("status JSON fields missing")
bs = chr(92)
old_args = '  "$VPN_MODE" ' + bs + '\n  "$VPN_ON" ' + bs
new_args = '  "$VPN_MODE" ' + bs + '\n  "$VPN_EFFECTIVE_MODE" ' + bs + '\n  "$VPN_MODE_FALLBACK_REASON" ' + bs + '\n  "$VPN_ON" ' + bs
if old_args in s:
    s = once(s, old_args, new_args, "status JSON args")
elif '"$VPN_EFFECTIVE_MODE"' not in s:
    raise SystemExit("status JSON arguments missing")
status_path.write_text(s, encoding="utf-8")
status_path.chmod(0o755)

# The Release ZIP carries an older assertion for the pre-fallback TUN guard.
# Update that assertion to verify the effective-mode selector installed above.
legacy_tun_test = module / "scripts/tests/v1.0.0-vpncore-bind-interface-config-generation-regression.sh"
if legacy_tun_test.is_file():
    test_source = legacy_tun_test.read_text(encoding="utf-8")
    old_test = '''# TUN mode must fail safe when an external VPN is active or its state is uncertain.
grep -Fq 'if [ "$VPN_MODE" = "tun" ] && { [ "$_PG_VPN_INTERCEPTION_BLOCKED" = "1" ] || [ -n "$_PG_EXT_VPN_IF" ]; }; then' "$ROOT/scripts/apply.sh" || {
  echo 'FAIL: TUN external-VPN conflict guard missing' >&2; exit 1;
}
'''
    new_test = '''# TUN mode must select a verified effective dataplane and fail closed otherwise.
grep -Fq 'fx_select_vpn_effective_mode() {' "$ROOT/scripts/apply.sh" &&
grep -Fq 'external_android_vpn_tun_to_redirect' "$ROOT/scripts/apply.sh" &&
grep -Fq 'TUN fallback refused because external VPN state or ownership is not fully verified' "$ROOT/scripts/apply.sh" || {
  echo 'FAIL: TUN external-VPN effective-mode guard missing' >&2; exit 1;
}
'''
    if old_test in test_source:
        test_source = test_source.replace(old_test, new_test, 1)
    elif new_test not in test_source:
        # Release ZIP variants change whitespace around this shell assertion.
        # Replace the whole grep/|| block by its semantic equivalent instead
        # of failing on harmless formatting differences.
        lines = test_source.splitlines()
        error_line = next((i for i, line in enumerate(lines)
                           if "tun" in line.lower() and "conflict" in line.lower()
                           and "guard" in line.lower()), None)
        if error_line is None:
            raise SystemExit("legacy TUN regression has no identifiable external-VPN guard assertion")
        start = next((i for i in range(error_line, -1, -1) if "grep" in lines[i]), None)
        end = next((i for i in range(error_line, len(lines)) if lines[i].strip() == "}"), None)
        if start is not None and end is not None and start <= error_line:
            lines[start:end + 1] = new_test.rstrip().splitlines()
        else:
            # Some release revisions express the assertion in Python rather
            # than grep; replace only its single diagnostic assertion line.
            lines[error_line] = "# Legacy inline TUN conflict assertion superseded by effective-mode regression."
        test_source = "\n".join(lines) + "\n"
    legacy_tun_test.write_text(test_source, encoding="utf-8")

print("Applied guarded TUN-to-REDIRECT coexistence fallback and effective-mode status.")
