#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
mkdir -p "$TMP/state/mitm"
cat > "$TMP/input.conf" <<'MODULE'
#!name=Aloha test
[Script]
Aloha=type=http-response,pattern=https://api.alohaprofile.com/v1/profile_info,requires-body=1,script-path=https://raw.example.net/aloha.js
[MITM]
hostname= %APPEND% api.alohaprofile.com,*.example.org
MODULE
TMPDIR="$TMP" sh "$ROOT/scripts/modconvert.sh" --emit "$TMP/input.conf" > "$TMP/converted.conf" 2> "$TMP/convert.err"
grep -Fq '[list:mitmhost]' "$TMP/converted.conf"
grep -Fq 'api.alohaprofile.com|modconvert-mitmhost|1' "$TMP/converted.conf"
grep -Fq '*.example.org|modconvert-mitmhost|1' "$TMP/converted.conf"
! grep -Fq '%APPEND%|' "$TMP/converted.conf"
cp "$TMP/converted.conf" "$TMP/state/settings.conf"
FX_SETTINGS="$TMP/state/settings.conf" PG="$TMP/state" sh "$ROOT/scripts/sync-mitm-hosts.sh" > "$TMP/sync.out"
grep -Fxq 'api.alohaprofile.com' "$TMP/state/mitm/hostnames.conf"
grep -Fxq '*.example.org' "$TMP/state/mitm/hostnames.conf"
# Bad replacement must not destroy the last known-good manifest.
printf '[list:mitmhost]\n*bad.example.org|x|1\n' > "$TMP/state/settings.conf"
if FX_SETTINGS="$TMP/state/settings.conf" PG="$TMP/state" sh "$ROOT/scripts/sync-mitm-hosts.sh" >/dev/null 2>&1; then
  echo 'FAIL: invalid hostname was accepted'; exit 1
fi
grep -Fxq 'api.alohaprofile.com' "$TMP/state/mitm/hostnames.conf"
grep -Fq 'sync-mitm-hosts.sh' "$ROOT/scripts/mitm-engine.sh"
echo 'FX MITM hostname allowlist import/sync/rollback regression: PASS'
