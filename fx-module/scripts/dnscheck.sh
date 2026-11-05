#!/system/bin/sh
# PrivacyGuard DNS active probe. Does not alter firewall/configuration.
# Usage: dnscheck.sh [text|json] [name]; bounded by timeout when available.
_pg_d=$(dirname "$0" 2>/dev/null)
MODDIR=$(cd "$_pg_d/.." 2>/dev/null && pwd)
[ -f "$MODDIR/module.prop" ] || MODDIR=/data/adb/modules/privacyguard
. "$MODDIR/scripts/util.sh" 2>/dev/null
MODE=${1:-text}
NAME=${2:-example.com}
# Accept a DNS hostname only; validate each label rather than only the
# character set. In particular, reject leading/trailing hyphens and oversized
# labels before passing the value to platform-specific nslookup implementations.
if ! printf '%s\n' "$NAME" | awk '
  {
    name=$0
    if (length(name)<1 || length(name)>253 || name ~ /^\./ || name ~ /\.$/ || name ~ /\.\./) exit 1
    n=split(name, label, ".")
    for (i=1; i<=n; i++) {
      if (length(label[i])<1 || length(label[i])>63 ||
          label[i] !~ /^[A-Za-z0-9-]+$/ ||
          label[i] ~ /^-/ || label[i] ~ /-$/) exit 1
    }
  }
  END { if (NR!=1) exit 1 }
'; then
  NAME=example.com
fi
DNS_PROBE_STATUS=unsupported
DNS_PROBE_TOOL=none
DNS_PROBE_DETAIL="no bounded DNS lookup tool available"
DNS_PROBE_RC=127
LOOKUP_KIND=none
if command -v nslookup >/dev/null 2>&1; then
  LOOKUP_KIND=nslookup
  DNS_PROBE_TOOL=nslookup
elif command -v toybox >/dev/null 2>&1 && toybox nslookup 2>&1 | grep -Eiq 'usage:|unknown|not found|address|server'; then
  # Android commonly ships nslookup as a Toybox applet rather than a standalone binary.
  LOOKUP_KIND=toybox
  DNS_PROBE_TOOL=toybox-nslookup
fi
TIMEOUT_KIND=none
if command -v timeout >/dev/null 2>&1; then
  TIMEOUT_KIND=timeout
elif command -v toybox >/dev/null 2>&1 && toybox timeout 1 true >/dev/null 2>&1; then
  TIMEOUT_KIND=toybox
fi
if [ "$LOOKUP_KIND" != none ] && [ "$TIMEOUT_KIND" != none ]; then
  case "$TIMEOUT_KIND" in
    timeout)
      if [ "$LOOKUP_KIND" = nslookup ]; then
        _out=$(timeout 5 nslookup "$NAME" 2>&1); DNS_PROBE_RC=$?
      else
        _out=$(timeout 5 toybox nslookup "$NAME" 2>&1); DNS_PROBE_RC=$?
      fi
      ;;
    toybox)
      if [ "$LOOKUP_KIND" = nslookup ]; then
        _out=$(toybox timeout 5 nslookup "$NAME" 2>&1); DNS_PROBE_RC=$?
      else
        _out=$(toybox timeout 5 toybox nslookup "$NAME" 2>&1); DNS_PROBE_RC=$?
      fi
      ;;
  esac
  # nslookup prints the resolver's own address even when the queried name
  # fails (e.g. "Server: 192.168.1.1" followed by NXDOMAIN). Treat explicit
  # negative resolver outcomes as failures before looking for any IP address;
  # otherwise the status UI can falsely report DNS success and hide outages.
  if printf '%s\n' "$_out" | grep -Eiq 'NXDOMAIN|SERVFAIL|REFUSED|timed out|time out|no servers could be reached|can.t find|cannot find|not found|connection refused|network is unreachable|temporary failure in name resolution'; then
    DNS_PROBE_STATUS=failed
    DNS_PROBE_DETAIL=$(printf '%s\n' "$_out" | tail -n 2 | tr '\n' ' ' | sed 's/"/\\"/g')
    [ -n "$DNS_PROBE_DETAIL" ] || DNS_PROBE_DETAIL="resolver returned a negative response"
  elif [ "$DNS_PROBE_RC" -eq 0 ] && printf '%s\n' "$_out" | grep -Eiq '(^|[[:space:]])(Address|Addresses):?[[:space:]]*[0-9]*[[:space:]]*([0-9]{1,3}\.){3}[0-9]{1,3}|(^|[[:space:]])[0-9]{1,3}(\.[0-9]{1,3}){3}([[:space:]]|$)|([0-9a-f]{0,4}:){2,}[0-9a-f:]+'; then
    DNS_PROBE_STATUS=success; DNS_PROBE_DETAIL="lookup returned an address"
  elif [ "$DNS_PROBE_RC" -eq 124 ] || [ "$DNS_PROBE_RC" -eq 137 ]; then
    DNS_PROBE_STATUS=timeout; DNS_PROBE_DETAIL="lookup exceeded 5-second limit"
  else
    DNS_PROBE_STATUS=failed; DNS_PROBE_DETAIL=$(printf '%s\n' "$_out" | tail -n 2 | tr '\n' ' ' | sed 's/"/\\"/g')
    [ -n "$DNS_PROBE_DETAIL" ] || DNS_PROBE_DETAIL="lookup returned no address (rc=$DNS_PROBE_RC)"
  fi
elif [ "$LOOKUP_KIND" != none ]; then
  DNS_PROBE_STATUS=unsupported
  DNS_PROBE_DETAIL="lookup tool found but no bounded timeout command is available; lookup not executed"
  DNS_PROBE_RC=125
fi
if [ "$MODE" = json ]; then
  _name=$(printf '%s' "$NAME" | sed 's/\\/\\\\/g;s/"/\\"/g')
  _detail=$(printf '%s' "$DNS_PROBE_DETAIL" | sed 's/\\/\\\\/g;s/"/\\"/g')
  printf '{"dns_probe_status":"%s","dns_probe_tool":"%s","dns_probe_name":"%s","dns_probe_detail":"%s","dns_probe_rc":%s}\n' "$DNS_PROBE_STATUS" "$DNS_PROBE_TOOL" "$_name" "$_detail" "$DNS_PROBE_RC"
else
  echo "DNS 主动探测: $DNS_PROBE_STATUS"
  echo "查询工具: $DNS_PROBE_TOOL"
  echo "查询域名: $NAME"
  echo "结果: $DNS_PROBE_DETAIL"
  echo "注意: 成功仅表示系统解析器完成了该次查询；不能单独证明所有应用、DoH/DoT 或全部 DNS 流量均正常。"
fi
[ "$DNS_PROBE_STATUS" = success ]
