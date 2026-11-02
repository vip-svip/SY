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
source='const secret = "local-only"; $done({ok:true});'
value64=$(printf '%s' "$source" | base64 | tr -d '\n')
note64=$(printf '%s' 'Local test' | base64 | tr -d '\n')
[ "$(sh "$SCRIPT" add "$value64" "$note64" 1)" = "OK" ] || fail "could not add local script"
result=$(sh "$RUN" 1) || fail "enabled local script did not execute: $result"
printf '%s' "$result" | grep -Fq '"done":true' || fail "runner result was not returned"
[ "$(cat "$PG/executed.js")" = "$source" ] || fail "runner did not receive the exact local source"
[ -f "$PG/jsruntime/local-run.log" ] || fail "private execution log missing"
if grep -Fq 'local-only' "$PG/jsruntime/local-run.log"; then fail "execution log leaked script source"; fi
[ "$(sh "$SCRIPT" toggle 1 0)" = "OK" ] || fail "could not disable local script"
if sh "$RUN" 1 >/dev/null 2>&1; then fail "disabled local script unexpectedly executed"; fi
url64=$(printf '%s' 'https://example.test/script.js' | base64 | tr -d '\n')
[ "$(sh "$SCRIPT" add "$url64" "$note64" 1)" = "OK" ] || fail "could not add HTTPS subscription"
if sh "$RUN" 2 >/dev/null 2>&1; then fail "HTTPS subscription was passed to local JS runner"; fi
if sh "$RUN" 999 >/dev/null 2>&1; then fail "out-of-range script index unexpectedly succeeded"; fi
[ ! -e "$PG/jsruntime/native-script-list.lock" ] || fail "script-list lock leaked after execution"
echo "PASS: native local JS execution requires enabled FXSRC_B64 source, preserves source bytes, rejects subscriptions, and logs metadata only"
