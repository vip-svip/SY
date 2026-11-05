#!/system/bin/sh
# Regression: when cleanup is incomplete, do not delete possible live overlay sources.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
U="$ROOT/uninstall.sh"
python3 - "$U" <<'PYCODE'
from pathlib import Path
import sys
s=Path(sys.argv[1]).read_text()
start=s.index('# A9. 崩溃归因 / 转换器 / 信任库覆盖层构建残留清理')
end=s.index('if [ "$PG_KEEP_DATA" = 1 ]; then\n  echo "PrivacyGuard 清理未完全完成', start)
block=s[start:end]
assert 'if [ "$PG_KEEP_DATA" = 1 ]; then' in block
assert 'preserving certificate-overlay temporary paths' in block
assert block.index('if [ "$PG_KEEP_DATA" = 1 ]; then') < block.index('rm -rf /data/local/tmp/pg-trunc-cacerts*')
assert block.index('else') < block.index('rm -rf /data/local/tmp/pg-trunc-cacerts*')
assert 'rm -f /data/local/tmp/live.lst /data/local/tmp/ovl.lst /data/local/tmp/diff.txt' in block
PYCODE
sh -n "$U"
echo 'FX uninstall incomplete certificate-overlay source preservation regression: PASS'
