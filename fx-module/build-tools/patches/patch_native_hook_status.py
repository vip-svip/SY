#!/usr/bin/env python3
"""Expose the authoritative native FX Hook overlay in status.sh JSON."""
from pathlib import Path
import sys

root = Path(sys.argv[1] if len(sys.argv) > 1 else "fx-module")
status = root / "scripts/status.sh"
if not status.is_file():
    raise SystemExit("FX status.sh is missing: " + str(status))
source = status.read_text(encoding="utf-8")

block = r'''# Read the authoritative native FX Hook overlays written by the unified APK.
# Legacy settings.conf fields below are retained for older clients only.
HOOK_NATIVE_CONFIG_FOUND=0
HOOK_NATIVE_CONFIG_USERS=0
HOOK_NATIVE_PRIVACY_ENABLED=0
HOOK_NATIVE_PRIVACY_TARGETS=0
HOOK_NATIVE_WIFI_SCAN_ENABLED=0
HOOK_NATIVE_WIFI_SCAN_TARGETS=0
HOOK_NATIVE_NOTIFICATION_LISTEN_ENABLED=0
HOOK_NATIVE_NOTIFICATION_LISTEN_TARGETS=0
HOOK_NATIVE_NOTIFICATION_PERMISSION_HIDE_ENABLED=0
HOOK_NATIVE_NOTIFICATION_PERMISSION_HIDE_TARGETS=0
HOOK_NATIVE_CLIPBOARD_ISOLATE_ENABLED=0
HOOK_NATIVE_CLIPBOARD_ISOLATE_TARGETS=0
HOOK_NATIVE_MEMBER_DIAG_ENABLED=0
HOOK_NATIVE_MEMBER_DIAG_TARGETS=0
HOOK_NATIVE_TARGETS=0
for _native_cfg in "$PG"/fx-native-hook-targets-*.conf; do
  [ -f "$_native_cfg" ] && [ ! -L "$_native_cfg" ] && [ -s "$_native_cfg" ] || continue
  if ! grep -qx 'schema_version=1' "$_native_cfg" ||
     ! grep -qx '^\[list:targets\]$' "$_native_cfg"; then
    continue
  fi
  HOOK_NATIVE_CONFIG_FOUND=1
  HOOK_NATIVE_CONFIG_USERS=$((HOOK_NATIVE_CONFIG_USERS + 1))
  _native_flags=$(awk -F= '
    $1=="privacy_enabled" {p=$2}
    $1=="wifi_scan_enabled" {w=$2}
    $1=="notification_listen_enabled" {n=$2}
    $1=="notification_permission_hide_enabled" {np=$2}
    $1=="clipboard_isolate_enabled" {c=$2}
    END {printf "%s|%s|%s|%s|%s", p,w,n,np,c}
  ' "$_native_cfg")
  _native_privacy=$(printf '%s' "$_native_flags" | cut -d '|' -f1)
  _native_wifi=$(printf '%s' "$_native_flags" | cut -d '|' -f2)
  _native_notif=$(printf '%s' "$_native_flags" | cut -d '|' -f3)
  _native_notif_perm=$(printf '%s' "$_native_flags" | cut -d '|' -f4)
  _native_clipboard=$(printf '%s' "$_native_flags" | cut -d '|' -f5)
  [ "$_native_privacy" = 1 ] && HOOK_NATIVE_PRIVACY_ENABLED=1
  [ "$_native_wifi" = 1 ] && HOOK_NATIVE_WIFI_SCAN_ENABLED=1
  [ "$_native_notif" = 1 ] && HOOK_NATIVE_NOTIFICATION_LISTEN_ENABLED=1
  [ "$_native_notif_perm" = 1 ] && HOOK_NATIVE_NOTIFICATION_PERMISSION_HIDE_ENABLED=1
  [ "$_native_clipboard" = 1 ] && HOOK_NATIVE_CLIPBOARD_ISOLATE_ENABLED=1
  _native_counts=$(awk '
    /^\[list:targets\]$/ {inlist=1; next}
    /^\[/ {if (inlist) exit}
    inlist && NF {
      targets++
      if ($0 ~ /(^|,)member_diag=1(,|$)/) member++
      if ($0 ~ /(^|,)(privacy=1|exif_strip=1|clipboard_read_block=1|clipboard_isolate=1|sensor_accel=1|sensor_gyro=1|sensor_light=1|sensor_magnet=1|sensor_pressure=1|sensor_prox=1|sensor_rate_limit=1|mic_silence=1|camera_access_block=1|location_access_block=1|mic_access_block=1|media_store_query_block=1)(,|$)/) privacy++
      if ($0 ~ /(^|,)wifi_scan_block=1(,|$)/) wifi++
      if ($0 ~ /(^|,)notification_listen_block=1(,|$)/) notif++
      if ($0 ~ /(^|,)notification_permission_hide=1(,|$)/) notif_perm++
      if ($0 ~ /(^|,)clipboard_isolate=1(,|$)/) clipboard++
    }
    END {printf "%d|%d|%d|%d|%d|%d|%d", targets,member,privacy,wifi,notif,notif_perm,clipboard}
  ' "$_native_cfg")
  HOOK_NATIVE_TARGETS=$((HOOK_NATIVE_TARGETS + $(printf '%s' "$_native_counts" | cut -d '|' -f1)))
  HOOK_NATIVE_MEMBER_DIAG_TARGETS=$((HOOK_NATIVE_MEMBER_DIAG_TARGETS + $(printf '%s' "$_native_counts" | cut -d '|' -f2)))
  HOOK_NATIVE_PRIVACY_TARGETS=$((HOOK_NATIVE_PRIVACY_TARGETS + $(printf '%s' "$_native_counts" | cut -d '|' -f3)))
  HOOK_NATIVE_WIFI_SCAN_TARGETS=$((HOOK_NATIVE_WIFI_SCAN_TARGETS + $(printf '%s' "$_native_counts" | cut -d '|' -f4)))
  HOOK_NATIVE_NOTIFICATION_LISTEN_TARGETS=$((HOOK_NATIVE_NOTIFICATION_LISTEN_TARGETS + $(printf '%s' "$_native_counts" | cut -d '|' -f5)))
  HOOK_NATIVE_NOTIFICATION_PERMISSION_HIDE_TARGETS=$((HOOK_NATIVE_NOTIFICATION_PERMISSION_HIDE_TARGETS + $(printf '%s' "$_native_counts" | cut -d '|' -f6)))
  HOOK_NATIVE_CLIPBOARD_ISOLATE_TARGETS=$((HOOK_NATIVE_CLIPBOARD_ISOLATE_TARGETS + $(printf '%s' "$_native_counts" | cut -d '|' -f7)))
done
[ "$HOOK_NATIVE_MEMBER_DIAG_TARGETS" -gt 0 ] && HOOK_NATIVE_MEMBER_DIAG_ENABLED=1
'''
if "HOOK_NATIVE_CONFIG_FOUND=0" not in source:
    anchor = "# VPN 状态（无配置文件时给空态默认值）"
    if source.count(anchor) != 1:
        raise SystemExit("status.sh native Hook insertion anchor changed")
    source = source.replace(anchor, block + "\n" + anchor, 1)

old_json = ',"hook_remote_status":"%s","hook_remote_targets":%s}\\n\' \\\n'
new_json = ',"hook_remote_status":"%s","hook_remote_targets":%s,"hook_native_config_found":"%s","hook_native_config_users":%s,"hook_native_privacy_enabled":"%s","hook_native_privacy_targets":%s,"hook_native_wifi_scan_enabled":"%s","hook_native_wifi_scan_targets":%s,"hook_native_notification_listen_enabled":"%s","hook_native_notification_listen_targets":%s,"hook_native_notification_permission_hide_enabled":"%s","hook_native_notification_permission_hide_targets":%s,"hook_native_clipboard_isolate_enabled":"%s","hook_native_clipboard_isolate_targets":%s,"hook_native_member_diag_enabled":"%s","hook_native_member_diag_targets":%s,"hook_native_targets":%s}\\n\' \\\n'
if '"hook_native_config_found"' not in source:
    if source.count(old_json) != 1:
        raise SystemExit("status.sh JSON format anchor changed")
    source = source.replace(old_json, new_json, 1)

old_args = '  "$HOOK_REMOTE_STATUS" \\\n  "$HOOK_REMOTE_TARGETS"\n'
new_args = '''  "$HOOK_REMOTE_STATUS" \\
  "$HOOK_REMOTE_TARGETS" \\
  "$HOOK_NATIVE_CONFIG_FOUND" \\
  "$HOOK_NATIVE_CONFIG_USERS" \\
  "$HOOK_NATIVE_PRIVACY_ENABLED" \\
  "$HOOK_NATIVE_PRIVACY_TARGETS" \\
  "$HOOK_NATIVE_WIFI_SCAN_ENABLED" \\
  "$HOOK_NATIVE_WIFI_SCAN_TARGETS" \\
  "$HOOK_NATIVE_NOTIFICATION_LISTEN_ENABLED" \\
  "$HOOK_NATIVE_NOTIFICATION_LISTEN_TARGETS" \\
  "$HOOK_NATIVE_NOTIFICATION_PERMISSION_HIDE_ENABLED" \\
  "$HOOK_NATIVE_NOTIFICATION_PERMISSION_HIDE_TARGETS" \\
  "$HOOK_NATIVE_CLIPBOARD_ISOLATE_ENABLED" \\
  "$HOOK_NATIVE_CLIPBOARD_ISOLATE_TARGETS" \\
  "$HOOK_NATIVE_MEMBER_DIAG_ENABLED" \\
  "$HOOK_NATIVE_MEMBER_DIAG_TARGETS" \\
  "$HOOK_NATIVE_TARGETS"
'''
if '"$HOOK_NATIVE_TARGETS"' not in source:
    if source.count(old_args) != 1:
        raise SystemExit("status.sh JSON argument list anchor changed")
    source = source.replace(old_args, new_args, 1)

required = (
    '"hook_native_config_found"',
    '"hook_native_privacy_enabled"',
    '"hook_native_wifi_scan_enabled"',
    '"hook_native_notification_listen_enabled"',
    '"hook_native_notification_permission_hide_enabled"',
    '"hook_native_clipboard_isolate_enabled"',
    '"hook_native_member_diag_enabled"',
)
missing = [field for field in required if field not in source]
if missing:
    raise SystemExit("native Hook status JSON incomplete: " + ", ".join(missing))

status.write_text(source, encoding="utf-8")
print("Added truthful per-user native Hook overlay status to status.sh JSON.")
