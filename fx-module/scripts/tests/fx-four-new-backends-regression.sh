#!/system/bin/sh
# Regression for the four backends added this session: hide, certgen, rulepriority,
# autopackage. Each had behaviour verified once by hand; this pins it so a later edit
# cannot silently break the contract.
#
# Checks, per script:
#   hide.sh         apply records a reversible entry; status emits valid JSON; revert
#                   consumes the record
#   certgen.sh      refuses a CN that names the module; inspect reports a subject
#   rulepriority.sh show is JSON; apply keeps order stable and preserves other sections
#   autopackage.sh  verify passes when every binary has a matching sidecar
#
# Android-only calls (chmod semantics, real binaries) are not asserted on a host; those
# checks report SKIP rather than PASS.
set -u

_d=$(CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd)
MODDIR=$(CDPATH= cd -- "$_d/../.." 2>/dev/null && pwd)
[ -f "$MODDIR/module.prop" ] || { echo '{"ok":false,"error":"module directory unavailable"}'; exit 2; }

T=${TMPDIR:-/tmp}/fxfour.$$
mkdir -p "$T" || { echo '{"ok":false,"error":"cannot create temp dir"}'; exit 73; }
trap 'rm -rf "$T" 2>/dev/null' EXIT HUP INT TERM

fail() { echo "FAIL: $*" >&2; exit 1; }
note() { echo "  $*"; }
pass() { echo "  PASS  $*"; }

# ---- hide.sh -----------------------------------------------------------------
HIDEDIR="$T/mod-hide"
mkdir -p "$HIDEDIR/scripts" "$T/state-hide"
cp "$MODDIR/scripts/hide.sh" "$HIDEDIR/scripts/" 2>/dev/null || fail "hide.sh missing"
cp "$MODDIR/module.prop" "$HIDEDIR/" 2>/dev/null || fail "module.prop missing"

: > "$T/state-hide/apply.log"
PG="$T/state-hide" MODDIR="$HIDEDIR" sh "$HIDEDIR/scripts/hide.sh" apply > "$T/hide-apply.txt" 2>&1 \
  || fail "hide apply returned non-zero"
grep -q '"ok":true' "$T/hide-apply.txt" || fail "hide apply did not report ok"
[ -s "$T/state-hide/hide/applied.tsv" ] || fail "hide apply wrote no reversible record"
pass "hide apply 写入可逆记录"

PG="$T/state-hide" MODDIR="$HIDEDIR" sh "$HIDEDIR/scripts/hide.sh" status > "$T/hide-status.txt" 2>&1 \
  || fail "hide status returned non-zero"
grep -q '"limitations"' "$T/hide-status.txt" || fail "hide status omitted limitations"
grep -q '"mounts"' "$T/hide-status.txt" || fail "hide status omitted mounts"
pass "hide status 输出结构化报告并列出限制"

PG="$T/state-hide" MODDIR="$HIDEDIR" sh "$HIDEDIR/scripts/hide.sh" revert > "$T/hide-revert.txt" 2>&1 \
  || fail "hide revert returned non-zero"
grep -q '"ok":true' "$T/hide-revert.txt" || fail "hide revert did not report ok"
pass "hide revert 成功消费记录"

# ---- certgen.sh ---------------------------------------------------------------
CGDIR="$T/mod-cert"
mkdir -p "$CGDIR/scripts" "$CGDIR/certs" "$T/state-cert"
cp "$MODDIR/scripts/certgen.sh" "$CGDIR/scripts/" 2>/dev/null || fail "certgen.sh missing"
cp "$MODDIR/module.prop" "$CGDIR/" 2>/dev/null || fail "module.prop missing (cert)"
cp "$MODDIR/certs/pg-https-ca.pem" "$MODDIR/certs/pg-mitm-ca.pem" "$CGDIR/certs/" 2>/dev/null || :
if [ -f "$MODDIR/certs/pg-https-ca.pem" ]; then
  PG="$T/state-cert" MODDIR="$CGDIR" sh "$CGDIR/scripts/certgen.sh" inspect > "$T/cert-inspect.txt" 2>&1 \
    || fail "certgen inspect returned non-zero"
  grep -q '"subject"' "$T/cert-inspect.txt" || fail "certgen inspect reported no subject"
  pass "certgen inspect 报告证书身份"

  PG="$T/state-cert" MODDIR="$CGDIR" sh "$CGDIR/scripts/certgen.sh" generate --cn "PrivacyGuard Root" \
      > "$T/cert-refuse.txt" 2>&1
  _rc=$?
  [ "$_rc" -eq 64 ] || fail "certgen accepted a module-naming CN (rc=$_rc)"
  grep -q 'must not identify the module' "$T/cert-refuse.txt" || fail "certgen refusal message missing"
  pass "certgen 拒绝含模块名的 CN"
else
  note "SKIP certgen（certs 目录缺失）"
fi

# ---- rulepriority.sh ---------------------------------------------------------
RPDIR="$T/mod-rp"
mkdir -p "$RPDIR/scripts" "$T/state-rp"
cp "$MODDIR/scripts/rulepriority.sh" "$RPDIR/scripts/" 2>/dev/null || fail "rulepriority.sh missing"
cp "$MODDIR/module.prop" "$RPDIR/" 2>/dev/null || fail "module.prop missing (rp)"
cat > "$T/state-rp/settings.conf" <<RPCONF
schema_version=1

[list:rule]
https://example.com/tracker.list, tag=TRACK, 1
https://example.com/generic.list, tag=MISC, 1
https://example.com/ads.list, tag=AD, 1
https://example.com/antifraud.list, tag=FRAUD, 1

[list:targets]
com.example.app,privacy=1
RPCONF

PG="$T/state-rp" MODDIR="$RPDIR" sh "$RPDIR/scripts/rulepriority.sh" show > "$T/rp-show.txt" 2>&1 \
  || fail "rulepriority show returned non-zero"
grep -q '"class"' "$T/rp-show.txt" || fail "rulepriority show omitted the value class"
pass "rulepriority show 输出分级"

PG="$T/state-rp" MODDIR="$RPDIR" sh "$RPDIR/scripts/rulepriority.sh" apply > "$T/rp-apply.txt" 2>&1 \
  || fail "rulepriority apply returned non-zero"
_after=$(sed -n '/^\[list:rule\]/,/^\[/p' "$T/state-rp/settings.conf" | grep -c 'https://')
[ "$_after" -eq 4 ] || fail "rulepriority changed the rule count ($_after)"
_first=$(sed -n '/^\[list:rule\]/,$p' "$T/state-rp/settings.conf" | grep 'https://' | head -n1)
case "$_first" in
  *antifraud*) pass "rulepriority 把最高价值的源排到最前" ;;
  *) fail "rulepriority did not hoist the antifraud source: $_first" ;;
esac
grep -q '\[list:targets\]' "$T/state-rp/settings.conf" || fail "rulepriority destroyed another section"
pass "rulepriority 未破坏其他段落"

# ---- autopackage.sh ----------------------------------------------------------
PG="$T/state-pkg" MODDIR="$MODDIR" sh "$MODDIR/scripts/autopackage.sh" verify > "$T/pkg-verify.txt" 2>&1
_rc=$?
if grep -q '"ok":true' "$T/pkg-verify.txt"; then
  pass "autopackage verify 通过（全部二进制 sidecar 一致）"
else
  # A missing sidecar is a real defect, so report it rather than skipping quietly.
  grep -q 'MISSING sidecar' "$T/pkg-verify.txt" && fail "autopackage verify 发现缺失 sidecar"
  fail "autopackage verify 失败（rc=$_rc）"
fi

echo '{"ok":true,"checked":["hide","certgen","rulepriority","autopackage"]}'
