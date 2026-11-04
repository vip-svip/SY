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
    [ -f "$backup" ] || continue
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

# Environment overrides must be expanded by the shell, not treated as literal text.
LIST=$(sh "$SCRIPT" list)
if grep -Fq '\${' "$SCRIPT"; then
  echo "FAIL: whitelist script contains escaped shell parameter expansions" >&2
  exit 1
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
if grep -Eq 'CONF\.yulong-white(-rollback)?\.\$\$|CONF\.restore\.\$\
  echo "FAIL: predictable whitelist temp names remain" >&2; exit 1
fi
for template in 'mktemp "$CONF.yulong-white.XXXXXX"' \
                'mktemp "$CONF.yulong-white-rollback.XXXXXX"' \
                'mktemp "$CONF.restore.XXXXXX"'; do
  grep -Fq "$template" "$SCRIPT" || {
    echo "FAIL: missing randomized whitelist transaction file: $template" >&2; exit 1;
  }
done

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

echo "PASS: Yulong whitelist uses private atomic temp/rollback files, rejects symlink paths, preserves stale-lock recovery and stages identical Release source"
 "$SCRIPT"; then
  echo "FAIL: predictable whitelist temp names remain" >&2; exit 1
fi
for template in 'mktemp "$CONF.yulong-white.XXXXXX"' \
                'mktemp "$CONF.yulong-white-rollback.XXXXXX"' \
                'mktemp "$CONF.restore.XXXXXX"'; do
  grep -Fq "$template" "$SCRIPT" || {
    echo "FAIL: missing randomized whitelist transaction file: $template" >&2; exit 1;
  }
done

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

echo "PASS: Yulong whitelist uses private atomic temp/rollback files, rejects symlink paths, preserves stale-lock recovery and stages identical Release source"
