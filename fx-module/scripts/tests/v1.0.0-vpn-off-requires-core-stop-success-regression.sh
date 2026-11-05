#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
APPLY="$ROOT/scripts/apply.sh"
CORE="$ROOT/scripts/vpncore.sh"
grep -Fq 'if ! vpncore_stop; then' "$APPLY"
grep -Fq '停止函数返回成功，但 sing-box PID 记录仍存在' "$APPLY"
grep -Fq 'vpncore_stop 不可用且 PID 记录仍存在' "$APPLY"
grep -Fq 'preserving PID file' "$CORE"
TMP=$(mktemp -d /tmp/fx-vpn-off-stop.XXXXXX)
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
awk '
  /直连模式不需要本地代理核心/ { armed=1 }
  armed && /if command -v vpncore_stop/ { copy=1 }
  copy { print }
  copy && /^  fi$/ { exit }
' "$APPLY" > "$TMP/guard.sh"
[ -s "$TMP/guard.sh" ]

# A real stop failure must be surfaced and its PID record retained.
mkdir -p "$TMP/fail"; : > "$TMP/fail/singbox.pid"
OUT=$(sh -c '
  PG="$1"; export PG; PG_ERRS=0
  pg_fail(){ PG_ERRS=$((PG_ERRS+1)); echo "FAIL:$2"; }
  vpncore_stop(){ echo STOP_CALLED; return 1; }
  . "$2"; [ "$PG_ERRS" -eq 1 ] && [ -e "$PG/singbox.pid" ]
' sh "$TMP/fail" "$TMP/guard.sh" 2>&1)
echo "$OUT" | grep -Fq 'STOP_CALLED'
echo "$OUT" | grep -Fq '托管 sing-box 核心停止失败'

# The apply.sh no-op fallback returns success but leaves the PID marker; reject it.
mkdir -p "$TMP/stub"; : > "$TMP/stub/singbox.pid"
OUT=$(sh -c '
  PG="$1"; export PG; PG_ERRS=0
  pg_fail(){ PG_ERRS=$((PG_ERRS+1)); echo "FAIL:$2"; }
  vpncore_stop(){ :; }
  . "$2"; [ "$PG_ERRS" -eq 1 ] && [ -e "$PG/singbox.pid" ]
' sh "$TMP/stub" "$TMP/guard.sh" 2>&1)
echo "$OUT" | grep -Fq 'PID 记录仍存在'

# A successful stop removes the PID marker and must not report an error.
mkdir -p "$TMP/good"; : > "$TMP/good/singbox.pid"
sh -c '
  PG="$1"; export PG; PG_ERRS=0
  pg_fail(){ PG_ERRS=$((PG_ERRS+1)); }
  vpncore_stop(){ rm -f "$PG/singbox.pid"; return 0; }
  . "$2"; [ "$PG_ERRS" -eq 0 ] && [ ! -e "$PG/singbox.pid" ]
' sh "$TMP/good" "$TMP/guard.sh"

# Missing stop function with a live ownership marker must also fail closed.
mkdir -p "$TMP/missing"; : > "$TMP/missing/singbox.pid"
OUT=$(sh -c '
  PG="$1"; export PG; PG_ERRS=0
  pg_fail(){ PG_ERRS=$((PG_ERRS+1)); echo "FAIL:$2"; }
  . "$2"; [ "$PG_ERRS" -eq 1 ] && [ -e "$PG/singbox.pid" ]
' sh "$TMP/missing" "$TMP/guard.sh" 2>&1)
echo "$OUT" | grep -Fq 'vpncore_stop 不可用且 PID 记录仍存在'
echo 'FX VPN-off requires confirmed core shutdown: PASS'
