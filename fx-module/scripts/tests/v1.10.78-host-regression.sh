#!/bin/sh
# Reproducible host-side fault injection; does not emulate Android kernel mounts.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
. "$ROOT/scripts/certcopy.sh"
. "$ROOT/scripts/certmarker.sh"
mkdir -p "$TMP/src" "$TMP/dest" "$TMP/bin" "$TMP/overlay"
printf 'cert-one\n' > "$TMP/src/11111111.0"
ca_copy_submodule_certs "$TMP/src" "$TMP/dest" test
[ "$(cat "$TMP/dest/11111111.0")" = cert-one ]
mkdir -p "$TMP/empty"
if ca_copy_submodule_certs "$TMP/empty" "$TMP/dest" empty 2>/dev/null; then echo 'FAIL empty cert source accepted' >&2; exit 1; fi
cat > "$TMP/bin/cp" <<'CP'
#!/bin/sh
exit 73
CP
chmod +x "$TMP/bin/cp"
mkdir -p "$TMP/dest-fail"
if PATH="$TMP/bin:$PATH" ca_copy_submodule_certs "$TMP/src" "$TMP/dest-fail" injected 2>/dev/null; then echo 'FAIL cp failure accepted' >&2; exit 1; fi
# Fake mount table state and mount/umount; no kernel mount is performed.
STATE="$TMP/mounted"
export STATE
cat > "$TMP/bin/mount" <<'MOUNT'
#!/bin/sh
if [ "$1" = --bind ]; then printf '%s\n' "$3" > "$STATE"; exit 0; fi
if [ -s "$STATE" ]; then printf 'overlay on %s type none (rw,bind)\n' "$(cat "$STATE")"; fi
exit 0
MOUNT
cat > "$TMP/bin/umount" <<'UMOUNT'
#!/bin/sh
[ "${FAIL_UMOUNT:-0}" = 1 ] && exit 16
rm -f "$STATE"
exit 0
UMOUNT
cat > "$TMP/bin/mv" <<'MV'
#!/bin/sh
case "$*" in *'.mounted.tmp.'*'.mounted'*) exit 74 ;; esac
exec /bin/mv "$@"
MV
chmod +x "$TMP/bin/mount" "$TMP/bin/umount" "$TMP/bin/mv"
# Marker commit failure + unmount failure must preserve overlay source.
PATH="$TMP/bin:$PATH" mount --bind "$TMP/overlay" "$TMP/target"
if PATH="$TMP/bin:$PATH" FAIL_UMOUNT=1 ca_commit_mount_marker "$TMP/target.mounted" "$TMP/target" "$TMP/overlay" 2>/dev/null; then echo 'FAIL marker failure accepted' >&2; exit 1; fi
[ -d "$TMP/overlay" ] && [ -s "$STATE" ] || { echo 'FAIL live mount source not preserved' >&2; exit 1; }
# Marker commit failure + successful detach may safely remove temporary overlay.
PATH="$TMP/bin:$PATH" umount "$TMP/target"
PATH="$TMP/bin:$PATH" mount --bind "$TMP/overlay" "$TMP/target"
if PATH="$TMP/bin:$PATH" ca_commit_mount_marker "$TMP/target.mounted" "$TMP/target" "$TMP/overlay" 2>/dev/null; then echo 'FAIL marker failure accepted on detach path' >&2; exit 1; fi
[ ! -d "$TMP/overlay" ] && [ ! -s "$STATE" ] || { echo 'FAIL detached overlay cleanup incorrect' >&2; exit 1; }
# Transaction source contracts: durable marker before mutation, recovery under lock,
# and no marker deletion on restore/runtime failure.
grep -q 'vpn-sub crash recovery' "$ROOT/scripts/apply.sh"
grep -q 'marker/backup retained' "$ROOT/scripts/apply.sh"
grep -q 'network rules still require normal apply reconciliation' "$ROOT/scripts/apply.sh"
python3 - "$ROOT/scripts/apply.sh" <<'PY'
import sys
s=open(sys.argv[1]).read()
backup=s.index('cp "$CONF" "$PG_SUB_TXN_BACKUP"')
commit=s.index('mv -f "$_pg_marker_tmp" "$PG_SUB_TXN_MARKER"')
assert backup < commit < s.index('PG_SUB_TXN_ACTIVE=1', commit)
assert 'vpn-sub crash recovery: stale transaction marker found' in s
crash=s[s.index('if [ "$_pg_crash_ok" = 1 ]; then'):s.index('network rules still require normal apply reconciliation')]
assert crash.index('rm -f "$PG_SUB_TXN_MARKER"') < crash.index('rm -f "$_pg_crash_bak"')
assert 'backup cleanup incomplete; orphan backup retained for diagnosis' in crash
PY
# WebUI must remain byte-identical to prior version is checked by packaging workflow.
echo 'PASS: cert copy failure injection, mount-marker publication/unmount failure injection, transaction recovery assertions'
