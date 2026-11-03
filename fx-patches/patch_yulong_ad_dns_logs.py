#!/usr/bin/env python3
"""Enable user-opt-in, local-only AdGuard Home DNS query logging in restored FX release source."""
from pathlib import Path
import sys

module = Path(sys.argv[1] if len(sys.argv) > 1 else "fx-module").resolve()
script = module / "scripts/adguardhome.sh"
if not script.is_file() or script.stat().st_size < 8000:
    raise SystemExit("AdGuard Home lifecycle script missing or unexpectedly small")

source = script.read_text(encoding="utf-8")
anchor = "  _rules_file=\"$MODDIR/fxrules/anti_fraud_96110.txt\"\n"
if anchor not in source:
    raise SystemExit("AdGuard Home rule render anchor missing")
insert = """  # DNS query logging is off by default. When explicitly enabled, AdGuard
  # keeps its own local querylog file for seven days; no external upload path
  # is configured. settings.conf is root-owned and atomically updated by FX.
  _dns_querylog_enabled=$(awk -F= '
    $1==\"dns_querylog_enabled\" {v=$2}
    END {if(v==\"1\") print 1; else print 0}
  ' \"$PG/settings.conf\" 2>/dev/null)
  case \"$_dns_querylog_enabled\" in 1) : ;; *) _dns_querylog_enabled=0 ;; esac
"""
if "_dns_querylog_enabled=$(awk -F=" not in source:
    source = source.replace(anchor, insert + anchor, 1)

old = """querylog:
  enabled: false
  file_enabled: false
  interval: 30d
  size_memory: 1000
  ignored: []
  ignored_enabled: false"""
new = """querylog:
  enabled: $_dns_querylog_enabled
  file_enabled: $_dns_querylog_enabled
  interval: 7d
  size_memory: 1000
  ignored: []
  ignored_enabled: false"""
if old not in source:
    if new not in source:
        raise SystemExit("AdGuard Home querylog YAML block not found")
else:
    source = source.replace(old, new, 1)

script.write_text(source, encoding="utf-8")
script.chmod(0o755)
print("Applied user-opt-in local AdGuard Home query log (7-day retention, disabled by default).")
