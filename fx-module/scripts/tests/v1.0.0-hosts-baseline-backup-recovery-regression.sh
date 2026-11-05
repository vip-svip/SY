#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
T=$(mktemp -d "${TMPDIR:-/tmp}/fx-host-base.XXXXXX")
trap 'rm -rf "$T"' EXIT HUP INT TERM
export PG="$T/pg" CONF="$T/settings.conf" MODDIR="$ROOT"
mkdir -p "$PG/backup" "$PG/cache"
: > "$CONF"
printf '127.0.0.1 localhost
::1 localhost ip6-localhost
192.0.2.44 oem-internal.example
' > "$PG/backup/hosts.orig"
. "$ROOT/scripts/util.sh"
# The live hosts target is hidden by our bind mount; never copy generated /system
# content in this state, recover the first-install OEM snapshot atomically instead.
pg_hosts_mount_state() { printf 'owned\n'; }
pg_capture_system_hosts_base
grep -Fxq '192.0.2.44 oem-internal.example' "$PG/cache/system-hosts.base"
grep -Fxq '::1 localhost ip6-localhost' "$PG/cache/system-hosts.base"
grep -Fq 'restored original system hosts baseline from first-install backup' "$PG/apply.log"
# A generated overlay must never be accepted as an OEM baseline.
rm -f "$PG/cache/system-hosts.base"
printf '# FX-only hosts overlay (generated test)\n0.0.0.0 should-not-recurse.example\n' > "$PG/backup/hosts.orig"
if pg_restore_system_hosts_base_from_backup; then
  echo 'FAIL: generated hosts overlay accepted as OEM baseline' >&2
  exit 1
fi
test ! -e "$PG/cache/system-hosts.base"
echo 'PASS: original hosts baseline recovered from backup; generated baseline rejected'
