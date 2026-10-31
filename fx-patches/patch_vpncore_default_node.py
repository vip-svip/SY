#!/usr/bin/env python3
"""Patch sing-box default-node fallback to select the first parseable node."""
from pathlib import Path
import re
import sys

root = Path(sys.argv[1] if len(sys.argv) > 1 else "fx-module")
target = root / "scripts" / "vpncore.sh"
if not target.is_file():
    raise SystemExit(f"missing VPN core source: {target}")
source = target.read_text(encoding="utf-8")
pattern = re.compile(r"(?ms)^vpncore_default_tag\(\) \{.*?^\}")
replacement = """vpncore_default_tag() {
  _sel=$(pg_get vpn_node 2>/dev/null)
  _i=0
  _first_valid_tag=""
  while IFS= read -r _line; do
    _uri=$(vpncore_line_uri "$_line")
    _i=$((_i+1))
    # Keep the selector index aligned with vpncore_outbounds: invalid node
    # URIs are skipped there, so they must never become the default tag here.
    [ -n "$(singbox_node_outbound "$_uri" "node-$_i")" ] || continue
    [ -n "$_first_valid_tag" ] || _first_valid_tag="node-$_i"
    if [ "$_uri" = "$_sel" ]; then
      printf '%s' "node-$_i"
      return 0
    fi
  done <<__PGNODES__
$(vpncore_nodes)
__PGNODES__
  # A stale or removed selected URI falls back to the first actually emitted
  # outbound, not hard-coded node-1 (which may have been rejected by parsing).
  [ -n "$_first_valid_tag" ] || return 1
  printf '%s' "$_first_valid_tag"
}"""
match = pattern.search(source)
if not match:
    raise SystemExit("cannot locate vpncore_default_tag() safely")
if "_first_valid_tag" in match.group(0):
    print("VPN default-node fallback patch already applied")
    raise SystemExit(0)
source = source[:match.start()] + replacement + source[match.end():]
target.write_text(source, encoding="utf-8")
print("Patched VPN default-node fallback to first parseable outbound")
