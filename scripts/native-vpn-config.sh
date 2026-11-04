#!/system/bin/sh
# Native editor for the canonical [conf:vpn] section.
set -eu
MP=${MP:-}
if [ -z "$MP" ]; then
  for d in /data/adb/modules/privacyguard /data/adb/modules_update/privacyguard /data/adb/modules/privacy_guard /data/adb/modules/pg; do
    if [ -s "$d/module.prop" ] && grep -q '^id=privacyguard$' "$d/module.prop" 2>/dev/null; then MP="$d"; break; fi
  done
fi
[ -n "$MP" ] && [ -s "$MP/module.prop" ] || { echo "FX module is not installed" >&2; exit 20; }
PG=${PG:-/data/adb/privacyguard}
CONF=${CONF:-$PG/settings.conf}
LOCK=${LOCK:-$PG/native-vpn-config.lock}

_nvc_validate_parent_chain() {
  _nvc_candidate=$1
  case "$_nvc_candidate" in /*) : ;; *) return 1 ;; esac
  case "$_nvc_candidate" in /|*/|*//* ) return 1 ;; esac
  _nvc_final=${_nvc_candidate##*/}
  case "$_nvc_final" in ''|.|..) return 1 ;; esac
  _nvc_parent=${_nvc_candidate%/*}
  [ -n "$_nvc_parent" ] || _nvc_parent=/
  _nvc_rest=${_nvc_parent#/}
  _nvc_walk=
  while [ -n "$_nvc_rest" ]; do
    case "$_nvc_rest" in
      */*) _nvc_component=${_nvc_rest%%/*}; _nvc_rest=${_nvc_rest#*/} ;;
      *) _nvc_component=$_nvc_rest; _nvc_rest= ;;
    esac
    case "$_nvc_component" in ''|.|..) return 1 ;; esac
    _nvc_walk="$_nvc_walk/$_nvc_component"
    [ -d "$_nvc_walk" ] && [ ! -L "$_nvc_walk" ] || return 1
  done
  return 0
}
_nvc_validate_parent_chain "$PG" || { echo "FX VPN config state parent is unsafe" >&2; exit 21; }
[ -d "$PG" ] && [ ! -L "$PG" ] || exit 21
[ "$CONF" = "$PG/settings.conf" ] || { echo "FX VPN settings path is outside PG" >&2; exit 21; }
[ "$LOCK" = "$PG/native-vpn-config.lock" ] || { echo "FX VPN lock path is outside PG" >&2; exit 22; }
[ -f "$CONF" ] && [ ! -L "$CONF" ] || { echo "FX settings.conf missing or unsafe" >&2; exit 21; }
[ ! -L "$LOCK" ] || { echo "FX VPN lock path is a symbolic link" >&2; exit 22; }
[ ! -e "$LOCK" ] || [ -d "$LOCK" ] || { echo "FX VPN lock path is not a directory" >&2; exit 22; }

valid_key() {
  case "$1" in
    local_ip|local_port|remote_dns|cn_dns|test_url|auto_update_h|chnroute_url|app_mode|core_ver|core_auto|core_bin|mixed_port|log_level|hosts_cache_min|pick_min_ms|pick_test_timeout|pick_max_nodes|hide_level|hide_mtu_clamp|hide_udp_block_all|hide_icmp_block_all|hide_dot_block) return 0 ;;
    *) return 1 ;;
  esac
}
get_value() {
  awk -F= -v key="$1" '
    $0=="[conf:vpn]" {insec=1;next}
    /^\[/ {insec=0}
    insec && $1==key {sub(/^[^=]*=/,""); value=$0}
    END {print value}
  ' "$CONF"
}
list_values() {
  awk -F= '
    $0=="[conf:vpn]" {insec=1;next}
    /^\[/ {insec=0}
    insec && NF>=2 && $1 ~ /^[a-z][a-z0-9_]*$/ {
      sub(/^[^=]*=/,"")
      printf "%s|%s\n", $1, $0
    }
  ' "$CONF"
}
is_uint() {
  case "$1" in ''|*[!0-9]*) return 1 ;; esac
  return 0
}
range() {
  is_uint "$2" || return 1
  [ "$2" -ge "$3" ] && [ "$2" -le "$4" ]
}
valid_ipv4() {
  printf '%s\n' "$1" | awk -F. '
    NF != 4 { bad=1 }
    NF == 4 {
      for (i=1; i<=4; i++) {
        if ($i !~ /^[0-9]+$/ || length($i)>3 || ($i+0)>255) bad=1
      }
    }
    END { exit bad ? 1 : 0 }
  '
}
validate_value() {
  key="$1"; value="$2"
  [ "${#value}" -le 1024 ] || return 1
  if printf '%s' "$value" | grep -q '[[:cntrl:]]'; then return 1; fi
  case "$value" in *'|'*) return 1 ;; esac
  case "$key" in
    local_ip)
      valid_ipv4 "$value" || return 1
      ;;
    local_port)
      range "$key" "$value" 1 65535 || return 1
      _mixed=$(get_value mixed_port)
      [ -z "$_mixed" ] || [ "$value" != "$_mixed" ] || return 1
      ;;
    mixed_port)
      [ -z "$value" ] || range "$key" "$value" 1 65535 || return 1
      _local=$(get_value local_port)
      [ -z "$value" ] || [ "$value" != "$_local" ] || return 1
      ;;
    remote_dns|cn_dns)
      case "$value" in ''|*[!A-Za-z0-9_.:-]*) return 1 ;; esac
      ;;
    test_url|chnroute_url)
      case "$value" in http://*|https://*) : ;; *) return 1 ;; esac
      ;;
    auto_update_h)
      range "$key" "$value" 1 720 || return 1
      ;;
    app_mode)
      case "$value" in only|bypass) : ;; *) return 1 ;; esac
      ;;
    core_ver)
      printf '%s\n' "$value" | grep -Eq '^(latest|[0-9]+([.][0-9]+){2})$' || return 1
      ;;
    core_auto|hide_mtu_clamp|hide_udp_block_all|hide_icmp_block_all|hide_dot_block)
      case "$value" in 0|1) : ;; *) return 1 ;; esac
      ;;
    core_bin)
      [ -z "$value" ] || case "$value" in
        /*) case "$value" in *[!A-Za-z0-9_./-]*) return 1 ;; esac ;;
        *) return 1 ;;
      esac
      ;;
    log_level)
      case "$value" in trace|debug|info|warn|error|fatal|panic) : ;; *) return 1 ;; esac
      ;;
    hosts_cache_min)
      range "$key" "$value" 0 10080 || return 1
      ;;
    pick_min_ms)
      range "$key" "$value" 1 2000 || return 1
      ;;
    pick_test_timeout)
      range "$key" "$value" 1 60 || return 1
      ;;
    pick_max_nodes)
      range "$key" "$value" 1 200 || return 1
      ;;
    hide_level)
      range "$key" "$value" 0 2 || return 1
      ;;
    *)
      return 1
      ;;
  esac
}

write_value() {
  key="$1"; value="$2"; tmp=$(mktemp "$CONF.native-vpn.XXXXXX") || return 1
  awk -v key="$key" -v value="$value" '
    BEGIN {insec=0; seen=0; written=0}
    $0=="[conf:vpn]" {
      if(insec && !written){print key "=" value; written=1}
      insec=1;seen=1;print;next
    }
    /^\[/ {
      if(insec && !written){print key "=" value; written=1}
      insec=0;print;next
    }
    insec && index($0,key "=")==1 {
      if(!written) print key "=" value
      written=1;next
    }
    {print}
    END {
      if(insec && !written) print key "=" value
      if(!seen) {print "";print "[conf:vpn]";print key "=" value}
    }
  ' "$CONF" > "$tmp" || { rm -f "$tmp"; return 1; }
  [ -s "$tmp" ] || { rm -f "$tmp"; return 1; }
  chmod 600 "$tmp" && mv -f "$tmp" "$CONF"
}
with_lock() {
  tries=0
  while ! mkdir "$LOCK" 2>/dev/null; do
    tries=$((tries+1))
    [ "$tries" -lt 20 ] || { echo "VPN settings are busy" >&2; return 10; }
    sleep 1
  done
  cleanup_lock() {
    rmdir "$LOCK" 2>/dev/null || :
  }
  # Signal handlers must exit into EXIT cleanup; never unlock and then resume
  # a config/firewall mutation without owning the transaction lock.
  trap cleanup_lock EXIT
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM
  "$@"
}
mutate() {
  key="$1"; value="$2"
  validate_value "$key" "$value" || { echo "invalid value for $key" >&2; return 2; }
  backup=$(mktemp "$CONF.native-vpn-rollback.XXXXXX") || return 1
  cp -p "$CONF" "$backup" || { rm -f "$backup"; return 1; }
  write_value "$key" "$value" || { rm -f "$backup"; return 1; }
  if sh "$MP/scripts/apply.sh" fast; then
    rm -f "$backup"
    echo "applied=1"
    return 0
  fi
  restore=$(mktemp "$CONF.restore.XXXXXX") || {
    rm -f "$backup"; echo "VPN config rollback staging failed" >&2; return 11;
  }
  cp -p "$backup" "$restore" && chmod 600 "$restore" \
    && mv -f "$restore" "$CONF" || {
    rm -f "$restore"
      rm -f "$backup"; echo "VPN config rollback failed" >&2; return 11;
    }
  sh "$MP/scripts/apply.sh" fast >/dev/null 2>&1 || echo "previous VPN config restored; runtime reconcile failed" >&2
  rm -f "$backup"
  echo "apply failed; previous VPN config restored" >&2
  return 1
}
cmd=${1:-list}
case "$cmd" in
  list)
    echo FXVPNCONF1
    list_values
    ;;
  get)
    [ "$#" -eq 2 ] && valid_key "$2" || { echo "usage: $0 get KEY" >&2; exit 2; }
    get_value "$2"
    ;;
  set)
    [ "$#" -eq 3 ] && valid_key "$2" || { echo "usage: $0 set KEY VALUE" >&2; exit 2; }
    with_lock mutate "$2" "$3"
    ;;
  *)
    echo "usage: $0 list|get KEY|set KEY VALUE" >&2
    exit 2
    ;;
esac
