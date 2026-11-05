#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
W="$ROOT/scripts/localdns-watchdog.sh"
sh -n "$W"
grep -Fq 'retaining watcher and retrying in 2s' "$W"
grep -Fq 'rechecking DNS health promptly instead of waiting the normal interval' "$W"
if grep -Eiq 'iptables|ip6tables|nft[[:space:]]' "$W"; then
  echo 'FAIL: watchdog must not mutate firewall state directly' >&2; exit 1
fi
T=$(mktemp -d "${TMPDIR:-/tmp}/fx-watchdog-health-lock.XXXXXX")
cleanup() {
  if [ -s "$T/state/localdns-watchdog.pid" ]; then sh "$T/mod/scripts/localdns-watchdog.sh" stop "$T/mod" "$T/state" >/dev/null 2>&1 || :; fi
  sleep 0.2 2>/dev/null || :
  rm -rf "$T"
}
trap cleanup EXIT HUP INT TERM
mkdir -p "$T/mod/scripts" "$T/state/adguardhome" "$T/state/unbound"
cp "$W" "$T/mod/scripts/localdns-watchdog.sh"
chmod 755 "$T/mod/scripts/localdns-watchdog.sh"
printf '101\n' > "$T/state/adguardhome/managed.pid"
printf '102\n' > "$T/state/unbound/managed.pid"
cat > "$T/mod/scripts/apply.sh" <<EOF_APPLY
#!/system/bin/sh
[ "\${1:-}" = fast ] || exit 2
_n=0
[ ! -f "$T/state/apply-count" ] || _n=\$(cat "$T/state/apply-count")
_n=\$((\$_n+1))
printf '%s\n' "\$_n" > "$T/state/apply-count"
echo "apply-fast-called-\$_n" >> "$T/state/apply-test.log"
# Simulate apply.lock contention while stale engine markers still exist.
[ "\$_n" -eq 1 ] && exit 75
exit 0
EOF_APPLY
cat > "$T/mod/scripts/adguardhome.sh" <<EOF_STATUS
#!/system/bin/sh
_n=0
[ ! -f "$T/state/status-count" ] || _n=\$(cat "$T/state/status-count")
_n=\$((\$_n+1))
printf '%s\n' "\$_n" > "$T/state/status-count"
# Fail the health probe until the second serialized apply has run.
_a=0
[ ! -f "$T/state/apply-count" ] || _a=\$(cat "$T/state/apply-count")
[ "\$_a" -ge 2 ] && exit 0
exit 1
EOF_STATUS
chmod 755 "$T/mod/scripts/apply.sh" "$T/mod/scripts/adguardhome.sh"
sh "$T/mod/scripts/localdns-watchdog.sh" start "$T/mod" "$T/state"
_i=0
while [ "$_i" -lt 45 ] && ! grep -Fq 'apply-fast-called-2' "$T/state/apply-test.log" 2>/dev/null; do sleep 0.1; _i=$((_i+1)); done
grep -Fq 'apply-fast-called-1' "$T/state/apply-test.log"
grep -Fq 'apply-fast-called-2' "$T/state/apply-test.log" || { echo 'FAIL: health-failure path did not retry after apply lock contention' >&2; exit 1; }
grep -Fq 'retaining watcher and retrying in 2s' "$T/state/localdns-watchdog.log" || { echo 'FAIL: failed apply retry was not logged' >&2; exit 1; }
sh "$T/mod/scripts/localdns-watchdog.sh" stop "$T/mod" "$T/state"
echo 'PASS: DNS health failure retries apply after lock contention without a long blind interval'
