#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
T=$(mktemp -d "${TMPDIR:-/tmp}/fx-host-mount.XXXXXX")
trap 'rm -rf "$T"' EXIT HUP INT TERM
PG="$T/pg" CONF="$T/settings.conf" MODDIR="$ROOT" sh -c '
  . "$MODDIR/scripts/util.sh"
  own="/data/adb/modules/FX/data/hosts on /system/etc/hosts type none (rw,bind)"
  foreign="/data/adb/modules/Other/hosts on /system/etc/hosts type none (rw,bind)"
  [ "$(pg_hosts_mount_state_from_text "$PG/hosts" /system/etc/hosts "$own")" = owned ]
  [ "$(pg_hosts_mount_state_from_text "$PG/hosts" /system/etc/hosts "$foreign")" = foreign ]
  [ "$(pg_hosts_mount_state_from_text "$PG/hosts" /system/etc/hosts "/dev/block/dm-1 on /system type ext4 (ro,seclabel)")" = none ]
' || { echo 'FAIL: hosts mount ownership classification' >&2; exit 1; }
# Enabling FX must not layer over another module's mount, and disabling FX must not unmount it.
grep -Fq 'foreign)' "$ROOT/scripts/apply.sh"
grep -Fq 'foreign /system/etc/hosts mount preserved' "$ROOT/scripts/apply.sh"
awk '/^else$/ && NR>1300 {branch=1} branch && /umount \/system\/etc\/hosts/ { if (seen_state!=1) bad=1 } branch && /_hosts_mount_state=/ { seen_state=1 } /^fi$/ && branch { exit bad }' "$ROOT/scripts/apply.sh" >/dev/null || {
  echo 'FAIL: unconditional hosts unmount detected in disable branch' >&2; exit 1;
}
# Exercise the real transaction helper against a foreign mount, not just the classifier.
mkdir -p "$T/pg/cache" "$T/bin"
export PG="$T/pg" CONF="$T/settings.conf" MODDIR="$ROOT"
: > "$CONF"
printf '127.0.0.1 old.example\n' > "$PG/hosts"
printf '0.0.0.0 candidate.example\n' > "$PG/cache/candidate"
. "$ROOT/scripts/util.sh"
mount() { printf '/data/adb/modules/Other/hosts on /system/etc/hosts type none (rw,bind)\n'; return 0; }
umount() { : > "$PG/cache/foreign-umount-was-called"; return 1; }
if pg_commit_hosts_candidate "$PG/cache/candidate"; then
  echo 'FAIL: hosts transaction replaced source while a foreign mount owns target' >&2
  exit 1
fi
grep -Fxq '127.0.0.1 old.example' "$PG/hosts"
grep -Fxq '0.0.0.0 candidate.example' "$PG/cache/candidate"
test ! -e "$PG/cache/foreign-umount-was-called"
echo 'PASS: FX hosts mount ownership is three-state; foreign hosts mounts are preserved'
