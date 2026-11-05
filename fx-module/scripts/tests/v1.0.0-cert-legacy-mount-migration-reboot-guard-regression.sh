#!/bin/sh
# A live legacy child CA module cannot safely change trust until a full reboot honors skip_mount.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
mkdir -p "$TMP/bin" "$TMP/modules/pg_mitm_ca" "$TMP/modules/pg_https_ca"
# Fake only the kernel boot ID; delegate other cat calls to the real tool.
cat > "$TMP/bin/cat" <<'CAT'
#!/bin/sh
if [ "${1-}" = /proc/sys/kernel/random/boot_id ]; then
  printf '%s\n' "${FAKE_BOOT_ID:-bootA}"
else
  exec /bin/cat "$@"
fi
CAT
chmod 755 "$TMP/bin/cat"
cat > "$TMP/modules/pg_mitm_ca/module.prop" <<'PROP'
id=pg_mitm_ca
PROP
# Extract the production helper without running certmgr's command dispatcher.
sed -n '/^pg_cert_ensure_skip_mount() {/,/^# Recover interrupted enable publication/{ /^# Recover interrupted enable publication/d; p; }' "$ROOT/scripts/certmgr.sh" > "$TMP/helper.sh"
. "$TMP/helper.sh"
SM="$TMP/modules"
MIGRATION_PENDING="$TMP/pending"
PATH="$TMP/bin:$PATH"
export SM MIGRATION_PENDING PATH
# First invocation detects the active raw-mounted legacy module, marks skip_mount, and requires reboot.
if pg_cert_ensure_skip_mount >"$TMP/out1" 2>"$TMP/err1"; then
  echo 'FAIL active legacy module migration did not require reboot' >&2; exit 1
fi
[ -f "$SM/pg_mitm_ca/skip_mount" ] || { echo 'FAIL skip_mount marker was not written' >&2; exit 1; }
[ "$(/bin/cat "$MIGRATION_PENDING")" = bootA ] || { echo 'FAIL pending reboot marker lacks current boot ID' >&2; exit 1; }
grep -q 'restart is required' "$TMP/err1" || { echo 'FAIL reboot requirement not reported' >&2; exit 1; }
# A second invocation during the same boot must still refuse trust mutation.
if pg_cert_ensure_skip_mount >"$TMP/out2" 2>"$TMP/err2"; then
  echo 'FAIL same-boot migration guard was bypassed' >&2; exit 1
fi
grep -q 'pending a full reboot' "$TMP/err2" || { echo 'FAIL pending reboot warning missing on retry' >&2; exit 1; }
# A different real boot ID allows operations after KernelSU honored skip_mount.
printf 'bootPrior\n' > "$MIGRATION_PENDING"
if ! FAKE_BOOT_ID=bootB pg_cert_ensure_skip_mount >"$TMP/out3" 2>"$TMP/err3"; then
  cat "$TMP/err3" >&2; echo 'FAIL migration guard remained blocked after reboot' >&2; exit 1
fi
# UI migration warning is cleared only by a successful trust-sync path after a different boot.
if ! FAKE_BOOT_ID=bootB pg_cert_clear_migration_pending_after_sync >"$TMP/out5" 2>"$TMP/err5"; then
  cat "$TMP/err5" >&2; echo 'FAIL migration marker did not clear after new boot' >&2; exit 1
fi
[ ! -e "$MIGRATION_PENDING" ] || { echo 'FAIL migration marker remained after verified post-reboot sync' >&2; exit 1; }
# A same-boot pending marker is never cleared.
printf 'bootB\n' > "$MIGRATION_PENDING"
if ! FAKE_BOOT_ID=bootB pg_cert_clear_migration_pending_after_sync; then echo 'FAIL same-boot clear helper errored' >&2; exit 1; fi
[ -f "$MIGRATION_PENDING" ] || { echo 'FAIL same-boot migration marker was cleared unsafely' >&2; exit 1; }
rm -f "$MIGRATION_PENDING"
# Disabled legacy modules were not mounted in this boot; their marker can be migrated without reboot guard.
rm -f "$MIGRATION_PENDING"
rm -f "$TMP/modules/pg_https_ca/skip_mount"
printf 'id=pg_https_ca\n' > "$TMP/modules/pg_https_ca/module.prop"
touch "$TMP/modules/pg_https_ca/disable"
if ! pg_cert_ensure_skip_mount >"$TMP/out4" 2>"$TMP/err4"; then
  cat "$TMP/err4" >&2; echo 'FAIL disabled child migration unexpectedly required reboot' >&2; exit 1
fi
[ -f "$TMP/modules/pg_https_ca/skip_mount" ] || { echo 'FAIL disabled child skip_mount not written' >&2; exit 1; }
echo 'PASS: legacy active CA migration blocks trust mutations until reboot; post-reboot marker clears only after verified sync; same-boot retries remain blocked; disabled children are safely migrated'
