#!/system/bin/sh
# Appended duplicate list sections must participate in the real list reader.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
TMP=${TMPDIR:-/tmp}/fx-list-merge.$$
mkdir -p "$TMP"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
printf '\357\273\277[list:rule]\nhttps://one.example/list.txt|first|1\n[list:fx]\nDOMAIN-SUFFIX,one.example,REJECT|first fx|1\n[list:rule]\nhttps://two.example/list.txt|appended|1\nhttps://off.example/list.txt|disabled|0\n[list:fx]\nDOMAIN-SUFFIX,two.example,REJECT|second fx|1\n' > "$TMP/settings.conf"
out=$(PG="$TMP" CONF="$TMP/settings.conf" sh -c '. "$1/scripts/util.sh"; pg_list_enabled rule; echo --FX--; pg_list_enabled fx' sh "$ROOT")
printf '%s\n' "$out" | grep -Fxq 'https://one.example/list.txt'
printf '%s\n' "$out" | grep -Fxq 'https://two.example/list.txt'
[ "$(printf '%s\n' "$out" | grep -Fc 'https://off.example/list.txt' || true)" -eq 0 ]
printf '%s\n' "$out" | grep -Fxq 'DOMAIN-SUFFIX,one.example,REJECT'
printf '%s\n' "$out" | grep -Fxq 'DOMAIN-SUFFIX,two.example,REJECT'
[ "$(printf '%s\n' "$out" | grep -Fc 'https://two.example/list.txt')" -eq 1 ]
echo 'FX list duplicate-section merge and BOM regression: PASS'
