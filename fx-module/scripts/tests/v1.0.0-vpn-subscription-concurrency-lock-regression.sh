#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
S="$ROOT/scripts/vpnsub.sh"
[ -s "$S" ] || { echo 'FAIL: vpnsub.sh missing'; exit 1; }
grep -Fq '_vpn_update_subs_unlocked() {' "$S"
grep -Fq 'vpn-update.lock' "$S"
grep -Fq '_vul_reap_lock="$_vul_lock.reaper"' "$S" || { echo 'FAIL: stale lock reclamation is not serialized'; exit 1; }
grep -Fq '$_vul_recheck' "$S" || { echo 'FAIL: stale lock owner is not rechecked'; exit 1; }
grep -Fq '订阅更新正在执行，请稍后重试' "$S"
sh -n "$S"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT HUP INT TERM
cat > "$T/worker.sh" <<'WORKER'
#!/system/bin/sh
set -eu
PG="$PGDIR"
pg_fail() { echo "$*" >&2; }
pg_log() { :; }
. "$VPNSUB"
_vpn_update_subs_unlocked() {
  if ! mkdir "$PG/cache/active" 2>/dev/null; then touch "$PG/cache/OVERLAP"; return 91; fi
  sleep 1
  rmdir "$PG/cache/active"
  return "${WORK_RC:-0}"
}
vpn_update_subs
WORKER
chmod 755 "$T/worker.sh"
mkdir -p "$T/pg/cache"
PGDIR="$T/pg" VPNSUB="$S" sh "$T/worker.sh" >"$T/one.out" 2>"$T/one.err" & p1=$!
i=0
while [ ! -f "$T/pg/cache/vpn-update.lock/pid" ] && [ "$i" -lt 100 ]; do sleep 0.02; i=$((i+1)); done
[ -f "$T/pg/cache/vpn-update.lock/pid" ] || { echo 'FAIL: lock owner PID not published'; exit 1; }
PGDIR="$T/pg" VPNSUB="$S" sh "$T/worker.sh" >"$T/two.out" 2>"$T/two.err" & p2=$!
wait "$p1"
wait "$p2"
[ ! -e "$T/pg/cache/OVERLAP" ] || { echo 'FAIL: concurrent subscription transactions overlapped'; exit 1; }
[ ! -e "$T/pg/cache/vpn-update.lock" ] || { echo 'FAIL: transaction lock leaked after success'; exit 1; }
if PGDIR="$T/pg" VPNSUB="$S" WORK_RC=17 sh "$T/worker.sh" >/dev/null 2>&1; then echo 'FAIL: inner transaction failure was swallowed'; exit 1; else rc=$?; fi
[ "$rc" -eq 17 ] || { echo "FAIL: inner return code not preserved ($rc)"; exit 1; }
[ ! -e "$T/pg/cache/vpn-update.lock" ] || { echo 'FAIL: transaction lock leaked after failure'; exit 1; }
# A lock without a published PID is ambiguous: it may be a live owner paused
# between mkdir and PID write. Fail closed rather than stealing it after a timer.
mkdir -p "$T/pg/cache/vpn-update.lock"
if PGDIR="$T/pg" VPNSUB="$S" sh "$T/worker.sh" >"$T/unknown.out" 2>"$T/unknown.err"; then
  echo 'FAIL: unknown-owner lock was incorrectly bypassed'; exit 1
else rc=$?; fi
[ "$rc" -eq 75 ] || { echo "FAIL: unknown-owner lock should fail closed with 75 (got $rc)"; exit 1; }
[ -d "$T/pg/cache/vpn-update.lock" ] || { echo 'FAIL: unknown-owner lock was removed'; exit 1; }
rm -rf "$T/pg/cache/vpn-update.lock"
# A leftover reaper guard is ambiguous (the former reaper may have died at any
# instruction). Never time-steal the guard or remove the target lock; fail closed.
mkdir -p "$T/pg/cache/vpn-update.lock" "$T/pg/cache/vpn-update.lock.reaper"
printf '99999998\n' > "$T/pg/cache/vpn-update.lock/pid"
printf '99999997\n' > "$T/pg/cache/vpn-update.lock.reaper/pid"
if PGDIR="$T/pg" VPNSUB="$S" sh "$T/worker.sh" >"$T/reaper.out" 2>"$T/reaper.err"; then
  echo 'FAIL: leftover reaper guard was incorrectly bypassed'; exit 1
else rc=$?; fi
[ "$rc" -eq 75 ] || { echo "FAIL: leftover reaper guard should fail closed with 75 (got $rc)"; exit 1; }
[ -d "$T/pg/cache/vpn-update.lock" ] || { echo 'FAIL: target lock removed while reaper state was ambiguous'; exit 1; }
[ -d "$T/pg/cache/vpn-update.lock.reaper" ] || { echo 'FAIL: reaper guard removed without proving ownership'; exit 1; }
rm -rf "$T/pg/cache/vpn-update.lock" "$T/pg/cache/vpn-update.lock.reaper"
# A numeric but dead PID is reclaimable; this exercises the serialized reaper path.
mkdir -p "$T/pg/cache/vpn-update.lock"
printf '99999999\n' > "$T/pg/cache/vpn-update.lock/pid"
PGDIR="$T/pg" VPNSUB="$S" sh "$T/worker.sh" >"$T/stale.out" 2>"$T/stale.err" || { cat "$T/stale.err" >&2; echo 'FAIL: stale-owner lock was not recovered'; exit 1; }
[ ! -e "$T/pg/cache/OVERLAP" ] || { echo 'FAIL: stale-lock recovery overlapped a transaction'; exit 1; }
[ ! -e "$T/pg/cache/vpn-update.lock" ] || { echo 'FAIL: recovered transaction lock leaked'; exit 1; }
[ ! -e "$T/pg/cache/vpn-update.lock.reaper" ] || { echo 'FAIL: reaper guard leaked'; exit 1; }
echo 'FX VPN subscription transaction concurrency lock regression: PASS'
