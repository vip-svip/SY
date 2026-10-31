#!/usr/bin/env python3
"""Prevent manual sing-box shutdown while FX proxy routing is configured."""
from pathlib import Path
import sys

root = Path(sys.argv[1] if len(sys.argv) > 1 else "fx-module")
apply = root / "scripts/apply.sh"
if not apply.is_file():
    raise SystemExit("FX apply.sh is missing")
source = apply.read_text(encoding="utf-8")
old = '''      stop) vpncore_stop; pg_summary "vpn-core-stop" ;;
'''
new = '''      stop)
        # The standalone UI stop button must never kill sing-box while FX
        # proxy interception is configured: REDIRECT rules would then target
        # a dead local listener and strand traffic. Normal VPN-off apply uses
        # the internal vpncore_stop path only after direct-mode cleanup.
        if [ "$(pg_get vpn_mode direct)" != "direct" ]; then
          pg_fail vpn-core "拒绝单独停止核心：FX 代理模式仍启用；请先关闭 VPN（切换直连），由统一应用流程清理流量规则并停止核心"
          pg_summary "vpn-core-stop"
          exit 1
        fi
        vpncore_stop
        _stop_rc=$?
        if [ "$_stop_rc" -eq 0 ] && [ -e "$PG/singbox.pid" ]; then
          pg_fail vpn-core "核心停止命令返回成功但 PID 记录仍存在；不能确认核心已停止"
          _stop_rc=1
        fi
        pg_summary "vpn-core-stop"
        exit "$_stop_rc"
        ;;
'''
if old in source:
    if source.count(old) != 1:
        raise SystemExit("vpn-core stop branch is ambiguous")
    source = source.replace(old, new, 1)
elif new not in source:
    raise SystemExit("vpn-core stop branch changed; refusing unsafe patch")
apply.write_text(source, encoding="utf-8")

# A direct-mode ensure is intentionally a successful no-op in vpncore.sh.
# The manual Start core button must not turn that no-op into a false success;
# only an active proxy mode may start the managed core.
start_old = '''      *)
        # 启动失败时把核心日志最后一行回传给WebUI（写 fd3=原始 stdout）。
'''
start_new = '''      *)
        if [ "$(pg_get vpn_mode direct)" = "direct" ]; then
          pg_fail vpn-core "当前为直连模式，无需启动独立核心；切换全局/规则并选择节点后，VPN 主开关会自动启动核心"
          pg_summary "vpn-core"
          exit 1
        fi
        # 启动失败时把核心日志最后一行回传给WebUI（写 fd3=原始 stdout）。
'''
if start_old in source:
    if source.count(start_old) != 1:
        raise SystemExit("vpn-core start branch is ambiguous")
    source = source.replace(start_old, start_new, 1)
elif start_new not in source:
    raise SystemExit("vpn-core start branch changed; refusing false-success patch")
apply.write_text(source, encoding="utf-8")

test = root / "scripts/tests/v1.0.0-vpn-core-stop-guard-regression.sh"
test.parent.mkdir(parents=True, exist_ok=True)
test.write_text(r'''#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
APPLY="$ROOT/scripts/apply.sh"
grep -Fq '拒绝单独停止核心：FX 代理模式仍启用' "$APPLY"
grep -Fq 'if [ "$(pg_get vpn_mode direct)" != "direct" ]; then' "$APPLY"
grep -Fq 'if [ "$_stop_rc" -eq 0 ] && [ -e "$PG/singbox.pid" ]; then' "$APPLY"
TMP=$(mktemp -d /tmp/fx-vpn-core-stop-guard.XXXXXX)
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
awk '
  /      stop[)]/ {active=1; next}
  active && /        ;;/ {exit}
  active {print}
' "$APPLY" > "$TMP/stop-body.sh"
[ -s "$TMP/stop-body.sh" ]
{ echo 'case x in x)'; cat "$TMP/stop-body.sh"; echo ';; esac'; } > "$TMP/stop-case.sh"

# Proxy/global/rule/TUN modes: reject before invoking stop.
for mode in global rule tun; do
  mkdir -p "$TMP/$mode"; : > "$TMP/$mode/singbox.pid"
  if OUT=$(sh -c '
    PG="$1"; export PG; mode="$2"; PG_ERRS=0
    pg_get(){ [ "$1" = vpn_mode ] && { echo "$mode"; return; }; echo "$2"; }
    pg_fail(){ PG_ERRS=$((PG_ERRS+1)); echo "FAIL:$2"; }
    pg_summary(){ :; }
    vpncore_stop(){ echo STOP_MUST_NOT_RUN; return 0; }
    . "$3"
  ' sh "$TMP/$mode" "$mode" "$TMP/stop-case.sh" 2>&1); then
    echo "FAIL: $mode mode unexpectedly allowed core stop" >&2; exit 1
  fi
  echo "$OUT" | grep -Fq '拒绝单独停止核心'
  ! echo "$OUT" | grep -Fq 'STOP_MUST_NOT_RUN'
done

# Direct mode: stop is allowed, but success requires removal of the PID marker.
mkdir -p "$TMP/direct"; : > "$TMP/direct/singbox.pid"
sh -c '
  PG="$1"; export PG
  pg_get(){ echo direct; }
  pg_fail(){ echo "unexpected failure: $2" >&2; return 1; }
  pg_summary(){ :; }
  vpncore_stop(){ rm -f "$PG/singbox.pid"; return 0; }
  . "$2"
' sh "$TMP/direct" "$TMP/stop-case.sh"
[ ! -e "$TMP/direct/singbox.pid" ]

# A success return with a retained PID marker must be converted to failure.
mkdir -p "$TMP/stale"; : > "$TMP/stale/singbox.pid"
if OUT=$(sh -c '
  PG="$1"; export PG
  pg_get(){ echo direct; }
  pg_fail(){ echo "FAIL:$2"; }
  pg_summary(){ :; }
  vpncore_stop(){ return 0; }
  . "$2"
' sh "$TMP/stale" "$TMP/stop-case.sh" 2>&1); then
  echo 'FAIL: stale PID marker was accepted as stopped' >&2; exit 1
fi
echo "$OUT" | grep -Fq 'PID 记录仍存在'
echo 'FX manual VPN-core stop guard regression: PASS'
''', encoding="utf-8")
test.chmod(0o755)
print("Guarded standalone VPN-core stop against active proxy modes and stale PID ownership.")
