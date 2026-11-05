#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
fail(){ echo "FAIL: $*" >&2; exit 1; }
T=$(mktemp -d "${TMPDIR:-/tmp}/fx-native-script-run.XXXXXX")
trap 'rm -rf "$T"' EXIT HUP INT TERM
MOD="$T/module"; PG="$T/pg"
mkdir -p "$MOD/scripts/jsruntime" "$PG"
printf 'id=privacyguard\nversion=1.0.0\n' > "$MOD/module.prop"
cp "$ROOT/fx-patches/native-script-list.sh" "$MOD/scripts/jsruntime/native-list.sh"
cp "$ROOT/fx-patches/native-script-run.sh" "$MOD/scripts/jsruntime/local-run.sh"
cp "$ROOT/fx-module/scripts/util.sh" "$MOD/scripts/util.sh"
chmod 755 "$MOD/scripts/jsruntime/"*.sh
cat > "$MOD/scripts/jsruntime/runner.sh" <<'RUNNER'
#!/bin/sh
cat "$1" > "$PG/executed.js"
printf '{"ok":true,"done":true,"value":"executed"}\n'
RUNNER
chmod 755 "$MOD/scripts/jsruntime/runner.sh"
cat > "$PG/settings.conf" <<'CONF'
[list:script]
CONF
export PG CONF="$PG/settings.conf"
SCRIPT="$MOD/scripts/jsruntime/native-list.sh"
RUN="$MOD/scripts/jsruntime/local-run.sh"
assert_lock_clean() {
  if [ -e "$PG/jsruntime/native-script-list.lock" ]; then
    echo "LOCK LEAK at $1:" >&2
    ls -la "$PG/jsruntime/native-script-list.lock" >&2 || :
    cat "$PG/jsruntime/native-script-list.lock/pid" >&2 2>/dev/null || :
    fail "script-list lock leaked after $1"
  fi
}
source='const secret = "local-only"; $done({ok:true});'
value64=$(printf '%s' "$source" | base64 | tr -d '\n')
source_sha=$(printf '%s' "$source" | sha256sum | awk '{print $1}')
note64=$(printf '%s' 'Local test' | base64 | tr -d '\n')
[ "$(sh "$SCRIPT" add "$value64" "$note64" 1)" = "OK" ] || fail "could not add local script"
result=$(sh "$RUN" 1 "$source_sha") || fail "enabled local script did not execute: $result"
printf '%s' "$result" | grep -Fq '"done":true' || fail "runner result was not returned"
[ "$(cat "$PG/executed.js")" = "$source" ] || fail "runner did not receive the exact local source"
if sh "$RUN" 1 "$(printf '%064d' 0)" >/dev/null 2>&1; then fail "stale script hash unexpectedly executed"; fi
assert_lock_clean "successful local execution"
[ -f "$PG/jsruntime/local-run.log" ] || fail "private execution log missing"
if grep -Fq 'local-only' "$PG/jsruntime/local-run.log"; then fail "execution log leaked script source"; fi
[ "$(sh "$SCRIPT" toggle 1 0)" = "OK" ] || fail "could not disable local script"
assert_lock_clean "native-list toggle"
if sh "$RUN" 1 "$source_sha" >/dev/null 2>&1; then fail "disabled local script unexpectedly executed"; fi
assert_lock_clean "disabled local execution rejection"
url64=$(printf '%s' 'https://example.test/script.js' | base64 | tr -d '\n')
[ "$(sh "$SCRIPT" add "$url64" "$note64" 1)" = "OK" ] || fail "could not add HTTPS subscription"
url_sha=$(printf '%s' 'https://example.test/script.js' | sha256sum | awk '{print $1}')
if sh "$RUN" 2 "$url_sha" >/dev/null 2>&1; then fail "HTTPS subscription was passed to local JS runner"; fi
if sh "$RUN" 999 "$source_sha" >/dev/null 2>&1; then fail "out-of-range script index unexpectedly succeeded"; fi
assert_lock_clean "test completion"
large_source=$(awk 'BEGIN { for (i=0; i<70000; i++) printf "z" }')
large64=$(printf '%s' "$large_source" | base64 | tr -d '\n')
large_sha=$(printf '%s' "$large_source" | sha256sum | awk '{print $1}')
[ "$(sh "$SCRIPT" add "$large64" "$note64" 1)" = "OK" ] || fail "large local script could not be stored"
result=$(sh "$RUN" 3 "$large_sha") || fail "large local script did not execute: $result"
[ "$(cat "$PG/executed.js")" = "$large_source" ] || fail "large local script was truncated before execution"
echo "PASS: native local JS execution preserves sources above 64 KiB and unbounded indexes"
