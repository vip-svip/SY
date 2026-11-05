#!/bin/sh
# Runtime regression: MITM status must see CA certs in collision slots and require A14 zygote verification.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
TMP=${TMPDIR:-/tmp}/fx-mitm-status-collision-$$
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
MOD="$TMP/mod"; PG="$TMP/pg"; APEX="$TMP/apex"; SYS="$TMP/system"
mkdir -p "$MOD/scripts" "$MOD/bin/arm64" "$MOD/certs/submodules/pg_mitm_ca/system/etc/security/cacerts" "$PG/mitm" "$APEX" "$SYS"
cp "$ROOT/certs/pg-mitm-ca.pem" "$PG/mitm/ca.pem"
cp "$ROOT/certs/pg-mitm-ca.pem" "$MOD/certs/pg-mitm-ca.pem"
cp "$ROOT/certs/ca-index" "$MOD/certs/ca-index"
# Use the hashes recorded for the real CA but put it only in later collision slots.
H1=$(awk -F'|' '$2=="pg_mitm_ca"{print $5;exit}' "$MOD/certs/ca-index")
H2=$(awk -F'|' '$2=="pg_mitm_ca"{print $6;exit}' "$MOD/certs/ca-index")
[ -n "$H1" ] && [ -n "$H2" ] || { echo 'FAIL: CA hashes unavailable' >&2; exit 1; }
# An unrelated valid certificate occupies .0, so the MITM CA is deliberately .1/.2.
cp "$ROOT/certs/pg-https-ca.pem" "$APEX/$H1.0"
cp "$ROOT/certs/pg-mitm-ca.pem" "$APEX/$H1.1"
cp "$ROOT/certs/pg-https-ca.pem" "$APEX/$H2.0"
cp "$ROOT/certs/pg-mitm-ca.pem" "$APEX/$H2.2"
cat > "$MOD/bin/arm64/pg-mitm" <<'BIN'
#!/bin/sh
printf '{"ok":true,"notAfter":"2030-01-01T00:00:00Z"}\n'
BIN
chmod 755 "$MOD/bin/arm64/pg-mitm"
cat > "$MOD/scripts/certmgr.sh" <<'CERTMGR'
#!/bin/sh
[ "$1/$2" = builtin/list ] || exit 2
printf '{"ok":true,"certs":[{"id":"pg_mitm_ca","name":"MITM CA","released":1,"disabled":0,"apex":1,"apex_ns":"%s"}],"apex_partial":0}\n' "${MOCK_APEX_NS:-verified}"
CERTMGR
chmod 755 "$MOD/scripts/certmgr.sh"
cat > "$MOD/scripts/mitm-redirect.sh" <<'REDIRECT'
#!/bin/sh
[ "$1" = status ] && { echo '{"ok":true,"ipv4_redirect":"disabled"}'; exit 0; }
exit 2
REDIRECT
chmod 755 "$MOD/scripts/mitm-redirect.sh"
# Copy and redirect absolute paths into the isolated test fixture.
sed -e "s|^PG=/data/adb/privacyguard$|PG=$PG|" \
    -e "s|/apex/com.android.conscrypt/cacerts|$APEX|g" \
    -e "s|/system/etc/security/cacerts|$SYS|g" \
    -e "s|/data/adb/modules/pg_mitm_ca|$TMP/child|g" \
    "$ROOT/scripts/mitm-engine.sh" > "$MOD/scripts/mitm-engine.sh"
chmod 755 "$MOD/scripts/mitm-engine.sh"
# With CA at .1/.2 and live zygote verification, status must report trusted.
out=$(sh "$MOD/scripts/mitm-engine.sh" status)
printf '%s\n' "$out" | grep -Fq '"ca_system_trust":"present"' || { echo "FAIL: collision-slot CA not recognized: $out" >&2; exit 1; }
# A shell-visible certificate is not sufficient on Android 14+ when zygote is unverified.
out=$(MOCK_APEX_NS=unverified sh "$MOD/scripts/mitm-engine.sh" status)
printf '%s\n' "$out" | grep -Fq '"ca_system_trust":"absent"' || { echo "FAIL: unverified zygote trust was reported active: $out" >&2; exit 1; }
echo 'PASS: MITM status scans collision slots and refuses APEX trust without verified zygote namespace'
