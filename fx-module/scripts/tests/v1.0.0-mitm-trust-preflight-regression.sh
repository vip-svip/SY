#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
F="$ROOT/scripts/mitm-redirect.sh"
sh -n "$F"
grep -Fq '_mitm_status=$(sh "$ENGINE" status 2>/dev/null)' "$F"
grep -Fq '"ca_submodule":"released"' "$F"
grep -Fq '"ca_system_trust":"present"' "$F"
grep -Fq 'MITM CA is not confirmed active in the system trust store' "$F"
# Guard must run before listener start and before installing firewall rules.
pre=$(grep -n '_mitm_status=' "$F" | head -n 1 | cut -d: -f1)
start=$(grep -n 'sh "$ENGINE" start' "$F" | head -n 1 | cut -d: -f1)
install=$(grep -n 'if ! install_family' "$F" | head -n 1 | cut -d: -f1)
[ "$pre" -lt "$start" ] && [ "$start" -lt "$install" ]
echo 'MITM trust preflight regression: PASS'
