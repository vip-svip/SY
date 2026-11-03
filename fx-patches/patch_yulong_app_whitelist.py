#!/usr/bin/env python3
"""Patch Yulong 7.0.1 app-whitelist bypass into FX's existing network paths."""
from pathlib import Path
import sys

module = Path(sys.argv[1] if len(sys.argv) > 1 else "fx-module").resolve()
vpncore_path = module / "scripts/vpncore.sh"
proxy_path = module / "scripts/yulong-root-proxy.sh"
if not vpncore_path.is_file() or not proxy_path.is_file():
    raise SystemExit("restored FX vpncore.sh or Yulong Root DNS Proxy is missing")

vpncore = vpncore_path.read_text(encoding="utf-8")
helper = """# Yulong 7.0.1 application whitelist: resolve package UIDs for FX TUN bypass.
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
    vpncore = vpncore.replace(anchor, helper + anchor, 1)

lines = vpncore.splitlines()
changed = False
for index, line in enumerate(lines):
    if '"exclude_uid":[0]' in line and '"type":"tun"' in line:
        if not line.rstrip().endswith("\\n'"):
            raise SystemExit("TUN exclude_uid printf line has unexpected format")
        lines[index] = (
            line.replace('"exclude_uid":[0]', '"exclude_uid":[%s]', 1)
            + ' "$(vpncore_yulong_exclude_uids)"'
        )
        changed = True
        break
if not changed and '"exclude_uid":[%s]' not in vpncore:
    raise SystemExit("TUN exclude_uid source anchor not found")
vpncore_path.write_text("\n".join(lines) + "\n", encoding="utf-8")

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
print("Applied Yulong app whitelist to FX sing-box TUN exclude_uid and Root DNS Proxy UID exemptions.")
