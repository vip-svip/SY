#!/bin/sh
# Regression: a live PID without a verified listener must not be reported ready.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
SRC="$ROOT/scripts/vpncore.sh"
# Keep the listener probe independent of netstat/curl availability by checking
# the kernel TCP tables, and prohibit the old PID-only success fallback.
grep -Fq '0A' "$SRC"
grep -Fq '/proc/net/tcp' "$SRC"
grep -Fq 'listener probe unavailable; refusing to infer readiness from PID alone' "$SRC"
if grep -Fq '探测不可用按存活判定' "$SRC"; then
  echo 'FAIL: PID-only readiness fallback remains' >&2
  exit 1
fi
grep -Fq '核心进程仍存活但本地端口未监听' "$SRC"
echo 'FX VPN core listener-required regression: PASS'
