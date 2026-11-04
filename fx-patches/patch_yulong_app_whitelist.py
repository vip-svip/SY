#!/usr/bin/env python3
"""Patch Yulong 7.0.1 app-whitelist bypass into all FX DNS/TUN ingress paths."""
from pathlib import Path
import shutil
import sys

module = Path(sys.argv[1] if len(sys.argv) > 1 else "fx-module").resolve()
vpncore_path = module / "scripts/vpncore.sh"
proxy_path = module / "scripts/yulong-root-proxy.sh"
apply_path = module / "scripts/apply.sh"
for required in (vpncore_path, proxy_path, apply_path):
    if not required.is_file():
        raise SystemExit(f"restored FX source is missing: {required}")

# 1. FX sing-box TUN: exclude whitelisted application UIDs entirely.
vpncore = vpncore_path.read_text(encoding="utf-8")
core_helper = """# Yulong 7.0.1 application whitelist: resolve package UIDs for FX TUN bypass.
vpncore_yulong_exclude_uids() {
  _yu_uids="0"
  for _yu_pkg in $(pg_list_enabled yulong_app_whitelist 2>/dev/null); do
    case "$_yu_pkg" in ''|*[!A-Za-z0-9_.-]*) continue ;; esac
    _yu_uid=$(stat -c %u "/data/data/$_yu_pkg" 2>/dev/null || true)
    case "$_yu_uid" in ''|*[!0-9]*|0) continue ;; esac
    case " $_yu_uids " in *" $_yu_uid "*) : ;; *) _yu_uids="$_yu_uids,$_yu_uid" ;; esac
  done
  printf '%s' "$_yu_uids"
}

"""
if "vpncore_yulong_exclude_uids()" not in vpncore:
    anchor = "vpncore_genconf() {"
    if anchor not in vpncore:
        raise SystemExit("vpncore_genconf anchor not found")
    vpncore = vpncore.replace(anchor, core_helper + anchor, 1)

core_lines = vpncore.splitlines()
core_changed = False
for index, line in enumerate(core_lines):
    if '"exclude_uid":[0]' in line and '"type":"tun"' in line:
        if not line.rstrip().endswith("\\n'"):
            raise SystemExit("TUN exclude_uid printf line has unexpected format")
        core_lines[index] = (
            line.replace('"exclude_uid":[0]', '"exclude_uid":[%s]', 1)
            + ' "$(vpncore_yulong_exclude_uids)"'
        )
        core_changed = True
        break
if not core_changed and '"exclude_uid":[%s]' not in vpncore:
    raise SystemExit("TUN exclude_uid source anchor not found")
vpncore_path.write_text("\n".join(core_lines) + "\n", encoding="utf-8")

# 2. Third-party VPN compatibility: exempt selected UIDs from FX-owned Root DNS chains.
proxy = proxy_path.read_text(encoding="utf-8")
for family, function in (("iptables", "_build_chain4"), ("ip6tables", "_build_chain6")):
    start = proxy.find(function + "() {")
    if start < 0:
        raise SystemExit(function + " function not found")
    end = proxy.find("\n}", start)
    if end < 0:
        raise SystemExit(function + " function end not found")
    block = proxy[start:end]
    if "yulong_app_whitelist" in block:
        continue
    owner = (
        f'  {family} -t nat -A "$_chain" '
        '-m owner --uid-owner "$_uid" -j RETURN || return 1\n'
    )
    if owner not in block:
        raise SystemExit(function + " VPN owner UID anchor not found")
    insertion = owner + f'''  # Whitelisted packages bypass only FX DNS filtering.
  for _yu_pkg in $(pg_list_enabled yulong_app_whitelist 2>/dev/null); do
    case "$_yu_pkg" in ''|*[!A-Za-z0-9_.-]*) continue ;; esac
    _yu_app_uid=$(stat -c %u "/data/data/$_yu_pkg" 2>/dev/null || true)
    case "$_yu_app_uid" in ''|*[!0-9]*|0) continue ;; esac
    {family} -t nat -A "$_chain" -m owner --uid-owner "$_yu_app_uid" -j RETURN || return 1
  done
'''
    proxy = proxy[:start] + block.replace(owner, insertion, 1) + proxy[end:]
proxy_path.write_text(proxy, encoding="utf-8")

# 3. Legacy transparent/DNS redirect paths: exempt whitelisted UIDs before PGNAT/PGVPN.
apply = apply_path.read_text(encoding="utf-8")
apply_helper = """# Yulong 7.0.1 per-app whitelist UID resolver for the legacy NAT paths.
pg_yulong_whitelist_uids() {
  _yu_uids=""
  for _yu_pkg in $(pg_list_enabled yulong_app_whitelist 2>/dev/null); do
    case "$_yu_pkg" in ''|*[!A-Za-z0-9_.-]*) continue ;; esac
    _yu_uid=$(stat -c %u "/data/data/$_yu_pkg" 2>/dev/null || true)
    case "$_yu_uid" in ''|*[!0-9]*|0) continue ;; esac
    case " $_yu_uids " in *" $_yu_uid "*) : ;; *)
      if [ -z "$_yu_uids" ]; then _yu_uids="$_yu_uid"; else _yu_uids="$_yu_uids $_yu_uid"; fi ;;
    esac
  done
  printf '%s' "$_yu_uids"
}
pg_yulong_whitelist_dns4() {
  for _yu_uid in $(pg_yulong_whitelist_uids); do
    nat4 -A PGNAT -m owner --uid-owner "$_yu_uid" -p udp --dport 53 -j RETURN || return 1
    nat4 -A PGNAT -m owner --uid-owner "$_yu_uid" -p tcp --dport 53 -j RETURN || return 1
  done
}
pg_yulong_whitelist_vpn4() {
  for _yu_uid in $(pg_yulong_whitelist_uids); do
    nat4 -A PGVPN -m owner --uid-owner "$_yu_uid" -j RETURN || return 1
  done
}
pg_yulong_whitelist_vpn6() {
  for _yu_uid in $(pg_yulong_whitelist_uids); do
    nat6 -A PGVPN6 -m owner --uid-owner "$_yu_uid" -j RETURN || return 1
  done
}
"""
if "pg_yulong_whitelist_uids()" not in apply:
    anchor = "# 提交 nat 表队列（只提交 nat 部分，filter/mangle 队列保持不动）"
    if anchor not in apply:
        raise SystemExit("apply.sh NAT queue function anchor not found")
    apply = apply.replace(anchor, apply_helper + anchor, 1)

# Every IPv4 PGNAT creation is a distinct active DNS path (AdGuard, custom, global).
if "pg_yulong_whitelist_dns4 || _IPTQ_WRITE_FAIL=1" not in apply:
    apply = apply.replace(
        '  nat4 -N PGNAT 2>/dev/null\n',
        '  nat4 -N PGNAT 2>/dev/null\n  pg_yulong_whitelist_dns4 || _IPTQ_WRITE_FAIL=1\n'
    )

# The AdGuard IPv6 PGNAT branch uses direct ip6tables and a fail-closed flag.
dns6_helper = """pg_yulong_whitelist_dns6() {
  for _yu_uid in $(pg_yulong_whitelist_uids); do
    ip6tables $FWWAIT -t nat -A PGNAT -m owner --uid-owner "$_yu_uid" -p udp --dport 53 -j RETURN >> "$PG/apply.log" 2>&1 || return 1
    ip6tables $FWWAIT -t nat -A PGNAT -m owner --uid-owner "$_yu_uid" -p tcp --dport 53 -j RETURN >> "$PG/apply.log" 2>&1 || return 1
  done
}
"""
if "pg_yulong_whitelist_dns6()" not in apply:
    apply = apply.replace("pg_yulong_whitelist_dns4() {", dns6_helper + "pg_yulong_whitelist_dns4() {", 1)
v6_anchor = '  ip6tables $FWWAIT -t nat -N PGNAT >/dev/null 2>&1 || _agh6_ok=0\n'
if v6_anchor not in apply:
    raise SystemExit("AdGuard IPv6 PGNAT creation anchor not found")
if "  pg_yulong_whitelist_dns6 || _agh6_ok=0\n" not in apply:
    apply = apply.replace(v6_anchor, v6_anchor + "  pg_yulong_whitelist_dns6 || _agh6_ok=0\n", 1)

vpn4_anchor = """  for _mu in $VPN_MOD_UIDS; do
    nat4 -A PGVPN -m owner --uid-owner "$_mu" -j RETURN 2>/dev/null
  done
"""
if vpn4_anchor not in apply:
    raise SystemExit("PGVPN module UID exemption anchor not found")
if "pg_yulong_whitelist_vpn4 || _IPTQ_WRITE_FAIL=1" not in apply:
    apply = apply.replace(vpn4_anchor, vpn4_anchor + "  pg_yulong_whitelist_vpn4 || _IPTQ_WRITE_FAIL=1\n", 1)

vpn6_anchor = """    for _mu in $VPN_MOD_UIDS; do
      nat6 -A PGVPN6 -m owner --uid-owner "$_mu" -j RETURN 2>/dev/null
    done
"""
if vpn6_anchor not in apply:
    raise SystemExit("PGVPN6 module UID exemption anchor not found")
if "pg_yulong_whitelist_vpn6 || _IPTQ_WRITE_FAIL=1" not in apply:
    apply = apply.replace(vpn6_anchor, vpn6_anchor + "    pg_yulong_whitelist_vpn6 || _IPTQ_WRITE_FAIL=1\n", 1)

apply_path.write_text(apply, encoding="utf-8")

# Keep the same reviewed, hardened whitelist implementation in source and
# restored Release module trees; never ship a stale archive copy.
repo = Path(__file__).resolve().parent.parent
whitelist_source = repo / "scripts/yulong-app-whitelist.sh"
whitelist_test_source = repo / "scripts/tests/fx-yulong-app-whitelist-runtime-regression.sh"
whitelist_target = module / "scripts/yulong-app-whitelist.sh"
whitelist_test_target = module / "scripts/tests/v1.0.0-yulong-app-whitelist-runtime-regression.sh"
if not whitelist_source.is_file() or whitelist_source.stat().st_size < 3000:
    raise SystemExit("reviewed Yulong app-whitelist source missing or unexpectedly small")
if not whitelist_test_source.is_file() or whitelist_test_source.stat().st_size < 1500:
    raise SystemExit("Yulong app-whitelist regression missing or unexpectedly small")
whitelist_target.parent.mkdir(parents=True, exist_ok=True)
whitelist_test_target.parent.mkdir(parents=True, exist_ok=True)
shutil.copy2(whitelist_source, whitelist_target)
shutil.copy2(whitelist_test_source, whitelist_test_target)
whitelist_target.chmod(0o755)
whitelist_test_target.chmod(0o755)

print("Applied Yulong app whitelist to TUN, IPv4/IPv6 PGNAT, PGVPN/PGVPN6 and external-VPN Root DNS; staged the hardened atomic whitelist writer and regression.")
