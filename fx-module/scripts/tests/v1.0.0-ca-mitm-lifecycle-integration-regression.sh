#!/system/bin/sh
# Regression guard for upgrade-safe CA trust and the explicit MITM lifecycle UI.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
CUSTOM="$ROOT/customize.sh"
SERVICE="$ROOT/service.sh"
APPLY="$ROOT/scripts/apply.sh"
UI="$ROOT/webroot/index.html"
ENGINE="$ROOT/scripts/mitm-engine.sh"
REDIRECT="$ROOT/scripts/mitm-redirect.sh"
fail(){ echo "FAIL: $*" >&2; exit 1; }
[ -f "$CUSTOM" ] && [ -f "$SERVICE" ] && [ -f "$APPLY" ] && [ -f "$UI" ] || fail 'required source is missing'
# Upgrade must preserve explicit opt-in. First installation still defaults to disabled.
grep -Fq '[ ! -f /data/adb/privacyguard/ca-trust-optin ]' "$CUSTOM" || fail 'default-off install guard missing'
grep -Fq 'ca-trust-optin' "$CUSTOM" || fail 'CA opt-in persistence logic missing'
if grep -Eq 'rm[[:space:]]+-f[[:space:]]+/data/adb/privacyguard/ca-trust-optin' "$CUSTOM"; then fail 'installer deletes explicit CA opt-in'; fi
# APEX/system trust is synced only after boot, and only if user previously opted in.
grep -Fq '[ -f "$PG/ca-trust-optin" ]' "$SERVICE" || fail 'post-boot CA opt-in guard missing'
grep -Fq 'builtin sync' "$SERVICE" || fail 'post-boot CA trust sync missing'
# apply must not wait on a nonexistent background CA job.
if grep -q '_CERT_BG_PID' "$APPLY"; then fail 'orphan CA background PID remains in apply.sh'; fi
grep -Fq 'wait "$_XPOSED_BG_PID"' "$APPLY" || fail 'LSPosed background job is not joined'
# MITM traffic UI must call real backend actions, not a visual-only switch.
for marker in 'id="mitmTrafficCard"' 'id="mitmTrafficRefresh"' 'id="mitmTrafficEnable"' 'id="mitmTrafficDisable"' 'function pgMitmTrafficAction' 'scripts/mitm-redirect.sh status'; do
  grep -Fq "$marker" "$UI" || fail "MITM UI marker missing: $marker"
done
# A MITM-specific enable must initialize and trust the runtime CA, not just release a static template.
grep -Fq "scripts/mitm-engine.sh trust-ca" "$UI" || fail 'runtime CA trust integration missing'
grep -Fq "scripts/mitm-engine.sh untrust-ca" "$UI" || fail 'MITM CA untrust integration missing'
grep -Fq "scripts/mitm-redirect.sh disable" "$UI" || fail 'cleanup-before-CA-mutation integration missing'
# Stable module IDs are used to dispatch backend mutations.
grep -Fq "esc(c.id||c.name)" "$UI" || fail 'CA actions still use labels instead of stable ids'
# Backend primitives remain present and explicit opt-in; no implicit boot/install redirect.
grep -Fq 'trust-ca)' "$ENGINE" || fail 'runtime CA trust operation missing'
grep -Fq 'sync_runtime_cert_to_child' "$ENGINE" || fail 'runtime CA is not synced into an already released child module'
grep -Fq 'enable)' "$REDIRECT" || fail 'explicit redirect enable operation missing'
grep -Fq 'disable)' "$REDIRECT" || fail 'explicit redirect disable operation missing'
sh -n "$CUSTOM"
sh -n "$SERVICE"
sh -n "$APPLY"
sh -n "$ENGINE"
sh -n "$REDIRECT"
echo 'PASS: CA upgrade persistence, post-boot trust restoration, and MITM UI/backend lifecycle are connected'
