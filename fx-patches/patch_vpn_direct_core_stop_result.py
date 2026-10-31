#!/usr/bin/env python3
"""Make VPN-off fail visibly unless the FX-owned sing-box core is confirmed stopped."""
from pathlib import Path
import sys

root = Path(sys.argv[1] if len(sys.argv) > 1 else "fx-module")
apply = root / "scripts/apply.sh"
if not apply.is_file():
    raise SystemExit("FX apply.sh is missing")

source = apply.read_text(encoding="utf-8")
old = '''  if command -v vpncore_stop >/dev/null 2>&1; then
    vpncore_stop
  fi
'''
new = '''  if command -v vpncore_stop >/dev/null 2>&1; then
    if ! vpncore_stop; then
      pg_fail vpn "直连模式已清理流量接管规则，但托管 sing-box 核心停止失败；保留 PID 记录并报告关闭失败（详见 vpncore.log）"
    elif [ -e "$PG/singbox.pid" ]; then
      pg_fail vpn "直连模式停止函数返回成功，但 sing-box PID 记录仍存在；无法确认核心已停止，保留记录并报告关闭失败"
    fi
  elif [ -e "$PG/singbox.pid" ]; then
    pg_fail vpn "直连模式无法确认托管 sing-box 核心已停止：vpncore_stop 不可用且 PID 记录仍存在；保留记录并报告关闭失败"
  fi
'''
if source.count(old) == 0:
    if new in source:
        print("VPN-off core-stop confirmation already present.")
    else:
        raise SystemExit("direct-mode vpncore_stop anchor changed; refusing unsafe patch")
elif source.count(old) != 1:
    raise SystemExit("direct-mode vpncore_stop anchor is ambiguous")
else:
    source = source.replace(old, new, 1)
    apply.write_text(source, encoding="utf-8")

test = root / "scripts/tests/v1.0.0-vpn-off-requires-core-stop-success-regression.sh"
test.write_text(r'''#!/system/bin/sh
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
''', encoding="utf-8")
test.chmod(0o755)
print("VPN-off now requires both successful stop and removal of the managed PID marker; expanded regression added.")
