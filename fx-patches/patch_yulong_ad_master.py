#!/usr/bin/env python3
"""Install an independent switch for the restored Yulong/FX ad rule list."""
from pathlib import Path
import re, sys
root=Path(sys.argv[1] if len(sys.argv)>1 else "fx-module")
util=root/"scripts/util.sh"
default=root/"scripts/default.conf"
if not util.is_file() or not default.is_file():
    raise SystemExit("restored FX util.sh/default.conf missing")
u=util.read_text(encoding="utf-8")
pattern=re.compile(r"(?m)^pg_list_enabled\(\) \{[^\n]*\}$")
replacement='''pg_list_enabled() {
  # Yulong ad master disables only the [list:rule] filter generation.
  # [list:domain], [list:block], FX anti-fraud and VPN/Hook settings are independent.
  if [ "$1" = "rule" ] && [ "$(pg_get yulong_ad_filter_enabled 1)" != "1" ]; then return 0; fi
  pg_list "$1" | grep -v '^[[:space:]]*#' | awk -F'|' '$3=="1" && $1!=""{print $1}'
}'''
if pattern.search(u):
    u2,n=pattern.subn(replacement,u,count=1)
    if n!=1: raise SystemExit("pg_list_enabled function anchor missing")
    u=u2
    util.write_text(u,encoding="utf-8")
elif "pg_list_enabled() {" not in u or "yulong_ad_filter_enabled" not in u:
    # A second build invocation sees the already-expanded multi-line function.
    # Accept only that known patched state; fail closed on an unknown shape.
    raise SystemExit("pg_list_enabled is neither the original one-line form nor the reviewed Yulong-patched form")
d=default.read_text(encoding="utf-8")
if "yulong_ad_filter_enabled=" not in d:
    marker="hook_ads_enabled=0\n"
    if marker not in d: raise SystemExit("default.conf hook_ads_enabled anchor missing")
    d=d.replace(marker,marker+"# Independent Yulong/FX ad filter master; 0 suspends [list:rule] only.\nyulong_ad_filter_enabled=1\n",1)
    default.write_text(d,encoding="utf-8")

# Stage the weekly scheduler into the restored module.
repo_root = Path(__file__).resolve().parent.parent
scheduler_source = repo_root / "scripts/yulong-ad-schedule.sh"
trusted_source = repo_root / "scripts/yulong-trusted-network.sh"
trusted_target = root / "scripts/yulong-trusted-network.sh"
if not trusted_source.is_file():
    raise SystemExit("Yulong trusted-network watcher source is missing")
trusted_target.write_text(trusted_source.read_text(encoding="utf-8"), encoding="utf-8")
trusted_target.chmod(0o755)
scheduler_target = root / "scripts/yulong-ad-schedule.sh"
if not scheduler_source.is_file():
    raise SystemExit("Yulong weekly schedule source is missing")
scheduler_target.write_text(scheduler_source.read_text(encoding="utf-8"), encoding="utf-8")
scheduler_target.chmod(0o755)

# The schedule gates only Yulong ad rules and never FX's 96110 or user Hosts lists.
u = util.read_text(encoding="utf-8")
needle = '''  if [ "$1" = "rule" ] && [ "$(pg_get yulong_ad_filter_enabled 1)" != "1" ]; then return 0; fi'''
schedule_gate = needle + '''
  if [ "$1" = "rule" ] && [ "$(pg_get yulong_ad_schedule_active 1)" != "1" ]; then return 0; fi
  if [ "$1" = "rule" ] && [ "$(pg_get yulong_ad_trusted_active 1)" != "1" ]; then return 0; fi'''
missing_gates = []
if "yulong_ad_schedule_active" not in u:
    missing_gates.append('  if [ "$1" = "rule" ] && [ "$(pg_get yulong_ad_schedule_active 1)" != "1" ]; then return 0; fi')
if "yulong_ad_trusted_active" not in u:
    missing_gates.append('  if [ "$1" = "rule" ] && [ "$(pg_get yulong_ad_trusted_active 1)" != "1" ]; then return 0; fi')
if missing_gates:
    if needle not in u:
        raise SystemExit("Yulong ad master gate anchor missing for schedule/trusted extension")
    u = u.replace(needle, needle + "\n" + "\n".join(missing_gates), 1)
    util.write_text(u, encoding="utf-8")

# Keep scalar defaults in the key/value section, before every [list:*] block.
# Older code appended escaped newline text after [list:fx], corrupting rule isolation.
malformed_schedule_block = r"\n# Weekly Yulong ad schedule runtime state (1=inside schedule, default enabled).\nyulong_ad_schedule_active=1\n"
d = d.replace(malformed_schedule_block, "")
d = re.sub(r"(?m)^# Weekly Yulong ad schedule runtime state.*(?:\r?\n|$)", "", d)
d = re.sub(r"(?m)^yulong_ad_schedule_active=.*(?:\r?\n|$)", "", d)
d = re.sub(r"(?m)^yulong_ad_trusted_active=.*(?:\r?\n|$)", "", d)
schedule_anchor = re.search(r"(?m)^yulong_ad_filter_enabled=[^\r\n]*", d)
if schedule_anchor is None:
    raise SystemExit("Yulong ad master default key missing before schedule state insertion")
schedule_default = (
    "\n# Weekly Yulong ad schedule runtime state (1=inside schedule, default enabled).\n"
    "yulong_ad_schedule_active=1\n"
    "yulong_ad_trusted_active=1\n"
)
d = d[:schedule_anchor.end()] + schedule_default + d[schedule_anchor.end():]
default.write_text(d, encoding="utf-8")

service = root / "service.sh"
if not service.is_file():
    raise SystemExit("restored FX service.sh missing")
service_text = service.read_text(encoding="utf-8")
service_marker = 'if [ -x "$MODDIR/scripts/jsruntime/scheduler.sh" ]; then'
service_trusted_insert = '''# Trusted Wi-Fi watcher gates only Yulong ad rules.
if [ -x "$MODDIR/scripts/yulong-trusted-network.sh" ]; then
  sh "$MODDIR/scripts/yulong-trusted-network.sh" start >> "$PG/boot.log" 2>&1 || :
fi
'''
service_insert = '''# Restore the Yulong weekly schedule after the main FX apply.
if [ -x "$MODDIR/scripts/yulong-ad-schedule.sh" ]; then
  sh "$MODDIR/scripts/yulong-ad-schedule.sh" start "$MODDIR" "$PG" >> "$PG/boot.log" 2>&1 || :
fi
'''
service_additions = []
if "yulong-trusted-network.sh" not in service_text:
    service_additions.append(service_trusted_insert)
if "yulong-ad-schedule.sh" not in service_text:
    service_additions.append(service_insert)
if service_additions:
    if service_marker not in service_text:
        raise SystemExit("FX service lifecycle insertion anchor missing")
    service_text = service_text.replace(service_marker, "".join(service_additions) + service_marker, 1)
    service.write_text(service_text, encoding="utf-8")
    service.chmod(0o755)

uninstall = root / "uninstall.sh"
if not uninstall.is_file():
    raise SystemExit("restored FX uninstall.sh missing")
uninstall_text = uninstall.read_text(encoding="utf-8")
if "yulong-trusted-network.sh" not in uninstall_text:
    remover_marker = 'REMOVER="$MODDIR/scripts/remove_adhook_app.sh"\n'
    if remover_marker not in uninstall_text:
        raise SystemExit("FX uninstall Hook remover anchor missing")
    trusted_stop = '''# Stop trusted Wi-Fi pause and restore its owned gate before uninstall.
if [ -x "$MODDIR/scripts/yulong-trusted-network.sh" ]; then
  sh "$MODDIR/scripts/yulong-trusted-network.sh" uninstall >/dev/null 2>&1 || :
fi
'''
    uninstall_text = uninstall_text.replace(remover_marker, trusted_stop + remover_marker, 1)
    uninstall.write_text(uninstall_text, encoding="utf-8")
    uninstall.chmod(0o755)

old_stop = 'if [ -x "$MODDIR/scripts/yulong-ad-schedule.sh" ]; then sh "$MODDIR/scripts/yulong-ad-schedule.sh" stop "$MODDIR" "$STATE_DIR" >/dev/null 2>&1 || :; fi\n'
uninstall_text = uninstall_text.replace(old_stop, "")
if "# Stop Yulong ad schedule before uninstall cleanup." not in uninstall_text:
    marker = "PG=/data/adb/privacyguard\n"
    if marker not in uninstall_text:
        raise SystemExit("FX uninstall PG state anchor missing for Yulong schedule shutdown")
    stop_block = '''# Stop Yulong ad schedule before uninstall cleanup.
if [ -x "$MODDIR/scripts/yulong-ad-schedule.sh" ]; then
  if ! sh "$MODDIR/scripts/yulong-ad-schedule.sh" stop "$MODDIR" "$PG" uninstall >/dev/null 2>&1; then
    PG_KEEP_DATA=1
    _mitm_warn "could not confirm stopping Yulong ad schedule watcher; preserving $PG and aborting uninstall"
    exit 1
  fi
elif [ -s "$PG/yulong-ad-schedule.pid" ]; then
  PG_KEEP_DATA=1
  _mitm_warn "Yulong ad schedule PID record exists but its script is missing; preserving $PG and aborting uninstall"
  exit 1
fi
'''
    uninstall_text = uninstall_text.replace(marker, marker + stop_block, 1)
    uninstall.write_text(uninstall_text, encoding="utf-8")
    uninstall.chmod(0o755)
