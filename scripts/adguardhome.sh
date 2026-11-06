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
LOG="$STATE/engine.log"
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
  chmod 700 "$STATE" "$WORK" 2>/dev/null || :
  for _candidate in "$BIN" "$BIN.sha256" "$TEMPLATE" "$CFG" "$PIDFILE" "$LOG"; do
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
  _hash "$BIN" "$BIN.sha256"
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
  _yulong_enabled=$(awk -F'|' '
    /^\[list:rule\][[:space:]]*$/ {section="rule"; next}
    /^\[/ {section=""; next}
    section=="rule" && $1=="builtin://Yulong_AdBlock.txt" && $3=="1" {enabled=1}
    END {print enabled+0}
  ' "$PG/settings.conf" 2>/dev/null)
  _yulong_file=""
  if [ "$_yulong_enabled" = "1" ]; then
    _yulong_file="$PG/rulefiles-user/Yulong_AdBlock.txt"
    if ! _safe_file_or_absent "$_yulong_file" || [ ! -r "$_yulong_file" ]; then
      _yulong_file="$MODDIR/rulefiles/Yulong_AdBlock.txt"
    fi
    if ! _safe_file_or_absent "$_yulong_file" || [ ! -r "$_yulong_file" ]; then
      _yulong_file=""
      _log 'Yulong ad-domain source is enabled but its rule file is unavailable; continuing with other DNS rules'
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

  # User allow/block lists are translated to AdGuard syntax. Strict domain
  # validation happens again here so corrupted settings cannot inject YAML.
  awk -F'|' '
    function valid(d) {
      return d ~ /^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$/
    }
    $0=="[list:domain]" {section="domain"; next}
    $0=="[list:block]" {section="block"; next}
    /^\[/ {section=""; next}
    section=="domain" && valid($1) && (NF<3 || $3=="1") {
      print "  - \"@@||" tolower($1) "^\""
    }
    section=="block" && valid($1) && (NF<3 || $3=="1") {
      print "  - \"||" tolower($1) "^\""
    }
  ' "$PG/settings.conf" >> "$_output" || return 1

  _unique=$(_new_private_temp "$STATE/user-rules.unique.XXXXXX") || return 1
  if ! awk '!seen[$0]++' "$_output" > "$_unique" || ! cat "$_unique" > "$_output"; then
    rm -f "$_unique" 2>/dev/null || :
    return 1
  fi
  rm -f "$_unique" 2>/dev/null || :
  chmod 600 "$_output" 2>/dev/null || return 1
  return 0
}
_render_managed_config() {
  _rules_file=$(_new_private_temp "$STATE/user-rules.XXXXXX") || return 1
  _config_file=$(_new_private_temp "$STATE/AdGuardHome.yaml.tmp.XXXXXX") || {
    rm -f "$_rules_file" 2>/dev/null || :
    return 1
  }
  if ! _build_user_rules "$_rules_file"; then
    rm -f "$_rules_file" "$_config_file" 2>/dev/null || :
    return 1
  fi
  if ! awk -v rules_file="$_rules_file" '
    /^user_rules:[[:space:]]*$/ {
      print
      found=1
      while ((getline rule < rules_file) > 0) print rule
      close(rules_file)
      in_rules=1
      next
    }
    in_rules && /^[^[:space:]]/ {in_rules=0}
    in_rules {next}
    {print}
    END {if (!found) exit 2}
  ' "$TEMPLATE" > "$_config_file"; then
    rm -f "$_rules_file" "$_config_file" 2>/dev/null || :
    _log 'unable to compose AdGuard Home config with managed DNS rules'
    return 1
  fi
  rm -f "$_rules_file" 2>/dev/null || :
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
  chmod 600 "$CFG" 2>/dev/null || return 1
  _log 'published loopback-only config with current Yulong and managed allow/block DNS rules'
}

_config_contract() {
  # AdGuard must remain a loopback-only DNS filter. Its sole upstream is the
  # local recursive Unbound listener; never allow a saved config to introduce
  # a public resolver or expose the DNS/admin listeners on LAN interfaces.
  awk '
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
    dns && /^  bind_hosts:/ {bind=1; next}
    dns && bind && /^  [A-Za-z_][A-Za-z0-9_-]*:/ {bind=0}
    dns && bind && /^  - / {hosts[$2]=1; bind_count++}
    dns && /^  upstream_dns:/ {upstream=1; next}
    dns && upstream && /^  [A-Za-z_][A-Za-z0-9_-]*:/ {upstream=0}
    dns && upstream && /^  - / {
      upstream_count++
      if ($2=="127.0.0.1:5353") local_upstream=1
      else unsafe_upstream=1
    }
    END {
      exit (http_loopback && dns_port=="53" &&
        hosts["127.0.0.1"] && hosts["::1"] && bind_count==2 &&
        upstream_count==1 && local_upstream && !unsafe_upstream) ? 0 : 1
    }
  ' "$CFG" || {
    _log 'AdGuard config violates FX loopback/listener/local-Unbound policy'
    return 1
  }
}
_remove_pid_marker_if_matches() {
  _expected=$1
  _safe_file_or_absent "$PIDFILE" || return 1
  [ -f "$PIDFILE" ] || return 0
  _current=$(cat "$PIDFILE" 2>/dev/null)
  [ "$_current" = "$_expected" ] || return 0
  rm -f "$PIDFILE" 2>/dev/null || :
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
_probe_endpoint() {
  _server=$1
  _probe_output=$(timeout 5 nslookup example.com "$_server" 2>&1) || return 1
  _probe_answers=$(printf '%s\n' "$_probe_output" | awk '
    tolower($0) ~ /^[[:space:]]*name:[[:space:]]*example[.]com([.]?)([[:space:]]|$)/ {
      answer=1; next
    }
    answer && tolower($0) ~ /^[[:space:]]*address([[:space:]]+[0-9]+)?:[[:space:]]*[0-9]+([.][0-9]+){3}([[:space:]]|$)/ {
      print $NF
    }
  ')
  for _answer in $_probe_answers; do
    _valid_ipv4 "$_answer" && return 0
  done
  return 1
}
_probe() {
  command -v nslookup >/dev/null 2>&1 && command -v timeout >/dev/null 2>&1 || return 1
  _probe_endpoint 127.0.0.1 || return 1
  _probe_endpoint ::1 || return 1
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
  if _p=$(_owned_pid 2>/dev/null); then
    if _probe; then
      echo 'ready'
      return 0
    fi
    _log 'existing AdGuard Home failed uncached loopback DNS probe; restarting'
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
      _log 'ready; loopback DNS filter answers through local Unbound upstream'
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

case "$ACTION" in
  ensure)
    _ensure
    ;;
  stop)
    _prepare_state_dirs || exit 1
    _stop
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
