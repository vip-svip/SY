#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
SCRIPT="$ROOT/scripts/yulong-app-whitelist.sh"
[ -s "$SCRIPT" ] || { echo "FAIL: migrated whitelist runtime script missing" >&2; exit 1; }
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
MODULE="$TMP/module"
STATE="$TMP/state"
mkdir -p "$MODULE/scripts" "$STATE"
printf 'id=privacyguard\n' > "$MODULE/module.prop"
cat > "$MODULE/scripts/apply.sh" <<'SH'
#!/system/bin/sh
printf '%s\n' "$*" >> "$FX_TEST_APPLY_LOG"
[ "${FX_TEST_APPLY_FAIL:-0}" != 1 ]
SH
chmod 0755 "$MODULE/scripts/apply.sh"
cat > "$STATE/settings.conf" <<'CONF'
[conf:general]
enabled=1
[list:yulong_app_whitelist]
CONF
chmod 0600 "$STATE/settings.conf"
export FX_TEST_APPLY_LOG="$TMP/apply.log"
export MP="$MODULE" PG="$STATE" CONF="$STATE/settings.conf" LOCK="$STATE/whitelist.lock"

# Environment overrides must be expanded by the shell, not treated as literal text.
LIST=$(sh "$SCRIPT" list)
printf '%s\n' "$LIST" | grep -qx 'FXYULONGWHITE1'
! printf '%s\n' "$LIST" | grep -q '\\\\$'

sh "$SCRIPT" add com.example.alpha
grep -Fqx 'com.example.alpha|com.example.alpha|1' "$CONF"
[ "$(stat -c %a "$CONF")" = 600 ]
grep -Fqx 'fast' "$FX_TEST_APPLY_LOG"

LIST=$(sh "$SCRIPT" list)
printf '%s\n' "$LIST" | grep -Fqx 'com.example.alpha|com.example.alpha|1'

# Removing a rule is transactional and does not disturb unrelated settings.
sh "$SCRIPT" remove com.example.alpha
! grep -Fq 'com.example.alpha|' "$CONF"
grep -Fqx '[conf:general]' "$CONF"
grep -Fqx 'enabled=1' "$CONF"

# An apply failure must restore the exact previous settings file.
BEFORE=$(cksum "$CONF")
if FX_TEST_APPLY_FAIL=1 sh "$SCRIPT" add com.example.beta; then
  echo "FAIL: whitelist mutation succeeded despite apply.sh failure" >&2
  exit 1
fi
AFTER=$(cksum "$CONF")
[ "$BEFORE" = "$AFTER" ] || { echo "FAIL: failed whitelist apply did not restore config" >&2; exit 1; }

# Invalid package syntax must be rejected before changing settings or running apply.sh.
BEFORE=$(cksum "$CONF")
if sh "$SCRIPT" add 'com.example.bad;id'; then
  echo "FAIL: invalid package token was accepted" >&2
  exit 1
fi
[ "$BEFORE" = "$(cksum "$CONF")" ] || { echo "FAIL: invalid package modified settings" >&2; exit 1; }

# Unsafe symlink settings paths must be rejected.
mv "$CONF" "$STATE/settings.real"
ln -s "$STATE/settings.real" "$CONF"
if sh "$SCRIPT" list; then
  echo "FAIL: whitelist accepted a symlink settings.conf" >&2
  exit 1
fi

echo "PASS: Yulong whitelist shell expansion, list/add/remove, apply rollback, package validation and config symlink rejection"
