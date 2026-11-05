#!/bin/sh
# Cert overlays must never report success when SELinux labels cannot be applied/verified.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
CERT="$ROOT/scripts/certmgr.sh"
TMP=${TMPDIR:-/tmp}/fx-cert-label-test-$$
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
mkdir -p "$TMP/bin-no-chcon" "$TMP/bin-mock" "$TMP/ref" "$TMP/overlay"
: > "$TMP/ref/1234abcd.0"
: > "$TMP/overlay/abcd1234.0"
# Extract only the POSIX function so runtime cases can safely mock platform tools.
sed -n '/^ca_chcon() {/,/^}/p' "$CERT" > "$TMP/function.sh"
[ -s "$TMP/function.sh" ] || { echo 'FAIL: ca_chcon function not found' >&2; exit 1; }
for cmd in find grep head awk; do ln -s "$(command -v "$cmd")" "$TMP/bin-no-chcon/$cmd"; done
for cmd in find grep head awk; do ln -s "$(command -v "$cmd")" "$TMP/bin-mock/$cmd"; done
cat > "$TMP/bin-mock/ls" <<'LS'
#!/bin/sh
last=""; for arg do last="$arg"; done
case "$*" in
  *-Z*)
    case "$last" in */ref/*) label=u:object_r:system_security_cacerts_file:s0 ;;
      *) if [ -f "${LABEL_MARKER:-/nonexistent}" ]; then label=u:object_r:system_security_cacerts_file:s0; else label=u:object_r:stale_file:s0; fi ;;
    esac
    printf '%s %s\n' "$label" "$last"
    ;;
  *) exec /bin/ls "$@" ;;
esac
LS
cat > "$TMP/bin-mock/chcon" <<'CHCON'
#!/bin/sh
case "${MOCK_CHCON:-fail}" in
  success) : > "${LABEL_MARKER:?}"; exit 0 ;;
  success-nochange) exit 0 ;;
  *) exit 1 ;;
esac
CHCON
chmod 755 "$TMP/bin-mock/ls" "$TMP/bin-mock/chcon"
# With chcon unavailable, publishing CA overlays must fail.
if PATH="$TMP/bin-no-chcon" /bin/sh -c '. "$1"; ca_chcon "$2" "$3"' _ "$TMP/function.sh" "$TMP/overlay" "$TMP/ref" >/dev/null 2>&1; then
  echo 'FAIL: missing chcon was accepted' >&2; exit 1
fi
# chcon returning failure (or failing to establish the label) must also fail.
if PATH="$TMP/bin-mock" MOCK_CHCON=fail /bin/sh -c '. "$1"; ca_chcon "$2" "$3"' _ "$TMP/function.sh" "$TMP/overlay" "$TMP/ref" >/dev/null 2>&1; then
  echo 'FAIL: failed chcon was accepted' >&2; exit 1
fi
# Returning zero without changing the label must NOT count as success.
if PATH="$TMP/bin-mock" MOCK_CHCON=success-nochange LABEL_MARKER="$TMP/label-applied" /bin/sh -c '. "$1"; ca_chcon "$2" "$3"' _ "$TMP/function.sh" "$TMP/overlay" "$TMP/ref" >/dev/null 2>&1; then
  echo 'FAIL: chcon success with unchanged context was accepted' >&2; exit 1
fi
# Successful chcon plus observable expected label is accepted.
PATH="$TMP/bin-mock" MOCK_CHCON=success LABEL_MARKER="$TMP/label-applied" /bin/sh -c '. "$1"; ca_chcon "$2" "$3"' _ "$TMP/function.sh" "$TMP/overlay" "$TMP/ref" >/dev/null 2>&1 || {
  echo 'FAIL: verified SELinux label was rejected' >&2; exit 1;
}
# Both active trust-store call sites must stop before bind-mount when labels fail.
python3 - "$CERT" <<'PY'
import sys
s=open(sys.argv[1],encoding='utf-8').read()
assert 'if ! ca_chcon "$OVL_APEX" "$SC_APEX"; then' in s
assert 'if ! ca_chcon "$OVL" "$SC"; then' in s
assert 'u:object_r:system_file:s0' not in s, 'must not accept a generic label when the CA-specific label is required'
for token in ('unable to apply and verify a readable SELinux context','refusing to publish CA trust overlay','u:object_r:system_security_cacerts_file:s0'):
    assert token in s, token
PY
echo 'PASS: certificate trust publication fails closed when SELinux labels cannot be applied and verified'
