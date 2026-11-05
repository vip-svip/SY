#!/system/bin/sh
set -eu
SHELL_BIN=$(command -v sh)
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
HTTP="$ROOT/scripts/jsruntime/http.sh"
T=$(mktemp -d "${TMPDIR:-/tmp}/fx-http-no-wget.XXXXXX")
trap 'rm -rf "$T"' EXIT HUP INT TERM
mkdir -p "$T/bin"
printf '#!%s\nprintf called > "$FX_WGET_MARKER"\nexit 0\n' "$SHELL_BIN" > "$T/bin/wget"
chmod +x "$T/bin/wget"
export FX_WGET_MARKER="$T/wget.called"
set +e
PATH="$T/bin" "$SHELL_BIN" "$HTTP" https://example.invalid/a GET "$T/body" "$T/response" "$T/headers" 5 >"$T/out" 2>"$T/err"
rc=$?
set -e
[ "$rc" -eq 69 ] || { echo "FAIL: expected curl-required exit 69, got $rc" >&2; exit 1; }
[ ! -e "$FX_WGET_MARKER" ] || { echo 'FAIL: insecure wget fallback was executed' >&2; exit 1; }
grep -q 'wget fallback disabled' "$T/err"
echo 'FX JS HTTP bridge blocks unsafe wget fallback: PASS'
