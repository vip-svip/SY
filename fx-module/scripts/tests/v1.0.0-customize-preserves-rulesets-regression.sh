#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
CUSTOMIZE="$ROOT/customize.sh"
CONF="$ROOT/scripts/default.conf"
# The installer must not strip builtin rules or user subscription sources after migration.
if grep -A12 -B2 'Preserve rule-set configuration on upgrade' "$CUSTOMIZE" | grep -Eq 'settings\.conf\.pgnew|^ *awk'; then
  echo 'FAIL: destructive blanket rules cleanup remains in customize.sh' >&2; exit 1
fi
for token in \
 'builtin://NoAppDownload.txt|' \
 'builtin://Adblock_Watermark.txt|' \
 'builtin://privacy_ad_domains|' \
 'https://raw.githubusercontent.com/TG-Twilight/AWAvenue-Ads-Rule/main/Filters/AWAvenue-Ads-Rule-Adblock.txt|' \
 'https://adguardteam.github.io/HostlistsRegistry/assets/filter_24.txt|' \
 'https://raw.githubusercontent.com/hagezi/dns-blocklists/main/adblock/pro.txt|'; do
  grep -Fq "$token" "$CONF" || { echo "FAIL: missing packaged rule source $token" >&2; exit 1; }
done
grep -Fq 'pg_migrate_lists()' "$ROOT/scripts/util.sh"
busybox ash -n "$CUSTOMIZE"
echo 'PASS: installer no longer deletes built-in rules or prior rule subscriptions after migration'
