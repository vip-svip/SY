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
assert "LC_ALL=C grep -q '[[:cntrl:]]'" in source, "valid_command must reject control characters before grep line matching"
assert "printf '%s' \"$1\"" in source, "valid_command must not append a synthetic line terminator"
assert source.count("valid_command(){") == 1, "Stellar command validator must be defined exactly once"
assert source.count("with_lock(){") == 1, "Stellar mutation lock must be defined exactly once"
validator = source.split("valid_command(){", 1)[1].split("\nwith_lock(){", 1)[0]
assert "grep -Eq '" in validator and validator.rstrip().endswith("}"), "valid_command must retain its complete bounded grammar and close before with_lock"

assert "trap cleanup_lock EXIT" in source, "lock cleanup must happen from EXIT only"
assert 'mktemp "$file.fx.XXXXXX"' in source, "Stellar mutations must use unique same-directory temporary files"
assert 'mv -f "$tmp" "$file"' in source, "Stellar mutation must atomically replace the state file"
assert '$file.tmp.$' not in source and '$PKGS.tmp.$' not in source, "predictable Stellar temporary paths remain"
assert 'for file in "$ALWAYS" "$SCOPES"; do' in source, "package revocation must remove dependent grants"
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
# Secure settings require an explicitly granted Stellar scope and a confirmed
# read-after-write result. The mock represents Android's settings service.
mkdir -p "$TMP/bin"
: > "$TMP/settings.store"
cat > "$TMP/bin/settings" <<'SETTINGS'
#!/bin/sh
set -eu
case "$1:$2" in
  put:secure)
    [ "$#" -eq 4 ] || exit 2
    write_value="$4"
    if [ -n "${MOCK_SETTINGS_CORRUPT_REQUEST:-}" ] \
        && [ "$4" = "$MOCK_SETTINGS_CORRUPT_REQUEST" ]; then
      write_value=mock-corrupted
    fi
    tmp="$SETTINGS_STORE.tmp.$"
    awk -F= -v key="$3" '$1!=key{print}' "$SETTINGS_STORE" > "$tmp"
    printf '%s=%s\n' "$3" "$write_value" >> "$tmp"
    mv "$tmp" "$SETTINGS_STORE"
    if [ -n "${MOCK_SETTINGS_FAIL_AFTER_WRITE:-}" ] \
        && [ "$4" = "$MOCK_SETTINGS_FAIL_AFTER_WRITE" ]; then
      exit 9
    fi
    ;;
  get:secure)
    [ "$#" -eq 3 ] || exit 2
    awk -F= -v key="$3" '$1==key{v=$2} END{if(v=="") print "null"; else print v}' "$SETTINGS_STORE"
    ;;
  delete:secure)
    [ "$#" -eq 3 ] || exit 2
    tmp="$SETTINGS_STORE.tmp.$"
    awk -F= -v key="$3" '$1!=key{print}' "$SETTINGS_STORE" > "$tmp"
    mv "$tmp" "$SETTINGS_STORE"
    ;;
  *) exit 2 ;;
esac
SETTINGS
chmod 0700 "$TMP/bin/settings"
export SETTINGS_STORE="$TMP/settings.store"
export PATH="$TMP/bin:$PATH"
if run secure-setting "$PKG" show_ime_with_hard_keyboard 1 >/dev/null 2>&1; then
  fail "secure-setting write was allowed without SECURE_SETTINGS_WRITE"
fi
run scope-set "$PKG" SECURE_SETTINGS_WRITE 1
secure_result=$(run secure-setting "$PKG" show_ime_with_hard_keyboard 1)
printf '%s\\n' "$secure_result" | grep -Fq 'success=1 package=com.example.stellarclient secure_setting=show_ime_with_hard_keyboard value=1' || fail "secure-setting write was not confirmed"
[ "$(settings get secure show_ime_with_hard_keyboard)" = 1 ] || fail "mock Android setting did not retain the written value"

# The Shield UI reads a bounded local audit log, not Binder daemon telemetry.
: > "$TMP/stellar_guard/action.log"
i=1
while [ "$i" -le 501 ]; do
  printf 'seed-%03d\n' "$i" >> "$TMP/stellar_guard/action.log"
  i=$((i+1))
done
secure_result=$(run secure-setting "$PKG" show_ime_with_hard_keyboard 1)
[ "$(wc -l < "$TMP/stellar_guard/action.log" | tr -d ' ')" = 500 ] || fail "Stellar action log did not retain 500 entries"
grep -Fq 'seed-003' "$TMP/stellar_guard/action.log" || fail "bounded log discarded entries too early"
grep -Fq 'seed-501' "$TMP/stellar_guard/action.log" || fail "bounded log did not retain newest prior entry"
! grep -Fq 'seed-001' "$TMP/stellar_guard/action.log" || fail "bounded log retained stale entries"
logs=$(run logs)
printf '%s\n' "$logs" | grep -Fqx 'FXSTELLARLOG1' || fail "Stellar log protocol header missing"
printf '%s\n' "$logs" | grep -Fq 'secure-setting show_ime_with_hard_keyboard=1' || fail "successful secure-setting action missing from log"
run clear-logs >/dev/null
[ "$(run logs)" = FXSTELLARLOG_EMPTY ] || fail "clear-logs did not empty the audit file"

# A backend command can mutate Android's setting and still return failure.
# FX must restore the exact pre-write value rather than leave a half-applied change.
if MOCK_SETTINGS_FAIL_AFTER_WRITE=0 sh "$TMP/control.sh" secure-setting "$PKG" show_ime_with_hard_keyboard 0 >/dev/null 2>&1; then
  fail "Stellar accepted a settings put that returned failure after mutation"
fi
[ "$(settings get secure show_ime_with_hard_keyboard)" = 1 ] || fail "failed settings put did not restore the previous value"

# A successful command with an incorrect read-back must also roll back.
if MOCK_SETTINGS_CORRUPT_REQUEST=0 sh "$TMP/control.sh" secure-setting "$PKG" show_ime_with_hard_keyboard 0 >/dev/null 2>&1; then
  fail "Stellar accepted a settings value that did not match the requested value"
fi
[ "$(settings get secure show_ime_with_hard_keyboard)" = 1 ] || fail "read-back mismatch did not restore the previous value"

# A failed write to a previously absent setting must delete the partial value.
if MOCK_SETTINGS_FAIL_AFTER_WRITE=1 sh "$TMP/control.sh" secure-setting "$PKG" screensaver_enabled 1 >/dev/null 2>&1; then
  fail "Stellar accepted a failed write to a previously absent setting"
fi
[ "$(settings get secure screensaver_enabled)" = null ] || fail "rollback did not restore an initially absent setting"
if run secure-setting "$PKG" adb_enabled 1 >/dev/null 2>&1; then
  fail "secure-setting key outside the fixed allowlist was accepted"
fi
if run secure-setting "$PKG" long_press_timeout 99 >/dev/null 2>&1; then
  fail "unsafe long_press_timeout value was accepted"
fi
run scope-set "$PKG" SECURE_SETTINGS_WRITE 0
if run secure-setting "$PKG" show_ime_with_hard_keyboard 0 >/dev/null 2>&1; then
  fail "secure-setting write was allowed after its scope was revoked"
fi
run scope-set "$PKG" SHELL_ID_COMMAND 1
run always-set "$PKG" 'id -u' 1

# Old PID-predictable temp paths are planted as symlinks to an unrelated
# sentinel. Mutations must use unique temporary files and leave it unchanged.
SENTINEL="$TMP/stellar-sentinel"
printf 'do-not-overwrite\n' > "$SENTINEL"
WRAPPER_PID="$TMP/stellar-wrapper.pid"
run_with_legacy_temp_symlinks(){
  sh -c '
    root=$1; sentinel=$2; control=$3; shift 3
    pid=$$
    for name in command_whitelist.txt command_always_allow.txt scope_grants.txt; do
      ln -s "$sentinel" "$root/stellar_guard/$name.tmp.$pid"
    done
    printf "%s\n" "$pid" > "$root/stellar-wrapper.pid"
    exec sh "$control" "$@"
  ' sh "$TMP" "$SENTINEL" "$TMP/control.sh" "$@"
  pid=$(cat "$WRAPPER_PID")
  for name in command_whitelist.txt command_always_allow.txt scope_grants.txt; do
    rm -f "$TMP/stellar_guard/$name.tmp.$pid"
  done
  rm -f "$WRAPPER_PID"
  [ "$(cat "$SENTINEL")" = "do-not-overwrite" ] || fail "Stellar mutation followed a legacy predictable temp symlink"
}
run_with_legacy_temp_symlinks scope-set "$PKG" FILESYSTEM_READ_COMMAND 1
grep -Fq "$(printf '%s\t%s' "$PKG" FILESYSTEM_READ_COMMAND)" "$TMP/stellar_guard/scope_grants.txt" || fail "scope update did not commit with a planted temp symlink"
run_with_legacy_temp_symlinks always-set "$PKG" 'ps' 1
grep -Fq "$(printf '%s\t%s' "$PKG" ps)" "$TMP/stellar_guard/command_always_allow.txt" || fail "always-allow update did not commit with a planted temp symlink"
SYMLINK_PKG=com.example.stellarprobe
run_with_legacy_temp_symlinks pkg-set "$SYMLINK_PKG" 1
listing=$(run list)
printf '%s\n' "$listing" | grep -Fqx "PKG|$SYMLINK_PKG" || fail "package add did not survive planted legacy temp symlinks"
run_with_legacy_temp_symlinks pkg-set "$SYMLINK_PKG" 0
listing=$(run list)
if printf '%s\n' "$listing" | grep -Fq "$SYMLINK_PKG"; then fail "package revoke did not remove its probe authorization"; fi
[ "$(cat "$SENTINEL")" = "do-not-overwrite" ] || fail "package add/revoke changed the sentinel target"
for name in command_whitelist.txt command_always_allow.txt scope_grants.txt; do
  ! find "$TMP/stellar_guard" -maxdepth 1 -name "$name.fx.*" -print -quit | grep -q . || fail "Stellar temporary state file leaked: $name"
done

listing=$(run list)
printf '%s\n' "$listing" | grep -Fqx "PKG|$PKG" || fail "authorized package missing from list"
printf '%s\n' "$listing" | grep -Fqx "SCOPE|$PKG|SHELL_ID_COMMAND" || fail "tab-delimited scope lookup did not round-trip"
printf '%s\n' "$listing" | grep -Fqx "ALWAYS|$PKG|id -u" || fail "tab-delimited command allowlist did not round-trip"
uid=$(run run "$PKG" SHELL_ID_COMMAND 'id -u') || fail "authorized id -u command was rejected"
bad_command=$(printf 'id -u\nid; touch %s' "$TMP/stellar-injected")
if run always-set "$PKG" "$bad_command" 1 >/dev/null 2>&1; then
  fail "multi-line Stellar allowlist command was accepted"
fi
if run run "$PKG" SHELL_ID_COMMAND "$bad_command" >/dev/null 2>&1; then
  fail "multi-line Stellar read-only command was accepted"
fi
[ ! -e "$TMP/stellar-injected" ] || fail "multi-line command injection created a marker file"

case "$uid" in ''|*[!0-9]*) fail "id -u did not return a numeric UID" ;; esac
run pkg-set "$PKG" 0
listing=$(run list)
if printf '%s\n' "$listing" | grep -Fq "$PKG"; then fail "removing package must also remove its scopes and always-allow commands"; fi

# Shield whitelist replacement must update the Stellar package policy as one
# bounded operation, deduplicate entries, and revoke grants for removed apps.
KEEP_PKG=com.example.keep
DROP_PKG=com.example.drop
NEW_PKG=com.example.new
run pkg-set "$KEEP_PKG" 1
run scope-set "$KEEP_PKG" FILESYSTEM_READ_COMMAND 1
run always-set "$KEEP_PKG" 'ps' 1
run pkg-set "$DROP_PKG" 1
run scope-set "$DROP_PKG" FILESYSTEM_READ_COMMAND 1
run always-set "$DROP_PKG" 'ps' 1
sync_result=$(run pkg-sync "$KEEP_PKG" "$NEW_PKG" "$KEEP_PKG")
printf '%s\n' "$sync_result" | grep -Fq 'success=1 package_count=2' || fail "Shield package sync did not report the deduplicated package count"
[ "$(cat "$TMP/stellar_guard/command_whitelist.txt")" = "$(printf '%s\n%s' "$KEEP_PKG" "$NEW_PKG")" ] || fail "Shield package sync did not replace the package policy exactly"
grep -Fq "$(printf '%s\t%s' "$KEEP_PKG" FILESYSTEM_READ_COMMAND)" "$TMP/stellar_guard/scope_grants.txt" || fail "sync discarded a retained package scope"
! grep -Fq "$DROP_PKG" "$TMP/stellar_guard/scope_grants.txt" || fail "sync retained a removed package scope"
grep -Fq "$(printf '%s\t%s' "$KEEP_PKG" ps)" "$TMP/stellar_guard/command_always_allow.txt" || fail "sync discarded a retained command grant"
! grep -Fq "$DROP_PKG" "$TMP/stellar_guard/command_always_allow.txt" || fail "sync retained a removed package command grant"
if run pkg-sync "$KEEP_PKG;touch /tmp/fx-stellar-sync-injected"; then
  fail "Shield package sync accepted shell metacharacters in a package name"
fi
[ ! -e /tmp/fx-stellar-sync-injected ] || fail "package sync evaluated a shell-injection payload"
run pkg-sync
[ ! -s "$TMP/stellar_guard/command_whitelist.txt" ] || fail "empty Shield whitelist sync did not clear Stellar package authorization"
[ ! -s "$TMP/stellar_guard/scope_grants.txt" ] || fail "empty Shield whitelist sync did not revoke old scopes"
[ ! -s "$TMP/stellar_guard/command_always_allow.txt" ] || fail "empty Shield whitelist sync did not revoke old command grants"
! find "$TMP/stellar_guard" -maxdepth 1 -name 'pkg-sync.*' -print -quit | grep -q . || fail "package sync temporary file leaked"

# Remove the populated state directory first; otherwise ln -s creates a link
# inside that directory and the test never exercises the intended path.
rm -rf "$TMP/stellar_guard"
# Reject a symlinked state directory and a symlinked state file before touching targets.
mkdir "$TMP/directory-target"
ln -s "$TMP/directory-target" "$TMP/stellar_guard"
test -L "$TMP/stellar_guard" || fail "could not create symlinked directory fixture"
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
echo "PASS: Stellar package/scope storage, secure-setting rollback, unpredictable atomic writes, legacy-temp symlink resistance and signal-safe locks"
