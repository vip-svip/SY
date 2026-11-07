#!/system/bin/sh
# Host regression for Unbound's runtime setting -> live config contract.
set -eu

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
UNBOUND="$ROOT/fx-module/scripts/unbound.sh"
fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "  ok: $*"; }

[ -s "$UNBOUND" ] || fail "FX Unbound lifecycle script is missing"
sh -n "$UNBOUND" || fail "FX Unbound lifecycle script does not parse"

TMP=$(mktemp -d "${TMPDIR:-/tmp}/fx-unbound-render.XXXXXX") || fail "cannot create fixture"
trap 'rm -rf "$TMP"' EXIT INT TERM
mkdir -p "$TMP/module/scripts" "$TMP/state"
cp "$UNBOUND" "$TMP/module/scripts/unbound.sh"

cat > "$TMP/module/scripts/yulong-ad-control.sh" <<'CONTROL'
#!/system/bin/sh
[ "${1:-}" = unbound-runtime-get ] || exit 64
printf '%s\n' FXYULONGUNBOUND1
printf 'UNBOUND_CACHE_MAX_TTL=86400\n'
printf 'UNBOUND_CACHE_MIN_TTL=0\n'
printf 'UNBOUND_SERVE_EXPIRED=1\n'
printf 'UNBOUND_SERVE_EXPIRED_TTL=86400\n'
printf 'UNBOUND_SERVE_EXPIRED_REPLY_TTL=30\n'
printf 'UNBOUND_SERVE_EXPIRED_CLIENT_TIMEOUT=1800\n'
case "${FX_TEST_MODE:-normal}" in
  missing) : ;;
  duplicate)
    printf 'UNBOUND_SERVE_EXPIRED_TTL_RESET=0\n'
    printf 'UNBOUND_SERVE_EXPIRED_TTL_RESET=1\n'
    ;;
  *) printf 'UNBOUND_SERVE_EXPIRED_TTL_RESET=%s\n' "${FX_TEST_RESET:-0}" ;;
esac
printf 'UNBOUND_PREFETCH=1\n'
printf 'UNBOUND_PREFETCH_KEY=1\n'
printf 'UNBOUND_QNAME_MINIMISATION=1\n'
printf 'UNBOUND_MSG_CACHE_SIZE=4m\n'
printf 'UNBOUND_RRSET_CACHE_SIZE=8m\n'
printf 'UNBOUND_KEY_CACHE_SIZE=4m\n'
printf 'UNBOUND_NEG_CACHE_SIZE=1m\n'
printf 'UNBOUND_NUM_THREADS=1\n'
CONTROL
chmod 0755 "$TMP/module/scripts/yulong-ad-control.sh"

render() {
  FX_TEST_MODE="${1:-normal}" FX_TEST_RESET="${2:-0}" \
    sh "$TMP/module/scripts/unbound.sh" render-config "$TMP/module" "$TMP/state"
}

echo "== serve-expired-ttl-reset disabled -> explicit no =="
out=$(render normal 0) || fail "disabled setting failed to render"
printf '%s\n' "$out" | grep -qx '  serve-expired-ttl-reset: no' || fail "disabled setting was not rendered as no"
pass "disabled setting is rendered explicitly"

echo "== serve-expired-ttl-reset enabled -> explicit yes =="
out=$(render normal 1) || fail "enabled setting failed to render"
printf '%s\n' "$out" | grep -qx '  serve-expired-ttl-reset: yes' || fail "enabled setting was not rendered as yes"
pass "enabled setting reaches the live Unbound config"

echo "== invalid, missing and duplicate values fail closed =="
if render normal 2 >/dev/null 2>&1; then fail "invalid boolean was accepted"; fi
if render missing 0 >/dev/null 2>&1; then fail "missing setting was accepted"; fi
if render duplicate 0 >/dev/null 2>&1; then fail "duplicate setting was accepted"; fi
pass "invalid, missing and duplicate runtime values are rejected"

echo "PASS: Unbound serve-expired TTL reset runtime rendering contract"
