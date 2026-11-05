#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
TMP=${TMPDIR:-/tmp}/fx-missing-builtin-source-$$
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
mkdir -p "$TMP/pg" "$TMP/work"
printf 'fx=1\n[list:fx]\nfxfile://missing-source|missing built-in|1\n' > "$TMP/settings.conf"
OUT=$(PG="$TMP/pg" CONF="$TMP/settings.conf" VPNRULE_SRC="$TMP/settings.conf" VPNRULE_WORK="$TMP/work" sh "$ROOT/scripts/vpnrule.sh" --list)
printf '%s\n' "$OUT" | grep -Fq 'SKIP:FXFILE  missing bundled source: fxrules/missing-source.txt' || {
  printf '%s\n' "$OUT" >&2
  echo 'FAIL: missing FX source must be explicitly skipped' >&2
  exit 1
}
printf '%s\n' "$OUT" | grep -Fq '已编译:   0' || {
  printf '%s\n' "$OUT" >&2
  echo 'FAIL: missing FX source must not compile as a real rule' >&2
  exit 1
}
echo 'FX missing bundled source regression: PASS'
