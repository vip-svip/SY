#!/system/bin/sh
# Truthful capability report. The MITM redirect is a separate, explicit opt-in
# action exposed by WebUI and mitm-redirect.sh; it is intentionally not installed
# by apply.sh/boot. Runtime health includes a kernel TCP-listener check.
MODDIR=${PG_MODDIR:-${MODDIR:-}}
if [ -z "$MODDIR" ] || [ ! -f "$MODDIR/module.prop" ]; then
  _d=$(cd "$(dirname "$0")" 2>/dev/null && pwd)
  case "$_d" in */scripts) _d=${_d%/scripts} ;; esac
  MODDIR=$_d
fi
if [ ! -x "$MODDIR/bin/arm64/pg-mitm" ] && [ ! -x "$MODDIR/bin/arm/pg-mitm" ]; then
  echo '{"ok":false,"status":"https-mitm-engine-missing","detail":"MITM binary is absent; system CA trust alone does not decrypt HTTPS."}'
  exit 2
fi
if [ ! -x "$MODDIR/scripts/mitm-engine.sh" ] || [ ! -x "$MODDIR/scripts/mitm-redirect.sh" ] || [ ! -x "$MODDIR/scripts/mitm-listener-health.sh" ]; then
  echo '{"ok":false,"status":"https-mitm-control-plane-incomplete","detail":"Required lifecycle/redirect/listener health scripts are missing."}'
  exit 2
fi
_redirect=$(sh "$MODDIR/scripts/mitm-redirect.sh" status 2>/dev/null)
_redirect_rc=$?
case "$_redirect" in
  *'"ipv4_redirect":"enabled"'*'"listener":"running"'*'"health":"ok"'*)
    echo '{"ok":true,"status":"https-mitm-redirect-enabled-experimental","scope":"IPv4 public TCP/443 only; explicit opt-in; CA trust required; HTTP/1.1 only; IPv6/QUIC untouched"}'
    exit 0
    ;;
  *'"ipv4_redirect":"enabled"'*)
    echo '{"ok":false,"status":"https-mitm-redirect-degraded","detail":"Redirect exists but listener health is not good; disable the redirect and inspect engine.log before use."}'
    exit 2
    ;;
  *'"ipv4_redirect":"disabled"'*)
    echo '{"ok":true,"status":"https-mitm-available-redirect-disabled","detail":"Backend and explicit UI/CLI opt-in are present. It is not auto-enabled by apply.sh or boot. Enable only after CA trust is verified and device testing is available."}'
    exit 0
    ;;
  *'"ipv4_redirect":"partial"'*|*'"ipv4_redirect":"orphaned-chain"'*)
    echo '{"ok":false,"status":"https-mitm-firewall-state-needs-recovery","detail":"Owned redirect chain is partial/orphaned; inspect and clean it before enabling."}'
    exit 2
    ;;
  *)
    if [ "$_redirect_rc" -eq 0 ]; then _state=unknown; else _state=unverifiable; fi
    printf '{"ok":false,"status":"https-mitm-redirect-%s","detail":"Firewall state could not be positively verified; no automatic cleanup was attempted."}\n' "$_state"
    exit 2
    ;;
esac
