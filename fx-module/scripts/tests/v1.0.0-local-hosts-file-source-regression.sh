#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT HUP INT TERM
mkdir -p "$T/pg/local" "$T/pg/cache"
cat > "$T/pg/settings.conf" <<'CONF'
[list:hosts_local]
0.0.0.0 enabled.example|Enabled legacy entry|1
127.0.0.1 disabled.example|Disabled legacy entry|0
# comment|ignored|1
CONF
printf '127.0.0.1 existing.local\n' > "$T/pg/local/hosts"
PG="$T/pg" CONF="$T/pg/settings.conf" sh -c '. "$1/scripts/util.sh"; pg_migrate_lists; pg_migrate_lists' sh "$ROOT"
F="$T/pg/local/hosts"
[ -f "$F" ] || { echo 'FAIL: canonical local hosts file missing'; exit 1; }
grep -Fxq '127.0.0.1 existing.local' "$F"
grep -Fxq '0.0.0.0 enabled.example' "$F"
grep -Fxq '# disabled legacy hosts entry: 127.0.0.1 disabled.example' "$F"
test -f "$T/pg/cache/hosts-local-list-migrated-v1"
before=$(wc -l < "$F")
PG="$T/pg" CONF="$T/pg/settings.conf" sh -c '. "$1/scripts/util.sh"; pg_migrate_lists' sh "$ROOT"
after=$(wc -l < "$F")
[ "$before" = "$after" ] || { echo 'FAIL: repeated migration duplicated lines'; exit 1; }
# Apply consumes only the canonical file, not the old section as a second source.
if grep -Fq 'pg_list_enabled hosts_local' "$ROOT/scripts/apply.sh"; then echo 'FAIL: apply still separately merges legacy hosts_local rows'; exit 1; fi
grep -Fq 'if [ ! -f "$PG/local/hosts" ] && [ -f "$PG/hosts.local" ]; then' "$ROOT/scripts/apply.sh"
UI_FILE="$ROOT/../adhook/app/src/main/assets/webroot/index.html"
[ -f "$UI_FILE" ] || UI_FILE="$ROOT/webroot/index.html"
python3 - "$UI_FILE" <<'PY'
from pathlib import Path
import sys
s=Path(sys.argv[1]).read_text()
assert 'function feRenderHosts(gen)' in s
assert "feCmd('stat','hosts','')" in s
assert 'hostsOpenEditor' in s
assert 'FX hosts 文件与系统生效视图' in s
assert 'data-hosts-view' in s and 'data-hosts-edit' in s
assert "feOpen('system-hosts'" in s
assert "feOpen('hosts'" in s
assert '独立于下载订阅' in s
assert '打开分页编辑器' in s
start=s.index('function feRenderHosts(gen){')
end=s.index('/* ---------- 事件：编辑器按钮 / 分页编辑 ---------- */',start)
fn=s[start:end]
assert "feCmd('stat','hosts','')" in fn
assert 'hosts-file-summary' in fn
assert 'feRows(' not in fn and '.fe-hrow' not in fn
assert "feCmd('page','hosts','1 200 65536')" not in fn
print('FX local hosts single-file UI regression: PASS')
PY
echo 'FX local hosts migration and source-separation regression: PASS'
