#!/system/bin/sh
# Audit84: exercise the same whitelist regex generation and hosts filtering used by apply.sh.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
APPLY="$ROOT/scripts/apply.sh"
# Keep the production implementation wired to the tested boundary-aware algorithm.
grep -Fq "print \"(^|[.[:space:]])\" d \"\$\" > out" "$APPLY" || {
  echo 'FAIL: apply.sh whitelist regex generation changed; update this regression'; exit 1;
}
grep -Fq 'grep -Eiv -f "$WL" "$TMP" > "$TMP.2"' "$APPLY" || {
  echo 'FAIL: apply.sh no longer filters generated hosts through whitelist'; exit 1;
}
T=$(mktemp -d "${TMPDIR:-/tmp}/fx-wl-regression.XXXXXX")
trap 'rm -rf "$T"' EXIT HUP INT TERM
cat > "$T/domains" <<'DOMAINS'
Google.COM
*.local
connectivitycheck.gstatic.com
DOMAINS
# Use the production algorithm: normalize wildcard prefix, lowercase, escape dots, anchor suffix.
sed 's/^\*\.//; s/[[:space:]]*$//' "$T/domains" | awk '
  /^[A-Za-z0-9.-]+$/ && length($0) > 0 {
    d=tolower($0); gsub(/\./,"\\.",d); print "(^|[.[:space:]])" d "$"
  }
' > "$T/wl.regex"
cat > "$T/hosts" <<'HOSTS'
0.0.0.0 google.com
0.0.0.0 ads.google.com
0.0.0.0 ADS.GOOGLE.COM
0.0.0.0 API.CONNECTIVITYCHECK.GSTATIC.COM
0.0.0.0 evilgoogle.com
0.0.0.0 google.com.evil
0.0.0.0 api.connectivitycheck.gstatic.com
0.0.0.0 bad.local
0.0.0.0 example.com
HOSTS
grep -Eiv -f "$T/wl.regex" "$T/hosts" > "$T/filtered" || rc=$?
# grep rc=1 is valid when all lines are whitelisted; this fixture intentionally retains rows.
[ "${rc:-0}" -le 1 ] || { echo 'FAIL: grep error applying whitelist'; exit 1; }
for blocked in 'evilgoogle.com' 'google.com.evil' 'example.com'; do
  grep -Fq "$blocked" "$T/filtered" || { echo "FAIL: whitelist overmatched $blocked"; exit 1; }
done
for allowed in '(^|[.[:space:]])google\.com$' '(^|[.[:space:]])ads\.google\.com$' '(^|[.[:space:]])api\.connectivitycheck\.gstatic\.com$' '(^|[.[:space:]])bad\.local$'; do
  if grep -Eq "$allowed" "$T/filtered"; then echo "FAIL: whitelist did not exempt pattern $allowed"; exit 1; fi
done
# Case-insensitive domain matching is required by DNS semantics.
if grep -Fq 'ADS.GOOGLE.COM' "$T/filtered" || grep -Fq 'API.CONNECTIVITYCHECK.GSTATIC.COM' "$T/filtered"; then
  echo 'FAIL: whitelist matching is case-sensitive'; exit 1;
fi
echo 'PASS: hosts whitelist wins on exact/suffix boundaries, case-insensitively, without overmatching neighboring domains'
