#!/system/bin/sh
# KernelSU uninstall hook: remove only Hook APKs explicitly owned by FX.
MODDIR=${MODDIR:-$(CDPATH= cd -- "$(dirname "$0")" 2>/dev/null && pwd)}
STATE_DIR=${PG:-/data/adb/privacyguard}
_mitm_warn() {
  _msg="PrivacyGuard uninstall warning: $*"
  echo "$_msg" >&2
  if command -v log >/dev/null 2>&1; then log -p w -t PrivacyGuardUninstall "$_msg" 2>/dev/null; fi
}
# FX_QUICKJS_SCHEDULER_STOP_BEGIN
_FX_SCHEDULER_STATE_DIR=${PG:-${STATE_DIR:-/data/adb/privacyguard}}
if [ -f "$MODDIR/scripts/jsruntime/scheduler.sh" ]; then
  if ! sh "$MODDIR/scripts/jsruntime/scheduler.sh" uninstall >> "$_FX_SCHEDULER_STATE_DIR/jsruntime/scheduler.log" 2>&1; then
    echo "FX uninstall: QuickJS scheduler did not confirm shutdown; preserving state and aborting cleanup" >&2
    exit 1
  fi
elif [ -s "$_FX_SCHEDULER_STATE_DIR/jsruntime/scheduler.pid" ]; then
  echo "FX uninstall: scheduler PID record exists but scheduler script is missing; aborting cleanup" >&2
  exit 1
fi
unset _FX_SCHEDULER_STATE_DIR
# FX_QUICKJS_SCHEDULER_STOP_END
# Retire FX-owned Root Proxy redirects before any firewall teardown. The helper
# owns only FXYRP chains and preserves independently enabled DNS engines.
# If its cleanup cannot be confirmed, keep module state and abort uninstall.
if [ -f "$MODDIR/scripts/yulong-root-proxy.sh" ]; then
  if ! MP="$MODDIR" PG="$STATE_DIR" CONF="$STATE_DIR/settings.conf" \
      sh "$MODDIR/scripts/yulong-root-proxy.sh" uninstall >> "$STATE_DIR/yulong-root-proxy.log" 2>&1; then
    _mitm_warn "Root Proxy cleanup was not confirmed; preserving state and aborting uninstall"
    exit 1
  fi
elif [ -e "$STATE_DIR/yulong-root-proxy-active" ] || \
     [ -e "$STATE_DIR/yulong-root-proxy-active.meta" ] || \
     [ -e "$STATE_DIR/unbound-vpn-egress-ip" ]; then
  _mitm_warn "Root Proxy state exists but its cleanup helper is missing; preserving state and aborting uninstall"
  exit 1
fi
# Stop Yulong ad schedule before uninstall; never re-apply ad rules during removal.
if [ -x "$MODDIR/scripts/yulong-ad-schedule.sh" ]; then
  if ! sh "$MODDIR/scripts/yulong-ad-schedule.sh" stop "$MODDIR" "$STATE_DIR" uninstall >> "$STATE_DIR/yulong-ad-schedule.log" 2>&1; then
    _mitm_warn "could not confirm stopping Yulong ad schedule watcher; preserving state and aborting cleanup"
    exit 1
  fi
elif [ -s "$STATE_DIR/yulong-ad-schedule.pid" ]; then
  _mitm_warn "Yulong ad schedule PID record exists but scheduler is missing; preserving state and aborting cleanup"
  exit 1
fi
if [ -f "$MODDIR/scripts/yulong-app-firewall.sh" ]; then
  sh "$MODDIR/scripts/yulong-app-firewall.sh" uninstall >/dev/null 2>&1 || :
fi
if [ -x "$MODDIR/scripts/yulong-trusted-network.sh" ]; then
  sh "$MODDIR/scripts/yulong-trusted-network.sh" uninstall >> "$STATE_DIR/yulong-trusted-network.log" 2>&1 || :
fi
REMOVER="$MODDIR/scripts/remove_adhook_app.sh"
if [ -f "$REMOVER" ]; then
  sh "$REMOVER" "$MODDIR" "$STATE_DIR"
  _rc=$?
  if [ "$_rc" -ne 0 ]; then
    echo "FX uninstall: one or more FX-owned Hook packages could not be removed; see $STATE_DIR/adhook-install.log" >&2
  fi
  exit "$_rc"
fi
echo "FX uninstall: Hook remover missing; leaving installed packages untouched" >&2
exit 0
