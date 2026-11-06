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
_dns_log_found=0
# Build the exact input list while validating every matching path. POSIX sh
# has no arrays, so positional parameters carry the file list to awk. This
# avoids passing a literal querylog.json.* when no rotated files exist.
set --
for LOG_FILE in "$DATA_DIR"/querylog.json "$DATA_DIR"/querylog.json.*; do
  [ -e "$LOG_FILE" ] || [ -L "$LOG_FILE" ] || continue
  [ ! -L "$LOG_FILE" ] || { echo "DNS query log symlink rejected: $LOG_FILE" >&2; exit 21; }
  [ -f "$LOG_FILE" ] || { echo "DNS query log is not a regular file: $LOG_FILE" >&2; exit 21; }
  set -- "$@" "$LOG_FILE"
  [ -s "$LOG_FILE" ] && _dns_log_found=1
done
[ "$_dns_log_found" = 1 ] || { echo FXDNSLOG_EMPTY; exit 0; }

awk '
function read_json_string(pos,    j,c,esc,hex) {
  str_value=""; str_valid=0; j=pos+1
  while (j <= length(current_line)) {
    c=substr(current_line,j,1)
    if (c == "\\") {
      j++
      if (j > length(current_line)) { str_end=length(current_line); return }
      esc=substr(current_line,j,1)
      if (esc=="u") {
        hex=substr(current_line,j+1,4)
        if (length(hex)!=4 || hex !~ /^[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]$/) {
          str_end=j; return
        }
        j+=5
        str_value=str_value "?"
        continue
      }
      if (esc !~ /^["\\\/bfnrt]$/) { str_end=j; return }
      if (esc=="b" || esc=="f" || esc=="n" || esc=="r" || esc=="t")
        str_value=str_value " "
      else
        str_value=str_value esc
      j++
      continue
    }
    if (c == "\"") { str_end=j; str_valid=1; return }
    if (c ~ /[[:cntrl:]]/) { str_end=j; return }
    str_value=str_value c; j++
  }
  str_end=length(current_line)
}
function scan_record(line,    i,n,c,j,k,key,value,stack,valid,first,last,nextc,expected) {
  current_line=line; n=length(line); first=1; last=n
  while (first<=n && substr(line,first,1) ~ /[[:space:]]/) first++
  while (last>=first && substr(line,last,1) ~ /[[:space:]]/) last--
  # Every non-empty JSONL row in AdGuard Home's query log must be an
  # object. Treat arrays, scalars and truncated wrappers as malformed rather
  # than silently classifying them as harmless non-query records.
  if (first>last || substr(line,first,1)!="{" || substr(line,last,1)!="}") return -1
  query=0; filtered=0; stack=""; valid=1
  for (i=first; i<=last; i++) {
    c=substr(line,i,1)
    if (c=="\"") {
      read_json_string(i)
      if (!str_valid) { valid=0; break }
      key=tolower(str_value); j=str_end; k=j+1
      while (k<=last && substr(line,k,1) ~ /[[:space:]]/) k++
      if (substr(line,k,1)==":") {
        k++
        while (k<=last && substr(line,k,1) ~ /[[:space:]]/) k++
        if (key=="qh" || key=="question") query=1
        if (key=="isfiltered") {
          if (tolower(substr(line,k,4))=="true") {
            nextc=substr(line,k+4,1)
            if (nextc !~ /[A-Za-z0-9_]/) filtered=1
          }
        } else if (key=="reason" || key=="status") {
          if (substr(line,k,1)=="\"") {
            read_json_string(k)
            if (!str_valid) { valid=0; break }
            value=tolower(str_value)
            if ((key=="reason" && value ~ /^filtered/) ||
                (key=="status" && value ~ /(block|filter)/)) filtered=1
          }
        }
      }
      i=j
    } else if (c=="{" || c=="[") {
      stack=stack c
    } else if (c=="}" || c=="]") {
      expected=(c=="}" ? "{" : "[")
      if (substr(stack,length(stack),1)!=expected) valid=0
      else stack=substr(stack,1,length(stack)-1)
    }
  }
  if (stack!="") valid=0
  return valid ? (query ? 1 : 0) : -1
}
BEGIN { queries=0; blocked=0; malformed=0 }
{
  if ($0 ~ /^[[:space:]]*$/) next
  record_status=scan_record($0)
  if (record_status < 0) {
    malformed=1
    next
  }
  if (record_status > 0) {
    queries++
    if (filtered) blocked++
  }
}
END {
  # Never publish plausible-looking partial aggregates when the log contains
  # a truncated or structurally malformed JSONL record.
  if (malformed) {
    print "DNS query log contains a malformed or truncated record" > "/dev/stderr"
    exit 21
  }
  if (queries == 0) {
    print "FXDNSLOG_EMPTY"
    exit
  }
  print "FXYULONGDNSSTATS1"
  print "queries=" queries
  print "blocked=" blocked
  print "unblocked=" queries-blocked
}' "$@"
