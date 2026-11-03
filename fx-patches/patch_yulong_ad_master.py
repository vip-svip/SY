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
u2,n=pattern.subn(replacement,u,count=1)
if n!=1: raise SystemExit("pg_list_enabled function anchor missing")
util.write_text(u2,encoding="utf-8")
d=default.read_text(encoding="utf-8")
if "yulong_ad_filter_enabled=" not in d:
    marker="hook_ads_enabled=0\n"
    if marker not in d: raise SystemExit("default.conf hook_ads_enabled anchor missing")
    d=d.replace(marker,marker+"# Independent Yulong/FX ad filter master; 0 suspends [list:rule] only.\nyulong_ad_filter_enabled=1\n",1)
    default.write_text(d,encoding="utf-8")

# Stage the weekly scheduler into the restored module.
repo_root = Path(__file__).resolve().parent.parent
scheduler_source = repo_root / "scripts/yulong-ad-schedule.sh"
scheduler_target = root / "scripts/yulong-ad-schedule.sh"
if not scheduler_source.is_file():
    raise SystemExit("Yulong weekly schedule source is missing")
scheduler_target.write_text(scheduler_source.read_text(encoding="utf-8"), encoding="utf-8")
scheduler_target.chmod(0o755)

# The schedule gates only Yulong ad rules and never FX's 96110 or user Hosts lists.
u = util.read_text(encoding="utf-8")
needle = '''  if [ "$1" = "rule" ] && [ "$(pg_get yulong_ad_filter_enabled 1)" != "1" ]; then return 0; fi'''
schedule_gate = needle + '''
  if [ "$1" = "rule" ] && [ "$(pg_get yulong_ad_schedule_active 1)" != "1" ]; then return 0; fi'''
if "yulong_ad_schedule_active" not in u:
    if needle not in u:
        raise SystemExit("Yulong ad master gate anchor missing for schedule extension")
    u = u.replace(needle, schedule_gate, 1)
    util.write_text(u, encoding="utf-8")

if "yulong_ad_schedule_active=" not in d:
    d += "\\n# Weekly Yulong ad schedule runtime state (1=inside schedule, default enabled).\\nyulong_ad_schedule_active=1\\n"
    default.write_text(d, encoding="utf-8")

service = root / "service.sh"
service_marker = 'if [ -x "$MODDIR/scripts/jsruntime/scheduler.sh" ]; then'
service_insert = '''# Restore the Yulong weekly schedule after the main FX apply.
if [ -x "$MODDIR/scripts/yulong-ad-schedule.sh" ]; then
  sh "$MODDIR/scripts/yulong-ad-schedule.sh" start "$MODDIR" "$PG" >> "$PG/boot.log" 2>&1 || :
fi
'''
if service.is_file():
    service_text = service.read_text(encoding="utf-8")
    if "yulong-ad-schedule.sh" not in service_text:
        if service_marker not in service_text:
            raise SystemExit("FX service scheduler insertion anchor missing")
        service_text = service_text.replace(service_marker, service_insert + service_marker, 1)
        service.write_text(service_text, encoding="utf-8")
        service.chmod(0o755)

uninstall = root / "uninstall.sh"
if uninstall.is_file():
    uninstall_text = uninstall.read_text(encoding="utf-8")
    if "yulong-ad-schedule.sh" not in uninstall_text:
        marker = 'STATE_DIR=/data/adb/privacyguard\\n'
        if marker in uninstall_text:
            uninstall_text = uninstall_text.replace(
                marker,
                marker + 'if [ -x "$MODDIR/scripts/yulong-ad-schedule.sh" ]; then sh "$MODDIR/scripts/yulong-ad-schedule.sh" stop "$MODDIR" "$STATE_DIR" >/dev/null 2>&1 || :; fi\\n',
                1
            )
            uninstall.write_text(uninstall_text, encoding="utf-8")
            uninstall.chmod(0o755)
