#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
W="$ROOT/scripts/localdns-watchdog.sh"
sh -n "$W"
grep -Fq 'engine PID marker absent while watchdog active; invoking apply transaction to recover or roll back DNS interception' "$W"
grep -Fq 'sh "$MODDIR/scripts/apply.sh" fast >> "$LOG" 2>&1' "$W"
grep -Fq 'retaining watcher and retrying instead of assuming fail-open' "$W"
grep -Fq 'apply returned success but DNS engine markers remain absent; retaining watcher and retrying recovery' "$W"
grep -Fq 'DNS engine markers re-established by apply; continue full-chain health checks' "$W"
if grep -Eiq 'iptables|ip6tables|nft[[:space:]]' "$W"; then
  echo 'FAIL: watchdog must not mutate firewall state directly' >&2; exit 1
fi
T=$(mktemp -d "${TMPDIR:-/tmp}/fx-watchdog-missing-marker.XXXXXX")
cleanup() {
  if [ -s "$T/state/localdns-watchdog.pid" ]; then sh "$T/mod/scripts/localdns-watchdog.sh" stop "$T/mod" "$T/state" >/dev/null 2>&1 || :; fi
  sleep 0.2 2>/dev/null || :
  rm -rf "$T"
}
trap cleanup EXIT HUP INT TERM
mkdir -p "$T/mod/scripts" "$T/state/adguardhome" "$T/state/unbound"
cp "$W" "$T/mod/scripts/localdns-watchdog.sh"
chmod 755 "$T/mod/scripts/localdns-watchdog.sh"
printf '102\n' > "$T/state/unbound/managed.pid"
cat > "$T/mod/scripts/apply.sh" <<EOF_APPLY
#!/system/bin/sh
[ "\${1:-}" = fast ] || exit 2
_n=0
[ ! -f "$T/state/apply-count" ] || _n=\$(cat "$T/state/apply-count")
_n=\$((\$_n+1))
printf '%s\n' "\$_n" > "$T/state/apply-count"
echo "apply-fast-called-\$_n" >> "$T/state/apply-test.log"
# Model the real race: the first apply is rejected because another apply owns
# the lock (EX_TEMPFAIL=75). The watcher must not exit or claim rollback.
[ "\$_n" -eq 1 ] && exit 75
printf '101\n' > "$T/state/adguardhome/managed.pid"
printf '102\n' > "$T/state/unbound/managed.pid"
exit 0
EOF_APPLY
cat > "$T/mod/scripts/adguardhome.sh" <<'EOF_AGH'
#!/system/bin/sh
[ "${1:-}" = status ] && exit 0
exit 0
EOF_AGH
chmod 755 "$T/mod/scripts/apply.sh" "$T/mod/scripts/adguardhome.sh"
# Runtime path: the missing AGH marker must cause apply.sh fast to be invoked;
# the stub restores both markers so the watcher remains alive until stopped.
sh "$T/mod/scripts/localdns-watchdog.sh" start "$T/mod" "$T/state"
_i=0
while [ "$_i" -lt 30 ] && [ ! -s "$T/state/apply-test.log" ]; do sleep 0.1; _i=$((_i+1)); done
[ -s "$T/state/apply-test.log" ] || { echo 'FAIL: apply transaction was not invoked for missing engine marker' >&2; exit 1; }
_i=0
while [ "$_i" -lt 40 ] && ! grep -Fq 'apply-fast-called-2' "$T/state/apply-test.log" 2>/dev/null; do sleep 0.1; _i=$((_i+1)); done
grep -Fq 'apply-fast-called-1' "$T/state/apply-test.log"
grep -Fq 'apply-fast-called-2' "$T/state/apply-test.log" || { echo 'FAIL: watcher did not retry after apply lock contention' >&2; exit 1; }
grep -Fq 'retaining watcher and retrying instead of assuming fail-open' "$T/state/localdns-watchdog.log" || { echo 'FAIL: watcher did not record fail-open uncertainty' >&2; exit 1; }
grep -Fq 'DNS engine markers re-established by apply' "$T/state/localdns-watchdog.log"
sh "$T/mod/scripts/localdns-watchdog.sh" stop "$T/mod" "$T/state"
echo 'PASS: missing DNS-engine marker survives apply lock contention, retries serialized recovery, and resumes health checks only after markers return'
