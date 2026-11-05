#!/system/bin/sh
# Host-compatible functional tests for whitelist atomic update, rollback copy and locking.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
TMP=${TMPDIR:-/tmp}/fx-whitelist-test.$$
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT HUP INT TERM
mkdir -p "$TMP/module/scripts" "$TMP/data"
cp "$ROOT/scripts/whitelist.sh" "$TMP/module/scripts/whitelist.sh"
cp "$ROOT/scripts/apply.sh" "$TMP/module/scripts/apply.sh"
chmod +x "$TMP/module/scripts/whitelist.sh" "$TMP/module/scripts/apply.sh"
CONF="$TMP/data/settings.conf"
cat > "$CONF" <<'CONFEOF'
[general]
mode=1
[list:domain]
ads.example|ad test|0
[subscription]
source=https://example.invalid/rules
CONFEOF
run() { PG="$TMP/data" CONF="$CONF" sh "$TMP/module/scripts/whitelist.sh" "$@"; }
run add Login.Example.com 'login allow' >/dev/null
grep -Fq 'login.example.com|login allow|1' "$CONF"
grep -Fq '[subscription]' "$CONF"
grep -Fq 'source=https://example.invalid/rules' "$CONF"
test -s "$CONF.whitelist.previous"
# Invalid input must not alter active configuration.
cp "$CONF" "$TMP/before"
if run add 'bad..example.com' >/dev/null 2>&1; then echo 'FAIL: invalid domain accepted' >&2; exit 1; fi
cmp -s "$CONF" "$TMP/before"
# Existing lock must prevent clobbering another writer's change.
mkdir "$CONF.whitelist.lock"
if run add concurrent.example.com >/dev/null 2>&1; then echo 'FAIL: lock was ignored' >&2; exit 1; fi
cmp -s "$CONF" "$TMP/before"
rmdir "$CONF.whitelist.lock"
# Symlinked active configs must be rejected so an apparent whitelist update
# cannot silently modify a different target file.
REAL_CONF="$TMP/data/real-settings.conf"
cp "$CONF" "$REAL_CONF"
LINK_CONF="$TMP/data/settings-link.conf"
ln -s "$REAL_CONF" "$LINK_CONF"
if PG="$TMP/data" CONF="$LINK_CONF" sh "$TMP/module/scripts/whitelist.sh" add symlink.example.com >/dev/null 2>&1; then
  echo 'FAIL: symlinked configuration was modified' >&2; exit 1
fi
if grep -Fq 'symlink.example.com|' "$REAL_CONF"; then
  echo 'FAIL: symlink target changed despite rejection' >&2; exit 1
fi
run remove login.example.com >/dev/null
if grep -Fq 'login.example.com|login allow|1' "$CONF"; then echo 'FAIL: remove left whitelist entry' >&2; exit 1; fi
grep -Fq '[subscription]' "$CONF"
sh -n "$ROOT/scripts/whitelist.sh"
echo 'PASS: whitelist transaction, backup, lock and validation regression'
