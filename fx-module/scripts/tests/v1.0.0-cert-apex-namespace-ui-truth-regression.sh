#!/bin/sh
# Regression checks for Android 14+ Conscrypt namespace truth and boot-safe CA sync.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
CERT="$ROOT/scripts/certmgr.sh"
NS="$ROOT/scripts/cert-apex-ns.sh"
COPY="$ROOT/scripts/certcopy.sh"
UI="$ROOT/webroot/index.html"
POST="$ROOT/post-fs-data.sh"
SERVICE="$ROOT/service.sh"
fail() { echo "FAIL: $*" >&2; exit 1; }
sh -n "$CERT" || fail 'certmgr shell syntax'
sh -n "$NS" || fail 'APEX namespace helper syntax'
sh -n "$COPY" || fail 'collision-safe cert helper syntax'
sh -n "$POST" || fail 'post-fs-data shell syntax'
sh -n "$SERVICE" || fail 'service shell syntax'

# Namespace helper must verify the zygote by its namespace ID after deduplicating
# candidates, so PID 1 sharing a mount namespace with zygote cannot false-fail.
grep -Fq 'ca_apex_ns_id "$_can_pid"' "$NS" || fail 'per-process mount namespace resolution missing'
grep -Fq 'ca_apex_ns_marker "$_can_pg" "$_can_zid"' "$NS" || fail 'zygote namespace marker verification missing'
grep -Fq 'no verified Conscrypt overlay in any live zygote namespace' "$NS" || fail 'required zygote fail-closed status missing'
grep -Fq 'APEX target mount remains in namespace' "$NS" || fail 'ambiguous mount preservation guard missing'

# Cert sync must detach owned namespaces before changing a shared overlay source,
# use collision-aware copy/remove, and report per-CA namespace verification.
python3 - "$CERT" <<'PY'
import sys
s=open(sys.argv[1]).read()
start=s.index('ca_sync_apex() {')
end=s.index('\n}\n', start)+3
f=s[start:end]
assert f.index('ca_apex_ns_unmount_all') < f.index('rm -rf "$OVL_APEX"'), 'unmount must precede source deletion'
assert 'ca_apex_ns_mount_all "$OVL_APEX" "$SC_APEX" "$PG"' in f
assert 'ca_copy_submodule_certs "$_ca_src" "$OVL_APEX"' in f
assert 'MARK_APEX_PARTIAL' in f
assert 'ca_apex_ns_verify_zygote "$SC_APEX" "$_ls_fp256" "$H1" "$H2"' in s
assert 'apex_ns' in s and '$APEX_NS' in s
assert '"apex_partial":%s' in s
assert 'system trust active' not in s
PY

# A raw child-module system mount can clobber a same-hash system root. Child CA
# modules are now skip_mount; certmgr owns collision-safe overlay publication.
grep -Fq ': > "$_rel_tmp/skip_mount"' "$CERT" || fail 'CA child skip_mount marker missing'
grep -Fq 'ca_store_has_cert "$SC_APEX"' "$CERT" || fail 'APEX lookup does not scan collision chain'
grep -Fq 'ca_remove_submodule_certs "$_cs_src" "$OVL" "system"' "$CERT" || fail 'disabled CA removal not collision-safe'
! grep -Eq 'rm -f "\$OVL(_APEX)?/\$_[ac]s?_h[12]\.0"' "$CERT" || fail 'blind .0 deletion survived'

# Older Android synchronizes before zygote; Android 14+ waits for a live zygote.
grep -Fq '[ "$_ca_api" -lt 34 ]' "$POST" || fail 'pre-zygote sync for Android <=13 missing'
grep -Fq 'ca-sync-boot-id' "$POST" || fail 'early sync boot marker missing'
grep -Fq 'pidof zygote64' "$SERVICE" || fail 'zygote namespace wait missing'
grep -Fq 'pg_ca_synced_this_boot' "$SERVICE" || fail 'duplicate boot remount guard missing'

# UI must not call A14 CA trusted based on shell /system file visibility alone.
grep -Fq "var live=apex?(c.apex_ns==='verified')" "$UI" || fail 'UI still trusts shell-side CA view on Android 14+'
grep -Fq '应用信任未验证' "$UI" || fail 'unverified namespace badge missing'
grep -Fq 'apex_partial' "$UI" || fail 'partial app namespace warning missing'

echo 'PASS: Conscrypt namespace verification, collision-safe CA overlays, boot-time sync ordering, and truthful UI state'

grep -Fq "if(j.migration_pending)notices.push" "$UI" || fail 'pending migration warning missing from UI'
