#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
SOURCE="$ROOT/fx-module/scripts/yulong-root-proxy.sh"
[ -s "$SOURCE" ] || { echo "FAIL: Yulong Root Proxy source missing" >&2; exit 1; }
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
MOD="$TMP/module"
PG="$TMP/state"
BIN="$TMP/bin"
mkdir -p "$MOD/scripts" "$PG" "$BIN"
printf 'id=privacyguard\n' > "$MOD/module.prop"
printf "%s\n" "# test utility stub" > "$MOD/scripts/util.sh"
for script in adguardhome.sh unbound.sh; do
  cat > "$MOD/scripts/$script" <<'SH'
#!/system/bin/sh
case "$1" in
  stop)
    if ! (umask 077; set -C; printf 'locked\n' > "$TMP/engine.lock") 2>/dev/null; then
      printf 'overlap\n' >> "$TMP/engine-overlap"
    fi
    /bin/sleep 0.04
    rm -f "$TMP/engine.lock"
    ;;
esac
exit 0
SH
  chmod 0755 "$MOD/scripts/$script"
done
for tool in iptables ip6tables; do
  cat > "$BIN/$tool" <<'SH'
#!/system/bin/sh
exit 1
SH
  chmod 0755 "$BIN/$tool"
done
cat > "$BIN/sleep" <<'SH'
#!/bin/sh
case "$1" in
  1) /bin/sleep 0.01 ;;
  *) /bin/sleep "$@" ;;
esac
SH
chmod 0755 "$BIN/sleep"
export MP="$MOD" PG="$PG" PATH="$BIN:$PATH" TMP="$TMP"
LOCK="$PG/yulong-root-proxy.lock"

grep -Fq '( umask 077; set -C; printf ' "$SOURCE" || {
  echo "FAIL: Root Proxy lock must use private noclobber file creation" >&2; exit 1;
}
grep -Fq 'mv "$LOCK" "$_release"' "$SOURCE" || {
  echo "FAIL: Root Proxy lock release must atomically rename the owner file" >&2; exit 1;
}
if grep -Fq 'rm -f "$LOCK/pid" 2>/dev/null || :' "$SOURCE"; then
  echo "FAIL: Root Proxy still removes PID before releasing the lock path" >&2; exit 1;
fi
if grep -Fq 'rmdir "$LOCK" 2>/dev/null || :' "$SOURCE"; then
  echo "FAIL: Root Proxy still exposes a PID-less lock directory" >&2; exit 1;
fi

# A live operation holds a private regular lock file until EXIT cleanup.
sh "$SOURCE" stop > "$TMP/normal-stop.log" 2>&1 &
normal_pid=$!
tries=0
while kill -0 "$normal_pid" 2>/dev/null && [ ! -f "$LOCK" ] && [ "$tries" -lt 100 ]; do
  tries=$((tries+1))
  /bin/sleep 0.001
done
[ -f "$LOCK" ] && [ ! -d "$LOCK" ] && [ ! -L "$LOCK" ] || {
  echo "FAIL: Root Proxy did not publish a regular non-symlink lock file while active" >&2; cat "$TMP/normal-stop.log" >&2 || :; exit 1;
}
[ "$(stat -c %a "$LOCK")" = "600" ] || {
  echo "FAIL: Root Proxy lock file must have mode 0600" >&2; stat -c '%a %n' "$LOCK" >&2; exit 1;
}
wait "$normal_pid" || { echo "FAIL: normal Root Proxy stop failed" >&2; cat "$TMP/normal-stop.log" >&2; exit 1; }
[ ! -e "$LOCK" ] || { echo "FAIL: normal Root Proxy operation leaked its lock" >&2; exit 1; }

# Never follow or replace a symlink used as the canonical lock path.
mkdir "$TMP/lock-target"
printf 'keep-lock-target\n' > "$TMP/lock-target/sentinel"
ln -s "$TMP/lock-target" "$LOCK"
if sh "$SOURCE" stop >/dev/null 2>&1; then
  echo "FAIL: Root Proxy accepted a symlink at its lock path" >&2; exit 1
fi
[ -L "$LOCK" ] && [ "$(cat "$TMP/lock-target/sentinel")" = "keep-lock-target" ] || {
  echo "FAIL: Root Proxy followed or removed the lock symlink target" >&2; exit 1;
}
rm "$LOCK"

# Normal ownership publishes a PID and removes the lock only at process exit.
sh "$SOURCE" stop >/dev/null
[ ! -e "$LOCK" ] || { echo "FAIL: normal Root Proxy operation leaked its lock" >&2; exit 1; }

# A stale regular-file owner is reclaimed.
printf '2147483647\n' > "$LOCK"
sh "$SOURCE" stop >/dev/null
[ ! -e "$LOCK" ] || { echo "FAIL: stale regular Root Proxy lock file was not recovered" >&2; exit 1; }

# A live regular-file owner is never stolen.
printf '%s\n' "$$" > "$LOCK"
set +e
sh "$SOURCE" stop >/dev/null 2>&1
file_rc=$?
set -e
[ "$file_rc" -eq 10 ] || { echo "FAIL: live regular Root Proxy file lock did not return busy (rc=$file_rc)" >&2; exit 1; }
[ "$(cat "$LOCK")" = "$$" ] || { echo "FAIL: live regular Root Proxy file lock owner changed" >&2; exit 1; }
rm -f "$LOCK"

# A dead lock owner is recovered rather than blocking all future DNS changes.
mkdir "$LOCK"
printf '2147483647\n' > "$LOCK/pid"
sh "$SOURCE" stop >/dev/null
[ ! -e "$LOCK" ] || { echo "FAIL: stale Root Proxy lock was not recovered" >&2; exit 1; }

# A live owner is never stolen; the command returns a bounded busy error.
mkdir "$LOCK"
printf '%s\n' "$$" > "$LOCK/pid"
set +e
sh "$SOURCE" stop >/dev/null 2>&1
rc=$?
set -e
[ "$rc" -eq 10 ] || { echo "FAIL: live Root Proxy lock did not return busy (rc=$rc)" >&2; exit 1; }
[ "$(cat "$LOCK/pid")" = "$$" ] || { echo "FAIL: live lock ownership was changed" >&2; exit 1; }
rm -f "$LOCK/pid"
rmdir "$LOCK"

# A PID-less directory is given a short publication window, then recovered.
mkdir "$LOCK"
sh "$SOURCE" stop >/dev/null
[ ! -e "$LOCK" ] || { echo "FAIL: orphaned PID-less Root Proxy lock was not recovered" >&2; exit 1; }

# Signal handlers must exit into the sole EXIT cleanup handler; they must not
# release the lock and then resume the protected mutation.
grep -Fqx '  trap cleanup_lock EXIT' "$SOURCE"
grep -Fqx "  trap 'exit 129' HUP" "$SOURCE"
grep -Fqx "  trap 'exit 130' INT" "$SOURCE"
grep -Fqx "  trap 'exit 143' TERM" "$SOURCE"

# Concurrent stop operations must serialize through the private file lock.
sh "$SOURCE" stop > "$TMP/concurrent-a.log" 2>&1 & p1=$!
/bin/sleep 0.005
sh "$SOURCE" stop > "$TMP/concurrent-b.log" 2>&1 & p2=$!
wait "$p1" || { rc=$?; cat "$TMP/concurrent-a.log" "$TMP/concurrent-b.log" >&2; exit "$rc"; }
wait "$p2" || { rc=$?; cat "$TMP/concurrent-a.log" "$TMP/concurrent-b.log" >&2; exit "$rc"; }
[ ! -s "$TMP/engine-overlap" ] || {
  echo "FAIL: concurrent Root Proxy engine cleanup overlapped" >&2
  cat "$TMP/engine-overlap" >&2
  exit 1
}
[ ! -e "$LOCK" ] || { echo "FAIL: concurrent Root Proxy stops leaked lock file" >&2; exit 1; }
echo "PASS: Root Proxy atomic file lock, stale/live owners, legacy directory migration and concurrent serialization"
