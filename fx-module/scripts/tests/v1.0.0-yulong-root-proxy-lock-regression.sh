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
#!/system/bin/sh
exit 0
SH
chmod 0755 "$BIN/sleep"
export MP="$MOD" PG="$PG" PATH="$BIN:$PATH"
LOCK="$PG/yulong-root-proxy.lock"

# Normal ownership publishes a PID and removes the lock only at process exit.
sh "$SOURCE" stop >/dev/null
[ ! -e "$LOCK" ] || { echo "FAIL: normal Root Proxy operation leaked its lock" >&2; exit 1; }

# A dead lock owner is recovered rather than blocking all future DNS changes.
mkdir "$LOCK"
printf '2147483647\n' > "$LOCK/pid"
sh "$SOURCE" stop >/dev/null
[ ! -e "$LOCK" ] || { echo "FAIL: stale Root Proxy lock was not recovered" >&2; exit 1; }

# A live owner is never stolen; the command returns a bounded busy error.
mkdir "$LOCK"
printf '%s\n' "$" > "$LOCK/pid"
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

echo "PASS: Yulong Root Proxy lock recovers dead owners, preserves live owners and cleans up only after exit"
