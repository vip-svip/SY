#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
T=$(mktemp -d "${TMPDIR:-/tmp}/fx-rule-recover.XXXXXX")
trap 'rm -rf "$T"' EXIT HUP INT TERM
mkdir -p "$T/pg/cache" "$T/pg/local"
# Simulate the state after the earlier buggy local migration removed user rules,
# while its pre-migration backup still contains the original user source rows.
cat > "$T/settings.conf" <<'__CURRENT__'
fx=0
vpn_mode=direct
[list:rule]
builtin://NoAppDownload.txt|当前本地网页规则|1
[list:block]
[list:fx]
__CURRENT__
cat > "$T/pg/cache/settings.conf.pre-empty-block-v1.bak" <<'__BACKUP__'
fx=0
vpn_mode=direct
[list:rule]
https://recovered.example/custom.txt|备份恢复的用户订阅|1
https://another.example/privacy.txt|备份恢复的隐私清单|0
builtin://NoAppDownload.txt|旧本地网页规则|1
[list:block]
[list:fx]
__BACKUP__
: > "$T/pg/cache/migrate-block-empty-v1.done"
: > "$T/pg/cache/rule_catalog_local_adult_sources_v1.done"
PG="$T/pg" CONF="$T/settings.conf" MODDIR="$ROOT" sh -c '
  . "$1/scripts/util.sh"
  pg_migrate_lists
  rows=$(pg_list rule)
  printf "%s\\n" "$rows" | grep -Fq "https://recovered.example/custom.txt|备份恢复的用户订阅|1"
  printf "%s\\n" "$rows" | grep -Fq "https://another.example/privacy.txt|备份恢复的隐私清单|0"
  [ "$(printf "%s\\n" "$rows" | grep -Fc "https://recovered.example/custom.txt|")" -eq 1 ]
  [ "$(printf "%s\\n" "$rows" | grep -Fc "builtin://NoAppDownload.txt|")" -eq 1 ]
' sh "$ROOT"
echo 'PASS: missing user rule sources are recovered once from the pre-migration backup without overwriting current states'
