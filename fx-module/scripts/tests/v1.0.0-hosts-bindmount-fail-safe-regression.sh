#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
U="$ROOT/scripts/util.sh"
T=$(mktemp -d "${TMPDIR:-/tmp}/fx-host-bindmount.XXXXXX")
trap 'rm -rf "$T"' EXIT HUP INT TERM
awk '/^pg_commit_hosts_candidate\(\) \{/ {p=1} p {print} p && /^}/ {exit}' "$U" > "$T/function.sh"
[ -s "$T/function.sh" ]
grep -Fq 'pg_hosts_mount_state' "$T/function.sh"
grep -Fq '无法卸载 /system/etc/hosts bind mount；保留旧 hosts，跳过替换' "$T/function.sh"
grep -Fq '被其他模块挂载；拒绝替换并保留现有挂载' "$T/function.sh"
backup=$(grep -n 'mv "$PG/hosts" "$_hc_backup"' "$T/function.sh" | cut -d: -f1)
commit=$(grep -n 'mv "$_hc_candidate" "$PG/hosts"' "$T/function.sh" | cut -d: -f1)
restore=$(grep -n 'mv "$_hc_backup" "$PG/hosts"' "$T/function.sh" | cut -d: -f1)
[ -n "$backup" ] && [ -n "$commit" ] && [ -n "$restore" ]
[ "$backup" -lt "$commit" ] && [ "$commit" -lt "$restore" ]
grep -Fq 'pg_hosts_mount_state_from_text' "$U"
grep -Fq 'foreign /system/etc/hosts mount preserved' "$ROOT/scripts/apply.sh"
sh -n "$ROOT/scripts/apply.sh"
echo 'FX hosts bind-mount/transaction fail-safe regression: PASS'
