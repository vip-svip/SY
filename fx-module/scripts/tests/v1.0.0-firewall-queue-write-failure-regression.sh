#!/system/bin/sh
# Static regression: failed queue append must propagate and prevent both filter and NAT commits.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
B="$ROOT/scripts/apply.sh"
grep -Fq '_IPTQ_WRITE_FAIL=0' "$B"
grep -Fq 'if ! printf' "$B"
grep -Fq '_IPTQ_WRITE_FAIL=1' "$B"
grep -Fq 'queue write failed' "$B"
awk '/^fw_flush\(\) \{/{f=1} f{print} /^\}/{if(f){exit}}' "$B" | grep -Fq 'refusing all queued rule commits'
awk '/^nat_flush\(\) \{/{f=1} f{print} /^\}/{if(f){exit}}' "$B" | grep -Fq 'refusing NAT queue commit'
echo 'PASS: firewall queue write failure blocks filter and NAT commits'
