#!/system/bin/sh
# Regression: ownership must use exact argv boundaries, not command-line substrings.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
SRC="$ROOT/scripts/vpncore.sh"
TMP="${TMPDIR:-/tmp}/fx-pid-owner.$$"
trap 'rm -f "$TMP"' EXIT HUP INT TERM
awk 'BEGIN{p=0} /^vpncore_pid_matches\(\) \{/ {p=1} p{print} p && /^\}/ {exit}' "$SRC" > "$TMP"
grep -Fq "tr '\\000' '\\n'" "$TMP"
grep -Fq 'exe != "sing-box"' "$TMP"
grep -Fq 'prev == "-c" || prev == "--config"' "$TMP"
grep -Fq '$0 == cfg' "$TMP"
! grep -Fq '*sing-box*"$PG/singbox.json"*' "$TMP"
sh -n "$SRC"
echo 'FX VPN core PID ownership regression: PASS'
