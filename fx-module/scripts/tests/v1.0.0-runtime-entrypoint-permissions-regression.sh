#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
required="service.sh post-fs-data.sh customize.sh action.sh uninstall.sh scripts/apply.sh scripts/whitelist.sh scripts/sync-mitm-hosts.sh scripts/localdns-watchdog.sh scripts/external-vpn-probe.sh scripts/mitm-redirect-watch.sh scripts/sync-urlrewrite.sh scripts/unbound.sh scripts/mitm-listener-health.sh scripts/vpn-external-watchdog.sh scripts/mitm-redirect.sh scripts/adguardhome.sh scripts/mitm-engine.sh scripts/jsruntime/runner.sh scripts/jsruntime/scheduler.sh scripts/jsruntime/sync-subs.sh scripts/jsruntime/http.sh bin/arm64/qjs bin/arm64/sing-box bin/arm64/pg-mitm bin/arm/sing-box"
for rel in $required; do
  [ -f "$ROOT/$rel" ] || { echo "FAIL: required runtime entry missing: $rel"; exit 1; }
  [ -x "$ROOT/$rel" ] || { echo "FAIL: runtime entry lost executable permission: $rel"; exit 1; }
done
# The ARM64 QuickJS runtime must be present and match its packaged SHA-256 sidecar.
if command -v sha256sum >/dev/null 2>&1 && [ -s "$ROOT/bin/arm64/qjs.sha256" ]; then
  expected=$(awk 'NR==1 {print $1}' "$ROOT/bin/arm64/qjs.sha256")
  actual=$(sha256sum "$ROOT/bin/arm64/qjs" | awk '{print $1}')
  [ "$expected" = "$actual" ] || { echo 'FAIL: QuickJS SHA-256 sidecar mismatch'; exit 1; }
fi
echo 'FX runtime entrypoint permissions regression: PASS'
