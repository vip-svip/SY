#!/system/bin/sh
set -eu
SOURCE_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
SCRIPT="$SOURCE_DIR/scripts/vpn-apps.sh"
T="${TMPDIR:-/tmp}/fx-vpn-apps-$$"
mkdir -p "$T/module/scripts" "$T/pg"
cp "$SCRIPT" "$T/module/scripts/vpn-apps.sh"
cat > "$T/module/module.prop" <<'EOF'
id=privacyguard
EOF
cp "$SOURCE_DIR/scripts/util.sh" "$T/module/scripts/util.sh"
cat > "$T/module/scripts/apply.sh" <<'EOF'
#!/system/bin/sh
[ "${FX_TEST_APPLY_FAIL:-0}" = "1" ] && exit 17
exit 0
EOF
chmod +x "$T/module/scripts/apply.sh"
cat > "$T/pg/settings.conf" <<'EOF'
vpn_app_proxy=0
[conf:vpn]
app_mode=bypass
[list:vpn_app]
com.example.alpha|com.example.alpha|1
[list:other]
other|other|1
EOF
run() { MP="$T/module" PG="$T/pg" CONF="$T/pg/settings.conf" sh "$SCRIPT" "$@"; }
run list > "$T/list"
grep -qx 'FXVPNAPP1' "$T/list"
cp "$T/pg/settings.conf" "$T/before-failed-apply.conf"
if FX_TEST_APPLY_FAIL=1 run apply-item com.example.rollback 1 >/dev/null 2>&1; then
  echo "configuration write unexpectedly survived a failed apply" >&2; exit 1
fi
cmp -s "$T/before-failed-apply.conf" "$T/pg/settings.conf" || {
  echo "failed apply did not restore the previous settings.conf" >&2; exit 1;
}
! grep -q '^com.example.rollback|' "$T/pg/settings.conf"
grep -qx 'master=0' "$T/list"
grep -qx 'mode=bypass' "$T/list"
grep -q '^com.example.alpha|com.example.alpha|1$' "$T/list"
run apply-item com.example.beta 1
run apply-item com.example.alpha 0
run apply-mode only
run apply-master 1
run list > "$T/list2"
grep -qx 'master=1' "$T/list2"
grep -qx 'mode=only' "$T/list2"
grep -q '^com.example.alpha|com.example.alpha|0$' "$T/list2"
grep -q '^com.example.beta|com.example.beta|1$' "$T/list2"
grep -q '^other|other|1$' "$T/pg/settings.conf"
if run apply-master 0; then :; else exit 1; fi
run apply-remove com.example.beta
run list > "$T/list3"
! grep -q '^com.example.beta|' "$T/list3"
if run set-item 'com.bad;rm -rf /' 1 >/dev/null 2>&1; then
  echo "unsafe package name accepted" >&2; exit 1
fi
# Enabling per-app routing without a selected package is rejected.
run apply-remove com.example.alpha
if run master 1 >/dev/null 2>&1; then
  echo "master switch enabled with an empty app list" >&2; exit 1
fi
sh -n "$SCRIPT"
echo 'PASS: per-app VPN app-list CRUD, settings transaction, input validation and empty-list guard'
rm -rf "$T"
