#!/system/bin/sh
# Native Yulong AdBlock 7.0.1 data adapter for FX.
set -eu
MP=""
for d in /data/adb/modules/privacyguard /data/adb/modules_update/privacyguard /data/adb/modules/privacy_guard /data/adb/modules/pg; do
  if [ -s "$d/module.prop" ] && grep -q '^id=privacyguard$' "$d/module.prop"; then MP="$d"; break; fi
done
[ -n "$MP" ] && [ -f "$MP/scripts/util.sh" ] || { echo "FX module is not installed" >&2; exit 20; }
PG=/data/adb/privacyguard
CONF=$PG/settings.conf
[ -f "$CONF" ] && [ ! -L "$CONF" ] || { echo "FX settings.conf missing or unsafe" >&2; exit 21; }
. "$MP/scripts/util.sh"
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
 trap 'rmdir "$lock" 2>/dev/null || :' EXIT HUP INT TERM
 "$@"
}
write_rule() {
 src=$1; title=$2; state=$3; mode=$4; tmp=$CONF.yulong-rule.$$
 awk -F'|' -v OFS='|' -v src="$src" -v title="$title" -v state="$state" -v mode="$mode" '
 BEGIN{inside=0;found=0;done=0}
 $0=="[list:rule]"{inside=1;found=1;print;next}
 /^\[/{if(inside&&mode=="add"&&!done){print src,title,state;done=1}inside=0;print;next}
 inside&&$0!~/^[[:space:]]*#/&&$1==src{if(mode=="remove")next;if(!done){print src,title,state;done=1}next}
 {print}
 END{if(inside&&mode=="add"&&!done){print src,title,state;done=1}if(!found&&mode=="add"){print "";print "[list:rule]";print src,title,state}if(!done&&mode=="set")exit 3}
 ' "$CONF" > "$tmp" || { rm -f "$tmp"; return 1; }
 [ -s "$tmp" ] && chmod 600 "$tmp" && mv -f "$tmp" "$CONF"
}
write_block() {
 domain=$1; note=$2; state=$3; mode=$4; tmp=$CONF.yulong-block.$$
 awk -F'|' -v OFS='|' -v domain="$domain" -v note="$note" -v state="$state" -v mode="$mode" '
 BEGIN{inside=0;found=0;done=0}
 $0=="[list:block]"{inside=1;found=1;print;next}
 /^\[/{if(inside&&mode=="add"&&!done){print domain,note,state;done=1}inside=0;print;next}
 inside&&$0!~/^[[:space:]]*#/&&tolower($1)==domain{if(mode=="remove")next;if(!done){print domain,note,state;done=1}next}
 {print}
 END{if(inside&&mode=="add"&&!done){print domain,note,state;done=1}if(!found&&mode=="add"){print "";print "[list:block]";print domain,note,state}}
 ' "$CONF" > "$tmp" || { rm -f "$tmp"; return 1; }
 [ -s "$tmp" ] && chmod 600 "$tmp" && mv -f "$tmp" "$CONF"
}
transaction() {
 op=$1; shift; backup=$CONF.yulong-ad-rollback.$$
 cp -p "$CONF" "$backup" || return 1
 if ! "$op" "$@"; then rm -f "$backup"; return 1; fi
 if sh "$MP/scripts/apply.sh" fast; then rm -f "$backup"; return 0; fi
 cp -p "$backup" "$CONF.restore.$$" && chmod 600 "$CONF.restore.$$" && mv -f "$CONF.restore.$$" "$CONF" || { rm -f "$backup"; return 31; }
 sh "$MP/scripts/apply.sh" fast >/dev/null 2>&1 || :
 rm -f "$backup"; echo "apply failed; previous config restored" >&2; return 1
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
      return 1
    }
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
  section=$1; servers=$2; tmp="$CONF.yulong-dns.$"
  awk -v section="$section" -v servers="$servers" '
    function emit(    n,a,i) {n=split(servers,a,",");for(i=1;i<=n;i++)print "nameserver " a[i]}
    BEGIN{inside=0;seen=0;written=0}
    $0=="[conf:" section "]"{if(inside&&!written){emit();written=1}inside=1;seen=1;print;next}
    /^\[/{if(inside&&!written){emit();written=1}inside=0;print;next}
    inside{next}
    {print}
    END{if(inside&&!written){emit();written=1}if(!seen){print "";print "[conf:" section "]";emit()}}
  ' "$CONF" > "$tmp" || { rm -f "$tmp"; return 1; }
  [ -s "$tmp" ] && chmod 600 "$tmp" && mv -f "$tmp" "$CONF"
}

remove_dns_section() {
  section=$1
  tmp="$CONF.yulong-dns-remove.$"
  awk -v section="$section" '
    $0=="[conf:" section "]" {inside=1; next}
    /^\[/ {inside=0}
    !inside {print}
  ' "$CONF" > "$tmp" || { rm -f "$tmp"; return 1; }
  [ -s "$tmp" ] || { rm -f "$tmp"; return 1; }
  chmod 600 "$tmp" && mv -f "$tmp" "$CONF"
}
m_dns_section_clear() { remove_dns_section "$1"; }


write_dns_response() {
  mode=$1
  tmp="$CONF.yulong-dns-response.$"
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
  [ -s "$tmp" ] && chmod 600 "$tmp" && mv -f "$tmp" "$CONF"
}
m_dns_response() { write_dns_response "$1"; }

write_vpn_dns() {
  key=$1; value=$2; tmp="$CONF.yulong-vpn-dns.$"
  awk -v key="$key" -v value="$value" '
    BEGIN{inside=0;seen=0;written=0}
    $0=="[conf:vpn]"{if(inside&&!written){print key "=" value;written=1}inside=1;seen=1;print;next}
    /^\[/{if(inside&&!written){print key "=" value;written=1}inside=0;print;next}
    inside&&index($0,key "=")==1{if(!written)print key "=" value;written=1;next}
    {print}
    END{if(inside&&!written)print key "=" value;if(!seen){print "";print "[conf:vpn]";print key "=" value}}
  ' "$CONF" > "$tmp" || { rm -f "$tmp"; return 1; }
  [ -s "$tmp" ] && chmod 600 "$tmp" && mv -f "$tmp" "$CONF"
}
m_dns_servers() { write_dns_section "$1" "$2"; }
m_vpn_dns() { write_vpn_dns "$1" "$2"; }
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
import_domains() {
  _import_kind="$1"
  _import_encoded="$2"
  case "$_import_kind" in allow|block) ;; *) return 2 ;; esac
  case "$_import_encoded" in ''|*[!A-Za-z0-9+/=]*) echo "invalid base64 domain import" >&2; return 2 ;; esac
  [ "\${#_import_encoded}" -le 87384 ] || { echo "domain import exceeds 64 KiB" >&2; return 2; }

  _import_raw="$PG/yulong-domain-import.$"
  _import_clean="$_import_raw.clean"
  rm -f "$_import_raw" "$_import_clean" 2>/dev/null || :
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
m_allow_add(){ sh "$MP/scripts/whitelist.sh" add "$1" "$2"; }
m_allow_remove(){ sh "$MP/scripts/whitelist.sh" remove "$1"; }
m_allow_import(){ import_domains allow "$1"; }
m_block_add(){ write_block "$1" "$2" 1 add; }
m_block_remove(){ write_block "$1" "" 0 remove; }
m_block_import(){ import_domains block "$1"; }
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
  if [ -s "$pidfile" ]; then
    pid=$(cat "$pidfile" 2>/dev/null)
    case "$pid" in ''|*[!0-9]*) pid= ;; esac
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then watcher=1; fi
  fi
  echo "watcher=$watcher"
}
schedule_set() {
  enabled=$1; start=$2; end=$3; days=$4
  { [ "$enabled" = 0 ] || [ "$enabled" = 1 ]; } || return 2
  valid_time "$start" && valid_time "$end" && valid_days "$days" || {
    echo "invalid schedule: use HH:MM and unique weekdays 1..7" >&2; return 2;
  }

  file="$PG/yulong-ad-schedule.conf"
  lock="$PG/yulong-ad-schedule.lock"
  tmp="$file.tmp.$$"
  backup="$file.rollback.$$"
  if ! mkdir "$lock" 2>/dev/null; then
    echo "schedule update is busy" >&2
    return 30
  fi
  trap 'rm -f "$tmp" "$backup"; rmdir "$lock" 2>/dev/null || :' EXIT HUP INT TERM

  existed=0
  if [ -f "$file" ] && [ ! -L "$file" ]; then
    cp -p "$file" "$backup" || { echo "unable to preserve previous schedule" >&2; return 31; }
    existed=1
  fi

  umask 077
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
  sync

  if [ ! -x "$MP/scripts/yulong-ad-schedule.sh" ]; then
    echo "Yulong schedule runtime is not installed" >&2
  else
    if MP="$MP" PG="$PG" sh "$MP/scripts/yulong-ad-schedule.sh" evaluate \
        && MP="$MP" PG="$PG" sh "$MP/scripts/yulong-ad-schedule.sh" start; then
      rm -f "$backup"
      echo "schedule=committed"
      return 0
    fi
    echo "schedule apply or watcher start failed; restoring previous schedule" >&2
  fi

  if [ "$existed" = 1 ] && [ -f "$backup" ]; then
    cp -p "$backup" "$tmp" && chmod 600 "$tmp" && mv -f "$tmp" "$file" || {
      echo "schedule rollback failed; previous copy remains at $backup" >&2
      return 34
    }
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
  trap 'rmdir "$lock" 2>/dev/null || :' EXIT HUP INT TERM
  agh_enabled=$(pg_get dns_engine_adguardhome 1 2>/dev/null)
  forward_enabled=$(pg_get dns_forward 1 2>/dev/null)
  if [ "$agh_enabled" != 1 ] && [ "$forward_enabled" != 1 ]; then echo "dns-engine-disabled"; return 0; fi
  # Stop only FX-managed resolvers; the helpers validate their own PID markers.
  if [ "$agh_enabled" = 1 ] && [ -x "$MP/scripts/adguardhome.sh" ]; then sh "$MP/scripts/adguardhome.sh" stop "$MP" "$PG" || :; fi
  if [ -x "$MP/scripts/unbound.sh" ]; then sh "$MP/scripts/unbound.sh" stop "$MP" "$PG" || :; fi
  u_rc=0; a_rc=0
  if [ -x "$MP/scripts/unbound.sh" ]; then sh "$MP/scripts/unbound.sh" ensure "$MP" "$PG" >> "$PG/boot.log" 2>&1 || u_rc=$?; fi
  if [ "$agh_enabled" = 1 ] && [ -x "$MP/scripts/adguardhome.sh" ]; then sh "$MP/scripts/adguardhome.sh" ensure "$MP" "$PG" >> "$PG/boot.log" 2>&1 || a_rc=$?; fi
  sh "$MP/scripts/apply.sh" fast >> "$PG/boot.log" 2>&1 || :
  echo "unbound_exit=$u_rc"; echo "adguardhome_exit=$a_rc"
  [ "$u_rc" -eq 0 ] && [ "$a_rc" -eq 0 ] || { echo "cache refresh incomplete; FX DNS rules were reconciled fail-open" >&2; return 31; }
  echo "cache=flushed"
}

cmd="${1:-list}"
case "$cmd" in
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
 block-import)
  [ "$#" -eq 2 ] || { echo "usage: $0 block-import base64-domain-list" >&2; exit 2; }
  with_lock transaction m_block_import "$2" ;;
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
  with_lock transaction m_dns "$2" "$3" ;;
 dns-config-get)
  dns_config_get
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
  [ "$#" -eq 2 ] && [ "$2" = fallback ] || { echo "usage: $0 dns-config-clear fallback" >&2; exit 2; }
  with_lock transaction m_dns_section_clear yulong_dns_fallback
  ;;

 dns-vpn-set)
  [ "$#" -eq 3 ] || { echo "usage: $0 dns-vpn-set remote_dns|cn_dns ipv4" >&2; exit 2; }
  case "$2" in remote_dns|cn_dns) ;; *) exit 2 ;; esac
  valid_ipv4 "$3" || { echo "VPN DNS must be an IPv4 literal" >&2; exit 2; }
  with_lock transaction m_vpn_dns "$2" "$3"
  ;;
 schedule-get)
  schedule_get
  ;;
 schedule-set)
  [ "$#" -eq 5 ] || { echo "usage: $0 schedule-set 0|1 HH:MM HH:MM days-csv" >&2; exit 2; }
  with_lock schedule_set "$2" "$3" "$4" "$5"
  ;;
 rootproxy-status)
  if [ -x "$MP/scripts/yulong-root-proxy.sh" ]; then
    sh "$MP/scripts/yulong-root-proxy.sh" status
  else
    echo "active=0"
    echo "status=not-installed"
  fi ;;
 logs)
  [ -s "$PG/boot.log" ] && tail -n 180 "$PG/boot.log" || echo "暂无日志" ;;
 ad-master)
   [ "$#" -eq 2 ] && { [ "$2" = 0 ] || [ "$2" = 1 ]; } || exit 2
   with_lock transaction m_dns yulong_ad_filter_enabled "$2" ;;
 *) exit 2 ;;
esac
