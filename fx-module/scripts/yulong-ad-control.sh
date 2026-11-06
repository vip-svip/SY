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
_yad_set_raw=
_yad_set_clean=
_yad_rule_raw=
_yad_rule_clean=
_yad_rule_add_raw=
_yad_rule_add_clean=
_yad_profile_raw=
_yad_bundle_raw=
_yad_bundle_clean=
_yad_rewrite_raw=
_yad_rewrite_clean=
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
  [ -z "$_yad_set_raw" ] || rm -f "$_yad_set_raw" 2>/dev/null || :
  [ -z "$_yad_set_clean" ] || rm -f "$_yad_set_clean" 2>/dev/null || :
  [ -z "$_yad_rule_raw" ] || rm -f "$_yad_rule_raw" 2>/dev/null || :
  [ -z "$_yad_rule_clean" ] || rm -f "$_yad_rule_clean" 2>/dev/null || :
  [ -z "$_yad_rule_add_raw" ] || rm -f "$_yad_rule_add_raw" 2>/dev/null || :
  [ -z "$_yad_rule_add_clean" ] || rm -f "$_yad_rule_add_clean" 2>/dev/null || :
  [ -z "$_yad_profile_raw" ] || rm -f "$_yad_profile_raw" 2>/dev/null || :
  [ -z "$_yad_bundle_raw" ] || rm -f "$_yad_bundle_raw" 2>/dev/null || :
  [ -z "$_yad_bundle_clean" ] || rm -f "$_yad_bundle_clean" 2>/dev/null || :
  [ -z "$_yad_rewrite_raw" ] || rm -f "$_yad_rewrite_raw" 2>/dev/null || :
  [ -z "$_yad_rewrite_clean" ] || rm -f "$_yad_rewrite_clean" 2>/dev/null || :
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
      for(i=1;i<=4;i++)if($i==""||$i!~/^[0-9]+$/||length($i)>3||$i+0>255||($i!="0"&&$i~/^0/)){bad=1;exit}
      first=$1+0; second=$2+0
      if(first==0||first==127||first>=224||(first==169&&second==254))bad=1
    }
    END{exit bad}
  '
}
normalize_dns_csv() { printf '%s' "$1" | tr -d '[:space:]'; }
valid_ipv4_dns_csv() { valid_ip_dns_csv "$1"; }
valid_fallback_dns_csv() { valid_ip_dns_csv "$1"; }
valid_ip_dns_csv() {
  printf '%s\n' "$1" | awk -F, '
    function valid_ipv4(v,n,a,j,first,second) {
      n=split(v,a,".")
      if(n!=4)return 0
      for(j=1;j<=4;j++)
        if(a[j]==""||a[j]!~/^[0-9]+$/||length(a[j])>3||a[j]+0>255||
           (a[j]!="0"&&a[j]~/^0/))return 0
      first=a[1]+0;second=a[2]+0
      if(v=="0.0.0.0"||v=="255.255.255.255"||first==0||first==127||
         first>=224||(first==169&&second==254))return 0
      return 1
    }
    function valid_ipv6(v,pos,left,right,count,i,n,a,b) {
      if(v=="" || v !~ /^[0-9A-Fa-f:]+$/ || v~/:::/) return 0
      pos=index(v,"::")
      if(pos && index(substr(v,pos+2),"::")) return 0
      count=0
      if(pos) {
        left=substr(v,1,pos-1); right=substr(v,pos+2)
        if(left!="") {
          n=split(left,a,":")
          for(i=1;i<=n;i++) if(a[i]!~/^[0-9A-Fa-f][0-9A-Fa-f]?[0-9A-Fa-f]?[0-9A-Fa-f]?$/) return 0
          count+=n
        }
        if(right!="") {
          n=split(right,b,":")
          for(i=1;i<=n;i++) if(b[i]!~/^[0-9A-Fa-f][0-9A-Fa-f]?[0-9A-Fa-f]?[0-9A-Fa-f]?$/) return 0
          count+=n
        }
        return count<8
      }
      n=split(v,a,":")
      if(n!=8)return 0
      for(i=1;i<=n;i++) if(a[i]!~/^[0-9A-Fa-f][0-9A-Fa-f]?[0-9A-Fa-f]?[0-9A-Fa-f]?$/) return 0
      return 1
    }
    function routable_ipv6(v,words,pos,left,right,n,a,b,i,first,allzero,loopback,last) {
      if(!valid_ipv6(v))return 0
      for(i=1;i<=8;i++)words[i]="0"
      pos=index(v,"::")
      if(pos) {
        left=substr(v,1,pos-1);right=substr(v,pos+2)
        if(left!=""){n=split(left,a,":");for(i=1;i<=n;i++)words[i]=tolower(a[i])}
        if(right!=""){n=split(right,b,":");for(i=1;i<=n;i++)words[9-n+i]=tolower(b[i])}
      } else {
        n=split(v,a,":")
        for(i=1;i<=8;i++)words[i]=tolower(a[i])
      }
      first=words[1]
      if(first~/^fe[89ab]/ || first~/^ff/)return 0
      allzero=1;loopback=1
      for(i=1;i<=8;i++)if(words[i]!~/^0+$/)allzero=0
      for(i=1;i<=7;i++)if(words[i]!~/^0+$/)loopback=0
      last=words[8];sub(/^0+/,"",last)
      if(allzero || (loopback && last=="1"))return 0
      return 1
    }
    function valid_ipv6_port(v,close,host,tail,port) {
      if(substr(v,1,1)!="[")return 0
      close=index(v,"]")
      if(close<3)return 0
      host=substr(v,2,close-2);tail=substr(v,close+1)
      if(!routable_ipv6(host))return 0
      if(tail=="")return 1
      if(substr(tail,1,1)!=":")return 0
      port=substr(tail,2)
      return port~/^[0-9]+$/ && port+0>=1 && port+0<=65535
    }
    function valid_endpoint(v,n,a) {
      if(valid_ipv4(v)||routable_ipv6(v)||valid_ipv6_port(v))return 1
      n=split(v,a,":")
      return n==2&&valid_ipv4(a[1])&&a[2]~/^[0-9]+$/&&a[2]+0>=1&&a[2]+0<=65535
    }
    {
      if(NF<1){bad=1;exit}
      for(i=1;i<=NF;i++)if(!valid_endpoint($i)){bad=1;exit}
    }
    END{exit bad}
  '
}
valid_dns_csv() {
  printf '%s\n' "$1" | awk -F, '
    function ipv4(v, n, a, j, first, second) {
      if(v!~/^[0-9.]+$/) return 0
      n=split(v,a,".")
      if(n!=4) return 0
      for(j=1;j<=4;j++)
        if(a[j]=="" || a[j]!~/^[0-9]+$/ || length(a[j])>3 ||
           a[j]+0>255 || (a[j]!="0" && a[j]~/^0/)) return 0
      first=a[1]+0; second=a[2]+0
      if(v=="0.0.0.0" || v=="255.255.255.255" ||
         first==0 || first==127 || first>=224 ||
         (first==169 && second==254)) return 0
      return 1
    }
    function valid_ipv6(v, pos, left, right, count, i, n, a, b) {
      if(v=="" || v !~ /^[0-9A-Fa-f:]+$/ || v ~ /:::/) return 0
      pos=index(v,"::")
      if(pos && index(substr(v,pos+2),"::")) return 0
      count=0
      if(pos) {
        left=substr(v,1,pos-1); right=substr(v,pos+2)
        if(left!="") {
          n=split(left,a,":")
          for(i=1;i<=n;i++) if(a[i]!~/^[0-9A-Fa-f][0-9A-Fa-f]?[0-9A-Fa-f]?[0-9A-Fa-f]?$/) return 0
          count+=n
        }
        if(right!="") {
          n=split(right,b,":")
          for(i=1;i<=n;i++) if(b[i]!~/^[0-9A-Fa-f][0-9A-Fa-f]?[0-9A-Fa-f]?[0-9A-Fa-f]?$/) return 0
          count+=n
        }
        return count<8
      }
      n=split(v,a,":")
      if(n!=8) return 0
      for(i=1;i<=n;i++) if(a[i]!~/^[0-9A-Fa-f][0-9A-Fa-f]?[0-9A-Fa-f]?[0-9A-Fa-f]?$/) return 0
      return 1
    }
    function valid_ipv6_port(v, close, host, tail, port) {
      if(substr(v,1,1)!="[") return 0
      close=index(v,"]")
      if(close<3) return 0
      host=substr(v,2,close-2); tail=substr(v,close+1)
      if(!valid_ipv6(host)) return 0
      if(tail=="") return 1
      if(substr(tail,1,1)!=":") return 0
      port=substr(tail,2)
      return port~/^[0-9]+$/ && port+0>=1 && port+0<=65535
    }
    function dns_host(v, n, labels, i) {
      if(v~/^[0-9.]+$/) return ipv4(v)
      if(length(v)>253 || substr(v,1,1)=="." || substr(v,length(v),1)==".") return 0
      n=split(v,labels,".")
      for(i=1;i<=n;i++)
        if(length(labels[i])<1 || length(labels[i])>63 ||
           labels[i]!~/^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?$/) return 0
      return 1
    }
    function valid_hostport(v, n, a) {
      if(substr(v,1,1)=="[") return valid_ipv6_port(v)
      n=split(v,a,":")
      if(n==1) return dns_host(a[1])
      if(n==2) return dns_host(a[1]) && a[2]~/^[0-9]+$/ && a[2]+0>=1 && a[2]+0<=65535
      return 0
    }
    function endpoint(v, rest, parts, hostpart, address) {
      if(ipv4(v) || valid_ipv6(v) || valid_ipv6_port(v)) return 1
      # Plain IPv4 upstreams may use a non-standard UDP/TCP port.
      if(split(v,address,":")==2 && ipv4(address[1]) &&
         address[2]~/^[0-9]+$/ && address[2]+0>=1 && address[2]+0<=65535) return 1
      if(substr(v,1,8)=="https://") {
        rest=substr(v,9)
        split(rest,parts,"/")
        hostpart=parts[1]
        if(!valid_hostport(hostpart)) return 0
        slash=index(rest,"/")
        path=slash ? substr(rest,slash) : ""
        return path=="" || path~/^\/[A-Za-z0-9._~!$&()*+,;=:@%/?#-]*$/
      }
      if(substr(v,1,6)=="tls://") return valid_hostport(substr(v,7))
      if(substr(v,1,7)=="quic://") return valid_hostport(substr(v,8))
      return 0
    }
    {
      if(NF<1){bad=1;exit}
      for(i=1;i<=NF;i++) if(!endpoint($i)){bad=1;exit}
    }
    END{exit bad}
  '
}
validate_existing_dns_section() {
  section=$1
  existing=$(awk -v section="$section" '
    BEGIN { inside=0; sections=0; count=0; bad=0 }
    $0=="[conf:" section "]" {
      sections++
      if (inside || sections>1) bad=1
      inside=1
      next
    }
    /^\[/ { inside=0 }
    inside && /^[[:space:]]*#/ { next }
    inside && /^[[:space:]]*$/ { next }
    inside && /^nameserver[[:space:]]+/ {
      value=$0
      sub(/^nameserver[[:space:]]+/, "", value)
      if (value=="" || value ~ /[[:space:]]/) bad=1
      if (seen[value]++) bad=1
      if (count++) printf ","
      printf "%s", value
      next
    }
    inside { bad=1 }
    END {
      if (sections>1 || bad) exit 1
    }
  ' "$CONF") || {
    echo "existing DNS section [$section] is ambiguous or malformed" >&2
    return 22
  }
  case "$section" in
    custom_dns) [ -z "$existing" ] || valid_dns_csv "$existing" ;;
    global_dns) [ -z "$existing" ] || valid_ipv4_dns_csv "$existing" ;;
    yulong_dns_fallback) [ -z "$existing" ] || valid_fallback_dns_csv "$existing" ;;
    *) return 2 ;;
  esac || {
    echo "existing DNS section [$section] contains invalid or unsupported endpoints" >&2
    return 22
  }
}
write_dns_sections_many() {
  _multi_custom=$1; _multi_global=$2; _multi_fallback=$3
  validate_existing_dns_section custom_dns || return $?
  validate_existing_dns_section global_dns || return $?
  validate_existing_dns_section yulong_dns_fallback || return $?
  _multi_tmp=$(mktemp "$CONF.yulong-dns-many.XXXXXX") || return 1
  _yad_conf_tmp=$_multi_tmp
  if ! awk -v custom="$_multi_custom" -v global="$_multi_global" -v fallback="$_multi_fallback" '
    function emit(value, n, a, i) {
      if (value == "-") return
      n=split(value,a,",")
      for(i=1;i<=n;i++) print "nameserver " a[i]
    }
    function finish_section() {
      if (!inside) return
      if (section == "custom_dns") emit(custom)
      else if (section == "global_dns") emit(global)
      else if (section == "yulong_dns_fallback") emit(fallback)
      inside=0; section=""
    }
    BEGIN {
      inside=0; section=""
      seen_custom=0; seen_global=0; seen_fallback=0
    }
    /^\[conf:(custom_dns|global_dns|yulong_dns_fallback)\]$/ {
      finish_section()
      section=$0
      sub(/^\[conf:/,"",section); sub(/\]$/,"",section)
      if (section=="custom_dns") seen_custom=1
      else if (section=="global_dns") seen_global=1
      else seen_fallback=1
      value=(section=="custom_dns" ? custom : (section=="global_dns" ? global : fallback))
      if (value != "-") { print; inside=1 } else inside=1
      next
    }
    /^\[/ {
      finish_section()
      print
      next
    }
    inside { next }
    { print }
    END {
      finish_section()
      if (!seen_custom && custom!="-") { print ""; print "[conf:custom_dns]"; emit(custom) }
      if (!seen_global && global!="-") { print ""; print "[conf:global_dns]"; emit(global) }
      if (!seen_fallback && fallback!="-") { print ""; print "[conf:yulong_dns_fallback]"; emit(fallback) }
    }
  ' "$CONF" > "$_multi_tmp"; then
    rm -f "$_multi_tmp"; _yad_conf_tmp=; return 1
  fi
  if [ -s "$_multi_tmp" ] && chmod 600 "$_multi_tmp" && mv -f "$_multi_tmp" "$CONF"; then
    _yad_conf_tmp=; return 0
  fi
  rm -f "$_multi_tmp"; _yad_conf_tmp=
  return 1
}

write_dns_section() {
  section=$1; servers=$2
  case "$section" in custom_dns|global_dns|yulong_dns_fallback) : ;; *) return 2 ;; esac
  validate_existing_dns_section "$section" || return $?
  tmp=$(mktemp "$CONF.yulong-dns.XXXXXX") || return 1
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
m_dns_section_clear() {
  _clear_dns_section=$1
  remove_dns_section "$_clear_dns_section" || return 1
  case "$_clear_dns_section" in
    custom_dns|global_dns) pg_set "$_clear_dns_section" 0 ;;
    yulong_dns_fallback) return 0 ;;
    *) return 2 ;;
  esac
}


dns_response_values() {
  awk -F= '
    function valid_ipv4(v,n,a,i) {
      n=split(v,a,".")
      if(n!=4)return 0
      for(i=1;i<=4;i++)
        if(a[i]!~/^[0-9]+$/ || length(a[i])>3 || a[i]+0>255 ||
           (a[i]!="0" && a[i]~/^0/))return 0
      return 1
    }
    function valid_ipv6(v,pos,left,right,count,i,n,a,b) {
      if(v=="" || v !~ /^[0-9A-Fa-f:]+$/ || v~/:::/)return 0
      pos=index(v,"::")
      if(pos && index(substr(v,pos+2),"::"))return 0
      count=0
      if(pos) {
        left=substr(v,1,pos-1); right=substr(v,pos+2)
        if(left!="") {
          n=split(left,a,":")
          for(i=1;i<=n;i++)
            if(a[i]!~/^[0-9A-Fa-f][0-9A-Fa-f]?[0-9A-Fa-f]?[0-9A-Fa-f]?$/)return 0
          count+=n
        }
        if(right!="") {
          n=split(right,b,":")
          for(i=1;i<=n;i++)
            if(b[i]!~/^[0-9A-Fa-f][0-9A-Fa-f]?[0-9A-Fa-f]?[0-9A-Fa-f]?$/)return 0
          count+=n
        }
        return count<8
      }
      n=split(v,a,":")
      if(n!=8)return 0
      for(i=1;i<=n;i++)
        if(a[i]!~/^[0-9A-Fa-f][0-9A-Fa-f]?[0-9A-Fa-f]?[0-9A-Fa-f]?$/)return 0
      return 1
    }
    BEGIN {
      inside=0; sections=0; bad=0
      mode_count=0; ipv4_count=0; ipv6_count=0; ttl_count=0
      mode="nxdomain"; ipv4="0.0.0.0"; ipv6="::"; ttl="10"
    }
    $0=="[conf:yulong_dns_response]" {
      sections++
      if(inside || sections>1)bad=1
      inside=1
      next
    }
    /^\[/ {inside=0}
    inside && /^[[:space:]]*#/ {next}
    inside && /^[[:space:]]*$/ {next}
    inside {
      if(index($0,"=")<2){bad=1;next}
      key=substr($0,1,index($0,"=")-1)
      value=substr($0,index($0,"=")+1)
      if(key=="mode") {
        mode_count++; mode=value
        if(value!="nxdomain" && value!="refused" && value!="custom_ip")bad=1
      } else if(key=="blocking_ipv4") {
        ipv4_count++; ipv4=value
        if(!valid_ipv4(value))bad=1
      } else if(key=="blocking_ipv6") {
        ipv6_count++; ipv6=value
        if(!valid_ipv6(value))bad=1
      } else if(key=="blocked_response_ttl") {
        ttl_count++; ttl=value
        if(value!~/^[0-9]+$/ || value+0>4294967295 || int(value+0)!=value+0)bad=1
      } else bad=1
    }
    END {
      if(sections>1 || bad || mode_count>1 || ipv4_count>1 || ipv6_count>1 || ttl_count>1)exit 1
      if(sections>0 && mode_count!=1)exit 1
      printf "mode=%s\nblocking_ipv4=%s\nblocking_ipv6=%s\nblocked_response_ttl=%s\n",mode,ipv4,ipv6,ttl
    }
  ' "$CONF"
}
validate_dns_response_config() {
  dns_response_values >/dev/null
}
write_dns_response_settings() {
  _response_mode=$1; _response_ipv4=$2; _response_ipv6=$3; _response_ttl=$4
  case "$_response_mode" in nxdomain|refused|custom_ip) : ;; *) echo "invalid DNS response mode" >&2; return 2 ;; esac
  valid_dns_rewrite_ipv4 "$_response_ipv4" || { echo "DNS blocking IPv4 address is invalid" >&2; return 2; }
  valid_dns_rewrite_ipv6 "$_response_ipv6" || { echo "DNS blocking IPv6 address is invalid" >&2; return 2; }
  valid_dns_runtime_uint32 "$_response_ttl" 1 || { echo "blocked response TTL must be an unsigned 32-bit integer" >&2; return 2; }
  validate_dns_response_config || {
    echo "existing DNS response-mode section is ambiguous or malformed" >&2
    return 22
  }
  _response_tmp=$(mktemp "$CONF.yulong-dns-response.XXXXXX") || return 1
  _yad_conf_tmp=$_response_tmp
  if ! awk -v mode="$_response_mode" -v ipv4="$_response_ipv4" -v ipv6="$_response_ipv6" -v ttl="$_response_ttl" '
    function emit() {
      print "mode=" mode
      print "blocking_ipv4=" ipv4
      print "blocking_ipv6=" ipv6
      print "blocked_response_ttl=" ttl
    }
    $0=="[conf:yulong_dns_response]" {
      if(seen++)bad=1
      print
      emit()
      inside=1
      written=1
      next
    }
    /^\[/ {inside=0;print;next}
    inside {next}
    {print}
    END {
      if(bad)exit 1
      if(!written){print "";print "[conf:yulong_dns_response]";emit()}
    }
  ' "$CONF" > "$_response_tmp"; then
    rm -f "$_response_tmp"; _yad_conf_tmp=
    echo "unable to stage DNS response settings" >&2
    return 1
  fi
  if [ -s "$_response_tmp" ] && chmod 600 "$_response_tmp" && mv -f "$_response_tmp" "$CONF"; then
    _yad_conf_tmp=
    return 0
  fi
  rm -f "$_response_tmp"; _yad_conf_tmp=
  return 1
}
m_dns_response() {
  _response_current=$(dns_response_values) || return $?
  _response_ipv4=$(printf '%s\n' "$_response_current" | sed -n 's/^blocking_ipv4=//p')
  _response_ipv6=$(printf '%s\n' "$_response_current" | sed -n 's/^blocking_ipv6=//p')
  _response_ttl=$(printf '%s\n' "$_response_current" | sed -n 's/^blocked_response_ttl=//p')
  write_dns_response_settings "$1" "$_response_ipv4" "$_response_ipv6" "$_response_ttl"
}
m_dns_response_config() {
  write_dns_response_settings "$1" "$2" "$3" "$4"
}

dns_config_set_many() {
  _many_custom=$(normalize_dns_csv "$1")
  _many_global=$(normalize_dns_csv "$2")
  _many_fallback=$(normalize_dns_csv "$3")
  if [ "$_many_custom" != "-" ]; then
    valid_dns_csv "$_many_custom" || { echo "custom DNS accepts one or more IPv4, https:// DoH, tls:// DoT, or quic:// DoQ endpoints" >&2; return 2; }
  fi
  if [ "$_many_global" != "-" ]; then
    valid_ipv4_dns_csv "$_many_global" || { echo "global DNS requires routable IPv4/IPv6 literals, optionally with ports" >&2; return 2; }
  fi
  if [ "$_many_fallback" != "-" ]; then
    valid_fallback_dns_csv "$_many_fallback" || { echo "fallback DNS requires routable IPv4/IPv6 literals, optionally with ports" >&2; return 2; }
  fi
  write_dns_sections_many "$_many_custom" "$_many_global" "$_many_fallback" || return 1
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

validate_existing_vpn_dns() {
  awk '
    BEGIN { inside=0; sections=0; remote=0; cn=0; bad=0 }
    $0=="[conf:vpn]" {
      sections++
      if (inside || sections>1) bad=1
      inside=1
      next
    }
    /^\[/ { inside=0 }
    inside && /^remote_dns=/ {
      remote++
      value=substr($0,12)
      if (value !~ /^[0-9.]+$/) bad=1
      n=split(value,a,".")
      if (n!=4) bad=1
      for(i=1;i<=n;i++) if(a[i]=="" || a[i]!~/^[0-9]+$/ || length(a[i])>3 || a[i]+0>255) bad=1
      next
    }
    inside && /^cn_dns=/ {
      cn++
      value=substr($0,8)
      if (value !~ /^[0-9.]+$/) bad=1
      n=split(value,a,".")
      if (n!=4) bad=1
      for(i=1;i<=n;i++) if(a[i]=="" || a[i]!~/^[0-9]+$/ || length(a[i])>3 || a[i]+0>255) bad=1
      next
    }
    END { if (sections>1 || remote>1 || cn>1 || bad) exit 1 }
  ' "$CONF"
}
write_vpn_dns() {
  key=$1; value=$2
  case "$key" in remote_dns|cn_dns) : ;; *) return 2 ;; esac
  valid_ipv4 "$value" || return 2
  validate_existing_vpn_dns || {
    echo "existing VPN DNS section or target keys are ambiguous or malformed" >&2
    return 22
  }
  tmp=$(mktemp "$CONF.yulong-vpn-dns.XXXXXX") || return 1
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
write_vpn_dns_many() {
  _remote_value=$1; _cn_value=$2
  valid_ipv4 "$_remote_value" && valid_ipv4 "$_cn_value" || return 2
  validate_existing_vpn_dns || {
    echo "existing VPN DNS section or target keys are ambiguous or malformed" >&2
    return 22
  }
  _vpn_tmp=$(mktemp "$CONF.yulong-vpn-dns-many.XXXXXX") || return 1
  _yad_conf_tmp=$_vpn_tmp
  if ! awk -v remote="$_remote_value" -v cn="$_cn_value" '
    BEGIN { inside=0; seen=0; remote_written=0; cn_written=0 }
    $0=="[conf:vpn]" {
      if (inside) {
        if (!remote_written) { print "remote_dns=" remote; remote_written=1 }
        if (!cn_written) { print "cn_dns=" cn; cn_written=1 }
      }
      inside=1; seen=1; print; next
    }
    /^\\[/ {
      if (inside) {
        if (!remote_written) { print "remote_dns=" remote; remote_written=1 }
        if (!cn_written) { print "cn_dns=" cn; cn_written=1 }
      }
      inside=0; print; next
    }
    inside && /^remote_dns=/ {
      if (!remote_written) print "remote_dns=" remote
      remote_written=1; next
    }
    inside && /^cn_dns=/ {
      if (!cn_written) print "cn_dns=" cn
      cn_written=1; next
    }
    { print }
    END {
      if (inside) {
        if (!remote_written) print "remote_dns=" remote
        if (!cn_written) print "cn_dns=" cn
      }
      if (!seen) {
        print ""
        print "[conf:vpn]"
        print "remote_dns=" remote
        print "cn_dns=" cn
      }
    }
  ' "$CONF" > "$_vpn_tmp"; then
    rm -f "$_vpn_tmp"; _yad_conf_tmp=; return 1
  fi
  if [ -s "$_vpn_tmp" ] && chmod 600 "$_vpn_tmp" && mv -f "$_vpn_tmp" "$CONF"; then
    _yad_conf_tmp=; return 0
  fi
  rm -f "$_vpn_tmp"; _yad_conf_tmp=
  return 1
}
dns_vpn_set_many() {
  _vpn_remote=$1; _vpn_cn=$2
  valid_ipv4 "$_vpn_remote" || { echo "VPN remote DNS must be an IPv4 literal" >&2; return 2; }
  valid_ipv4 "$_vpn_cn" || { echo "VPN China DNS must be an IPv4 literal" >&2; return 2; }
  write_vpn_dns_many "$_vpn_remote" "$_vpn_cn" || {
    echo "unable to atomically update both VPN DNS values" >&2
    return 1
  }
  echo "vpn_dns=updated remote_dns=$_vpn_remote cn_dns=$_vpn_cn"
}
m_vpn_dns_reset() { write_vpn_dns_many 1.1.1.1 223.5.5.5; }
valid_dns_runtime_duration() {
  _runtime_duration=$1
  case "$_runtime_duration" in
    *ms) _runtime_duration_number=${_runtime_duration%ms}; _runtime_duration_limit=9223372036854 ;;
    *s)  _runtime_duration_number=${_runtime_duration%s};  _runtime_duration_limit=9223372036 ;;
    *m)  _runtime_duration_number=${_runtime_duration%m};  _runtime_duration_limit=153722867 ;;
    *h)  _runtime_duration_number=${_runtime_duration%h};  _runtime_duration_limit=2562047 ;;
    *) return 1 ;;
  esac
  case "$_runtime_duration_number" in ''|*[!0-9]*) return 1 ;; esac
  awk -v n="$_runtime_duration_number" -v limit="$_runtime_duration_limit" '
    BEGIN { if (n+0<1 || n+0>limit || int(n+0)!=(n+0)) exit 1 }
  '
}
valid_dns_runtime_uint32() {
  _uint_value=$1
  _allow_zero=\${2:-0}
  case "$_uint_value" in ''|*[!0-9]*) return 1 ;; esac
  awk -v value="$_uint_value" -v allow_zero="$_allow_zero" '
    BEGIN {
      if (value+0>4294967295 || int(value+0)!=value+0) exit 1
      if (allow_zero=="1" ? value+0<0 : value+0<1) exit 1
    }
  '
}
valid_dns_runtime_answer_ttl() {
  _ttl_value=$1
  valid_dns_runtime_duration "$_ttl_value" || return 1
  awk -v value="$_ttl_value" '
    BEGIN {
      if (value ~ /^[0-9]+ms$/) seconds=substr(value,1,length(value)-2)/1000
      else if (value ~ /^[0-9]+s$/) seconds=substr(value,1,length(value)-1)
      else if (value ~ /^[0-9]+m$/) seconds=substr(value,1,length(value)-1)*60
      else if (value ~ /^[0-9]+h$/) seconds=substr(value,1,length(value)-1)*3600
      else exit 1
      if (seconds<1 || seconds>4294967295) exit 1
    }
  '
}
dns_runtime_values() {
  awk -F= '
    function valid_uint32(value, allow_zero) {
      return value ~ /^[0-9]+$/ && value+0<=4294967295 &&
        int(value+0)==value+0 && (allow_zero ? value+0>=0 : value+0>=1)
    }
    function valid_optimistic_answer_ttl(value, n, seconds) {
      if (value ~ /^[0-9]+ms$/) {
        n=substr(value,1,length(value)-2); seconds=n/1000
      } else if (value ~ /^[0-9]+s$/) {
        n=substr(value,1,length(value)-1); seconds=n
      } else if (value ~ /^[0-9]+m$/) {
        n=substr(value,1,length(value)-1); seconds=n*60
      } else if (value ~ /^[0-9]+h$/) {
        n=substr(value,1,length(value)-1); seconds=n*3600
      } else return 0
      return valid_duration(value) && seconds>=1 && seconds<=4294967295
    }
    function valid_duration(value, n, limit) {
      if (value ~ /^[0-9]+ms$/) {
        n=substr(value,1,length(value)-2); limit=9223372036854
      } else if (value ~ /^[0-9]+s$/) {
        n=substr(value,1,length(value)-1); limit=9223372036
      } else if (value ~ /^[0-9]+m$/) {
        n=substr(value,1,length(value)-1); limit=153722867
      } else if (value ~ /^[0-9]+h$/) {
        n=substr(value,1,length(value)-1); limit=2562047
      } else return 0
      return n ~ /^[0-9]+$/ && n+0>=1 && n+0<=limit && int(n+0)==n+0
    }
    BEGIN {
      mode="load_balance"; fastest="1s"; timeout="10s"; cache_size="4194304";
      cache_ttl_min="0"; cache_ttl_max="0"; optimistic_answer_ttl="30s"; optimistic_max_age="12h";
      cache_enabled="1"; cache_optimistic="0"; dnssec="1";
      inside=0; sections=0; bad=0
    }
    $0=="[conf:yulong_dns_runtime]" { sections++; if(sections>1)bad=1; inside=1; next }
    /^\[/ { inside=0 }
    inside && /^[[:space:]]*#/ { next }
    inside && /^[[:space:]]*$/ { next }
    inside {
      if(index($0,"=")<2){bad=1;next}
      key=substr($0,1,index($0,"=")-1)
      value=substr($0,index($0,"=")+1)
      if(seen[key]++){bad=1;next}
      if(key=="upstream_mode")mode=value
      else if(key=="fastest_timeout")fastest=value
      else if(key=="upstream_timeout")timeout=value
      else if(key=="cache_size")cache_size=value
      else if(key=="cache_ttl_min")cache_ttl_min=value
      else if(key=="cache_ttl_max")cache_ttl_max=value
      else if(key=="cache_optimistic_answer_ttl")optimistic_answer_ttl=value
      else if(key=="cache_optimistic_max_age")optimistic_max_age=value
      else if(key=="cache_enabled")cache_enabled=value
      else if(key=="cache_optimistic")cache_optimistic=value
      else if(key=="enable_dnssec")dnssec=value
      else bad=1
    }
    END {
      if(sections>1 || bad)exit 1
      if(mode!="load_balance" && mode!="parallel" && mode!="fastest_addr")exit 1
      if(!valid_duration(fastest))exit 1
      if(!valid_duration(timeout))exit 1
      if(!valid_uint32(cache_size,0))exit 1
      if(!valid_uint32(cache_ttl_min,1) || !valid_uint32(cache_ttl_max,1) ||
         cache_ttl_min+0>cache_ttl_max+0)exit 1
      if(!valid_optimistic_answer_ttl(optimistic_answer_ttl) ||
         !valid_duration(optimistic_max_age))exit 1
      if(cache_enabled!="0" && cache_enabled!="1")exit 1
      if(cache_optimistic!="0" && cache_optimistic!="1")exit 1
      if(dnssec!="0" && dnssec!="1")exit 1
      print "UPSTREAM_MODE=" mode
      print "FASTEST_TIMEOUT=" fastest
      print "UPSTREAM_TIMEOUT=" timeout
      print "CACHE_SIZE=" cache_size
      print "CACHE_TTL_MIN=" cache_ttl_min
      print "CACHE_TTL_MAX=" cache_ttl_max
      print "CACHE_OPTIMISTIC_ANSWER_TTL=" optimistic_answer_ttl
      print "CACHE_OPTIMISTIC_MAX_AGE=" optimistic_max_age
      print "CACHE_ENABLED=" cache_enabled
      print "CACHE_OPTIMISTIC=" cache_optimistic
      print "ENABLE_DNSSEC=" dnssec
    }
  ' "$CONF"
}
dns_runtime_get() {
  echo FXYULONGDNSRUNTIME1
  dns_runtime_values
}
write_dns_runtime_settings() {
  _runtime_mode=$1; _runtime_fastest=$2; _runtime_timeout=$3
  _runtime_cache_size=$4; _runtime_cache_enabled=$5
  _runtime_cache_optimistic=$6; _runtime_dnssec=$7
  _runtime_cache_ttl_min=$8; _runtime_cache_ttl_max=$9
  _runtime_optimistic_answer_ttl=\${10}; _runtime_optimistic_max_age=\${11}
  case "$_runtime_mode" in load_balance|parallel|fastest_addr) : ;; *) echo "invalid DNS upstream mode" >&2; return 2 ;; esac
  valid_dns_runtime_duration "$_runtime_fastest" || { echo "invalid DNS fastest-address timeout" >&2; return 2; }
  valid_dns_runtime_duration "$_runtime_timeout" || { echo "invalid DNS upstream timeout" >&2; return 2; }
  valid_dns_runtime_uint32 "$_runtime_cache_size" 0 || { echo "DNS cache size must be a positive uint32 byte count" >&2; return 2; }
  valid_dns_runtime_uint32 "$_runtime_cache_ttl_min" 1 &&
    valid_dns_runtime_uint32 "$_runtime_cache_ttl_max" 1 &&
    awk -v min="$_runtime_cache_ttl_min" -v max="$_runtime_cache_ttl_max" 'BEGIN{exit !(min+0<=max+0)}' || {
      echo "DNS cache minimum/maximum TTL must be uint32 seconds with minimum <= maximum" >&2
      return 2
    }
  valid_dns_runtime_answer_ttl "$_runtime_optimistic_answer_ttl" || {
    echo "optimistic cache answer TTL must be at least one second and fit uint32 seconds" >&2
    return 2
  }
  valid_dns_runtime_duration "$_runtime_optimistic_max_age" || {
    echo "optimistic cache maximum age must be a positive duration" >&2
    return 2
  }
  for _runtime_flag in "$_runtime_cache_enabled" "$_runtime_cache_optimistic" "$_runtime_dnssec"; do
    case "$_runtime_flag" in 0|1) : ;; *) echo "DNS runtime flags must be 0 or 1" >&2; return 2 ;; esac
  done
  dns_runtime_values >/dev/null || { echo "existing DNS runtime settings are ambiguous or malformed" >&2; return 22; }
  _runtime_tmp=$(mktemp "$CONF.yulong-dns-runtime.XXXXXX") || return 1
  _yad_conf_tmp=$_runtime_tmp
  if ! awk -v mode="$_runtime_mode" -v fastest="$_runtime_fastest" \
      -v timeout="$_runtime_timeout" -v cache_size="$_runtime_cache_size" \
      -v cache_ttl_min="$_runtime_cache_ttl_min" -v cache_ttl_max="$_runtime_cache_ttl_max" \
      -v optimistic_answer_ttl="$_runtime_optimistic_answer_ttl" -v optimistic_max_age="$_runtime_optimistic_max_age" \
      -v cache_enabled="$_runtime_cache_enabled" -v cache_optimistic="$_runtime_cache_optimistic" \
      -v dnssec="$_runtime_dnssec" '
    function emit() {
      print "upstream_mode=" mode
      print "fastest_timeout=" fastest
      print "upstream_timeout=" timeout
      print "cache_size=" cache_size
      print "cache_ttl_min=" cache_ttl_min
      print "cache_ttl_max=" cache_ttl_max
      print "cache_optimistic_answer_ttl=" optimistic_answer_ttl
      print "cache_optimistic_max_age=" optimistic_max_age
      print "cache_enabled=" cache_enabled
      print "cache_optimistic=" cache_optimistic
      print "enable_dnssec=" dnssec
    }
    $0=="[conf:yulong_dns_runtime]" {
      if(seen++)bad=1
      print
      emit()
      inside=1
      written=1
      next
    }
    /^\[/ {inside=0;print;next}
    inside {next}
    {print}
    END {
      if(bad)exit 1
      if(!written){print "";print "[conf:yulong_dns_runtime]";emit()}
    }
  ' "$CONF" > "$_runtime_tmp"; then
    rm -f "$_runtime_tmp"; _yad_conf_tmp=
    echo "unable to stage DNS runtime settings" >&2
    return 1
  fi
  if [ -s "$_runtime_tmp" ] && chmod 600 "$_runtime_tmp" && mv -f "$_runtime_tmp" "$CONF"; then
    _yad_conf_tmp=
    return 0
  fi
  rm -f "$_runtime_tmp"; _yad_conf_tmp=
  return 1
}
dns_runtime_set() {
  write_dns_runtime_settings "$@" || return $?
  echo "dns_runtime=updated"
}

valid_unbound_cache_size() {
  case "$1" in ''|*[!0-9kKmMgG]*) return 1 ;; esac
  _ub_size_number=$1
  case "$_ub_size_number" in *[kKmMgG]) _ub_size_number=${_ub_size_number%?} ;; esac
  case "$_ub_size_number" in ''|*[!0-9]*) return 1 ;; esac
  return 0
}
unbound_online_cpu_count() {
  _ub_online_cores=$(awk -F, '
    {
      for (i=1; i<=NF; i++) {
        split($i, range, "-")
        first=range[1]+0
        last=(range[2]=="" ? first : range[2]+0)
        if (range[1] ~ /^[0-9]+$/ && last>=first) total+=last-first+1
      }
    }
    END { if (total>0) print total }
  ' /sys/devices/system/cpu/online 2>/dev/null)
  case "$_ub_online_cores" in ''|*[!0-9]*|0)
    _ub_online_cores=$(getconf _NPROCESSORS_ONLN 2>/dev/null | tr -d '[:space:]') ;;
  esac
  case "$_ub_online_cores" in ''|*[!0-9]*|0)
    _ub_online_cores=$(awk '/^processor[[:space:]]*:/ {n++} END {print n+0}' /proc/cpuinfo 2>/dev/null) ;;
  esac
  case "$_ub_online_cores" in ''|*[!0-9]*|0) _ub_online_cores=1 ;; esac
  printf '%s' "$_ub_online_cores"
}
valid_unbound_thread_count() {
  valid_dns_runtime_uint32 "$1" 0 || return 1
  [ "$1" -gt 0 ] 2>/dev/null || return 1
  _ub_available_cores=$(unbound_online_cpu_count)
  awk -v requested="$1" -v available="$_ub_available_cores" 'BEGIN{exit !(requested<=available)}'
}
unbound_runtime_values() {
  awk -F= '
    function valid_uint32(value, allow_zero) {
      return value ~ /^[0-9]+$/ && value+0<=4294967295 &&
        int(value+0)==value+0 && (allow_zero ? value+0>=0 : value+0>=1)
    }
    function valid_cache_size(value, number) {
      if(value !~ /^[0-9]+([kKmMgG])?$/)return 0
      number=value
      sub(/[kKmMgG]$/,"",number)
      return number~/^[0-9]+$/
    }
    BEGIN {
      cache_max_ttl="86400"; cache_min_ttl="0"
      msg_cache_size="8m"; rrset_cache_size="16m"; key_cache_size="4m"; neg_cache_size="2m"
      serve_expired="1"; serve_expired_ttl="86400"
      serve_expired_reply_ttl="30"; serve_expired_client_timeout="1800"
      prefetch="1"; prefetch_key="1"; qname_minimisation="1"; num_threads="1"
      inside=0; sections=0; bad=0
    }
    $0=="[conf:yulong_unbound_runtime]" {sections++; if(sections>1)bad=1; inside=1; next}
    /^\[/ {inside=0}
    inside && /^[[:space:]]*#/ {next}
    inside && /^[[:space:]]*$/ {next}
    inside {
      if(index($0,"=")<2){bad=1;next}
      key=substr($0,1,index($0,"=")-1)
      value=substr($0,index($0,"=")+1)
      if(seen[key]++){bad=1;next}
      if(key=="cache_max_ttl")cache_max_ttl=value
      else if(key=="cache_min_ttl")cache_min_ttl=value
      else if(key=="serve_expired")serve_expired=value
      else if(key=="serve_expired_ttl")serve_expired_ttl=value
      else if(key=="serve_expired_reply_ttl")serve_expired_reply_ttl=value
      else if(key=="serve_expired_client_timeout")serve_expired_client_timeout=value
      else if(key=="prefetch")prefetch=value
      else if(key=="prefetch_key")prefetch_key=value
      else if(key=="qname_minimisation")qname_minimisation=value
      else if(key=="msg_cache_size")msg_cache_size=value
      else if(key=="rrset_cache_size")rrset_cache_size=value
      else if(key=="key_cache_size")key_cache_size=value
      else if(key=="neg_cache_size")neg_cache_size=value
      else if(key=="num_threads")num_threads=value
      else bad=1
    }
    END {
      if(sections>1 || bad)exit 1
      if(!valid_uint32(cache_max_ttl,0) || !valid_uint32(cache_min_ttl,1) ||
         cache_min_ttl+0>cache_max_ttl+0)exit 1
      if(serve_expired!="0" && serve_expired!="1")exit 1
      if(!valid_uint32(serve_expired_ttl,1) ||
         !valid_uint32(serve_expired_reply_ttl,0) ||
         !valid_uint32(serve_expired_client_timeout,1))exit 1
      if(prefetch!="0" && prefetch!="1")exit 1
      if(prefetch_key!="0" && prefetch_key!="1")exit 1
      if(qname_minimisation!="0" && qname_minimisation!="1")exit 1
      if(!valid_cache_size(msg_cache_size) || !valid_cache_size(rrset_cache_size) ||
         !valid_cache_size(key_cache_size) || !valid_cache_size(neg_cache_size))exit 1
      if(!valid_uint32(num_threads,0) || num_threads+0<1)exit 1
      print "UNBOUND_CACHE_MAX_TTL=" cache_max_ttl
      print "UNBOUND_CACHE_MIN_TTL=" cache_min_ttl
      print "UNBOUND_SERVE_EXPIRED=" serve_expired
      print "UNBOUND_SERVE_EXPIRED_TTL=" serve_expired_ttl
      print "UNBOUND_SERVE_EXPIRED_REPLY_TTL=" serve_expired_reply_ttl
      print "UNBOUND_SERVE_EXPIRED_CLIENT_TIMEOUT=" serve_expired_client_timeout
      print "UNBOUND_PREFETCH=" prefetch
      print "UNBOUND_PREFETCH_KEY=" prefetch_key
      print "UNBOUND_QNAME_MINIMISATION=" qname_minimisation
      print "UNBOUND_MSG_CACHE_SIZE=" msg_cache_size
      print "UNBOUND_RRSET_CACHE_SIZE=" rrset_cache_size
      print "UNBOUND_KEY_CACHE_SIZE=" key_cache_size
      print "UNBOUND_NEG_CACHE_SIZE=" neg_cache_size
      print "UNBOUND_NUM_THREADS=" num_threads
    }
  ' "$CONF"
}
unbound_runtime_get() {
  echo FXYULONGUNBOUND1
  unbound_runtime_values || return $?
  printf 'UNBOUND_THREADS_MAX=%s\n' "$(unbound_online_cpu_count)"
}
write_unbound_runtime_settings() {
  _ub_cache_max_ttl=$1
  _ub_cache_min_ttl=$2
  _ub_serve_expired=$3
  _ub_serve_expired_ttl=$4
  _ub_serve_expired_reply_ttl=$5
  _ub_serve_expired_client_timeout=$6
  _ub_prefetch=$7
  _ub_prefetch_key=$8
  _ub_qname_minimisation=$9
  _ub_msg_cache_size=${10}
  _ub_rrset_cache_size=${11}
  _ub_key_cache_size=${12}
  _ub_neg_cache_size=${13}
  _ub_num_threads=${14}

  valid_dns_runtime_uint32 "$_ub_cache_max_ttl" 0 &&
    valid_dns_runtime_uint32 "$_ub_cache_min_ttl" 1 &&
    awk -v min="$_ub_cache_min_ttl" -v max="$_ub_cache_max_ttl" 'BEGIN{exit !(min+0<=max+0)}' || {
      echo "Unbound cache TTL must use uint32 seconds with minimum <= maximum" >&2
      return 2
    }
  case "$_ub_serve_expired" in 0|1) : ;; *) echo "Unbound serve-expired flag must be 0 or 1" >&2; return 2 ;; esac
  valid_dns_runtime_uint32 "$_ub_serve_expired_ttl" 1 || {
    echo "Unbound serve-expired TTL must be uint32 seconds; zero disables its age limit" >&2
    return 2
  }
  valid_dns_runtime_uint32 "$_ub_serve_expired_reply_ttl" 0 || {
    echo "Unbound serve-expired reply TTL must be a positive uint32 seconds value" >&2
    return 2
  }
  valid_dns_runtime_uint32 "$_ub_serve_expired_client_timeout" 1 || {
    echo "Unbound serve-expired client timeout must be uint32 milliseconds" >&2
    return 2
  }
  for _ub_flag in "$_ub_prefetch" "$_ub_prefetch_key" "$_ub_qname_minimisation"; do
    case "$_ub_flag" in 0|1) : ;; *) echo "Unbound runtime flags must be 0 or 1" >&2; return 2 ;; esac
  done
  for _ub_size in "$_ub_msg_cache_size" "$_ub_rrset_cache_size" "$_ub_key_cache_size" "$_ub_neg_cache_size"; do
    valid_unbound_cache_size "$_ub_size" || {
      echo "Unbound cache sizes must be non-negative bytes or a number with k/m/g suffix" >&2
      return 2
    }
  done
  valid_unbound_thread_count "$_ub_num_threads" || {
    echo "Unbound worker threads must be positive and no greater than online CPU cores" >&2
    return 2
  }
  unbound_runtime_values >/dev/null || {
    echo "existing Unbound runtime settings are ambiguous or malformed" >&2
    return 22
  }
  _ub_runtime_tmp=$(mktemp "$CONF.yulong-unbound-runtime.XXXXXX") || return 1
  _yad_conf_tmp=$_ub_runtime_tmp
  if ! awk -v cache_max_ttl="$_ub_cache_max_ttl" -v cache_min_ttl="$_ub_cache_min_ttl" \
      -v serve_expired="$_ub_serve_expired" -v serve_expired_ttl="$_ub_serve_expired_ttl" \
      -v serve_expired_reply_ttl="$_ub_serve_expired_reply_ttl" \
      -v serve_expired_client_timeout="$_ub_serve_expired_client_timeout" \
      -v prefetch="$_ub_prefetch" -v prefetch_key="$_ub_prefetch_key" -v qname_minimisation="$_ub_qname_minimisation" \
      -v msg_cache_size="$_ub_msg_cache_size" -v rrset_cache_size="$_ub_rrset_cache_size" \
      -v key_cache_size="$_ub_key_cache_size" -v neg_cache_size="$_ub_neg_cache_size" \
      -v num_threads="$_ub_num_threads" '
    function emit() {
      print "cache_max_ttl=" cache_max_ttl
      print "cache_min_ttl=" cache_min_ttl
      print "serve_expired=" serve_expired
      print "serve_expired_ttl=" serve_expired_ttl
      print "serve_expired_reply_ttl=" serve_expired_reply_ttl
      print "serve_expired_client_timeout=" serve_expired_client_timeout
      print "prefetch=" prefetch
      print "prefetch_key=" prefetch_key
      print "qname_minimisation=" qname_minimisation
      print "msg_cache_size=" msg_cache_size
      print "rrset_cache_size=" rrset_cache_size
      print "key_cache_size=" key_cache_size
      print "neg_cache_size=" neg_cache_size
      print "num_threads=" num_threads
    }
    $0=="[conf:yulong_unbound_runtime]" {
      if(seen++)bad=1
      print
      emit()
      inside=1
      written=1
      next
    }
    /^\[/ {inside=0;print;next}
    inside {next}
    {print}
    END {
      if(bad)exit 1
      if(!written){print "";print "[conf:yulong_unbound_runtime]";emit()}
    }
  ' "$CONF" > "$_ub_runtime_tmp"; then
    rm -f "$_ub_runtime_tmp"; _yad_conf_tmp=
    echo "unable to stage Unbound runtime settings" >&2
    return 1
  fi
  if [ -s "$_ub_runtime_tmp" ] && chmod 600 "$_ub_runtime_tmp" && mv -f "$_ub_runtime_tmp" "$CONF"; then
    _yad_conf_tmp=
    return 0
  fi
  rm -f "$_ub_runtime_tmp"; _yad_conf_tmp=
  return 1
}
unbound_runtime_set() {
  write_unbound_runtime_settings "$@" || return $?
  echo "unbound_runtime=updated"
}

dns_profile_get() {
  validate_existing_dns_section custom_dns || return $?
  validate_existing_dns_section global_dns || return $?
  validate_existing_dns_section yulong_dns_fallback || return $?
  validate_existing_vpn_dns || return $?
  validate_dns_response_config || {
    echo "DNS profile contains an ambiguous or malformed response-mode section" >&2
    return 22
  }
  _profile_response_record=$(dns_response_values) || return $?
  _profile_mode=$(printf '%s\n' "$_profile_response_record" | sed -n 's/^mode=//p')
  _profile_response_ipv4=$(printf '%s\n' "$_profile_response_record" | sed -n 's/^blocking_ipv4=//p')
  _profile_response_ipv6=$(printf '%s\n' "$_profile_response_record" | sed -n 's/^blocking_ipv6=//p')
  _profile_response_ttl=$(printf '%s\n' "$_profile_response_record" | sed -n 's/^blocked_response_ttl=//p')
  _retention_record=$(dns_querylog_retention_get) || return $?
  case "$_retention_record" in
    querylog_retention=*) _profile_retention=\${_retention_record#querylog_retention=} ;;
    *) echo "DNS query-log retention is unavailable" >&2; return 22 ;;
  esac
  _querylog_runtime_record=$(dns_querylog_runtime_get) || return $?
  _profile_querylog_memory_size=$(printf '%s\n' "$_querylog_runtime_record" | sed -n 's/^memory_size=//p')
  [ -n "$_profile_querylog_memory_size" ] || { echo "DNS query-log buffer size is unavailable" >&2; return 22; }
  _querylog_ignored_record=$(dns_querylog_ignored_values) || { echo "DNS query-log ignored-domain settings are unavailable" >&2; return 22; }
  _profile_querylog_ignored_enabled=$(printf '%s\n' "$_querylog_ignored_record" | sed -n 's/^QUERYLOG_IGNORED_ENABLED=//p')
  _profile_querylog_ignored=$(printf '%s\n' "$_querylog_ignored_record" | sed -n 's/^QUERYLOG_IGNORED=//p')
  [ -n "$_profile_querylog_ignored_enabled" ] || { echo "DNS query-log ignored-domain flag is unavailable" >&2; return 22; }
  _profile_dns_rewrites_rows=$(dns_rewrites_values) || return $?
  _profile_dns_rewrites=$(printf '%s\n' "$_profile_dns_rewrites_rows" | awk 'NF{if(NR>1)printf ",";printf "%s",$0}')
  _statistics_record=$(dns_statistics_values) || { echo "DNS statistics settings are unavailable" >&2; return 22; }
  _profile_statistics_enabled=$(printf '%s\n' "$_statistics_record" | sed -n 's/^STATISTICS_ENABLED=//p')
  _profile_statistics_interval=$(printf '%s\n' "$_statistics_record" | sed -n 's/^STATISTICS_INTERVAL=//p')
  _profile_statistics_ignored_enabled=$(printf '%s\n' "$_statistics_record" | sed -n 's/^STATISTICS_IGNORED_ENABLED=//p')
  _profile_statistics_ignored=$(printf '%s\n' "$_statistics_record" | sed -n 's/^STATISTICS_IGNORED=//p')
  [ -n "$_profile_statistics_enabled" ] && [ -n "$_profile_statistics_interval" ] &&
    [ -n "$_profile_statistics_ignored_enabled" ] || { echo "DNS statistics settings are incomplete" >&2; return 22; }
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
  printf 'RESPONSE_MODE=%s\n' "$_profile_mode"
  printf 'RESPONSE_IPV4=%s\n' "$_profile_response_ipv4"
  printf 'RESPONSE_IPV6=%s\n' "$_profile_response_ipv6"
  printf 'RESPONSE_TTL=%s\n' "$_profile_response_ttl"
  printf 'QUERYLOG_RETENTION=%s\n' "$_profile_retention"
  printf 'QUERYLOG_MEMORY_SIZE=%s\n' "$_profile_querylog_memory_size"
  printf 'QUERYLOG_IGNORED_ENABLED=%s\n' "$_profile_querylog_ignored_enabled"
  printf 'QUERYLOG_IGNORED=%s\n' "$_profile_querylog_ignored"
  printf 'DNS_REWRITES=%s\n' "$_profile_dns_rewrites"
  printf 'STATISTICS_ENABLED=%s\n' "$_profile_statistics_enabled"
  printf 'STATISTICS_INTERVAL=%s\n' "$_profile_statistics_interval"
  printf 'STATISTICS_IGNORED_ENABLED=%s\n' "$_profile_statistics_ignored_enabled"
  printf 'STATISTICS_IGNORED=%s\n' "$_profile_statistics_ignored"
  dns_runtime_values || return $?
  unbound_runtime_values || return $?
}

dns_profile_restore() {
  _profile_encoded=$1
  case "$_profile_encoded" in ''|*[!A-Za-z0-9+/=]*) echo "invalid DNS profile encoding" >&2; return 2 ;; esac
  _yad_profile_raw=$(mktemp "$PG/yulong-dns-profile.XXXXXX") || return 1
  chmod 600 "$_yad_profile_raw" || return 1
  (umask 077; printf '%s' "$_profile_encoded" | base64 -d > "$_yad_profile_raw") || { echo "unable to decode DNS profile" >&2; return 2; }
  _profile_bytes=$(wc -c < "$_yad_profile_raw" | tr -d ' ')
  [ "$(sed -n '1p' "$_yad_profile_raw")" = FXYULONGDNSPROFILE1 ] || { echo "unsupported DNS profile version" >&2; return 2; }
  awk '
    NR==1 {if($0!="FXYULONGDNSPROFILE1")bad=1;next}
    {
      if(index($0,"=")<2 || $0 ~ /\r/){bad=1;next}
      key=substr($0,1,index($0,"=")-1)
      value=substr($0,index($0,"=")+1)
      if(key !~ /^(dns_engine_adguardhome|dns_forward|custom_dns|global_dns|block_quic|block_dot|block_plain_dns|block_ipv6|block_track_domains|vpn_external_dns_proxy|vpn_external_compat|dns_querylog_enabled|CUSTOM_SERVERS|GLOBAL_SERVERS|FALLBACK_SERVERS|VPN_REMOTE|VPN_CN|RESPONSE_MODE|RESPONSE_IPV4|RESPONSE_IPV6|RESPONSE_TTL|QUERYLOG_RETENTION|QUERYLOG_MEMORY_SIZE|QUERYLOG_IGNORED_ENABLED|QUERYLOG_IGNORED|DNS_REWRITES|STATISTICS_ENABLED|STATISTICS_INTERVAL|STATISTICS_IGNORED_ENABLED|STATISTICS_IGNORED|UPSTREAM_MODE|FASTEST_TIMEOUT|UPSTREAM_TIMEOUT|CACHE_SIZE|CACHE_TTL_MIN|CACHE_TTL_MAX|CACHE_OPTIMISTIC_ANSWER_TTL|CACHE_OPTIMISTIC_MAX_AGE|CACHE_ENABLED|CACHE_OPTIMISTIC|ENABLE_DNSSEC|UNBOUND_CACHE_MAX_TTL|UNBOUND_CACHE_MIN_TTL|UNBOUND_SERVE_EXPIRED|UNBOUND_SERVE_EXPIRED_TTL|UNBOUND_SERVE_EXPIRED_REPLY_TTL|UNBOUND_SERVE_EXPIRED_CLIENT_TIMEOUT|UNBOUND_PREFETCH|UNBOUND_PREFETCH_KEY|UNBOUND_QNAME_MINIMISATION|UNBOUND_MSG_CACHE_SIZE|UNBOUND_RRSET_CACHE_SIZE|UNBOUND_KEY_CACHE_SIZE|UNBOUND_NEG_CACHE_SIZE|UNBOUND_NUM_THREADS)$/)bad=1
      if(seen[key]++)bad=1
    }
    END {
      split("dns_engine_adguardhome dns_forward custom_dns global_dns block_quic block_dot block_plain_dns block_ipv6 block_track_domains vpn_external_dns_proxy vpn_external_compat dns_querylog_enabled CUSTOM_SERVERS GLOBAL_SERVERS FALLBACK_SERVERS VPN_REMOTE VPN_CN RESPONSE_MODE", required, " ")
      for (i=1; i<=18; i++) if (!seen[required[i]]) bad=1
      if (bad) exit 1
    }
  ' "$_yad_profile_raw" || { echo "DNS profile has unknown, duplicate, missing, or malformed fields" >&2; return 2; }
  _profile_response_ipv4=0.0.0.0
  _profile_response_ipv6=::
  _profile_response_ttl=10
  _profile_querylog_retention=7d
  _profile_querylog_memory_size=1000
  _profile_querylog_ignored_enabled=0
  _profile_querylog_ignored=
  _profile_dns_rewrites=
  _profile_statistics_enabled=0
  _profile_statistics_interval=10d
  _profile_statistics_ignored_enabled=0
  _profile_statistics_ignored=
  _profile_runtime_mode=load_balance
  _profile_runtime_fastest=1s
  _profile_runtime_timeout=10s
  _profile_runtime_cache_size=4194304
  _profile_runtime_cache_ttl_min=0
  _profile_runtime_cache_ttl_max=0
  _profile_runtime_optimistic_answer_ttl=30s
  _profile_runtime_optimistic_max_age=12h
  _profile_runtime_cache_enabled=1
  _profile_runtime_cache_optimistic=0
  _profile_runtime_dnssec=1
  _profile_unbound_cache_max_ttl=86400
  _profile_unbound_cache_min_ttl=0
  _profile_unbound_serve_expired=1
  _profile_unbound_serve_expired_ttl=86400
  _profile_unbound_serve_expired_reply_ttl=30
  _profile_unbound_serve_expired_client_timeout=1800
  _profile_unbound_prefetch=1
  _profile_unbound_prefetch_key=1
  _profile_unbound_qname_minimisation=1
  _profile_unbound_msg_cache_size=8m
  _profile_unbound_rrset_cache_size=16m
  _profile_unbound_key_cache_size=4m
  _profile_unbound_neg_cache_size=2m
  _profile_unbound_num_threads=1
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
        [ -z "$_profile_fallback" ] || valid_fallback_dns_csv "$_profile_fallback" || { echo "invalid fallback DNS servers" >&2; return 2; }
        ;;
      VPN_REMOTE|VPN_CN)
        valid_ipv4 "$_profile_value" || { echo "invalid VPN DNS address: $_profile_key" >&2; return 2; }
        ;;
      RESPONSE_MODE)
        case "$_profile_value" in nxdomain|refused|custom_ip) : ;; *) echo "invalid DNS response mode" >&2; return 2 ;; esac
        ;;
      RESPONSE_IPV4)
        valid_dns_rewrite_ipv4 "$_profile_value" || { echo "invalid DNS blocking IPv4 address" >&2; return 2; }
        _profile_response_ipv4=$_profile_value
        ;;
      RESPONSE_IPV6)
        valid_dns_rewrite_ipv6 "$_profile_value" || { echo "invalid DNS blocking IPv6 address" >&2; return 2; }
        _profile_response_ipv6=$_profile_value
        ;;
      RESPONSE_TTL)
        valid_dns_runtime_uint32 "$_profile_value" 1 || { echo "invalid blocked DNS response TTL" >&2; return 2; }
        _profile_response_ttl=$_profile_value
        ;;
      QUERYLOG_RETENTION)
        valid_dns_querylog_retention "$_profile_value" || { echo "invalid DNS query-log retention" >&2; return 2; }
        _profile_querylog_retention=$_profile_value
        ;;
      QUERYLOG_MEMORY_SIZE)
        valid_dns_querylog_memory_size "$_profile_value" || { echo "invalid DNS query-log buffer size" >&2; return 2; }
        _profile_querylog_memory_size=$_profile_value
        ;;
      QUERYLOG_IGNORED_ENABLED)
        case "$_profile_value" in 0|1) _profile_querylog_ignored_enabled=$_profile_value ;; *) echo "invalid DNS query-log ignored-domain flag" >&2; return 2 ;; esac
        ;;
      QUERYLOG_IGNORED)
        _profile_querylog_ignored=$(valid_dns_querylog_domains "$_profile_value") || { echo "invalid DNS query-log ignored-domain list" >&2; return 2; }
        ;;
      DNS_REWRITES)
        _profile_dns_rewrites=$_profile_value
        ;;
      STATISTICS_ENABLED)
        case "$_profile_value" in 0|1) _profile_statistics_enabled=$_profile_value ;; *) echo "invalid DNS statistics enabled flag" >&2; return 2 ;; esac
        ;;
      STATISTICS_INTERVAL)
        valid_dns_querylog_retention "$_profile_value" || { echo "invalid DNS statistics interval" >&2; return 2; }
        _profile_statistics_interval=$_profile_value
        ;;
      STATISTICS_IGNORED_ENABLED)
        case "$_profile_value" in 0|1) _profile_statistics_ignored_enabled=$_profile_value ;; *) echo "invalid DNS statistics ignored-domain flag" >&2; return 2 ;; esac
        ;;
      STATISTICS_IGNORED)
        _profile_statistics_ignored=$(valid_dns_statistics_domains "$_profile_value") || { echo "invalid DNS statistics ignored-domain list" >&2; return 2; }
        ;;
      UPSTREAM_MODE)
        case "$_profile_value" in load_balance|parallel|fastest_addr) _profile_runtime_mode=$_profile_value ;; *) echo "invalid DNS upstream mode" >&2; return 2 ;; esac
        ;;
      FASTEST_TIMEOUT)
        valid_dns_runtime_duration "$_profile_value" || { echo "invalid fastest-address timeout" >&2; return 2; }
        _profile_runtime_fastest=$_profile_value
        ;;
      UPSTREAM_TIMEOUT)
        valid_dns_runtime_duration "$_profile_value" || { echo "invalid upstream timeout" >&2; return 2; }
        _profile_runtime_timeout=$_profile_value
        ;;
      CACHE_SIZE)
        valid_dns_runtime_uint32 "$_profile_value" 0 || { echo "invalid DNS cache size" >&2; return 2; }
        _profile_runtime_cache_size=$_profile_value
        ;;
      CACHE_TTL_MIN)
        valid_dns_runtime_uint32 "$_profile_value" 1 || { echo "invalid DNS cache minimum TTL" >&2; return 2; }
        _profile_runtime_cache_ttl_min=$_profile_value
        ;;
      CACHE_TTL_MAX)
        valid_dns_runtime_uint32 "$_profile_value" 1 || { echo "invalid DNS cache maximum TTL" >&2; return 2; }
        _profile_runtime_cache_ttl_max=$_profile_value
        ;;
      CACHE_OPTIMISTIC_ANSWER_TTL)
        valid_dns_runtime_answer_ttl "$_profile_value" || { echo "invalid optimistic answer TTL" >&2; return 2; }
        _profile_runtime_optimistic_answer_ttl=$_profile_value
        ;;
      CACHE_OPTIMISTIC_MAX_AGE)
        valid_dns_runtime_duration "$_profile_value" || { echo "invalid optimistic maximum cache age" >&2; return 2; }
        _profile_runtime_optimistic_max_age=$_profile_value
        ;;
      CACHE_ENABLED)
        case "$_profile_value" in 0|1) _profile_runtime_cache_enabled=$_profile_value ;; *) return 2 ;; esac
        ;;
      CACHE_OPTIMISTIC)
        case "$_profile_value" in 0|1) _profile_runtime_cache_optimistic=$_profile_value ;; *) return 2 ;; esac
        ;;
      ENABLE_DNSSEC)
        case "$_profile_value" in 0|1) _profile_runtime_dnssec=$_profile_value ;; *) return 2 ;; esac
        ;;
      UNBOUND_CACHE_MAX_TTL)
        valid_dns_runtime_uint32 "$_profile_value" 0 || { echo "invalid Unbound maximum cache TTL" >&2; return 2; }
        _profile_unbound_cache_max_ttl=$_profile_value
        ;;
      UNBOUND_CACHE_MIN_TTL)
        valid_dns_runtime_uint32 "$_profile_value" 1 || { echo "invalid Unbound minimum cache TTL" >&2; return 2; }
        _profile_unbound_cache_min_ttl=$_profile_value
        ;;
      UNBOUND_SERVE_EXPIRED)
        case "$_profile_value" in 0|1) _profile_unbound_serve_expired=$_profile_value ;; *) return 2 ;; esac
        ;;
      UNBOUND_SERVE_EXPIRED_TTL)
        valid_dns_runtime_uint32 "$_profile_value" 1 || return 2
        _profile_unbound_serve_expired_ttl=$_profile_value
        ;;
      UNBOUND_SERVE_EXPIRED_REPLY_TTL)
        valid_dns_runtime_uint32 "$_profile_value" 0 || return 2
        _profile_unbound_serve_expired_reply_ttl=$_profile_value
        ;;
      UNBOUND_SERVE_EXPIRED_CLIENT_TIMEOUT)
        valid_dns_runtime_uint32 "$_profile_value" 1 || return 2
        _profile_unbound_serve_expired_client_timeout=$_profile_value
        ;;
      UNBOUND_PREFETCH)
        case "$_profile_value" in 0|1) _profile_unbound_prefetch=$_profile_value ;; *) return 2 ;; esac
        ;;
      UNBOUND_PREFETCH_KEY)
        case "$_profile_value" in 0|1) _profile_unbound_prefetch_key=$_profile_value ;; *) return 2 ;; esac
        ;;
      UNBOUND_QNAME_MINIMISATION)
        case "$_profile_value" in 0|1) _profile_unbound_qname_minimisation=$_profile_value ;; *) return 2 ;; esac
        ;;
      UNBOUND_MSG_CACHE_SIZE)
        valid_unbound_cache_size "$_profile_value" || return 2
        _profile_unbound_msg_cache_size=$_profile_value
        ;;
      UNBOUND_RRSET_CACHE_SIZE)
        valid_unbound_cache_size "$_profile_value" || return 2
        _profile_unbound_rrset_cache_size=$_profile_value
        ;;
      UNBOUND_KEY_CACHE_SIZE)
        valid_unbound_cache_size "$_profile_value" || return 2
        _profile_unbound_key_cache_size=$_profile_value
        ;;
      UNBOUND_NEG_CACHE_SIZE)
        valid_unbound_cache_size "$_profile_value" || return 2
        _profile_unbound_neg_cache_size=$_profile_value
        ;;
      UNBOUND_NUM_THREADS)
        valid_unbound_thread_count "$_profile_value" || { echo "invalid Unbound worker count for this device" >&2; return 2; }
        _profile_unbound_num_threads=$_profile_value
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
      RESPONSE_IPV4|RESPONSE_IPV6|RESPONSE_TTL) : ;;
    esac
  done < "$_yad_profile_raw"
  # An enabled upstream list must be present before any live setting changes.
  # Global DNS still has priority at runtime, but each enabled toggle must be
  # restorable without silently changing the saved switch state.
  if [ "$_profile_global_enabled" = 1 ] && [ -z "$_profile_global" ]; then
    echo "global DNS is enabled in this profile but its upstream list is empty" >&2
    return 2
  fi
  if [ "$_profile_custom_enabled" = 1 ] && [ -z "$_profile_custom" ]; then
    echo "custom DNS is enabled in this profile but its upstream list is empty" >&2
    return 2
  fi
  awk -v min="$_profile_unbound_cache_min_ttl" -v max="$_profile_unbound_cache_max_ttl" 'BEGIN{exit !(min+0<=max+0)}' || {
    echo "Unbound cache minimum TTL exceeds maximum TTL" >&2
    return 2
  }
  # Preserve the native DNS dependency invariants before touching the live config.
  if [ "$_profile_forward" != 1 ]; then _profile_agh=0; _profile_proxy=0; fi
  if [ "$_profile_agh" != 1 ]; then _profile_proxy=0; fi
  if [ "$_profile_compat" != 1 ]; then _profile_proxy=0; fi
  if [ "$_profile_proxy" = 1 ]; then _profile_forward=1; _profile_agh=1; _profile_compat=1; fi
  [ -x "$MP/scripts/native-dns-settings.sh" ] || { echo "native DNS dependency manager is missing" >&2; return 20; }
  MP="$MP" PG="$PG" sh "$MP/scripts/native-dns-settings.sh" set-many-deferred \
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
  write_dns_querylog_retention "$_profile_querylog_retention" || return 1
  write_dns_querylog_runtime "$_profile_querylog_memory_size" || return 1
  write_dns_querylog_ignored_settings "$_profile_querylog_ignored_enabled" "$_profile_querylog_ignored" || return 1
  _profile_dns_rewrites_b64=$(printf '%s' "$_profile_dns_rewrites" | tr ',' '\n' | base64 | tr -d '\n') || return 1
  dns_rewrites_set_many "$_profile_dns_rewrites_b64" || return 1
  write_dns_statistics_settings "$_profile_statistics_enabled" "$_profile_statistics_interval" "$_profile_statistics_ignored_enabled" "$_profile_statistics_ignored" || return 1
  awk -v min="$_profile_runtime_cache_ttl_min" -v max="$_profile_runtime_cache_ttl_max" 'BEGIN{exit !(min+0<=max+0)}' || { echo "DNS profile cache TTL minimum exceeds maximum" >&2; return 2; }
  write_dns_runtime_settings "$_profile_runtime_mode" "$_profile_runtime_fastest" "$_profile_runtime_timeout" "$_profile_runtime_cache_size" "$_profile_runtime_cache_enabled" "$_profile_runtime_cache_optimistic" "$_profile_runtime_dnssec" "$_profile_runtime_cache_ttl_min" "$_profile_runtime_cache_ttl_max" "$_profile_runtime_optimistic_answer_ttl" "$_profile_runtime_optimistic_max_age" || return 1
  write_unbound_runtime_settings "$_profile_unbound_cache_max_ttl" "$_profile_unbound_cache_min_ttl" "$_profile_unbound_serve_expired" "$_profile_unbound_serve_expired_ttl" "$_profile_unbound_serve_expired_reply_ttl" "$_profile_unbound_serve_expired_client_timeout" "$_profile_unbound_prefetch" "$_profile_unbound_prefetch_key" "$_profile_unbound_qname_minimisation" "$_profile_unbound_msg_cache_size" "$_profile_unbound_rrset_cache_size" "$_profile_unbound_key_cache_size" "$_profile_unbound_neg_cache_size" "$_profile_unbound_num_threads" || return 1
  if [ -n "$_profile_custom" ]; then m_dns_servers custom_dns "$_profile_custom" || return 1
  else m_dns_section_clear custom_dns || return 1; fi
  if [ -n "$_profile_global" ]; then m_dns_servers global_dns "$_profile_global" || return 1
  else m_dns_section_clear global_dns || return 1; fi
  if [ -n "$_profile_fallback" ]; then m_dns_servers yulong_dns_fallback "$_profile_fallback" || return 1
  else m_dns_section_clear yulong_dns_fallback || return 1; fi
  m_vpn_dns remote_dns "$_profile_remote" &&
    m_vpn_dns cn_dns "$_profile_cn" &&
    m_dns_response_config "$_profile_mode" "$_profile_response_ipv4" "$_profile_response_ipv6" "$_profile_response_ttl" || return 1
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

valid_dns_querylog_retention() {
  case "$1" in
    *d) _dns_retention_value=${1%d}; _dns_retention_max=365 ;;
    *h) _dns_retention_value=${1%h}; _dns_retention_max=8760 ;;
    *) return 1 ;;
  esac
  case "$_dns_retention_value" in ''|*[!0-9]*) return 1 ;; esac
  awk -v value="$_dns_retention_value" -v maximum="$_dns_retention_max" '
    BEGIN {
      if (value+0<1 || value+0>maximum || int(value+0)!=value+0) exit 1
    }
  '
}
write_dns_querylog_retention() {
  interval=$1
  valid_dns_querylog_retention "$interval" || return 2
  tmp=$(mktemp "$CONF.yulong-querylog-retention.XXXXXX") || return 1
  _yad_conf_tmp=$tmp
  # Validate the existing section before rewriting it. Never collapse duplicate
  # sections/keys or silently discard unknown values during a user mutation.
  if ! awk '
    BEGIN { inside=0; sections=0; intervals=0; bad=0 }
    $0=="[conf:yulong_dns_querylog_retention]" {
      sections++
      if (inside || sections>1) bad=1
      inside=1
      next
    }
    /^\[/ { inside=0 }
    inside && /^[[:space:]]*#/ { next }
    inside && /^[[:space:]]*$/ { next }
    inside && /^interval=/ { intervals++; next }
    inside { bad=1 }
    END { if (sections>1 || intervals>1 || bad) exit 1 }
  ' "$CONF"; then
    rm -f "$tmp"; _yad_conf_tmp=
    echo "existing DNS query-log retention section is ambiguous or malformed" >&2
    return 22
  fi
  if ! awk -v interval="$interval" '
    BEGIN { inside=0; seen=0; written=0 }
    $0=="[conf:yulong_dns_querylog_retention]" {
      inside=1; seen=1; print; next
    }
    /^\[/ {
      if (inside && !written) { print "interval=" interval; written=1 }
      inside=0; print; next
    }
    inside && /^interval=/ {
      if (!written) print "interval=" interval
      written=1; next
    }
    { print }
    END {
      if (inside && !written) print "interval=" interval
      if (!seen) { print ""; print "[conf:yulong_dns_querylog_retention]"; print "interval=" interval }
    }
  ' "$CONF" > "$tmp"; then
    rm -f "$tmp"; _yad_conf_tmp=; return 1
  fi
  if [ -s "$tmp" ] && chmod 600 "$tmp" && mv -f "$tmp" "$CONF"; then _yad_conf_tmp=; return 0; fi
  rm -f "$tmp"; _yad_conf_tmp=; return 1
}
dns_querylog_retention_get() {
  value=$(awk '
    BEGIN { inside=0; sections=0; intervals=0; value=""; bad=0 }
    $0=="[conf:yulong_dns_querylog_retention]" { sections++; inside=1; next }
    /^\[/ { inside=0 }
    inside && /^[[:space:]]*#/ { next }
    inside && /^[[:space:]]*$/ { next }
    inside && /^interval=/ { intervals++; value=substr($0,10); next }
    inside { bad=1 }
    END {
      if (sections>1 || intervals>1 || bad) exit 1
      if (sections==0) { print "7d"; exit }
      if (intervals==1) print value
      else exit 1
    }
  ' "$CONF" 2>/dev/null) || {
    echo "querylog_retention=unknown"
    return 22
  }
  valid_dns_querylog_retention "$value" || {
    echo "querylog_retention=unknown"
    return 22
  }
  echo "querylog_retention=$value"
}
dns_querylog_retention_set() {
  write_dns_querylog_retention "$1" || return $?
  echo "querylog_retention=$1"
}
dns_querylog_memory_limit() {
  _mem_total_kb=$(awk '$1=="MemTotal:" {print $2; exit}' /proc/meminfo 2>/dev/null)
  case "$_mem_total_kb" in
    ''|*[!0-9]*) echo "device physical memory is unavailable; cannot derive a query-log buffer limit" >&2; return 1 ;;
  esac
  _mem_limit=$((_mem_total_kb / 64))
  [ "$_mem_limit" -gt 0 ] || _mem_limit=1
  echo "$_mem_limit"
}
valid_dns_querylog_memory_size() {
  _mem_value=$1
  case "$_mem_value" in ''|*[!0-9]*) return 1 ;; esac
  _mem_limit=$(dns_querylog_memory_limit) || return 1
  awk -v value="$_mem_value" -v maximum="$_mem_limit" '
    BEGIN { if (value+0<0 || value+0>maximum || int(value+0)!=value+0) exit 1 }
  '
}
dns_querylog_runtime_get() {
  _mem_value=$(awk '
    BEGIN { inside=0; sections=0; values=0; value="1000"; bad=0 }
    $0=="[conf:yulong_dns_querylog_runtime]" { sections++; inside=1; next }
    /^\[/ { inside=0 }
    inside && /^[[:space:]]*#/ { next }
    inside && /^[[:space:]]*$/ { next }
    inside && /^memory_size=/ { values++; value=substr($0,13); next }
    inside { bad=1 }
    END { if(sections>1 || values>1 || bad) exit 1; print value }
  ' "$CONF" 2>/dev/null) || {
    echo "querylog_memory_size=unknown"
    return 22
  }
  _mem_limit=$(dns_querylog_memory_limit) || {
    echo "querylog_memory_size=unknown"
    echo "querylog_memory_max=unavailable"
    return 22
  }
  valid_dns_querylog_memory_size "$_mem_value" || {
    echo "querylog_memory_size=unknown"
    return 22
  }
  echo FXYULONGDNSQUERYLOG1
  echo "memory_size=$_mem_value"
  echo "memory_max=$_mem_limit"
}
write_dns_querylog_runtime() {
  _mem_value=$1
  valid_dns_querylog_memory_size "$_mem_value" || {
    echo "query-log memory buffer size exceeds the device-derived safe limit" >&2
    return 2
  }
  _mem_tmp=$(mktemp "$CONF.yulong-querylog-runtime.XXXXXX") || return 1
  _yad_conf_tmp=$_mem_tmp
  if ! awk -v value="$_mem_value" '
    BEGIN { inside=0; sections=0; values=0; written=0; bad=0 }
    $0=="[conf:yulong_dns_querylog_runtime]" {
      sections++
      if(sections>1) {bad=1; next}
      inside=1
      print
      print "memory_size=" value
      written=1
      next
    }
    /^\[/ { inside=0; print; next }
    inside && /^[[:space:]]*#/ { print; next }
    inside && /^[[:space:]]*$/ { print; next }
    inside && /^memory_size=/ { values++; next }
    inside { bad=1; next }
    { print }
    END {
      if(bad || sections>1 || values>1) exit 1
      if(!written) {
        print ""
        print "[conf:yulong_dns_querylog_runtime]"
        print "memory_size=" value
      }
    }
  ' "$CONF" > "$_mem_tmp"; then
    rm -f "$_mem_tmp"; _yad_conf_tmp=
    echo "existing DNS query-log runtime section is ambiguous or malformed" >&2
    return 22
  fi
  if [ -s "$_mem_tmp" ] && chmod 600 "$_mem_tmp" && mv -f "$_mem_tmp" "$CONF"; then
    _yad_conf_tmp=
    return 0
  fi
  rm -f "$_mem_tmp"; _yad_conf_tmp=; return 1
}
dns_querylog_runtime_set() {
  write_dns_querylog_runtime "$1" || return $?
  printf 'memory_size=%s
' "$1"
}
valid_dns_querylog_domains() {
  valid_dns_statistics_domains "$1"
}
dns_querylog_ignored_values() {
  awk -F= '
    function valid_domain(value, n, labels, i) {
      value=tolower(value)
      if (length(value)>253 || value=="" ||
          substr(value,1,1)=="." || substr(value,length(value),1)=="." ||
          value ~ /\.\./ || value !~ /^[a-z0-9.-]+$/) return 0
      n=split(value,labels,".")
      for (i=1;i<=n;i++)
        if (length(labels[i])<1 || length(labels[i])>63 ||
            labels[i]!~/^[a-z0-9]([a-z0-9-]*[a-z0-9])?$/) return 0
      return 1
    }
    BEGIN {
      enabled="0"; ignored=""; inside=0; sections=0; bad=0
      enabled_count=0; ignored_count=0
    }
    $0=="[conf:yulong_dns_querylog_ignored]" {
      sections++
      if (sections>1) bad=1
      inside=1
      next
    }
    /^\[/ {inside=0}
    inside && /^[[:space:]]*#/ {next}
    inside && /^[[:space:]]*$/ {next}
    inside {
      if(index($0,"=")<2){bad=1;next}
      key=substr($0,1,index($0,"=")-1)
      value=substr($0,index($0,"=")+1)
      if(key=="enabled"){enabled_count++; enabled=value}
      else if(key=="ignored"){ignored_count++; ignored=tolower(value)}
      else bad=1
    }
    END {
      if(sections>1 || bad || enabled_count>1 || ignored_count>1)exit 1
      if(enabled!="0" && enabled!="1")exit 1
      if(ignored!="") {
        n=split(ignored,domains,",")
        for(i=1;i<=n;i++) if(!valid_domain(domains[i]) || seen[domains[i]]++)exit 1
      }
      printf "QUERYLOG_IGNORED_ENABLED=%s\nQUERYLOG_IGNORED=%s\n",enabled,ignored
    }
  ' "$CONF" 2>/dev/null
}
dns_querylog_ignored_get() {
  echo FXYULONGDNSQIGNORE1
  dns_querylog_ignored_values
}
write_dns_querylog_ignored_settings() {
  _qlog_ignore_enabled=$1
  _qlog_ignore_domains=$(valid_dns_querylog_domains "$2") || {
    echo "DNS query-log ignored-domain list is malformed or contains duplicates" >&2
    return 2
  }
  case "$_qlog_ignore_enabled" in 0|1) : ;; *) echo "DNS query-log ignored-domain flag must be 0 or 1" >&2; return 2 ;; esac
  dns_querylog_ignored_values >/dev/null || {
    echo "existing DNS query-log ignored-domain settings are ambiguous or malformed" >&2
    return 22
  }
  _qlog_ignore_tmp=$(mktemp "$CONF.yulong-dns-querylog-ignored.XXXXXX") || return 1
  _yad_conf_tmp=$_qlog_ignore_tmp
  if ! awk -v enabled="$_qlog_ignore_enabled" -v ignored="$_qlog_ignore_domains" '
    function emit() {
      print "enabled=" enabled
      print "ignored=" ignored
    }
    $0=="[conf:yulong_dns_querylog_ignored]" {
      if(seen++)bad=1
      print
      emit()
      inside=1
      written=1
      next
    }
    /^\[/ {inside=0;print;next}
    inside {next}
    {print}
    END {
      if(bad)exit 1
      if(!written){print "";print "[conf:yulong_dns_querylog_ignored]";emit()}
    }
  ' "$CONF" > "$_qlog_ignore_tmp"; then
    rm -f "$_qlog_ignore_tmp"; _yad_conf_tmp=
    echo "unable to stage DNS query-log ignored-domain settings" >&2
    return 1
  fi
  if [ -s "$_qlog_ignore_tmp" ] && chmod 600 "$_qlog_ignore_tmp" && mv -f "$_qlog_ignore_tmp" "$CONF"; then
    _yad_conf_tmp=
    return 0
  fi
  rm -f "$_qlog_ignore_tmp"; _yad_conf_tmp=
  return 1
}
dns_querylog_ignored_config_set() {
  write_dns_querylog_ignored_settings "$1" "$2" || return $?
  printf 'querylog_ignored_enabled=%s\n' "$1"
}
valid_dns_rewrite_ipv4() {
  printf '%s\n' "$1" | awk -F. '
    NF!=4 {exit 1}
    {
      for(i=1;i<=4;i++)
        if($i!~/^[0-9]+$/ || length($i)>3 || $i+0>255 ||
           ($i!="0" && $i~/^0/)) exit 1
    }
  '
}
valid_dns_rewrite_ipv6() {
  printf '%s\n' "$1" | awk '
    function valid_ipv6(v,pos,left,right,count,i,n,a,b) {
      if(v=="" || v !~ /^[0-9A-Fa-f:]+$/ || v~/:::/) return 0
      pos=index(v,"::")
      if(pos && index(substr(v,pos+2),"::")) return 0
      count=0
      if(pos) {
        left=substr(v,1,pos-1); right=substr(v,pos+2)
        if(left!="") {
          n=split(left,a,":")
          for(i=1;i<=n;i++) if(a[i]!~/^[0-9A-Fa-f][0-9A-Fa-f]?[0-9A-Fa-f]?[0-9A-Fa-f]?$/) return 0
          count+=n
        }
        if(right!="") {
          n=split(right,b,":")
          for(i=1;i<=n;i++) if(b[i]!~/^[0-9A-Fa-f][0-9A-Fa-f]?[0-9A-Fa-f]?[0-9A-Fa-f]?$/) return 0
          count+=n
        }
        return count<8
      }
      n=split(v,a,":")
      if(n!=8) return 0
      for(i=1;i<=n;i++) if(a[i]!~/^[0-9A-Fa-f][0-9A-Fa-f]?[0-9A-Fa-f]?[0-9A-Fa-f]?$/) return 0
      return 1
    }
    {if(!valid_ipv6($0))exit 1}
  '
}
valid_dns_rewrite_source_domain() {
  _rewrite_source=$1
  case "$_rewrite_source" in
    \*.*)
      _rewrite_suffix=\${_rewrite_source#*.}
      case "$_rewrite_suffix" in *\**) return 1 ;; esac
      [ "\${#_rewrite_source}" -le 253 ] || return 1
      _rewrite_suffix=$(valid_domain "$_rewrite_suffix") || return 1
      printf '*.%s' "$_rewrite_suffix"
      ;;
    *\*) return 1 ;;
    *) valid_domain "$_rewrite_source" ;;
  esac
}
valid_dns_rewrite_answer() {
  _rewrite_answer=$1
  case "$_rewrite_answer" in
    A|a|AAAA|aaaa)
      printf '%s' "$_rewrite_answer" | tr 'a-z' 'A-Z'
      ;;
    *[!0-9.]*)
      case "$_rewrite_answer" in
        *:*)
          valid_dns_rewrite_ipv6 "$_rewrite_answer" || return 1
          printf '%s' "$_rewrite_answer" | tr 'A-F' 'a-f'
          ;;
        *)
          valid_domain "$_rewrite_answer"
          ;;
      esac
      ;;
    *)
      valid_dns_rewrite_ipv4 "$_rewrite_answer" || return 1
      printf '%s' "$_rewrite_answer"
      ;;
  esac
}
dns_rewrites_values() {
  awk -F= '
    function valid_domain(v,n,a,i) {
      v=tolower(v)
      if(v=="" || length(v)>253 || v~/\.\./ || v~/^[.]|[.]$/ || v~/[^a-z0-9.-]/) return 0
      n=split(v,a,".")
      for(i=1;i<=n;i++)
        if(length(a[i])<1 || length(a[i])>63 ||
           a[i]!~/^[a-z0-9]([a-z0-9-]*[a-z0-9])?$/) return 0
      return 1
    }
    function valid_ipv4(v,n,a,i) {
      n=split(v,a,".")
      if(n!=4)return 0
      for(i=1;i<=4;i++)
        if(a[i]!~/^[0-9]+$/ || length(a[i])>3 || a[i]+0>255 ||
           (a[i]!="0" && a[i]~/^0/)) return 0
      return 1
    }
    function valid_ipv6(v,pos,left,right,count,i,n,a,b) {
      if(v=="" || v !~ /^[0-9A-Fa-f:]+$/ || v~/:::/) return 0
      pos=index(v,"::")
      if(pos && index(substr(v,pos+2),"::")) return 0
      count=0
      if(pos) {
        left=substr(v,1,pos-1); right=substr(v,pos+2)
        if(left!="") {
          n=split(left,a,":")
          for(i=1;i<=n;i++) if(a[i]!~/^[0-9A-Fa-f][0-9A-Fa-f]?[0-9A-Fa-f]?[0-9A-Fa-f]?$/) return 0
          count+=n
        }
        if(right!="") {
          n=split(right,b,":")
          for(i=1;i<=n;i++) if(b[i]!~/^[0-9A-Fa-f][0-9A-Fa-f]?[0-9A-Fa-f]?[0-9A-Fa-f]?$/) return 0
          count+=n
        }
        return count<8
      }
      n=split(v,a,":")
      if(n!=8)return 0
      for(i=1;i<=n;i++) if(a[i]!~/^[0-9A-Fa-f][0-9A-Fa-f]?[0-9A-Fa-f]?[0-9A-Fa-f]?$/) return 0
      return 1
    }
    function valid_source_domain(v,suffix) {
      v=tolower(v)
      if(substr(v,1,2)=="*.") {
        suffix=substr(v,3)
        return length(v)<=253 && index(suffix,"*")==0 && valid_domain(suffix)
      }
      if(index(v,"*")) return 0
      return valid_domain(v)
    }
    function valid_answer(v) {
      if(v=="A" || v=="AAAA") return 1
      if(v~/^[0-9.]+$/) return valid_ipv4(v)
      if(v~/^[0-9A-Fa-f:]+$/ && index(v,":")) return valid_ipv6(v)
      return valid_domain(v)
    }
    BEGIN {inside=0; sections=0; bad=0}
    $0=="[conf:yulong_dns_rewrites]" {sections++; if(sections>1)bad=1; inside=1; next}
    /^\[/ {inside=0}
    inside && /^[[:space:]]*#/ {next}
    inside && /^[[:space:]]*$/ {next}
    inside {
      if(substr($0,1,8)!="rewrite="){bad=1;next}
      value=substr($0,9)
      parts=split(value,p,/[|]/)
      host=tolower(p[1]); answer=tolower(p[2])
      if(answer=="a" || answer=="aaaa") answer=toupper(answer)
      if(parts!=2 || !valid_source_domain(host) || !valid_answer(answer) || seen[host]++){bad=1;next}
      print host "|" answer
    }
    END {if(sections>1 || bad)exit 1}
  ' "$CONF" 2>/dev/null
}
dns_rewrites_get() {
  echo FXYULONGDNSRW1
  dns_rewrites_values
}
dns_rewrites_yaml() {
  _rewrite_rows=$(dns_rewrites_values) || {
    echo "DNS rewrite settings are malformed or ambiguous" >&2
    return 22
  }
  [ -n "$_rewrite_rows" ] || return 0
  while IFS='|' read -r _rewrite_domain _rewrite_answer; do
    [ -n "$_rewrite_domain" ] || continue
    printf '    - domain: "%s"\n      answer: "%s"\n' "$_rewrite_domain" "$_rewrite_answer"
  done <<EOF_REWRITE_ROWS
$_rewrite_rows
EOF_REWRITE_ROWS
}
dns_rewrites_set_many() {
  _rewrite_encoded=$1
  case "$_rewrite_encoded" in *[!A-Za-z0-9+/=]*) echo "invalid DNS rewrite list encoding" >&2; return 2 ;; esac
  _yad_rewrite_raw=$(mktemp "$PG/yulong-dns-rewrites.XXXXXX") || return 1
  _yad_rewrite_clean=$(mktemp "$PG/yulong-dns-rewrites-clean.XXXXXX") || return 1
  chmod 600 "$_yad_rewrite_raw" "$_yad_rewrite_clean" || return 1
  (umask 077; printf '%s' "$_rewrite_encoded" | base64 -d > "$_yad_rewrite_raw") || {
    echo "unable to decode DNS rewrite list" >&2
    return 2
  }
  dns_rewrites_values >/dev/null || {
    echo "existing DNS rewrite settings are malformed or ambiguous" >&2
    return 22
  }
  _rewrite_count=0
  while IFS='|' read -r _rewrite_domain _rewrite_answer _rewrite_extra ||
        [ -n "$_rewrite_domain$_rewrite_answer$_rewrite_extra" ]; do
    _rewrite_domain=$(printf '%s' "$_rewrite_domain" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    _rewrite_answer=$(printf '%s' "$_rewrite_answer" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    [ -n "$_rewrite_domain$_rewrite_answer$_rewrite_extra" ] || continue
    [ -z "$_rewrite_extra" ] || { echo "DNS rewrite rows must use domain|answer" >&2; return 2; }
    _rewrite_domain=$(valid_dns_rewrite_source_domain "$_rewrite_domain") || { echo "invalid DNS rewrite source domain or wildcard pattern" >&2; return 2; }
    _rewrite_answer=$(valid_dns_rewrite_answer "$_rewrite_answer") || { echo "invalid DNS rewrite answer for $_rewrite_domain" >&2; return 2; }
    if awk -F'|' -v domain="$_rewrite_domain" '$1==domain{found=1} END{exit !found}' "$_yad_rewrite_clean"; then
      echo "duplicate DNS rewrite source domain: $_rewrite_domain" >&2
      return 2
    fi
    printf '%s|%s\n' "$_rewrite_domain" "$_rewrite_answer" >> "$_yad_rewrite_clean" || return 1
    _rewrite_count=$((_rewrite_count + 1))
  done < "$_yad_rewrite_raw"
  _rewrite_tmp=$(mktemp "$CONF.yulong-dns-rewrites.XXXXXX") || return 1
  _yad_conf_tmp=$_rewrite_tmp
  if ! awk -v rows="$_yad_rewrite_clean" '
    function emit(row) {
      while((getline row < rows)>0) print "rewrite=" row
      close(rows)
    }
    $0=="[conf:yulong_dns_rewrites]" {
      if(seen++)bad=1
      print
      emit()
      inside=1
      written=1
      next
    }
    /^\[/ {inside=0;print;next}
    inside {next}
    {print}
    END {
      if(bad)exit 1
      if(!written){print "";print "[conf:yulong_dns_rewrites]";emit()}
    }
  ' "$CONF" > "$_rewrite_tmp"; then
    rm -f "$_rewrite_tmp"; _yad_conf_tmp=
    echo "unable to stage DNS rewrite settings" >&2
    return 1
  fi
  if [ -s "$_rewrite_tmp" ] && chmod 600 "$_rewrite_tmp" && mv -f "$_rewrite_tmp" "$CONF"; then
    _yad_conf_tmp=
    rm -f "$_yad_rewrite_raw" "$_yad_rewrite_clean"
    _yad_rewrite_raw=; _yad_rewrite_clean=
    echo "dns_rewrites=updated count=$_rewrite_count"
    return 0
  fi
  rm -f "$_rewrite_tmp"; _yad_conf_tmp=
  return 1
}
valid_dns_statistics_domains() {
  printf '%s\n' "$1" | awk -F, '
    function valid_domain(value, n, labels, i) {
      value=tolower(value)
      if (length(value)>253 || value=="" ||
          substr(value,1,1)=="." || substr(value,length(value),1)=="." ||
          value ~ /\.\./ || value !~ /^[a-z0-9.-]+$/) return 0
      n=split(value,labels,".")
      for (i=1;i<=n;i++)
        if (length(labels[i])<1 || length(labels[i])>63 ||
            labels[i]!~/^[a-z0-9]([a-z0-9-]*[a-z0-9])?$/) return 0
      return 1
    }
    {
      if ($0=="") { print ""; exit }
      out=""
      for (i=1;i<=NF;i++) {
        value=tolower($i)
        if (!valid_domain(value) || seen[value]++) exit 1
        if (i>1) out=out ","
        out=out value
      }
      print out
    }
  '
}
dns_statistics_values() {
  awk -F= '
    function valid_domain(value, n, labels, i) {
      value=tolower(value)
      if (length(value)>253 || value=="" ||
          substr(value,1,1)=="." || substr(value,length(value),1)=="." ||
          value ~ /\.\./ || value !~ /^[a-z0-9.-]+$/) return 0
      n=split(value,labels,".")
      for (i=1;i<=n;i++)
        if (length(labels[i])<1 || length(labels[i])>63 ||
            labels[i]!~/^[a-z0-9]([a-z0-9-]*[a-z0-9])?$/) return 0
      return 1
    }
    BEGIN {
      enabled="0"; interval="10d"; ignored_enabled="0"; ignored=""
      inside=0; sections=0; bad=0
      enabled_count=0; interval_count=0; ignored_enabled_count=0; ignored_count=0
    }
    $0=="[conf:yulong_dns_statistics]" {sections++; if(sections>1)bad=1; inside=1; next}
    /^\[/ {inside=0}
    inside && /^[[:space:]]*#/ {next}
    inside && /^[[:space:]]*$/ {next}
    inside {
      if(index($0,"=")<2){bad=1;next}
      key=substr($0,1,index($0,"=")-1)
      value=substr($0,index($0,"=")+1)
      if(key=="enabled"){enabled_count++; enabled=value}
      else if(key=="interval"){interval_count++; interval=value}
      else if(key=="ignored_enabled"){ignored_enabled_count++; ignored_enabled=value}
      else if(key=="ignored"){ignored_count++; ignored=tolower(value)}
      else bad=1
    }
    END {
      if(sections>1 || bad || enabled_count>1 || interval_count>1 ||
         ignored_enabled_count>1 || ignored_count>1)exit 1
      if(enabled!="0" && enabled!="1")exit 1
      if(ignored_enabled!="0" && ignored_enabled!="1")exit 1
      if(interval !~ /^[0-9]+[hd]$/)exit 1
      unit=substr(interval,length(interval),1)
      amount=substr(interval,1,length(interval)-1)
      maximum=(unit=="h"?8760:365)
      if(amount+0<1 || amount+0>maximum || int(amount+0)!=amount+0)exit 1
      if(ignored!="") {
        n=split(ignored,domains,",")
        for(i=1;i<=n;i++) {
          if(!valid_domain(domains[i]) || seen[domains[i]]++)exit 1
        }
      }
      printf "STATISTICS_ENABLED=%s\nSTATISTICS_INTERVAL=%s\nSTATISTICS_IGNORED_ENABLED=%s\nSTATISTICS_IGNORED=%s\n",
        enabled,interval,ignored_enabled,ignored
    }
  ' "$CONF" 2>/dev/null
}
dns_statistics_get() {
  echo FXYULONGDNSSTAT1
  dns_statistics_values
}
write_dns_statistics_settings() {
  _stats_enabled=$1
  _stats_interval=$2
  _stats_ignored_enabled=$3
  _stats_ignored_domains=$(valid_dns_statistics_domains "$4") || {
    echo "DNS statistics ignored-domain list is malformed or contains duplicates" >&2
    return 2
  }
  case "$_stats_enabled" in 0|1) : ;; *) echo "DNS statistics enabled flag must be 0 or 1" >&2; return 2 ;; esac
  case "$_stats_ignored_enabled" in 0|1) : ;; *) echo "DNS statistics ignored-domain flag must be 0 or 1" >&2; return 2 ;; esac
  valid_dns_querylog_retention "$_stats_interval" || {
    echo "DNS statistics interval must be between 1h and 8760h" >&2
    return 2
  }
  dns_statistics_values >/dev/null || {
    echo "existing DNS statistics settings are ambiguous or malformed" >&2
    return 22
  }
  _stats_tmp=$(mktemp "$CONF.yulong-dns-statistics.XXXXXX") || return 1
  _yad_conf_tmp=$_stats_tmp
  if ! awk -v enabled="$_stats_enabled" -v interval="$_stats_interval" \
      -v ignored_enabled="$_stats_ignored_enabled" -v ignored="$_stats_ignored_domains" '
    function emit() {
      print "enabled=" enabled
      print "interval=" interval
      print "ignored_enabled=" ignored_enabled
      print "ignored=" ignored
    }
    $0=="[conf:yulong_dns_statistics]" {
      if(seen++)bad=1
      print
      emit()
      inside=1
      written=1
      next
    }
    /^\[/ {inside=0;print;next}
    inside {next}
    {print}
    END {
      if(bad)exit 1
      if(!written){print "";print "[conf:yulong_dns_statistics]";emit()}
    }
  ' "$CONF" > "$_stats_tmp"; then
    rm -f "$_stats_tmp"; _yad_conf_tmp=
    echo "unable to stage DNS statistics settings" >&2
    return 1
  fi
  if [ -s "$_stats_tmp" ] && chmod 600 "$_stats_tmp" && mv -f "$_stats_tmp" "$CONF"; then
    _yad_conf_tmp=
    return 0
  fi
  rm -f "$_stats_tmp"; _yad_conf_tmp=
  return 1
}
dns_statistics_set() {
  _current_statistics=$(dns_statistics_values) || return $?
  _current_ignored_enabled=$(printf '%s\n' "$_current_statistics" | sed -n 's/^STATISTICS_IGNORED_ENABLED=//p')
  _current_ignored=$(printf '%s\n' "$_current_statistics" | sed -n 's/^STATISTICS_IGNORED=//p')
  write_dns_statistics_settings "$1" "$2" "$_current_ignored_enabled" "$_current_ignored" || return $?
  printf 'statistics_enabled=%s statistics_interval=%s\n' "$1" "$2"
}
dns_statistics_config_set() {
  write_dns_statistics_settings "$1" "$2" "$3" "$4" || return $?
  printf 'statistics_enabled=%s statistics_interval=%s ignored_enabled=%s\n' "$1" "$2" "$3"
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
m_rule_rename(){ old_state=$(pg_list rule|awk -F'|' -v src="$1" '$1==src{print $3;exit}'); [ -n "$old_state" ] || return 3; write_rule "$1" "$2" "$old_state" set; }
m_rule_set(){ old=$(pg_list rule|awk -F'|' -v src="$1" '$1==src{print $2;exit}'); [ -n "$old" ] || return 3; write_rule "$1" "$old" "$2" set; }
m_rule_remove(){ write_rule "$1" "" 0 remove; }
rule_add_many() {
  _add_encoded="$1"
  case "$_add_encoded" in ''|*[!A-Za-z0-9+/=]*) echo "invalid base64 rule import" >&2; return 2 ;; esac
  _add_raw=$(mktemp "$PG/yulong-rule-add.XXXXXX") || return 1
  _yad_rule_add_raw=$_add_raw
  _add_clean=$(mktemp "$PG/yulong-rule-add-clean.XXXXXX") || return 1
  _yad_rule_add_clean=$_add_clean
  chmod 600 "$_add_raw" "$_add_clean" || return 1
  (umask 077; printf '%s' "$_add_encoded" | base64 -d > "$_add_raw") || { echo "unable to decode rule import" >&2; return 2; }
  _add_bytes=$(wc -c < "$_add_raw" | tr -d ' ')
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
  done < "$_add_raw"
  [ "$_add_count" -gt 0 ] || { echo "no rule sources to import" >&2; return 2; }
  while IFS='|' read -r _add_source _add_title; do
    write_rule "$_add_source" "$_add_title" 1 add || { echo "failed to add rule source: $_add_source" >&2; return 1; }
  done < "$_add_clean"
  echo "added=$_add_count"
}
rule_remove_many() {
  _remove_encoded="$1"
  case "$_remove_encoded" in ''|*[!A-Za-z0-9+/=]*) echo "invalid base64 rule source list" >&2; return 2 ;; esac
  _remove_raw=$(mktemp "$PG/yulong-rule-remove.XXXXXX") || return 1
  _yad_rule_remove_raw=$_remove_raw
  _remove_clean=$(mktemp "$PG/yulong-rule-remove-clean.XXXXXX") || return 1
  _yad_rule_remove_clean=$_remove_clean
  chmod 600 "$_remove_raw" "$_remove_clean" || return 1
  (umask 077; printf '%s' "$_remove_encoded" | base64 -d > "$_remove_raw") || { echo "unable to decode rule source list" >&2; return 2; }
  _remove_bytes=$(wc -c < "$_remove_raw" | tr -d ' ')
  _remove_count=0
  while IFS= read -r _remove_source || [ -n "$_remove_source" ]; do
    [ -n "$_remove_source" ] || continue
    valid_source "$_remove_source" || { echo "invalid rule source in batch" >&2; return 2; }
    if ! grep -F -x -q "$_remove_source" "$_remove_clean"; then
      printf '%s\n' "$_remove_source" >> "$_remove_clean" || return 1
      _remove_count=$((_remove_count + 1))
    fi
  done < "$_remove_raw"
  [ "$_remove_count" -gt 0 ] || { echo "no rule sources to remove" >&2; return 2; }
  while IFS= read -r _remove_source; do
    pg_list rule | awk -F'|' -v src="$_remove_source" '$1==src{found=1} END{exit !found}' || {
      echo "rule source is not configured: $_remove_source" >&2
      return 3
    }
  done < "$_remove_clean"
  while IFS= read -r _remove_source; do
    m_rule_remove "$_remove_source" || { echo "failed to remove rule source: $_remove_source" >&2; return 1; }
  done < "$_remove_clean"
  echo "removed=$_remove_count"
}
rule_set_many() {
  _rule_state="$1"; _rule_encoded="$2"
  [ "$_rule_state" = 0 ] || [ "$_rule_state" = 1 ] || return 2
  case "$_rule_encoded" in ''|*[!A-Za-z0-9+/=]*) echo "invalid base64 rule source list" >&2; return 2 ;; esac
  _rule_raw=$(mktemp "$PG/yulong-rule-set.XXXXXX") || return 1
  _yad_rule_raw=$_rule_raw
  _rule_clean=$(mktemp "$PG/yulong-rule-set-clean.XXXXXX") || return 1
  _yad_rule_clean=$_rule_clean
  chmod 600 "$_rule_raw" "$_rule_clean" || return 1
  (umask 077; printf '%s' "$_rule_encoded" | base64 -d > "$_rule_raw") || { echo "unable to decode rule source list" >&2; return 2; }
  _rule_bytes=$(wc -c < "$_rule_raw" | tr -d ' ')
  _rule_count=0
  while IFS= read -r _rule_source || [ -n "$_rule_source" ]; do
    [ -n "$_rule_source" ] || continue
    valid_source "$_rule_source" || { echo "invalid rule source in batch" >&2; return 2; }
    if ! grep -F -x -q "$_rule_source" "$_rule_clean"; then      printf '%s\n' "$_rule_source" >> "$_rule_clean" || return 1
      _rule_count=$((_rule_count + 1))
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
  _yad_bundle_raw=$(mktemp "$PG/yulong-domain-bundle.XXXXXX") || return 1
  _yad_bundle_clean=$(mktemp "$PG/yulong-domain-bundle-clean.XXXXXX") || return 1
  chmod 600 "$_yad_bundle_raw" "$_yad_bundle_clean" || return 1
  (umask 077; printf '%s' "$_bundle_encoded" | base64 -d > "$_yad_bundle_raw") || { echo "unable to decode domain bundle" >&2; return 2; }
  _bundle_bytes=$(wc -c < "$_yad_bundle_raw" | tr -d ' ')
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
  _remove_raw=$(mktemp "$PG/yulong-domain-remove.XXXXXX") || return 1
  _yad_remove_raw=$_remove_raw
  chmod 600 "$_remove_raw" || return 1
  (umask 077; printf '%s' "$_remove_encoded" | base64 -d > "$_remove_raw") || {
    rm -f "$_remove_raw"; _yad_remove_raw=; echo "unable to decode domain removal" >&2; return 2;
  }
  _remove_bytes=$(wc -c < "$_remove_raw" | tr -d ' ')
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
write_allow() {
  domain=$1; note=$2; state=$3; mode=$4
  tmp=$(mktemp "$CONF.yulong-allow.XXXXXX") || return 1
  _yad_conf_tmp=$tmp
  awk -F'|' -v OFS='|' -v domain="$domain" -v note="$note" -v state="$state" -v mode="$mode" '
    BEGIN{inside=0;found=0;done=0}
    $0=="[list:domain]"{inside=1;found=1;print;next}
    /^\\[/{if(inside&&mode=="add"&&!done){print domain,note,state;done=1}inside=0;print;next}
    inside&&$0!~/^[[:space:]]*#/&&tolower($1)==domain{if(mode=="remove")next;if(!done){print domain,note,state;done=1}next}
    {print}
    END{if(inside&&mode=="add"&&!done){print domain,note,state;done=1}if(!found&&mode=="add"){print "";print "[list:domain]";print domain,note,state}if(!done&&mode=="set")exit 3}
  ' "$CONF" > "$tmp" || { rm -f "$tmp"; _yad_conf_tmp=; return 1; }
  if [ -s "$tmp" ] && chmod 600 "$tmp" && mv -f "$tmp" "$CONF"; then _yad_conf_tmp=; return 0; fi
  rm -f "$tmp"; _yad_conf_tmp=; return 1
}
m_allow_add(){ write_allow "$1" "$2" 1 add; }
m_allow_remove(){ write_allow "$1" "" 0 remove; }
m_allow_set(){ old_note=$(pg_list domain|awk -F'|' -v d="$1" '$1==d{print $2;exit}'); [ -n "$old_note" ] || return 3; write_allow "$1" "$old_note" "$2" set; }
m_allow_note(){ old_state=$(pg_list domain|awk -F"|" -v d="$1" '$1==d{print $3;exit}'); [ -n "$old_state" ] || return 3; write_allow "$1" "$2" "$old_state" set; }
m_allow_note_clear(){ old_state=$(pg_list domain|awk -F"|" -v d="$1" '$1==d{print $3;exit}'); [ -n "$old_state" ] || return 3; write_allow "$1" "" "$old_state" set; }
m_allow_import(){ import_domains allow "$1"; }
allow_set_many() {
  _allow_enabled=$1; _allow_encoded=$2
  case "$_allow_enabled" in 0|1) : ;; *) echo "whitelist state must be 0 or 1" >&2; return 2 ;; esac
  case "$_allow_encoded" in ''|*[!A-Za-z0-9+/=]*) echo "invalid base64 whitelist state list" >&2; return 2 ;; esac
  _yad_set_raw=$(mktemp "$PG/yulong-allow-set.XXXXXX") || return 1
  _yad_set_clean=$(mktemp "$PG/yulong-allow-set-clean.XXXXXX") || return 1
  chmod 600 "$_yad_set_raw" "$_yad_set_clean" || return 1
  (umask 077; printf '%s' "$_allow_encoded" | base64 -d > "$_yad_set_raw") || { echo "unable to decode whitelist state list" >&2; return 2; }
  _allow_bytes=$(wc -c < "$_yad_set_raw" | tr -d ' ')
  _allow_count=0
  while IFS= read -r _allow_line || [ -n "$_allow_line" ]; do
    _allow_line=$(printf '%s' "$_allow_line" | tr -d '\\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    [ -n "$_allow_line" ] || continue
    _allow_domain=$(valid_domain "$_allow_line") || { echo "invalid domain in whitelist state list" >&2; return 2; }
    if ! pg_list domain | awk -F'|' -v d="$_allow_domain" '$1==d{found=1} END{exit !found}'; then
      echo "whitelist domain no longer exists: $_allow_domain" >&2; return 3
    fi
    if ! grep -Fxq "$_allow_domain" "$_yad_set_clean"; then
      printf '%s\\n' "$_allow_domain" >> "$_yad_set_clean" || return 1
      _allow_count=$((_allow_count + 1))
    fi
  done < "$_yad_set_raw"
  [ "$_allow_count" -gt 0 ] || { echo "no whitelist domains to update" >&2; return 2; }
  while IFS= read -r _allow_domain; do
    m_allow_set "$_allow_domain" "$_allow_enabled" || { echo "failed to update whitelist domain: $_allow_domain" >&2; return 1; }
  done < "$_yad_set_clean"
  rm -f "$_yad_set_raw" "$_yad_set_clean"; _yad_set_raw=; _yad_set_clean=
  echo "updated=$_allow_count enabled=$_allow_enabled"
}
m_block_note(){ old_state=$(pg_list block|awk -F"|" -v d="$1" '$1==d{print $3;exit}'); [ -n "$old_state" ] || return 3; write_block "$1" "$2" "$old_state" set; }
m_block_note_clear(){ old_state=$(pg_list block|awk -F"|" -v d="$1" '$1==d{print $3;exit}'); [ -n "$old_state" ] || return 3; write_block "$1" "" "$old_state" set; }
m_block_add(){ write_block "$1" "$2" 1 add; }
m_block_set(){ old_note=$(pg_list block|awk -F'|' -v d="$1" '$1==d{print $2;exit}'); [ -n "$old_note" ] || return 3; write_block "$1" "$old_note" "$2" set; }
block_set_many() {
  _set_enabled=$1
  _set_encoded=$2
  case "$_set_enabled" in 0|1) : ;; *) echo "blacklist state must be 0 or 1" >&2; return 2 ;; esac
  case "$_set_encoded" in ''|*[!A-Za-z0-9+/=]*) echo "invalid base64 blacklist state list" >&2; return 2 ;; esac
  _yad_set_raw=$(mktemp "$PG/yulong-block-set.XXXXXX") || return 1
  _yad_set_clean=$(mktemp "$PG/yulong-block-set-clean.XXXXXX") || return 1
  chmod 600 "$_yad_set_raw" "$_yad_set_clean" || return 1
  (umask 077; printf '%s' "$_set_encoded" | base64 -d > "$_yad_set_raw") || { echo "unable to decode blacklist state list" >&2; return 2; }
  _set_bytes=$(wc -c < "$_yad_set_raw" | tr -d ' ')
  _set_count=0
  while IFS= read -r _set_line || [ -n "$_set_line" ]; do
    _set_line=$(printf '%s' "$_set_line" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    [ -n "$_set_line" ] || continue
    _set_domain=$(valid_domain "$_set_line") || { echo "invalid domain in blacklist state list" >&2; return 2; }
    if ! printf '%s\\n' "$(pg_list block)" | awk -F'|' -v d="$_set_domain" '$1==d{found=1} END{exit !found}'; then
      echo "blacklist domain no longer exists: $_set_domain" >&2
      return 3
    fi
    if ! grep -Fxq "$_set_domain" "$_yad_set_clean"; then
      printf '%s\n' "$_set_domain" >> "$_yad_set_clean" || return 1
      _set_count=$((_set_count + 1))
    fi
  done < "$_yad_set_raw"
  [ "$_set_count" -gt 0 ] || { echo "no blacklist domains to update" >&2; return 2; }
  while IFS= read -r _set_domain; do
    m_block_set "$_set_domain" "$_set_enabled" || { echo "failed to update blacklist domain: $_set_domain" >&2; return 1; }
  done < "$_yad_set_clean"
  rm -f "$_yad_set_raw" "$_yad_set_clean"
  _yad_set_raw=; _yad_set_clean=
  echo "updated=$_set_count enabled=$_set_enabled"
}
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
dns_log_summary() {
  if [ "$(pg_get dns_querylog_enabled 0 2>/dev/null)" != "1" ]; then
    echo FXDNSLOG_DISABLED
    return 0
  fi
  helper="$MP/scripts/yulong-ad-dns-summary.sh"
  [ -x "$helper" ] || { echo "DNS summary helper is not installed" >&2; return 20; }
  sh "$helper" "$PG/adguardhome/work/data"
}
dns_log_tail() {
  if [ "$(pg_get dns_querylog_enabled 0 2>/dev/null)" != "1" ]; then
    echo FXDNSLOG_DISABLED
    return 0
  fi
  _dns_log_dir="$PG/adguardhome/work/data"
  [ ! -L "$PG/adguardhome" ] && [ ! -L "$PG/adguardhome/work" ] &&
    [ ! -L "$_dns_log_dir" ] || {
      echo "unsafe DNS query-log path" >&2
      return 21
    }
  [ -d "$_dns_log_dir" ] || { echo FXDNSLOG_EMPTY; return 0; }
  _dns_log_found=0
  for _dns_log_file in "$_dns_log_dir"/querylog.json "$_dns_log_dir"/querylog.json.*; do
    [ -e "$_dns_log_file" ] || [ -L "$_dns_log_file" ] || continue
    [ ! -L "$_dns_log_file" ] && [ -f "$_dns_log_file" ] || {
      echo "refusing to read non-regular or linked DNS query log: $_dns_log_file" >&2
      return 21
    }
    [ -s "$_dns_log_file" ] || continue
    _dns_log_found=1
    cat "$_dns_log_file" || return 31
    printf '\n'
  done
  [ "$_dns_log_found" = 1 ] || echo FXDNSLOG_EMPTY
}
dns_log_clear() {
  dir="$PG/adguardhome/work/data"
  _safe_rest=${dir#/}
  _safe_walk=
  case "$dir" in /*) : ;; *) echo "unsafe DNS query-log directory" >&2; return 21 ;; esac
  while [ -n "$_safe_rest" ]; do
    case "$_safe_rest" in
      */*) _safe_part=${_safe_rest%%/*}; _safe_rest=${_safe_rest#*/} ;;
      *) _safe_part=$_safe_rest; _safe_rest= ;;
    esac
    case "$_safe_part" in ''|.|..) echo "unsafe DNS query-log path" >&2; return 21 ;; esac
    _safe_walk="$_safe_walk/$_safe_part"
    [ ! -L "$_safe_walk" ] || { echo "DNS query-log path contains a symlink" >&2; return 21; }
  done
  [ -d "$dir" ] && [ ! -L "$dir" ] || { echo "DNS query-log directory is missing or unsafe" >&2; return 21; }
  _found=0
  for _file in "$dir"/querylog.json "$dir"/querylog.json.*; do
    [ -e "$_file" ] || [ -L "$_file" ] || continue
    [ ! -L "$_file" ] && [ -f "$_file" ] || {
      echo "refusing to clear non-regular or linked DNS query log: $_file" >&2
      return 21
    }
    _found=$((_found + 1))
  done
  for _file in "$dir"/querylog.json "$dir"/querylog.json.*; do
    [ -e "$_file" ] || [ -L "$_file" ] || continue
    : > "$_file" || { echo "failed to clear DNS query log: $_file" >&2; return 31; }
    chmod 600 "$_file" 2>/dev/null || {
      echo "cannot enforce private DNS query-log permissions: $_file" >&2
      return 31
    }
  done
  echo "cleared=$([ "$_found" -gt 0 ] && echo 1 || echo 0) files=$_found"
}
cache_flush() {
  target=${1:-all}
  case "$target" in all|adguardhome|unbound) ;; *) echo "cache target must be all, adguardhome, or unbound" >&2; return 2 ;; esac
  lock="$PG/yulong-cache-flush.lock"
  if ! mkdir "$lock" 2>/dev/null; then echo "DNS cache refresh is already running" >&2; return 30; fi
  _yad_cache_lock=$lock
  agh_enabled=$(pg_get dns_engine_adguardhome 1 2>/dev/null)
  forward_enabled=$(pg_get dns_forward 1 2>/dev/null)
  if [ "$target" = adguardhome ]; then
    [ "$agh_enabled" = 1 ] || { echo "AdGuard Home is not enabled in FX; no cache was changed" >&2; return 33; }
    forward_enabled=0
  elif [ "$target" = unbound ]; then
    [ "$forward_enabled" = 1 ] || { echo "Unbound is not enabled in FX; no cache was changed" >&2; return 33; }
    agh_enabled=0
  fi
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
  # Restart only the selected FX-owned resolver engines; never touch third-party VPNs.
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
  echo "cache=flushed target=$target"
}
cmd="${1:-list}"
case "$cmd" in
  dns-log-summary)
  [ "$#" -eq 1 ] || exit 2
  with_lock dns_log_summary
  ;;
  dns-log-tail)
  [ "$#" -eq 1 ] || exit 2
  with_lock dns_log_tail
  ;;
 cache-flush)
  [ "$#" -ge 1 ] && [ "$#" -le 2 ] || exit 2
  cache_flush "${2:-all}"
  ;;
 dns-log-clear)
  [ "$#" -eq 1 ] || exit 2
  with_lock dns_log_clear
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
 rule-remove-many)
  [ "$#" -eq 2 ] || { echo "usage: $0 rule-remove-many base64-source-list" >&2; exit 2; }
  with_lock transaction rule_remove_many "$2" ;;
 rule-rename)
  [ "$#" -eq 3 ] && valid_source "$2" && valid_text "$3" || exit 2
  with_lock transaction m_rule_rename "$2" "$3" ;;
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
 allow-note-clear)
  [ "$#" -eq 2 ] || exit 2
  d=$(valid_domain "$2") || exit 2
  with_lock transaction m_allow_note_clear "$d" ;;
 allow-note)
  [ "$#" -eq 3 ] || exit 2
  d=$(valid_domain "$2") || exit 2; valid_text "$3" || exit 2
  with_lock transaction m_allow_note "$d" "$3" ;;
 allow-set)
  [ "$#" -eq 3 ] || exit 2
  d=$(valid_domain "$2") || exit 2
  { [ "$3" = 0 ] || [ "$3" = 1 ]; } || exit 2
  with_lock transaction m_allow_set "$d" "$3" ;;
 allow-set-many)
  [ "$#" -eq 3 ] || { echo "usage: $0 allow-set-many 0|1 base64-domain-list" >&2; exit 2; }
  with_lock transaction allow_set_many "$2" "$3" ;;
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
 block-note-clear)
  [ "$#" -eq 2 ] || exit 2
  d=$(valid_domain "$2") || exit 2
  with_lock transaction m_block_note_clear "$d" ;;
 block-note)
  [ "$#" -eq 3 ] || exit 2
  d=$(valid_domain "$2") || exit 2; valid_text "$3" || exit 2
  with_lock transaction m_block_note "$d" "$3" ;;
 block-set)
  [ "$#" -eq 3 ] || exit 2
  d=$(valid_domain "$2") || exit 2
  { [ "$3" = 0 ] || [ "$3" = 1 ]; } || exit 2
  with_lock transaction m_block_set "$d" "$3" ;;
 block-set-many)
  [ "$#" -eq 3 ] || { echo "usage: $0 block-set-many 0|1 base64-domain-list" >&2; exit 2; }
  with_lock transaction block_set_many "$2" "$3" ;;
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
 dns-querylog-retention-get)
  [ "$#" -eq 1 ] || exit 2
  dns_querylog_retention_get
  ;;
 dns-querylog-retention-set)
  [ "$#" -eq 2 ] || exit 2
  with_lock transaction dns_querylog_retention_set "$2"
  ;;
 dns-querylog-runtime-get)
  [ "$#" -eq 1 ] || exit 2
  dns_querylog_runtime_get
  ;;
 dns-querylog-runtime-set)
  [ "$#" -eq 2 ] || exit 2
  with_lock transaction dns_querylog_runtime_set "$2"
  ;;
 dns-querylog-ignored-get)
  [ "$#" -eq 1 ] || exit 2
  dns_querylog_ignored_get
  ;;
 dns-querylog-ignored-set)
  [ "$#" -eq 3 ] || { echo "usage: $0 dns-querylog-ignored-set 0|1 domain-csv" >&2; exit 2; }
  with_lock transaction dns_querylog_ignored_config_set "$2" "$3"
  ;;
 dns-rewrites-get)
  [ "$#" -eq 1 ] || exit 2
  dns_rewrites_get
  ;;
 dns-rewrites-set)
  [ "$#" -eq 2 ] || { echo "usage: $0 dns-rewrites-set base64-domain-answer-rows" >&2; exit 2; }
  with_lock transaction dns_rewrites_set_many "$2"
  ;;
 dns-rewrites-yaml)
  [ "$#" -eq 1 ] || exit 2
  dns_rewrites_yaml
  ;;
 dns-statistics-get)
  [ "$#" -eq 1 ] || exit 2
  dns_statistics_get
  ;;
 dns-statistics-set)
  [ "$#" -eq 3 ] || { echo "usage: $0 dns-statistics-set 0|1 1h..8760h" >&2; exit 2; }
  with_lock transaction dns_statistics_set "$2" "$3"
  ;;
 dns-statistics-config-set)
  [ "$#" -eq 5 ] || { echo "usage: $0 dns-statistics-config-set 0|1 1h..8760h 0|1 ignored-domains-csv" >&2; exit 2; }
  with_lock transaction dns_statistics_config_set "$2" "$3" "$4" "$5"
  ;;
 dns-runtime-get)
  [ "$#" -eq 1 ] || exit 2
  dns_runtime_get
  ;;
 dns-runtime-set)
  [ "$#" -eq 12 ] || { echo "usage: $0 dns-runtime-set MODE FASTEST_TIMEOUT UPSTREAM_TIMEOUT CACHE_SIZE CACHE_ENABLED CACHE_OPTIMISTIC DNSSEC CACHE_TTL_MIN CACHE_TTL_MAX OPTIMISTIC_ANSWER_TTL OPTIMISTIC_MAX_AGE" >&2; exit 2; }
  shift
  with_lock transaction dns_runtime_set "$@"
  ;;
 unbound-runtime-get)
  [ "$#" -eq 1 ] || exit 2
  unbound_runtime_get
  ;;
 unbound-runtime-set)
  [ "$#" -eq 15 ] || { echo "usage: $0 unbound-runtime-set CACHE_MAX_TTL CACHE_MIN_TTL SERVE_EXPIRED SERVE_EXPIRED_TTL REPLY_TTL CLIENT_TIMEOUT_MS PREFETCH PREFETCH_KEY QNAME_MINIMISATION MSG_CACHE_SIZE RRSET_CACHE_SIZE KEY_CACHE_SIZE NEG_CACHE_SIZE NUM_THREADS" >&2; exit 2; }
  shift
  with_lock transaction unbound_runtime_set "$@"
  ;;
 unbound-anchor-status)
  [ "$#" -eq 1 ] || exit 2
  [ -x "$MP/scripts/unbound.sh" ] || { echo "Unbound lifecycle script is missing" >&2; exit 20; }
  MP="$MP" PG="$PG" sh "$MP/scripts/unbound.sh" anchor-status "$MP" "$PG"
  ;;
 unbound-root-hints-refresh)
  [ "$#" -eq 1 ] || exit 2
  [ -x "$MP/scripts/unbound.sh" ] || { echo "Unbound lifecycle script is missing" >&2; exit 20; }
  MP="$MP" PG="$PG" sh "$MP/scripts/unbound.sh" root-hints-refresh "$MP" "$PG"
  ;;
 unbound-anchor-refresh)
  [ "$#" -eq 1 ] || exit 2
  [ -x "$MP/scripts/unbound.sh" ] || { echo "Unbound lifecycle script is missing" >&2; exit 20; }
  MP="$MP" PG="$PG" sh "$MP/scripts/unbound.sh" anchor-refresh "$MP" "$PG"
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
 dns-diagnose)
  [ "$#" -eq 1 ] || exit 2
  [ -x "$MP/scripts/native-dns-settings.sh" ] || { echo "native DNS dependency manager is missing" >&2; exit 20; }
  _diag_status=$(MP="$MP" PG="$PG" sh "$MP/scripts/native-dns-settings.sh" status 2>/dev/null) || {
    echo "unable to obtain native DNS status" >&2
    exit 20
  }
  [ "$(printf '%s\n' "$_diag_status" | sed -n '1p')" = FXDNS1 ] || {
    echo "native DNS status response is malformed" >&2
    exit 21
  }
  _diag_value() {
    printf '%s\n' "$1" | awk -F'|' -v wanted="$2" '
      $1==wanted {count++; value=$2}
      END {if(count==1) print value; else exit 1}
    '
  }
  _diag_forward=$(_diag_value "$_diag_status" dns_forward 2>/dev/null) || _diag_forward=unknown
  _diag_agh=$(_diag_value "$_diag_status" dns_engine_adguardhome 2>/dev/null) || _diag_agh=unknown
  _diag_ready=$(_diag_value "$_diag_status" dns_stack_ready 2>/dev/null) || _diag_ready=unknown
  _diag_reason=$(_diag_value "$_diag_status" dns_stack_readiness_reason 2>/dev/null) || _diag_reason=unknown
  _diag_watchdog=$(_diag_value "$_diag_status" localdns_watchdog 2>/dev/null) || _diag_watchdog=unknown
  _diag_coexist=$(_diag_value "$_diag_status" vpn_coexistence_verdict 2>/dev/null) || _diag_coexist=unknown
  _diag_route=$(_diag_value "$_diag_status" vpn_route_probe 2>/dev/null) || _diag_route=unknown
  _diag_private_dns=$(_diag_value "$_diag_status" private_dns_mode 2>/dev/null) || _diag_private_dns=unknown
  case "$_diag_ready" in 0|1) : ;; *) _diag_ready=unknown ;; esac
  case "$_diag_reason" in ''|*[!A-Za-z0-9_.:-]*) _diag_reason=unknown ;; esac
  case "$_diag_watchdog" in running|stopped|invalid|unsafe|identity_unknown|unknown|unavailable) : ;; *) _diag_watchdog=unknown ;; esac
  case "$_diag_coexist" in compatible|incompatible|unknown) : ;; *) _diag_coexist=unknown ;; esac
  case "$_diag_route" in passed|failed|unavailable|not_applicable|unknown) : ;; *) _diag_route=unknown ;; esac
  case "$_diag_private_dns" in off|opportunistic|hostname|unknown) : ;; *) _diag_private_dns=unknown ;; esac
  _diag_probe="$MP/engines/unbound/fx-dns-probe"
  _diag_probe_available=0
  if [ -f "$_diag_probe" ] && [ -x "$_diag_probe" ] && [ ! -L "$_diag_probe" ]; then
    _diag_probe_available=1
  fi
  _diag_unbound_process=disabled
  _diag_unbound_probe=disabled
  if [ "$_diag_forward" = 1 ] || [ "$_diag_agh" = 1 ]; then
    _diag_unbound_raw=$(MP="$MP" PG="$PG" sh "$MP/scripts/unbound.sh" status "$MP" "$PG" 2>/dev/null || :)
    case "$_diag_unbound_raw" in
      ready) _diag_unbound_process=ready ;;
      running-unhealthy) _diag_unbound_process=running_unhealthy ;;
      stopped) _diag_unbound_process=stopped ;;
      *) _diag_unbound_process=unknown ;;
    esac
    if [ "$_diag_probe_available" = 1 ]; then
      if "$_diag_probe" 127.0.0.1 5353 5 >/dev/null 2>&1; then
        _diag_unbound_probe=passed
      else
        _diag_unbound_probe=failed
      fi
    else
      _diag_unbound_probe=unavailable
    fi
  fi
  _diag_agh_process=disabled
  _diag_agh_ipv4=disabled
  _diag_agh_ipv6=disabled
  if [ "$_diag_agh" = 1 ]; then
    _diag_agh_raw=$(MP="$MP" PG="$PG" sh "$MP/scripts/adguardhome.sh" status "$MP" "$PG" 2>/dev/null || :)
    case "$_diag_agh_raw" in
      ready) _diag_agh_process=ready ;;
      running-unhealthy) _diag_agh_process=running_unhealthy ;;
      stopped) _diag_agh_process=stopped ;;
      *) _diag_agh_process=unknown ;;
    esac
    if [ "$_diag_probe_available" = 1 ]; then
      if "$_diag_probe" 127.0.0.1 53 5 >/dev/null 2>&1; then
        _diag_agh_ipv4=passed
      else
        _diag_agh_ipv4=failed
      fi
      if "$_diag_probe" ::1 53 5 >/dev/null 2>&1; then
        _diag_agh_ipv6=passed
      else
        _diag_agh_ipv6=failed
      fi
    else
      _diag_agh_ipv4=unavailable
      _diag_agh_ipv6=unavailable
    fi
  fi
  _diag_upstream_mode=$(_diag_value "$_diag_status" dns_upstream_mode 2>/dev/null) || _diag_upstream_mode=unknown
  _diag_upstream_state=$(_diag_value "$_diag_status" dns_upstream_state 2>/dev/null) || _diag_upstream_state=unknown
  _diag_bootstrap_mode=$(_diag_value "$_diag_status" dns_bootstrap_mode 2>/dev/null) || _diag_bootstrap_mode=unknown
  _diag_fallback_mode=$(_diag_value "$_diag_status" dns_fallback_mode 2>/dev/null) || _diag_fallback_mode=unknown
  _diag_rootproxy_cleanup=$(_diag_value "$_diag_status" rootproxy_cleanup 2>/dev/null) || _diag_rootproxy_cleanup=unknown
  case "$_diag_rootproxy_cleanup" in complete|failed|not_required) : ;; *) _diag_rootproxy_cleanup=unknown ;; esac
  _diag_querylog_ignored_enabled=$(_diag_value "$_diag_status" dns_querylog_ignored_enabled 2>/dev/null) || _diag_querylog_ignored_enabled=unknown
  _diag_querylog_ignored_count=$(_diag_value "$_diag_status" dns_querylog_ignored_count 2>/dev/null) || _diag_querylog_ignored_count=unknown
  _diag_statistics_ignored_enabled=$(_diag_value "$_diag_status" dns_statistics_ignored_enabled 2>/dev/null) || _diag_statistics_ignored_enabled=unknown
  _diag_statistics_ignored_count=$(_diag_value "$_diag_status" dns_statistics_ignored_count 2>/dev/null) || _diag_statistics_ignored_count=unknown
  case "$_diag_querylog_ignored_enabled" in 0|1|unknown) : ;; *) _diag_querylog_ignored_enabled=unknown ;; esac
  case "$_diag_statistics_ignored_enabled" in 0|1|unknown) : ;; *) _diag_statistics_ignored_enabled=unknown ;; esac
  case "$_diag_querylog_ignored_count" in ''|*[!0-9]*) _diag_querylog_ignored_count=unknown ;; esac
  case "$_diag_statistics_ignored_count" in ''|*[!0-9]*) _diag_statistics_ignored_count=unknown ;; esac
  _diag_response_mode=unknown
  _diag_response_ipv4=unknown
  _diag_response_ipv6=unknown
  _diag_response_ttl=unknown
  if _diag_response_raw=$(dns_response_values 2>/dev/null); then
    _diag_response_mode=$(_diag_kv_value "$_diag_response_raw" mode 2>/dev/null) || _diag_response_mode=unknown
    _diag_response_ipv4=$(_diag_kv_value "$_diag_response_raw" blocking_ipv4 2>/dev/null) || _diag_response_ipv4=unknown
    _diag_response_ipv6=$(_diag_kv_value "$_diag_response_raw" blocking_ipv6 2>/dev/null) || _diag_response_ipv6=unknown
    _diag_response_ttl=$(_diag_kv_value "$_diag_response_raw" blocked_response_ttl 2>/dev/null) || _diag_response_ttl=unknown
  fi
  case "$_diag_response_mode" in nxdomain|refused|custom_ip|unknown) : ;; *) _diag_response_mode=unknown ;; esac
  case "$_diag_response_ipv4" in ''|*[!0-9.]*) _diag_response_ipv4=unknown ;; esac
  case "$_diag_response_ipv6" in ''|*[!0-9A-Fa-f:]*) _diag_response_ipv6=unknown ;; esac
  case "$_diag_response_ttl" in ''|*[!0-9]*) _diag_response_ttl=unknown ;; esac
  _diag_rewrites_count=unknown
  if _diag_rewrites_rows=$(dns_rewrites_values 2>/dev/null); then
    _diag_rewrites_count=$(printf '%s\n' "$_diag_rewrites_rows" | awk 'NF{n++} END{print n+0}')
  fi
  case "$_diag_rewrites_count" in ''|*[!0-9]*) _diag_rewrites_count=unknown ;; esac
  case "$_diag_upstream_mode" in local_recursive|custom|global|unknown) : ;; *) _diag_upstream_mode=unknown ;; esac
  case "$_diag_upstream_state" in ready|missing_primary|unknown) : ;; *) _diag_upstream_state=unknown ;; esac
  case "$_diag_bootstrap_mode" in not_required|local_unbound|unknown) : ;; *) _diag_bootstrap_mode=unknown ;; esac
  case "$_diag_fallback_mode" in none|explicit|local_unbound|unknown) : ;; *) _diag_fallback_mode=unknown ;; esac
  _diag_kv_value() {
    printf '%s\n' "$1" | awk -F= -v wanted="$2" '
      index($0,"=")>0 {key=substr($0,1,index($0,"=")-1); value=substr($0,index($0,"=")+1); if(key==wanted){count++; found=value}}
      END {if(count==1)print found; else exit 1}
    '
  }
  _diag_dns_runtime=$(dns_runtime_get 2>/dev/null || :)
  _diag_unbound_runtime=$(unbound_runtime_get 2>/dev/null || :)
  _diag_querylog_retention_raw=$(dns_querylog_retention_get 2>/dev/null || :)
  _diag_querylog_runtime=$(dns_querylog_runtime_get 2>/dev/null || :)
  _diag_statistics_runtime=$(dns_statistics_get 2>/dev/null || :)
  _diag_dns_runtime_header=$(printf '%s\n' "$_diag_dns_runtime" | sed -n '1p')
  _diag_unbound_runtime_header=$(printf '%s\n' "$_diag_unbound_runtime" | sed -n '1p')
  _diag_querylog_runtime_header=$(printf '%s\n' "$_diag_querylog_runtime" | sed -n '1p')
  _diag_statistics_runtime_header=$(printf '%s\n' "$_diag_statistics_runtime" | sed -n '1p')
  _diag_retention_header=$(_diag_kv_value "$_diag_querylog_retention_raw" querylog_retention 2>/dev/null) || _diag_retention_header=unknown
  _diag_querylog_enabled=$(_diag_value "$_diag_status" dns_querylog_enabled 2>/dev/null) || _diag_querylog_enabled=unknown
  _diag_querylog_memory_size=unknown; _diag_querylog_memory_max=unknown
  [ "$_diag_querylog_runtime_header" = FXYULONGDNSQUERYLOG1 ] && {
    _diag_querylog_memory_size=$(_diag_kv_value "$_diag_querylog_runtime" memory_size 2>/dev/null) || _diag_querylog_memory_size=unknown
    _diag_querylog_memory_max=$(_diag_kv_value "$_diag_querylog_runtime" memory_max 2>/dev/null) || _diag_querylog_memory_max=unknown
  }
  _diag_statistics_enabled=unknown; _diag_statistics_interval=unknown
  [ "$_diag_statistics_runtime_header" = FXYULONGDNSSTAT1 ] && {
    _diag_statistics_enabled=$(_diag_kv_value "$_diag_statistics_runtime" STATISTICS_ENABLED 2>/dev/null) || _diag_statistics_enabled=unknown
    _diag_statistics_interval=$(_diag_kv_value "$_diag_statistics_runtime" STATISTICS_INTERVAL 2>/dev/null) || _diag_statistics_interval=unknown
  }
  _diag_adguard_upstream_mode=unknown
  _diag_adguard_fastest_timeout=unknown
  _diag_adguard_upstream_timeout=unknown
  _diag_adguard_cache_size=unknown
  _diag_adguard_cache_ttl_min=unknown
  _diag_adguard_cache_ttl_max=unknown
  _diag_adguard_optimistic_answer_ttl=unknown
  _diag_adguard_optimistic_max_age=unknown
  _diag_adguard_cache_enabled=unknown
  _diag_adguard_cache_optimistic=unknown
  _diag_adguard_dnssec_enabled=unknown
  [ "$_diag_dns_runtime_header" = FXYULONGDNSRUNTIME1 ] && {
    _diag_adguard_upstream_mode=$(_diag_kv_value "$_diag_dns_runtime" UPSTREAM_MODE 2>/dev/null) || _diag_adguard_upstream_mode=unknown
    _diag_adguard_fastest_timeout=$(_diag_kv_value "$_diag_dns_runtime" FASTEST_TIMEOUT 2>/dev/null) || _diag_adguard_fastest_timeout=unknown
    _diag_adguard_upstream_timeout=$(_diag_kv_value "$_diag_dns_runtime" UPSTREAM_TIMEOUT 2>/dev/null) || _diag_adguard_upstream_timeout=unknown
    _diag_adguard_cache_size=$(_diag_kv_value "$_diag_dns_runtime" CACHE_SIZE 2>/dev/null) || _diag_adguard_cache_size=unknown
    _diag_adguard_cache_ttl_min=$(_diag_kv_value "$_diag_dns_runtime" CACHE_TTL_MIN 2>/dev/null) || _diag_adguard_cache_ttl_min=unknown
    _diag_adguard_cache_ttl_max=$(_diag_kv_value "$_diag_dns_runtime" CACHE_TTL_MAX 2>/dev/null) || _diag_adguard_cache_ttl_max=unknown
    _diag_adguard_optimistic_answer_ttl=$(_diag_kv_value "$_diag_dns_runtime" CACHE_OPTIMISTIC_ANSWER_TTL 2>/dev/null) || _diag_adguard_optimistic_answer_ttl=unknown
    _diag_adguard_optimistic_max_age=$(_diag_kv_value "$_diag_dns_runtime" CACHE_OPTIMISTIC_MAX_AGE 2>/dev/null) || _diag_adguard_optimistic_max_age=unknown
    _diag_adguard_cache_enabled=$(_diag_kv_value "$_diag_dns_runtime" CACHE_ENABLED 2>/dev/null) || _diag_adguard_cache_enabled=unknown
    _diag_adguard_cache_optimistic=$(_diag_kv_value "$_diag_dns_runtime" CACHE_OPTIMISTIC 2>/dev/null) || _diag_adguard_cache_optimistic=unknown
    _diag_adguard_dnssec_enabled=$(_diag_kv_value "$_diag_dns_runtime" ENABLE_DNSSEC 2>/dev/null) || _diag_adguard_dnssec_enabled=unknown
  }
  _diag_unbound_cache_max_ttl=unknown
  _diag_unbound_cache_min_ttl=unknown
  _diag_unbound_serve_expired=unknown
  _diag_unbound_serve_expired_ttl=unknown
  _diag_unbound_serve_expired_reply_ttl=unknown
  _diag_unbound_serve_expired_client_timeout=unknown
  _diag_unbound_prefetch=unknown
  _diag_unbound_prefetch_key=unknown
  _diag_unbound_qname_minimisation=unknown
  _diag_unbound_msg_cache_size=unknown
  _diag_unbound_rrset_cache_size=unknown
  _diag_unbound_key_cache_size=unknown
  _diag_unbound_neg_cache_size=unknown
  _diag_unbound_num_threads=unknown
  _diag_unbound_threads_max=unknown
  [ "$_diag_unbound_runtime_header" = FXYULONGUNBOUND1 ] && {
    _diag_unbound_cache_max_ttl=$(_diag_kv_value "$_diag_unbound_runtime" UNBOUND_CACHE_MAX_TTL 2>/dev/null) || _diag_unbound_cache_max_ttl=unknown
    _diag_unbound_cache_min_ttl=$(_diag_kv_value "$_diag_unbound_runtime" UNBOUND_CACHE_MIN_TTL 2>/dev/null) || _diag_unbound_cache_min_ttl=unknown
    _diag_unbound_serve_expired=$(_diag_kv_value "$_diag_unbound_runtime" UNBOUND_SERVE_EXPIRED 2>/dev/null) || _diag_unbound_serve_expired=unknown
    _diag_unbound_serve_expired_ttl=$(_diag_kv_value "$_diag_unbound_runtime" UNBOUND_SERVE_EXPIRED_TTL 2>/dev/null) || _diag_unbound_serve_expired_ttl=unknown
    _diag_unbound_serve_expired_reply_ttl=$(_diag_kv_value "$_diag_unbound_runtime" UNBOUND_SERVE_EXPIRED_REPLY_TTL 2>/dev/null) || _diag_unbound_serve_expired_reply_ttl=unknown
    _diag_unbound_serve_expired_client_timeout=$(_diag_kv_value "$_diag_unbound_runtime" UNBOUND_SERVE_EXPIRED_CLIENT_TIMEOUT 2>/dev/null) || _diag_unbound_serve_expired_client_timeout=unknown
    _diag_unbound_prefetch=$(_diag_kv_value "$_diag_unbound_runtime" UNBOUND_PREFETCH 2>/dev/null) || _diag_unbound_prefetch=unknown
    _diag_unbound_prefetch_key=$(_diag_kv_value "$_diag_unbound_runtime" UNBOUND_PREFETCH_KEY 2>/dev/null) || _diag_unbound_prefetch_key=unknown
    _diag_unbound_qname_minimisation=$(_diag_kv_value "$_diag_unbound_runtime" UNBOUND_QNAME_MINIMISATION 2>/dev/null) || _diag_unbound_qname_minimisation=unknown
    _diag_unbound_msg_cache_size=$(_diag_kv_value "$_diag_unbound_runtime" UNBOUND_MSG_CACHE_SIZE 2>/dev/null) || _diag_unbound_msg_cache_size=unknown
    _diag_unbound_rrset_cache_size=$(_diag_kv_value "$_diag_unbound_runtime" UNBOUND_RRSET_CACHE_SIZE 2>/dev/null) || _diag_unbound_rrset_cache_size=unknown
    _diag_unbound_key_cache_size=$(_diag_kv_value "$_diag_unbound_runtime" UNBOUND_KEY_CACHE_SIZE 2>/dev/null) || _diag_unbound_key_cache_size=unknown
    _diag_unbound_neg_cache_size=$(_diag_kv_value "$_diag_unbound_runtime" UNBOUND_NEG_CACHE_SIZE 2>/dev/null) || _diag_unbound_neg_cache_size=unknown
    _diag_unbound_num_threads=$(_diag_kv_value "$_diag_unbound_runtime" UNBOUND_NUM_THREADS 2>/dev/null) || _diag_unbound_num_threads=unknown
    _diag_unbound_threads_max=$(_diag_kv_value "$_diag_unbound_runtime" UNBOUND_THREADS_MAX 2>/dev/null) || _diag_unbound_threads_max=unknown
  }
  _diag_anchor_state=unknown
  _diag_anchor_age=unknown
  _diag_anchor_bytes=unknown
  _diag_refresh_route=unknown
  _diag_anchor_resolver_state=unknown
  _diag_root_hints_state=unknown
  _diag_root_hints_bytes=unknown
  _diag_anchor_raw=$(MP="$MP" PG="$PG" sh "$MP/scripts/unbound.sh" anchor-status "$MP" "$PG" 2>/dev/null || :)
  if [ "$(printf '%s\n' "$_diag_anchor_raw" | sed -n '1p')" = FXYUNBOUNDANCHOR2 ]; then
    _diag_anchor_state=$(_diag_kv_value "$_diag_anchor_raw" anchor_state 2>/dev/null) || _diag_anchor_state=unknown
    _diag_anchor_age=$(_diag_kv_value "$_diag_anchor_raw" anchor_age 2>/dev/null) || _diag_anchor_age=unknown
    _diag_anchor_bytes=$(_diag_kv_value "$_diag_anchor_raw" anchor_bytes 2>/dev/null) || _diag_anchor_bytes=unknown
    _diag_refresh_route=$(_diag_kv_value "$_diag_anchor_raw" refresh_route 2>/dev/null) || _diag_refresh_route=unknown
    _diag_anchor_resolver_state=$(_diag_kv_value "$_diag_anchor_raw" resolver_state 2>/dev/null) || _diag_anchor_resolver_state=unknown
    _diag_root_hints_state=$(_diag_kv_value "$_diag_anchor_raw" root_hints_state 2>/dev/null) || _diag_root_hints_state=unknown
    _diag_root_hints_bytes=$(_diag_kv_value "$_diag_anchor_raw" root_hints_bytes 2>/dev/null) || _diag_root_hints_bytes=unknown
  fi
  case "$_diag_anchor_state" in valid|missing|invalid|unsafe) : ;; *) _diag_anchor_state=unknown ;; esac
  case "$_diag_anchor_age" in stale|current|unknown) : ;; *) _diag_anchor_age=unknown ;; esac
  case "$_diag_anchor_bytes" in ''|*[!0-9]*) _diag_anchor_bytes=unknown ;; esac
  case "$_diag_refresh_route" in system_default|vpn_bound|unsafe|unknown) : ;; *) _diag_refresh_route=unknown ;; esac
  case "$_diag_anchor_resolver_state" in running|stopped|unknown) : ;; *) _diag_anchor_resolver_state=unknown ;; esac
  case "$_diag_root_hints_state" in valid|missing|invalid|unsafe) : ;; *) _diag_root_hints_state=unknown ;; esac
  case "$_diag_root_hints_bytes" in ''|*[!0-9]*) _diag_root_hints_bytes=unknown ;; esac
  echo FXYULONGDNSDIAG4
  printf 'dns_stack_ready=%s\n' "$_diag_ready"
  printf 'dns_stack_readiness_reason=%s\n' "$_diag_reason"
  printf 'unbound_process=%s\n' "$_diag_unbound_process"
  printf 'unbound_probe=%s\n' "$_diag_unbound_probe"
  printf 'adguardhome_process=%s\n' "$_diag_agh_process"
  printf 'adguardhome_ipv4_probe=%s\n' "$_diag_agh_ipv4"
  printf 'adguardhome_ipv6_probe=%s\n' "$_diag_agh_ipv6"
  printf 'localdns_watchdog=%s\n' "$_diag_watchdog"
  printf 'vpn_coexistence_verdict=%s\n' "$_diag_coexist"
  printf 'vpn_route_probe=%s\n' "$_diag_route"
  printf 'private_dns_mode=%s\n' "$_diag_private_dns"
  printf 'dns_upstream_mode=%s\n' "$_diag_upstream_mode"
  printf 'dns_upstream_state=%s\n' "$_diag_upstream_state"
  printf 'dns_bootstrap_mode=%s\n' "$_diag_bootstrap_mode"
  printf 'dns_fallback_mode=%s\n' "$_diag_fallback_mode"
  printf 'rootproxy_cleanup=%s\n' "$_diag_rootproxy_cleanup"
  printf 'dns_response_mode=%s\n' "$_diag_response_mode"
  printf 'dns_blocking_ipv4=%s\n' "$_diag_response_ipv4"
  printf 'dns_blocking_ipv6=%s\n' "$_diag_response_ipv6"
  printf 'dns_blocked_response_ttl=%s\n' "$_diag_response_ttl"
  printf 'dns_rewrites_count=%s\n' "$_diag_rewrites_count"
  printf 'dns_querylog_ignored_enabled=%s\n' "$_diag_querylog_ignored_enabled"
  printf 'dns_querylog_ignored_count=%s\n' "$_diag_querylog_ignored_count"
  printf 'dns_statistics_ignored_enabled=%s\n' "$_diag_statistics_ignored_enabled"
  printf 'dns_statistics_ignored_count=%s\n' "$_diag_statistics_ignored_count"
  printf 'dnssec_anchor_state=%s\n' "$_diag_anchor_state"
  printf 'root_hints_state=%s\n' "$_diag_root_hints_state"
  printf 'root_hints_bytes=%s\n' "$_diag_root_hints_bytes"
  printf 'dns_querylog_enabled=%s\n' "$_diag_querylog_enabled"
  printf 'dns_querylog_retention=%s\n' "$_diag_retention_header"
  printf 'dns_querylog_memory_size=%s\n' "$_diag_querylog_memory_size"
  printf 'dns_querylog_memory_max=%s\n' "$_diag_querylog_memory_max"
  printf 'dns_statistics_enabled=%s\n' "$_diag_statistics_enabled"
  printf 'dns_statistics_interval=%s\n' "$_diag_statistics_interval"
  printf 'adguard_upstream_mode=%s\n' "$_diag_adguard_upstream_mode"
  printf 'adguard_fastest_timeout=%s\n' "$_diag_adguard_fastest_timeout"
  printf 'adguard_upstream_timeout=%s\n' "$_diag_adguard_upstream_timeout"
  printf 'adguard_cache_size=%s\n' "$_diag_adguard_cache_size"
  printf 'adguard_cache_ttl_min=%s\n' "$_diag_adguard_cache_ttl_min"
  printf 'adguard_cache_ttl_max=%s\n' "$_diag_adguard_cache_ttl_max"
  printf 'adguard_optimistic_answer_ttl=%s\n' "$_diag_adguard_optimistic_answer_ttl"
  printf 'adguard_optimistic_max_age=%s\n' "$_diag_adguard_optimistic_max_age"
  printf 'adguard_cache_enabled=%s\n' "$_diag_adguard_cache_enabled"
  printf 'adguard_cache_optimistic=%s\n' "$_diag_adguard_cache_optimistic"
  printf 'adguard_dnssec_enabled=%s\n' "$_diag_adguard_dnssec_enabled"
  printf 'unbound_cache_max_ttl=%s\n' "$_diag_unbound_cache_max_ttl"
  printf 'unbound_cache_min_ttl=%s\n' "$_diag_unbound_cache_min_ttl"
  printf 'unbound_serve_expired=%s\n' "$_diag_unbound_serve_expired"
  printf 'unbound_serve_expired_ttl=%s\n' "$_diag_unbound_serve_expired_ttl"
  printf 'unbound_serve_expired_reply_ttl=%s\n' "$_diag_unbound_serve_expired_reply_ttl"
  printf 'unbound_serve_expired_client_timeout=%s\n' "$_diag_unbound_serve_expired_client_timeout"
  printf 'unbound_prefetch=%s\n' "$_diag_unbound_prefetch"
  printf 'unbound_prefetch_key=%s\n' "$_diag_unbound_prefetch_key"
  printf 'unbound_qname_minimisation=%s\n' "$_diag_unbound_qname_minimisation"
  printf 'unbound_msg_cache_size=%s\n' "$_diag_unbound_msg_cache_size"
  printf 'unbound_rrset_cache_size=%s\n' "$_diag_unbound_rrset_cache_size"
  printf 'unbound_key_cache_size=%s\n' "$_diag_unbound_key_cache_size"
  printf 'unbound_neg_cache_size=%s\n' "$_diag_unbound_neg_cache_size"
  printf 'unbound_num_threads=%s\n' "$_diag_unbound_num_threads"
  printf 'unbound_threads_max=%s\n' "$_diag_unbound_threads_max"
  printf 'dnssec_anchor_age=%s\n' "$_diag_anchor_age"
  printf 'dnssec_anchor_bytes=%s\n' "$_diag_anchor_bytes"
  printf 'dnssec_refresh_route=%s\n' "$_diag_refresh_route"
  printf 'dnssec_resolver_state=%s\n' "$_diag_anchor_resolver_state"
  ;;
 dns-repair)
  [ "$#" -eq 1 ] || exit 2
  [ -x "$MP/scripts/localdns-watchdog.sh" ] || { echo "local DNS watchdog is missing" >&2; exit 20; }
  MP="$MP" PG="$PG" sh "$MP/scripts/localdns-watchdog.sh" repair "$MP" "$PG"
  ;;
 dns-config-set)
  [ "$#" -eq 3 ] || { echo "usage: $0 dns-config-set custom|global|fallback server[,server...]" >&2; exit 2; }
  servers=$(normalize_dns_csv "$3")
  case "$2" in
    custom)
      section=custom_dns
      valid_dns_csv "$servers" || { echo "custom DNS accepts one or more IPv4, https:// DoH, tls:// DoT, or quic:// DoQ endpoints" >&2; exit 2; }
      ;;
    global)
      section=global_dns
      valid_ipv4_dns_csv "$servers" || { echo "global DNS requires routable IPv4/IPv6 literals, optionally with ports" >&2; exit 2; }
      ;;
    fallback)
      section=yulong_dns_fallback
      valid_fallback_dns_csv "$servers" || { echo "fallback DNS requires routable IPv4/IPv6 literals, optionally with ports" >&2; exit 2; }
      ;;
    *) exit 2 ;;
  esac
  with_lock transaction m_dns_servers "$section" "$servers"
  ;;


 dns-response-get)
  echo FXYULONGDNSRESP1
  dns_response_values || exit $?
  ;;
 dns-response-set)
  [ "$#" -eq 2 ] || { echo "usage: $0 dns-response-set nxdomain|refused|custom_ip" >&2; exit 2; }
  case "$2" in nxdomain|refused|custom_ip) ;; *) exit 2 ;; esac
  with_lock transaction m_dns_response "$2"
  ;;
 dns-response-config-set)
  [ "$#" -eq 5 ] || { echo "usage: $0 dns-response-config-set MODE IPV4 IPV6 TTL" >&2; exit 2; }
  with_lock transaction m_dns_response_config "$2" "$3" "$4" "$5"
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

 rootproxy-reconcile-route)
  [ -x "$MP/scripts/yulong-root-proxy.sh" ] || { echo "Root Proxy is not installed" >&2; exit 20; }
  sh "$MP/scripts/yulong-root-proxy.sh" reconcile-route ;;
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
  [ -s "$PG/boot.log" ] && cat "$PG/boot.log" || echo "暂无日志" ;;
 ad-master)
   [ "$#" -eq 2 ] && { [ "$2" = 0 ] || [ "$2" = 1 ]; } || exit 2
   with_lock transaction m_dns yulong_ad_filter_enabled "$2" ;;
 *) exit 2 ;;
esac