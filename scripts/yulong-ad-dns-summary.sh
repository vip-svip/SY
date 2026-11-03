#!/system/bin/sh
# Privacy-preserving aggregate for the locally retained AdGuard Home query log.
# Only numeric counts are emitted. Query domains, client IPs and raw JSON never
# leave this process.
set -eu
umask 077

[ "$#" -eq 1 ] || { echo "usage: $0 <adguardhome-data-dir>" >&2; exit 2; }
DATA_DIR=$1
case "$DATA_DIR" in /*) ;; *) DATA_DIR="$PWD/$DATA_DIR" ;; esac

reject_symlink_components() {
  path=$1
  while [ -n "$path" ] && [ "$path" != "/" ]; do
    [ ! -L "$path" ] || return 1
    case "$path" in
      */*) parent=${path%/*}; [ -n "$parent" ] || parent=/ ;;
      *) break ;;
    esac
    [ "$parent" != "$path" ] || break
    path=$parent
  done
  return 0
}

reject_symlink_components "$DATA_DIR" || {
  echo "unsafe DNS log directory path" >&2
  exit 21
}
[ -d "$DATA_DIR" ] || { echo FXDNSLOG_EMPTY; exit 0; }
LOG_FILE="$DATA_DIR/querylog.json"
[ ! -L "$LOG_FILE" ] || { echo "DNS query log symlink rejected" >&2; exit 21; }
[ -e "$LOG_FILE" ] || { echo FXDNSLOG_EMPTY; exit 0; }
[ -f "$LOG_FILE" ] || { echo "DNS query log is not a regular file" >&2; exit 21; }
[ -s "$LOG_FILE" ] || { echo FXDNSLOG_EMPTY; exit 0; }

awk '
BEGIN { queries=0; blocked=0 }
{
  line=tolower($0)
  # AdGuard Home querylog is JSON-lines. Count only records with a DNS
  # question field; do not print or retain any field from the record.
  if (line ~ /^[[:space:]]*\{/ &&
      (line ~ /"qh"[[:space:]]*:/ || line ~ /"question"[[:space:]]*:/)) {
    queries++
    if (line ~ /"isfiltered"[[:space:]]*:[[:space:]]*true/ ||
        line ~ /"reason"[[:space:]]*:[[:space:]]*"filtered[^"]*"/ ||
        line ~ /"status"[[:space:]]*:[[:space:]]*"[^"]*(block|filter)[^"]*"/) {
      blocked++
    }
  }
}
END {
  if (queries == 0) {
    print "FXDNSLOG_EMPTY"
    exit
  }
  print "FXYULONGDNSSTATS1"
  print "queries=" queries
  print "blocked=" blocked
  print "unblocked=" queries-blocked
}
' "$LOG_FILE"
