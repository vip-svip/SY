#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
T=$(mktemp -d "${TMPDIR:-/tmp}/fx-wl-manager.XXXXXX")
trap 'rm -rf "$T"' EXIT HUP INT TERM
mkdir -p "$T/pg"
CONF="$T/pg/settings.conf" PG="$T/pg"; export CONF PG
cat > "$CONF" <<'CFG'
version=1.0.0
[list:domain]
Safe.Example.com|existing|1
other.example.org|other|1
[list:block]
Safe.Example.com|blocked test|1
CFG
sh "$ROOT/scripts/whitelist.sh" list > "$T/list"
grep -Fq 'Safe.Example.com|existing|1' "$T/list"
sh "$ROOT/scripts/whitelist.sh" add '*.SAFE.example.com' 'login endpoint' >/dev/null
[ "$(awk '/^\[list:domain\]/{i=1;next}/^\[/{i=0} i && tolower($0) ~ /^safe\.example\.com\|/{n++} END{print n+0}' "$CONF")" -eq 1 ] || { echo 'FAIL: add should canonicalize and deduplicate'; exit 1; }
grep -Fq 'safe.example.com|login endpoint|1' "$CONF"
if sh "$ROOT/scripts/whitelist.sh" add 'bad..example.com' >/dev/null 2>&1; then echo 'FAIL: malformed domain accepted'; exit 1; fi
sh "$ROOT/scripts/whitelist.sh" remove 'SAFE.EXAMPLE.COM' >/dev/null
if awk '/^\[list:domain\]/{i=1;next}/^\[/{i=0} i && tolower($0) ~ /^safe\.example\.com\|/{found=1} END{exit !found}' "$CONF"; then echo 'FAIL: remove did not remove normalized entry'; exit 1; fi
grep -Fq 'Safe.Example.com|blocked test|1' "$CONF" || { echo 'FAIL: editing whitelist altered block rules'; exit 1; }
echo 'PASS: whitelist CLI add/list/remove, strict validation, canonical dedup, unrelated sections preserved'
