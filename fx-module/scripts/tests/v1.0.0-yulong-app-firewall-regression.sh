#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
MODULE="$ROOT/fx-module"
SOURCE="$MODULE/scripts/yulong-app-firewall.sh"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/fx-yulong-firewall.XXXXXX")
mkdir -p "$TMP/module/scripts" "$TMP/pg" "$TMP/bin"
cp "$SOURCE" "$TMP/module/scripts/yulong-app-firewall.sh"
printf 'id=privacyguard\n' > "$TMP/module/module.prop"
cat > "$TMP/pg/settings.conf" <<'EOF'
[conf:yulong_app_firewall]
enabled=0

[list:yulong_app_firewall]
EOF
cat > "$TMP/bin/iptables" <<'EOF'
#!/bin/sh
echo "iptables $*" >> "$MOCK_LOG"
case "$*" in
  *" -I OUTPUT 1 -j "*)
    if [ -n "${MOCK_FAIL_IPV6_ONCE:-}" ] && [ -e "$MOCK_FAIL_IPV6_ONCE" ]; then
      rm -f "$MOCK_FAIL_IPV6_ONCE"
      exit 1
    fi
    ;;
  *" -C OUTPUT -j "*) exit 1 ;;
esac
EOF
cat > "$TMP/bin/ip6tables" <<'EOF'
#!/bin/sh
echo "ip6tables $*" >> "$MOCK_LOG"
case "$*" in
  *" -C OUTPUT -j "*) exit 1 ;;
  *) exit 0 ;;
esac
EOF
cat > "$TMP/bin/cmd" <<'EOF'
#!/bin/sh
if [ "$1" = package ] && [ "$2" = list ] && [ "$3" = packages ] && [ "$4" = -U ]; then
  echo "package:com.example.blocked uid:10123"
  echo "package:com.example.allowed uid:10124"
  exit 0
fi
exit 1
EOF
chmod 755 "$TMP/bin/"*
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
export MP="$TMP/module" PG="$TMP/pg" MOCK_LOG="$TMP/iptables.log"
export PATH="$TMP/bin:$PATH"
run() { sh "$TMP/module/scripts/yulong-app-firewall.sh" "$@"; }
export CONF="$PG/settings.conf" ACTIVE="$PG/yulong-firewall-active"
SENTINEL="$TMP/sentinel"
printf 'do-not-overwrite\\n' > "$SENTINEL"
WRAPPER_PID_FILE="$TMP/wrapper.pid"
export WRAPPER_PID_FILE

run_with_predictable_symlink_sentinels() {
  sh -c '
    conf=$1; active=$2; sentinel=$3; script=$4; shift 4
    pid=$
    for suffix in yulong-master yulong-list yulong-rollback restore; do
      ln -s "$sentinel" "$conf.$suffix.$pid"
    done
    ln -s "$sentinel" "$active.tmp.$pid"
    printf "%s\\n" "$pid" > "$WRAPPER_PID_FILE"
    exec sh "$script" "$@"
  ' sh "$CONF" "$ACTIVE" "$SENTINEL" "$TMP/module/scripts/yulong-app-firewall.sh" "$@"
}
remove_predictable_symlink_sentinels() {
  pid=$(cat "$WRAPPER_PID_FILE")
  for suffix in yulong-master yulong-list yulong-rollback restore; do
    rm -f "$CONF.$suffix.$pid"
  done
  rm -f "$ACTIVE.tmp.$pid" "$WRAPPER_PID_FILE"
}

# The settings file itself must not be read through a symlink.
mv "$CONF" "$TMP/settings.saved"
ln -s "$SENTINEL" "$CONF"
if run list >/dev/null 2>&1; then
  echo "FAIL: firewall accepted a symlinked settings.conf" >&2; exit 1
fi
[ "$(cat "$SENTINEL")" = "do-not-overwrite" ] || { echo "FAIL: settings.conf symlink target was read/changed" >&2; exit 1; }
rm -f "$CONF"
mv "$TMP/settings.saved" "$CONF"

run list > "$TMP/list"
grep -qx 'FXYULONGFW1' "$TMP/list"
grep -qx 'master=0' "$TMP/list"

# Exercise every old predictable temp name while its target is a sentinel symlink.
run_with_predictable_symlink_sentinels set com.example.blocked 10123 1
[ "$(cat "$SENTINEL")" = "do-not-overwrite" ] || { echo "FAIL: firewall config writer followed a predictable temp symlink" >&2; exit 1; }
grep -Fq 'com.example.blocked|10123|1' "$PG/settings.conf"
remove_predictable_symlink_sentinels

# Force the IPv6 OUTPUT swap to fail once so the transaction takes its restore path.
touch "$TMP/fail-ipv6-once"
export MOCK_FAIL_IPV6_ONCE="$TMP/fail-ipv6-once"
if run_with_predictable_symlink_sentinels master 1 > "$TMP/rollback.out" 2>&1; then
  echo "FAIL: firewall unexpectedly committed while IPv6 chain activation was forced to fail" >&2; exit 1
fi
remove_predictable_symlink_sentinels
unset MOCK_FAIL_IPV6_ONCE
[ "$(cat "$SENTINEL")" = "do-not-overwrite" ] || { echo "FAIL: firewall rollback followed a predictable temp symlink" >&2; exit 1; }
grep -qx 'enabled=0' "$PG/settings.conf"
test ! -e "$PG/yulong-firewall-active"

run master 1 > "$TMP/enable.out"
grep -Fq 'firewall=1' "$TMP/enable.out"
grep -Fq 'iptables -t filter -A FXYUL_B -m owner --uid-owner 10123 -j REJECT' "$MOCK_LOG"
grep -Fq 'ip6tables -t filter -A FXYUL_B -m owner --uid-owner 10123 -j REJECT' "$MOCK_LOG"
grep -qx 'FXYUL_B' "$PG/yulong-firewall-active"

run list > "$TMP/active.list"
grep -qx 'master=1' "$TMP/active.list"
grep -Fq 'com.example.blocked|10123|1' "$TMP/active.list"

run master 0 > "$TMP/disable.out"
grep -Fq 'firewall=0' "$TMP/disable.out"
test ! -e "$PG/yulong-firewall-active"
grep -Fq 'iptables -t filter -F FXYUL_A' "$MOCK_LOG"
grep -Fq 'ip6tables -t filter -F FXYUL_B' "$MOCK_LOG"

# No source path may retain PID-predictable temp file names or a symlinkable config.
! grep -Eq 'yulong-(master|list|rollback)\\.\\$\\$|restore\\.\\$\\$|ACTIVE\\.tmp\\.\\$\\test ! -e "$PG/yulong-firewall-active"

# Signals must terminate into the sole EXIT cleanup handler; a signal must
# never unlock the firewall transaction and then resume its mutation.
grep -Fqx '  trap cleanup_lock EXIT' "$SOURCE"
grep -Fqx "  trap 'exit 129' HUP" "$SOURCE"
grep -Fqx "  trap 'exit 130' INT" "$SOURCE"
grep -Fqx "  trap 'exit 143' TERM" "$SOURCE"
! grep -Fq "trap 'rmdir \"\$LOCK\" 2>/dev/null || :' EXIT HUP INT TERM" "$SOURCE" || {
  echo "FAIL: firewall lock is released directly by a signal trap" >&2; exit 1;
}
echo \"PASS: Yulong app firewall persists lists, resolves UID, activates IPv4+IPv6 rules, disables, and cleans up only its own chains\"
 "$SOURCE" || {
  echo "FAIL: predictable firewall temp paths remain" >&2; exit 1;
}
grep -Fq 'mktemp "$CONF.yulong-master.XXXXXX"' "$SOURCE"
grep -Fq 'mktemp "$CONF.yulong-list.XXXXXX"' "$SOURCE"
grep -Fq 'mktemp "$CONF.yulong-rollback.XXXXXX"' "$SOURCE"
grep -Fq 'mktemp "$CONF.restore.XXXXXX"' "$SOURCE"
grep -Fq '[ -f "$CONF" ] && [ ! -L "$CONF" ]' "$SOURCE"

run uninstall
test ! -e "$PG/yulong-firewall-active"

# Signals must terminate into the sole EXIT cleanup handler; a signal must
# never unlock the firewall transaction and then resume its mutation.
grep -Fqx '  trap cleanup_lock EXIT' "$SOURCE"
grep -Fqx "  trap 'exit 129' HUP" "$SOURCE"
grep -Fqx "  trap 'exit 130' INT" "$SOURCE"
grep -Fqx "  trap 'exit 143' TERM" "$SOURCE"
! grep -Fq "trap 'rmdir \"\$LOCK\" 2>/dev/null || :' EXIT HUP INT TERM" "$SOURCE" || {
  echo "FAIL: firewall lock is released directly by a signal trap" >&2; exit 1;
}
echo \"PASS: Yulong app firewall persists lists, resolves UID, activates IPv4+IPv6 rules, disables, and cleans up only its own chains\"
