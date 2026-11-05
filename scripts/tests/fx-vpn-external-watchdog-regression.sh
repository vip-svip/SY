#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
SOURCE="$ROOT/fx-module/scripts/vpn-external-watchdog.sh"
fail(){ echo "FAIL: $*" >&2; exit 1; }
[ -s "$SOURCE" ] || fail "external VPN watchdog missing"
sh -n "$SOURCE" || fail "watchdog shell syntax invalid"
T=$(mktemp -d "${TMPDIR:-/tmp}/fx-vpn-watchdog.XXXXXX")
trap 'if [ -n "${MOD:-}" ] && [ -f "$MOD/scripts/vpn-external-watchdog.sh" ]; then PG="$PG" MODDIR="$MOD" sh "$MOD/scripts/vpn-external-watchdog.sh" stop "$MOD" "$PG" >/dev/null 2>&1 || :; fi; rm -rf "$T"' EXIT HUP INT TERM
MOD="$T/module"; PG="$T/state"
mkdir -p "$MOD/scripts" "$PG"
cp "$SOURCE" "$MOD/scripts/vpn-external-watchdog.sh"
cat > "$MOD/scripts/yulong-root-proxy.sh" <<'PROXY'
#!/bin/sh
echo "$1" >> "$PG/proxy-calls.log"
case "$1" in reconcile|status|stop) exit 0;; *) exit 64;; esac
PROXY
chmod 0755 "$MOD/scripts/yulong-root-proxy.sh"
printf 'vpn_external_dns_proxy=1\n' > "$PG/settings.conf"

# Snapshot and apply marker are safe, atomic state writes.
PG="$PG" MODDIR="$MOD" sh "$MOD/scripts/vpn-external-watchdog.sh" snapshot "$MOD" "$PG" || fail "snapshot failed"
grep -Fqx 'format=FXVPNWATCH1' "$PG/vpn-external-watchdog.snapshot" || fail "snapshot format missing"
PG="$PG" MODDIR="$MOD" sh "$MOD/scripts/vpn-external-watchdog.sh" mark-applied "$MOD" "$PG" || fail "mark-applied failed"

# The process is started once, identified, and stopped cooperatively.
FX_VPN_WATCHDOG_INTERVAL=1 PG="$PG" MODDIR="$MOD" sh "$MOD/scripts/vpn-external-watchdog.sh" start "$MOD" "$PG" || fail "watchdog start failed"
PG="$PG" MODDIR="$MOD" sh "$MOD/scripts/vpn-external-watchdog.sh" status > "$T/status.out" || fail "watchdog status failed"
grep -Fqx 'running=1' "$T/status.out" || fail "watchdog did not report running"
FX_VPN_WATCHDOG_INTERVAL=1 PG="$PG" MODDIR="$MOD" sh "$MOD/scripts/vpn-external-watchdog.sh" start "$MOD" "$PG" || fail "idempotent second start failed"
PG="$PG" MODDIR="$MOD" sh "$MOD/scripts/vpn-external-watchdog.sh" stop "$MOD" "$PG" || fail "watchdog stop failed"
[ ! -e "$PG/vpn-external-watchdog.pid" ] || fail "watchdog PID record remained after stop"
grep -Fq 'reconcile' "$PG/proxy-calls.log" || fail "watch loop never reconciled Root Proxy"

# An untrusted PID symlink must be rejected without touching its target.
printf '99999999\n' > "$T/pid-target"
ln -s "$T/pid-target" "$PG/vpn-external-watchdog.pid"
if PG="$PG" MODDIR="$MOD" sh "$MOD/scripts/vpn-external-watchdog.sh" stop "$MOD" "$PG" > "$T/symlink.out" 2>&1; then
  fail "watchdog accepted a symlink PID record"
fi
grep -Fq 'refusing symlink PID record' "$T/symlink.out" || fail "symlink PID refusal not reported"
grep -Fxq 99999999 "$T/pid-target" || fail "symlink PID target changed"

echo "PASS: external VPN watchdog snapshots state, starts idempotently, reconciles, and stops with PID identity checks"
