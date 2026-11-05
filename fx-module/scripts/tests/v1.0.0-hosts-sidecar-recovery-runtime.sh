#!/system/bin/sh
# Runtime tests for the extracted POSIX-shell recovery function.
# Runs in a disposable temp directory; does not touch device or repo caches.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
A="$ROOT/scripts/apply.sh"
T=$(mktemp -d "${TMPDIR:-/tmp}/fx-sidecar-recovery.XXXXXX")
trap 'rm -rf "$T"' EXIT HUP INT TERM
awk '/^pg_hosts_sidecar_recover\(\) \{/ { active=1 } active { print } active && /^\}$/ { exit }' "$A" > "$T/recover.sh"
[ -s "$T/recover.sh" ] || { echo "FAIL: recovery function not extracted" >&2; exit 1; }

setup() {
  PG="$T/pg"
  rm -rf "$PG"
  mkdir -p "$PG/cache"
  # shellcheck disable=SC1090
  . "$T/recover.sh"
}
pg_log() { :; }
write_marker() {
  cat > "$PG/cache/sidecar.txn" <<EOF
pid=123
had_ip=$1
had_wlexc=$2
ip_backup=$PG/cache/subnet-ips.list.rollback.123
wlexc_backup=$PG/cache/wlexc.rollback.123
phase=$3
EOF
}

# Active transaction restores both prior sidecars and removes marker only on success.
setup
printf 'old-ip\n' > "$PG/cache/subnet-ips.list.rollback.123"
printf 'old-wl\n' > "$PG/cache/wlexc.rollback.123"
printf 'new-ip\n' > "$PG/cache/subnet-ips.list"
printf 'new-wl\n' > "$PG/cache/wlexc.tmp"
write_marker 1 1 active
pg_hosts_sidecar_recover
grep -qx 'old-ip' "$PG/cache/subnet-ips.list"
grep -qx 'old-wl' "$PG/cache/wlexc.tmp"
[ ! -e "$PG/cache/sidecar.txn" ] || { echo "FAIL: active marker remains after successful recovery" >&2; exit 1; }

# Missing backup must fail closed and preserve the marker.
setup
printf 'new-ip\n' > "$PG/cache/subnet-ips.list"
printf 'new-wl\n' > "$PG/cache/wlexc.tmp"
write_marker 1 1 active
if pg_hosts_sidecar_recover; then echo "FAIL: missing backup accepted" >&2; exit 1; fi
[ -f "$PG/cache/sidecar.txn" ] || { echo "FAIL: marker deleted on recovery failure" >&2; exit 1; }

# Inject a one-shot failure while restoring the second sidecar. The marker and
# both backups must survive, then a retry must complete the same recovery.
setup
printf 'old-ip\n' > "$PG/cache/subnet-ips.list.rollback.123"
printf 'old-wl\n' > "$PG/cache/wlexc.rollback.123"
printf 'new-ip\n' > "$PG/cache/subnet-ips.list"
printf 'new-wl\n' > "$PG/cache/wlexc.tmp"
write_marker 1 1 active
mv() {
  case "$*" in
    *"$PG/cache/wlexc.tmp") return 1 ;;
    *) command mv "$@" ;;
  esac
}
if pg_hosts_sidecar_recover; then echo "FAIL: injected second-sidecar failure ignored" >&2; exit 1; fi
[ -f "$PG/cache/sidecar.txn" ] || { echo "FAIL: marker lost after partial recovery" >&2; exit 1; }
[ -f "$PG/cache/subnet-ips.list.rollback.123" ] || { echo "FAIL: IP backup lost after partial recovery" >&2; exit 1; }
[ -f "$PG/cache/wlexc.rollback.123" ] || { echo "FAIL: whitelist backup lost after partial recovery" >&2; exit 1; }
unset -f mv
pg_hosts_sidecar_recover
grep -qx 'old-ip' "$PG/cache/subnet-ips.list"
grep -qx 'old-wl' "$PG/cache/wlexc.tmp"
[ ! -e "$PG/cache/sidecar.txn" ] || { echo "FAIL: retry left marker behind" >&2; exit 1; }

# Invalid phase must be rejected without mutating caches.
setup
printf 'keep-ip\n' > "$PG/cache/subnet-ips.list"
printf 'keep-wl\n' > "$PG/cache/wlexc.tmp"
write_marker 0 0 invalid
if pg_hosts_sidecar_recover; then echo "FAIL: invalid phase accepted" >&2; exit 1; fi
grep -qx 'keep-ip' "$PG/cache/subnet-ips.list"
grep -qx 'keep-wl' "$PG/cache/wlexc.tmp"
[ -f "$PG/cache/sidecar.txn" ] || { echo "FAIL: invalid marker removed" >&2; exit 1; }

# Committed transaction keeps the new generation and cleans backups/marker.
setup
printf 'new-ip\n' > "$PG/cache/subnet-ips.list"
printf 'new-wl\n' > "$PG/cache/wlexc.tmp"
printf 'old-ip\n' > "$PG/cache/subnet-ips.list.rollback.123"
printf 'old-wl\n' > "$PG/cache/wlexc.rollback.123"
write_marker 1 1 committed
pg_hosts_sidecar_recover
grep -qx 'new-ip' "$PG/cache/subnet-ips.list"
grep -qx 'new-wl' "$PG/cache/wlexc.tmp"
[ ! -e "$PG/cache/sidecar.txn" ] || { echo "FAIL: committed marker not cleaned" >&2; exit 1; }
[ ! -e "$PG/cache/subnet-ips.list.rollback.123" ] || { echo "FAIL: committed backup not cleaned" >&2; exit 1; }

echo 'FX Hosts sidecar recovery runtime tests: PASS'
