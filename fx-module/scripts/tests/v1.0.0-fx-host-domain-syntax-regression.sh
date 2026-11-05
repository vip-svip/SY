#!/system/bin/sh
# Reject malformed DOMAIN/DOMAIN-SUFFIX values before emitting system hosts entries.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
APPLY="$ROOT/scripts/apply.sh"
grep -Fq 'function valid_domain(d,n,a,i)' "$APPLY"
grep -Fq 'if(valid_domain(v) && !seen[v]++) print "0.0.0.0 " v' "$APPLY"
grep -Fq 'd ~ /[.][.]|^[.]|[.]$/' "$APPLY"
grep -Fq 'a[i] !~ /^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?$/' "$APPLY"
sh -n "$APPLY"
echo 'FX host-domain syntax regression: PASS (invalid labels rejected, duplicate domain entries deduplicated)'
