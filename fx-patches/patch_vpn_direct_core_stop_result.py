#!/usr/bin/env python3
"""Make VPN-off fail visibly if the FX-owned sing-box core cannot be stopped."""
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
    fi
  elif [ -s "$PG/singbox.pid" ]; then
    pg_fail vpn "直连模式无法确认托管 sing-box 核心已停止：vpncore_stop 不可用且 PID 记录仍存在；保留记录并报告关闭失败"
  fi
'''
if source.count(old) == 0:
    if new in source:
        print("VPN-off core-stop failure handling already present.")
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
grep -Fq '托管 sing-box 核心停止失败' "$APPLY"
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
OUT=$(sh -c '
  PG="$1"; export PG
  PG_ERRS=0
  pg_fail(){ PG_ERRS=$((PG_ERRS+1)); echo "FAIL:$2"; }
  vpncore_stop(){ echo "STOP_CALLED"; return 1; }
  . "$2"
  [ "$PG_ERRS" -eq 1 ]
' sh "$TMP" "$TMP/guard.sh" 2>&1)
echo "$OUT" | grep -Fq 'STOP_CALLED'
echo "$OUT" | grep -Fq '托管 sing-box 核心停止失败'
echo 'FX VPN-off requires successful core shutdown: PASS'
''', encoding="utf-8")
test.chmod(0o755)
print("VPN-off now fails visibly when the managed core cannot be stopped; regression added.")
