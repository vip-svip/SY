#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
U="$ROOT/uninstall.sh"
grep -Fq 'PG_FW_INCOMPLETE=0' "$U"
grep -Fq 'PG_CLEANUP_INCOMPLETE=0' "$U"
grep -Fq '_pg_fw_warn() { PG_FW_INCOMPLETE=1; _mitm_warn' "$U"
grep -Fq 'PG_FW_INCOMPLETE=1; _mitm_warn' "$U"
! grep -Fq '_pg_fw_warn() { PG_FW_INCOMPLETE=1; PG_CLEANUP_INCOMPLETE=1;' "$U"
grep -Fq 'PG_CLEANUP_INCOMPLETE=1' "$U"
grep -Fq 'PG_KEEP_DATA=1' "$U"
grep -Fq '为保护重试所需的状态、脚本或挂载源，已保留' "$U"
grep -Fq 'could not verify Settings restore' "$U"
grep -Fq 'if [ "$PG_FW_INCOMPLETE" = 1 ]; then' "$U"
grep -Fq '模块自有防火墙链与已跟踪恢复步骤未报告残留' "$U"
sh -n "$U"
echo 'FX uninstall cleanup status regression: PASS'
