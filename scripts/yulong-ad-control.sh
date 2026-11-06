#!/system/bin/sh
# Native Yulong AdBlock 7.0.1 data adapter for FX.
set -eu
umask 077
MP=""
for d in /data/adb/modules/privacyguard /data/adb/modules_update/privacyguard /data/adb/modules/privacy_guard /data/adb/modules/pg; do
  if [ -s "$d/module.prop" ] && grep -q '^id=privacyguard$' "$d/module.prop"; then MP="$d"; break; fi
done
[ -n "$MP" ] && [ -f "$MP/scripts/util.sh" ] || { echo "FX module is not installed" >&2; exit 20; }
PG=/data/adb/privacyguard
CONF=$PG/settings.conf
[ -f "$CONF" ] && [ ! -L "$CONF" ] || { echo "FX settings.conf missing or unsafe" >&2; exit 21; }
. "$MP/scripts/util.sh"

# One exit/signal cleanup owner prevents nested helpers from replacing each other's traps.
_yad_conf_tmp=
_yad_transaction_backup=
_yad_transaction_restore=
_yad_schedule_lock=
_yad_schedule_tmp=
_yad_schedule_backup=
_yad_control_lock=
_yad_cache_lock=
_yad_import_raw=
_yad_import_clean=
_yad_remove_raw=
_yad_rule_raw=
_yad_rule_clean=
_yad_rule_add_raw=
_yad_rule_add_clean=
_yad_profile_raw=
_yad_bundle_raw=
_yad_bundle_clean=
_yad_cleanup() {
  [ -z "$_yad_conf_tmp" ] || rm -f "$_yad_conf_tmp" 2>/dev/null || :
  [ -z "$_yad_transaction_backup" ] || rm -f "$_yad_transaction_backup" 2>/dev/null || :
  [ -z "$_yad_transaction_restore" ] || rm -f "$_yad_transaction_restore" 2>/dev/null || :
  [ -z "$_yad_schedule_tmp" ] || rm -f "$_yad_schedule_tmp" 2>/dev/null || :
  [ -z "$_yad_schedule_backup" ] || rm -f "$_yad_schedule_backup" 2>/dev/null || :
  [ -z "$_yad_control_lock" ] || rmdir "$_yad_control_lock" 2>/dev/null || :
  [ -z "$_yad_schedule_lock" ] || rmdir "$_yad_schedule_lock" 2>/dev/null || :
  [ -z "$_yad_cache_lock" ] || rmdir "$_yad_cache_lock" 2>/dev/null || :
  [ -z "$_yad_import_raw" ] || rm -f "$_yad_import_raw" 2>/dev/null || :
  [ -z "$_yad_import_clean" ] || rm -f "$_yad_import_clean" 2>/dev/null || :
  [ -z "$_yad_remove_raw" ] || rm -f "$_yad_remove_raw" 2>/dev/null || :
  [ -z "$_yad_rule_raw" ] || rm -f "$_yad_rule_raw" 2>/dev/null || :
  [ -z "$_yad_rule_clean" ] || rm -f "$_yad_rule_clean" 2>/dev/null || :
  [ -z "$_yad_rule_add_raw" ] || rm -f "$_yad_rule_add_raw" 2>/dev/null || :
  [ -z "$_yad_rule_add_clean" ] || rm -f "$_yad_rule_add_clean" 2>/dev/null || :
  [ -z "$_yad_profile_raw" ] || rm -f "$_yad_profile_raw" 2>/dev/null || :
  [ -z "$_yad_bundle_raw" ] || rm -f "$_yad_bundle_raw" 2>/dev/null || :
  [ -z "$_yad_bundle_clean" ] || rm -f "$_yad_bundle_clean" 2>/dev/null || :
}
trap '_yad_cleanup' 0
trap '_yad_cleanup; exit 129' HUP
trap '_yad_cleanup; exit 130' INT
trap '_yad_cleanup; exit 143' TERM
valid_domain() {
  d=$(printf '%s' "$1" | tr 'A-Z' 'a-z')
  case "$d" in ''|.*|*.|*..*|*[!a-z0-9.-]*) return 1 ;; esac
  printf '%s\n' "$d" | awk '{if(length($0)>253)exit 1;n=split($0,a,".");for(i=1;i<=n;i++)if(length(a[i])<1||length(a[i])>63||a[i]!~/^[a-z0-9]([a-z0-9-]*[a-z0-9])?$/)exit 1;print tolower($0)}'
}
valid_source() {
 case "$1" in
  https://*) printf '%s' "$1" | grep -Eq '^https://[A-Za-z0-9._~:/?#@!$&()*+,;=%-]+$' ;;
  builtin://*) printf '%s' "$1" | grep -Eq '^builtin://[A-Za-z0-9._-]+$' ;;
  *) return 1 ;;
 esac
}
valid_text() {
 [ -n "$1" ] || return 1
 n=$(printf '%s' "$1" | wc -c | tr -d ' ')
 [ "$n" -le 180 ] || return 1
 case "$1" in *'|'*|*'
'*) return 1 ;; esac
}
with_lock() {
 lock=$PG/yulong-ad-control.lock; n=0
 while ! mkdir "$lock" 2>/dev/null; do n=$((n+1)); [ "$n" -lt 20 ] || return 30; sleep 1; done
 _yad_control_lock=$lock
 if "$@"; then rc=0; else rc=$?; fi
 rmdir "$lock" 2>/dev/null || :
 _yad_control_lock=
 return "$rc"
}
write_rule() {
 src=$1; title=$2; state=$3; mode=$4; tmp=$(mktemp "$CONF.yulong-rule.XXXXXX") || return 1
  _yad_conf_tmp=$tmp
 awk -F'|' -v OFS='|' -v src="$src" -v title="$title" -v state="$state" -v mode="$mode" '
 BEGIN{inside=0;found=0;done=0}
 $0=="[list:rule]"{inside=1;found=1;print;next}
 /^\[/{if(inside&&mode=="add"&&!done){print src,title,state;done=1}inside=0;print;next}
 inside&&$0!~/^[[:space:]]*#/&&$1==src{if(mode=="remove")next;if(!done){print src,title,state;done=1}next}
 {print}
 END{if(inside&&mode=="add"&&!done){print src,title,state;done=1}if(!found&&mode=="add"){print "";print "[list:rule]";print src,title,state}if(!done&&mode=="set")exit 3}
 ' "$CONF" > "$tmp" || { rm -f "$tmp"; return 1; }
 if [ -s "$tmp" ] && chmod 600 "$tmp" && mv -f "$tmp" "$CONF"; then _yad_conf_tmp=; return 0; fi
 rm -f "$tmp"
 _yad_conf_tmp=
 return 1
  rm -f "$tmp"
  return 1
}
write_block() {
 domain=$1; note=$2; state=$3; mode=$4; tmp=$(mktemp "$CONF.yulong-block.XXXXXX") || return 1
  _yad_conf_tmp=$tmp
 awk -F'|' -v OFS='|' -v domain="$domain" -v note="$note" -v state="$state" -v mode="$mode" '
 BEGIN{inside=0;found=0;done=0}
 $0=="[list:block]"{inside=1;found=1;print;next}
 /^\[/{if(inside&&mode=="add"&&!done){print domain,note,state;done=1}inside=0;print;next}
 inside&&$0!~/^[[:space:]]*#/&&tolower($1)==domain{if(mode=="remove")next;if(!done){print domain,note,state;done=1}next}
 {print}
 END{if(inside&&mode=="add"&&!done){print domain,note,state;done=1}if(!found&&mode=="add"){print "";print "[list:block]";print domain,note,state}}
 ' "$CONF" > "$tmp" || { rm -f "$tmp"; return 1; }
 if [ -s "$tmp" ] && chmod 600 "$tmp" && mv -f "$tmp" "$CONF"; then _yad_conf_tmp=; return 0; fi
 rm -f "$tmp"
 _yad_conf_tmp=
 return 1
  rm -f "$tmp"
  return 1
}
restore_transaction_backup() {
  _yad_transaction_restore=$(mktemp "$CONF.yulong-ad-restore.XXXXXX") || return 1
  restore=$_yad_transaction_restore
  if cp -p "$backup" "$restore" && chmod 600 "$restore" && mv -f "$restore" "$CONF"; then
    _yad_transaction_restore=; restore=; return 0
  fi
  rm -f "$restore"
  _yad_transaction_restore=; restore=
  return 1
}
transaction() {
  op=$1; shift
  _yad_transaction_backup=$(mktemp "$CONF.yulong-ad-rollback.XXXXXX") || return 1
  backup=$_yad_transaction_backup
  if ! cp -p "$CONF" "$backup" || ! chmod 600 "$backup"; then
    rm -f "$backup"
    _yad_transaction_backup=; backup=
    return 1
  fi
  if ! "$op" "$@"; then
    if restore_transaction_backup; then
      sh "$MP/scripts/apply.sh" fast >/dev/null 2>&1 || \
        echo "mutation failed; previous config restored but runtime reconcile failed" >&2
      rm -f "$backup"
      _yad_transaction_backup=; backup=
      echo "mutation failed; previous config restored" >&2
      return 1
    fi
    rm -f "$backup" "$restore"
    _yad_transaction_backup=; _yad_transaction_restore=; backup=; restore=
    echo "mutation failed and config rollback failed" >&2
    return 31
  fi
  if sh "$MP/scripts/apply.sh" fast; then
    rm -f "$backup" "$restore"
    _yad_transaction_backup=; _yad_transaction_restore=; backup=; restore=
    return 0
  fi
  if restore_transaction_backup; then
    sh "$MP/scripts/apply.sh" fast >/dev/null 2>&1 || :
    rm -f "$backup"
    _yad_transaction_backup=; backup=
    echo "apply failed; previous config restored" >&2
    return 1
  fi
  rm -f "$backup" "$restore"
  _yad_transaction_backup=; _yad_transaction_restore=; backup=; restore=
  echo "apply failed and config rollback failed" >&2
  return 31
}
m_dns(){ pg_set "$1" "$2"; }
valid_ipv4() {
  printf '%s\n' "$1" | awk -F. '
    {
      if(NF!=4){bad=1;exit}
      for(i=1;i<=4;i++)if($i==""||$i!~/^[0-9]+$/||length($i)>3||$i+0>255){bad=1;exit}
    }
    END{exit bad}
  '
}
normalize_dns_csv() { printf '%s' "$1" | tr -d '[:space:]'; }
valid_ipv4_dns_csv() {
  printf '%s\n' "$1" | awk -F, '
    {
      if(NF<1||NF>3){bad=1;exit}
      for(i=1;i<=NF;i++){
        if($i!~/^[0-9.]+$/){bad=1;exit}
        n=split($i,a,".")
        if(n!=4){bad=1;exit}
        for(j=1;j<=4;j++)if(a[j]==""||a[j]!~/^[0-9]+$/||length(a[j])>3||a[j]+0>255){bad=1;exit}
        if($i=="0.0.0.0"||$i=="255.255.255.255"){bad=1;exit}
      }
    }
    END{exit bad}
  '
}
valid_dns_csv() {
  printf '%s\n' "$1" | awk -F, '
    function ipv4(v, n, a, j) {
      if(v!~/^[0-9.]+$/) return 0
      n=split(v,a,".")
      if(n!=4) return 0
      for(j=1;j<=4;j++) if(a[j]==""||a[j]!~/^[0-9]+$/||length(a[j])>3||a[j]+0>255) return 0
      if(v=="0.0.0.0"||v=="255.255.255.255") return 0
      return 1    }
    function dns_host(v) {
      return v~/^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$/ && v!~/\.\./
    }
    function valid_hostport(v, n, a) {
      n=split(v,a,":")
      if(n==1) return dns_host(a[1])
      if(n==2) return dns_host(a[1]) && a[2]~/^[0-9]+$/ && a[2]+0>=1 && a[2]+0<=65535
      return 0
    }
    function endpoint(v, rest, parts, hostpart) {
      if(ipv4(v)) return 1
      if(substr(v,1,8)=="https://") {
        rest=substr(v,9)
        split(rest,parts,"/")
        hostpart=parts[1]
        if(!valid_hostport(hostpart)) return 0
        return rest~/^[A-Za-z0-9.-]+(:[0-9]+)?(\/[A-Za-z0-9._~!$&()*+,;=:@%/?#-]*)?$/
      }
      if(substr(v,1,6)=="tls://") return valid_hostport(substr(v,7))
      if(substr(v,1,7)=="quic://") return valid_hostport(substr(v,8))
      return 0
    }
    {
      if(NF<1||NF>3){bad=1;exit}
      for(i=1;i<=NF;i++) if(!endpoint($i)){bad=1;exit}
    }
    END{exit bad}
  '
}
write_dns_section() {
  section=$1; servers=$2; tmp=$(mktemp "$CONF.yulong-dns.XXXXXX") || return 1
  _yad_conf_tmp=$tmp
  awk -v section="$section" -v servers="$servers" '
    function emit(    n,a,i) {n=split(servers,a,",");for(i=1;i<=n;i++)print "nameserver " a[i]}
    BEGIN{inside=0;seen=0;written=0}
    $0=="[conf:" section "]"{if(inside&&!written){emit();written=1}inside=1;seen=1;print;next}
    /^\[/{if(inside&&!written){emit();written=1}inside=0;print;next}
    inside{next}
    {print}
    END{if(inside&&!written){emit();written=1}if(!seen){print "";print "[conf:" section "]";emit()}}
  ' "$CONF" > "$tmp" || { rm -f "$tmp"; return 1; }
  if [ -s "$tmp" ] && chmod 600 "$tmp" && mv -f "$tmp" "$CONF"; then _yad_conf_tmp=; return 0; fi
  rm -f "$tmp"
  _yad_conf_tmp=
  return 1
  rm -f "$tmp"
  return 1
}

remove_dns_section() {
  section=$1
  tmp=$(mktemp "$CONF.yulong-dns-remove.XXXXXX") || return 1
  _yad_conf_tmp=$tmp
  awk -v section="$section" '
    $0=="[conf:" section "]" {inside=1; next}
    /^\[/ {inside=0}
    !inside {print}
  ' "$CONF" > "$tmp" || { rm -f "$tmp"; return 1; }
  [ -s "$tmp" ] || { rm -f "$tmp"; return 1; }
  if chmod 600 "$tmp" && mv -f "$tmp" "$CONF"; then _yad_conf_tmp=; return 0; fi
  rm -f "$tmp"
  _yad_conf_tmp=
  return 1
}
m_dns_section_clear() { remove_dns_section "$1"; }


write_dns_response() {
  mode=$1
  tmp=$(mktemp "$CONF.yulong-dns-response.XXXXXX") || return 1
  _yad_conf_tmp=$tmp
  awk -v mode="$mode" '
    BEGIN{inside=0;seen=0;written=0}
    $0=="[conf:yulong_dns_response]" {
      if(inside&&!written){print "mode=" mode;written=1}
      inside=1;seen=1;print;next
    }
    /^\[/ {
      if(inside&&!written){print "mode=" mode;written=1}
      inside=0;print;next
    }
    inside&&/^mode=/ {
      if(!written)print "mode=" mode
      written=1;next
    }
    {print}
    END{
      if(inside&&!written)print "mode=" mode
      if(!seen){print "";print "[conf:yulong_dns_response]";print "mode=" mode}
    }
  ' "$CONF" > "$tmp" || { rm -f "$tmp"; return 1; }
  if [ -s "$tmp" ] && chmod 600 "$tmp" && mv -f "$tmp" "$CONF"; then _yad_conf_tmp=; return 0; fi
  rm -f "$tmp"
  _yad_conf_tmp=
  return 1
  rm -f "$tmp"
  return 1
}
m_dns_response() { write_dns_response "$1"; }
dns_config_set_many() {
  _many_custom=$(normalize_dns_csv "$1")
  _many_global=$(normalize_dns_csv "$2")
  _many_fallback=$(normalize_dns_csv "$3")
  if [ "$_many_custom" != "-" ]; then
    valid_dns_csv "$_many_custom" || { echo "custom DNS accepts 1..3 IPv4, https:// DoH, tls:// DoT, or quic:// DoQ endpoints" >&2; return 2; }
  fi
  if [ "$_many_global" != "-" ]; then
    valid_ipv4_dns_csv "$_many_global" || { echo "global DNS requires 1..3 IPv4 literals" >&2; return 2; }
  fi
  if [ "$_many_fallback" != "-" ]; then
    valid_ipv4_dns_csv "$_many_fallback" || { echo "fallback DNS requires 1..3 IPv4 literals" >&2; return 2; }
  fi
  if [ "$_many_custom" = "-" ]; then m_dns_section_clear custom_dns || return 1
  else m_dns_servers custom_dns "$_many_custom" || return 1; fi
  if [ "$_many_global" = "-" ]; then m_dns_section_clear global_dns || return 1
  else m_dns_servers global_dns "$_many_global" || return 1; fi
  if [ "$_many_fallback" = "-" ]; then m_dns_section_clear yulong_dns_fallback || return 1
  else m_dns_servers yulong_dns_fallback "$_many_fallback" || return 1; fi
  echo "dns_servers=updated custom=$_many_custom global=$_many_global fallback=$_many_fallback"
}
dns_security_profile_set() {
  _security_mode=$1; _security_enabled=$2
  case "$_security_mode" in nxdomain|refused|custom_ip) ;; *) echo "invalid DNS response mode" >&2; return 2 ;; esac
  case "$_security_enabled" in 0|1) ;; *) echo "DNS security profile flag must be 0 or 1" >&2; return 2 ;; esac
  m_dns_response "$_security_mode" &&
    dns_filter_policy_set "$_security_enabled" "$_security_enabled" "$_security_enabled" "$_security_enabled" "$_security_enabled" || {
      echo "unable to apply complete DNS security profile" >&2
      return 1
    }
  echo "dns_security_profile=updated response=$_security_mode filters=$_security_enabled"
}
dns_filter_policy_set() {
  _policy_quic=$1; _policy_dot=$2; _policy_plain=$3; _policy_ipv6=$4; _policy_track=$5
  for _policy_value in "$_policy_quic" "$_policy_dot" "$_policy_plain" "$_policy_ipv6" "$_policy_track"; do
    case "$_policy_value" in 0|1) : ;; *) echo "DNS filter policy values must be 0 or 1" >&2; return 2 ;; esac
  done
  m_dns block_quic "$_policy_quic" &&
    m_dns block_dot "$_policy_dot" &&
    m_dns block_plain_dns "$_policy_plain" &&
    m_dns block_ipv6 "$_policy_ipv6" &&
    m_dns block_track_domains "$_policy_track" || {
      echo "unable to apply complete DNS filter policy" >&2
      return 1
    }
  echo "policy=updated quic=$_policy_quic dot=$_policy_dot plain_dns=$_policy_plain ipv6=$_policy_ipv6 tracking=$_policy_track"
}

write_vpn_dns() {
  key=$1; value=$2; tmp=$(mktemp "$CONF.yulong-vpn-dns.XXXXXX") || return 1
  _yad_conf_tmp=$tmp
  awk -v key="$key" -v value="$value" '
    BEGIN{inside=0;seen=0;written=0}
    $0=="[conf:vpn]"{if(inside&&!written){print key "=" value;written=1}inside=1;seen=1;print;next}
    /^\[/{if(inside&&!written){print key "=" value;written=1}inside=0;print;next}
    inside&&index($0,key "=")==1{if(!written)print key "=" value;written=1;next}
    {print}
    END{if(inside&&!written)print key "=" value;if(!seen){print "";print "[conf:vpn]";print key "=" value}}
  ' "$CONF" > "$tmp" || { rm -f "$tmp"; return 1; }
  if [ -s "$tmp" ] && chmod 600 "$tmp" && mv -f "$tmp" "$CONF"; then _yad_conf_tmp=; return 0; fi
  rm -f "$tmp"
  _yad_conf_tmp=
  return 1
  rm -f "$tmp"
  return 1
}
m_dns_servers() { write_dns_section "$1" "$2"; }
m_vpn_dns() { write_vpn_dns "$1" "$2"; }
dns_vpn_set_many() {
  _vpn_remote=$1; _vpn_cn=$2
  valid_ipv4 "$_vpn_remote" || { echo "VPN remote DNS must be an IPv4 literal" >&2; return 2; }
  valid_ipv4 "$_vpn_cn" || { echo "VPN China DNS must be an IPv4 literal" >&2; return 2; }
  m_vpn_dns remote_dns "$_vpn_remote" &&
    m_vpn_dns cn_dns "$_vpn_cn" || {
      echo "unable to update both VPN DNS values" >&2
      return 1
    }
  echo "vpn_dns=updated remote_dns=$_vpn_remote cn_dns=$_vpn_cn"
}
m_vpn_dns_reset() { write_vpn_dns remote_dns 1.1.1.1 && write_vpn_dns cn_dns 223.5.5.5; }
dns_profile_get() {
  echo FXYULONGDNSPROFILE1
  for key in dns_engine_adguardhome dns_forward custom_dns global_dns block_quic block_dot block_plain_dns block_ipv6 block_track_domains vpn_external_dns_proxy vpn_external_compat dns_querylog_enabled; do
    printf '%s=%s\n' "$key" "$(pg_get "$key" 0)"
  done
  for pair in custom_dns:CUSTOM global_dns:GLOBAL yulong_dns_fallback:FALLBACK; do
    section=${pair%%:*}; label=${pair#*:}
    value=$(pg_conf "$section" 2>/dev/null | awk '/^[[:space:]]*nameserver[[:space:]]+/{if(n++)printf ",";printf "%s",$2}')
    printf '%s_SERVERS=%s\n' "$label" "$value"
  done
  printf 'VPN_REMOTE=%s\n' "$(pg_conf vpn 2>/dev/null | sed -n 's/^remote_dns=//p' | head -n1)"
  printf 'VPN_CN=%s\n' "$(pg_conf vpn 2>/dev/null | sed -n 's/^cn_dns=//p' | head -n1)"
  mode=$(awk -F= '$0=="[conf:yulong_dns_response]"{inside=1;next} /^\[/{inside=0} inside&&$1=="mode"{v=$2} END{print v}' "$CONF" 2>/dev/null)
  case "$mode" in nxdomain|refused|custom_ip) ;; *) mode=nxdomain ;; esac
  printf 'RESPONSE_MODE=%s\n' "$mode"
}

dns_profile_restore() {
  _profile_encoded=$1
  case "$_profile_encoded" in ''|*[!A-Za-z0-9+/=]*) echo "invalid DNS profile encoding" >&2; return 2 ;; esac
  [ "${#_profile_encoded}" -le 87384 ] || { echo "DNS profile exceeds 64 KiB" >&2; return 2; }
  _yad_profile_raw=$(mktemp "$PG/yulong-dns-profile.XXXXXX") || return 1
  chmod 600 "$_yad_profile_raw" || return 1
  (umask 077; printf '%s' "$_profile_encoded" | base64 -d > "$_yad_profile_raw") || { echo "unable to decode DNS profile" >&2; return 2; }
  _profile_bytes=$(wc -c < "$_yad_profile_raw" | tr -d ' ')
  [ "$_profile_bytes" -le 65536 ] || { echo "DNS profile exceeds 64 KiB" >&2; return 2; }
  [ "$(sed -n '1p' "$_yad_profile_raw")" = FXYULONGDNSPROFILE1 ] || { echo "unsupported DNS profile version" >&2; return 2; }
  awk '
    NR==1 {if($0!="FXYULONGDNSPROFILE1")bad=1;next}
    {
      if(index($0,"=")<2 || $0 ~ /\r/){bad=1;next}
      key=substr($0,1,index($0,"=")-1)
      value=substr($0,index($0,"=")+1)
      if(key !~ /^(dns_engine_adguardhome|dns_forward|custom_dns|global_dns|block_quic|block_dot|block_plain_dns|block_ipv6|block_track_domains|vpn_external_dns_proxy|vpn_external_compat|dns_querylog_enabled|CUSTOM_SERVERS|GLOBAL_SERVERS|FALLBACK_SERVERS|VPN_REMOTE|VPN_CN|RESPONSE_MODE)$/)bad=1
      if(seen[key]++)bad=1
      count++
    }
    END{if(bad||count!=18)exit 1}
  ' "$_yad_profile_raw" || { echo "DNS profile has unknown, duplicate, missing, or malformed fields" >&2; return 2; }
  _profile_seen='|'
  while IFS= read -r _profile_line || [ -n "$_profile_line" ]; do
    [ "$_profile_line" = FXYULONGDNSPROFILE1 ] && continue
    _profile_key=${_profile_line%%=*}; _profile_value=${_profile_line#*=}
    case "$_profile_key" in
      dns_engine_adguardhome|dns_forward|custom_dns|global_dns|block_quic|block_dot|block_plain_dns|block_ipv6|block_track_domains|vpn_external_dns_proxy|vpn_external_compat|dns_querylog_enabled)
        case "$_profile_value" in 0|1) : ;; *) echo "invalid DNS flag: $_profile_key" >&2; return 2 ;; esac
        ;;
      CUSTOM_SERVERS)
        _profile_custom=$_profile_value
        [ -z "$_profile_custom" ] || valid_dns_csv "$_profile_custom" || { echo "invalid custom DNS servers" >&2; return 2; }
        ;;
      GLOBAL_SERVERS)
        _profile_global=$_profile_value
        [ -z "$_profile_global" ] || valid_ipv4_dns_csv "$_profile_global" || { echo "invalid global DNS servers" >&2; return 2; }
        ;;
      FALLBACK_SERVERS)
        _profile_fallback=$_profile_value
        [ -z "$_profile_fallback" ] || valid_ipv4_dns_csv "$_profile_fallback" || { echo "invalid fallback DNS servers" >&2; return 2; }
        ;;
      VPN_REMOTE|VPN_CN)
        valid_ipv4 "$_profile_value" || { echo "invalid VPN DNS address: $_profile_key" >&2; return 2; }
        ;;
      RESPONSE_MODE)
        case "$_profile_value" in nxdomain|refused|custom_ip) : ;; *) echo "invalid DNS response mode" >&2; return 2 ;; esac
        ;;
    esac
    case "$_profile_key" in
      dns_engine_adguardhome) _profile_agh=$_profile_value ;;
      dns_forward) _profile_forward=$_profile_value ;;
      custom_dns) _profile_custom_enabled=$_profile_value ;;
      global_dns) _profile_global_enabled=$_profile_value ;;
      block_quic) _profile_quic=$_profile_value ;;
      block_dot) _profile_dot=$_profile_value ;;
      block_plain_dns) _profile_plain=$_profile_value ;;
      block_ipv6) _profile_ipv6=$_profile_value ;;
      block_track_domains) _profile_track=$_profile_value ;;
      vpn_external_dns_proxy) _profile_proxy=$_profile_value ;;
      vpn_external_compat) _profile_compat=$_profile_value ;;
      dns_querylog_enabled) _profile_querylog=$_profile_value ;;
      VPN_REMOTE) _profile_remote=$_profile_value ;;
      VPN_CN) _profile_cn=$_profile_value ;;
      RESPONSE_MODE) _profile_mode=$_profile_value ;;
    esac
  done < "$_yad_profile_raw"
  # Preserve the native DNS dependency invariants before touching the live config.
  if [ "$_profile_forward" != 1 ]; then _profile_agh=0; _profile_proxy=0; fi
  if [ "$_profile_agh" != 1 ]; then _profile_proxy=0; fi
  if [ "$_profile_compat" != 1 ]; then _profile_proxy=0; fi
  if [ "$_profile_proxy" = 1 ]; then _profile_forward=1; _profile_agh=1; _profile_compat=1; fi
  [ -x "$MP/scripts/native-dns-settings.sh" ] || { echo "native DNS dependency manager is missing" >&2; return 20; }
  MP="$MP" PG="$PG" sh "$MP/scripts/native-dns-settings.sh" set-many \
    dns_engine_adguardhome "$_profile_agh" \
    dns_forward "$_profile_forward" \
    vpn_external_compat "$_profile_compat" \
    vpn_external_dns_proxy "$_profile_proxy" || return 1
  pg_set custom_dns "$_profile_custom_enabled" &&
    pg_set global_dns "$_profile_global_enabled" &&
    pg_set block_quic "$_profile_quic" &&
    pg_set block_dot "$_profile_dot" &&
    pg_set block_plain_dns "$_profile_plain" &&
    pg_set block_ipv6 "$_profile_ipv6" &&
    pg_set block_track_domains "$_profile_track" &&
    pg_set dns_querylog_enabled "$_profile_querylog" || return 1
  if [ -n "$_profile_custom" ]; then m_dns_servers custom_dns "$_profile_custom" || return 1
  else m_dns_section_clear custom_dns || return 1; fi
  if [ -n "$_profile_global" ]; then m_dns_servers global_dns "$_profile_global" || return 1
  else m_dns_section_clear global_dns || return 1; fi
  if [ -n "$_profile_fallback" ]; then m_dns_servers yulong_dns_fallback "$_profile_fallback" || return 1
  else m_dns_section_clear yulong_dns_fallback || return 1; fi
  m_vpn_dns remote_dns "$_profile_remote" &&
    m_vpn_dns cn_dns "$_profile_cn" &&
    m_dns_response "$_profile_mode" || return 1
  printf 'dns_profile=restored native_agh=%s native_forward=%s native_compat=%s native_proxy=%s\n' "$_profile_agh" "$_profile_forward" "$_profile_compat" "$_profile_proxy"
}
dns_profile_transaction() {
  _profile_backup=$(umask 077; mktemp "$CONF.dns-profile-rollback.XXXXXX") || return 1
  if ! cp -p "$CONF" "$_profile_backup" || ! chmod 600 "$_profile_backup"; then rm -f "$_profile_backup"; return 1; fi
  if ! dns_profile_restore "$1"; then
    _profile_restore=$(umask 077; mktemp "$CONF.dns-profile-restore.XXXXXX") || { echo "DNS profile mutation failed; backup retained at $_profile_backup" >&2; return 11; }
    if ! cp -p "$_profile_backup" "$_profile_restore" || ! chmod 600 "$_profile_restore" || ! mv -f "$_profile_restore" "$CONF"; then
      rm -f "$_profile_restore" 2>/dev/null || :; echo "DNS profile rollback failed; backup retained at $_profile_backup" >&2; return 11
    fi
    sh "$MP/scripts/apply.sh" full >/dev/null 2>&1 || echo "previous DNS profile restored; runtime reconcile failed" >&2
    rm -f "$_profile_backup"; return 1
  fi
  if sh "$MP/scripts/apply.sh" full; then rm -f "$_profile_backup"; return 0; fi
  _profile_restore=$(umask 077; mktemp "$CONF.dns-profile-restore.XXXXXX") || { echo "DNS profile apply failed; backup retained at $_profile_backup" >&2; return 11; }
  if ! cp -p "$_profile_backup" "$_profile_restore" || ! chmod 600 "$_profile_restore" || ! mv -f "$_profile_restore" "$CONF"; then
    rm -f "$_profile_restore" 2>/dev/null || :; echo "DNS profile apply rollback failed; backup retained at $_profile_backup" >&2; return 11
  fi
  sh "$MP/scripts/apply.sh" full >/dev/null 2>&1 || echo "previous DNS profile restored; runtime reconcile failed" >&2
  rm -f "$_profile_backup"; echo "DNS profile apply failed; previous settings restored" >&2; return 1
}

dns_config_get() {
  echo FXYULONGDNS1
  echo "CUSTOM_ENABLED|$(pg_get custom_dns 0)"
  echo "GLOBAL_ENABLED|$(pg_get global_dns 0)"
  pg_conf custom_dns 2>/dev/null | awk '/^[[:space:]]*nameserver[[:space:]]+/{print "CUSTOM|" $2}'
  pg_conf global_dns 2>/dev/null | awk '/^[[:space:]]*nameserver[[:space:]]+/{print "GLOBAL|" $2}'
  pg_conf yulong_dns_fallback 2>/dev/null | awk '/^[[:space:]]*nameserver[[:space:]]+/{print "FALLBACK|" $2}'
  echo "VPN_REMOTE|$(pg_conf vpn 2>/dev/null | sed -n 's/^remote_dns=//p' | head -n1)"
  echo "VPN_CN|$(pg_conf vpn 2>/dev/null | sed -n 's/^cn_dns=//p' | head -n1)"
}
m_rule_add(){ write_rule "$1" "$2" "$3" add; }
m_rule_set(){ old=$(pg_list rule|awk -F'|' -v src="$1" '$1==src{print $2;exit}'); [ -n "$old" ] || return 3; write_rule "$1" "$old" "$2" set; }
m_rule_remove(){ write_rule "$1" "" 0 remove; }
rule_add_many() {
  _add_encoded="$1"
  case "$_add_encoded" in ''|*[!A-Za-z0-9+/=]*) echo "invalid base64 rule import" >&2; return 2 ;; esac
  [ "${#_add_encoded}" -le 87384 ] || { echo "rule import exceeds 64 KiB" >&2; return 2; }
  _add_raw=$(mktemp "$PG/yulong-rule-add.XXXXXX") || return 1
  _yad_rule_add_raw=$_add_raw
  _add_clean=$(mktemp "$PG/yulong-rule-add-clean.XXXXXX") || return 1
  _yad_rule_add_clean=$_add_clean
  chmod 600 "$_add_raw" "$_add_clean" || return 1
  (umask 077; printf '%s' "$_add_encoded" | base64 -d > "$_add_raw") || { echo "unable to decode rule import" >&2; return 2; }
  _add_bytes=$(wc -c < "$_add_raw" | tr -d ' ')
  [ "$_add_bytes" -le 65536 ] || { echo "rule import exceeds 64 KiB" >&2; return 2; }
  _add_count=0
  while IFS='|' read -r _add_source _add_title _add_extra || [ -n "$_add_source$_add_title$_add_extra" ]; do
    [ -n "$_add_source" ] || continue
    [ -z "$_add_extra" ] || { echo "invalid rule row: use source|name" >&2; return 2; }
    valid_source "$_add_source" || { echo "invalid rule source" >&2; return 2; }
    valid_text "$_add_title" || { echo "invalid rule name" >&2; return 2; }
    if grep -F -x -q "$_add_source" "$_add_clean" || pg_list rule | awk -F'|' -v src="$_add_source" '$1==src{found=1} END{exit !found}'; then
      echo "duplicate or already configured rule source: $_add_source" >&2; return 2
    fi
    printf '%s|%s\n' "$_add_source" "$_add_title" >> "$_add_clean" || return 1
    _add_count=$((_add_count + 1))
    [ "$_add_count" -le 2000 ] || { echo "rule import is limited to 2000 sources" >&2; return 2; }
  done < "$_add_raw"
  [ "$_add_count" -gt 0 ] || { echo "no rule sources to import" >&2; return 2; }
  while IFS='|' read -r _add_source _add_title; do
    write_rule "$_add_source" "$_add_title" 1 add || { echo "failed to add rule source: $_add_source" >&2; return 1; }
  done < "$_add_clean"
  echo "added=$_add_count"
}
rule_set_many() {
  _rule_state="$1"; _rule_encoded="$2"
  [ "$_rule_state" = 0 ] || [ "$_rule_state" = 1 ] || return 2
  case "$_rule_encoded" in ''|*[!A-Za-z0-9+/=]*) echo "invalid base64 rule source list" >&2; return 2 ;; esac
  [ "${#_rule_encoded}" -le 87384 ] || { echo "rule source list exceeds 64 KiB" >&2; return 2; }
  _rule_raw=$(mktemp "$PG/yulong-rule-set.XXXXXX") || return 1
  _yad_rule_raw=$_rule_raw
  _rule_clean=$(mktemp "$PG/yulong-rule-set-clean.XXXXXX") || return 1
  _yad_rule_clean=$_rule_clean
  chmod 600 "$_rule_raw" "$_rule_clean" || return 1
  (umask 077; printf '%s' "$_rule_encoded" | base64 -d > "$_rule_raw") || { echo "unable to decode rule source list" >&2; return 2; }
  _rule_bytes=$(wc -c < "$_rule_raw" | tr -d ' ')
  [ "$_rule_bytes" -le 65536 ] || { echo "rule source list exceeds 64 KiB" >&2; return 2; }
  _rule_count=0
  while IFS= read -r _rule_source || [ -n "$_rule_source" ]; do
    [ -n "$_rule_source" ] || continue
    valid_source "$_rule_source" || { echo "invalid rule source in batch" >&2; return 2; }
    if ! grep -F -x -q "$_rule_source" "$_rule_clean"; then      printf '%s\n' "$_rule_source" >> "$_rule_clean" || return 1
      _rule_count=$((_rule_count + 1))
      [ "$_rule_count" -le 2000 ] || { echo "rule batch is limited to 2000 sources" >&2; return 2; }
    fi
  done < "$_rule_raw"
  [ "$_rule_count" -gt 0 ] || { echo "no rule sources to update" >&2; return 2; }
  while IFS= read -r _rule_source; do
    m_rule_set "$_rule_source" "$_rule_state" || { echo "failed to update rule source: $_rule_source" >&2; return 1; }
  done < "$_rule_clean"
  echo "updated=$_rule_count state=$_rule_state"
}
import_domains() {
  _import_kind="$1"
  _import_encoded="$2"
  case "$_import_kind" in allow|block) ;; *) return 2 ;; esac
  case "$_import_encoded" in ''|*[!A-Za-z0-9+/=]*) echo "invalid base64 domain import" >&2; return 2 ;; esac
  [ "${#_import_encoded}" -le 87384 ] || { echo "domain import exceeds 64 KiB" >&2; return 2; }

  _import_raw=$(mktemp "$PG/yulong-domain-import.XXXXXX") || {
    echo "unable to create private domain import staging file" >&2
    return 1
  }
  _yad_import_raw=$_import_raw
  _import_clean=$(mktemp "$PG/yulong-domain-import-clean.XXXXXX") || {
    echo "unable to create private normalized domain import staging file" >&2
    return 1
  }
  _yad_import_clean=$_import_clean
  chmod 600 "$_import_raw" "$_import_clean" || {
    echo "unable to protect domain import staging files" >&2
    return 1
  }
  (umask 077; printf '%s' "$_import_encoded" | base64 -d > "$_import_raw") || {
    rm -f "$_import_raw" "$_import_clean" 2>/dev/null || :
    echo "unable to decode domain import" >&2
    return 2
  }
  _import_bytes=$(wc -c < "$_import_raw" | tr -d ' ')
  [ "$_import_bytes" -le 65536 ] || {
    rm -f "$_import_raw" "$_import_clean" 2>/dev/null || :
    echo "domain import exceeds 64 KiB" >&2
    return 2
  }

  _import_count=0
  while IFS='|' read -r _import_domain _import_note _import_extra || \
        [ -n "$_import_domain$_import_note$_import_extra" ]; do
    _import_domain=$(printf '%s' "$_import_domain" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    _import_note=$(printf '%s' "$_import_note" | tr -d '\r')
    [ -n "$_import_domain" ] || continue
    [ -z "$_import_extra" ] || {
      rm -f "$_import_raw" "$_import_clean" 2>/dev/null || :
      echo "invalid domain row: only domain|note is accepted" >&2
      return 2
    }
    _import_domain=$(valid_domain "$_import_domain") || {
      rm -f "$_import_raw" "$_import_clean" 2>/dev/null || :
      echo "invalid domain in import" >&2
      return 2
    }
    if [ -z "$_import_note" ]; then
      if [ "$_import_kind" = allow ]; then _import_note="FX 批量白名单"; else _import_note="FX 批量黑名单"; fi
    fi
    valid_text "$_import_note" || {
      rm -f "$_import_raw" "$_import_clean" 2>/dev/null || :
      echo "invalid note for domain: $_import_domain" >&2
      return 2
    }
    printf '%s|%s\n' "$_import_domain" "$_import_note" >> "$_import_clean" || {
      rm -f "$_import_raw" "$_import_clean" 2>/dev/null || :
      return 1
    }
    _import_count=$((_import_count + 1))
    [ "$_import_count" -le 2000 ] || {
      rm -f "$_import_raw" "$_import_clean" 2>/dev/null || :
      echo "domain import is limited to 2000 rows" >&2
      return 2
    }
  done < "$_import_raw"

  [ "$_import_count" -gt 0 ] || {
    rm -f "$_import_raw" "$_import_clean" 2>/dev/null || :
    echo "no domains to import" >&2
    return 2
  }

  while IFS='|' read -r _import_domain _import_note; do
    if [ "$_import_kind" = allow ]; then
      sh "$MP/scripts/whitelist.sh" add "$_import_domain" "$_import_note" || {
        rm -f "$_import_raw" "$_import_clean" 2>/dev/null || :
        echo "failed to add allow domain: $_import_domain" >&2
        return 1
      }
    else
      write_block "$_import_domain" "$_import_note" 1 add || {
        rm -f "$_import_raw" "$_import_clean" 2>/dev/null || :
        echo "failed to add block domain: $_import_domain" >&2
        return 1
      }
    fi
  done < "$_import_clean"

  rm -f "$_import_raw" "$_import_clean" 2>/dev/null || :
  echo "imported=$_import_count"
}
import_domain_bundle() {
  _bundle_encoded="$1"
  case "$_bundle_encoded" in ''|*[!A-Za-z0-9+/=]*) echo "invalid domain bundle encoding" >&2; return 2 ;; esac
  [ "${#_bundle_encoded}" -le 87384 ] || { echo "domain bundle exceeds 64 KiB" >&2; return 2; }
  _yad_bundle_raw=$(mktemp "$PG/yulong-domain-bundle.XXXXXX") || return 1
  _yad_bundle_clean=$(mktemp "$PG/yulong-domain-bundle-clean.XXXXXX") || return 1
  chmod 600 "$_yad_bundle_raw" "$_yad_bundle_clean" || return 1
  (umask 077; printf '%s' "$_bundle_encoded" | base64 -d > "$_yad_bundle_raw") || { echo "unable to decode domain bundle" >&2; return 2; }
  _bundle_bytes=$(wc -c < "$_yad_bundle_raw" | tr -d ' ')
  [ "$_bundle_bytes" -le 65536 ] || { echo "domain bundle exceeds 64 KiB" >&2; return 2; }
  _bundle_count=0
  while IFS='|' read -r _bundle_kind _bundle_domain _bundle_note _bundle_extra || [ -n "$_bundle_kind$_bundle_domain$_bundle_note$_bundle_extra" ]; do
    case "$_bundle_kind" in ''|'#'*) continue ;; allow|block) : ;; *) echo "invalid domain bundle kind" >&2; return 2 ;; esac
    [ -z "$_bundle_extra" ] || { echo "invalid domain bundle row: use allow|domain|note or block|domain|note" >&2; return 2; }
    _bundle_domain=$(printf '%s' "$_bundle_domain" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    _bundle_note=$(printf '%s' "$_bundle_note" | tr -d '\r')
    _bundle_domain=$(valid_domain "$_bundle_domain") || { echo "invalid domain in bundle" >&2; return 2; }
    if [ -z "$_bundle_note" ]; then
      if [ "$_bundle_kind" = allow ]; then _bundle_note="FX 导入白名单"; else _bundle_note="FX 导入黑名单"; fi
    fi
    valid_text "$_bundle_note" || { echo "invalid note for domain: $_bundle_domain" >&2; return 2; }
    if awk -F'|' -v k="$_bundle_kind" -v d="$_bundle_domain" '$1==k && $2==d{found=1} END{exit !found}' "$_yad_bundle_clean"; then continue; fi
    printf '%s|%s|%s\n' "$_bundle_kind" "$_bundle_domain" "$_bundle_note" >> "$_yad_bundle_clean" || return 1
    _bundle_count=$((_bundle_count + 1))
    [ "$_bundle_count" -le 2000 ] || { echo "domain bundle is limited to 2000 unique rows" >&2; return 2; }
  done < "$_yad_bundle_raw"
  [ "$_bundle_count" -gt 0 ] || { echo "no domains to import" >&2; return 2; }
  while IFS='|' read -r _bundle_kind _bundle_domain _bundle_note; do
    if [ "$_bundle_kind" = allow ]; then
      sh "$MP/scripts/whitelist.sh" add "$_bundle_domain" "$_bundle_note" || { echo "failed to import allow domain: $_bundle_domain" >&2; return 1; }
    else
      write_block "$_bundle_domain" "$_bundle_note" 1 add || { echo "failed to import block domain: $_bundle_domain" >&2; return 1; }
    fi
  done < "$_yad_bundle_clean"
  echo "imported=$_bundle_count"
}
remove_domains() {
  _remove_kind="$1"
  _remove_encoded="$2"
  case "$_remove_kind" in allow|block) ;; *) return 2 ;; esac
  case "$_remove_encoded" in ''|*[!A-Za-z0-9+/=]*) echo "invalid base64 domain removal" >&2; return 2 ;; esac
  [ "${#_remove_encoded}" -le 87384 ] || { echo "domain removal exceeds 64 KiB" >&2; return 2; }
  _remove_raw=$(mktemp "$PG/yulong-domain-remove.XXXXXX") || return 1
  _yad_remove_raw=$_remove_raw
  chmod 600 "$_remove_raw" || return 1
  (umask 077; printf '%s' "$_remove_encoded" | base64 -d > "$_remove_raw") || {
    rm -f "$_remove_raw"; _yad_remove_raw=; echo "unable to decode domain removal" >&2; return 2;
  }
  _remove_bytes=$(wc -c < "$_remove_raw" | tr -d ' ')
  [ "$_remove_bytes" -le 65536 ] || { echo "domain removal exceeds 64 KiB" >&2; return 2; }
  _remove_clean=$(mktemp "$PG/yulong-domain-remove-clean.XXXXXX") || return 1
  chmod 600 "$_remove_clean" || { rm -f "$_remove_clean"; return 1; }
  _remove_count=0
  while IFS= read -r _remove_line || [ -n "$_remove_line" ]; do
    _remove_line=$(printf '%s' "$_remove_line" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    [ -n "$_remove_line" ] || continue
    _remove_domain=$(valid_domain "$_remove_line") || {
      rm -f "$_remove_clean"; echo "invalid domain in removal list" >&2; return 2;
    }
    printf '%s\n' "$_remove_domain" >> "$_remove_clean" || { rm -f "$_remove_clean"; return 1; }
    _remove_count=$((_remove_count + 1))
    [ "$_remove_count" -le 2000 ] || { rm -f "$_remove_clean"; echo "domain removal is limited to 2000 rows" >&2; return 2; }
  done < "$_remove_raw"
  [ "$_remove_count" -gt 0 ] || { rm -f "$_remove_clean"; echo "no domains to remove" >&2; return 2; }
  while IFS= read -r _remove_domain; do
    if [ "$_remove_kind" = allow ]; then
      sh "$MP/scripts/whitelist.sh" remove "$_remove_domain" || { rm -f "$_remove_clean"; echo "failed to remove allow domain" >&2; return 1; }
    else
      write_block "$_remove_domain" "" 0 remove || { rm -f "$_remove_clean"; echo "failed to remove block domain" >&2; return 1; }
    fi
  done < "$_remove_clean"
  rm -f "$_remove_clean" "$_remove_raw"
  _yad_remove_raw=
  echo "removed=$_remove_count"
}
m_allow_add(){ sh "$MP/scripts/whitelist.sh" add "$1" "$2"; }
m_allow_remove(){ sh "$MP/scripts/whitelist.sh" remove "$1"; }
m_allow_import(){ import_domains allow "$1"; }
m_block_add(){ write_block "$1" "$2" 1 add; }
m_block_remove(){ write_block "$1" "" 0 remove; }
m_block_import(){ import_domains block "$1"; }
domain_clear_all() {
  _clear_kind=$1
  case "$_clear_kind" in allow|block) ;; *) return 2 ;; esac
  _clear_domains=$(pg_list "$_clear_kind" 2>/dev/null | awk -F'|' 'NF && $1!="" {print $1}')
  [ -n "$_clear_domains" ] || { echo "${_clear_kind}_domains=already_empty"; return 0; }
  _clear_encoded=$(printf '%s\n' "$_clear_domains" | base64 | tr -d '\n') || return 1
  remove_domains "$_clear_kind" "$_clear_encoded"
}
m_allow_remove_many(){ remove_domains allow "$1"; }
m_block_remove_many(){ remove_domains block "$1"; }
m_block_remove_many(){ remove_domains block "$1"; }
valid_time() {
  printf '%s\n' "$1" | awk -F: 'NF==2 && $1~/^[0-9][0-9]$/ && $2~/^[0-9][0-9]$/ && $1+0<=23 && $2+0<=59 {ok=1} END{exit !ok}'
}
valid_days() {
  printf '%s\n' "$1" | awk -F, '
    NF<1 || NF>7 {bad=1}
    {
      for(i=1;i<=NF;i++) {
        if($i!~/^[1-7]$/ || seen[$i]++) bad=1
      }
    }
    END {exit bad ? 1 : 0}
  '
}
schedule_get() {
  file="$PG/yulong-ad-schedule.conf"
  enabled=0; start=22:00; end=07:00; days=1,2,3,4,5,6,7
  if [ -f "$file" ] && [ ! -L "$file" ]; then
    enabled=$(awk -F= '$1=="enabled"{print $2;exit}' "$file")
    start=$(awk -F= '$1=="start"{print $2;exit}' "$file")
    end=$(awk -F= '$1=="end"{print $2;exit}' "$file")
    days=$(awk -F= '$1=="days"{print $2;exit}' "$file")
    [ "$enabled" = 1 ] || enabled=0
    valid_time "$start" || start=22:00
    valid_time "$end" || end=07:00
    valid_days "$days" || days=1,2,3,4,5,6,7
  fi
  echo FXYULONGADSCHED1
  echo "enabled=$enabled"
  echo "start=$start"
  echo "end=$end"
  echo "days=$days"
  echo "active=$(pg_get yulong_ad_schedule_active 1)"
  watcher=0
  pidfile="$PG/yulong-ad-schedule.pid"
  if [ -f "$pidfile" ] && [ ! -L "$pidfile" ]; then
    pid=$(cat "$pidfile" 2>/dev/null)
    case "$pid" in ''|*[!0-9]*) pid= ;; esac
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null && [ -r "/proc/$pid/cmdline" ]; then
      proc_state=$(awk '{print $3}' "/proc/$pid/stat" 2>/dev/null || :)
      proc_cmd=$(tr '\000' ' ' < "/proc/$pid/cmdline" 2>/dev/null || :)
      case "$proc_cmd" in
        *"yulong-ad-schedule.sh"*' watch '*) [ "$proc_state" = Z ] || watcher=1 ;;
      esac
    fi
  fi
  echo "watcher=$watcher"
}schedule_set() {
  enabled=$1; start=$2; end=$3; days=$4
  { [ "$enabled" = 0 ] || [ "$enabled" = 1 ]; } || return 2
  valid_time "$start" && valid_time "$end" && valid_days "$days" || {
    echo "invalid schedule: use HH:MM and unique weekdays 1..7" >&2; return 2;
  }
  file="$PG/yulong-ad-schedule.conf"
  lock="$PG/yulong-ad-schedule.lock"
  if ! mkdir "$lock" 2>/dev/null; then
    echo "schedule update is busy" >&2
    return 30
  fi
  _yad_schedule_lock=$lock
  _yad_schedule_tmp=$(mktemp "$file.tmp.XXXXXX") || return 31
  tmp=$_yad_schedule_tmp
  _yad_schedule_backup=
  existed=0
  if [ -f "$file" ] && [ ! -L "$file" ]; then
    _yad_schedule_backup=$(mktemp "$file.rollback.XXXXXX") || return 31
    backup=$_yad_schedule_backup
    cp -p "$file" "$backup" && chmod 600 "$backup" || {
      echo "unable to preserve previous schedule" >&2
      return 31
    }
    existed=1
  fi
  {
    printf 'enabled=%s\n' "$enabled"
    printf 'start=%s\n' "$start"
    printf 'end=%s\n' "$end"
    printf 'days=%s\n' "$days"
  } > "$tmp" || { echo "unable to write schedule candidate" >&2; return 32; }
  chmod 600 "$tmp" && mv -f "$tmp" "$file" || {
    echo "unable to commit schedule candidate" >&2
    return 33
  }
  _yad_schedule_tmp=; tmp=
  sync
  if [ ! -x "$MP/scripts/yulong-ad-schedule.sh" ]; then
    echo "Yulong schedule runtime is not installed" >&2
  else
    if MP="$MP" PG="$PG" sh "$MP/scripts/yulong-ad-schedule.sh" evaluate \
        && MP="$MP" PG="$PG" sh "$MP/scripts/yulong-ad-schedule.sh" start; then
      rm -f "$backup"
      backup=; _yad_schedule_backup=
      echo "schedule=committed"
      return 0
    fi
    echo "schedule apply or watcher start failed; restoring previous schedule" >&2
  fi
  if [ "$existed" = 1 ] && [ -f "$backup" ]; then
    _yad_schedule_tmp=$(mktemp "$file.restore.XXXXXX") || {
      echo "schedule rollback temp creation failed; previous copy remains at $backup" >&2
      backup=; _yad_schedule_backup=
      return 34
    }
    tmp=$_yad_schedule_tmp
    if cp -p "$backup" "$tmp" && chmod 600 "$tmp" && mv -f "$tmp" "$file"; then
      tmp=; _yad_schedule_tmp=
    else
      rm -f "$tmp"
      tmp=; _yad_schedule_tmp=
      echo "schedule rollback failed; previous copy remains at $backup" >&2
      backup=; _yad_schedule_backup=
      return 34
    fi
  else
    rm -f "$file"
  fi
  sync
  MP="$MP" PG="$PG" sh "$MP/scripts/yulong-ad-schedule.sh" evaluate >/dev/null 2>&1 || :
  return 35
}
cache_flush() {
  lock="$PG/yulong-cache-flush.lock"
  if ! mkdir "$lock" 2>/dev/null; then echo "DNS cache refresh is already running" >&2; return 30; fi
  _yad_cache_lock=$lock
  agh_enabled=$(pg_get dns_engine_adguardhome 1 2>/dev/null)
  forward_enabled=$(pg_get dns_forward 1 2>/dev/null)
  if [ "$agh_enabled" != 1 ] && [ "$forward_enabled" != 1 ]; then
    echo "dns-engine-disabled"
    return 0
  fi
  if [ "$forward_enabled" = 1 ] && [ ! -x "$MP/scripts/unbound.sh" ]; then
    echo "Unbound is enabled but its FX lifecycle helper is missing; cache was not cleared" >&2
    return 32
  fi
  if [ "$agh_enabled" = 1 ] && [ ! -x "$MP/scripts/adguardhome.sh" ]; then
    echo "AdGuard Home is enabled but its FX lifecycle helper is missing; cache was not cleared" >&2
    return 32
  fi
  a_stop_rc=0; u_stop_rc=0; u_rc=0; a_rc=0; apply_rc=0
  # Restart only the resolver engines that are actually enabled in FX config.
  # Failed stops, ensures or route re-apply must never emit the success marker.
  if [ "$agh_enabled" = 1 ]; then
    sh "$MP/scripts/adguardhome.sh" stop "$MP" "$PG" || a_stop_rc=$?
  fi
  if [ "$forward_enabled" = 1 ]; then
    sh "$MP/scripts/unbound.sh" stop "$MP" "$PG" || u_stop_rc=$?
  fi
  if [ "$forward_enabled" = 1 ]; then
    sh "$MP/scripts/unbound.sh" ensure "$MP" "$PG" >> "$PG/boot.log" 2>&1 || u_rc=$?
  fi
  if [ "$agh_enabled" = 1 ]; then
    sh "$MP/scripts/adguardhome.sh" ensure "$MP" "$PG" >> "$PG/boot.log" 2>&1 || a_rc=$?
  fi
  sh "$MP/scripts/apply.sh" fast >> "$PG/boot.log" 2>&1 || apply_rc=$?
  echo "adguardhome_stop_exit=$a_stop_rc"; echo "unbound_stop_exit=$u_stop_rc"
  echo "unbound_exit=$u_rc"; echo "adguardhome_exit=$a_rc"; echo "apply_exit=$apply_rc"
  [ "$a_stop_rc" -eq 0 ] && [ "$u_stop_rc" -eq 0 ] \
    && [ "$u_rc" -eq 0 ] && [ "$a_rc" -eq 0 ] && [ "$apply_rc" -eq 0 ] || {
      echo "cache refresh incomplete; FX DNS routing was reconciled on a best-effort basis" >&2
      return 31
    }
  echo "cache=flushed"
}
cmd="${1:-list}"
case "$cmd" in
  dns-log-summary)
  [ "$#" -eq 1 ] || exit 2
  if [ "$(pg_get dns_querylog_enabled 0 2>/dev/null)" != "1" ]; then
    echo FXDNSLOG_DISABLED
    exit 0
  fi
  helper="$MP/scripts/yulong-ad-dns-summary.sh"
  [ -x "$helper" ] || { echo "DNS summary helper is not installed" >&2; exit 20; }
  sh "$helper" "$PG/adguardhome/work/data"
  ;;
  dns-log-tail)
  if [ "$(pg_get dns_querylog_enabled 0 2>/dev/null)" != "1" ]; then
    echo FXDNSLOG_DISABLED
    exit 0
  fi
  logfile="$PG/adguardhome/work/data/querylog.json"
  if [ -s "$logfile" ]; then
    tail -n 500 "$logfile"
  else
    echo FXDNSLOG_EMPTY
  fi
  ;;
 cache-flush)
  [ "$#" -eq 1 ] || exit 2
  cache_flush
  ;;
 dns-log-clear)
  dir="$PG/adguardhome/work/data"
  found=0
  for file in "$dir"/querylog.json "$dir"/querylog.json.*; do
    [ -f "$file" ] || continue
    : > "$file" || exit 31
    chmod 600 "$file" 2>/dev/null || :
    found=1
  done
  echo "cleared=$found"
  ;;

 list)
  echo FXYULONGAD1
  echo "AD_MASTER|$(pg_get yulong_ad_filter_enabled 1)"
  pg_list rule|awk -F'|' '$1!=""&&$0!~/^[[:space:]]*#/&&NF>=3{print "RULE|"$1"|"$2"|"($3=="1"?"1":"0")}'
  pg_list domain|awk -F'|' '$1!=""&&$0!~/^[[:space:]]*#/&&NF>=2{print "ALLOW|"$1"|"$2"|" (NF<3||$3=="1"?"1":"0")}'
  pg_list block|awk -F'|' '$1!=""&&$0!~/^[[:space:]]*#/&&NF>=2{print "BLOCK|"$1"|"$2"|" (NF<3||$3=="1"?"1":"0")}'
  for key in dns_engine_adguardhome dns_forward custom_dns global_dns block_quic block_dot block_plain_dns block_ipv6 block_track_domains vpn_external_dns_proxy vpn_external_compat dns_querylog_enabled; do
    default=0
    [ "$key" = "vpn_external_dns_proxy" ] && default=1
    echo "DNS|$key|$(pg_get "$key" "$default")"
  done
  ;;
 rule-add)
  [ "$#" -eq 4 ] && valid_source "$2" && valid_text "$3" && { [ "$4" = 0 ] || [ "$4" = 1 ]; } || exit 2
  with_lock transaction m_rule_add "$2" "$3" "$4" ;;
 rule-set)
  [ "$#" -eq 3 ] && valid_source "$2" && { [ "$3" = 0 ] || [ "$3" = 1 ]; } || exit 2
  with_lock transaction m_rule_set "$2" "$3" ;;
 rule-remove)
  [ "$#" -eq 2 ] && valid_source "$2" || exit 2
  with_lock transaction m_rule_remove "$2" ;;
 rule-set-many)
  [ "$#" -eq 3 ] || { echo "usage: $0 rule-set-many 0|1 base64-source-list" >&2; exit 2; }
  with_lock transaction rule_set_many "$2" "$3" ;;
 rule-add-many)
  [ "$#" -eq 2 ] || { echo "usage: $0 rule-add-many base64-source-name-list" >&2; exit 2; }
  with_lock transaction rule_add_many "$2" ;;
 domain-import-bundle)
  [ "$#" -eq 2 ] || { echo "usage: $0 domain-import-bundle base64-export" >&2; exit 2; }
  with_lock transaction import_domain_bundle "$2" ;;
 allow-add)
  [ "$#" -ge 2 ] && [ "$#" -le 3 ] || exit 2
  d=$(valid_domain "$2") || exit 2; note=$3; [ -n "$note" ] || note="FX 白名单"; valid_text "$note" || exit 2
  with_lock transaction m_allow_add "$d" "$note" ;;
 allow-remove)
  [ "$#" -eq 2 ] || exit 2; d=$(valid_domain "$2") || exit 2
  with_lock transaction m_allow_remove "$d" ;;
 allow-import)
  [ "$#" -eq 2 ] || { echo "usage: $0 allow-import base64-domain-list" >&2; exit 2; }
  with_lock transaction m_allow_import "$2" ;;
 allow-clear-all)
  [ "$#" -eq 1 ] || exit 2
  with_lock transaction domain_clear_all allow ;;
 block-clear-all)
  [ "$#" -eq 1 ] || exit 2
  with_lock transaction domain_clear_all block ;;
 allow-remove-many)
  [ "$#" -eq 2 ] || { echo "usage: $0 allow-remove-many base64-domain-list" >&2; exit 2; }
  with_lock transaction m_allow_remove_many "$2" ;;
 block-import)
  [ "$#" -eq 2 ] || { echo "usage: $0 block-import base64-domain-list" >&2; exit 2; }
  with_lock transaction m_block_import "$2" ;;
 block-remove-many)  [ "$#" -eq 2 ] || { echo "usage: $0 block-remove-many base64-domain-list" >&2; exit 2; }
  with_lock transaction m_block_remove_many "$2" ;;
 block-add)
  [ "$#" -ge 2 ] && [ "$#" -le 3 ] || exit 2
  d=$(valid_domain "$2") || exit 2; note=$3; [ -n "$note" ] || note="FX 黑名单"; valid_text "$note" || exit 2
  with_lock transaction m_block_add "$d" "$note" ;;
 block-remove)
  [ "$#" -eq 2 ] || exit 2; d=$(valid_domain "$2") || exit 2
  with_lock transaction m_block_remove "$d" ;;
 dns-set)
  [ "$#" -eq 3 ] || exit 2
  case "$2" in dns_engine_adguardhome|dns_forward|custom_dns|global_dns|block_quic|block_dot|block_plain_dns|block_ipv6|block_track_domains|vpn_external_dns_proxy|vpn_external_compat|dns_querylog_enabled) ;; *) exit 2 ;; esac
  [ "$3" = 0 ] || [ "$3" = 1 ] || exit 2
  case "$2" in
    dns_engine_adguardhome|dns_forward|vpn_external_dns_proxy|vpn_external_compat)
      [ -x "$MP/scripts/native-dns-settings.sh" ] || {
        echo "native DNS dependency manager is missing" >&2
        exit 20
      }
      MP="$MP" PG="$PG" sh "$MP/scripts/native-dns-settings.sh" set "$2" "$3"
      ;;
    *)
      with_lock transaction m_dns "$2" "$3"
      ;;
  esac ;;
 dns-security-profile-set)
  [ "$#" -eq 3 ] || { echo "usage: $0 dns-security-profile-set nxdomain|refused|custom_ip 0|1" >&2; exit 2; }
  with_lock transaction dns_security_profile_set "$2" "$3"
  ;;
 dns-filter-policy-set)
  [ "$#" -eq 6 ] || { echo "usage: $0 dns-filter-policy-set QUIC DOT PLAIN_DNS IPV6 TRACKING" >&2; exit 2; }
  with_lock transaction dns_filter_policy_set "$2" "$3" "$4" "$5" "$6"
  ;;
 dns-config-set-many)
  [ "$#" -eq 4 ] || { echo "usage: $0 dns-config-set-many CUSTOM GLOBAL FALLBACK (use - to clear)" >&2; exit 2; }
  with_lock transaction dns_config_set_many "$2" "$3" "$4"
  ;;
 dns-config-get)
  dns_config_get
  ;;
 dns-profile-get)
  [ "$#" -eq 1 ] || exit 2
  dns_profile_get
  ;;
 dns-native-set-many)
  [ "$#" -ge 3 ] || { echo "usage: $0 dns-native-set-many KEY 0|1 [KEY 0|1 ...]" >&2; exit 2; }
  [ -x "$MP/scripts/native-dns-settings.sh" ] || { echo "native DNS dependency manager is missing" >&2; exit 20; }
  shift
  MP="$MP" PG="$PG" sh "$MP/scripts/native-dns-settings.sh" set-many "$@"
  ;;
 dns-runtime-status)
  [ "$#" -eq 1 ] || exit 2
  [ -x "$MP/scripts/native-dns-settings.sh" ] || { echo "native DNS dependency manager is missing" >&2; exit 20; }
  MP="$MP" PG="$PG" sh "$MP/scripts/native-dns-settings.sh" status
  ;;
 dns-config-set)
  [ "$#" -eq 3 ] || { echo "usage: $0 dns-config-set custom|global|fallback server[,server...]" >&2; exit 2; }
  servers=$(normalize_dns_csv "$3")
  case "$2" in
    custom)
      section=custom_dns
      valid_dns_csv "$servers" || { echo "custom DNS accepts 1..3 IPv4, https:// DoH, tls:// DoT, or quic:// DoQ endpoints" >&2; exit 2; }
      ;;
    global)
      section=global_dns
      valid_ipv4_dns_csv "$servers" || { echo "global DNS requires 1..3 IPv4 literals" >&2; exit 2; }
      ;;
    fallback)
      section=yulong_dns_fallback
      valid_ipv4_dns_csv "$servers" || { echo "fallback DNS requires 1..3 IPv4 literals" >&2; exit 2; }
      ;;
    *) exit 2 ;;
  esac
  with_lock transaction m_dns_servers "$section" "$servers"
  ;;


 dns-response-get)
  echo FXYULONGDNSRESP1
  mode=$(awk -F= '$1=="mode" {v=$2} $0=="[conf:yulong_dns_response]" {inside=1;next} /^\[/ {inside=0} inside&&$1=="mode" {v=$2} END{print v}' "$CONF" 2>/dev/null)
  case "$mode" in nxdomain|refused|custom_ip) ;; *) mode=nxdomain ;; esac
  echo "mode=$mode"
  ;;
 dns-response-set)
  [ "$#" -eq 2 ] || { echo "usage: $0 dns-response-set nxdomain|refused|custom_ip" >&2; exit 2; }
  case "$2" in nxdomain|refused|custom_ip) ;; *) exit 2 ;; esac
  with_lock transaction m_dns_response "$2"
  ;;

 dns-config-clear)
  [ "$#" -eq 2 ] || { echo "usage: $0 dns-config-clear custom|global|fallback" >&2; exit 2; }
  case "$2" in custom) section=custom_dns ;; global) section=global_dns ;; fallback) section=yulong_dns_fallback ;; *) exit 2 ;; esac
  with_lock transaction m_dns_section_clear "$section"
  ;;

 dns-vpn-set)
  [ "$#" -eq 3 ] || { echo "usage: $0 dns-vpn-set remote_dns|cn_dns ipv4" >&2; exit 2; }
  case "$2" in remote_dns|cn_dns) ;; *) exit 2 ;; esac
  valid_ipv4 "$3" || { echo "VPN DNS must be an IPv4 literal" >&2; exit 2; }
  with_lock transaction m_vpn_dns "$2" "$3"
  ;;
 dns-vpn-set-many)
  [ "$#" -eq 3 ] || { echo "usage: $0 dns-vpn-set-many REMOTE_IPV4 CN_IPV4" >&2; exit 2; }
  with_lock transaction dns_vpn_set_many "$2" "$3"
  ;;
 dns-vpn-reset)
  [ "$#" -eq 1 ] || exit 2
  with_lock transaction m_vpn_dns_reset
  ;;
 schedule-get)
  schedule_get
  ;;
 schedule-set)
  [ "$#" -eq 5 ] || { echo "usage: $0 schedule-set 0|1 HH:MM HH:MM days-csv" >&2; exit 2; }
  with_lock schedule_set "$2" "$3" "$4" "$5"
  ;;
 rootproxy-whitelist-list)
  [ -x "$MP/scripts/yulong-root-proxy.sh" ] || { echo "Root Proxy is not installed" >&2; exit 20; }
  sh "$MP/scripts/yulong-root-proxy.sh" whitelist-list ;;
 rootproxy-whitelist-set)
  [ "$#" -eq 3 ] || { echo "usage: $0 rootproxy-whitelist-set PACKAGE 0|1" >&2; exit 2; }
  [ -x "$MP/scripts/yulong-root-proxy.sh" ] || { echo "Root Proxy is not installed" >&2; exit 20; }
  sh "$MP/scripts/yulong-root-proxy.sh" whitelist-set "$2" "$3" ;;
 rootproxy-status)
  if [ -x "$MP/scripts/yulong-root-proxy.sh" ]; then
    sh "$MP/scripts/yulong-root-proxy.sh" status
  else
    echo "active=0"
    echo "status=not-installed"
  fi ;;

 trusted-status)
  sh "$MP/scripts/yulong-trusted-network.sh" status ;;
 trusted-refresh)
  sh "$MP/scripts/yulong-trusted-network.sh" evaluate >/dev/null
  sh "$MP/scripts/yulong-trusted-network.sh" status ;;
 trusted-ssid-add)
  [ "$#" -eq 2 ] || exit 2
  sh "$MP/scripts/yulong-trusted-network.sh" add "$2" ;;
 trusted-ssid-remove)
  [ "$#" -eq 2 ] || exit 2
  sh "$MP/scripts/yulong-trusted-network.sh" remove "$2" ;;
 trusted-pause-set)
  [ "$#" -eq 2 ] && { [ "$2" = 0 ] || [ "$2" = 1 ]; } || exit 2
  sh "$MP/scripts/yulong-trusted-network.sh" pause-set "$2" ;;

 logs)
  [ -s "$PG/boot.log" ] && tail -n 180 "$PG/boot.log" || echo "暂无日志" ;;
 ad-master)
   [ "$#" -eq 2 ] && { [ "$2" = 0 ] || [ "$2" = 1 ]; } || exit 2
   with_lock transaction m_dns yulong_ad_filter_enabled "$2" ;;
 *) exit 2 ;;
esac