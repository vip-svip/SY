#!/system/bin/sh
# Exercise the AdGuard Home manager lifecycle with a harmless fake server binary.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
T=$(mktemp -d "${TMPDIR:-/tmp}/fx-agh-runtime.XXXXXX")
cleanup() {
  if [ -x "$T/mod/scripts/adguardhome.sh" ]; then
    sh "$T/mod/scripts/adguardhome.sh" stop "$T/mod" "$T/state" >/dev/null 2>&1 || :
  elif [ -x "$T/mod/scripts/unbound.sh" ]; then
    sh "$T/mod/scripts/unbound.sh" stop "$T/mod" "$T/state" >/dev/null 2>&1 || :
  fi
  rm -rf "$T"
}
trap cleanup EXIT HUP INT TERM
mkdir -p "$T/mod/scripts" "$T/mod/engines/adguardhome" "$T/mod/engines/unbound" "$T/mod/fxrules" "$T/bin" "$T/state"
cp "$ROOT/scripts/adguardhome.sh" "$T/mod/scripts/adguardhome.sh"
cp "$ROOT/scripts/unbound.sh" "$T/mod/scripts/unbound.sh"
cp "$ROOT/fxrules/anti_fraud_96110.txt" "$T/mod/fxrules/anti_fraud_96110.txt"
cp "$ROOT/engines/unbound/root.hints" "$ROOT/engines/unbound/root.hints.sha256" \
   "$ROOT/engines/unbound/root.key.seed" "$ROOT/engines/unbound/root.key.seed.sha256" \
   "$T/mod/engines/unbound/"
cat > "$T/mod/engines/unbound/unbound" <<EOF_UNBOUND
#!/bin/sh
while :; do :; done
EOF_UNBOUND
cat > "$T/mod/engines/unbound/unbound-checkconf" <<EOF_CHECK
#!/bin/sh
[ -s "\$1" ] || exit 2
exit 0
EOF_CHECK
cat > "$T/mod/engines/unbound/unbound-anchor" <<'EOF_ANCHOR'
#!/bin/sh
exit 1
EOF_ANCHOR
cat > "$T/mod/engines/unbound/fx-dns-probe" <<EOF_PROBE
#!/bin/sh
[ ! -f "$T/fail-unbound-probe" ] || exit 1
echo 'PASS rcode=3 bytes=88 port=5353'
EOF_PROBE
chmod 755 "$T/mod/engines/unbound/unbound" "$T/mod/engines/unbound/unbound-checkconf" "$T/mod/engines/unbound/unbound-anchor" "$T/mod/engines/unbound/fx-dns-probe"
(cd "$T/mod/engines/unbound" && sha256sum unbound > unbound.sha256 && sha256sum unbound-checkconf > unbound-checkconf.sha256 && sha256sum unbound-anchor > unbound-anchor.sha256 && sha256sum fx-dns-probe > fx-dns-probe.sha256)
cat > "$T/mod/engines/adguardhome/AdGuardHome-android-arm64" <<EOF_FAKE
#!/bin/sh
for arg in "\$@"; do
  if [ "\$arg" = "--check-config" ]; then exit 0; fi
done
while :; do :; done
EOF_FAKE
chmod 755 "$T/mod/engines/adguardhome/AdGuardHome-android-arm64"
(cd "$T/mod/engines/adguardhome" && sha256sum AdGuardHome-android-arm64 > AdGuardHome-android-arm64.sha256)
cat > "$T/bin/nslookup" <<EOF_LOOKUP
#!/bin/sh
if [ -f "$T/fail-probe" ]; then
  echo ';; connection timed out; no servers could be reached'
  exit 1
fi
printf 'Server: 127.0.0.1\\nAddress 1: 127.0.0.1\\n\\nName: example.com\\nAddress 1: 93.184.216.34\\n'
EOF_LOOKUP
chmod 755 "$T/bin/nslookup"
# Test only: prepend our deterministic nslookup; keep real timeout/hash/core tools.
sed "s|^PATH=/system/bin:/system/xbin:/sbin:/vendor/bin:/usr/bin:/bin$|PATH=$T/bin:/usr/bin:/bin:/system/bin:/system/xbin:/sbin:/vendor/bin|" \
  "$T/mod/scripts/adguardhome.sh" > "$T/mod/scripts/adguardhome.tmp"
mv "$T/mod/scripts/adguardhome.tmp" "$T/mod/scripts/adguardhome.sh"
chmod 755 "$T/mod/scripts/adguardhome.sh"

sh "$T/mod/scripts/adguardhome.sh" ensure "$T/mod" "$T/state" >/dev/null
sh "$T/mod/scripts/adguardhome.sh" status "$T/mod" "$T/state" | grep -qx ready
[ -s "$T/state/unbound/managed.pid" ] || { echo 'FAIL: AdGuard Home started without its local recursive resolver'; exit 1; }
grep -Fq '127.0.0.1:5353' "$T/state/adguardhome/AdGuardHome.yaml"
sh "$T/mod/scripts/adguardhome.sh" stop "$T/mod" "$T/state" >/dev/null
[ ! -s "$T/state/adguardhome/managed.pid" ] || { echo 'FAIL: AdGuard PID marker remains after stop'; exit 1; }
[ ! -s "$T/state/unbound/managed.pid" ] || { echo 'FAIL: Unbound PID marker remains after chained stop'; exit 1; }

# A healthy binary with a broken resolver must not stay running.
touch "$T/fail-probe"
if sh "$T/mod/scripts/adguardhome.sh" ensure "$T/mod" "$T/state" >/dev/null 2>&1; then
  echo 'FAIL: DNS health failure was accepted' >&2; exit 1
fi
[ ! -s "$T/state/adguardhome/managed.pid" ] || { echo 'FAIL: unhealthy process left managed PID'; exit 1; }
rm -f "$T/fail-probe"

# A hash mismatch must block startup before any process is spawned.
printf '%s  AdGuardHome-android-arm64\n' '0000000000000000000000000000000000000000000000000000000000000000' > "$T/mod/engines/adguardhome/AdGuardHome-android-arm64.sha256"
if sh "$T/mod/scripts/adguardhome.sh" ensure "$T/mod" "$T/state" >/dev/null 2>&1; then
  echo 'FAIL: SHA-256 mismatch was accepted' >&2; exit 1
fi
[ ! -s "$T/state/adguardhome/managed.pid" ] || { echo 'FAIL: checksum failure left managed PID'; exit 1; }
echo 'PASS: chained local Unbound -> AdGuard Home start/status/stop, recursive upstream wiring, failed-probe cleanup and checksum fail-closed simulation'
