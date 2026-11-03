#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
SOURCE="$ROOT/scripts/yulong-stellar-control.sh"
fail(){ echo "FAIL: $*" >&2; exit 1; }
[ -s "$SOURCE" ] || fail "Stellar control source missing"
sh -n "$SOURCE" || fail "Stellar control is not valid POSIX shell"
python3 - "$SOURCE" <<'PY'
from pathlib import Path
import sys
source = Path(sys.argv[1]).read_text(encoding="utf-8")
slash = chr(92)
assert "id" + slash + " -u" in source, "id -u case must escape its embedded space once"
assert "id" + slash * 2 + " -u" not in source, "case pattern has two backslashes before a space"
assert "printf '%s" + slash + "n'" in source, "command validation must print a real newline"
assert "awk -F '" + slash + "t'" in source, "scope lookups must split on a real tab"
assert "awk -F '" + slash + "t' -v OFS='" + slash + "t'" in source, "scope writes must use real tab separators"
assert "trap cleanup_lock EXIT" in source, "lock cleanup must happen from EXIT only"
for signal, code in (("HUP",129),("INT",130),("TERM",143)):
    assert "trap 'exit " + str(code) + "' " + signal in source, signal + " must exit into the cleanup trap"
print("PASS: Stellar POSIX shell syntax, delimiter escaping and signal-safe locking")
PY
TMP=$(mktemp -d "${TMPDIR:-/tmp}/fx-stellar-control.XXXXXX")
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
sed "s|^DIR=/data/local/tmp/stellar_guard$|DIR=$TMP/stellar_guard|" "$SOURCE" > "$TMP/control.sh"
sh -n "$TMP/control.sh"
run(){ sh "$TMP/control.sh" "$@"; }
PKG=com.example.stellarclient
run pkg-set "$PKG" 1
run scope-set "$PKG" SHELL_ID_COMMAND 1
run always-set "$PKG" 'id -u' 1
listing=$(run list)
printf '%s\n' "$listing" | grep -Fqx "PKG|$PKG" || fail "authorized package missing from list"
printf '%s\n' "$listing" | grep -Fqx "SCOPE|$PKG|SHELL_ID_COMMAND" || fail "tab-delimited scope lookup did not round-trip"
printf '%s\n' "$listing" | grep -Fqx "ALWAYS|$PKG|id -u" || fail "tab-delimited command allowlist did not round-trip"
uid=$(run run "$PKG" SHELL_ID_COMMAND 'id -u') || fail "authorized id -u command was rejected"
case "$uid" in ''|*[!0-9]*) fail "id -u did not return a numeric UID" ;; esac
run pkg-set "$PKG" 0
listing=$(run list)
if printf '%s\n' "$listing" | grep -Fq "$PKG"; then fail "removing package must also remove its scopes and always-allow commands"; fi

# Reject a symlinked state directory and a symlinked state file before touching targets.
mkdir "$TMP/directory-target"
ln -s "$TMP/directory-target" "$TMP/stellar_guard"
sed "s|^DIR=/data/local/tmp/stellar_guard$|DIR=$TMP/stellar_guard|" "$SOURCE" > "$TMP/directory-link.sh"
if sh "$TMP/directory-link.sh" list >/dev/null 2>&1; then fail "symlinked Stellar data directory was accepted"; fi
test ! -e "$TMP/directory-target/command_whitelist.txt" || fail "directory symlink target was modified"
rm "$TMP/stellar_guard"

mkdir -m 0700 "$TMP/file-target"
printf 'preserve-me\n' > "$TMP/victim"
ln -s "$TMP/victim" "$TMP/file-target/command_whitelist.txt"
sed "s|^DIR=/data/local/tmp/stellar_guard$|DIR=$TMP/file-target|" "$SOURCE" > "$TMP/file-link.sh"
if sh "$TMP/file-link.sh" list >/dev/null 2>&1; then fail "symlinked Stellar state file was accepted"; fi
grep -Fxq preserve-me "$TMP/victim" || fail "symlink target content was changed"
echo "PASS: Stellar package/scope storage, symlink rejection and rollback-safe locks"
