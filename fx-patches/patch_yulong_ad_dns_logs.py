#!/usr/bin/env python3
"""Stage the local DNS query-log helper and support legacy and current renderers."""
from pathlib import Path
import shutil
import sys

module = Path(sys.argv[1] if len(sys.argv) > 1 else "fx-module").resolve()
script = module / "scripts" / "adguardhome.sh"
if not script.is_file() or script.stat().st_size < 8000:
    raise SystemExit("AdGuard Home lifecycle script missing or unexpectedly small")

source = script.read_text(encoding="utf-8")
legacy_anchor = '  _rules_file="$MODDIR/fxrules/anti_fraud_96110.txt"\n'
legacy_insert = """  # DNS query logging is off by default. When explicitly enabled, AdGuard
  # retains its local query log for thirty days; no external upload path
  # is configured. settings.conf is root-owned and atomically updated by FX.
  _dns_querylog_enabled=$(awk -F= '
    $1=="dns_querylog_enabled" {v=$2}
    END {if(v=="1") print "true"; else print "false"}
  ' "$PG/settings.conf" 2>/dev/null)
  case "$_dns_querylog_enabled" in true) : ;; *) _dns_querylog_enabled=false ;; esac
"""
legacy_old = """querylog:
  enabled: false
  file_enabled: false
  interval: 30d
  size_memory: 1000
  ignored: []
  ignored_enabled: false"""
legacy_new = """querylog:
  enabled: $_dns_querylog_enabled
  file_enabled: $_dns_querylog_enabled
  interval: 30d
  size_memory: 1000
  ignored: []
  ignored_enabled: false"""

# Current FX AdGuard renderer obtains the complete query-log runtime contract
# (enabled, retention, memory batching and ignored domains) from the Root
# settings adapter and merges it into the runtime YAML. Do not downgrade that
# renderer by applying the older one-switch patch.
modern_markers = (
    "dns-querylog-runtime-get",
    "dns-querylog-ignored-get",
    "in_querylog && /^  ignored:",
)
modern_renderer = all(marker in source for marker in modern_markers)

if modern_renderer:
    pass
elif legacy_anchor in source:
    if "_dns_querylog_enabled=$(awk -F=" not in source:
        source = source.replace(legacy_anchor, legacy_insert + legacy_anchor, 1)
    if legacy_old in source:
        source = source.replace(legacy_old, legacy_new, 1)
    elif legacy_new not in source:
        raise SystemExit("legacy AdGuard Home querylog YAML block not found")
else:
    raise SystemExit(
        "AdGuard Home renderer is neither the supported legacy layout nor the "
        "current Root-managed DNS query-log renderer"
    )

script.write_text(source, encoding="utf-8")
script.chmod(0o755)

resolved = Path(__file__).resolve()
repo_root = next(
    (
        parent for parent in resolved.parents
        if (parent / "fx-module").is_dir()
        and (parent / "scripts" / "yulong-ad-dns-summary.sh").is_file()
    ),
    None,
)
if repo_root is None:
    raise SystemExit("repository DNS summary helper source could not be located")
helper_source = repo_root / "scripts" / "yulong-ad-dns-summary.sh"
helper_target = module / "scripts" / "yulong-ad-dns-summary.sh"
if helper_source.stat().st_size < 500:
    raise SystemExit("privacy-preserving DNS summary helper is unexpectedly small")
helper_target.parent.mkdir(parents=True, exist_ok=True)
shutil.copy2(helper_source, helper_target)
helper_target.chmod(0o755)
print("Preserved the current Root-managed DNS query-log renderer and staged the numeric-only summary helper.")
