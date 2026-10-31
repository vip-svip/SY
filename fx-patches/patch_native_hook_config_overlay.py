#!/usr/bin/env python3
"""Keep native Hook APP config authoritative when apply.sh regenerates Remote Files."""
from pathlib import Path
import sys

root = Path(sys.argv[1] if len(sys.argv) > 1 else "fx-module")
generator = root / "scripts/gen_xposed_conf.sh"
if not generator.is_file():
    raise SystemExit("FX Remote Files generator not found")

source = generator.read_text(encoding="utf-8")
if "fx-native-hook-targets-$_gxc_uid.conf" in source:
    print("Native Hook config overlay already applied.")
    raise SystemExit(0)

start = '''    {
      # Modern unified Hook schema. Keep xposed.conf in its legacy format for
'''
end = '''    } > "$_gxc_tmp" 2>/dev/null || { rm -f "$_gxc_tmp"; _GXC_ALL_OK=0; continue; }'''
if source.count(start) != 1 or source.count(end) != 1:
    raise SystemExit("Remote Files generation block changed; refusing unsafe overlay patch")

prefix = '''    _GXC_NATIVE_CONFIG="$PG/fx-native-hook-targets-$_gxc_uid.conf"
    if [ -e "$_GXC_NATIVE_CONFIG" ]; then
      _GXC_NATIVE_SIZE=$(wc -c < "$_GXC_NATIVE_CONFIG" 2>/dev/null | tr -d ' ')
      _GXC_NATIVE_LINES=$(wc -l < "$_GXC_NATIVE_CONFIG" 2>/dev/null | tr -d ' ')
      if [ ! -f "$_GXC_NATIVE_CONFIG" ] || [ -L "$_GXC_NATIVE_CONFIG" ] ||
         [ ! -s "$_GXC_NATIVE_CONFIG" ] || [ "${_GXC_NATIVE_SIZE:-0}" -gt 65536 ] ||
         [ "${_GXC_NATIVE_LINES:-0}" -gt 1000 ] ||
         ! grep -q '^schema_version=1$' "$_GXC_NATIVE_CONFIG" ||
         ! grep -q '^ads_enabled=[01]$' "$_GXC_NATIVE_CONFIG" ||
         ! grep -q '^privacy_enabled=[01]$' "$_GXC_NATIVE_CONFIG" ||
         ! grep -q '^\\[list:targets\\]$' "$_GXC_NATIVE_CONFIG"; then
        echo "gen_xposed_conf: native Hook overlay invalid for user $_gxc_uid; refusing to overwrite it with legacy config" >&2
        _GXC_ALL_OK=0
        continue
      fi
      if ! cp "$_GXC_NATIVE_CONFIG" "$_gxc_tmp" 2>/dev/null || [ ! -s "$_gxc_tmp" ]; then
        echo "gen_xposed_conf: native Hook overlay copy failed for user $_gxc_uid" >&2
        rm -f "$_gxc_tmp" 2>/dev/null
        _GXC_ALL_OK=0
        continue
      fi
      _GXC_REMOTE_ENABLED=$(awk '/^\\[/{exit} /^ads_enabled=/{sub(/^ads_enabled=/, ""); print; exit}' "$_gxc_tmp" | tr -d ' \\r')
      _GXC_REMOTE_TARGETS=$(awk '/^\\[list:targets\\]$/ {inlist=1; next} /^\\[/ {if (inlist) exit} inlist && NF {n++} END {print n+0}' "$_gxc_tmp" | tr -d ' ')
    else
'''
source = source.replace(start, prefix + start, 1)
source = source.replace(end, end + '\n    fi', 1)
generator.write_text(source, encoding="utf-8")
print("Applied per-user native Hook Remote Files overlay.")
