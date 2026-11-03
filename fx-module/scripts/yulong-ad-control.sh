#!/system/bin/sh
# Yulong AdBlock 7.0.1 native FX backend. Uses FX's single apply/VPN pipeline.
set -eu
D=$(CDPATH= cd -- "$(dirname "$0")" 2>/dev/null && pwd)
MP=${D%/scripts}; PG=/data/adb/privacyguard; CONF=$PG/settings.conf
[ -s "$MP/module.prop" ] && [ -s "$MP/scripts/util.sh" ] && [ -f "$CONF" ] || exit 20
. "$MP/scripts/util.sh"
valid_state(){ [ "$1" = 0 ] || [ "$1" = 1 ]; }
valid_text(){ case "$1" in *'|'*) return 1;; esac; [ "$(printf %s "$1"|wc -c|tr -d ' ')" -le "${2:-512}" ] && ! printf %s "$1"|grep -q '[[:cntrl:]]'; }
valid_ip(){ printf '%s\n' "$1"|awk -F. 'NF!=4{ok=0;exit}{ok=1;for(i=1;i<=4;i++)if($i!~/^[0-9]+$/||length($i)>3||($i+0)>255)ok=0}END{exit(ok?0:1)}'; }
valid_domain(){ printf '%s\n' "$1"|grep -Eqi '^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$' && case "$1" in *..*|.*|*.) return 1;; esac; }
apply(){ sh "$MP/scripts/apply.sh" fast >> "$PG/boot.log" 2>&1; }
read_vpn(){ pg_conf vpn|awk -F= -v k="$1" '$1==k{print substr($0,index($0,"=")+1);exit}'; }
write_section(){
  kind=$1; name=$2; bodyfile=$3; body=$(cat "$bodyfile"); tmp="$CONF.yad.$$"
  awk -v target="[$kind:$name]" -v body="$body" 'BEGIN{n=split(body,a,"\n");inside=0;done=0}$0==target{if(!done){print;for(i=1;i<=n;i++)if(a[i]!="")print a[i];done=1}inside=1;next}/^\[/{inside=0}inside{next}{print}END{if(!done){print "";print target;for(i=1;i<=n;i++)if(a[i]!="")print a[i]}}' "$CONF" > "$tmp" || { rm -f "$tmp"; return 1; }
  chmod 600 "$tmp" && mv -f "$tmp" "$CONF"
}
update_list(){
  list=$1; op=$2; key=$3; note=${4-}; state=${5-1}; old="$PG/yad-old.$$"; new="$PG/yad-new.$$"
  valid_text "$key" 2048 && valid_text "$note" 512 || return 2
  pg_list "$list" > "$old"
  if awk -F'|' -v OFS='|' -v op="$op" -v key="$key" -v note="$note" -v state="$state" 'BEGIN{found=0}/^[[:space:]]*#/||NF==0{print;next}$1==key{found=1;if(op=="del")next;if(op=="set"){$3=state;print;next}if(op=="add"){print key,note,state;next}}{print}END{if(op=="add"&&!found)print key,note,state;if((op=="set"||op=="del")&&!found)exit 5}' "$old" > "$new"; then
    write_section list "$list" "$new"; r=$?; rm -f "$old" "$new"; return "$r"
  else r=$?; rm -f "$old" "$new"; [ "$r" -eq 5 ] && return 0; return "$r"; fi
}
get_dns(){
  pg_conf custom_dns|sed -n 's/^[[:space:]]*nameserver[[:space:]]*//p'|while read -r v; do [ -n "$v" ] && echo "CUSTOM|$v"; done
  pg_conf global_dns|sed -n 's/^[[:space:]]*nameserver[[:space:]]*//p'|while read -r v; do [ -n "$v" ] && echo "GLOBAL|$v"; done
  echo "VPN_REMOTE|$(read_vpn remote_dns)"; echo "VPN_CN|$(read_vpn cn_dns)"
}
set_dns(){
  case "$1" in custom) sec=custom_dns;; global) sec=global_dns;; *) return 2;; esac
  body="$PG/yad-dns.$$"; : > "$body"; n=0; oldifs=$IFS; IFS=,
  for ip in $2; do ip=$(printf %s "$ip"|tr -d '[:space:]'); [ -n "$ip" ] || continue; valid_ip "$ip" || { IFS=$oldifs; rm -f "$body"; return 2; }; n=$((n+1)); [ "$n" -le 3 ] || { IFS=$oldifs; rm -f "$body"; return 2; }; echo "nameserver $ip" >> "$body"; done
  IFS=$oldifs; [ "$n" -gt 0 ] || { rm -f "$body"; return 2; }; write_section conf "$sec" "$body"; r=$?; rm -f "$body"; [ "$r" -eq 0 ] && apply
}
cmd=list; [ "$#" -eq 0 ] || cmd=$1
case "$cmd" in
 list)
  echo "AD_MASTER|$(pg_get yulong_ad_filter_enabled 1)"
  for k in dns_engine_adguardhome dns_forward custom_dns global_dns block_quic block_dot block_plain_dns block_ipv6 block_track_domains dns_querylog_enabled vpn_external_dns_proxy vpn_external_compat; do echo "DNS|$k|$(pg_get "$k" 0)"; done
  pg_list rule|awk -F'|' '$1!=""&&$1!~/^#/{print "RULE|"$1"|"$2"|"($3=="1"?1:0)}'
  pg_list domain|awk -F'|' '$1!=""&&$1!~/^#/{print "ALLOW|"$1"|"$2"|"($3=="0"?0:1)}'
  pg_list block|awk -F'|' '$1!=""&&$1!~/^#/{print "BLOCK|"$1"|"$2"|"($3=="0"?0:1)}'
  ;;
 ad-master) [ "$#" -eq 2 ] && valid_state "$2" || exit 2; pg_set yulong_ad_filter_enabled "$2"; apply ;;
 rule-add) [ "$#" -eq 4 ] || exit 2; case "$2" in https://*|builtin://*) ;; *) exit 2;; esac; valid_state "$4" && update_list rule add "$2" "$3" "$4"; apply ;;
 rule-set) [ "$#" -eq 3 ] && valid_state "$3" || exit 2; update_list rule set "$2" "" "$3"; apply ;;
 rule-remove) [ "$#" -eq 2 ] || exit 2; update_list rule del "$2"; apply ;;
 allow-add|block-add) [ "$#" -eq 3 ] && valid_domain "$2" && valid_text "$3" 512 || exit 2; if [ "$cmd" = allow-add ]; then update_list domain add "$2" "$3" 1; else update_list block add "$2" "$3" 1; fi; apply ;;
 allow-remove|block-remove) [ "$#" -eq 2 ] && valid_domain "$2" || exit 2; if [ "$cmd" = allow-remove ]; then update_list domain del "$2"; else update_list block del "$2"; fi; apply ;;
 dns-set) [ "$#" -eq 3 ] && valid_state "$3" || exit 2; case "$2" in dns_engine_adguardhome|dns_forward|custom_dns|global_dns|block_quic|block_dot|block_plain_dns|block_ipv6|block_track_domains|dns_querylog_enabled|vpn_external_dns_proxy|vpn_external_compat) ;; *) exit 2;; esac; pg_set "$2" "$3"; apply ;;
 dns-config-get) get_dns ;;
 dns-config-set) [ "$#" -eq 3 ] || exit 2; set_dns "$2" "$3" ;;
 dns-vpn-set) [ "$#" -eq 3 ] || exit 2; case "$2" in remote_dns|cn_dns) ;; *) exit 2;; esac; valid_ip "$3" || exit 2; old="$PG/yad-vpn-old.$$"; new="$PG/yad-vpn-new.$$"; pg_conf vpn > "$old"; awk -v k="$2" -v v="$3" 'BEGIN{d=0}index($0,k"=")==1{if(!d)print k"="v;d=1;next}{print}END{if(!d)print k"="v}' "$old" > "$new"; write_section conf vpn "$new"; r=$?; rm -f "$old" "$new"; [ "$r" -eq 0 ] && apply ;;
 cache-flush) sh "$MP/scripts/adguardhome.sh" stop "$MP" "$PG" >> "$PG/boot.log" 2>&1 || exit 1; sh "$MP/scripts/adguardhome.sh" ensure "$MP" "$PG" >> "$PG/boot.log" 2>&1 ;;
 rootproxy-status) sh "$MP/scripts/yulong-root-proxy.sh" status ;;
 schedule-get) sh "$MP/scripts/yulong-ad-schedule.sh" status "$MP" "$PG" ;;
 schedule-set)
  [ "$#" -eq 5 ] && valid_state "$2" || exit 2; echo "$3"|grep -Eq '^([01][0-9]|2[0-3]):[0-5][0-9]$' || exit 2; echo "$4"|grep -Eq '^([01][0-9]|2[0-3]):[0-5][0-9]$' || exit 2; echo "$5"|grep -Eq '^[1-7](,[1-7])*$' || exit 2
  days=$(echo "$5"|tr ',' '\n'|sort -nu|paste -sd, -); sf="$PG/yulong-ad-schedule.conf"; tmp="$sf.tmp.$$"; (umask 077; printf 'enabled=%s\nstart=%s\nend=%s\ndays=%s\n' "$2" "$3" "$4" "$days" > "$tmp"); chmod 600 "$tmp" && mv -f "$tmp" "$sf"; sh "$MP/scripts/yulong-ad-schedule.sh" start "$MP" "$PG" >/dev/null 2>&1; sh "$MP/scripts/yulong-ad-schedule.sh" evaluate ;;
 logs) [ -f "$PG/apply.log" ] && tail -n 500 "$PG/apply.log" || echo "No FX log yet." ;;
 *) echo "unknown Yulong Ad control command: $cmd" >&2; exit 64 ;;
esac
