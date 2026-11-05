#!/system/bin/sh
# Runtime test: a configured chain is not enough; hook + redirect must both exist.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
S="$ROOT/scripts/status.sh"
T=$(mktemp -d "${TMPDIR:-/tmp}/fx-vpn-status-live.XXXXXX")
trap 'rm -rf "$T"' EXIT HUP INT TERM
mkdir -p "$T/bin" "$T/pg"
printf "vpn_mode=global\nvpn_node=test-node\n[conf:vpn]\nlocal_port=17996\n" > "$T/pg/settings.conf"
cat > "$T/bin/iptables" <<'IPT'
#!/bin/sh
args="$*"
case "$args" in
  '-w 5 -L'|'-w 5 -L '*) exit 0 ;;
  '-w 5 -S PGUARD') echo '-N PGUARD'; exit 0 ;;
  '-w 5 -t nat -S PGVPN')
    [ "${FX_TEST_CHAIN:-yes}" = yes ] || exit 1
    echo '-N PGVPN'
    if [ "${FX_TEST_REDIRECT:-yes}" = yes ]; then echo '-A PGVPN -p tcp -j REDIRECT --to-ports 17996'; fi
    exit 0 ;;
  '-w 5 -t nat -S PGNAT')
    echo '-N PGNAT'
    if [ "${FX_TEST_DNS_RULES:-no}" = yes ]; then
      echo '-A PGNAT -p udp --dport 53 -j DNAT --to-destination 127.0.0.1:53'
      echo '-A PGNAT -p tcp --dport 53 -j DNAT --to-destination 127.0.0.1:53'
    fi
    exit 0 ;;
  '-w 5 -t nat -S OUTPUT')
    echo '-N OUTPUT'
    if [ "${FX_TEST_HOOK:-yes}" = yes ]; then echo '-A OUTPUT -j PGVPN'; fi
    if [ "${FX_TEST_DNS_HOOK:-no}" = yes ]; then echo '-A OUTPUT -j PGNAT'; fi
    exit 0 ;;
esac
exit 1
IPT
cat > "$T/bin/ss" <<'SS'
#!/bin/sh
if [ "${FX_TEST_LISTENER:-yes}" = yes ]; then
  echo 'LISTEN 0 128 127.0.0.1:17996 0.0.0.0:*'
fi
exit 0
SS
cat > "$T/bin/ip6tables" <<'IPT6'
#!/bin/sh
case "$*" in '-w 5 -S PGUARD') echo '-N PGUARD'; exit 0 ;; esac
exit 1
IPT6
chmod 755 "$T/bin/iptables" "$T/bin/ip6tables" "$T/bin/ss"
check() {
  label=$1; expected=$2; shift 2
  out=$(env PATH="$T/bin:/usr/bin:/bin" PG="$T/pg" "$@" sh "$S" json)
  got=$(printf '%s' "$out" | python3 -c 'import json,sys; print(str(json.load(sys.stdin)["vpn_on"]).lower())')
  [ "$got" = "$expected" ] || { echo "FAIL $label: expected vpn_on=$expected got $got" >&2; exit 1; }
}
check active true
check missing-hook false FX_TEST_HOOK=no
check missing-redirect false FX_TEST_REDIRECT=no
check missing-chain false FX_TEST_CHAIN=no
check missing-listener false FX_TEST_LISTENER=no
check_dns() {
  label=$1; expected=$2; shift 2
  out=$(env PATH="$T/bin:/usr/bin:/bin" PG="$T/pg" FX_TEST_DNS_RULES=yes "$@" sh "$S" json)
  got=$(printf '%s' "$out" | python3 -c 'import json,sys; print(json.load(sys.stdin)["dns_forward_status"])')
  [ "$got" = "$expected" ] || { echo "FAIL DNS $label: expected=$expected got=$got" >&2; exit 1; }
}
check_dns active active FX_TEST_DNS_HOOK=yes
check_dns missing-output-hook inactive FX_TEST_HOOK=no FX_TEST_DNS_HOOK=no
printf '%s\n' 'PASS: status.sh requires VPN firewall hooks plus a live redirect listener; DNS firewall state remains independently reported'
