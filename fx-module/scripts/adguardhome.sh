#!/system/bin/sh
# FX-owned AdGuard Home DNS filter. Client DNS binds only to loopback and
# forwards cache misses to FX Unbound on 127.0.0.1:5353.
set -u
case "$0" in
  */scripts/adguardhome.sh) MODDIR=${0%/scripts/adguardhome.sh} ;;
  *) MODDIR=${MODDIR:-/data/adb/modules/privacyguard} ;;
esac
ACTION=${1:-status}
[ "$#" -ge 2 ] && MODDIR=$2
PG=${3:-/data/adb/privacyguard}
ROOT="$MODDIR/engines/adguardhome"
BIN="$ROOT/AdGuardHome"
TEMPLATE="$ROOT/AdGuardHome.yaml"
STATE="$PG/adguardhome"
CFG="$STATE/AdGuardHome.yaml"
WORK="$STATE/work"
PIDFILE="$STATE/managed.pid"
CONFIG_HASH="$STATE/config.sha256"
LIFECYCLE_LOCK="$STATE/lifecycle.lock"
LOG="$STATE/engine.log"
PROBE="$MODDIR/engines/unbound/fx-dns-probe"
PATH=/system/bin:/system/xbin:/sbin:/vendor/bin:/usr/bin:/bin
export PATH

_path_components_are_safe() {
  _safe_path=$1
  case "$_safe_path" in /*) : ;; *) return 1 ;; esac
  case "$_safe_path" in *//*|*/../*|*/..|*/./*|*/.) return 1 ;; esac
  _safe_rest=${_safe_path#/}
  _safe_walk=
  while [ -n "$_safe_rest" ]; do
    case "$_safe_rest" in
      */*) _safe_part=${_safe_rest%%/*}; _safe_rest=${_safe_rest#*/} ;;
      *) _safe_part=$_safe_rest; _safe_rest= ;;
    esac
    case "$_safe_part" in ''|.|..) return 1 ;; esac
    _safe_walk="$_safe_walk/$_safe_part"
    [ ! -L "$_safe_walk" ] || return 1
  done
  return 0
}
_safe_file_or_absent() {
  _safe_file=$1
  _path_components_are_safe "$_safe_file" || return 1
  [ ! -L "$_safe_file" ] || return 1
  [ ! -e "$_safe_file" ] || [ -f "$_safe_file" ]
}
_new_private_temp() {
  _temp_template=$1
  _temp_path=$(umask 077; mktemp "$_temp_template") || return 1
  [ -f "$_temp_path" ] && [ ! -L "$_temp_path" ] || return 1
  chmod 600 "$_temp_path" 2>/dev/null || { rm -f "$_temp_path"; return 1; }
  printf '%s\n' "$_temp_path"
}
_prepare_state_dirs() {
  _path_components_are_safe "$MODDIR" && [ -d "$MODDIR" ] || {
    echo "AdGuard Home module path is missing or unsafe" >&2; return 1;
  }
  _path_components_are_safe "$ROOT" && [ -d "$ROOT" ] || {
    echo "AdGuard Home runtime directory is missing or unsafe" >&2; return 1;
  }
  _path_components_are_safe "$PG" && [ -d "$PG" ] && [ ! -L "$PG" ] || {
    echo "AdGuard Home parent state directory is missing or unsafe" >&2; return 1;
  }
  _path_components_are_safe "$STATE" && _path_components_are_safe "$WORK" || {
    echo "unsafe AdGuard Home state path" >&2; return 1;
  }
  if [ -e "$STATE" ]; then
    [ -d "$STATE" ] && [ ! -L "$STATE" ] || { echo "AdGuard Home state path is not a real directory" >&2; return 1; }
  else
    (umask 077; mkdir "$STATE") || return 1
  fi
  if [ -e "$WORK" ]; then
    [ -d "$WORK" ] && [ ! -L "$WORK" ] || { echo "AdGuard Home work path is not a real directory" >&2; return 1; }
  else
    (umask 077; mkdir "$WORK") || return 1
  fi
  chmod 700 "$STATE" "$WORK" 2>/dev/null || {
    echo "cannot enforce private AdGuard Home state/work directory permissions" >&2
    return 1
  }
  for _candidate in "$BIN" "$BIN.sha256" "$TEMPLATE" "$CFG" "$PIDFILE" "$CONFIG_HASH" "$LOG"; do
    _safe_file_or_absent "$_candidate" || {
      echo "AdGuard Home refuses a symlink or non-regular state/runtime file: $_candidate" >&2
      return 1
    }
  done
  return 0
}
_log() {
  _path_components_are_safe "$STATE" || return 0
  [ -d "$STATE" ] && [ ! -L "$STATE" ] && _safe_file_or_absent "$LOG" || return 0
  printf '[%s] adguardhome: %s\n' "$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null)" "$*" >> "$LOG" 2>/dev/null || :
}
_is_uint() { case "${1:-}" in ''|*[!0-9]*) return 1;; *) return 0;; esac; }
_hash() {
  _file=$1
  _sidecar=$2
  _safe_file_or_absent "$_file" && [ -f "$_file" ] && [ -s "$_file" ] || {
    _log "runtime input is missing, linked or not a regular file: $_file"; return 1;
  }
  _safe_file_or_absent "$_sidecar" && [ -f "$_sidecar" ] && [ -s "$_sidecar" ] || {
    _log "runtime checksum sidecar is missing, linked or not a regular file: $_sidecar"; return 1;
  }
  _expected=$(awk 'NF && length($1)==64 && $1 ~ /^[a-fA-F0-9]+$/ {print tolower($1); exit}' "$_sidecar" 2>/dev/null)
  [ "${#_expected}" -eq 64 ] || { _log "invalid SHA-256 sidecar: $_sidecar"; return 1; }
  if command -v sha256sum >/dev/null 2>&1; then
    _actual=$(sha256sum "$_file" 2>/dev/null | awk '{print tolower($1)}')
  elif command -v toybox >/dev/null 2>&1; then
    _actual=$(toybox sha256sum "$_file" 2>/dev/null | awk '{print tolower($1)}')
  else
    _log 'SHA-256 command unavailable; refusing AdGuard Home startup'; return 1
  fi
  [ "$_actual" = "$_expected" ] || { _log "SHA-256 mismatch: $_file"; return 1; }
  return 0
}
_check_files() {
  [ -x "$BIN" ] || { _log 'AdGuard Home Android ARM64 executable is missing or not executable'; return 1; }
  _safe_file_or_absent "$TEMPLATE" && [ -s "$TEMPLATE" ] || {
    _log 'AdGuard Home runtime YAML template is missing or unsafe'; return 1;
  }
  _hash "$BIN" "$BIN.sha256" || return 1
  [ -x "$PROBE" ] || { _log 'FX uncached DNS health probe is missing or not executable'; return 1; }
  _hash "$PROBE" "$PROBE.sha256"
}
_build_user_rules() {
  _output=$1
  [ -f "$PG/settings.conf" ] && [ ! -L "$PG/settings.conf" ] && [ -r "$PG/settings.conf" ] || {
    _log 'settings.conf is missing or unsafe; refusing to render DNS rules'
    return 1
  }
  : > "$_output" || return 1
  # Preserve the fixed product rules shipped with the trusted runtime template.
  awk '
    /^user_rules:[[:space:]]*$/ {inside=1; next}
    inside && /^[^[:space:]]/ {exit}
    inside && /^  - / {print}
  ' "$TEMPLATE" >> "$_output" || return 1

  # Only the dedicated [list:rule] subscription entry enables Yulong's bundled
  # ad-domain data. It never reads the protected [list:fx] anti-fraud section.
  # Read subscription state through the same strict parser as the native UI.
  # Duplicate or malformed rows must not be silently ignored when deciding
  # whether the bundled Yulong source is active.
  _rule_rows=$(MP="$MODDIR" PG="$PG" sh "$MODDIR/scripts/native-managed-lists.sh" list ruleList) || {
    _log 'managed rule subscription list is invalid; refusing partial DNS rule render'
    return 1
  }
  _yulong_enabled=$(printf '%s\\n' "$_rule_rows" | awk -F'|' '
    NR==1 {if($0!="FXLIST1") exit 2; next}
    NF!=4 || $1 !~ /^[0-9]+$/ || $4 !~ /^[01]$/ {exit 2}
    $2=="builtin://Yulong_AdBlock.txt" && $4=="1" {enabled=1}
    END {if(NR<1) exit 2; print enabled+0}
  ') || return 1
  _yulong_file=""
  if [ "$_yulong_enabled" = "1" ]; then
    _yulong_file="$PG/rulefiles-user/Yulong_AdBlock.txt"
    if ! _safe_file_or_absent "$_yulong_file" || [ ! -r "$_yulong_file" ]; then
      _yulong_file="$MODDIR/rulefiles/Yulong_AdBlock.txt"
    fi
    if ! _safe_file_or_absent "$_yulong_file" || [ ! -r "$_yulong_file" ] || [ ! -s "$_yulong_file" ]; then
      _log 'Yulong ad-domain source is enabled but its rule file is missing, empty or unsafe; refusing partial DNS rule render'
      return 1
    fi
  fi
  if [ -n "$_yulong_file" ]; then
    awk '
      /^[[:space:]]*#/ || NF < 2 {next}
      $1 != "0.0.0.0" && $1 != "127.0.0.1" {next}
      {
        d=tolower($2)
        if (d ~ /^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)+$/ && d !~ /\.\./)
          print "  - \"||" d "^\""
      }
    ' "$_yulong_file" >> "$_output" || return 1
  fi

  # Consume the same strict, duplicate-aware managed-list reader as the
  # native UI. A malformed row must fail the complete render rather than be
  # silently skipped and leave a partially applied allow/block policy.
  _domain_rows=$(MP="$MODDIR" PG="$PG" sh "$MODDIR/scripts/native-managed-lists.sh" list domainList) || {
    _log 'managed allowlist is invalid; refusing partial DNS rule render'
    return 1
  }
  _block_rows=$(MP="$MODDIR" PG="$PG" sh "$MODDIR/scripts/native-managed-lists.sh" list blockList) || {
    _log 'managed blocklist is invalid; refusing partial DNS rule render'
    return 1
  }
  printf '%s\\n' "$_domain_rows" | awk -F'|' '
    NR==1 {if($0!="FXLIST1") exit 2; next}
    NF!=4 || $1 !~ /^[0-9]+$/ || $4 !~ /^[01]$/ {exit 2}
    $4=="1" {
      d=tolower($2)
      if(d !~ /^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)*$/ || length(d)>253) exit 2
      print "  - \\"@@||" d "^\\""
    }
  ' >> "$_output" || return 1
  printf '%s\\n' "$_block_rows" | awk -F'|' '
    NR==1 {if($0!="FXLIST1") exit 2; next}
    NF!=4 || $1 !~ /^[0-9]+$/ || $4 !~ /^[01]$/ {exit 2}
    $4=="1" {
      d=tolower($2)
      if(d !~ /^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)*$/ || length(d)>253) exit 2
      print "  - \\"||" d "^\\""
    }
  ' >> "$_output" || return 1

  _unique=$(_new_private_temp "$STATE/user-rules.unique.XXXXXX") || return 1
  if ! awk '!seen[$0]++' "$_output" > "$_unique" || ! cat "$_unique" > "$_output"; then
    rm -f "$_unique" 2>/dev/null || :
    return 1
  fi
  rm -f "$_unique" 2>/dev/null || :
  chmod 600 "$_output" 2>/dev/null || return 1
  return 0
}
_build_filter_sources() {
  _output=$1
  [ -f "$PG/settings.conf" ] && [ ! -L "$PG/settings.conf" ] && [ -r "$PG/settings.conf" ] || return 1
  awk -F'|' '
    function valid_url(u, i, ch, allowed) {
      if ((index(u,"http://")!=1 && index(u,"https://")!=1)) return 0
      allowed="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._~:/?#@!$&\047()*+,;=%-"
      for (i=1; i<=length(u); i++) {
        ch=substr(u,i,1)
        if (!index(allowed,ch)) return 0
      }
      return 1
    }
    $0=="[list:rule]" {section="rule"; next}
    /^\[/ {section=""; next}
    section=="rule" && valid_url($1) && ($3=="0" || $3=="1") && !seen[$1]++ {
      url=$1
      name=$2
      gsub(/["\\]/," ",name)
      gsub(/[\r\t]/," ",name)
      gsub(/[[:cntrl:]]/," ",name)
      gsub(/[[:space:]]+/," ",name)
      sub(/^[[:space:]]+/,"",name)
      sub(/[[:space:]]+$/,"",name)
      if (name=="") name=url
      # Stable URL-derived IDs survive subscription reordering. Resolve rare
      # hash collisions deterministically within this render.
      alphabet="0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._~:/?#@!$&'()*+,;=%"
      id=0
      for (i=1; i<=length(url); i++)
        id=(id*131+index(alphabet,substr(url,i,1)))%2147483000
      id=id+1
      while (used_id[id]++) id=(id%2147483000)+1
      print "  - enabled: " ($3=="1" ? "true" : "false")
      print "    url: \"" url "\""
      print "    name: \"" name "\""
      print "    id: " id
    }
  ' "$PG/settings.conf" > "$_output" || return 1
  chmod 600 "$_output" 2>/dev/null || return 1
  return 0
}

# FX_YULONG_UPSTREAMS_BEGIN
_dns_setting_flag() {
  _flag_key=$1
  awk -F= -v key="$_flag_key" '
    function trim(s) { sub(/^[[:space:]]+/, "", s); sub(/[[:space:]]+$/, "", s); return s }
    /^[[:space:]]*#/ { next }
    index($0, "=") {
      line=$0
      split(line, pair, "=")
      name=trim(pair[1])
      if (name==key) {
        count++
        value=trim(substr(line, index(line, "=")+1))
        if (value !~ /^[01]$/) bad=1
      }
    }
    END {
      if (count==0) { print "0"; exit }
      if (count!=1 || bad) exit 1
      print value
    }
  ' "$PG/settings.conf"
}
_build_dns_upstreams() {
  _section=$1
  _mode=$2
  _output=$3
  awk -v section="$_section" -v mode="$_mode" '
    function valid_ipv4(v, n, a, i) {
      n=split(v,a,".")
      if(n!=4) return 0
      for(i=1;i<=4;i++)
        if(a[i]!~/^[0-9]+$/ || length(a[i])>3 || a[i]+0>255 ||
           (a[i]!="0" && a[i]~/^0/)) return 0
      first=a[1]+0; second=a[2]+0
      if(v=="0.0.0.0" || v=="255.255.255.255" ||
         first==0 || first==127 || first>=224 ||
         (first==169 && second==254)) return 0
      return 1
    }
    function dns_host(v, n, labels, i) {
      if(v~/^[0-9.]+$/) return valid_ipv4(v)
      if(length(v)>253 || substr(v,1,1)=="." || substr(v,length(v),1)==".") return 0
      n=split(v,labels,".")
      for(i=1;i<=n;i++)
        if(length(labels[i])<1 || length(labels[i])>63 ||
           labels[i]!~/^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?$/) return 0
      return 1
    }
    function valid_hostport(v, n, a) {
      n=split(v,a,":")
      if(n==1) return dns_host(a[1])
      if(n==2) return dns_host(a[1]) && a[2]~/^[0-9]+$/ &&
        a[2]+0>=1 && a[2]+0<=65535
      return 0
    }
    function valid_ipv4_port(v, n, a) {
      n=split(v,a,":")
      return n==2 && valid_ipv4(a[1]) && a[2]~/^[0-9]+$/ &&
        a[2]+0>=1 && a[2]+0<=65535
    }
    function valid_endpoint(v, rest, parts, authority) {
      if(valid_ipv4(v) || valid_ipv4_port(v)) return 1
      if(substr(v,1,8)=="https://") {
        rest=substr(v,9)
        split(rest,parts,"/")
        authority=parts[1]
        if(!valid_hostport(authority)) return 0
        return rest~/^[A-Za-z0-9.-]+(:[0-9]+)?(\\/[A-Za-z0-9._~!$&()*+,;=:@%/?#-]*)?$/
      }
      if(substr(v,1,6)=="tls://") return valid_hostport(substr(v,7))
      if(substr(v,1,7)=="quic://") return valid_hostport(substr(v,8))
      return 0
    }
    BEGIN { inside=0; sections=0; count=0; bad=0 }
    $0=="[conf:" section "]" {
      sections++
      if(sections>1 || inside) bad=1
      inside=1
      next
    }
    /^\\[/ { inside=0 }
    inside && /^[[:space:]]*#/ { next }
    inside && /^[[:space:]]*$/ { next }
    inside {
      if(NF!=2 || $1!="nameserver") {bad=1; next}
      server=$2
      if(mode=="ipv4" ? !(valid_ipv4(server) || valid_ipv4_port(server)) : !valid_endpoint(server)) {
        bad=1
        next
      }
      normalized=tolower(server)
      if(seen[normalized]++) {bad=1; next}
      print "  - \"" server "\""
      count++
    }
    END { if(bad || sections!=1 || count<1) exit 1 }
  ' "$PG/settings.conf" > "$_output"
}
# FX_YULONG_UPSTREAMS_END

_render_managed_config() {
  _rules_file=$(_new_private_temp "$STATE/user-rules.XXXXXX") || return 1
  _filters_file=$(_new_private_temp "$STATE/filter-sources.XXXXXX") || {
    rm -f "$_rules_file" 2>/dev/null || :
    return 1
  }
  _fallback_file=$(_new_private_temp "$STATE/fallback-dns.XXXXXX") || {
    rm -f "$_rules_file" "$_filters_file" 2>/dev/null || :
    return 1
  }
  _upstream_file=$(_new_private_temp "$STATE/upstream-dns.XXXXXX") || {
    rm -f "$_rules_file" "$_filters_file" "$_fallback_file" 2>/dev/null || :
    return 1
  }
  _bootstrap_file=$(_new_private_temp "$STATE/bootstrap-dns.XXXXXX") || {
    rm -f "$_rules_file" "$_filters_file" "$_fallback_file" "$_upstream_file" 2>/dev/null || :
    return 1
  }
  _config_file=$(_new_private_temp "$STATE/AdGuardHome.yaml.tmp.XXXXXX") || {
    rm -f "$_rules_file" "$_filters_file" "$_fallback_file" "$_upstream_file" "$_bootstrap_file" 2>/dev/null || :
    return 1
  }
  [ -f "$PG/settings.conf" ] && [ ! -L "$PG/settings.conf" ] && [ -r "$PG/settings.conf" ] || {
    _log 'settings.conf is missing, unreadable or unsafe; refusing DNS config render'
    rm -f "$_rules_file" "$_filters_file" "$_fallback_file" "$_upstream_file" "$_bootstrap_file" "$_config_file" 2>/dev/null || :
    return 1
  }
  if ! _build_user_rules "$_rules_file" || ! _build_filter_sources "$_filters_file"; then
    rm -f "$_rules_file" "$_filters_file" "$_fallback_file" "$_upstream_file" "$_bootstrap_file" "$_config_file" 2>/dev/null || :
    return 1
  fi
  _custom_dns_enabled=$(_dns_setting_flag custom_dns) || {
    _log 'custom DNS enable flag is duplicated or malformed'
    rm -f "$_rules_file" "$_filters_file" "$_fallback_file" "$_upstream_file" "$_bootstrap_file" "$_config_file" 2>/dev/null || :
    return 1
  }
  _global_dns_enabled=$(_dns_setting_flag global_dns) || {
    _log 'global DNS enable flag is duplicated or malformed'
    rm -f "$_rules_file" "$_filters_file" "$_fallback_file" "$_upstream_file" "$_bootstrap_file" "$_config_file" 2>/dev/null || :
    return 1
  }
  if [ "$_global_dns_enabled" = 1 ]; then
    _build_dns_upstreams global_dns ipv4 "$_upstream_file" || {
      _log 'global DNS is enabled but its complete upstream list is invalid'
      rm -f "$_rules_file" "$_filters_file" "$_fallback_file" "$_upstream_file" "$_bootstrap_file" "$_config_file" 2>/dev/null || :
      return 1
    }
  elif [ "$_custom_dns_enabled" = 1 ]; then
    _build_dns_upstreams custom_dns any "$_upstream_file" || {
      _log 'custom DNS is enabled but its complete upstream list is invalid'
      rm -f "$_rules_file" "$_filters_file" "$_fallback_file" "$_upstream_file" "$_bootstrap_file" "$_config_file" 2>/dev/null || :
      return 1
    }
  else
    printf '  - 127.0.0.1:5353\n' > "$_upstream_file" || return 1
  fi
  : > "$_bootstrap_file" || return 1
  if grep -Eq 'https://|tls://|quic://' "$_upstream_file"; then
    # Keep encrypted-upstream bootstrap on FX's own recursive resolver.
    # Unbound resolves the hostname without introducing a fixed public DNS dependency.
    printf '  - 127.0.0.1:5353\n' > "$_bootstrap_file" || return 1
  fi
  _dns_querylog_enabled=$(_dns_setting_flag dns_querylog_enabled) || {
    _log 'DNS query-log enable flag is duplicated or malformed'
    rm -f "$_rules_file" "$_filters_file" "$_fallback_file" "$_upstream_file" "$_bootstrap_file" "$_config_file" 2>/dev/null || :
    return 1
  }
  _dns_runtime_output=$(MP="$MODDIR" PG="$PG" sh "$MODDIR/scripts/yulong-ad-control.sh" dns-runtime-get) || {
    _log 'unable to read complete AdGuard Home runtime settings'
    rm -f "$_rules_file" "$_filters_file" "$_fallback_file" "$_upstream_file" "$_bootstrap_file" "$_config_file" 2>/dev/null || :
    return 1
  }
  _dns_runtime_upstream_mode=$(printf '%s\n' "$_dns_runtime_output" | sed -n 's/^UPSTREAM_MODE=//p')
  _dns_runtime_fastest_timeout=$(printf '%s\n' "$_dns_runtime_output" | sed -n 's/^FASTEST_TIMEOUT=//p')
  _dns_runtime_upstream_timeout=$(printf '%s\n' "$_dns_runtime_output" | sed -n 's/^UPSTREAM_TIMEOUT=//p')
  _dns_runtime_cache_size=$(printf '%s\n' "$_dns_runtime_output" | sed -n 's/^CACHE_SIZE=//p')
  _dns_runtime_cache_ttl_min=$(printf '%s\n' "$_dns_runtime_output" | sed -n 's/^CACHE_TTL_MIN=//p')
  _dns_runtime_cache_ttl_max=$(printf '%s\n' "$_dns_runtime_output" | sed -n 's/^CACHE_TTL_MAX=//p')
  _dns_runtime_optimistic_answer_ttl=$(printf '%s\n' "$_dns_runtime_output" | sed -n 's/^CACHE_OPTIMISTIC_ANSWER_TTL=//p')
  _dns_runtime_optimistic_max_age=$(printf '%s\n' "$_dns_runtime_output" | sed -n 's/^CACHE_OPTIMISTIC_MAX_AGE=//p')
  _dns_runtime_cache_enabled=$(printf '%s\n' "$_dns_runtime_output" | sed -n 's/^CACHE_ENABLED=//p')
  _dns_runtime_cache_optimistic=$(printf '%s\n' "$_dns_runtime_output" | sed -n 's/^CACHE_OPTIMISTIC=//p')
  _dns_runtime_dnssec=$(printf '%s\n' "$_dns_runtime_output" | sed -n 's/^ENABLE_DNSSEC=//p')
  [ -n "$_dns_runtime_upstream_mode" ] && [ -n "$_dns_runtime_fastest_timeout" ] &&
    [ -n "$_dns_runtime_upstream_timeout" ] && [ -n "$_dns_runtime_cache_size" ] &&
    [ -n "$_dns_runtime_cache_ttl_min" ] && [ -n "$_dns_runtime_cache_ttl_max" ] &&
    [ -n "$_dns_runtime_optimistic_answer_ttl" ] && [ -n "$_dns_runtime_optimistic_max_age" ] &&
    [ -n "$_dns_runtime_cache_enabled" ] && [ -n "$_dns_runtime_cache_optimistic" ] &&
    [ -n "$_dns_runtime_dnssec" ] || {
      _log 'AdGuard Home runtime settings response is incomplete'
      rm -f "$_rules_file" "$_filters_file" "$_fallback_file" "$_upstream_file" "$_bootstrap_file" "$_config_file" 2>/dev/null || :
      return 1
    }
  _querylog_interval=$(awk '
    BEGIN { inside=0; sections=0; intervals=0; value=""; bad=0 }
    $0=="[conf:yulong_dns_querylog_retention]" {
      sections++
      if (inside) bad=1
      inside=1
      next
    }
    /^\\[/ { inside=0 }
    inside && /^[[:space:]]*#/ { next }
    inside && /^[[:space:]]*$/ { next }
    inside && /^interval=/ {
      intervals++
      value=substr($0,10)
      if (value ~ /^[0-9]+d$/) {
        retention_value=substr(value,1,length(value)-1)
        retention_max=365
      } else if (value ~ /^[0-9]+h$/) {
        retention_value=substr(value,1,length(value)-1)
        retention_max=8760
      } else {
        bad=1
        next
      }
      if (retention_value+0<1 || retention_value+0>retention_max ||
          int(retention_value+0)!=retention_value+0) bad=1
      next
    }
    inside { bad=1 }
    END {
      if (sections>1 || intervals>1 || bad) exit 1
      if (sections==0) print "7d"
      else if (intervals==1) print value
      else exit 1
    }
  ' "$PG/settings.conf" 2>/dev/null) || {
    _log 'saved DNS query-log retention setting is ambiguous or invalid; refusing to render AdGuard config'
    rm -f "$_rules_file" "$_filters_file" "$_fallback_file" "$_upstream_file" "$_bootstrap_file" "$_config_file" 2>/dev/null || :
    return 1
  }
  _querylog_runtime_output=$(MP="$MODDIR" PG="$PG" sh "$MODDIR/scripts/yulong-ad-control.sh" dns-querylog-runtime-get 2>/dev/null) || {
    _log 'unable to read query-log memory buffer setting'
    rm -f "$_rules_file" "$_filters_file" "$_fallback_file" "$_upstream_file" "$_bootstrap_file" "$_config_file" 2>/dev/null || :
    return 1
  }
  _querylog_memory_size=$(printf '%s\n' "$_querylog_runtime_output" | sed -n 's/^memory_size=//p')
  case "$_querylog_memory_size" in ''|*[!0-9]*)
    _log 'query-log memory buffer setting is missing or malformed'
    rm -f "$_rules_file" "$_filters_file" "$_fallback_file" "$_upstream_file" "$_bootstrap_file" "$_config_file" 2>/dev/null || :
    return 1
    ;;
  esac
  _dns_response_mode=$(awk '
    BEGIN { inside=0; sections=0; modes=0; value=""; bad=0 }
    $0=="[conf:yulong_dns_response]" {
      sections++
      if (inside) bad=1
      inside=1
      next
    }
    /^\\[/ { inside=0 }
    inside && /^[[:space:]]*#/ { next }
    inside && /^[[:space:]]*$/ { next }
    inside && /^mode=/ {
      modes++
      value=substr($0,6)
      if (value!="nxdomain" && value!="refused" && value!="custom_ip") bad=1
      next
    }
    inside { bad=1 }
    END {
      if (sections>1 || modes>1 || bad) exit 1
      if (sections==0) print "nxdomain"
      else if (modes==1) print value
      else exit 1
    }
  ' "$PG/settings.conf" 2>/dev/null) || {
    _log 'saved DNS blocking response mode is ambiguous or invalid; refusing to render AdGuard config'
    rm -f "$_rules_file" "$_filters_file" "$_fallback_file" "$_upstream_file" "$_bootstrap_file" "$_config_file" 2>/dev/null || :
    return 1
  }
  if ! awk '
    function valid_ipv4(s, n,a,i) {
      n=split(s,a,".")
      if(n!=4) return 0
      for(i=1;i<=4;i++) if(a[i]!~/^[0-9]+$/ || length(a[i])>3 || a[i]+0>255 || (a[i]!="0" && a[i]~/^0/)) return 0
      # Fallback resolvers must be externally routable IPv4 endpoints.
      # Loopback would send a failed query back into AdGuard itself, while
      # link-local addresses are not stable upstream resolver destinations.
      if(a[1]+0==0 || a[1]+0==127 || a[1]+0>=224) return 0
      if(a[1]+0==169 && a[2]+0==254) return 0
      return 1
    }
    function valid_ipv4_port(s,n,a) {
      n=split(s,a,":")
      return n==2 && valid_ipv4(a[1]) && a[2]~/^[0-9]+$/ &&
        a[2]+0>=1 && a[2]+0<=65535
    }
    $0=="[conf:yulong_dns_fallback]" {sections++; if(sections>1) bad=1; inside=1; next}
    /^\[/ {inside=0}
    inside && /^[[:space:]]*#/ {next}
    inside && /^[[:space:]]*$/ {next}
    inside && /^[[:space:]]*[^#[:space:]]/ {
      # Accept only complete nameserver key/value pairs; reject malformed,
      # duplicate, unknown, or empty fallback entries instead of skipping them.
      if(NF!=2 || $1!="nameserver") {bad=1; next}
      server=$2
      if(!valid_ipv4(server) && !valid_ipv4_port(server)) {bad=1; next}
      if(seen[server]++) {bad=1; next}
      count++
      print "  - " server
    }
    END {if(bad || sections>1) exit 1}
  ' "$PG/settings.conf" > "$_fallback_file"; then
    rm -f "$_rules_file" "$_filters_file" "$_fallback_file" "$_upstream_file" "$_bootstrap_file" "$_config_file" 2>/dev/null || :
    _log 'saved fallback DNS list is invalid; refusing to render AdGuard config'
    return 1
  fi
  # When an explicitly selected external upstream has no user-supplied
  # fallback, keep DNS available through FX's own recursive Unbound service.
  # Explicit fallback entries remain authoritative and are never overwritten.
  if [ ! -s "$_fallback_file" ] &&
     { [ "$_custom_dns_enabled" = 1 ] || [ "$_global_dns_enabled" = 1 ]; }; then
    printf '  - 127.0.0.1:5353\n' > "$_fallback_file" || return 1
  fi
  if ! awk -v querylog_interval="$_querylog_interval" -v querylog_memory_size="$_querylog_memory_size" -v querylog_enabled="$_dns_querylog_enabled" -v dns_response_mode="$_dns_response_mode" -v upstream_mode="$_dns_runtime_upstream_mode" -v fastest_timeout="$_dns_runtime_fastest_timeout" -v upstream_timeout="$_dns_runtime_upstream_timeout" -v cache_size="$_dns_runtime_cache_size" -v cache_ttl_min="$_dns_runtime_cache_ttl_min" -v cache_ttl_max="$_dns_runtime_cache_ttl_max" -v optimistic_answer_ttl="$_dns_runtime_optimistic_answer_ttl" -v optimistic_max_age="$_dns_runtime_optimistic_max_age" -v cache_enabled="$_dns_runtime_cache_enabled" -v cache_optimistic="$_dns_runtime_cache_optimistic" -v dnssec="$_dns_runtime_dnssec" -v rules_file="$_rules_file" -v filters_file="$_filters_file" -v fallback_file="$_fallback_file" -v upstream_file="$_upstream_file" -v bootstrap_file="$_bootstrap_file" '
    /^querylog:[[:space:]]*$/ {in_querylog=1; print; next}
    in_querylog && /^[^[:space:]]/ {in_querylog=0}
    in_querylog && /^  enabled:/ {
      print "  enabled: " (querylog_enabled=="1" ? "true" : "false")
      next
    }
    in_querylog && /^  file_enabled:/ {
      print "  file_enabled: " (querylog_enabled=="1" ? "true" : "false")
      next
    }
    in_querylog && /^  interval:/ {print "  interval: " querylog_interval; next}
    in_querylog && /^  size_memory:/ {print "  size_memory: " querylog_memory_size; next}
    /^  upstream_mode:/ {print "  upstream_mode: " upstream_mode; next}
    /^  fastest_timeout:/ {print "  fastest_timeout: " fastest_timeout; next}
    /^  upstream_timeout:/ {print "  upstream_timeout: " upstream_timeout; next}
    /^  cache_enabled:/ {print "  cache_enabled: " (cache_enabled=="1" ? "true" : "false"); next}
    /^  cache_size:/ {print "  cache_size: " cache_size; next}
    /^  cache_ttl_min:/ {print "  cache_ttl_min: " cache_ttl_min; next}
    /^  cache_ttl_max:/ {print "  cache_ttl_max: " cache_ttl_max; next}
    /^  cache_optimistic_answer_ttl:/ {print "  cache_optimistic_answer_ttl: " optimistic_answer_ttl; next}
    /^  cache_optimistic_max_age:/ {print "  cache_optimistic_max_age: " optimistic_max_age; next}
    /^  cache_optimistic:/ {print "  cache_optimistic: " (cache_optimistic=="1" ? "true" : "false"); next}
    /^  enable_dnssec:/ {print "  enable_dnssec: " (dnssec=="1" ? "true" : "false"); next}
    # FX_YULONG_DNS_RESPONSE_BEGIN
    /^  blocking_mode:/ {
      print "  blocking_mode: " dns_response_mode
      if (dns_response_mode=="custom_ip") {
        print "  blocking_ipv4: \"0.0.0.0\""
        print "  blocking_ipv6: \"::\""
      }
      next
    }
    /^  upstream_dns:[[:space:]]*$/ {
      print
      while ((getline upstream < upstream_file) > 0) print upstream
      close(upstream_file)
      if ((getline bootstrap < bootstrap_file) > 0) {
        print "  bootstrap_dns:"
        print bootstrap
        while ((getline bootstrap < bootstrap_file) > 0) print bootstrap
      }
      close(bootstrap_file)
      next
    }
    /^  fallback_dns:[[:space:]]*\[\][[:space:]]*$/ {
      if ((getline fallback < fallback_file) > 0) {
        print "  fallback_dns:"
        print fallback
        while ((getline fallback < fallback_file) > 0) print fallback
      } else {
        print "  fallback_dns: []"
      }
      close(fallback_file)
      next
    }
    /^filters:[[:space:]]*\[\][[:space:]]*$/ {
      if ((getline filter < filters_file) > 0) {
        print "filters:"
        print filter
        while ((getline filter < filters_file) > 0) print filter
      } else {
        print "filters: []"
      }
      close(filters_file)
      next
    }
    /^user_rules:[[:space:]]*$/ {
      print
      found_rules=1
      while ((getline rule < rules_file) > 0) print rule
      close(rules_file)
      in_rules=1
      next
    }
    in_rules && /^[^[:space:]]/ {in_rules=0}
    in_rules {next}
    {print}
    END {if (!found_rules) exit 2}
  ' "$TEMPLATE" > "$_config_file"; then
    rm -f "$_rules_file" "$_filters_file" "$_fallback_file" "$_upstream_file" "$_bootstrap_file" "$_config_file" 2>/dev/null || :
    _log 'unable to compose AdGuard Home config with managed subscriptions and DNS rules'
    return 1
  fi
  rm -f "$_rules_file" "$_filters_file" "$_fallback_file" "$_upstream_file" "$_bootstrap_file" 2>/dev/null || :
  chmod 600 "$_config_file" 2>/dev/null || {
    rm -f "$_config_file" 2>/dev/null || :
    return 1
  }
  printf '%s\n' "$_config_file"
}
_install_config() {
  _safe_file_or_absent "$CFG" || { _log 'AdGuard Home config path is unsafe'; return 1; }
  _tmp=$(_render_managed_config) || {
    _log 'unable to render managed AdGuard Home DNS rules'
    return 1
  }
  if ! mv -f "$_tmp" "$CFG"; then
    rm -f "$_tmp" 2>/dev/null || :
    _log 'unable to atomically publish AdGuard Home config'
    return 1
  fi
  # The rendered file was created by _new_private_temp (umask 077 + chmod 600);
  # atomic rename preserves its private mode, so no post-publication chmod is needed.
  _log 'published loopback-only config with current Yulong and managed allow/block DNS rules'
}

_config_contract() {
  # The DNS listener/admin interface remain loopback-only. Upstream lists may
  # be the local recursive Unbound listener or a validated FX custom/global list.
  awk '
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
    function valid_ipv4(v, n, a, i) {
      n=split(v,a,".")
      if(n!=4) return 0
      for(i=1;i<=4;i++)
        if(a[i]!~/^[0-9]+$/ || length(a[i])>3 || a[i]+0>255 ||
           (a[i]!="0" && a[i]~/^0/)) return 0
      first=a[1]+0; second=a[2]+0
      if(v=="0.0.0.0" || v=="255.255.255.255" ||
         first==0 || first==127 || first>=224 ||
         (first==169 && second==254)) return 0
      return 1
    }
    function dns_host(v, n, labels, i) {
      if(v~/^[0-9.]+$/) return valid_ipv4(v)
      if(length(v)>253 || substr(v,1,1)=="." || substr(v,length(v),1)==".") return 0
      n=split(v,labels,".")
      for(i=1;i<=n;i++)
        if(length(labels[i])<1 || length(labels[i])>63 ||
           labels[i]!~/^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?$/) return 0
      return 1
    }
    function valid_hostport(v, n, a) {
      n=split(v,a,":")
      if(n==1) return dns_host(a[1])
      if(n==2) return dns_host(a[1]) && a[2]~/^[0-9]+$/ &&
        a[2]+0>=1 && a[2]+0<=65535
      return 0
    }
    function valid_ipv4_port(v, n, a) {
      n=split(v,a,":")
      return n==2 && valid_ipv4(a[1]) && a[2]~/^[0-9]+$/ &&
        a[2]+0>=1 && a[2]+0<=65535
    }
    function valid_endpoint(v, rest, parts, authority) {
      if(valid_ipv4(v) || valid_ipv4_port(v)) return 1
      if(substr(v,1,8)=="https://") {
        rest=substr(v,9); split(rest,parts,"/"); authority=parts[1]
        if(!valid_hostport(authority)) return 0
        return rest~/^[A-Za-z0-9.-]+(:[0-9]+)?(\\/[A-Za-z0-9._~!$&()*+,;=:@%/?#-]*)?$/
      }
      if(substr(v,1,6)=="tls://") return valid_hostport(substr(v,7))
      if(substr(v,1,7)=="quic://") return valid_hostport(substr(v,8))
      return 0
    }
    /^http:$/ {http=1; next}
    http && /^[^[:space:]]/ {http=0}
    http && /^  address:/ {
      split($2,http_parts,":")
      if (http_parts[1]=="127.0.0.1" && http_parts[2] ~ /^[0-9]+$/ &&
          http_parts[2]>=0 && http_parts[2]<=65535) http_loopback=1
    }
    /^dns:$/ {dns=1; next}
    dns && /^[^[:space:]]/ {dns=0}
    dns && /^  port:/ {dns_port=$2}
    dns && /^  upstream_mode:/ {runtime_mode=$2}
    dns && /^  fastest_timeout:/ {runtime_fastest=$2}
    dns && /^  upstream_timeout:/ {runtime_timeout=$2}
    dns && /^  size_memory:/ {runtime_querylog_memory_size=$2}
    dns && /^  cache_size:/ {runtime_cache_size=$2}
    dns && /^  cache_ttl_min:/ {runtime_cache_ttl_min=$2}
    dns && /^  cache_ttl_max:/ {runtime_cache_ttl_max=$2}
    dns && /^  cache_optimistic_answer_ttl:/ {runtime_optimistic_answer_ttl=$2}
    dns && /^  cache_optimistic_max_age:/ {runtime_optimistic_max_age=$2}
    dns && /^  cache_enabled:/ {runtime_cache_enabled=$2}
    dns && /^  cache_optimistic:/ {runtime_cache_optimistic=$2}
    dns && /^  enable_dnssec:/ {runtime_dnssec=$2}
    dns && /^  bind_hosts:/ {bind=1; next}
    dns && bind && /^  [A-Za-z_][A-Za-z0-9_-]*:/ {bind=0}
    dns && bind && /^  - / {hosts[$2]=1; bind_count++}
    dns && /^  upstream_dns:/ {upstream=1; next}
    dns && upstream && /^  [A-Za-z_][A-Za-z0-9_-]*:/ {upstream=0}
    dns && upstream && /^  - / {
      server=$2
      sub(/^"/,"",server); sub(/"$/,"",server)
      upstream_count++
      if (server=="127.0.0.1:5353") {
        local_upstream=1
        local_count++
      } else if (!valid_endpoint(server)) {
        unsafe_upstream=1
      }
      if (upstream_seen[tolower(server)]++) unsafe_upstream=1
    }
    dns && /^  bootstrap_dns:/ {bootstrap=1; next}
    dns && bootstrap && /^  [A-Za-z_][A-Za-z0-9_-]*:/ {bootstrap=0}
    dns && bootstrap && /^  - / {
      server=$2
      sub(/^"/,"",server); sub(/"$/,"",server)
      bootstrap_count++
      if (server=="127.0.0.1:5353") {
        if (bootstrap_seen[server]++) unsafe_bootstrap=1
      } else {
        if (!valid_ipv4(server) || bootstrap_seen[server]++) unsafe_bootstrap=1
        first=split(server,octets,".")
        if(octets[1]+0==0 || octets[1]+0==127 || octets[1]+0>=224 ||
           (octets[1]+0==169 && octets[2]+0==254)) unsafe_bootstrap=1
      }
    }
    dns && /^  fallback_dns:/ {
      fallback=1
      # Only the empty-list form or a block sequence is accepted. A scalar,
      # extra token, or malformed inline value must not silently pass as an
      # empty fallback list.
      if (NF==2 && $2=="[]") fallback_empty=1
      else if (NF!=1) unsafe_fallback=1
      next
    }
    dns && fallback && /^  [A-Za-z_][A-Za-z0-9_-]*:/ {fallback=0}
    dns && fallback && /^  - / {
      server=$2
      fallback_count++
      if (server=="127.0.0.1:5353") {
        if (fallback_seen[server]++) unsafe_fallback=1
      } else {
        if((!valid_ipv4(server) && !valid_ipv4_port(server)) || fallback_seen[server]++)
          unsafe_fallback=1
      }
    }
    END {
      exit (http_loopback && dns_port=="53" &&
        hosts["127.0.0.1"] && hosts["::1"] && bind_count==2 &&
        upstream_count>=1 && !unsafe_upstream &&
        (!local_upstream || (local_count==1 && upstream_count==1)) &&
        !unsafe_bootstrap && !unsafe_fallback &&
        (runtime_mode=="load_balance" || runtime_mode=="parallel" || runtime_mode=="fastest_addr") &&
        valid_duration(runtime_fastest) && valid_duration(runtime_timeout) &&
        runtime_querylog_memory_size~/^[0-9]+$/ &&
        valid_uint32(runtime_cache_size,0) &&
        valid_uint32(runtime_cache_ttl_min,1) && valid_uint32(runtime_cache_ttl_max,1) &&
        runtime_cache_ttl_min+0<=runtime_cache_ttl_max+0 &&
        valid_optimistic_answer_ttl(runtime_optimistic_answer_ttl) &&
        valid_duration(runtime_optimistic_max_age) &&
        (runtime_cache_enabled=="true" || runtime_cache_enabled=="false") &&
        (runtime_cache_optimistic=="true" || runtime_cache_optimistic=="false") &&
        (runtime_dnssec=="true" || runtime_dnssec=="false")) ? 0 : 1
    }
  ' "$CFG" || {
    _log 'AdGuard config violates FX loopback/listener/local-Unbound policy'
    return 1
  }
}
_current_config_hash() {
  _safe_file_or_absent "$CFG" && [ -f "$CFG" ] && [ -s "$CFG" ] || return 1
  if command -v sha256sum >/dev/null 2>&1; then
    _digest=$(sha256sum "$CFG" 2>/dev/null | awk 'NR==1 {print tolower($1)}')
  elif command -v toybox >/dev/null 2>&1; then
    _digest=$(toybox sha256sum "$CFG" 2>/dev/null | awk 'NR==1 {print tolower($1)}')
  else
    return 1
  fi
  case "$_digest" in
    *[!a-f0-9]*|'') return 1 ;;
  esac
  [ "${#_digest}" -eq 64 ] || return 1
  printf '%s\n' "$_digest"
}
_publish_config_hash() {
  _digest=$1
  _safe_file_or_absent "$CONFIG_HASH" || return 1
  _tmp=$(_new_private_temp "$STATE/config.sha256.tmp.XXXXXX") || return 1
  if ! printf '%s\n' "$_digest" > "$_tmp" || ! chmod 600 "$_tmp" || ! mv -f "$_tmp" "$CONFIG_HASH"; then
    rm -f "$_tmp" 2>/dev/null || :
    return 1
  fi
  return 0
}
_remove_pid_marker_if_matches() {
  _expected=$1
  _safe_file_or_absent "$PIDFILE" || return 1
  [ -f "$PIDFILE" ] || return 0
  _current=$(cat "$PIDFILE" 2>/dev/null) || return 1
  [ "$_current" = "$_expected" ] || return 0
  # Isolate the marker before deletion, then verify the moved contents.
  # This prevents a stale lifecycle operation from unlinking a newer PID.
  _release="$PIDFILE.release.$$"
  _n=0
  while { [ -e "$_release" ] || [ -L "$_release" ]; } && [ "$_n" -lt 20 ]; do
    _n=$((_n + 1))
    _release="$PIDFILE.release.$$.\${_n}"
  done
  [ ! -e "$_release" ] && [ ! -L "$_release" ] || return 1
  mv "$PIDFILE" "$_release" 2>/dev/null || return 1
  _moved=$(cat "$_release" 2>/dev/null || true)
  if [ "$_moved" = "$_expected" ] && [ ! -L "$_release" ] && [ -f "$_release" ]; then
    rm -f "$_release" 2>/dev/null || return 1
    return 0
  fi
  if [ ! -e "$PIDFILE" ] && [ ! -L "$PIDFILE" ]; then
    mv "$_release" "$PIDFILE" 2>/dev/null || :
  fi
  return 1
}
_owned_pid() {
  _safe_file_or_absent "$PIDFILE" && [ -f "$PIDFILE" ] || return 1
  _p=$(cat "$PIDFILE" 2>/dev/null)
  _is_uint "$_p" && [ "$_p" -gt 1 ] 2>/dev/null || return 1
  [ -r "/proc/$_p/cmdline" ] || return 1
  _argv=$(tr '\000' '\n' < "/proc/$_p/cmdline" 2>/dev/null) || return 1
  printf '%s\n' "$_argv" | grep -Fqx -- "$BIN" || return 1
  printf '%s\n' "$_argv" | grep -Fqx -- "$CFG" || return 1
  printf '%s\n' "$_argv" | grep -Fqx -- "$WORK" || return 1
  printf '%s\n' "$_p"
}
_valid_ipv4() {
  printf '%s\n' "$1" | awk -F. '
    NF != 4 {ok=0; exit}
    {
      ok=1
      for (i=1; i<=4; i++) {
        if ($i !~ /^[0-9]+$/ || length($i)>3 || ($i+0)>255 ||
            ($i != "0" && $i ~ /^0/)) ok=0
      }
      first=$1+0
      if (first==0 || first>=224) ok=0
    }
    END {exit(ok ? 0 : 1)}
  '
}
_probe() {
  # Use a random, uncached query and validate the DNS transaction itself.
  # This checks the actual AdGuard listener and selected upstream/fallback
  # path instead of allowing a cached example.com A record to mask failures.
  "$PROBE" 127.0.0.1 53 5 >> "$LOG" 2>&1 || return 1
  "$PROBE" ::1 53 5 >> "$LOG" 2>&1 || return 1
  return 0
}
_stop() {
  _p=$(_owned_pid 2>/dev/null) || _p=
  if [ -z "$_p" ]; then
    if [ -f "$PIDFILE" ] && [ ! -L "$PIDFILE" ]; then
      _stale=$(cat "$PIDFILE" 2>/dev/null)
      if _is_uint "$_stale" && [ "$_stale" -gt 1 ] 2>/dev/null && kill -0 "$_stale" 2>/dev/null; then
        _log 'PID marker points to a live process not owned by this AdGuard Home instance; refusing to signal it'
        return 1
      fi
      rm -f "$PIDFILE" 2>/dev/null || return 1
    fi
    _log 'AdGuard Home is already stopped'
    return 0
  fi
  # Revalidate ownership immediately before signalling, matching the
  # guarded Unbound stop path and avoiding a stale/reused PID target.
  _same=$(_owned_pid 2>/dev/null) || _same=
  if [ "$_same" != "$_p" ]; then
    _log "refusing to signal PID $_p because process ownership changed before TERM"
    return 1
  fi
  kill -TERM "$_p" 2>/dev/null || :
  _now=
  _tries=0
  while kill -0 "$_p" 2>/dev/null && [ "$_tries" -lt 20 ]; do
    _now=$(_owned_pid 2>/dev/null) || _now=
    [ "$_now" = "$_p" ] || break
    sleep 1
    _tries=$((_tries+1))
  done
  if [ "$_now" = "$_p" ] && kill -0 "$_p" 2>/dev/null; then
    _now=$(_owned_pid 2>/dev/null) || _now=
    if [ "$_now" = "$_p" ]; then kill -KILL "$_p" 2>/dev/null || :; fi
  fi
  _now=
  _tries=0
  while kill -0 "$_p" 2>/dev/null && [ "$_tries" -lt 5 ]; do
    _now=$(_owned_pid 2>/dev/null) || _now=
    [ "$_now" = "$_p" ] || break
    sleep 1
    _tries=$((_tries+1))
  done
  _now=$(_owned_pid 2>/dev/null) || _now=
  if [ "$_now" = "$_p" ] && kill -0 "$_p" 2>/dev/null; then
    _log 'AdGuard Home did not stop; preserving PID marker'
    return 1
  fi
  _remove_pid_marker_if_matches "$_p" || return 1
  _log 'stopped managed DNS filter'
  return 0
}
_ensure() {
  _prepare_state_dirs || return 1
  _check_files || return 1
  _install_config || return 1
  _config_contract || return 1
  _current_hash=$(_current_config_hash) || {
    _log 'unable to calculate managed AdGuard Home config fingerprint'
    return 1
  }
  if _p=$(_owned_pid 2>/dev/null); then
    _previous_hash=
    if _safe_file_or_absent "$CONFIG_HASH" && [ -f "$CONFIG_HASH" ]; then
      _previous_hash=$(cat "$CONFIG_HASH" 2>/dev/null)
    fi
    if [ "$_previous_hash" = "$_current_hash" ] && _probe; then
      echo 'ready'
      return 0
    fi
    if [ "$_previous_hash" != "$_current_hash" ]; then
      _log 'managed DNS rules changed; restarting AdGuard Home to load the new config'
    else
      _log 'existing AdGuard Home failed uncached loopback DNS probe; restarting'
    fi
    _stop || return 1
  else
    if [ -f "$PIDFILE" ]; then
      _stale=$(cat "$PIDFILE" 2>/dev/null)
      if _is_uint "$_stale" && [ "$_stale" -gt 1 ] 2>/dev/null && kill -0 "$_stale" 2>/dev/null; then
        _log 'PID marker belongs to a live process with unrecognized argv; refusing duplicate startup'
        return 1
      fi
      rm -f "$PIDFILE" 2>/dev/null || return 1
    fi
  fi
  nohup "$BIN" --no-check-update -c "$CFG" -w "$WORK" >> "$LOG" 2>&1 </dev/null &
  _p=$!
  [ "$_p" -gt 1 ] 2>/dev/null || { _log 'failed to fork AdGuard Home'; return 1; }
  _tmp=$(_new_private_temp "$STATE/managed.pid.tmp.XXXXXX") || {
    kill "$_p" 2>/dev/null || :
    _log 'unable to create private AdGuard Home PID marker'; return 1;
  }
  if ! printf '%s\n' "$_p" > "$_tmp" || ! mv -f "$_tmp" "$PIDFILE"; then
    rm -f "$_tmp" 2>/dev/null || :
    kill "$_p" 2>/dev/null || :
    _log 'unable to publish AdGuard Home PID marker'; return 1
  fi
  _tries=0
  while [ "$_tries" -lt 30 ]; do
    _now=$(_owned_pid 2>/dev/null) || _now=
    if [ "$_now" = "$_p" ] && _probe; then
      _publish_config_hash "$_current_hash" || {
        _log 'DNS filter is healthy but config fingerprint publication failed'
        _stop || :
        return 1
      }
      _log 'ready; loopback DNS filter answers through local Unbound upstream with current managed rules'
      echo 'ready'
      return 0
    fi
    if ! kill -0 "$_p" 2>/dev/null; then break; fi
    sleep 1
    _tries=$((_tries+1))
  done
  _log 'AdGuard Home startup or loopback DNS health probe failed; stopping filter'
  _stop || :
  return 1
}


_release_lifecycle_lock() {
  [ -d "$LIFECYCLE_LOCK" ] && [ ! -L "$LIFECYCLE_LOCK" ] || return 0
  _lock_owner_file="$LIFECYCLE_LOCK/owner"
  [ -f "$_lock_owner_file" ] && [ ! -L "$_lock_owner_file" ] || return 0
  _lock_owner=$(cat "$_lock_owner_file" 2>/dev/null) || return 0
  [ "$_lock_owner" = "$$" ] || return 0
  rm -f "$_lock_owner_file" 2>/dev/null || return 1
  rmdir "$LIFECYCLE_LOCK" 2>/dev/null || return 1
  return 0
}
_with_lifecycle_lock() {
  _locked_action=$1
  _prepare_state_dirs || return 1
  _wait=0
  while ! mkdir "$LIFECYCLE_LOCK" 2>/dev/null; do
    [ ! -L "$LIFECYCLE_LOCK" ] && [ -d "$LIFECYCLE_LOCK" ] || {
      _log 'unsafe AdGuard Home lifecycle lock path'
      return 1
    }
    if [ "$_wait" -ge 35 ]; then
      _log 'AdGuard Home lifecycle operation is busy; refusing concurrent start/stop'
      return 1
    fi
    sleep 1
    _wait=$((_wait+1))
  done
  if ! printf '%s\n' "$$" > "$LIFECYCLE_LOCK/owner"; then
    rmdir "$LIFECYCLE_LOCK" 2>/dev/null || :
    _log 'unable to publish AdGuard Home lifecycle lock owner'
    return 1
  fi
  chmod 700 "$LIFECYCLE_LOCK" 2>/dev/null || {
    rm -f "$LIFECYCLE_LOCK/owner" 2>/dev/null || :
    rmdir "$LIFECYCLE_LOCK" 2>/dev/null || :
    return 1
  }
  trap '_release_lifecycle_lock' EXIT
  trap 'exit 1' HUP INT TERM
  "$_locked_action"
}

case "$ACTION" in
  ensure)
    _with_lifecycle_lock _ensure
    ;;
  stop)
    _with_lifecycle_lock _stop
    ;;
  status)
    if [ -z "$PG" ] || [ ! -d "$PG" ] || [ -L "$PG" ] || ! _path_components_are_safe "$PG"; then
      echo 'unknown'
      exit 2
    fi
    if _p=$(_owned_pid 2>/dev/null); then
      if _probe; then echo ready; exit 0; fi
      echo running-unhealthy
      exit 1
    fi
    echo stopped
    exit 1
    ;;
  render-config)
    _prepare_state_dirs || exit 1
    cat "$TEMPLATE"
    ;;
  *)
    echo 'usage: adguardhome.sh {ensure|stop|status|render-config} [module_dir] [data_dir]' >&2
    exit 64
    ;;
esac
