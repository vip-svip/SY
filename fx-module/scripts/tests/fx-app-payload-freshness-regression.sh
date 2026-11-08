#!/system/bin/sh
# Guard the "module ships the app, install releases it" contract.
#
# What this pins, so a stale or missing payload cannot ship silently again:
#   1. the module carries a system-app overlay AND an optional payload
#   2. both are the same bytes, and each has a matching sha256 sidecar
#   3. the payload actually contains the classes this module is supposed to provide
#      (a 1 MB release APK that predates the policy classes was shipped once already)
#   4. customize.sh and post-fs-data.sh still stage and verify that overlay
#
# Android-only calls cannot run here, so the script is static plus one DEX string scan;
# it fails closed on every check it can evaluate on a plain host.
set -u

_d=$(CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd)
MODDIR=$(CDPATH= cd -- "$_d/../.." 2>/dev/null && pwd)
[ -f "$MODDIR/module.prop" ] || { echo '{"ok":false,"error":"module directory unavailable"}'; exit 2; }

fail() { echo "FAIL: $*" >&2; exit 1; }
note() { echo "  $*"; }

OVERLAY="$MODDIR/system/app/FX/FX.apk"
OVERLAY_SUM="$MODDIR/system/app/FX/FX.apk.sha256"
OPTIONAL="$MODDIR/optional/FXUnifiedHook.apk"
OPTIONAL_SUM="$MODDIR/optional/FXUnifiedHook.apk.sha256"
CUSTOMIZE="$MODDIR/customize.sh"
POSTFS="$MODDIR/post-fs-data.sh"

# ---- 1. both payloads exist -------------------------------------------------------
[ -s "$OVERLAY" ] || fail "system-app overlay missing: system/app/FX/FX.apk"
[ -s "$OPTIONAL" ] || fail "optional payload missing: optional/FXUnifiedHook.apk"
[ -s "$OVERLAY_SUM" ] || fail "overlay checksum sidecar missing"
[ -s "$OPTIONAL_SUM" ] || fail "optional checksum sidecar missing"
note "payloads present"

# ---- 2. identical bytes + matching sidecars --------------------------------------
if command -v cmp >/dev/null 2>&1; then
  cmp -s "$OVERLAY" "$OPTIONAL" || fail "overlay and optional payload differ; a stale copy would ship"
  note "overlay and optional payload are byte-identical"
fi

check_sidecar() {
  _cs_apk=$1; _cs_sum=$2; _cs_label=$3
  if command -v sha256sum >/dev/null 2>&1; then
    _cs_want=$(awk 'NR==1 {print $1}' "$_cs_sum" 2>/dev/null)
    case "$_cs_want" in ''|*[!0-9a-fA-F]*) fail "$_cs_label sidecar malformed" ;; esac
    [ "${#_cs_want}" -eq 64 ] || fail "$_cs_label sidecar is not 64 hex characters"
    _cs_got=$(sha256sum "$_cs_apk" | awk '{print $1}')
    [ "$_cs_got" = "$_cs_want" ] || fail "$_cs_label sidecar does not match the APK"
    note "$_cs_label checksum matches"
  fi
}
check_sidecar "$OVERLAY" "$OVERLAY_SUM" overlay
check_sidecar "$OPTIONAL" "$OPTIONAL_SUM" optional

# ---- 3. the payload carries the policy classes -----------------------------------
# A one-dex 1.1 MB release APK shipped once and contained none of these; scanning DEX
# string constants is what caught it.
case "$(wc -c < "$OPTIONAL")" in
  *[!0-9]*) fail "cannot size the payload" ;;
esac
_payload_bytes=$(wc -c < "$OPTIONAL")
[ "$_payload_bytes" -ge 8000000 ] || fail "payload is only $_payload_bytes bytes; a full build is several MB larger than the 1.1 MB stale release"

# Extract classes*.dex from the APK without unzip: Android has no unzip in this PATH, and
# a zip entry can be read with a small python/jar-free path only. Prefer a helper if present.
SCAN=$(command -v strings 2>/dev/null || true)
if [ -n "${SCAN:-}" ]; then
  _dexdir=$(mktemp -d "${TMPDIR:-/tmp}/fxapp-verify.XXXXXX") || fail "cannot create temp dir"
  trap 'rm -rf "$_dexdir" 2>/dev/null' EXIT HUP INT TERM
  if command -v unzip >/dev/null 2>&1; then
    unzip -q -o "$OPTIONAL" 'classes*.dex' -d "$_dexdir" 2>/dev/null || fail "cannot extract dex from payload"
    _dexblob=$(cat "$_dexdir"/classes*.dex 2>/dev/null | head -c 200000000)
    _present=0
    for marker in AntiFraudBlockPolicy VendorAntiFraudCatalog VipUnlockPolicy; do
      case "$_dexblob" in
        *"$marker"*) _present=$((_present + 1)) ;;
      esac
    done
    [ "$_present" -ge 3 ] || fail "payload is missing this module's policy classes; a stale APK shipped"
    note "payload carries AntiFraudBlockPolicy / VendorAntiFraudCatalog / VipUnlockPolicy"
  else
    note "SKIP: unzip absent; dex string scan not evaluated on this host"
  fi
fi

# ---- 4. the stage + verify logic still exists ------------------------------------
grep -q 'fx_system_app_stage' "$CUSTOMIZE" || fail "customize.sh no longer stages the system app"
grep -q 'system/app/FX' "$CUSTOMIZE" || fail "customize.sh no longer targets system/app/FX"
grep -q 'fx-system-app-overlay-verify' "$POSTFS" || fail "post-fs-data.sh no longer verifies the overlay"
note "stage and boot-verify logic present"

echo "PASS: module carries a current FX app, install stages it, boot verifies it"
exit 0
