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
m_rule_add(){ write_rule "$1" "$2" "$3" add; }
m_rule_set(){ old=$(pg_list rule|awk -F'|' -v src="$1" '$1==src{print $2;exit}'); [ -n "$old" ] || return 3; write_rule "$1" "$old" "$2" set; }
m_rule_remove(){ write_rule "$1" "" 0 remove; }
m_allow_add(){ sh "$MP/scripts/whitelist.sh" add "$1" "$2"; }
m_allow_remove(){ sh "$MP/scripts/whitelist.sh" remove "$1"; }
m_block_add(){ write_block "$1" "$2" 1 add; }
m_block_remove(){ write_block "$1" "" 0 remove; }
cmd="$1"
case "$cmd" in
  dns-log-tail)
  if ! grep -q '^dns_querylog_enabled=1 "$CONF" 2>/dev/null; then
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
  for key in dns_engine_adguardhome dns_forward block_quic block_dot block_plain_dns block_ipv6 block_track_domains vpn_external_dns_proxy vpn_external_compat dns_querylog_enabled; do
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
 block-add)
  [ "$#" -ge 2 ] && [ "$#" -le 3 ] || exit 2
  d=$(valid_domain "$2") || exit 2; note=$3; [ -n "$note" ] || note="FX 黑名单"; valid_text "$note" || exit 2
  with_lock transaction m_block_add "$d" "$note" ;;
 block-remove)
  [ "$#" -eq 2 ] || exit 2; d=$(valid_domain "$2") || exit 2
  with_lock transaction m_block_remove "$d" ;;
 dns-set)
  [ "$#" -eq 3 ] || exit 2
  case "$2" in dns_engine_adguardhome|dns_forward|block_quic|block_dot|block_plain_dns|block_ipv6|block_track_domains|vpn_external_dns_proxy|vpn_external_compat|dns_querylog_enabled) ;; *) exit 2 ;; esac
  [ "$3" = 0 ] || [ "$3" = 1 ] || exit 2
  with_lock transaction m_dns "$2" "$3" ;;
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
