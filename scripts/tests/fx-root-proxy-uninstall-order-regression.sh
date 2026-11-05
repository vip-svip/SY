#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
SOURCE="$ROOT/fx-module/uninstall.sh"
fail(){ echo "FAIL: $*" >&2; exit 1; }
[ -s "$SOURCE" ] || fail "FX uninstall hook missing"
sh -n "$SOURCE" || fail "FX uninstall hook shell syntax invalid"
T=$(mktemp -d "${TMPDIR:-/tmp}/fx-root-proxy-uninstall.XXXXXX")
trap 'rm -rf "$T"' EXIT HUP INT TERM
MOD="$T/module"; PG="$T/state"; LOG="$T/order.log"
mkdir -p "$MOD/scripts" "$PG"
cp "$SOURCE" "$MOD/uninstall.sh"
cat > "$MOD/scripts/yulong-root-proxy.sh" <<'PROXY'
#!/bin/sh
printf 'root-proxy:%s\n' "$*" >> "$ORDER_LOG"
[ "${MOCK_PROXY_FAIL:-0}" = 0 ]
PROXY
mkdir -p "$MOD/scripts/jsruntime"
cat > "$MOD/scripts/jsruntime/scheduler.sh" <<'SCHEDULER'
#!/bin/sh
printf 'scheduler:%s\n' "$*" >> "$ORDER_LOG"
SCHEDULER
cat > "$MOD/scripts/yulong-app-firewall.sh" <<'FIREWALL'
#!/bin/sh
printf 'firewall:%s\n' "$*" >> "$ORDER_LOG"
FIREWALL
cat > "$MOD/scripts/remove_adhook_app.sh" <<'REMOVER'
#!/bin/sh
printf 'hook-remover:%s\n' "$*" >> "$ORDER_LOG"
[ "${MOCK_HOOK_REMOVE_FAIL:-0}" = 0 ]
REMOVER
chmod 0755 "$MOD/scripts/"*.sh

# Successful uninstall must stop the Root Proxy before firewall teardown,
# then remove the Hook app before retiring only FX system-app deployment state.
printf '%s\n' verified-digest > "$PG/system-app-apk.sha256"
printf '%s\n' retry > "$PG/system-app-retry"
printf '%s\n' unrelated > "$PG/unrelated-state"
ORDER_LOG="$LOG" PG="$PG" MODDIR="$MOD" sh "$MOD/uninstall.sh" > "$T/success.out" 2>&1 || fail "successful Root Proxy shutdown blocked uninstall"
[ "$(sed -n '1p' "$LOG")" = 'scheduler:uninstall' ] || fail "QuickJS scheduler was not stopped when its state/log directory was absent"
[ "$(sed -n '2p' "$LOG")" = 'root-proxy:uninstall' ] || fail "Root Proxy was not stopped after the scheduler"
[ "$(sed -n '3p' "$LOG")" = 'firewall:uninstall' ] || fail "firewall teardown did not follow Root Proxy shutdown"
[ "$(sed -n '4p' "$LOG")" = "hook-remover:$MOD $PG" ] || fail "ownership-safe Hook remover did not run after network teardown"
[ ! -e "$PG/system-app-apk.sha256" ] || fail "stale system-app deployment digest survived successful uninstall"
[ ! -e "$PG/system-app-retry" ] || fail "stale system-app retry marker survived successful uninstall"
[ "$(cat "$PG/unrelated-state")" = unrelated ] || fail "uninstall removed unrelated PrivacyGuard state"

# An unconfirmed cleanup must abort before firewall teardown and preserve state.
printf '%s\n' verified-digest > "$PG/system-app-apk.sha256"
printf '%s\n' retry > "$PG/system-app-retry"
: > "$LOG"
: > "$PG/yulong-root-proxy-active"
if ORDER_LOG="$LOG" MOCK_PROXY_FAIL=1 PG="$PG" MODDIR="$MOD" sh "$MOD/uninstall.sh" > "$T/failure.out" 2>&1; then
  fail "uninstall continued after Root Proxy cleanup failure"
fi
[ "$(sed -n '1p' "$LOG")" = 'scheduler:uninstall' ] || fail "scheduler shutdown was skipped before failed Root Proxy cleanup"
[ "$(sed -n '2p' "$LOG")" = 'root-proxy:uninstall' ] || fail "firewall teardown ran after failed Root Proxy cleanup"
[ "$(wc -l < "$LOG" | tr -d ' ')" = 2 ] || fail "firewall or Hook teardown ran after failed Root Proxy cleanup"
grep -Fq 'preserving state and aborting uninstall' "$T/failure.out" || fail "cleanup failure was not reported"
[ -f "$PG/yulong-root-proxy-active" ] || fail "Root Proxy state marker was removed after failed cleanup"
[ -f "$PG/system-app-apk.sha256" ] || fail "deployment digest was removed after failed Root Proxy teardown"
[ -f "$PG/system-app-retry" ] || fail "deployment retry state was removed after failed Root Proxy teardown"

# Missing helper plus residual FX-owned state must also fail closed.
rm -f "$MOD/scripts/yulong-root-proxy.sh"
: > "$LOG"
if ORDER_LOG="$LOG" PG="$PG" MODDIR="$MOD" sh "$MOD/uninstall.sh" > "$T/missing.out" 2>&1; then
  fail "uninstall accepted residual Root Proxy state without its helper"
fi
[ "$(cat "$LOG")" = 'scheduler:uninstall' ] || fail "scheduler was not stopped before missing Root Proxy helper refusal"
grep -Fq 'cleanup helper is missing' "$T/missing.out" || fail "missing helper refusal was not reported"
[ -f "$PG/yulong-root-proxy-active" ] || fail "residual Root Proxy marker was not preserved"

# A symlinked state root must be rejected before any helper or log redirection.
ln -s "$PG" "$T/state-link"
if ORDER_LOG="$T/symlink-order.log" PG="$T/state-link" MODDIR="$MOD" sh "$MOD/uninstall.sh" > "$T/symlink.out" 2>&1; then
  fail "uninstall accepted a symlinked FX state directory"
fi
[ ! -e "$T/symlink-order.log" ] || fail "uninstall invoked a helper before rejecting the symlinked state root"
grep -Fq 'state directory is a symlink or non-directory' "$T/symlink.out" || fail "symlinked state root refusal was not reported"
grep -Fq '_FX_SCHEDULER_LOG=/dev/null' "$SOURCE" || fail "uninstall has no safe fallback when scheduler log directory is absent"
grep -Fq '[ ! -L "$_FX_SCHEDULER_STATE_DIR/jsruntime" ]' "$SOURCE" || fail "scheduler log writer does not reject a symlinked runtime directory"
grep -Fq '[ ! -L "$_FX_SCHEDULER_STATE_DIR/jsruntime/scheduler.log" ]' "$SOURCE" || fail "scheduler log writer does not reject dangling log symlinks"

# A symlinked network teardown log must be rejected before either network
# helper runs; the external target must remain untouched.
cat > "$MOD/scripts/vpn-external-watchdog.sh" <<'WATCHDOG'
#!/bin/sh
printf 'vpn-watchdog:%s\\n' "$*" >> "$ORDER_LOG"
WATCHDOG
chmod 0755 "$MOD/scripts/vpn-external-watchdog.sh"
echo outside > "$T/outside-network.log"
ln -s "$T/outside-network.log" "$PG/vpn-external-watchdog.log"
: > "$LOG"
if ORDER_LOG="$LOG" PG="$PG" MODDIR="$MOD" sh "$MOD/uninstall.sh" > "$T/log-link.out" 2>&1; then
  fail "uninstall accepted a symlinked network teardown log"
fi
[ ! -s "$LOG" ] || fail "a helper ran before symlinked teardown log was rejected"
grep -Fxq outside "$T/outside-network.log" || fail "external log target was modified: $(cat "$T/outside-network.log")"
[ -L "$PG/vpn-external-watchdog.log" ] || fail "symlinked network log was removed"
grep -Fq 'network teardown log is a symlink or non-regular file' "$T/log-link.out" || fail "symlinked teardown log refusal was not reported"
rm -f "$PG/vpn-external-watchdog.log"

echo "PASS: FX uninstall safely validates state root, stops Root Proxy before firewall teardown and retires deployment markers only after successful Hook removal"
