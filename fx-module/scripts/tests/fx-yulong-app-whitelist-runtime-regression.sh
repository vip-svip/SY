#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
SCRIPT="$ROOT/scripts/yulong-app-whitelist.sh"
if [ "$#" -gt 0 ]; then
  MODULE=$(CDPATH= cd -- "$1" && pwd)
  [ -s "$MODULE/scripts/yulong-app-whitelist.sh" ] || {
    echo "FAIL: restored module whitelist implementation missing" >&2; exit 1;
  }
  cmp -s "$SCRIPT" "$MODULE/scripts/yulong-app-whitelist.sh" || {
    echo "FAIL: restored module whitelist implementation differs from canonical source" >&2; exit 1;
  }
  [ -s "$MODULE/scripts/tests/v1.0.0-yulong-app-whitelist-runtime-regression.sh" ] || {
    echo "FAIL: restored module whitelist regression missing" >&2; exit 1;
  }
fi
[ -s "$SCRIPT" ] || { echo "FAIL: migrated whitelist runtime script missing" >&2; exit 1; }
sh -n "$SCRIPT" || { echo "FAIL: whitelist runtime shell syntax invalid" >&2; exit 1; }
sh -n "$0" || { echo "FAIL: whitelist regression shell syntax invalid" >&2; exit 1; }
TMP=$(mktemp -d /tmp/fx-yulong-whitelist.XXXXXX)
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
MODULE="$TMP/module"
STATE="$TMP/state"
mkdir -p "$MODULE/scripts" "$STATE"
printf 'id=privacyguard\n' > "$MODULE/module.prop"
cat > "$MODULE/scripts/apply.sh" <<'SH'
#!/system/bin/sh
printf '%s\n' "$*" >> "$FX_TEST_APPLY_LOG"
if [ "$FX_TEST_VERIFY_LOCK_PID" = 1 ]; then
  lock_pid=$(cat "$LOCK/pid") || exit 90
  case "$lock_pid" in ''|*[!0-9]*) exit 91 ;; esac
  kill -0 "$lock_pid" 2>/dev/null || exit 92
  [ "$(stat -c %a "$LOCK/pid")" = 600 ] || exit 93
  for backup in "$CONF".yulong-white-rollback.*; do
    [ -f "$backup" ] && [ ! -L "$backup" ] || continue
    [ "$(stat -c %a "$backup")" = 600 ] || exit 94
  done
fi
[ "$FX_TEST_APPLY_FAIL" != 1 ]
SH
chmod 0755 "$MODULE/scripts/apply.sh"
cat > "$STATE/settings.conf" <<'CONF'
[conf:general]
enabled=1
[list:yulong_app_whitelist]
CONF
chmod 0600 "$STATE/settings.conf"
export FX_TEST_APPLY_LOG="$TMP/apply.log"
export FX_TEST_APPLY_FAIL=0 FX_TEST_VERIFY_LOCK_PID=1
export MP="$MODULE" PG="$STATE" CONF="$STATE/settings.conf" LOCK="$STATE/whitelist.lock"
mkdir -p "$TMP/bin"
cat > "$TMP/bin/cmd" <<'CMD'
#!/system/bin/sh
[ "$*" = "package list packages -U" ] || exit 64
case "${FX_TEST_PACKAGE_MODE:-good}" in
  good) printf '%s\n' "package:com.example.installed uid:10101" ;;
  empty) : ;;
  fail) exit 71 ;;
  malformed)
    printf '%s\n' "package:com.example.installed uid:10101" "partial package-manager output"
    ;;
  *) exit 72 ;;
esac
CMD
chmod 0755 "$TMP/bin/cmd"
PATH="$TMP/bin:$PATH"
export PATH FX_TEST_PACKAGE_MODE=good

# The state-directory leaf and every ancestor must be real directories.
mkdir "$TMP/external-state"
cp "$CONF" "$TMP/external-state/settings.conf"
ln -s "$TMP/external-state" "$TMP/state-link"
if env MP="$MODULE" PG="$TMP/state-link" CONF="$TMP/state-link/settings.conf" \
    LOCK="$TMP/state-link/yulong-app-whitelist.lock" sh "$SCRIPT" list >/dev/null 2>&1; then
  echo "FAIL: whitelist accepted a symlinked PG directory" >&2; exit 1
fi
cmp -s "$CONF" "$TMP/external-state/settings.conf" || {
  echo "FAIL: PG symlink changed external settings" >&2; exit 1;
}
rm "$TMP/state-link"

mkdir "$TMP/real-parent"
ln -s "$TMP/real-parent" "$TMP/parent-link"
if env MP="$MODULE" PG="$TMP/parent-link/state" CONF="$TMP/parent-link/state/settings.conf" \
    LOCK="$TMP/parent-link/state/yulong-app-whitelist.lock" sh "$SCRIPT" list >/dev/null 2>&1; then
  echo "FAIL: whitelist accepted PG below a symlinked parent" >&2; exit 1
fi
[ ! -e "$TMP/real-parent/state" ] || {
  echo "FAIL: symlinked parent created an external whitelist state directory" >&2; exit 1;
}
rm "$TMP/parent-link"

# Environment overrides cannot redirect the settings file or lock outside PG.
if env MP="$MODULE" PG="$STATE" CONF="$TMP/outside-settings.conf" LOCK="$LOCK" sh "$SCRIPT" list >/dev/null 2>&1; then
  echo "FAIL: whitelist accepted an external CONF override" >&2; exit 1
fi
if env MP="$MODULE" PG="$STATE" CONF="$CONF" LOCK="$TMP/outside-lock" sh "$SCRIPT" list >/dev/null 2>&1; then
  echo "FAIL: whitelist accepted an external LOCK override" >&2; exit 1
fi
[ ! -e "$TMP/outside-settings.conf" ] && [ ! -e "$TMP/outside-lock" ] || {
  echo "FAIL: rejected whitelist path override created external state" >&2; exit 1;
}

# A lock symlink is rejected before any lock recovery or configuration write.
ln -s "$TMP/sentinel" "$LOCK"
if sh "$SCRIPT" list >/dev/null 2>&1; then
  echo "FAIL: whitelist accepted a symlinked lock path" >&2; exit 1
fi
rm "$LOCK"

grep -Fq '    /^\[/ {inlist=0}' "$SCRIPT" || {
  echo "FAIL: whitelist read_rows AWK section-boundary regex is malformed" >&2; exit 1;
}
if grep -Fq '    /^\\[/ {inlist=0}' "$SCRIPT"; then
  echo "FAIL: whitelist read_rows has a double-escaped AWK section-boundary regex" >&2
  exit 1
fi

# Environment overrides must be expanded by the shell, not treated as literal text.
LIST=$(sh "$SCRIPT" list)
if grep -Fq '\${' "$SCRIPT"; then
  echo "FAIL: whitelist script contains escaped shell parameter expansions" >&2
  exit 1
fi
grep -Fq '_yw_validate_parent_chain "$PG"' "$SCRIPT" || {
  echo "FAIL: whitelist state parent chain validation missing" >&2; exit 1;
}
grep -Fq '[ "$CONF" = "$PG/settings.conf" ]' "$SCRIPT" || {
  echo "FAIL: whitelist settings path is not pinned inside PG" >&2; exit 1;
}
grep -Fq '[ "$LOCK" = "$PG/yulong-app-whitelist.lock" ]' "$SCRIPT" || {
  echo "FAIL: whitelist lock path is not pinned inside PG" >&2; exit 1;
}
if grep -Fq 'mkdir -p "$PG"' "$SCRIPT"; then
  echo "FAIL: unsafe recursive whitelist state directory creation remains" >&2; exit 1
fi

# A killed writer must not leave a permanent directory lock.
mkdir -p "$LOCK"
printf '2147483647\n' > "$LOCK/pid"
sh "$SCRIPT" add com.example.stale
grep -Fqx 'com.example.stale|com.example.stale|1' "$CONF"
[ ! -e "$LOCK" ] || { echo "FAIL: recovered stale lock was not released" >&2; exit 1; }
sh "$SCRIPT" add com.example.alpha
grep -Fqx 'com.example.alpha|com.example.alpha|1' "$CONF"
[ "$(stat -c %a "$CONF")" = 600 ]
grep -Fqx 'fast' "$FX_TEST_APPLY_LOG"
LIST=$(sh "$SCRIPT" list)
printf '%s\n' "$LIST" | grep -Fqx 'com.example.alpha|com.example.alpha|1'

# Removing a rule is transactional and does not disturb unrelated settings.
sh "$SCRIPT" remove com.example.alpha
! grep -Fq 'com.example.alpha|' "$CONF"
grep -Fqx '[conf:general]' "$CONF"
grep -Fqx 'enabled=1' "$CONF"

# An apply failure must restore the exact previous settings file.
BEFORE=$(cksum "$CONF")
export FX_TEST_APPLY_FAIL=1
if sh "$SCRIPT" add com.example.beta; then
  echo "FAIL: whitelist mutation succeeded despite apply.sh failure" >&2
  exit 1
fi
export FX_TEST_APPLY_FAIL=0
AFTER=$(cksum "$CONF")
[ "$BEFORE" = "$AFTER" ] || { echo "FAIL: failed whitelist apply did not restore config" >&2; exit 1; }

# Invalid package syntax must be rejected before changing settings or running apply.sh.
BEFORE=$(cksum "$CONF")
if sh "$SCRIPT" add 'com.example.bad;id'; then
  echo "FAIL: invalid package token was accepted" >&2
  exit 1
fi
[ "$BEFORE" = "$(cksum "$CONF")" ] || { echo "FAIL: invalid package modified settings" >&2; exit 1; }

# Predictable legacy temp names are symlinks to a sentinel. Randomized mktemp
# paths must not follow or overwrite the sentinel during commit or rollback.
SENTINEL="$TMP/sentinel"
printf 'do-not-overwrite\n' > "$SENTINEL"
WRAPPER_PID_FILE="$TMP/wrapper.pid"
export WRAPPER_PID_FILE
run_with_predictable_symlink_sentinels() {
  sh -c '
    conf=$1; sentinel=$2; script=$3; shift 3
    pid=$$
    for suffix in yulong-white yulong-white-rollback restore; do
      ln -s "$sentinel" "$conf.$suffix.$pid"
    done
    printf "%s\n" "$pid" > "$WRAPPER_PID_FILE"
    exec sh "$script" "$@"
  ' sh "$CONF" "$SENTINEL" "$SCRIPT" "$@"
}
remove_predictable_symlink_sentinels() {
  [ -s "$WRAPPER_PID_FILE" ] || return 0
  pid=$(cat "$WRAPPER_PID_FILE")
  for suffix in yulong-white yulong-white-rollback restore; do
    rm -f "$CONF.$suffix.$pid"
  done
  rm -f "$WRAPPER_PID_FILE"
}
run_with_predictable_symlink_sentinels add com.example.atomic
[ "$(cat "$SENTINEL")" = "do-not-overwrite" ] || {
  echo "FAIL: whitelist writer followed a predictable temp symlink" >&2; exit 1;
}
grep -Fqx 'com.example.atomic|com.example.atomic|1' "$CONF" || {
  echo "FAIL: whitelist atomic write did not persist" >&2; exit 1;
}
remove_predictable_symlink_sentinels

before_rollback=$(cksum "$CONF")
export FX_TEST_APPLY_FAIL=1
if run_with_predictable_symlink_sentinels add com.example.rollback; then
  echo "FAIL: whitelist mutation succeeded while apply was forced to fail" >&2; exit 1
fi
export FX_TEST_APPLY_FAIL=0
remove_predictable_symlink_sentinels
[ "$(cat "$SENTINEL")" = "do-not-overwrite" ] || {
  echo "FAIL: whitelist rollback followed a predictable temp symlink" >&2; exit 1;
}
[ "$before_rollback" = "$(cksum "$CONF")" ] || {
  echo "FAIL: randomized rollback did not restore the exact config" >&2; exit 1;
}

# The lock directory and its PID file are never read or written through links.
rm -f "$LOCK"
ln -s "$SENTINEL" "$LOCK"
if sh "$SCRIPT" add com.example.locklink >/dev/null 2>&1; then
  echo "FAIL: whitelist accepted a symlinked lock directory" >&2; exit 1
fi
rm -f "$LOCK"
mkdir "$LOCK"
ln -s "$SENTINEL" "$LOCK/pid"
if sh "$SCRIPT" add com.example.pidlink >/dev/null 2>&1; then
  echo "FAIL: whitelist accepted a symlinked lock PID file" >&2; exit 1
fi
rm -f "$LOCK/pid"
rmdir "$LOCK"
[ "$(cat "$SENTINEL")" = "do-not-overwrite" ] || {
  echo "FAIL: lock recovery changed the sentinel target" >&2; exit 1;
}

grep -Fq '"$$" > "$_YW_PID_TEMP"' "$SCRIPT" || {
  echo "FAIL: whitelist lock owner does not record the current PID" >&2; exit 1;
}
if grep -Fq 'cp -p "$CONF" "$backup"' "$SCRIPT" || grep -Fq 'cp -p "$backup" "$_YW_RESTORE"' "$SCRIPT"; then
  echo "FAIL: private rollback files inherit the source config mode" >&2; exit 1;
fi
if grep -Eq 'CONF\.yulong-white(-rollback)?\.\$\$|CONF\.restore\.\$\$' "$SCRIPT"; then
  echo "FAIL: predictable whitelist temp names remain" >&2; exit 1
fi
for template in 'mktemp "$CONF.yulong-white.XXXXXX"' \
                'mktemp "$CONF.yulong-white-rollback.XXXXXX"' \
                'mktemp "$CONF.restore.XXXXXX"'; do
  grep -Fq "$template" "$SCRIPT" || {
    echo "FAIL: missing randomized whitelist transaction file: $template" >&2; exit 1;
  }
done

# The UI's prune command must remove only packages absent from one complete PackageManager snapshot.
sh "$SCRIPT" add com.example.installed
printf '%s\n' "com.example.retired|retired selection|0" >> "$CONF"
BEFORE_PRUNE=$(cksum "$CONF")
PRUNE_OUTPUT=$(sh "$SCRIPT" prune)
case "$PRUNE_OUTPUT" in *"removed=3 applied=1"*) ;; *) echo "FAIL: prune did not report the three uninstalled whitelist entries: $PRUNE_OUTPUT" >&2; exit 1 ;; esac
grep -Fqx 'com.example.installed|com.example.installed|1' "$CONF"
! grep -Fq 'com.example.stale|' "$CONF"
! grep -Fq 'com.example.atomic|' "$CONF"
! grep -Fq 'com.example.retired|' "$CONF"
grep -Fqx '[conf:general]' "$CONF"

# A clean snapshot is a no-op: no config change and no unnecessary apply.
BEFORE_PRUNE=$(cksum "$CONF")
PRUNE_OUTPUT=$(sh "$SCRIPT" prune)
[ "$PRUNE_OUTPUT" = "removed=0 applied=0" ] || { echo "FAIL: clean whitelist prune was not a no-op: $PRUNE_OUTPUT" >&2; exit 1; }
[ "$BEFORE_PRUNE" = "$(cksum "$CONF")" ] || { echo "FAIL: no-op prune changed settings" >&2; exit 1; }

# Empty, failed or partially malformed PackageManager snapshots must fail closed.
for mode in empty fail malformed; do
  BEFORE_PRUNE=$(cksum "$CONF")
  export FX_TEST_PACKAGE_MODE="$mode"
  if sh "$SCRIPT" prune >/dev/null 2>&1; then echo "FAIL: prune accepted $mode PackageManager snapshot" >&2; exit 1; fi
  [ "$BEFORE_PRUNE" = "$(cksum "$CONF")" ] || { echo "FAIL: $mode snapshot changed the whitelist" >&2; exit 1; }
done
export FX_TEST_PACKAGE_MODE=good

# A failed runtime apply must restore the exact previous whitelist selection.
sh "$SCRIPT" add com.example.retired-again
BEFORE_PRUNE=$(cksum "$CONF")
export FX_TEST_APPLY_FAIL=1
if sh "$SCRIPT" prune >/dev/null 2>&1; then echo "FAIL: prune succeeded despite apply failure" >&2; exit 1; fi
export FX_TEST_APPLY_FAIL=0
[ "$BEFORE_PRUNE" = "$(cksum "$CONF")" ] || { echo "FAIL: failed prune did not restore the exact whitelist" >&2; exit 1; }
! grep -Fq 'com.example.retired-again|' "$CONF"
# Unsafe settings.conf symlink is rejected without following its target.
mv "$CONF" "$STATE/settings.real"
ln -s "$STATE/settings.real" "$CONF"
if sh "$SCRIPT" list; then
  echo "FAIL: whitelist accepted a symlink settings.conf" >&2
  exit 1
fi
[ "$(cat "$SENTINEL")" = "do-not-overwrite" ] || {
  echo "FAIL: whitelist settings guard changed the sentinel target" >&2; exit 1;
}

echo "PASS: Yulong whitelist lock PID, private rollback files, randomized temp paths, symlink guards and stale-lock recovery"
