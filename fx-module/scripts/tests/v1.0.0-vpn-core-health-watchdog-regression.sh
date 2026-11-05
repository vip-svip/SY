#!/system/bin/sh
# Ensure external-VPN watcher also repairs a degraded managed dataplane even
# when the external VPN state itself has not changed.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
W="$ROOT/scripts/vpn-external-watchdog.sh"
grep -Fq '_core_health_reconcile' "$W"
grep -Fq 'scripts/status.sh' "$W"
grep -Fq '"vpn_on":true' "$W"
grep -Fq '"vpn_on":false' "$W"
grep -Fq "grep -q '^vpn_core=1$'" "$W"
grep -Fq '_node=$(sed -n' "$W"
grep -Fq 'external VPN is' "$W" || grep -Fq 'Do not fight intentional fail-safe suspension' "$W"
grep -Fq '30 ]' "$W"
grep -Fq 'apply.sh" fast' "$W"
sh -n "$W"
printf '%s\n' 'PASS: watchdog checks effective dataplane health and rate-limits managed-core recovery without overriding fail-safe external-VPN states'
