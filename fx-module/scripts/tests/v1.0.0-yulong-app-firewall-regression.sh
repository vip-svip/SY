#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
MODULE="$ROOT/fx-module"
SOURCE="$MODULE/scripts/yulong-app-firewall.sh"
TMP="${TMPDIR:-/tmp}/fx-yulong-firewall-$"
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
  *" -C OUTPUT -j "*) exit 1 ;;
  *) exit 0 ;;
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
export MP="$TMP/module" PG="$TMP/pg" MOCK_LOG="$TMP/iptables.log"
export PATH="$TMP/bin:$PATH"
run() { sh "$TMP/module/scripts/yulong-app-firewall.sh" "$@"; }

run list > "$TMP/list"
grep -qx 'FXYULONGFW1' "$TMP/list"
grep -qx 'master=0' "$TMP/list"

run set com.example.blocked 10123 1
grep -Fq 'com.example.blocked|10123|1' "$PG/settings.conf"

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

run uninstall
test ! -e "$PG/yulong-firewall-active"

echo "PASS: Yulong app firewall persists lists, resolves UID, activates IPv4+IPv6 rules, disables, and cleans up only its own chains"
rm -rf "$TMP"
