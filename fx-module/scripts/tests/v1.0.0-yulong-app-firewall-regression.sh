#!/system/bin/sh
set -e
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
SCRIPT="$ROOT/scripts/yulong-app-firewall.sh"
T="/tmp/fx-yulong-fw-$$"
mkdir -p "$T/module/scripts" "$T/pg" "$T/bin"
cp "$SCRIPT" "$T/module/scripts/yulong-app-firewall.sh"
printf 'id=privacyguard\n' > "$T/module/module.prop"
cat > "$T/pg/settings.conf" <<'EOF'
[conf:yulong_app_firewall]
enabled=0
[list:yulong_app_firewall]
EOF
cat > "$T/bin/iptables" <<'EOF'
#!/system/bin/sh
name=$(basename "$0")
printf '%s %s\n' "$name" "$*" >> "$FX_FW_LOG"
case "$*" in
  *" -C OUTPUT -j "*) exit 1 ;;
  *" -A "*)
    if [ "$name" = ip6tables ] && [ "$FX_FW_FAIL_V6_APPEND" = 1 ]; then exit 1; fi
    ;;
esac
exit 0
EOF
cp "$T/bin/iptables" "$T/bin/ip6tables"
cat > "$T/bin/cmd" <<'EOF'
#!/system/bin/sh
if [ "$1" = package ] && [ "$2" = list ] && [ "$3" = packages ] && [ "$4" = -U ]; then
  echo 'package:com.example.alpha uid:10001'
  echo 'package:com.example.beta uid:10002'
  exit 0
fi
exit 1
EOF
chmod 755 "$T/bin/iptables" "$T/bin/ip6tables" "$T/bin/cmd"
run() {
  MP="$T/module" PG="$T/pg" CONF="$T/pg/settings.conf" ACTIVE="$T/pg/active" LOCK="$T/pg/lock" \
  PATH="$T/bin:$PATH" FX_FW_LOG="$T/firewall.log" sh "$SCRIPT" "$@"
}
run list > "$T/list"
grep -qx 'FXYULONGFW1' "$T/list"
grep -qx 'master=0' "$T/list"
run set com.example.alpha 10001 1 > "$T/set-alpha"
grep -q '^com.example.alpha|10001|1$' "$T/pg/settings.conf"
run master 1 > "$T/enable"
grep -qx 'firewall=1' "$T/enable"
grep -qx 'blocked_packages=1' "$T/enable"
[ "$(cat "$T/pg/active")" = FXYUL_B ]
grep -q 'iptables -t filter -A FXYUL_B -m owner --uid-owner 10001 -j REJECT' "$T/firewall.log"
grep -q 'ip6tables -t filter -A FXYUL_B -m owner --uid-owner 10001 -j REJECT' "$T/firewall.log"
cp "$T/pg/settings.conf" "$T/before-failed-apply.conf"
if FX_FW_FAIL_V6_APPEND=1 run set com.example.beta 10002 1 > "$T/failed-apply.log" 2>&1; then
  echo 'IPv6 rule failure was incorrectly accepted' >&2; exit 1
fi
cmp -s "$T/before-failed-apply.conf" "$T/pg/settings.conf" || {
  echo 'failed dual-stack apply did not restore the previous settings.conf' >&2; exit 1;
}
[ "$(cat "$T/pg/active")" = FXYUL_B ] || {
  echo 'failed IPv6 activation replaced the previous active firewall chain' >&2; exit 1;
}
! grep -q '^com.example.beta|' "$T/pg/settings.conf"
if run remove com.example.alpha > "$T/remove-last.log" 2>&1; then
  echo 'firewall allowed an empty selected-app set while master was enabled' >&2; exit 1
fi
grep -q '^com.example.alpha|10001|1$' "$T/pg/settings.conf"
run master 0 > "$T/disable"
grep -qx 'firewall=0' "$T/disable"
[ ! -e "$T/pg/active" ]
run remove com.example.alpha
! grep -q '^com.example.alpha|' "$T/pg/settings.conf"
if run set 'com.bad;id' 10001 1 >/dev/null 2>&1; then
  echo 'unsafe package name was accepted' >&2; exit 1
fi
sh -n "$SCRIPT"
if grep -E '(^|[[:space:]])(iptables|ip6tables)[[:space:]].*(PGUARD|PGVPN|PGNAT|PGKS)' "$T/firewall.log"; then
  echo 'firewall touched an unrelated FX chain' >&2; exit 1
fi
echo 'PASS: Yulong app firewall config CRUD, UID refresh, IPv4/IPv6 chain build, fail-closed rollback, and FX chain isolation'
rm -rf "$T"
