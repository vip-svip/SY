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
