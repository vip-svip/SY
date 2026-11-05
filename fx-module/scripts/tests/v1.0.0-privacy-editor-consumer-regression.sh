#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
HTML="$ROOT/webroot/index.html"
CONF="$ROOT/scripts/default.conf"
EARLY="$ROOT/post-fs-data.sh"
HOOK="$ROOT/lsposed/app/src/main/java/de/privacyguard/hook/MainHook.java"
fail(){ echo "FAIL: $*" >&2; exit 1; }
# Startup property editor must use the exact key consumed at boot.
grep -Fq 'uptime=3600' "$HTML" || fail 'boot-time editor must write uptime integer'
grep -Fq "grep -m1 '^uptime='" "$EARLY" || fail 'boot-time parser must consume uptime'
# Switch-only settings must not expose editors that save unconsumed pseudo-config.
for key in crash anr usagestats a11y; do
  if grep -Fq "data-misc-edit=\"$key\"" "$HTML"; then fail "$key is switch-only and must not open a pseudo-editor"; fi
done
! grep -Fq 'data-misc-edit="props"' "$HTML" || fail 'property randomization pseudo-editor must remain absent'
# sys-service hook consumes plain service names, not key=value directives.
grep -Fq 'MainHook 按行读取服务名；不要写 key=value' "$HTML" || fail 'system-service editor must document line-based parser'
grep -Fq 'private void usageHide()' "$HOOK" || fail 'UsageStats hook missing'
grep -Fq 'if (!on("usagestats_off")) return;' "$HOOK" || fail 'UsageStats hook must be controlled by switch'
echo 'PASS: privacy editors only expose parser-backed settings and switch-only controls do not save fake config'
