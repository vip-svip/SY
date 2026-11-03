#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
CONTROL="$ROOT/scripts/yulong-ad-control.sh"
[ -s "$CONTROL" ] || { echo "FAIL: Yulong control adapter missing" >&2; exit 1; }
sh -n "$CONTROL" || { echo "FAIL: Yulong control adapter shell syntax invalid" >&2; exit 1; }

python3 - "$CONTROL" <<'PY'
from pathlib import Path
import re
import sys

source = Path(sys.argv[1]).read_text(encoding="utf-8")
required = {
    "private default umask": "set -eu\numask 077",
    "unique rule candidate": 'mktemp "$CONF.yulong-rule.XXXXXX"',
    "unique block candidate": 'mktemp "$CONF.yulong-block.XXXXXX"',
    "unique transaction rollback": 'mktemp "$CONF.yulong-ad-rollback.XXXXXX"',
    "unique transaction restore": 'mktemp "$CONF.yulong-ad-restore.XXXXXX"',
    "unique DNS candidate": 'mktemp "$CONF.yulong-dns.XXXXXX"',
    "unique DNS removal candidate": 'mktemp "$CONF.yulong-dns-remove.XXXXXX"',
    "unique DNS response candidate": 'mktemp "$CONF.yulong-dns-response.XXXXXX"',
    "unique VPN DNS candidate": 'mktemp "$CONF.yulong-vpn-dns.XXXXXX"',
    "unique schedule candidate": 'mktemp "$file.tmp.XXXXXX"',
    "unique schedule backup": 'mktemp "$file.rollback.XXXXXX"',
    "unique schedule restore": 'mktemp "$file.restore.XXXXXX"',
    "candidate file mode": 'chmod 600 "$tmp"',
    "atomic settings replacement": 'mv -f "$tmp" "$CONF"',
    "shared cleanup handler": "trap '_yad_cleanup' 0",
    "schedule lock is registered": "_yad_schedule_lock=$lock",
    "control lock is registered": "_yad_control_lock=$lock",
    "cache lock is registered": "_yad_cache_lock=$lock",
    "schedule candidate is registered": "_yad_schedule_tmp=$(mktemp",
    "schedule backup is registered": "_yad_schedule_backup=$(mktemp",
}
for label, needle in required.items():
    if needle not in source:
        raise SystemExit(f"FAIL: {label}: missing {needle!r}")

bad_patterns = (
    r'tmp=\$CONF\.yulong-[^\r\n]*\.\$\$',
    r'(?:backup|restore)=\$CONF\.yulong-[^\r\n]*\.\$',
    r'tmp="\$CONF\.yulong-[^\r\n]*\.\$"',
)
for pattern in bad_patterns:
    if re.search(pattern, source):
        raise SystemExit(f"FAIL: unsafe predictable Yulong temp path remains: {pattern}")

for function_name, next_marker in (
    ("with_lock() {", "write_rule() {"),
    ("schedule_set() {", "cache_flush() {"),
    ("cache_flush() {", 'cmd="$' + '{1:-list}"'),
):
    start = source.index(function_name)
    end = source.index(next_marker, start + len(function_name))
    block = source[start:end]
    if "trap " in block:
        raise SystemExit(f"FAIL: {function_name[:-3]} overrides the shared cleanup trap")

if source.count("trap '_yad_cleanup' 0") != 1:
    raise SystemExit("FAIL: expected exactly one process-wide cleanup trap")
for candidate in (
    "_yad_conf_tmp=$tmp",
    "_yad_transaction_backup=",
    "_yad_transaction_restore=",
):
    if candidate not in source:
        raise SystemExit(f"FAIL: cleanup handler does not track {candidate}")
print("PASS: Yulong config transactions use unique private candidates and one composable lock/temp cleanup trap")
PY

T=$(mktemp -d "/tmp/fx-yulong-temp-XXXXXX")
trap 'rm -rf "$T"' EXIT HUP INT TERM
umask 077
a=$(mktemp "$T/settings.conf.yulong-rule.XXXXXX")
b=$(mktemp "$T/settings.conf.yulong-rule.XXXXXX")
[ "$a" != "$b" ] || { echo "FAIL: mktemp reused a live candidate name" >&2; exit 1; }
[ "$(dirname "$a")" = "$T" ] && [ "$(dirname "$b")" = "$T" ] || {
  echo "FAIL: candidate is not created beside its destination" >&2
  exit 1
}
[ "$(stat -c %a "$a")" = 600 ] && [ "$(stat -c %a "$b")" = 600 ] || {
  echo "FAIL: umask 077 did not produce mode 0600 temp files" >&2
  exit 1
}
echo "PASS: Yulong mktemp candidates are unique, same-directory and mode 0600"
