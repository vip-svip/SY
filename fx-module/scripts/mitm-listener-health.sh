#!/system/bin/sh
# Read-only health check for the exact loopback TCP socket used by the
# transparent MITM redirect. /proc/net/tcp stores IPv4 bytes little-endian.
# PG_PROC_NET_TCP is an injectable path for host-side regression tests only.
case "${1:-check}" in
  check)
    _tcp=${PG_PROC_NET_TCP:-/proc/net/tcp}
    [ -r "$_tcp" ] || exit 1
    # 127.0.0.1:18443 = 0100007F:4813; TCP_LISTEN state is 0A.
    awk 'NR > 1 && toupper($2) == "0100007F:4813" && toupper($4) == "0A" { found=1 } END { exit !found }' "$_tcp"
    ;;
  *) echo 'usage: mitm-listener-health.sh check' >&2; exit 2 ;;
esac
