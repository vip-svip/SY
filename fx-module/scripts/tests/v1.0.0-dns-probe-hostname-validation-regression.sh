#!/system/bin/sh
# Regression: exercise the real DNS probe validator with a fake resolver.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
D="$ROOT/scripts/dnscheck.sh"
[ -f "$D" ]
sh -n "$D"

TMP=${TMPDIR:-/tmp}/fx-dns-name-test.$$
mkdir -p "$TMP/bin"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
cat > "$TMP/bin/nslookup" <<'SH'
#!/bin/sh
printf '%s\n' "$1" > "$DNS_TEST_LOG"
printf 'Name: %s\nAddress: 203.0.113.1\n' "$1"
SH
chmod 755 "$TMP/bin/nslookup"
export DNS_TEST_LOG="$TMP/query.log"
PATH="$TMP/bin:$PATH"
export PATH

check_fallback() {
  input=$1
  output=$(sh "$D" json "$input")
  queried=$(cat "$DNS_TEST_LOG")
  [ "$queried" = "example.com" ] || {
    echo "FAIL: invalid hostname was sent to resolver: $input -> $queried" >&2
    exit 1
  }
  printf '%s\n' "$output" | grep -Fq '"dns_probe_name":"example.com"' || {
    echo "FAIL: invalid hostname was not normalized: $input" >&2
    exit 1
  }
}
check_fallback 'bad..example'
check_fallback '-leading.example'
check_fallback 'trailing-.example'
check_fallback "$(printf 'a%.0s' $(seq 1 64)).example"
check_fallback "$(printf 'a%.0s' $(seq 1 64)).$(printf 'b%.0s' $(seq 1 64)).$(printf 'c%.0s' $(seq 1 64)).$(printf 'd%.0s' $(seq 1 64))"

valid='good-label.example'
output=$(sh "$D" json "$valid")
queried=$(cat "$DNS_TEST_LOG")
[ "$queried" = "$valid" ] || {
  echo "FAIL: valid hostname was changed: $valid -> $queried" >&2
  exit 1
}
printf '%s\n' "$output" | grep -Fq '"dns_probe_name":"good-label.example"' || {
  echo "FAIL: valid hostname was not preserved" >&2
  exit 1
}
echo 'FX DNS probe hostname validation regression: PASS'
