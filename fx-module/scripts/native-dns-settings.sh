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
    _filter_counts=$(awk -F'|' '
      function valid_url(u, i, ch, allowed) {
        if (length(u)>2048 || (index(u,"http://")!=1 && index(u,"https://")!=1)) return 0
        allowed="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._~:/?#@!$&\\047()*+,;=%-"
        for (i=1; i<=length(u); i++) {
          ch=substr(u,i,1)
          if (!index(allowed,ch)) return 0
        }
        return 1
      }
      $0=="[list:rule]" {section="rule"; next}
      /^\[/ {section=""; next}
      section=="rule" && valid_url($1) && ($3=="0" || $3=="1") {
        total++
        if ($3=="1") enabled++
      }
      END {printf "%d|%d\n", total+0, enabled+0}
    ' "$CONF")
    _filter_total=${_filter_counts%%|*}
    _filter_enabled=${_filter_counts#*|}
    case "$_filter_total:$_filter_enabled" in *[!0-9:]*|:*) _filter_total=unknown; _filter_enabled=unknown ;; esac
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
  _configured=0
  _ready=0
  if [ "$_agh_enabled" = 1 ] || [ "$_unbound_enabled" = 1 ]; then
    _configured=1
    _ready=1
    if [ "$_unbound_enabled" = 1 ]; then
      [ "$_unbound" = ready ] || _ready=0
    fi
    if [ "$_agh_enabled" = 1 ]; then
      [ "$_unbound_enabled" = 1 ] && [ "$_agh" = ready ] || _ready=0
    fi
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
      # AdGuard's only upstream is local Unbound; enabling the filter must
      # activate its recursive resolver in the same config transaction.
      pg_set dns_forward 1 || _set_rc=$?
      [ "$_set_rc" -ne 0 ] || pg_set dns_engine_adguardhome 1 || _set_rc=$?
      ;;
    dns_engine_adguardhome:0)
      # Root Proxy redirects to AdGuard on port 53. Disarm it before disabling
      # that listener; Unbound may remain enabled for independent local DNS.
      pg_set vpn_external_dns_proxy 0 || _set_rc=$?
      [ "$_set_rc" -ne 0 ] || pg_set dns_engine_adguardhome 0 || _set_rc=$?
      ;;
    dns_forward:0)
      # Do not leave an enabled filter pointing at a resolver that is disabled.
      pg_set dns_engine_adguardhome 0 || _set_rc=$?
      [ "$_set_rc" -ne 0 ] || pg_set vpn_external_dns_proxy 0 || _set_rc=$?
      [ "$_set_rc" -ne 0 ] || pg_set dns_forward 0 || _set_rc=$?
      ;;
    vpn_external_compat:0)
      # Root Proxy is a third-party-VPN fallback and cannot remain armed when
      # compatibility mode has been disabled.
      pg_set vpn_external_dns_proxy 0 || _set_rc=$?
      [ "$_set_rc" -ne 0 ] || pg_set vpn_external_compat 0 || _set_rc=$?
      ;;
    vpn_external_dns_proxy:1)
      # Root Proxy requires the explicit compatibility path, AdGuard's local
      # listener and its Unbound upstream in the same settings transaction.
      pg_set dns_forward 1 || _set_rc=$?
      [ "$_set_rc" -ne 0 ] || pg_set dns_engine_adguardhome 1 || _set_rc=$?
      [ "$_set_rc" -ne 0 ] || pg_set vpn_external_compat 1 || _set_rc=$?
      [ "$_set_rc" -ne 0 ] || pg_set vpn_external_dns_proxy 1 || _set_rc=$?
      ;;
    *)
      pg_set "$_key" "$_value" || _set_rc=$?
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
mutate_many() {
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
  pg_set dns_engine_adguardhome "$_want_agh" || _rc=$?
  [ "$_rc" -ne 0 ] || pg_set dns_forward "$_want_forward" || _rc=$?
  [ "$_rc" -ne 0 ] || pg_set vpn_external_compat "$_want_compat" || _rc=$?
  [ "$_rc" -ne 0 ] || pg_set vpn_external_dns_proxy "$_want_proxy" || _rc=$?
  if [ "$_rc" -ne 0 ]; then
    _restore=$(umask 077; mktemp "$CONF.native-dns-restore.XXXXXX") || { echo "batch mutation failed; backup retained at $_backup" >&2; return 11; }
    if ! cp -p "$_backup" "$_restore" || ! chmod 600 "$_restore" || ! mv -f "$_restore" "$CONF"; then
      rm -f "$_restore" 2>/dev/null || :; echo "batch mutation rollback failed; backup retained at $_backup" >&2; return 11
    fi
    rm -f "$_backup"; return "$_rc"
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
  *)
    echo "usage: $0 status|reconcile|set KEY 0|1|set-many KEY 0|1 ..." >&2
    exit 2
    ;;
esac
