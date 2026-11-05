#!/system/bin/sh
# Verify watchdog PID publication/start/stop without racing a deliberately disabled
# option against the parent's live-child check. Disabled-mode exit remains a static
# guard; the runtime test models the true production precondition (both engines ready).
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
T=$(mktemp -d "${TMPDIR:-/tmp}/fx-localdns-watchdog.XXXXXX")
cleanup() {
  if [ -s "$T/state/localdns-watchdog.pid" ]; then
    sh "$T/mod/scripts/localdns-watchdog.sh" stop "$T/mod" "$T/state" >/dev/null 2>&1 || kill "$(cat "$T/state/localdns-watchdog.pid" 2>/dev/null)" 2>/dev/null || :
  fi
  sleep 0.2 2>/dev/null || :
  rm -rf "$T"
}
trap cleanup EXIT HUP INT TERM
mkdir -p "$T/mod/scripts" "$T/state/adguardhome" "$T/state/unbound"
cp "$ROOT/scripts/localdns-watchdog.sh" "$T/mod/scripts/localdns-watchdog.sh"
chmod 755 "$T/mod/scripts/localdns-watchdog.sh"
cat > "$T/state/settings.conf" <<'EOF_SETTINGS'
dns_engine_adguardhome=1
EOF_SETTINGS
# Managed PID markers must be non-empty: production intentionally treats an empty
# marker as an engine-not-ready condition and exits before publishing liveness.
printf '101\n' > "$T/state/adguardhome/managed.pid"
printf '102\n' > "$T/state/unbound/managed.pid"
cat > "$T/mod/scripts/adguardhome.sh" <<'EOF_AGH'
#!/system/bin/sh
[ "${1:-}" = status ] && exit 0
exit 0
EOF_AGH
chmod 755 "$T/mod/scripts/adguardhome.sh"
# Static safety properties: firewall transactions remain exclusively in apply.sh.
grep -Fq 'PID ownership was not published in time' "$T/mod/scripts/localdns-watchdog.sh"
! grep -Fq '_setting_enabled' "$T/mod/scripts/localdns-watchdog.sh"
grep -Fq 'sh "$MODDIR/scripts/apply.sh" fast' "$T/mod/scripts/localdns-watchdog.sh"
grep -Fq 'sh "$MODDIR/scripts/adguardhome.sh" status "$MODDIR" "$PG"' "$T/mod/scripts/localdns-watchdog.sh"
grep -Fq 'sleep 30' "$T/mod/scripts/localdns-watchdog.sh"
! grep -Fq 'sleep 90' "$T/mod/scripts/localdns-watchdog.sh"
! grep -Fq 'sh "$MODDIR/scripts/unbound.sh" status' "$T/mod/scripts/localdns-watchdog.sh"
if grep -Eiq 'iptables|ip6tables|nft[[:space:]]' "$T/mod/scripts/localdns-watchdog.sh"; then
  echo 'FAIL: watchdog mutates firewall state outside the apply transaction' >&2; exit 1
fi
sh "$T/mod/scripts/localdns-watchdog.sh" start "$T/mod" "$T/state"
[ -s "$T/state/localdns-watchdog.pid" ] || { echo 'FAIL: watchdog did not publish PID marker'; exit 1; }
_p=$(cat "$T/state/localdns-watchdog.pid")
case "$_p" in ''|*[!0-9]*) echo 'FAIL: malformed watchdog PID' >&2; exit 1;; esac
sh "$T/mod/scripts/localdns-watchdog.sh" stop "$T/mod" "$T/state"
_i=0
while [ "$_i" -lt 30 ] && [ -e "$T/state/localdns-watchdog.pid" ]; do sleep 0.1; _i=$((_i+1)); done
[ ! -e "$T/state/localdns-watchdog.pid" ] || { echo 'FAIL: watchdog PID marker remained after verified stop'; exit 1; }
echo 'PASS: watchdog start/stop, healthy-chain gates, PID publication, automatic-mode lifecycle, firewall-transaction ownership'
