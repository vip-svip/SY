#!/usr/bin/env python3
from pathlib import Path
import sys

if len(sys.argv) != 2:
    raise SystemExit("usage: patch_yulong_profiles.py FX_MODULE_ROOT")

module = Path(sys.argv[1]).resolve()
source_root = Path(__file__).resolve().parents[1]
sources = {
    "yulong-profiles.sh": source_root / "scripts" / "yulong-profiles.sh",
    "yulong-profile-schedule.sh": source_root / "scripts" / "yulong-profile-schedule.sh",
}
scripts = module / "scripts"
if not (module / "module.prop").is_file():
    raise SystemExit(f"FX module.prop missing under {module}")
scripts.mkdir(parents=True, exist_ok=True)
for name, source in sources.items():
    if not source.is_file():
        raise SystemExit(f"FX profile source missing: {source}")
    destination = scripts / name
    destination.write_bytes(source.read_bytes())
    destination.chmod(0o755)

# The original Yulong profile contains two independent flags. AdGuard Home's
# provider-level Safe Search switches preserve both semantics without a second
# DNS engine or a second VpnService.
agh = scripts / "adguardhome.sh"
if not agh.is_file():
    raise SystemExit("restored FX adguardhome.sh is missing")
agh_text = agh.read_text(encoding="utf-8")
marker = "# FX_YULONG_PROFILE_SAFE_SEARCH_V1"
replacement = '''  # FX_YULONG_PROFILE_SAFE_SEARCH_V1
  safe_search:
    enabled: $_pg_safe_search_active
    bing: $_pg_safe_search_flag
    duckduckgo: $_pg_safe_search_flag
    ecosia: $_pg_safe_search_flag
    google: $_pg_safe_search_flag
    pixabay: $_pg_safe_search_flag
    yandex: $_pg_safe_search_flag
    youtube: $_pg_youtube_restricted_flag'''
old = "  safe_search:\\n    enabled: false"
if marker not in agh_text:
    if old not in agh_text:
        raise SystemExit("AdGuard Home safe_search template anchor is missing")
    agh_text = agh_text.replace(old, replacement, 1)
    querylog = '''  case "$_dns_querylog_enabled" in true) : ;; *) _dns_querylog_enabled=false ;; esac
'''
    additions = '''  case "$_dns_querylog_enabled" in true) : ;; *) _dns_querylog_enabled=false ;; esac
  _pg_safe_search_flag=$(awk -F= '$1=="yulong_safe_search_enabled" && $2=="1" {v=1} END {if(v) print "true"; else print "false"}' "$PG/settings.conf" 2>/dev/null)
  _pg_youtube_restricted_flag=$(awk -F= '$1=="yulong_youtube_restricted_mode" && $2=="1" {v=1} END {if(v) print "true"; else print "false"}' "$PG/settings.conf" 2>/dev/null)
  _pg_safe_search_active=false
  if [ "$_pg_safe_search_flag" = true ] || [ "$_pg_youtube_restricted_flag" = true ]; then
    _pg_safe_search_active=true
  fi
'''
    if querylog not in agh_text:
        raise SystemExit("AdGuard Home Safe Search state insertion anchor is missing")
    agh_text = agh_text.replace(querylog, additions, 1)
    agh.write_text(agh_text, encoding="utf-8")
    agh.chmod(0o755)
elif "_pg_youtube_restricted_flag" not in agh_text:
    raise SystemExit("Safe Search marker exists but state reader is missing; refusing partial patch")

# Restore the independent ProtectionProfile scheduler after the main FX apply.
service = module / "service.sh"
if not service.is_file():
    raise SystemExit("FX service.sh is missing")
service_text = service.read_text(encoding="utf-8")
service_marker = '# FX_YULONG_PROFILE_SCHEDULER_START_V1'
service_block = '''# FX_YULONG_PROFILE_SCHEDULER_START_V1
if [ -x "$MODDIR/scripts/yulong-profile-schedule.sh" ]; then
  sh "$MODDIR/scripts/yulong-profile-schedule.sh" start "$MODDIR" "$PG" >> "$PG/boot.log" 2>&1 || \\
    echo "[$(date '+%m-%d %H:%M:%S')] Yulong profile schedule watcher failed to start" >> "$PG/boot.log"
fi
'''
if service_marker not in service_text:
    anchor = 'if [ -x "$MODDIR/scripts/jsruntime/scheduler.sh" ]; then'
    if anchor not in service_text:
        raise SystemExit("FX service scheduler insertion anchor is missing")
    service_text = service_text.replace(anchor, service_block + anchor, 1)
    service.write_text(service_text, encoding="utf-8")
    service.chmod(0o755)

# Stop and confirm this worker before uninstall removes module/state files.
uninstall = module / "uninstall.sh"
if not uninstall.is_file():
    raise SystemExit("FX uninstall.sh is missing")
uninstall_text = uninstall.read_text(encoding="utf-8")
uninstall_marker = "# FX_YULONG_PROFILE_SCHEDULER_STOP_V1"
uninstall_block = '''# FX_YULONG_PROFILE_SCHEDULER_STOP_V1
if [ -x "$MODDIR/scripts/yulong-profile-schedule.sh" ]; then
  if ! sh "$MODDIR/scripts/yulong-profile-schedule.sh" stop "$MODDIR" "$PG" uninstall >> "$PG/yulong-profile-schedule.log" 2>&1; then
    PG_KEEP_DATA=1
    _mitm_warn "could not confirm stopping Yulong profile schedule watcher; preserving $PG and aborting uninstall"
    exit 1
  fi
elif [ -s "$PG/yulong-profile-schedule.pid" ]; then
  PG_KEEP_DATA=1
  _mitm_warn "Yulong profile schedule PID record exists but scheduler is missing; preserving $PG and aborting uninstall"
  exit 1
fi
'''
if uninstall_marker not in uninstall_text:
    anchor = "# Stop trusted Wi-Fi pause and restore its owned gate before uninstall."
    if anchor not in uninstall_text:
        raise SystemExit("FX uninstall trusted-network anchor is missing")
    uninstall_text = uninstall_text.replace(anchor, uninstall_block + anchor, 1)
    uninstall.write_text(uninstall_text, encoding="utf-8")
    uninstall.chmod(0o755)

print("Patched Yulong ProtectionProfile CRUD, independent weekly profile scheduler, and AdGuard Home Safe Search application.")
