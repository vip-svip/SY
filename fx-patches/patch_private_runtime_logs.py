#!/usr/bin/env python3
"""Restrict FX runtime logs and prevent subscription URLs leaking into diagnostics."""
from pathlib import Path
import sys

root = Path(sys.argv[1] if len(sys.argv) > 1 else "fx-module")
required = ("scripts/util.sh", "scripts/apply.sh", "scripts/jsruntime/sync-subs.sh",
            "scripts/vpncore.sh", "service.sh")
files = {name: root / name for name in required}
missing = [name for name, path in files.items() if not path.is_file()]
if missing:
    raise SystemExit("runtime log patch source missing: " + ", ".join(missing))


def replace_once(source: str, old: str, new: str, label: str) -> str:
    count = source.count(old)
    if count == 1:
        return source.replace(old, new, 1)
    if count == 0 and new in source:
        return source
    raise SystemExit(f"{label}: expected one known source block, found {count}")


# Logs are root-only because they can contain node hosts, local paths and
# diagnostic details. Use restrictive creation masks and repair old file modes.
util_path = files["scripts/util.sh"]
util = util_path.read_text(encoding="utf-8")
util = replace_once(
    util,
    'pg_log() { echo "[$(date '+%m-%d %H:%M:%S')] $*" >> "$PG/apply.log"; }',
    '''pg_log() {
  (umask 077; echo "[$(date '+%m-%d %H:%M:%S')] $*" >> "$PG/apply.log") || return 1
  chmod 600 "$PG/apply.log" 2>/dev/null || :
  return 0
}''',
    "pg_log permission hardening",
)
util = replace_once(
    util,
    'pg_err_reset() { PG_ERRS=0; : > "$PG_LOGF" 2>/dev/null; }',
    '''pg_err_reset() {
  PG_ERRS=0
  (umask 077; : > "$PG_LOGF") 2>/dev/null || :
  chmod 600 "$PG_LOGF" 2>/dev/null || :
}''',
    "apply.errors permission hardening",
)
old_fail = '''pg_fail() {
  PG_ERRS=$((PG_ERRS+1))
  echo "[$(date '+%m-%d %H:%M:%S')] FAIL($1): $2" >> "$PG/apply.log"
  echo "$1: $2" >> "$PG_LOGF" 2>/dev/null
}'''
new_fail = '''pg_fail() {
  PG_ERRS=$((PG_ERRS+1))
  (umask 077
   echo "[$(date '+%m-%d %H:%M:%S')] FAIL($1): $2" >> "$PG/apply.log"
   echo "$1: $2" >> "$PG_LOGF" 2>/dev/null) || :
  chmod 600 "$PG/apply.log" "$PG_LOGF" 2>/dev/null || :
}'''
util = replace_once(util, old_fail, new_fail, "pg_fail permission hardening")
# The FX rules catalog URLs are user-editable and may contain credentials.
util_lines = util.splitlines()
for i, line in enumerate(util_lines):
    if "pg_log" in line and "$_fx_url" in line:
        util_lines[i] = line.replace("$_fx_url", "[source URL redacted]")
util_new = "\n".join(util_lines) + "\n"
if util_new == util or "$_fx_url" in "\n".join(
    line for line in util_new.splitlines() if "pg_log" in line
):
    if "$_fx_url" in "\n".join(line for line in util_new.splitlines() if "pg_log" in line):
        raise SystemExit("util.sh still logs a full FX subscription URL")
util_path.write_text(util_new, encoding="utf-8")

apply_path = files["scripts/apply.sh"]
apply = apply_path.read_text(encoding="utf-8")
apply = replace_once(
    apply,
    '. "$MODDIR/scripts/util.sh"\n',
    '. "$MODDIR/scripts/util.sh"\numask 077\n',
    "apply restrictive umask",
)
apply = replace_once(
    apply,
    'mkdir -p "$PG/cache" 2>/dev/null || true\n',
    'mkdir -p "$PG/cache" 2>/dev/null || true\nchmod 600 "$PG/apply.log" "$PG/apply.errors" 2>/dev/null || :\n',
    "repair existing apply log permissions",
)
apply_lines = apply.splitlines()
for i, line in enumerate(apply_lines):
    if "pg_log" in line:
        line = line.replace("$_hf_url", "[subscription URL redacted]")
        line = line.replace("$_cu", "[subscription URL redacted]")
        apply_lines[i] = line
apply_new = "\n".join(apply_lines) + "\n"
if any(token in line for line in apply_new.splitlines() if "pg_log" in line
       for token in ("$_hf_url", "$_cu")):
    raise SystemExit("apply.sh still logs a full user subscription URL")
apply_path.write_text(apply_new, encoding="utf-8")

sync_path = files["scripts/jsruntime/sync-subs.sh"]
sync = sync_path.read_text(encoding="utf-8")
sync_lines = sync.splitlines()
for i, line in enumerate(sync_lines):
    if "pg_log" in line and "$url" in line:
        sync_lines[i] = line.replace("$url", "[subscription URL redacted]")
sync_new = "\n".join(sync_lines) + "\n"
if any("$url" in line for line in sync_new.splitlines() if "pg_log" in line):
    raise SystemExit("sync-subs.sh still logs a full script subscription URL")
sync_path.write_text(sync_new, encoding="utf-8")

vpn_path = files["scripts/vpncore.sh"]
vpn = vpn_path.read_text(encoding="utf-8")
vpn_lines = vpn.splitlines()
for i, line in enumerate(vpn_lines):
    if "pg_log" in line and "$_url" in line:
        vpn_lines[i] = line.replace("$_url", "[release URL redacted]")
vpn_new = "\n".join(vpn_lines) + "\n"
if any("$_url" in line for line in vpn_new.splitlines() if "pg_log" in line):
    raise SystemExit("vpncore.sh still logs its complete release URL")
vpn_path.write_text(vpn_new, encoding="utf-8")

service_path = files["service.sh"]
service = service_path.read_text(encoding="utf-8")
service = replace_once(
    service,
    'PG=/data/adb/privacyguard\nmkdir -p "$PG" 2>/dev/null\n',
    'PG=/data/adb/privacyguard\numask 077\nmkdir -p "$PG" 2>/dev/null\n: >> "$PG/boot.log" 2>/dev/null\nchmod 600 "$PG/boot.log" "$PG/apply.log" "$PG/apply.errors" 2>/dev/null || :\n',
    "service log permission hardening",
)
service_path.write_text(service, encoding="utf-8")
print("Hardened FX runtime log permissions and redacted user subscription URLs from diagnostics.")
