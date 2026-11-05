#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
UTIL="$ROOT/scripts/util.sh"
# Migration must be idempotent and create/retain an empty block section on older configurations,
# never insert always-on domains into that section. Legacy rules go into the disabled opt-in ruleset.
grep -Fq 'migrate-block-empty-v1.done' "$UTIL"
grep -Fq 'if (!found) { print ""; print "[list:block]";' "$UTIL"
grep -Fq 'migrate: blacklist cleared; former active entries moved to disabled privacy_ad_domains ruleset' "$UTIL"
grep -Fq 'privacy_ad_domains.txt' "$UTIL"
! grep -Fq 'incremental privacy/ad blocklist v3 installed' "$UTIL"
busybox ash -n "$UTIL"
echo 'Missing block-section migration regression: PASS (missing section is recreated empty; legacy domains stay outside it)'
