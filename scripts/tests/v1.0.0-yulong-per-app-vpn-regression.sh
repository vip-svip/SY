#!/system/bin/sh
set -eu
SOURCE_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
SCRIPT="$SOURCE_DIR/scripts/vpn-apps.sh"
sh -n "$SCRIPT" || { echo "VPN app manager has invalid POSIX shell syntax" >&2; exit 1; }
T="${TMPDIR:-/tmp}/fx-vpn-apps-$$"
mkdir -p "$T/module/scripts" "$T/pg"
cp "$SCRIPT" "$T/module/scripts/vpn-apps.sh"
cat > "$T/module/module.prop" <<'EOF'
id=privacyguard
EOF
cp "$SOURCE_DIR/scripts/util.sh" "$T/module/scripts/util.sh"
cat > "$T/module/scripts/apply.sh" <<'EOF'
#!/system/bin/sh
if [ "${FX_TEST_APPLY_DELAY:-0}" = "1" ]; then
  printf 'entered\n' >> "$FX_TEST_APPLY_LOG"
  sleep 1
fi
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
# Concurrent app-list writes must serialize through one transaction lock.
run_delayed() {
  env MP="$T/module" PG="$T/pg" CONF="$T/pg/settings.conf" \
    FX_TEST_APPLY_DELAY=1 FX_TEST_APPLY_LOG="$T/concurrent-apply.log" \
    sh "$SCRIPT" "$@"
}
: > "$T/concurrent-apply.log"
run_delayed apply-item com.example.concurrent_a 1 > "$T/concurrent-a.log" 2>&1 &
pid_a=$!
# Force a real overlap: A must have entered the slow apply phase while its
# transaction lock is held before B is started. This avoids scheduler flakiness.
for attempt in $(seq 1 50); do
  [ -s "$T/concurrent-apply.log" ] && break
  sleep 0.05
done
[ -s "$T/concurrent-apply.log" ] || { echo "first VPN writer never entered the apply phase" >&2; exit 1; }
[ -d "$T/pg/settings.conf.vpn-apps.lock" ] || { echo "first VPN writer released its lock before apply completed" >&2; exit 1; }
run_delayed apply-item com.example.concurrent_b 1 > "$T/concurrent-b.log" 2>&1 &
pid_b=$!
sleep 0.2
[ "$(wc -l < "$T/concurrent-apply.log" | tr -d ' ')" = 1 ] || {
  echo "second VPN writer entered apply while writer A still owned the lock" >&2
  cat "$T/concurrent-apply.log" >&2
  exit 1
}
wait "$pid_a" || { echo "first concurrent VPN app update failed" >&2; cat "$T/concurrent-a.log" >&2; exit 1; }
wait "$pid_b" || { echo "second concurrent VPN app update failed" >&2; cat "$T/concurrent-b.log" >&2; exit 1; }
run list > "$T/concurrent-list"
grep -Fq 'com.example.concurrent_a|com.example.concurrent_a|1' "$T/concurrent-list" || {
  echo "concurrent update A was lost" >&2; cat "$T/concurrent-list" >&2; exit 1;
}
grep -Fq 'com.example.concurrent_b|com.example.concurrent_b|1' "$T/concurrent-list" || {
  echo "concurrent update B was lost" >&2; cat "$T/concurrent-list" >&2; exit 1;
}
[ ! -e "$T/pg/settings.conf.vpn-apps.lock" ] || {
  echo "VPN app config lock leaked after concurrent updates" >&2; exit 1;
}
if grep -Fq 'CONF.vpn-apps.$$' "$SCRIPT" \
    || grep -Fq 'CONF.vpn-mode.$$' "$SCRIPT" \
    || grep -Fq 'CONF.vpn-apps.rollback.$$' "$SCRIPT" \
    || grep -Fq 'CONF.vpn-apps.restore.$$' "$SCRIPT"; then
  echo "predictable PID-suffixed VPN config temp paths remain" >&2; exit 1;
fi
grep -Fq 'mktemp "$CONF.vpn-apps.XXXXXX"' "$SCRIPT"
grep -Fq 'mktemp "$CONF.vpn-mode.XXXXXX"' "$SCRIPT"
grep -Fq 'mktemp "$CONF.vpn-apps.rollback.XXXXXX"' "$SCRIPT"
grep -Fq 'mktemp "$CONF.vpn-apps.restore.XXXXXX"' "$SCRIPT"

sh -n "$SCRIPT"
echo 'PASS: per-app VPN app-list CRUD, atomic rollback, serialized concurrent writes, input validation and empty-list guard'
rm -rf "$T"
