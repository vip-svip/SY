#!/bin/sh
set -eu
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
if [ -n "${1:-}" ]; then
  # Package lane: test the restored module after its source-restoration patcher.
  MODULE=$(CDPATH= cd -- "$1" && pwd)
  REPO=$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)
  SOURCE="$MODULE/scripts/yulong-app-firewall.sh"
else
  # Host lane: test the canonical reviewed source, not an unpatched Release snapshot.
  REPO=$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)
  MODULE="$REPO/fx-module"
  SOURCE="$REPO/scripts/yulong-app-firewall.sh"
fi
fail(){ echo "FAIL: $*" >&2; exit 1; }
[ -s "$SOURCE" ] || fail "Yulong firewall implementation missing"
sh -n "$SOURCE" || fail "Yulong firewall implementation has invalid POSIX shell syntax"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/fx-yulong-firewall.XXXXXX")
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
case "${3:-}" in
  -S)
    if [ "${4:-}" = OUTPUT ]; then
      printf '%s\n' '-P OUTPUT ACCEPT'
      while IFS= read -r hook; do [ -n "$hook" ] && printf '%s\n' "-A OUTPUT -j $hook"; done < "$MOCK_HOOKS4"
    else
      printf '%s\n' '-N FXYUL_A' '-N FXYUL_B'
      while IFS= read -r hook; do [ -n "$hook" ] && printf '%s\n' "-A OUTPUT -j $hook"; done < "$MOCK_HOOKS4"
    fi
    exit 0 ;;
  -C) [ "${4:-}" = OUTPUT ] && [ "${5:-}" = -j ] || exit 1; grep -qx "${6:-}" "$MOCK_HOOKS4"; exit $? ;;
  -I) [ "${4:-}" = OUTPUT ] && [ "${5:-}" = 1 ] && [ "${6:-}" = -j ] || exit 1; printf '%s\n' "${7:-}" >> "$MOCK_HOOKS4"; exit 0 ;;
  -D)
    [ "${4:-}" = OUTPUT ] && [ "${5:-}" = -j ] || exit 1
    [ "${MOCK_FAIL_DELETE_CHAIN:-}" != "${6:-}" ] || exit 1
    tmp=$(mktemp "$MOCK_HOOKS4.tmp.XXXXXX") || exit 1; grep -vx "${6:-}" "$MOCK_HOOKS4" > "$tmp" || :; mv -f "$tmp" "$MOCK_HOOKS4"; exit 0 ;;
esac
exit 0
IPTABLES
cat > "$TMP/bin/ip6tables" <<'IP6TABLES'
#!/bin/sh
echo "ip6tables $*" >> "$MOCK_LOG"
case "${3:-}" in
  -S)
    if [ "${4:-}" = OUTPUT ]; then
      printf '%s\n' '-P OUTPUT ACCEPT'
      while IFS= read -r hook; do [ -n "$hook" ] && printf '%s\n' "-A OUTPUT -j $hook"; done < "$MOCK_HOOKS6"
    else
      printf '%s\n' '-N FXYUL_A' '-N FXYUL_B'
      while IFS= read -r hook; do [ -n "$hook" ] && printf '%s\n' "-A OUTPUT -j $hook"; done < "$MOCK_HOOKS6"
    fi
    exit 0 ;;
  -C) [ "${4:-}" = OUTPUT ] && [ "${5:-}" = -j ] || exit 1; grep -qx "${6:-}" "$MOCK_HOOKS6"; exit $? ;;
  -I)
    [ "${4:-}" = OUTPUT ] && [ "${5:-}" = 1 ] && [ "${6:-}" = -j ] || exit 1
    if [ -n "${MOCK_FAIL_IPV6_ONCE:-}" ] && [ -e "$MOCK_FAIL_IPV6_ONCE" ]; then rm -f "$MOCK_FAIL_IPV6_ONCE"; exit 1; fi
    printf '%s\n' "${7:-}" >> "$MOCK_HOOKS6"; exit 0 ;;
  -D)
    [ "${4:-}" = OUTPUT ] && [ "${5:-}" = -j ] || exit 1
    [ "${MOCK_FAIL_DELETE_CHAIN:-}" != "${6:-}" ] || exit 1
    tmp="$MOCK_HOOKS6.tmp.$"; grep -vx "${6:-}" "$MOCK_HOOKS6" > "$tmp" || :; mv -f "$tmp" "$MOCK_HOOKS6"; exit 0 ;;
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
printf 'package:com.example.blocked uid:10123\npackage:com.example.allowed uid:10124\n' > "$PACKAGE_LIST"
NET_CLASS="$TMP/net"
mkdir -p "$NET_CLASS/wlan0" "$NET_CLASS/rmnet_data0" "$NET_CLASS/eth0" "$NET_CLASS/tun0"
cat > "$TMP/bin/date" <<'DATE'
#!/bin/sh
if [ "${1:-}" = "+%H:%M" ] && [ -n "${MOCK_TIME:-}" ]; then
  printf '%s\n' "$MOCK_TIME"
else
  exec /bin/date "$@"
fi
DATE
chmod 0755 "$TMP/bin/date"
REAL_NOHUP=$(command -v nohup)
MOCK_WATCH_SPAWN_LOG="$TMP/nohup-spawn.log"
grep -Fq 'if [ "${MOCK_WATCH_SPAWN_DELAY:-0}" = "1" ]' "$0" || fail "mock nohup delay is not expandable"
export REAL_NOHUP MOCK_WATCH_SPAWN_LOG
cat > "$TMP/bin/nohup" <<'NOHUP'
#!/bin/sh
printf 'spawn\n' >> "$MOCK_WATCH_SPAWN_LOG"
if [ "${MOCK_WATCH_SPAWN_DELAY:-0}" = "1" ]; then sleep 1; fi
exec "$REAL_NOHUP" "$@"
NOHUP
chmod 0755 "$TMP/bin/nohup"
MOCK_HOOKS4="$TMP/iptables.hooks"
MOCK_HOOKS6="$TMP/ip6tables.hooks"
: > "$MOCK_HOOKS4"; : > "$MOCK_HOOKS6"
export MOCK_HOOKS4 MOCK_HOOKS6
export MP="$TMP/module" PG="$TMP/pg" MOCK_LOG="$TMP/iptables.log"
export MOCK_PACKAGE_LIST="$PACKAGE_LIST" NET_CLASS MOCK_TIME=12:00
export PATH="$TMP/bin:$PATH"
CONF="$PG/settings.conf"
ACTIVE="$PG/yulong-firewall-active"
LOCK="$PG/yulong-firewall.lock"
export CONF ACTIVE LOCK
run(){ sh "$TMP/module/scripts/yulong-app-firewall.sh" "$@"; }

SENTINEL="$TMP/sentinel"
printf 'do-not-overwrite\n' > "$SENTINEL"

# Reject final and ancestor state-directory symlinks before touching external files.
mkdir "$TMP/external-state"
cp "$CONF" "$TMP/external-state/settings.conf"
ln -s "$TMP/external-state" "$TMP/state-link"
if env MP="$MP" PG="$TMP/state-link" CONF="$TMP/state-link/settings.conf" \
    ACTIVE="$TMP/state-link/yulong-firewall-active" LOCK="$TMP/state-link/yulong-firewall.lock" \
    NET_CLASS="$NET_CLASS" sh "$TMP/module/scripts/yulong-app-firewall.sh" list >/dev/null 2>&1; then
  fail "firewall accepted a symlinked PG directory"
fi
cmp -s "$CONF" "$TMP/external-state/settings.conf" || fail "PG symlink changed external settings"
[ ! -e "$TMP/external-state/yulong-firewall.lock" ] || fail "PG symlink created an external lock"
rm "$TMP/state-link"

mkdir "$TMP/real-parent"
ln -s "$TMP/real-parent" "$TMP/parent-link"
if env MP="$MP" PG="$TMP/parent-link/state" CONF="$TMP/parent-link/state/settings.conf" \
    ACTIVE="$TMP/parent-link/state/yulong-firewall-active" LOCK="$TMP/parent-link/state/yulong-firewall.lock" \
    NET_CLASS="$NET_CLASS" sh "$TMP/module/scripts/yulong-app-firewall.sh" list >/dev/null 2>&1; then
  fail "firewall accepted PG below a symlinked parent"
fi
[ ! -e "$TMP/real-parent/state" ] || fail "symlinked parent created external firewall state"
rm "$TMP/parent-link"

# Reject environment path overrides that redirect any persistent write outside PG.
value="$TMP/outside-settings.conf"
if env MP="$MP" PG="$PG" CONF="$value" ACTIVE="$ACTIVE" LOCK="$LOCK" \
    NET_CLASS="$NET_CLASS" sh "$TMP/module/scripts/yulong-app-firewall.sh" list >/dev/null 2>&1; then
  fail "firewall accepted an external CONF override"
fi
[ ! -e "$value" ] || fail "rejected CONF override created external settings"

value="$TMP/outside-active"
if env MP="$MP" PG="$PG" CONF="$CONF" ACTIVE="$value" LOCK="$LOCK" \
    NET_CLASS="$NET_CLASS" sh "$TMP/module/scripts/yulong-app-firewall.sh" list >/dev/null 2>&1; then
  fail "firewall accepted an external ACTIVE override"
fi
[ ! -e "$value" ] || fail "rejected ACTIVE override created external marker"

value="$TMP/outside-lock"
if env MP="$MP" PG="$PG" CONF="$CONF" ACTIVE="$ACTIVE" LOCK="$value" \
    NET_CLASS="$NET_CLASS" sh "$TMP/module/scripts/yulong-app-firewall.sh" list >/dev/null 2>&1; then
  fail "firewall accepted an external LOCK override"
fi
[ ! -e "$value" ] || fail "rejected LOCK override created external lock"

# Reject symlinks at the active marker and operation lock themselves.
ln -s "$SENTINEL" "$ACTIVE"
if run list >/dev/null 2>&1; then fail "firewall accepted a symlinked active marker"; fi
[ "$(cat "$SENTINEL")" = "do-not-overwrite" ] || fail "active marker symlink target changed"
rm -f "$ACTIVE"
ln -s "$SENTINEL" "$LOCK"
if run list >/dev/null 2>&1; then fail "firewall accepted a symlinked operation lock"; fi
[ "$(cat "$SENTINEL")" = "do-not-overwrite" ] || fail "operation lock symlink target changed"
rm -f "$LOCK"
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

# Master configuration must contain exactly one valid enabled bit.
cp "$CONF" "$TMP/settings.valid"
cat > "$CONF" <<'BAD_NO_MASTER'
[list:yulong_app_firewall]
BAD_NO_MASTER
if run list > "$TMP/missing-master" 2>&1; then fail "firewall list accepted a missing master section"; fi
grep -qx 'FXYULONGFW2' "$TMP/$TMP/missing-master" && fail "invalid master emitted a success protocol header"
cat > "$CONF" <<'BAD_DUP_MASTER'
[conf:yulong_app_firewall]
enabled=0
[conf:yulong_app_firewall]
enabled=1
BAD_DUP_MASTER
if run list > "$TMP/duplicate-master" 2>&1; then fail "firewall list accepted duplicate master sections"; fi
grep -qx 'FXYULONGFW2' "$TMP/$TMP/duplicate-master" && fail "invalid master emitted a success protocol header"
cat > "$CONF" <<'BAD_INVALID_MASTER'
[conf:yulong_app_firewall]
enabled=maybe
BAD_INVALID_MASTER
if run list > "$TMP/invalid-master" 2>&1; then fail "firewall list accepted an invalid master value"; fi
grep -qx 'FXYULONGFW2' "$TMP/$TMP/invalid-master" && fail "invalid master emitted a success protocol header"
cat > "$CONF" <<'BAD_DUP_VALUE'
[conf:yulong_app_firewall]
enabled=0
enabled=1
BAD_DUP_VALUE
if run list > "$TMP/duplicate-master-value" 2>&1; then fail "firewall list accepted duplicate master keys"; fi
grep -qx 'FXYULONGFW2' "$TMP/$TMP/duplicate-master-value" && fail "invalid master emitted a success protocol header"

# An absent list section is a valid empty selection, but duplicate sections are not.
cat > "$CONF" <<'EMPTY_RULES'
[conf:yulong_app_firewall]
enabled=0
EMPTY_RULES
run list > "$TMP/no-rule-section"
grep -qx 'FXYULONGFW2' "$TMP/no-rule-section" || fail "empty rule set lost protocol header"
grep -qx 'master=0' "$TMP/no-rule-section" || fail "empty rule set lost valid master state"
[ "$(wc -l < "$TMP/no-rule-section" | tr -d ' ')" = 2 ] || fail "missing rule-list section must represent an empty rule set"
cat > "$CONF" <<'DUP_RULES'
[conf:yulong_app_firewall]
enabled=0
[list:yulong_app_firewall]
[list:yulong_app_firewall]
DUP_RULES
if run list > "$TMP/duplicate-rule-section" 2>&1; then fail "firewall list accepted duplicate rule-list sections"; fi
mv "$TMP/settings.valid" "$CONF"

run list > "$TMP/list"
grep -qx 'FXYULONGFW2' "$TMP/list" || fail "firewall list protocol header missing"
grep -qx 'master=0' "$TMP/list" || fail "firewall default master state is not disabled"

# Root must revalidate package existence and the caller's UID before mutating
# a per-app rule. A stale UI row after uninstall/reinstall must not overwrite
# the saved package rule with an obsolete or unrelated UID.
if run rule com.example.blocked 99999 1 1 1 0 22:00 06:00 > "$TMP/uid-mismatch.out" 2>&1; then
  fail "firewall accepted a stale/mismatched package UID"
fi
grep -Fq "package UID changed" "$TMP/uid-mismatch.out" || fail "UID mismatch rejection was not explained"
if grep -Fq "com.example.blocked|99999|" "$CONF"; then
  fail "UID mismatch changed the persisted firewall rule"
fi
printf 'package:com.example.allowed uid:10124\n' > "$PACKAGE_LIST"
if run set com.example.blocked 10123 1 > "$TMP/package-missing.out" 2>&1; then
  fail "firewall accepted a package that is no longer installed"
fi
grep -Fq "no longer installed" "$TMP/package-missing.out" || fail "missing package rejection was not explained"
printf 'package:com.example.blocked uid:10123\npackage:com.example.allowed uid:10124\n' > "$PACKAGE_LIST"
export MOCK_PACKAGE_LIST_FAIL=1
if run rule com.example.blocked 10123 1 1 1 0 22:00 06:00 > "$TMP/uid-snapshot-failed.out" 2>&1; then
  fail "firewall accepted a rule mutation when package UID verification failed"
fi
unset MOCK_PACKAGE_LIST_FAIL

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
! grep -qx 'FXYUL_B' "$MOCK_HOOKS4" || fail "IPv4 new OUTPUT hook was not rolled back after IPv6 activation failure"
! grep -qx 'FXYUL_B' "$MOCK_HOOKS6" || fail "failed IPv6 hook became active"
grep -Fq 'iptables -t filter -D OUTPUT -j FXYUL_B' "$MOCK_LOG" || fail "IPv4 hook rollback command was not issued"
! grep -qx 'FXYUL_B' "$MOCK_HOOKS4" || fail "failed IPv6 activation left an IPv4 OUTPUT jump"
! grep -qx 'FXYUL_B' "$MOCK_HOOKS6" || fail "failed IPv6 activation left an IPv6 OUTPUT jump"

# Verify both protocol families receive the selected UID rule and a real
# OUTPUT jump that makes the populated chains reachable by device traffic.
run master 1 > "$TMP/enable.out"
grep -Fq 'firewall=1' "$TMP/enable.out" || fail "firewall did not enable"
grep -qx 'FXYUL_B' "$MOCK_HOOKS4" || fail "IPv4 new chain was not attached to OUTPUT"
grep -qx 'FXYUL_B' "$MOCK_HOOKS6" || fail "IPv6 new chain was not attached to OUTPUT"
grep -Fq 'iptables -t filter -I OUTPUT 1 -j FXYUL_B' "$MOCK_LOG" || fail "IPv4 OUTPUT hook insertion missing"
grep -Fq 'ip6tables -t filter -I OUTPUT 1 -j FXYUL_B' "$MOCK_LOG" || fail "IPv6 OUTPUT hook insertion missing"
grep -Fq 'iptables -t filter -A FXYUL_B -o wlan+ -m owner --uid-owner 10123 -j REJECT' "$MOCK_LOG" || fail "IPv4 Wi-Fi rule missing"
grep -Fq 'ip6tables -t filter -A FXYUL_B -o wlan+ -m owner --uid-owner 10123 -j REJECT' "$MOCK_LOG" || fail "IPv6 Wi-Fi rule missing"
grep -qx 'FXYUL_B' "$ACTIVE" || fail "active chain marker is incorrect"
grep -qx 'FXYUL_B' "$MOCK_HOOKS4" || fail "IPv4 OUTPUT jump was not installed"
grep -qx 'FXYUL_B' "$MOCK_HOOKS6" || fail "IPv6 OUTPUT jump was not installed"
[ "$(stat -c %a "$ACTIVE")" = 600 ] || fail "active marker is not private"

# Shared Android UIDs cannot be isolated by package name. Distinct saved rules
# for two packages sharing one UID merge into the effective UID policy.
cp "$CONF" "$TMP/shared-uid-before.conf"
printf 'package:com.example.blocked uid:10123\npackage:com.example.shared uid:10123\npackage:com.example.allowed uid:10124\n' > "$PACKAGE_LIST"
before_shared_lines=$(wc -l < "$MOCK_LOG")
run rule com.example.blocked 10123 1 1 0 0 22:00 06:00 > "$TMP/shared-wifi.out"
run rule com.example.shared 10123 1 0 1 0 22:00 06:00 > "$TMP/shared-mobile.out"
run list > "$TMP/shared-uid.list"
grep -Fq 'com.example.blocked|10123|1|1|0|0|22:00|06:00' "$TMP/shared-uid.list" || fail "shared UID Wi-Fi member rule was not preserved"
grep -Fq 'com.example.shared|10123|1|0|1|0|22:00|06:00' "$TMP/shared-uid.list" || fail "shared UID mobile member rule was not preserved"
shared_log="$TMP/shared-uid-apply.log"
tail -n +$((before_shared_lines + 1)) "$MOCK_LOG" > "$shared_log"
grep -Fq -- '-o wlan+ -m owner --uid-owner 10123 -j REJECT' "$shared_log" || fail "shared UID Wi-Fi policy from first package was not applied"
grep -Fq -- '-o rmnet+ -m owner --uid-owner 10123 -j REJECT' "$shared_log" || fail "shared UID mobile policy from second package was not merged"
grep -Fq -- 'ip6tables -t filter -A FXYUL_' "$shared_log" || fail "shared UID IPv6 chain was not rebuilt"
# Restore the original one-package state before the remaining lifecycle tests.
cp "$TMP/shared-uid-before.conf" "$CONF"
chmod 600 "$CONF"
printf 'package:com.example.blocked uid:10123\npackage:com.example.allowed uid:10124\n' > "$PACKAGE_LIST"
run apply > "$TMP/shared-uid-restore.out" || fail "original firewall policy could not be restored after shared UID regression"
grep -Fq 'firewall=1' "$TMP/shared-uid-restore.out" || fail "restored single-package firewall was not reactivated"

# Removing the last selected app is a valid empty policy. It must commit the
# config mutation and remove both active IPv4/IPv6 chains instead of rolling
# back to a still-blocking policy.
run remove com.example.blocked > "$TMP/remove-last.out"
grep -Fq 'firewall=0' "$TMP/remove-last.out" || fail "removing the last app did not disable the firewall"
[ ! -e "$ACTIVE" ] || fail "removing the last app left a stale active marker"
! grep -qx 'FXYUL_B' "$MOCK_HOOKS4" || fail "last-app removal left an IPv4 OUTPUT jump"
! grep -qx 'FXYUL_B' "$MOCK_HOOKS6" || fail "last-app removal left an IPv6 OUTPUT jump"
if grep -Fq 'com.example.blocked|10123|1' "$CONF"; then
  fail "removing the last app rolled back its config mutation"
fi
grep -Fq 'iptables -t filter -F FXYUL_B' "$MOCK_LOG" || fail "last-app removal did not clear IPv4 active chain"
grep -Fq 'ip6tables -t filter -F FXYUL_B' "$MOCK_LOG" || fail "last-app removal did not clear IPv6 active chain"

# Re-add once so uninstall is tested while the firewall is actually active.
run set com.example.blocked 10123 1 > "$TMP/re-enable.out"
grep -Fq 'firewall=1' "$TMP/re-enable.out" || fail "firewall did not reactivate after last-app removal"
[ -s "$ACTIVE" ] || fail "re-enabled firewall has no active marker"
grep -qx 'FXYUL_B' "$MOCK_HOOKS4" || fail "re-enabled firewall has no IPv4 OUTPUT jump"
grep -qx 'FXYUL_B' "$MOCK_HOOKS6" || fail "re-enabled firewall has no IPv6 OUTPUT jump"

run list > "$TMP/active.list"
grep -qx 'master=1' "$TMP/active.list" || fail "enabled master state not visible"
grep -Fq 'com.example.blocked|10123|1' "$TMP/active.list" || fail "enabled app row not visible"

# A selected app uninstall removes only owned chains but preserves the saved
# package selection so a reinstall can reapply the policy under its new UID.
printf 'package:com.example.allowed uid:10124\n' > "$PACKAGE_LIST"
before_lines=$(wc -l < "$MOCK_LOG")
run apply-event > "$TMP/uninstalled.out"
grep -Fq 'firewall=1' "$TMP/uninstalled.out" || fail "firewall master state was lost after selected app uninstall"
grep -Fq 'blocked_packages=0' "$TMP/uninstalled.out" || fail "uninstalled app remained in active UID rules"
[ ! -e "$ACTIVE" ] || fail "uninstall left a stale active-chain marker"
run list > "$TMP/uninstalled.list"
grep -Fq 'com.example.blocked|10123|1' "$TMP/uninstalled.list" || fail "uninstall discarded saved selection"
[ "$(tail -n +$((before_lines + 1)) "$MOCK_LOG" | grep -c -- '-F FXYUL_')" -ge 4 ] || fail "uninstall did not flush both owned IPv4/IPv6 chains"

# Reinstall same package with a new UID; both IP families must use only the
# fresh UID, never the stale UID recorded before uninstall.
printf 'package:com.example.blocked uid:10125\npackage:com.example.allowed uid:10124\n' > "$PACKAGE_LIST"
before_lines=$(wc -l < "$MOCK_LOG")
run apply-event > "$TMP/reinstalled.out"
grep -Fq 'blocked_packages=1' "$TMP/reinstalled.out" || fail "reinstalled app was not restored to firewall"
grep -Fq 'iptables -t filter -A FXYUL_B -o wlan+ -m owner --uid-owner 10125 -j REJECT' "$MOCK_LOG" || fail "IPv4 firewall did not adopt new UID"
grep -Fq 'ip6tables -t filter -A FXYUL_B -o wlan+ -m owner --uid-owner 10125 -j REJECT' "$MOCK_LOG" || fail "IPv6 firewall did not adopt new UID"
[ "$(tail -n +$((before_lines + 1)) "$MOCK_LOG" | grep -c -- 'uid-owner 10123')" -eq 0 ] || fail "reinstalled firewall kept stale UID"

# A failed PackageManager snapshot must leave the last known-good firewall on.
export MOCK_PACKAGE_LIST_FAIL=1
if run apply-event > "$TMP/snapshot-failed.out" 2>&1; then
  fail "firewall accepted failed PackageManager UID snapshot"
fi
unset MOCK_PACKAGE_LIST_FAIL
[ -f "$ACTIVE" ] || fail "snapshot failure removed last known-good active chain"

# A failed OUTPUT detach must fail closed and retain the active marker
# so a later disable retry can identify and clean the still-attached rules.
active_chain=$(cat "$ACTIVE")
case "$active_chain" in FXYUL_A|FXYUL_B) : ;; *) fail "active firewall chain marker is invalid before teardown test" ;; esac
export MOCK_FAIL_DELETE_CHAIN="$active_chain"
grep -qx "$active_chain" "$MOCK_HOOKS4" || fail "active IPv4 hook is absent before failure injection"
grep -qx "$active_chain" "$MOCK_HOOKS6" || fail "active IPv6 hook is absent before failure injection"
if run master 0 > "$TMP/disable-detach-failed.out" 2>&1; then
  cat "$TMP/disable-detach-failed.out" >&2
  tail -n 30 "$MOCK_LOG" >&2
  fail "firewall disable accepted a failed OUTPUT hook deletion"
fi
unset MOCK_FAIL_DELETE_CHAIN
[ -s "$ACTIVE" ] || fail "failed teardown discarded the active marker"
grep -qx "$active_chain" "$MOCK_HOOKS4" || fail "failed teardown lost the still-attached IPv4 hook"
grep -Fq "cannot detach FX firewall OUTPUT hook: $active_chain" "$TMP/disable-detach-failed.out" || fail "failed teardown did not report the hook deletion failure"

run uninstall
[ ! -e "$ACTIVE" ] || fail "uninstall did not remove active firewall state after successful retry"
! grep -qx 'FXYUL_B' "$MOCK_HOOKS4" || fail "uninstall left an IPv4 OUTPUT jump"
! grep -qx 'FXYUL_B' "$MOCK_HOOKS6" || fail "uninstall left an IPv6 OUTPUT jump"
[ ! -d "$PG/yulong-firewall.lock" ] || fail "uninstall left the firewall operation lock behind"


# V2 fixture isolates the original per-app network/schedule behavior.
V2="$TMP/v2"
mkdir -p "$V2/module/scripts" "$V2/pg" "$V2/net/wlan0" "$V2/net/rmnet_data0" "$V2/net/eth0" "$V2/net/tun0"
: > "$V2/iptables.hooks"; : > "$V2/ip6tables.hooks"
cp "$SOURCE" "$V2/module/scripts/yulong-app-firewall.sh"
printf 'id=privacyguard\n' > "$V2/module/module.prop"
cat > "$V2/pg/settings.conf" <<'EOF'
[conf:yulong_app_firewall]
enabled=0

[list:yulong_app_firewall]
EOF
cat > "$V2/packages.txt" <<'PKGS'
package:com.example.wifi uid:20001
package:com.example.mobile uid:20002
package:com.example.night uid:20003
package:com.example.none uid:20004
PKGS
v2run() {
  MP="$V2/module" PG="$V2/pg" CONF="$V2/pg/settings.conf" \
  ACTIVE="$V2/pg/yulong-firewall-active" LOCK="$V2/pg/yulong-firewall.lock" \
  NET_CLASS="$V2/net" MOCK_LOG="$V2/iptables.log" \
  MOCK_HOOKS4="$V2/iptables.hooks" MOCK_HOOKS6="$V2/ip6tables.hooks" \
  MOCK_PACKAGE_LIST="$V2/packages.txt" sh "$V2/module/scripts/yulong-app-firewall.sh" "$@"
}
export MOCK_TIME=12:00
v2run rule com.example.wifi 20001 1 1 0 0 22:00 06:00 > "$V2/wifi-save.out"
v2run rule com.example.mobile 20002 1 0 1 0 22:00 06:00 > "$V2/mobile-save.out"
v2run rule com.example.night 20003 1 1 1 1 22:00 06:00 > "$V2/night-save.out"
v2run rule com.example.none 20004 0 1 1 0 22:00 06:00 > "$V2/disabled-save.out"
export MOCK_TIME=23:00
# The master switch auto-starts the watcher; set the short host-test interval
# before that process is spawned so it inherits the intended 1-second cadence.
export WATCH_INTERVAL=1
v2run master 1 > "$V2/enable.out"
grep -Fq 'firewall=1' "$V2/enable.out" || fail "v2 firewall did not enable"
grep -qx 'FXYUL_B' "$V2/iptables.hooks" && grep -qx 'FXYUL_B' "$V2/ip6tables.hooks" || fail "V2 firewall did not attach both OUTPUT hooks"
grep -Fq 'iptables -t filter -A FXYUL_B -o wlan+ -m owner --uid-owner 20001 -j REJECT' "$V2/iptables.log" || fail "Wi-Fi wildcard rule missing"
grep -Fq 'ip6tables -t filter -A FXYUL_B -o wlan+ -m owner --uid-owner 20001 -j REJECT' "$V2/iptables.log" || fail "IPv6 Wi-Fi wildcard rule missing"
if grep -Fq ' -o rmnet+ -m owner --uid-owner 20001 ' "$V2/iptables.log"; then fail "Wi-Fi-only rule blocked mobile data"; fi
grep -Fq 'iptables -t filter -A FXYUL_B -o rmnet+ -m owner --uid-owner 20002 -j REJECT' "$V2/iptables.log" || fail "mobile-only wildcard rule missing"
if grep -Fq ' -o wlan+ -m owner --uid-owner 20002 ' "$V2/iptables.log"; then fail "mobile-only rule blocked Wi-Fi"; fi
grep -Fq 'iptables -t filter -A FXYUL_B -o eth+ -m owner --uid-owner 20001 -j REJECT' "$V2/iptables.log" || fail "other-transport fallback wildcard missing"
if grep -Fq 'uid-owner 20004' "$V2/iptables.log"; then fail "disabled rule generated packet matches"; fi
v2run list > "$V2/list"
grep -Fq 'com.example.wifi|20001|1|1|0|0|22:00|06:00' "$V2/list" || fail "Wi-Fi-only rule was not persisted"
grep -Fq 'com.example.night|20003|1|1|1|1|22:00|06:00' "$V2/list" || fail "scheduled rule was not persisted"

# Source FirewallManager uses inclusive local-time endpoints, including over midnight.
export MOCK_TIME=06:00
v2run apply-event > "$V2/end-inclusive.out"
grep -Fq -- '-o wlan+ -m owner --uid-owner 20003 -j REJECT' "$V2/iptables.log" || fail "schedule end boundary must be inclusive"
export MOCK_TIME=06:01
before_lines=$(wc -l < "$V2/iptables.log")
v2run apply-event > "$V2/after-end.out"
if tail -n +$((before_lines + 1)) "$V2/iptables.log" | grep -Fq 'uid-owner 20003'; then fail "cross-midnight rule remained active after its end minute"; fi

export MOCK_TIME=23:00
WATCH_PIDFILE="$V2/pg/yulong-app-firewall.pid"
WATCH_LOCK_PATH="$V2/pg/yulong-app-firewall-watch.lock"
export MOCK_WATCH_SPAWN_DELAY=1
: > "$MOCK_WATCH_SPAWN_LOG"
v2run stop-watch > "$V2/watch-stop-before-race.out"
# A lock directory without owner metadata may be a live starter paused after mkdir.
# Contenders must fail closed instead of stealing that active initialization window.
: > "$WATCH_LOCK_PATH"
export WATCH_LOCK_MAX_TRIES=3
if v2run start-watch > "$V2/watch-ownerless-lock.out" 2>&1; then
  fail "watcher start accepted an ownerless lock file"
fi
[ -f "$WATCH_LOCK_PATH" ] || fail "watcher start removed an ownerless lock file"
[ ! -s "$WATCH_LOCK_PATH" ] || fail "watcher wrote an owner PID into a lock owned by another start"
[ "$(wc -l < "$MOCK_WATCH_SPAWN_LOG" | tr -d ' ')" -eq 0 ] || fail "watcher spawned while an ownerless lock was present"
rm -f "$WATCH_LOCK_PATH"
unset WATCH_LOCK_MAX_TRIES
# Two simultaneous starts must serialize around the check/spawn/PID publication window.
v2run start-watch > "$V2/watch-start-a.out" 2>&1 &
start_a=$!
v2run start-watch > "$V2/watch-start-b.out" 2>&1 &
start_b=$!
wait "$start_a" || { cat "$V2/watch-start-a.out" >&2; fail "first concurrent watcher start failed"; }
wait "$start_b" || { cat "$V2/watch-start-b.out" >&2; fail "second concurrent watcher start failed"; }
_spawn_count=$(wc -l < "$MOCK_WATCH_SPAWN_LOG" | tr -d ' ')
if [ "$_spawn_count" -ne 1 ]; then
  echo "expected one nohup spawn, got $_spawn_count" >&2
  cat "$MOCK_WATCH_SPAWN_LOG" >&2 || :
  echo "start A output:" >&2; cat "$V2/watch-start-a.out" >&2 || :
  echo "start B output:" >&2; cat "$V2/watch-start-b.out" >&2 || :
  echo "watch PID: $(cat "$WATCH_PIDFILE" 2>/dev/null || echo missing)" >&2
  echo "lock owner: $(cat "$WATCH_LOCK_PATH" 2>/dev/null || echo missing)" >&2
  ps -ef 2>/dev/null | grep -F "$V2/module/scripts/yulong-app-firewall.sh" | grep -v grep >&2 || :
  fail "concurrent starts spawned more than one watcher"
fi
[ -s "$WATCH_PIDFILE" ] || fail "per-app schedule watcher PID file missing after concurrent start"
[ "$(stat -c %a "$WATCH_PIDFILE")" = 600 ] || fail "watcher PID record is not private"
watch_pid=$(cat "$WATCH_PIDFILE")
case "$watch_pid" in ''|*[!0-9]*) fail "watcher PID is malformed" ;; esac
kill -0 "$watch_pid" 2>/dev/null || fail "schedule watcher is not alive"
watch_cmdline=$(tr '\000' '\n' < "/proc/$watch_pid/cmdline" 2>/dev/null || true)
[ "$(printf '%s\n' "$watch_cmdline" | sed -n '2p')" = "$V2/module/scripts/yulong-app-firewall.sh" ] || fail "published PID is not the exact watcher script"
[ "$(printf '%s\n' "$watch_cmdline" | sed -n '3p')" = "watch-loop" ] || fail "published PID is not the watch-loop child"
if ! grep -Fq 'already-running' "$V2/watch-start-a.out" && ! grep -Fq 'already-running' "$V2/watch-start-b.out"; then
  fail "concurrent start did not observe the active watcher"
fi
[ ! -e "$WATCH_LOCK_PATH" ] || fail "watcher lifecycle lock remained after concurrent starts"

# Stop while a start is delayed before publishing its PID. The serialized stop
# must wait for publication, then terminate that exact watcher instead of missing it.
# Removing only the marker must not permit another watcher to spawn.
# The running process is rediscovered through /proc and its marker is restored.
: > "$MOCK_WATCH_SPAWN_LOG"
v2run start-watch > "$V2/watch-recover-base.out"
_recover_pid=$(cat "$WATCH_PIDFILE")
_recover_count=$(wc -l < "$MOCK_WATCH_SPAWN_LOG" | tr -d ' ')
rm -f "$WATCH_PIDFILE"
v2run start-watch > "$V2/watch-recover-marker.out"
[ "$(wc -l < "$MOCK_WATCH_SPAWN_LOG" | tr -d ' ')" -eq "$_recover_count" ] || fail "lost watcher marker caused a duplicate spawn"
[ "$(cat "$WATCH_PIDFILE")" = "$_recover_pid" ] || fail "live watcher marker was not restored to the existing process"
kill -0 "$_recover_pid" 2>/dev/null || fail "existing watcher died during marker recovery"

v2run stop-watch > "$V2/watch-stop-before-overlap.out"
: > "$MOCK_WATCH_SPAWN_LOG"
v2run start-watch > "$V2/watch-start-race.out" 2>&1 &
starting=$!
# Wait until the mock nohup records its spawn. That happens only after start-watch
# has acquired the lifecycle lock, so stop is guaranteed to contend with that owner.
_race_wait=0
while [ "$_race_wait" -lt 100 ]; do
  [ -s "$MOCK_WATCH_SPAWN_LOG" ] && break
  sleep 0.01
  _race_wait=$((_race_wait + 1))
done
[ -s "$MOCK_WATCH_SPAWN_LOG" ] || {
  cat "$V2/watch-start-race.out" >&2 || :
  fail "watcher start did not enter delayed child-spawn phase"
}
v2run stop-watch > "$V2/watch-stop-race.out" 2>&1 &
stopping=$!
wait "$starting" || { cat "$V2/watch-start-race.out" >&2; fail "watcher start failed during start/stop race"; }
wait "$stopping" || {
  cat "$V2/watch-stop-race.out" >&2
  _race_owner=$(cat "$WATCH_LOCK_PATH" 2>/dev/null || true)
  echo "race lock owner: $_race_owner" >&2
  echo "race expected script: $V2/module/scripts/yulong-app-firewall.sh" >&2
  case "$_race_owner" in ''|*[!0-9]*) : ;; *)
    if [ -r "/proc/$_race_owner/cmdline" ]; then
      echo "race owner cmdline:" >&2
      tr '\000' '\n' < "/proc/$_race_owner/cmdline" >&2 || :
      ps -o pid=,ppid=,args= -p "$_race_owner" >&2 || :
    fi
    ;;
  esac
  fail "watcher stop failed during start/stop race"
}
[ ! -e "$WATCH_PIDFILE" ] || fail "stop racing with start left a live watcher PID file"
[ ! -e "$WATCH_LOCK_PATH" ] || fail "watcher lifecycle lock remained after start/stop race"
[ "$(wc -l < "$MOCK_WATCH_SPAWN_LOG" | tr -d ' ')" -eq 1 ] || fail "start/stop race spawned unexpected watcher count"

unset MOCK_WATCH_SPAWN_DELAY
v2run start-watch > "$V2/watch-start.out"
[ -s "$WATCH_PIDFILE" ] || fail "watcher did not restart after serialized stop"
watch_pid=$(cat "$WATCH_PIDFILE")
kill -0 "$watch_pid" 2>/dev/null || fail "restarted watcher is not alive"
before_rebuild=$(grep -cE 'iptables -t filter -F FXYUL_[AB]' "$V2/iptables.log" || true)
mkdir -p "$V2/net/vendor0"
sleep 2
_watch_wait=0
after_rebuild=$before_rebuild
while [ "$after_rebuild" -le "$before_rebuild" ]; do
  [ "$_watch_wait" -lt 40 ] || fail "watcher did not re-apply after a new vendor interface appeared within 10 seconds"
  sleep 0.25
  after_rebuild=$(grep -cE 'iptables -t filter -F FXYUL_[AB]' "$V2/iptables.log" || true)
  _watch_wait=$((_watch_wait + 1))
done
if grep -Fq -- '-o vendor0 -m owner --uid-owner' "$V2/iptables.log"; then
  fail "unknown vendor interface was blocked without transport classification"
fi
v2run stop-watch > "$V2/watch-stop.out"
[ ! -e "$WATCH_PIDFILE" ] || fail "watcher PID file remained after stop"
v2run uninstall > "$V2/uninstall.out"
[ ! -e "$V2/pg/yulong-firewall-active" ] || fail "v2 uninstall left firewall active"
[ ! -s "$V2/iptables.hooks" ] && [ ! -s "$V2/ip6tables.hooks" ] || fail "V2 uninstall left OUTPUT hooks attached"

# Restore-from-Release layouts already include a schedule-stop block between
# STATE_DIR and REMOVER. The patcher must still insert firewall cleanup safely.
RESTORE="$TMP/release-layout"
mkdir -p "$RESTORE/scripts"
printf 'id=privacyguard\n' > "$RESTORE/module.prop"
cat > "$RESTORE/service.sh" <<'SERVICE'
#!/system/bin/sh
sh "$MODDIR/scripts/apply.sh" >> "$PG/boot.log" 2>&1
_rc=$?
SERVICE
cat > "$RESTORE/uninstall.sh" <<'UNINSTALL'
#!/system/bin/sh
MODDIR=/data/adb/modules/privacyguard
STATE_DIR=/data/adb/privacyguard
if [ -f "$MODDIR/scripts/yulong-ad-schedule.sh" ]; then
  sh "$MODDIR/scripts/yulong-ad-schedule.sh" stop >> "$STATE_DIR/yulong-ad-schedule.log" 2>&1 || :
fi
REMOVER="$MODDIR/scripts/remove_adhook_app.sh"
UNINSTALL
[ -s "$REPO/fx-patches/patch_yulong_app_firewall.py" ] || fail "firewall source restore patcher missing"
python3 "$REPO/fx-patches/patch_yulong_app_firewall.py" "$RESTORE" "$REPO" || fail "Release-layout firewall patch failed"
grep -Fq 'yulong-app-firewall.sh" apply' "$RESTORE/service.sh" || fail "service hook was not inserted"
grep -Fq 'yulong-app-firewall.sh" start-watch' "$RESTORE/service.sh" || fail "per-app schedule watcher boot hook missing"
grep -Fq 'yulong-ad-schedule.sh" start' "$RESTORE/service.sh" || fail "schedule start was not inserted"
grep -Fq 'yulong-ad-schedule.sh" stop' "$RESTORE/uninstall.sh" || fail "schedule stop was removed"
grep -Fq 'yulong-app-firewall.sh" uninstall' "$RESTORE/uninstall.sh" || fail "firewall uninstall cleanup was not inserted"
python3 "$REPO/fx-patches/patch_yulong_app_firewall.py" "$RESTORE" "$REPO" || fail "second Release-layout firewall patch failed"
cmp -s "$RESTORE/scripts/yulong-app-firewall.sh" "$REPO/scripts/yulong-app-firewall.sh" || fail "Release patcher staged a stale firewall implementation"
cmp -s "$RESTORE/scripts/tests/v1.0.0-yulong-app-firewall-regression.sh" "$REPO/scripts/tests/fx-yulong-app-firewall-regression.sh" || fail "Release patcher staged a stale firewall regression"
grep -Fq 'apply-event) with_lock --event apply_rules ;;' "$RESTORE/scripts/yulong-app-firewall.sh" || fail "restored module script has no package-event path"
grep -Fq 'start-watch) start_watch ;;' "$RESTORE/scripts/yulong-app-firewall.sh" || fail "restored firewall has no schedule watcher"
grep -Fq 'interface_snapshot' "$RESTORE/scripts/yulong-app-firewall.sh" || fail "restored firewall has no interface inventory watcher"
grep -Fq 'reconcile_watch_lifecycle' "$RESTORE/scripts/yulong-app-firewall.sh" || fail "app rule mutations do not reconcile watcher lifecycle"


[ "$(grep -Fc 'yulong-app-firewall.sh" apply' "$RESTORE/service.sh")" -eq 1 ] || fail "firewall boot hook is not idempotent"
[ "$(grep -Fc 'yulong-app-firewall.sh" start-watch' "$RESTORE/service.sh")" -eq 1 ] || fail "firewall watcher boot hook is not idempotent"
[ "$(grep -Fc 'yulong-ad-schedule.sh" start' "$RESTORE/service.sh")" -eq 1 ] || fail "schedule start hook is not idempotent"
[ "$(grep -Fc 'yulong-ad-schedule.sh" stop' "$RESTORE/uninstall.sh")" -eq 1 ] || fail "schedule stop hook is not idempotent"
[ "$(grep -Fc 'yulong-app-firewall.sh" uninstall' "$RESTORE/uninstall.sh")" -eq 1 ] || fail "firewall uninstall hook is not idempotent"

python3 - "$REPO/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java" "$REPO/adhook/app/src/main/java/de/privacyguard/adhook/imported/ad/FxYulongFirewallActivity.java" "$REPO/adhook/app/src/main/java/de/privacyguard/adhook/imported/ad/FxYulongFirewallAppFilterPolicy.java" "$REPO/adhook/app/src/test/java/de/privacyguard/adhook/imported/ad/FxYulongFirewallAppFilterPolicyTest.java" <<'PY'
from pathlib import Path
import sys
main = Path(sys.argv[1]).read_text(encoding="utf-8")
firewall = Path(sys.argv[2]).read_text(encoding="utf-8")
policy = Path(sys.argv[3]).read_text(encoding="utf-8")
policy_test = Path(sys.argv[4]).read_text(encoding="utf-8")

assert 'nativeAction("应用网络防火墙"' in main, "FX Ad shell must expose the native per-app firewall entry"
assert "FxYulongFirewallActivity.class" in main, "native firewall action must open the Wi-Fi/mobile firewall, not the VPN route picker"
assert "showImportedVpnAppManager();" not in main, "Ad firewall entry must not route to the VPN manager"
assert 'getStringExtra("suite_page")' in firewall, "firewall Activity must preserve legacy incoming page identity"
assert 'state.getString(STATE_SUITE_PAGE, launchPage)' in firewall, "selected firewall category must survive Activity recreation"
assert 'appFilterMode = "用户应用".equals(suitePage) ? 1 : "系统应用".equals(suitePage) ? 2 : 0;' in firewall
assert 'FxYulongFirewallAppFilterPolicy.includes(filterMode, info.flags)' in firewall, "user/system package classification policy must be applied before rendering"
assert "case ALL_APPS:" in policy and "case USER_APPS:" in policy and "case SYSTEM_APPS:" in policy
assert "private static final int FLAG_SYSTEM = 1;" in policy
assert "private static final int FLAG_UPDATED_SYSTEM_APP = 128;" in policy
assert "(applicationFlags & FLAG_SYSTEM)" in policy
assert "(applicationFlags & FLAG_UPDATED_SYSTEM_APP)" in policy
assert "unknownMode" in policy_test, "package policy unit tests must fail closed for unknown modes"
assert 'pageTitle.setText("FX Ad · " + suitePage)' in firewall, "native firewall page must update its unified title when category changes"
for page in ("按应用设置", "用户应用", "系统应用"):
    assert f'button("{page}", () -> selectSuitePage("{page}"))' in firewall, (
        f"the original {page} firewall category is not reachable from the FX Activity"
    )
assert "private void selectSuitePage(String page)" in firewall, "category selection must update the real app filter"
assert "appLoadGeneration++;" in firewall, "stale PackageManager callbacks must be invalidated on Activity destroy"
print("PASS: Yulong user/system/all-app firewall categories are reachable in the single FX Ad Activity and drive the real PackageManager filter")
PY

echo "PASS: Yulong per-app firewall preserves legacy rows, separates Wi-Fi/mobile, enforces inclusive local-time schedules, reconciles UIDs, and owns its watcher lifecycle"
