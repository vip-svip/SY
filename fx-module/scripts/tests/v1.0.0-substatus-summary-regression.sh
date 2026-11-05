#!/system/bin/sh
# Audit101: summary must aggregate the latest result for each source and optional type.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
S="$ROOT/scripts/substatus.sh"
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT HUP INT TERM
PG="$t/pg"; export PG
sh "$S" record rule https://example.test/a ok downloaded 12
sh "$S" record rule https://example.test/b fail timeout 0
sh "$S" record rule https://example.test/a cached fallback 12
sh "$S" record vpnsub node-list partial "one invalid" 3
# Pipe characters must not corrupt the pipe-delimited database or JSON fields.
sh "$S" record rule 'https://example.test/a|variant' fail 'server|returned|error' 0
all=$(sh "$S" summary)
rule=$(sh "$S" summary rule)
printf '%s' "$all" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["total"]==4,d; assert d["cached_count"]==1,d; assert d["fail_count"]==2,d; assert d["partial_count"]==1,d'
printf '%s' "$rule" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["total"]==3,d; assert d["cached_count"]==1,d; assert d["fail_count"]==2,d; assert d["partial_count"]==0,d'
items=$(sh "$S" get rule)
printf '%s' "$items" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert any("%7Cvariant" in x["key"] and "server%7Creturned%7Cerror" in x["detail"] for x in d["items"]),d'
# Summary must be valid JSON when there is no database yet.
PG="$t/empty"; export PG
empty=$(sh "$S" summary)
printf '%s' "$empty" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["total"]==0 and d["fail_count"]==0,d'
echo 'PASS: substatus summary aggregates latest per-source status and filters by type'
