#!/system/bin/sh
# Native FX DNS engine settings adapter.
# Exposes only the DNS switches used by the integrated AdGuard Home/Unbound
# and external-VPN Root Proxy pipelines; never accepts arbitrary config keys.
set -eu
umask 077

MP=${MP:-}
if [ -z "$MP" ]; then
  for d in /data/adb/modules/privacyguard /data/adb/modules_update/privacyguard /data/adb/modules/privacy_guard /data/adb/modules/pg; do
    if [ -s "$d/module.prop" ] && grep -q '^id=privacyguard$' "$d/module.prop" 2>/dev/null; then MP=$d; break; fi
  done
fi
[ -n "$MP" ] && [ -s "$MP/module.prop" ] && [ -s "$MP/scripts/util.sh" ] || {
  echo "FX module is not installed" >&2; exit 20;
}
PG=${PG:-/data/adb/privacyguard}
CONF="$PG/settings.conf"
LOCK="$PG/native-dns-settings.lock"
DEFAULTS="$MP/scripts/default.conf"
export MP PG CONF
. "$MP/scripts/util.sh"

valid_key() {
  case "$1" in
    dns_engine_adguardhome|dns_forward|vpn_external_compat|vpn_external_dns_proxy) return 0 ;;
    *) return 1 ;;
  esac
}
path_is_safe() {
  _path=$1
  case "$_path" in /*) : ;; *) return 1 ;; esac
  case "$_path" in *//*|*/../*|*/..|*/./*|*/.) return 1 ;; esac
  _rest=${_path#/}
  _walk=
  while [ -n "$_rest" ]; do
    case "$_rest" in
      */*) _part=${_rest%%/*}; _rest=${_rest#*/} ;;
      *) _part=$_rest; _rest= ;;
    esac
    case "$_part" in ''|.|..) return 1 ;; esac
    _walk="$_walk/$_part"
    [ ! -L "$_walk" ] || return 1
  done
  return 0
}
path_is_safe "$PG" || { echo "unsafe FX DNS state path" >&2; exit 21; }
[ -d "$PG" ] && [ ! -L "$PG" ] || { echo "FX DNS state directory is missing or unsafe" >&2; exit 21; }
[ -f "$CONF" ] && [ ! -L "$CONF" ] && [ -r "$CONF" ] || { echo "FX settings.conf is missing or unsafe" >&2; exit 21; }
[ -f "$DEFAULTS" ] && [ ! -L "$DEFAULTS" ] && [ -r "$DEFAULTS" ] || { echo "FX default settings are missing or unsafe" >&2; exit 21; }
[ "$CONF" = "$PG/settings.conf" ] && [ "$LOCK" = "$PG/native-dns-settings.lock" ] || exit 22
[ ! -L "$LOCK" ] || { echo "FX DNS settings lock is a symbolic link" >&2; exit 22; }
[ ! -e "$LOCK" ] || [ -d "$LOCK" ] || { echo "FX DNS settings lock is not a directory" >&2; exit 22; }

declared_flag() {
  awk -v key="$1" '
    BEGIN {FS="="; count=0; valid=0}
    /^\[/ {in_sections=1}
    !in_sections && $1==key {
      count++
      if (NF==2 && $2 ~ /^[01]$/) valid=1
      else valid=0
    }
    END {exit !(count==1 && valid==1)}
  ' "$DEFAULTS"
}
write_flags_many() {
  [ "$#" -ge 2 ] && [ "$(($# % 2))" -eq 0 ] || return 2
  _flags_args=
  _flags_seen='|'
  while [ "$#" -gt 0 ]; do
    _fk=$1; _fv=$2; shift 2
    valid_key "$_fk" || return 2
    case "$_fv" in 0|1) : ;; *) return 2 ;; esac
    declared_flag "$_fk" || return 2
    case "$_flags_seen" in *"|$_fk|"*) return 2 ;; esac
    _flags_seen="${_flags_seen}${_fk}|"
    _flags_args="${_flags_args}${_flags_args:+ }${_fk}=${_fv}"
  done
  _flags_tmp=$(umask 077; mktemp "$CONF.native-dns-batch.XXXXXX") || return 1
  if ! awk -v updates="$_flags_args" '
    BEGIN {
      n=split(updates,p," "); section=0; bad=0
      for(i=1;i<=n;i++){split(p[i],kv,"="); wanted[kv[1]]=kv[2]; count[kv[1]]=0}
    }
    /^\[/ {section=1}
    !section {
      eq=index($0,"=")
      if(eq>1){
        key=substr($0,1,eq-1)
        if(key in wanted){
          count[key]++
          if(substr($0,eq+1)!~/^[01]$/ || count[key]>1) bad=1
          print key "=" wanted[key]
          next
        }
      }
    }
    {print}
    END {
      for(key in wanted) if(count[key]!=1) bad=1
      if(bad) exit 1
    }
  ' "$CONF" > "$_flags_tmp"; then
    rm -f "$_flags_tmp"; return 1
  fi
  if [ -s "$_flags_tmp" ] && chmod 600 "$_flags_tmp" && mv -f "$_flags_tmp" "$CONF"; then
    return 0
  fi
  rm -f "$_flags_tmp"
  return 1
}
read_flag() {
  _key=$1
  _value=$(pg_get "$_key" 0 2>/dev/null || printf 0)
  case "$_value" in 0|1) printf '%s' "$_value" ;; *) printf 'unknown' ;; esac
}
service_status() {
  _script=$1
  _status=unavailable
  if [ -f "$MP/scripts/$_script.sh" ] && [ ! -L "$MP/scripts/$_script.sh" ]; then
    _status=$(sh "$MP/scripts/$_script.sh" status "$MP" "$PG" 2>/dev/null) || :
  fi
  case "$_status" in ready|running-unhealthy|stopped) printf '%s' "$_status" ;; *) printf 'unavailable' ;; esac
}

dns_section_count() {
  _section=$1
  awk -v target="$_section" '
    function valid_ipv4(v,n,a,i,first,second) {
      if(v !~ /^[0-9.]+$/) return 0
      n=split(v,a,".")
      if(n!=4) return 0
      for(i=1;i<=4;i++)
        if(a[i]!~/^[0-9]+$/ || length(a[i])>3 || a[i]+0>255 ||
           (a[i]!="0" && a[i]~/^0/)) return 0
      first=a[1]+0; second=a[2]+0
      if(v=="0.0.0.0" || v=="255.255.255.255" || first==0 ||
         first==127 || first>=224 || (first==169 && second==254)) return 0
      return 1
    }
    function valid_ipv4_port(v,n,a) {
      n=split(v,a,":")
      return n==2 && valid_ipv4(a[1]) && a[2]~/^[0-9]+$/ &&
        a[2]+0>=1 && a[2]+0<=65535
    }
    function dns_host(v,n,a,i) {
      if(v~/^[0-9.]+$/) return valid_ipv4(v)
      if(length(v)>253 || substr(v,1,1)=="." || substr(v,length(v),1)==".") return 0
      n=split(v,a,".")
      for(i=1;i<=n;i++)
        if(length(a[i])<1 || length(a[i])>63 ||
           a[i]!~/^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?$/) return 0
      return 1
    }
    function valid_hostport(v,n,a) {
      n=split(v,a,":")
      if(n==1) return dns_host(a[1])
      return n==2 && dns_host(a[1]) && a[2]~/^[0-9]+$/ &&
        a[2]+0>=1 && a[2]+0<=65535
    }
    function valid_endpoint(v,rest,parts,authority) {
      if(valid_ipv4(v) || valid_ipv4_port(v)) return 1
      if(substr(v,1,8)=="https://") {
        rest=substr(v,9); split(rest,parts,"/"); authority=parts[1]
        if(!valid_hostport(authority)) return 0
        return rest~/^[A-Za-z0-9.-]+(:[0-9]+)?(\\/[A-Za-z0-9._~!dns_section_count() {
  _section=$1
  awk -v target="$_section" '
    BEGIN {inside=0; sections=0; count=0; bad=0}
    $0=="[conf:" target "]" {sections++; inside=1; next}
    /^\[/ {inside=0}
    inside && /^[[:space:]]*#/ {next}
    inside && /^[[:space:]]*$/ {next}
    inside {
      if(NF!=2 || $1!="nameserver" || $2 ~ /[[:space:]]/) bad=1
      else count++
    }
    END {
      if(sections>1 || bad) exit 1
      print count+0
    }
  ' "$CONF"
}()*+,;=:@%/?#-]*)?$/
      }
      if(substr(v,1,6)=="tls://") return valid_hostport(substr(v,7))
      if(substr(v,1,7)=="quic://") return valid_hostport(substr(v,8))
      return 0
    }
    BEGIN {inside=0; sections=0; count=0; bad=0}
    $0=="[conf:" target "]" {sections++; if(sections>1) bad=1; inside=1; next}
    /^\\[/ {inside=0}
    inside && /^[[:space:]]*#/ {next}
    inside && /^[[:space:]]*$/ {next}
    inside {
      if(NF!=2 || $1!="nameserver") {bad=1; next}
      server=$2
      if(target=="custom_dns") {
        if(!valid_endpoint(server)) {bad=1; next}
      } else if(!valid_ipv4(server) && !valid_ipv4_port(server)) {
        bad=1; next
      }
      normalized=tolower(server)
      if(seen[normalized]++) {bad=1; next}
      count++
    }
    END {
      if(sections>1 || bad) exit 1
      print count+0
    }
  ' "$CONF"
}
dns_encrypted_upstream_count() {
  _section=${1:-custom_dns}
  awk -v target="$_section" '
    $0=="[conf:" target "]" {inside=1; next}
    /^\[/ {inside=0}
    inside && /^[[:space:]]*nameserver[[:space:]]+/ &&
      $2 ~ /^(https:\/\/|tls:\/\/|quic:\/\/)/ {count++}
    END {print count+0}
  ' "$CONF"
}
status() {
  _agh=$(service_status adguardhome)
  _unbound=$(service_status unbound)
  _root=unavailable
  _whitelist_count=unknown
  _root_reason=unknown
  _root_cleanup=not_required
  _private_dns_mode=unknown
  _dns_filter_coverage=unknown
  _coexistence_verdict=unknown
  _coexistence_route_probe=unavailable
  _filter_total=unknown
  _filter_enabled=unknown
  _root_interface=unknown
  _root_vpn_uid=unknown
  _root_egress_ipv4=unknown
  _root_activated_at=unknown
  _root_redirects=unknown
  _root_dns_probe=unavailable
  _root_route=unknown
  if [ -f "$CONF" ] && [ ! -L "$CONF" ] && [ -r "$CONF" ]; then
    _rule_rows=
    if [ -f "$MP/scripts/native-managed-lists.sh" ] && [ ! -L "$MP/scripts/native-managed-lists.sh" ]; then
      _rule_rows=$(MP="$MP" PG="$PG" sh "$MP/scripts/native-managed-lists.sh" list ruleList 2>/dev/null) || _rule_rows=
    fi
    if [ -n "$_rule_rows" ]; then
      _filter_counts=$(printf '%s\n' "$_rule_rows" | awk -F'|' '
        NR==1 {if($0!="FXLIST1") exit 2; next}
        NF!=4 || $1 !~ /^[0-9]+$/ || $4 !~ /^[01]$/ {exit 2}
        {total++; if($4=="1") enabled++}
        END {if(NR<1) exit 2; printf "%d|%d\n", total+0, enabled+0}
      ') || _filter_counts=
      case "$_filter_counts" in
        ''|*[!0-9|]*) _filter_total=unknown; _filter_enabled=unknown ;;
        *'|'*) _filter_total=${_filter_counts%%|*}; _filter_enabled=${_filter_counts#*|} ;;
        *) _filter_total=unknown; _filter_enabled=unknown ;;
      esac
    else
      _filter_total=unknown
      _filter_enabled=unknown
    fi
  fi
  if [ -f "$MP/scripts/yulong-root-proxy.sh" ] && [ ! -L "$MP/scripts/yulong-root-proxy.sh" ]; then
    if _root_output=$(MP="$MP" PG="$PG" sh "$MP/scripts/yulong-root-proxy.sh" status 2>/dev/null); then :; else _root_status_rc=$?; fi
    if [ -n "$_root_output" ]; then
      if printf '%s\n' "$_root_output" | grep -Fqx 'active=1'; then _root=active
      elif printf '%s\n' "$_root_output" | grep -Fqx 'active=0'; then _root=inactive
      fi
      _count=$(printf '%s\n' "$_root_output" | sed -n 's/^whitelist_count=//p' | head -1)
      case "$_count" in ''|*[!0-9]*) : ;; *) _whitelist_count=$_count ;; esac
      _reason=$(printf '%s\n' "$_root_output" | sed -n 's/^reason=//p' | head -1)
      case "$_reason" in ''|*[!A-Za-z0-9_.:-]*) : ;; *) _root_reason=$_reason ;; esac
      _cleanup=$(printf '%s\n' "$_root_output" | sed -n 's/^cleanup=//p' | head -1)
      case "$_cleanup" in complete|failed) _root_cleanup=$_cleanup ;; esac

      # Preserve the live route proof in the public status response. The
      # Root Proxy status command only emits these values after all route,
      # redirect and local DNS probes have succeeded.
      _iface=$(printf '%s\n' "$_root_output" | sed -n 's/^interface=//p' | head -1)
      case "$_iface" in ''|*[!A-Za-z0-9_.:-]*) : ;; *) _root_interface=$_iface ;; esac
      _uid=$(printf '%s\n' "$_root_output" | sed -n 's/^vpn_uid=//p' | head -1)
      case "$_uid" in ''|*[!0-9]*) : ;; *) _root_vpn_uid=$_uid ;; esac
      _egress=$(printf '%s\n' "$_root_output" | sed -n 's/^egress_ipv4=//p' | head -1)
      case "$_egress" in ''|*[!0-9.]*) : ;; *) _root_egress_ipv4=$_egress ;; esac
      _activated=$(printf '%s\n' "$_root_output" | sed -n 's/^activated_at=//p' | head -1)
      case "$_activated" in ''|*[!0-9]*) : ;; *) _root_activated_at=$_activated ;; esac
      _redirects=$(printf '%s\n' "$_root_output" | sed -n 's/^redirects=//p' | head -1)
      case "$_redirects" in attached|detached) _root_redirects=$_redirects ;; esac
      _probe=$(printf '%s\n' "$_root_output" | sed -n 's/^dns_probe=//p' | head -1)
      case "$_probe" in passed|failed|unavailable) _root_dns_probe=$_probe ;; esac
      _route=$(printf '%s\n' "$_root_output" | sed -n 's/^route=//p' | head -1)
      case "$_route" in verified|unavailable|not_applicable) _root_route=$_route ;; esac

      _mode=$(printf '%s\n' "$_root_output" | sed -n 's/^private_dns_mode=//p' | head -1)
      case "$_mode" in off|opportunistic|hostname) _private_dns_mode=$_mode ;; esac
      _coverage=$(printf '%s\n' "$_root_output" | sed -n 's/^dns_filter_coverage=//p' | head -1)
      case "$_coverage" in port53_redirect_active|opportunistic_private_dns_may_bypass_redirect|strict_private_dns_bypasses_redirect|unknown) _dns_filter_coverage=$_coverage ;; esac
    fi
  fi
  if [ -f "$MP/scripts/fx-vpn-coexistence-arbiter.sh" ] && [ ! -L "$MP/scripts/fx-vpn-coexistence-arbiter.sh" ]; then
    _coexistence=$(MP="$MP" PG="$PG" sh "$MP/scripts/fx-vpn-coexistence-arbiter.sh" 2>/dev/null || :)
    _verdict=$(printf '%s\n' "$_coexistence" | sed -n 's/.*"verdict":"\([^"]*\)".*/\1/p' | head -1)
    case "$_verdict" in compatible|incompatible|unknown) _coexistence_verdict=$_verdict ;; esac
    _route_probe=$(printf '%s\n' "$_coexistence" | sed -n 's/.*"route_probe":"\([^"]*\)".*/\1/p' | head -1)
    case "$_route_probe" in passed|failed|unavailable|not_applicable) _coexistence_route_probe=$_route_probe ;; esac
  fi
  _agh_enabled=$(read_flag dns_engine_adguardhome)
  _unbound_enabled=$(read_flag dns_forward)
  _custom_dns_enabled=$(read_flag custom_dns)
  _global_dns_enabled=$(read_flag global_dns)
  _dns_custom_count=$(dns_section_count custom_dns 2>/dev/null) || _dns_custom_count=unknown
  _dns_global_count=$(dns_section_count global_dns 2>/dev/null) || _dns_global_count=unknown
  _dns_fallback_count=$(dns_section_count yulong_dns_fallback 2>/dev/null) || _dns_fallback_count=unknown
  _dns_upstream_mode=local_recursive
  if [ "$_global_dns_enabled" = 1 ]; then _dns_upstream_mode=global
  elif [ "$_custom_dns_enabled" = 1 ]; then _dns_upstream_mode=custom
  elif [ "$_global_dns_enabled" = unknown ] || [ "$_custom_dns_enabled" = unknown ]; then _dns_upstream_mode=unknown
  fi
  # Only inspect the list that the active policy actually selects. An invalid
  # dormant custom list must not make a valid global-DNS runtime look broken,
  # and an unused encrypted endpoint must not be reported as a bootstrap dependency.
  case "$_dns_upstream_mode" in
    custom) _dns_encrypted_count=$(dns_encrypted_upstream_count custom_dns 2>/dev/null) || _dns_encrypted_count=unknown ;;
    *) _dns_encrypted_count=0 ;;
  esac
  _dns_upstream_state=ready
  case "$_dns_upstream_mode" in
    unknown) _dns_upstream_state=unknown ;;
    custom)
      case "$_dns_custom_count" in
        unknown) _dns_upstream_state=unknown ;;
        0) _dns_upstream_state=missing_primary ;;
        *[!0-9]*|'') _dns_upstream_state=unknown ;;
      esac
      ;;
    global)
      case "$_dns_global_count" in
        unknown) _dns_upstream_state=unknown ;;
        0) _dns_upstream_state=missing_primary ;;
        *[!0-9]*|'') _dns_upstream_state=unknown ;;
      esac
      ;;
  esac
  case "$_dns_encrypted_count" in
    ''|*[!0-9]*) _dns_bootstrap_mode=unknown ;;
    0) _dns_bootstrap_mode=not_required ;;
    *) _dns_bootstrap_mode=local_unbound ;;
  esac
  case "$_dns_fallback_count" in
    ''|*[!0-9]*) _dns_fallback_mode=unknown ;;
    0)
      case "$_dns_upstream_mode" in custom|global) _dns_fallback_mode=local_unbound ;; *) _dns_fallback_mode=none ;; esac
      ;;
    *) _dns_fallback_mode=explicit ;;
  esac
  _local_dns_watchdog=unavailable
  if [ -L "$PG/localdns-watchdog.pid" ] || [ -L "$MP/scripts/localdns-watchdog.sh" ]; then
    _local_dns_watchdog=unsafe
  elif [ -f "$MP/scripts/localdns-watchdog.sh" ]; then
    _watchdog_status=$(sh "$MP/scripts/localdns-watchdog.sh" status "$MP" "$PG" 2>/dev/null || :)
    case "$_watchdog_status" in
      running\ pid=*) _local_dns_watchdog=running ;;
      stopped|stopped\ *|stopped\ stale-pid=*) _local_dns_watchdog=stopped ;;
      invalid) _local_dns_watchdog=invalid ;;
      unsafe) _local_dns_watchdog=unsafe ;;
      identity_unknown\ *) _local_dns_watchdog=identity_unknown ;;
      *) _local_dns_watchdog=unknown ;;
    esac
  elif [ -e "$MP/scripts/localdns-watchdog.sh" ] || [ -e "$PG/localdns-watchdog.pid" ]; then
    _local_dns_watchdog=unknown
  fi
  _configured=0
  _ready=0
  _readiness_reason=disabled
  if [ "$_agh_enabled" = unknown ] || [ "$_unbound_enabled" = unknown ]; then
    # An unreadable/duplicated engine flag is not equivalent to disabled.
    # Surface the stack as configured-but-not-ready instead of silently
    # reporting a healthy disabled state.
    _configured=1
    _readiness_reason=dns_engine_flag_unknown
  elif [ "$_agh_enabled" = 1 ] || [ "$_unbound_enabled" = 1 ]; then
    _configured=1
    _ready=1
    if [ "$_unbound_enabled" = 1 ] && [ "$_unbound" != ready ]; then
      _ready=0
      _readiness_reason="unbound_$_unbound"
    fi
    if [ "$_agh_enabled" = 1 ]; then
      if [ "$_unbound_enabled" != 1 ]; then
        _ready=0
        _readiness_reason=unbound_disabled
      elif [ "$_agh" != ready ]; then
        _ready=0
        _readiness_reason="adguardhome_$_agh"
      fi
      # An engine process being alive is insufficient when its selected
      # upstream configuration is incomplete or could not be interpreted.
      if [ "$_ready" = 1 ]; then
        case "$_dns_upstream_state" in
          missing_primary)
            _ready=0
            _readiness_reason=dns_upstream_missing_primary
            ;;
          unknown)
            _ready=0
            _readiness_reason=dns_upstream_config_unknown
            ;;
        esac
      fi
      if [ "$_ready" = 1 ] && [ "$_dns_fallback_mode" = unknown ]; then
        _ready=0
        _readiness_reason=dns_fallback_config_unknown
      fi
      # Encrypted upstream bootstrap and implicit local fallback both depend
      # on the same healthy local recursive listener. Never mark this stack
      # ready if the setting flags say that listener is unavailable.
      if [ "$_ready" = 1 ] &&
         { [ "$_dns_bootstrap_mode" = local_unbound ] ||
           [ "$_dns_fallback_mode" = local_unbound ]; } &&
         { [ "$_unbound_enabled" != 1 ] || [ "$_unbound" != ready ]; }; then
        _ready=0
        _readiness_reason=dns_local_recursive_dependency_unready
      fi
    fi
    [ "$_ready" = 1 ] && _readiness_reason=ready
  fi
  echo FXDNS1
  printf 'dns_engine_adguardhome|%s\n' "$(read_flag dns_engine_adguardhome)"
  printf 'dns_forward|%s\n' "$(read_flag dns_forward)"
  printf 'vpn_external_compat|%s\n' "$(read_flag vpn_external_compat)"
  printf 'vpn_external_dns_proxy|%s\n' "$(read_flag vpn_external_dns_proxy)"
  printf 'adguardhome|%s\n' "$_agh"
  printf 'unbound|%s\n' "$_unbound"
  printf 'root_proxy|%s\n' "$_root"
  printf 'rootproxy_reason|%s\n' "$_root_reason"
  printf 'rootproxy_cleanup|%s\n' "$_root_cleanup"
  printf 'rootproxy_interface|%s\n' "$_root_interface"
  printf 'rootproxy_vpn_uid|%s\n' "$_root_vpn_uid"
  printf 'rootproxy_egress_ipv4|%s\n' "$_root_egress_ipv4"
  printf 'rootproxy_activated_at|%s\n' "$_root_activated_at"
  printf 'rootproxy_redirects|%s\n' "$_root_redirects"
  printf 'rootproxy_dns_probe|%s\n' "$_root_dns_probe"
  printf 'rootproxy_route|%s\n' "$_root_route"
  printf 'rootproxy_whitelist_count|%s\n' "$_whitelist_count"
  printf 'dns_filter_sources_total|%s\n' "$_filter_total"
  printf 'dns_filter_sources_enabled|%s\n' "$_filter_enabled"
  printf 'private_dns_mode|%s\n' "$_private_dns_mode"
  printf 'dns_filter_coverage|%s\n' "$_dns_filter_coverage"
  printf 'vpn_coexistence_verdict|%s\n' "$_coexistence_verdict"
  printf 'vpn_route_probe|%s\n' "$_coexistence_route_probe"
  printf 'dns_stack_enabled|%s\n' "$_configured"
  printf 'dns_stack_ready|%s\n' "$_ready"
  printf 'dns_stack_readiness_reason|%s\n' "$_readiness_reason"
  printf 'dns_upstream_mode|%s\n' "$_dns_upstream_mode"
  printf 'dns_upstream_state|%s\n' "$_dns_upstream_state"
  printf 'dns_custom_upstreams|%s\n' "$_dns_custom_count"
  printf 'dns_global_upstreams|%s\n' "$_dns_global_count"
  printf 'dns_fallback_upstreams|%s\n' "$_dns_fallback_count"
  printf 'dns_fallback_mode|%s\n' "$_dns_fallback_mode"
  printf 'dns_encrypted_upstreams|%s\n' "$_dns_encrypted_count"
  printf 'dns_bootstrap_mode|%s\n' "$_dns_bootstrap_mode"
  printf 'localdns_watchdog|%s\n' "$_local_dns_watchdog"
  printf 'custom_dns|%s\n' "$(read_flag custom_dns)"
  printf 'global_dns|%s\n' "$(read_flag global_dns)"
  printf 'block_quic|%s\n' "$(read_flag block_quic)"
  printf 'block_dot|%s\n' "$(read_flag block_dot)"
  printf 'block_plain_dns|%s\n' "$(read_flag block_plain_dns)"
  printf 'block_ipv6|%s\n' "$(read_flag block_ipv6)"
  printf 'block_track_domains|%s\n' "$(read_flag block_track_domains)"
  printf 'dns_querylog_enabled|%s\n' "$(read_flag dns_querylog_enabled)"
}
mutate() {
  _key=$1
  _value=$2
  valid_key "$_key" || { echo "DNS setting is not allowlisted" >&2; return 2; }
  case "$_value" in 0|1) : ;; *) echo "DNS setting value must be 0 or 1" >&2; return 2 ;; esac
  declared_flag "$_key" || { echo "DNS setting is not declared by FX defaults" >&2; return 2; }
  _backup=$(umask 077; mktemp "$CONF.native-dns-rollback.XXXXXX") || return 1
  cp -p "$CONF" "$_backup" || { rm -f "$_backup"; return 1; }
  _set_rc=0
  case "$_key:$_value" in
    dns_engine_adguardhome:1)
      # Keep Unbound active for the default recursive path and encrypted
      # upstream bootstrap; an explicitly enabled custom/global list can
      # override AdGuard's primary upstream without disabling this fallback.
      write_flags_many dns_forward 1 dns_engine_adguardhome 1 || _set_rc=$?
      ;;
    dns_engine_adguardhome:0)
      # Root Proxy redirects to AdGuard on port 53. Disarm it before disabling
      # that listener; Unbound may remain enabled for independent local DNS.
      write_flags_many vpn_external_dns_proxy 0 dns_engine_adguardhome 0 || _set_rc=$?
      ;;
    dns_forward:0)
      # Do not leave an enabled filter pointing at a resolver that is disabled.
      write_flags_many dns_engine_adguardhome 0 vpn_external_dns_proxy 0 dns_forward 0 || _set_rc=$?
      ;;
    vpn_external_compat:0)
      # Root Proxy is a third-party-VPN fallback and cannot remain armed when
      # compatibility mode has been disabled.
      write_flags_many vpn_external_dns_proxy 0 vpn_external_compat 0 || _set_rc=$?
      ;;
    vpn_external_dns_proxy:1)
      # Root Proxy requires the explicit compatibility path, AdGuard's local
      # listener and its Unbound upstream in the same settings transaction.
      write_flags_many dns_forward 1 dns_engine_adguardhome 1 vpn_external_compat 1 vpn_external_dns_proxy 1 || _set_rc=$?
      ;;
    *)
      write_flags_many "$_key" "$_value" || _set_rc=$?
      ;;
  esac
  if [ "$_set_rc" -ne 0 ]; then
    _restore=$(umask 077; mktemp "$CONF.native-dns-restore.XXXXXX") || {
      echo "DNS setting mutation failed; backup retained at $_backup" >&2
      return 11
    }
    if ! cp -p "$_backup" "$_restore" || ! chmod 600 "$_restore" || ! mv -f "$_restore" "$CONF"; then
      rm -f "$_restore" 2>/dev/null || :
      echo "DNS setting mutation and rollback failed; backup retained at $_backup" >&2
      return 11
    fi
    rm -f "$_backup"
    return "$_set_rc"
  fi
  if sh "$MP/scripts/apply.sh" full; then
    rm -f "$_backup"
    printf 'saved=1 applied=1 key=%s value=%s\n' "$_key" "$_value"
    return 0
  fi
  _restore=$(umask 077; mktemp "$CONF.native-dns-restore.XXXXXX") || {
    echo "DNS setting rollback staging failed; backup retained at $_backup" >&2
    return 11
  }
  if ! cp -p "$_backup" "$_restore" || ! chmod 600 "$_restore" || ! mv -f "$_restore" "$CONF"; then
    rm -f "$_restore" 2>/dev/null || :
    echo "DNS setting rollback failed; backup retained at $_backup" >&2
    return 11
  fi
  sh "$MP/scripts/apply.sh" full >/dev/null 2>&1 || echo "previous DNS settings restored; runtime reconcile failed" >&2
  rm -f "$_backup"
  echo "DNS apply failed; previous settings restored" >&2
  return 1
}
mutate_many_common() {
  _apply_runtime=$1
  shift
  [ "$#" -ge 2 ] && [ "$#" -le 8 ] && [ $(($# % 2)) -eq 0 ] || {
    echo "usage: set-many KEY 0|1 [KEY 0|1 ...]" >&2; return 2;
  }
  _want_agh=$(read_flag dns_engine_adguardhome); _want_forward=$(read_flag dns_forward)
  _want_compat=$(read_flag vpn_external_compat); _want_proxy=$(read_flag vpn_external_dns_proxy)
  _seen='|'
  while [ "$#" -gt 0 ]; do
    _k=$1; _v=$2; shift 2
    valid_key "$_k" && declared_flag "$_k" || { echo "DNS setting is not allowlisted or declared" >&2; return 2; }
    case "$_v" in 0|1) : ;; *) echo "DNS setting value must be 0 or 1" >&2; return 2 ;; esac
    case "$_seen" in *"|$_k|"*) echo "duplicate DNS setting key" >&2; return 2 ;; esac
    _seen="${_seen}${_k}|"
    case "$_k" in
      dns_engine_adguardhome) _want_agh=$_v ;;
      dns_forward) _want_forward=$_v ;;
      vpn_external_compat) _want_compat=$_v ;;
      vpn_external_dns_proxy) _want_proxy=$_v ;;
    esac
  done
  # Normalize the requested profile against the same dependency rules as set.
  if [ "$_want_forward" != 1 ]; then _want_agh=0; _want_proxy=0; fi
  if [ "$_want_agh" != 1 ]; then _want_proxy=0; fi
  if [ "$_want_compat" != 1 ]; then _want_proxy=0; fi
  if [ "$_want_proxy" = 1 ]; then _want_forward=1; _want_agh=1; _want_compat=1; fi
  _backup=$(umask 077; mktemp "$CONF.native-dns-rollback.XXXXXX") || return 1
  cp -p "$CONF" "$_backup" || { rm -f "$_backup"; return 1; }
  _rc=0
  write_flags_many dns_engine_adguardhome "$_want_agh" dns_forward "$_want_forward" vpn_external_compat "$_want_compat" vpn_external_dns_proxy "$_want_proxy" || _rc=$?
  if [ "$_rc" -ne 0 ]; then
    _restore=$(umask 077; mktemp "$CONF.native-dns-restore.XXXXXX") || { echo "batch mutation failed; backup retained at $_backup" >&2; return 11; }
    if ! cp -p "$_backup" "$_restore" || ! chmod 600 "$_restore" || ! mv -f "$_restore" "$CONF"; then
      rm -f "$_restore" 2>/dev/null || :; echo "batch mutation rollback failed; backup retained at $_backup" >&2; return 11
    fi
    rm -f "$_backup"; return "$_rc"
  fi
  if [ "$_apply_runtime" = 0 ]; then
    rm -f "$_backup"
    printf 'saved=1 applied=deferred dns_engine_adguardhome=%s dns_forward=%s vpn_external_compat=%s vpn_external_dns_proxy=%s\n' "$_want_agh" "$_want_forward" "$_want_compat" "$_want_proxy"
    return 0
  fi
  if sh "$MP/scripts/apply.sh" full; then
    rm -f "$_backup"
    printf 'saved=1 applied=1 dns_engine_adguardhome=%s dns_forward=%s vpn_external_compat=%s vpn_external_dns_proxy=%s\n' "$_want_agh" "$_want_forward" "$_want_compat" "$_want_proxy"
    return 0
  fi
  _restore=$(umask 077; mktemp "$CONF.native-dns-restore.XXXXXX") || { echo "batch apply failed; backup retained at $_backup" >&2; return 11; }
  if ! cp -p "$_backup" "$_restore" || ! chmod 600 "$_restore" || ! mv -f "$_restore" "$CONF"; then
    rm -f "$_restore" 2>/dev/null || :; echo "batch apply rollback failed; backup retained at $_backup" >&2; return 11
  fi
  sh "$MP/scripts/apply.sh" full >/dev/null 2>&1 || echo "previous DNS settings restored; runtime reconcile failed" >&2
  rm -f "$_backup"; echo "DNS batch apply failed; previous settings restored" >&2; return 1
}

mutate_many() { mutate_many_common 1 "$@"; }
mutate_many_deferred() { mutate_many_common 0 "$@"; }

reconcile_locked() {
  sh "$MP/scripts/apply.sh" full || {
    echo "DNS runtime reconciliation failed" >&2
    return 1
  }
  status
}
with_lock() {
  _lock_pid=$$
  case "$_lock_pid" in ''|0|*[!0-9]*) echo "cannot determine DNS lock owner PID" >&2; return 10 ;; esac
  _tries=0
  _retries=${FX_DNS_LOCK_RETRIES:-20}
  case "$_retries" in ''|*[!0-9]*|0) _retries=20 ;; esac
  [ "$_retries" -le 120 ] 2>/dev/null || _retries=120
  while :; do
    [ ! -L "$LOCK" ] || { echo "unsafe FX DNS settings lock" >&2; return 22; }
    if mkdir "$LOCK" 2>/dev/null; then
      _lock_owner="$LOCK/owner"
      if (umask 077; set -C; printf '%s\\n' "$_lock_pid" > "$_lock_owner") 2>/dev/null; then
        _lock_release() {
          if [ ! -L "$LOCK" ] && [ -d "$LOCK" ] &&
              [ ! -L "$_lock_owner" ] && [ -f "$_lock_owner" ] &&
              [ "$(cat "$_lock_owner" 2>/dev/null || true)" = "$_lock_pid" ]; then
            _release="$LOCK.release.$_lock_pid"
            _release_try=0
            while { [ -e "$_release" ] || [ -L "$_release" ]; } && [ "$_release_try" -lt 20 ]; do
              _release_try=$((_release_try + 1))
              _release="$LOCK.release.$_lock_pid.$_release_try"
            done
            if [ ! -e "$_release" ] && [ ! -L "$_release" ] &&
                mv "$LOCK" "$_release" 2>/dev/null; then
              if [ ! -L "$_release/owner" ] && [ -f "$_release/owner" ] &&
                  [ "$(cat "$_release/owner" 2>/dev/null || true)" = "$_lock_pid" ]; then
                rm -f "$_release/owner" 2>/dev/null || :
                rmdir "$_release" 2>/dev/null || :
              elif [ ! -e "$LOCK" ] && [ ! -L "$LOCK" ]; then
                mv "$_release" "$LOCK" 2>/dev/null || :
              fi
            fi
          fi
        }
        trap _lock_release EXIT
        trap 'exit 129' HUP
        trap 'exit 130' INT
        trap 'exit 143' TERM
        "$@"
        return $?
      fi
      rmdir "$LOCK" 2>/dev/null || :
    else
      [ ! -L "$LOCK" ] && [ -d "$LOCK" ] || { echo "unsafe FX DNS settings lock" >&2; return 22; }
      _owner_file="$LOCK/owner"
      if [ ! -L "$_owner_file" ] && [ -f "$_owner_file" ]; then
        _owner=$(cat "$_owner_file" 2>/dev/null || :)
        case "$_owner" in
          ''|0|*[!0-9]*) : ;;
          *)
            if ! kill -0 "$_owner" 2>/dev/null; then
              _owner2=$(cat "$_owner_file" 2>/dev/null || :)
              if [ "$_owner2" = "$_owner" ] && ! kill -0 "$_owner2" 2>/dev/null; then
                _stale="$LOCK.stale.$_lock_pid.$_tries"
                if [ ! -e "$_stale" ] && [ ! -L "$_stale" ] &&
                    mv "$LOCK" "$_stale" 2>/dev/null; then
                  _moved_owner=$(cat "$_stale/owner" 2>/dev/null || :)
                  if [ "$_moved_owner" = "$_owner" ] &&
                      ! kill -0 "$_moved_owner" 2>/dev/null; then
                    rm -f "$_stale/owner" 2>/dev/null || :
                    rmdir "$_stale" 2>/dev/null || :
                  elif [ ! -e "$LOCK" ] && [ ! -L "$LOCK" ]; then
                    mv "$_stale" "$LOCK" 2>/dev/null || :
                  fi
                  continue
                fi
              fi
            fi
            ;;
        esac
      fi
    fi
    _tries=$((_tries + 1))
    if [ "$_tries" -ge "$_retries" ]; then
      echo "FX DNS settings are busy or lock owner cannot be verified" >&2
      return 75
    fi
    sleep 1
  done
}
cmd=${1:-status}
case "$cmd" in
  status)
    [ "$#" -eq 1 ] || exit 2
    status
    ;;
  reconcile)
    [ "$#" -eq 1 ] || { echo "usage: $0 reconcile" >&2; exit 2; }
    with_lock reconcile_locked
    ;;
  set)
    [ "$#" -eq 3 ] || { echo "usage: $0 set KEY 0|1" >&2; exit 2; }
    valid_key "$2" || { echo "DNS setting is not allowlisted" >&2; exit 2; }
    with_lock mutate "$2" "$3"
    ;;
  set-many)
    [ "$#" -ge 3 ] || { echo "usage: $0 set-many KEY 0|1 [KEY 0|1 ...]" >&2; exit 2; }
    shift
    with_lock mutate_many "$@"
    ;;
  set-many-deferred)
    [ "$#" -ge 3 ] || { echo "usage: $0 set-many-deferred KEY 0|1 [KEY 0|1 ...]" >&2; exit 2; }
    shift
    with_lock mutate_many_deferred "$@"
    ;;
  *)
    echo "usage: $0 status|reconcile|set KEY 0|1|set-many KEY 0|1 ...|set-many-deferred KEY 0|1 ..." >&2
    exit 2
    ;;
esac
