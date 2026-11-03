#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
MODULE="$ROOT/fx-module"
SOURCE="$MODULE/scripts/yulong-app-firewall.sh"
fail(){ echo "FAIL: $*" >&2; exit 1; }
[ -s "$SOURCE" ] || fail "Yulong firewall implementation missing"
sh -n "$SOURCE" || fail "Yulong firewall implementation has invalid POSIX shell syntax"
TMP=$(mktemp -d "\${TMPDIR:-/tmp}/fx-yulong-firewall.XXXXXX")
cleanup(){ rm -rf "$TMP"; }
trap cleanup EXIT HUP INT TERM
mkdir -p "$TMP/module/scripts" "$TMP/pg" "$TMP/bin"
cp "$SOURCE" "$TMP/module/scripts/yulong-app-firewall.sh"
printf 'id=privacyguard\n' > "$TMP/module/module.prop"
cat > "$TMP/pg/settings.conf" <<'EOF'
[conf:yulong_app_firewall]
enabled=0

[list:yulong_app_firewall]
EOF

cat > "$TMP/bin/iptables" <<'IPTABLES'
#!/bin/sh
echo "iptables $*" >> "$MOCK_LOG"
case "$*" in
  *" -C OUTPUT -j "*) exit 1 ;;
esac
exit 0
IPTABLES
cat > "$TMP/bin/ip6tables" <<'IP6TABLES'
#!/bin/sh
echo "ip6tables $*" >> "$MOCK_LOG"
case "$*" in
  *" -C OUTPUT -j "*) exit 1 ;;
  *" -I OUTPUT 1 -j "*)
    if [ -n "\${MOCK_FAIL_IPV6_ONCE:-}" ] && [ -e "$MOCK_FAIL_IPV6_ONCE" ]; then
      rm -f "$MOCK_FAIL_IPV6_ONCE"
      exit 1
    fi
    ;;
esac
exit 0
IP6TABLES
cat > "$TMP/bin/cmd" <<'CMD'
#!/bin/sh
if [ "$1" = package ] && [ "$2" = list ] && [ "$3" = packages ] && [ "$4" = -U ]; then
  [ -z "${MOCK_PACKAGE_LIST_FAIL:-}" ] || exit 1
  if [ -n "${MOCK_PACKAGE_LIST:-}" ] && [ -s "$MOCK_PACKAGE_LIST" ]; then
    cat "$MOCK_PACKAGE_LIST"
    exit 0
  fi
  echo "package:com.example.blocked uid:10123"
  echo "package:com.example.allowed uid:10124"
  exit 0
fi
exit 1
CMD
chmod 0755 "$TMP/bin/"*
PACKAGE_LIST="$TMP/packages.txt"
printf 'package:com.example.blocked uid:10123\\npackage:com.example.allowed uid:10124\\n' > "$PACKAGE_LIST"
export MP="$TMP/module" PG="$TMP/pg" MOCK_LOG="$TMP/iptables.log"
export MOCK_PACKAGE_LIST="$PACKAGE_LIST"
export PATH="$TMP/bin:$PATH"
CONF="$PG/settings.conf"
ACTIVE="$PG/yulong-firewall-active"
export CONF ACTIVE
run(){ sh "$TMP/module/scripts/yulong-app-firewall.sh" "$@"; }

SENTINEL="$TMP/sentinel"
printf 'do-not-overwrite\n' > "$SENTINEL"
WRAPPER_PID_FILE="$TMP/wrapper.pid"
export WRAPPER_PID_FILE

run_with_predictable_symlink_sentinels() {
  sh -c '
    conf=$1; active=$2; sentinel=$3; script=$4; shift 4
    pid=$$
    for suffix in yulong-master yulong-list yulong-rollback restore; do
      ln -s "$sentinel" "$conf.$suffix.$pid"
    done
    ln -s "$sentinel" "$active.tmp.$pid"
    printf "%s\n" "$pid" > "$WRAPPER_PID_FILE"
    exec sh "$script" "$@"
  ' sh "$CONF" "$ACTIVE" "$SENTINEL" "$TMP/module/scripts/yulong-app-firewall.sh" "$@"
}
remove_predictable_symlink_sentinels() {
  [ -s "$WRAPPER_PID_FILE" ] || return 0
  pid=$(cat "$WRAPPER_PID_FILE")
  for suffix in yulong-master yulong-list yulong-rollback restore; do
    rm -f "$CONF.$suffix.$pid"
  done
  rm -f "$ACTIVE.tmp.$pid" "$WRAPPER_PID_FILE"
}

# The settings file itself must not be read through a symlink.
mv "$CONF" "$TMP/settings.saved"
ln -s "$SENTINEL" "$CONF"
if run list >/dev/null 2>&1; then fail "firewall accepted a symlinked settings.conf"; fi
[ "$(cat "$SENTINEL")" = "do-not-overwrite" ] || fail "settings.conf symlink target was read/changed"
rm -f "$CONF"
mv "$TMP/settings.saved" "$CONF"

run list > "$TMP/list"
grep -qx 'FXYULONGFW1' "$TMP/list" || fail "firewall list protocol header missing"
grep -qx 'master=0' "$TMP/list" || fail "firewall default master state is not disabled"

# Exercise the old predictable temp names with sentinel symlinks in place.
run_with_predictable_symlink_sentinels set com.example.blocked 10123 1
[ "$(cat "$SENTINEL")" = "do-not-overwrite" ] || fail "firewall config writer followed a predictable temp symlink"
grep -Fq 'com.example.blocked|10123|1' "$CONF" || fail "firewall app row did not persist"
remove_predictable_symlink_sentinels

# Force only IPv6 activation to fail so the config transaction must roll back.
touch "$TMP/fail-ipv6-once"
export MOCK_FAIL_IPV6_ONCE="$TMP/fail-ipv6-once"
if run_with_predictable_symlink_sentinels master 1 > "$TMP/rollback.out" 2>&1; then
  fail "firewall committed while IPv6 chain activation was forced to fail"
fi
remove_predictable_symlink_sentinels
unset MOCK_FAIL_IPV6_ONCE
[ "$(cat "$SENTINEL")" = "do-not-overwrite" ] || fail "firewall rollback followed a predictable temp symlink"
grep -qx 'enabled=0' "$CONF" || fail "failed dual-stack activation did not restore previous config"
[ ! -e "$ACTIVE" ] || fail "failed activation left an active-chain marker"

# Verify both protocol families receive the selected UID rule.
run master 1 > "$TMP/enable.out"
grep -Fq 'firewall=1' "$TMP/enable.out" || fail "firewall did not enable"
grep -Fq 'iptables -t filter -A FXYUL_B -m owner --uid-owner 10123 -j REJECT' "$MOCK_LOG" || fail "IPv4 owner rule missing"
grep -Fq 'ip6tables -t filter -A FXYUL_B -m owner --uid-owner 10123 -j REJECT' "$MOCK_LOG" || fail "IPv6 owner rule missing"
grep -qx 'FXYUL_B' "$ACTIVE" || fail "active chain marker is incorrect"
[ "$(stat -c %a "$ACTIVE")" = 600 ] || fail "active marker is not private"

# Uninstalling a selected app removes stale UID rules but preserves its selection.
printf 'package:com.example.allowed uid:10124\\n' > "$PACKAGE_LIST"
before_lines=$(wc -l < "$MOCK_LOG")
run apply-event > "$TMP/uninstalled.out"
grep -Fq 'firewall=1' "$TMP/uninstalled.out" || fail "master firewall state was lost after app uninstall"
grep -Fq 'blocked_packages=0' "$TMP/uninstalled.out" || fail "uninstalled app remained in the active UID set"
[ ! -e "$ACTIVE" ] || fail "uninstall left a stale active-chain marker"
run list > "$TMP/uninstalled.list"
grep -Fq 'com.example.blocked|10123|1' "$TMP/uninstalled.list" || fail "uninstall discarded the saved package selection"
[ "$(tail -n +$((before_lines + 1)) "$MOCK_LOG" | grep -c -- '-F FXYUL_')" -ge 4 ] || fail "uninstall did not flush owned IPv4/IPv6 chains"

# Reinstalling the same package with a new UID applies the new UID to both families.
printf 'package:com.example.blocked uid:10125\\npackage:com.example.allowed uid:10124\\n' > "$PACKAGE_LIST"
before_lines=$(wc -l < "$MOCK_LOG")
run apply-event > "$TMP/reinstalled.out"
grep -Fq 'blocked_packages=1' "$TMP/reinstalled.out" || fail "reinstalled app was not restored to the firewall"
grep -Fq 'iptables -t filter -A FXYUL_B -m owner --uid-owner 10125 -j REJECT' "$MOCK_LOG" || fail "IPv4 firewall did not adopt new UID"
grep -Fq 'ip6tables -t filter -A FXYUL_B -m owner --uid-owner 10125 -j REJECT' "$MOCK_LOG" || fail "IPv6 firewall did not adopt new UID"
[ "$(tail -n +$((before_lines + 1)) "$MOCK_LOG" | grep -c -- 'uid-owner 10123')" -eq 0 ] || fail "reinstalled firewall kept the stale UID"

# An unavailable PackageManager snapshot must preserve the last known-good chain.
export MOCK_PACKAGE_LIST_FAIL=1
if run apply-event > "$TMP/snapshot-failed.out" 2>&1; then
  fail "firewall accepted a failed PackageManager UID snapshot"
fi
unset MOCK_PACKAGE_LIST_FAIL
[ -f "$ACTIVE" ] || fail "failed PackageManager snapshot removed the active chain"

run list > "$TMP/active.list"
grep -qx 'master=1' "$TMP/active.list" || fail "enabled master state not visible"
grep -Fq 'com.example.blocked|10123|1' "$TMP/active.list" || fail "enabled app row not visible"

run master 0 > "$TMP/disable.out"
grep -Fq 'firewall=0' "$TMP/disable.out" || fail "firewall did not disable"
[ ! -e "$ACTIVE" ] || fail "disable left an active marker"
grep -Fq 'iptables -t filter -F FXYUL_A' "$MOCK_LOG" || fail "IPv4 chain cleanup missing"
grep -Fq 'ip6tables -t filter -F FXYUL_B' "$MOCK_LOG" || fail "IPv6 chain cleanup missing"

# No PID-predictable temp names may be present in the implementation.
if grep -Eq 'CONF\.yulong-(master|list|rollback)\.\$\$|CONF\.restore\.\$\$|ACTIVE\.tmp\.\$\$' "$SOURCE"; then
  fail "predictable firewall temp paths remain"
fi
for pattern in 'mktemp "$CONF.yulong-master.XXXXXX"' 'mktemp "$CONF.yulong-list.XXXXXX"' \
               'mktemp "$CONF.yulong-rollback.XXXXXX"' 'mktemp "$CONF.restore.XXXXXX"' \
               'mktemp "$ACTIVE.XXXXXX"'; do
  grep -Fq "$pattern" "$SOURCE" || fail "missing unique temp creation: $pattern"
done
grep -Fq '[ -f "$CONF" ] && [ ! -L "$CONF" ]' "$SOURCE" || fail "settings.conf symlink guard missing"
grep -Fq '[ ! -L "$ACTIVE" ]' "$SOURCE" || fail "active marker symlink guard missing"

# Signal handlers must exit into the sole EXIT cleanup handler.
grep -Fqx '  trap cleanup_lock EXIT' "$SOURCE" || fail "EXIT lock cleanup handler missing"
grep -Fqx "  trap 'exit 129' HUP" "$SOURCE" || fail "HUP exit handler missing"
grep -Fqx "  trap 'exit 130' INT" "$SOURCE" || fail "INT exit handler missing"
grep -Fqx "  trap 'exit 143' TERM" "$SOURCE" || fail "TERM exit handler missing"
if grep -Fq "trap 'rmdir \"\$LOCK\" 2>/dev/null || :' EXIT HUP INT TERM" "$SOURCE"; then
  fail "firewall lock is released directly by signal traps"
fi

run uninstall
[ ! -e "$ACTIVE" ] || fail "uninstall did not remove active firewall state"
RECEIVER="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/imported/ad/FxYulongFirewallPackageReceiver.java"
MANIFEST="$ROOT/adhook/app/src/main/AndroidManifest.xml"
[ -s "$RECEIVER" ] || fail "package lifecycle firewall receiver missing"
grep -Fq 'FxYulongFirewallPackageReceiver' "$MANIFEST" || fail "package lifecycle receiver is not declared"
grep -Fq 'ACTION_PACKAGE_REMOVED' "$RECEIVER" || fail "package removal is not observed"
grep -Fq 'ACTION_PACKAGE_ADDED' "$RECEIVER" || fail "package install is not observed"
grep -Fq 'ACTION_PACKAGE_REPLACED' "$RECEIVER" || fail "package update is not observed"
grep -Fq 'PREF_MASTER' "$RECEIVER" || fail "receiver is not gated by the firewall master switch"
grep -Fq 'apply-event' "$RECEIVER" || fail "package receiver does not use bounded reconciliation"
grep -Fq 'apply-event) with_lock --event apply_rules ;;' "$SOURCE" || fail "bounded package-event command missing"
grep -Fq 'putBoolean("master_enabled", masterEnabled)' "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/imported/ad/FxYulongFirewallActivity.java" || fail "firewall UI does not publish its master state"
echo "PASS: Yulong app firewall reconciles uninstall/reinstall UID changes, preserves last-good rules on snapshot failure and cleans only owned chains"
