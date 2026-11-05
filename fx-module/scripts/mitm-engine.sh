#!/system/bin/sh
# PrivacyGuard TLS MITM engine lifecycle and explicit CA trust synchronization.
# Firewall redirects are managed separately; the engine binds only to loopback.
PG=/data/adb/privacyguard
MODDIR=${PG_MODDIR:-${MODDIR:-}}
if [ -z "$MODDIR" ] || [ ! -f "$MODDIR/module.prop" ]; then
  _d=$(cd "$(dirname "$0")" 2>/dev/null && pwd); case "$_d" in */scripts) _d=${_d%/scripts} ;; esac; MODDIR=$_d
fi
BIN="$MODDIR/bin/arm64/pg-mitm"
[ -x "$BIN" ] || BIN="$MODDIR/bin/arm/pg-mitm"
DIR="$PG/mitm"
PID="$DIR/engine.pid"
LOG="$DIR/engine.log"
CERTS="$MODDIR/certs"
CAID="$CERTS/ca-index"
TEMPLATE="$CERTS/submodules/pg_mitm_ca/system/etc/security/cacerts"
CHILD="/data/adb/modules/pg_mitm_ca"
CERTMGR="$MODDIR/scripts/certmgr.sh"
# Keep read-only status queries side-effect free. Only lifecycle/mutation commands
# create the private runtime directory.
ensure_runtime_dir() {
  mkdir -p "$DIR" 2>/dev/null || return 1
  chmod 700 "$DIR" 2>/dev/null || return 1
}
# Match argv[0] exactly. A substring search across the whole command line can
# mistake an unrelated process that merely has the engine path in an argument
# for the engine itself, which is unsafe before sending signals.
is_engine_pid() {
  _iep_pid=$1
  case "$_iep_pid" in ''|*[!0-9]*) return 1 ;; esac
  [ -r "/proc/$_iep_pid/cmdline" ] || return 1
  _iep_argv0=$(tr '\000' '\n' < "/proc/$_iep_pid/cmdline" 2>/dev/null | sed -n '1p')
  [ -n "$_iep_argv0" ] && [ "$_iep_argv0" = "$BIN" ]
}
# A live PID is not proof that the socket is bound. Before a transparent
# redirect is installed, require the exact loopback listener to appear in the
# kernel TCP table. The helper is also used by read-only status reporting.
listener_ready() {
  [ -x "$MODDIR/scripts/mitm-listener-health.sh" ] || return 1
  (unset PG_PROC_NET_TCP; sh "$MODDIR/scripts/mitm-listener-health.sh" check) >/dev/null 2>&1
}
wait_for_listener() {
  _wfl_i=0
  while [ "$_wfl_i" -lt 6 ]; do
    is_engine_pid "$1" && listener_ready && return 0
    is_engine_pid "$1" || return 1
    sleep 1
    _wfl_i=$((_wfl_i+1))
  done
  is_engine_pid "$1" && listener_ready
}

# The CA index intentionally stores a 16-hex-character prefix for compatibility.
# Trust verification must use the full SHA-256 digest to avoid treating a prefix
# collision as proof that the installed system certificate is our CA.
ca_fingerprint256() {
  sed -n '/BEGIN CERTIFICATE/,/END CERTIFICATE/p' "$1" 2>/dev/null \
    | grep -v -- '-----' | tr -d '\r\n \t' | base64 -d 2>/dev/null \
    | sha256sum 2>/dev/null | awk '{print tolower($1)}'
}
ca_fingerprint16() {
  ca_fingerprint256 "$1" | cut -c1-16
}

# Restore the trust transaction backup conservatively. Never delete the
# backup unless every required restoration operation succeeded.
restore_trust_backup() {
  _rbk=$1
  [ -d "$_rbk" ] || return 1
  [ -f "$_rbk/ca-index" ] && [ -f "$_rbk/template/$_h_old.0" ] && [ -f "$_rbk/template/$_h_new.0" ] || return 1
  cp -p "$_rbk/ca-index" "$CAID" || return 1
  cp -p "$_rbk/template/$_h_old.0" "$TEMPLATE/$_h_old.0" || return 1
  cp -p "$_rbk/template/$_h_new.0" "$TEMPLATE/$_h_new.0" || return 1
  rm -rf "$CHILD" || return 1
  if [ -d "$_rbk/child" ]; then
    cp -R "$_rbk/child" "$CHILD" || return 1
  fi
  sh "$CERTMGR" builtin sync >/dev/null 2>&1 || return 1
  rm -rf "$_rbk" || return 1
  return 0
}

# If the CA child module was already released, its files are not a live copy of
# certs/submodules/pg_mitm_ca: KernelSU mounts the child module directory itself.
# Update that real source transactionally as well, or the runtime private key
# and the CA visible to Android can differ. A missing/removed child is left for
# certmgr's normal enable path to rebuild from the verified template.
sync_runtime_cert_to_child() {
  [ -d "$CHILD" ] || return 0
  [ ! -f "$CHILD/remove" ] || return 0
  _src_dir="$CHILD/system/etc/security/cacerts"
  [ -d "$_src_dir" ] || { echo 'MITM CA child module exists but its cacerts directory is missing' >&2; return 1; }
  _stage_dir="${_src_dir}.runtime-stage.$$"
  _prev_dir="${_src_dir}.runtime-prev.$$"
  [ ! -e "$_stage_dir" ] && [ ! -e "$_prev_dir" ] || { echo 'MITM CA child update has leftover staging data; refusing to overwrite it' >&2; return 1; }
  cp -R "$_src_dir" "$_stage_dir" || { echo 'Unable to stage existing MITM CA child certificates' >&2; return 1; }
  for _old_cert in "$_stage_dir/"*.0; do
    [ -f "$_old_cert" ] || continue
    rm -f "$_old_cert" || { rm -rf "$_stage_dir"; echo 'Unable to remove stale staged MITM CA certificate' >&2; return 1; }
  done
  if ! cp "$DIR/ca.pem" "$_stage_dir/$_h_old.0" || ! cp "$DIR/ca.pem" "$_stage_dir/$_h_new.0"; then
    rm -rf "$_stage_dir"
    echo 'Unable to stage runtime MITM CA certificate in child module' >&2
    return 1
  fi
  chmod 644 "$_stage_dir/"*.0 2>/dev/null || { rm -rf "$_stage_dir"; echo 'Unable to set runtime MITM CA certificate permissions' >&2; return 1; }
  [ "$(ca_fingerprint256 "$_stage_dir/$_h_old.0")" = "$_runtime_fp256" ] &&     [ "$(ca_fingerprint256 "$_stage_dir/$_h_new.0")" = "$_runtime_fp256" ] || {
      rm -rf "$_stage_dir"
      echo 'Staged MITM CA child certificate fingerprint mismatch' >&2
      return 1
    }
  if ! mv "$_src_dir" "$_prev_dir"; then
    rm -rf "$_stage_dir"
    echo 'Unable to preserve existing MITM CA child certificate directory' >&2
    return 1
  fi
  if ! mv "$_stage_dir" "$_src_dir"; then
    mv "$_prev_dir" "$_src_dir" 2>/dev/null || echo 'CRITICAL: old MITM CA child certificate directory remains at staging path' >&2
    rm -rf "$_stage_dir"
    echo 'Unable to publish runtime MITM CA child certificate directory' >&2
    return 1
  fi
  if ! rm -rf "$_prev_dir"; then
    echo 'Unable to remove superseded MITM CA child certificate directory; transaction rollback required' >&2
    return 1
  fi
  return 0
}

trust_ca() {
  ensure_runtime_dir || { echo 'Unable to prepare private MITM runtime directory' >&2; return 1; }
  [ -x "$BIN" ] || { echo 'MITM engine binary missing' >&2; return 2; }
  [ -f "$CAID" ] && [ -d "$TEMPLATE" ] && [ -f "$CERTMGR" ] || { echo 'CA template/index/certmgr missing' >&2; return 2; }
  _init_out=$("$BIN" -mode init-ca -dir "$DIR" 2>&1)
  case "$_init_out" in
    *'CA subject mismatch'*)
      echo 'CA subject mismatch; refusing implicit key rotation. Run mitm-engine.sh rotate-ca explicitly, then review and enable trust with trust-ca.' >&2
      return 1
      ;;
    *)
      case "$_init_out" in *'"ok":true'*) : ;; *) echo "CA initialization failed: $_init_out" >&2; return 1 ;; esac
      ;;
  esac
  _runtime_fp256=$(ca_fingerprint256 "$DIR/ca.pem")
  [ -n "$_runtime_fp256" ] || { echo 'Unable to calculate full SHA-256 fingerprint for local CA' >&2; return 1; }
  _fp=$(printf '%s' "$_runtime_fp256" | cut -c1-16)
  [ -n "$_fp" ] || { echo 'Unable to fingerprint local CA' >&2; return 1; }
  _line=$(grep -v '^#' "$CAID" | awk -F'|' '$2=="pg_mitm_ca" {print; exit}')
  [ -n "$_line" ] || { echo 'pg_mitm_ca index entry missing' >&2; return 1; }
  _h_old=$(printf '%s\n' "$_line" | awk -F'|' '{print $5}')
  _h_new=$(printf '%s\n' "$_line" | awk -F'|' '{print $6}')
  case "$_h_old:$_h_new" in *[!0-9a-fA-F:.]*|:*|*:) echo 'Invalid CA hash index' >&2; return 1 ;; esac

  _bk="$DIR/trust-backup"
  # A leftover backup can indicate an interrupted trust transaction. Never
  # erase it automatically: preserve recovery data and require manual review.
  if [ -e "$_bk" ]; then
    echo 'Existing CA trust backup found; refusing to overwrite recovery data. Review $DIR/trust-backup before retrying.' >&2
    return 1
  fi
  # Build the backup in a private staging directory, then publish it atomically.
  # A failed copy must not leave a partial trust-backup that blocks every retry.
  _bk_stage="$DIR/trust-backup.tmp.$$"
  [ ! -e "$_bk_stage" ] || { echo 'Temporary CA backup path already exists; refusing to overwrite it' >&2; return 1; }
  if ! mkdir -p "$_bk_stage/template"; then
    echo 'Unable to create temporary CA backup directory' >&2
    return 1
  fi
  chmod 700 "$_bk_stage" 2>/dev/null
  if ! cp -p "$CAID" "$_bk_stage/ca-index" ||
     ! cp -p "$TEMPLATE/$_h_old.0" "$TEMPLATE/$_h_new.0" "$_bk_stage/template/" 2>/dev/null; then
    rm -rf "$_bk_stage"
    echo 'Unable to back up CA index/template; no trust changes were applied' >&2
    return 1
  fi
  if [ -d "$CHILD" ] && ! cp -R "$CHILD" "$_bk_stage/child"; then
    rm -rf "$_bk_stage"
    echo 'Unable to back up existing CA child module; no trust changes were applied' >&2
    return 1
  fi
  if ! mv "$_bk_stage" "$_bk"; then
    rm -rf "$_bk_stage"
    echo 'Unable to publish complete CA trust backup; no trust changes were applied' >&2
    return 1
  fi

  _tmp="$DIR/ca.$$.pem"
  cp "$DIR/ca.pem" "$_tmp" && chmod 644 "$_tmp" || { rm -rf "$_bk" "$_tmp"; return 1; }
  if ! cp "$_tmp" "$TEMPLATE/$_h_old.0.tmp.$$" || ! cp "$_tmp" "$TEMPLATE/$_h_new.0.tmp.$$"; then
    rm -f "$_tmp" "$TEMPLATE/"*.tmp.$$; rm -rf "$_bk"; return 1
  fi
  chmod 644 "$TEMPLATE/$_h_old.0.tmp.$$" "$TEMPLATE/$_h_new.0.tmp.$$"
  mv -f "$TEMPLATE/$_h_old.0.tmp.$$" "$TEMPLATE/$_h_old.0" && mv -f "$TEMPLATE/$_h_new.0.tmp.$$" "$TEMPLATE/$_h_new.0" || {
    rm -f "$_tmp"
    if restore_trust_backup "$_bk"; then :; else echo 'CA trust rollback incomplete; recovery backup preserved at trust-backup' >&2; fi
    return 1
  }
  _idx_tmp="$DIR/ca-index.$$.tmp"
  awk -F'|' -v fp="$_fp" 'BEGIN{OFS="|"} /^#/ {print; next} $2=="pg_mitm_ca" {$3=fp} {print}' "$CAID" > "$_idx_tmp" || {
    rm -f "$_tmp" "$_idx_tmp"
    if restore_trust_backup "$_bk"; then :; else echo 'CA index generation rollback incomplete; recovery backup preserved at trust-backup' >&2; fi
    return 1;
  }
  if ! mv -f "$_idx_tmp" "$CAID"; then
    rm -f "$_tmp"
    if restore_trust_backup "$_bk"; then :; else echo 'CA index commit rollback incomplete; recovery backup preserved at trust-backup' >&2; fi
    return 1
  fi
  rm -f "$_tmp"
  if ! sync_runtime_cert_to_child; then
    if restore_trust_backup "$_bk"; then
      echo 'Runtime CA child-module sync failed; previous certificate/index/child restored' >&2
    else
      echo 'Runtime CA child-module sync failed; rollback incomplete, recovery backup preserved at trust-backup' >&2
    fi
    return 1
  fi
  if sh "$CERTMGR" builtin enable pg_mitm_ca; then
    # The transaction committed. Backups are no longer needed; if cleanup fails,
    # retain them so the next invocation refuses to overwrite recovery data.
    if rm -rf "$_bk"; then
      echo '{"ok":true,"ca":"pg_mitm_ca","trust":"enabled","scope":"system trust store; firewall redirect remains disabled"}'
      return 0
    fi
    echo '{"ok":false,"error":"CA trust enabled but recovery backup cleanup failed; inspect trust-backup"}' >&2
    return 1
  fi
  # Roll back source template/index and the installed child module if certmgr enable fails.
  if restore_trust_backup "$_bk"; then
    echo '{"ok":false,"error":"CA trust enable failed; prior template/index/child restored"}' >&2
  else
    echo '{"ok":false,"error":"CA trust enable failed; rollback incomplete, recovery backup preserved at trust-backup"}' >&2
  fi
  return 1
}

case "${1:-status}" in
  init-ca)
    ensure_runtime_dir || { echo 'Unable to prepare private MITM runtime directory' >&2; exit 1; }
    [ -x "$BIN" ] || { echo '{"ok":false,"error":"MITM engine binary missing for this ABI"}'; exit 2; }
    exec "$BIN" -mode init-ca -dir "$DIR"
    ;;
  trust-ca) trust_ca; exit $? ;;
  rotate-ca)
    ensure_runtime_dir || { echo 'Unable to prepare private MITM runtime directory' >&2; exit 1; }
    [ -x "$BIN" ] || { echo 'MITM engine binary missing' >&2; exit 2; }
    # Rotation is deliberately a separate, explicit operation. The Go engine
    # preserves the previous keypair as .previous files for recovery.
    exec "$BIN" -mode rotate-ca -dir "$DIR"
    ;;
  untrust-ca)
    [ -f "$CERTMGR" ] || exit 2
    sh "$CERTMGR" builtin disable pg_mitm_ca
    ;;
  status)
    if [ ! -x "$BIN" ]; then echo '{"ok":false,"status":"engine-binary-missing","listener":"unknown","traffic_redirect":"not-configured"}'; exit 2; fi
    _engine_status=$("$BIN" -mode status -dir "$DIR" 2>/dev/null) || {
      echo '{"ok":false,"status":"engine-status-failed","listener":"unknown","traffic_redirect":"not-configured"}'; exit 1;
    }
    case "$_engine_status" in *'"ok":true'*) : ;; *) echo '{"ok":false,"status":"ca-status-invalid","listener":"unknown","traffic_redirect":"not-configured"}'; exit 1 ;; esac
    _not_after=$(printf '%s\n' "$_engine_status" | sed -n 's/.*"notAfter":"\([^"]*\)".*/\1/p')
    # Report the independent CA submodule and trust-store state separately from
    # engine health. A running process does not imply the CA is installed/trusted.
    _ca_submodule=unknown
    _ca_system_trust=unknown
    _ca_apex_ns=not-applicable
    if [ -f "$CERTMGR" ]; then
      _ca_list=$(sh "$CERTMGR" builtin list 2>/dev/null)
      _ca_obj=$(printf '%s\n' "$_ca_list" | tr '{' '\n' | grep '"id":"pg_mitm_ca"' | head -n 1)
      if [ -n "$_ca_obj" ]; then
        case "$_ca_obj" in *'"released":1'*) _ca_submodule=released ;; *'"released":0'*) _ca_submodule=missing ;; esac
        case "$_ca_obj" in *'"disabled":1'*) _ca_submodule=disabled ;; esac
        case "$_ca_obj" in
          *'"apex":1'*)
            _ca_apex_ns=$(printf '%s\n' "$_ca_obj" | sed -n 's/.*"apex_ns":"\([^"]*\)".*/\1/p')
            [ -n "$_ca_apex_ns" ] || _ca_apex_ns=unverified
            ;;
        esac
      fi
    fi
    # A hash-named file alone is not proof that this CA is trusted: collisions
    # can put another certificate at the same filename. Compare the actual DER
    # SHA-256 fingerprint of the live system/APEX trust-store entries.
    _expected_fp=$(ca_fingerprint256 "$DIR/ca.pem")
    _trust_view=/system/etc/security/cacerts
    [ -d /apex/com.android.conscrypt/cacerts ] && _trust_view=/apex/com.android.conscrypt/cacerts
    if [ -n "$_expected_fp" ] && [ -d "$_trust_view" ] && [ -f "$CAID" ]; then
      _h_old=$(grep -v '^#' "$CAID" 2>/dev/null | awk -F'|' '$2=="pg_mitm_ca" {print $5; exit}')
      _h_new=$(grep -v '^#' "$CAID" 2>/dev/null | awk -F'|' '$2=="pg_mitm_ca" {print $6; exit}')
      case "$_h_old:$_h_new" in ''|:*|*:) _h_old=; _h_new= ;; esac
      if [ -n "$_h_old" ] && [ -n "$_h_new" ]; then
        _ca_system_trust=absent
      fi
      if [ -n "$_h_old" ] && [ -n "$_h_new" ]; then
        # certmgr publishes into collision slots .0..99. Checking only .0 caused
        # a false "untrusted" state when another stock CA shares this subject hash.
        for _hash in "$_h_old" "$_h_new"; do
          case "$_hash" in ''|*[!0-9a-fA-F]*) continue ;; esac
          _slot=0
          while [ "$_slot" -le 99 ]; do
            _f="$_trust_view/$_hash.$_slot"
            if [ -f "$_f" ]; then
              _actual_fp=$(ca_fingerprint256 "$_f")
              if [ -n "$_actual_fp" ] && [ "$_actual_fp" = "$_expected_fp" ]; then _ca_system_trust=present; break; fi
            fi
            _slot=$((_slot+1))
          done
          [ "$_ca_system_trust" = present ] && break
        done
      fi
      # On Android 14+, shell-visible APEX files alone are insufficient: only
      # certmgr's actual live zygote mount-namespace fingerprint check can
      # confirm the trust view inherited by subsequently launched apps.
      if [ "$_trust_view" = /apex/com.android.conscrypt/cacerts ] && [ "$_ca_apex_ns" != verified ]; then
        _ca_system_trust=absent
      fi
    fi
    _listener=stopped
    _listener_pid=""
    if [ -f "$PID" ]; then
      _p=$(cat "$PID" 2>/dev/null); case "$_p" in ''|*[!0-9]*) _p= ;; esac
      if [ -n "$_p" ] && is_engine_pid "$_p"; then
        _listener_pid=$_p
        if listener_ready; then _listener=running; else _listener=unhealthy; fi
      else
        # Status is observational: do not delete stale PID state while polling.
        # Explicit start/stop lifecycle operations own PID-file cleanup.
        _listener=stopped
      fi
    fi
    # Report the actual redirect-chain state instead of a hard-coded placeholder.
    _redirect=unknown
    if [ -f "$MODDIR/scripts/mitm-redirect.sh" ]; then
      _redirect_json=$(sh "$MODDIR/scripts/mitm-redirect.sh" status 2>/dev/null)
      case "$_redirect_json" in *'"ipv4_redirect":"enabled"'*) _redirect=enabled ;; *'"ipv4_redirect":"disabled"'*) _redirect=disabled ;; esac
    fi
    printf '{"ok":true,"engine":"experimental-http1-mitm","listener":"%s","listener_pid":"%s","ca_not_after":"%s","ca_submodule":"%s","ca_system_trust":"%s","traffic_redirect":"%s","scope":"IPv4 TCP/443 only; TLS HTTP/1.1 only; no QUIC/pinning bypass"}\n' "$_listener" "$_listener_pid" "$_not_after" "$_ca_submodule" "$_ca_system_trust" "$_redirect"
    ;;
  start)
    ensure_runtime_dir || { echo 'Unable to prepare private MITM runtime directory' >&2; exit 1; }
    [ -x "$BIN" ] || { echo 'MITM engine binary missing for this ABI' >&2; exit 2; }
    mkdir -p "$PG/jsruntime/scripts" 2>/dev/null || exit 1
    chmod 700 "$PG/jsruntime" "$PG/jsruntime/scripts" 2>/dev/null || :
    # Publish only explicitly enabled MITM hostnames before serving requests.
    # Without a valid allowlist the Go engine safely passes TLS through instead
    # of terminating arbitrary HTTPS traffic.
    if [ -x "$MODDIR/scripts/sync-mitm-hosts.sh" ]; then
      _hosts_out=$(FX_MODDIR="$MODDIR" PG="$PG" sh "$MODDIR/scripts/sync-mitm-hosts.sh" 2>&1)
      _hosts_rc=$?
      printf '%s\n' "$_hosts_out" >>"$LOG"
      [ "$_hosts_rc" -eq 0 ] || echo "MITM hostname sync failed; previous allowlist retained where possible" >>"$LOG"
    fi
    # Publish imported URL Rewrite rules atomically before serving requests.
    # A sync failure keeps the last known-good manifest and is logged; it does
    # not turn path-scoped rules into domain-wide blocks.
    if [ -x "$MODDIR/scripts/sync-urlrewrite.sh" ]; then
      _rw_out=$(FX_MODDIR="$MODDIR" PG="$PG" sh "$MODDIR/scripts/sync-urlrewrite.sh" 2>&1)
      _rw_rc=$?
      printf '%s\n' "$_rw_out" >>"$LOG"
      [ "$_rw_rc" -eq 0 ] || echo "URL Rewrite sync failed; previous manifest retained where possible" >>"$LOG"
    fi
    # Refresh enabled script subscriptions before the engine snapshots its hook list.
    # Failure is logged but does not disable ordinary HTTPS forwarding or replace
    # a last-known-good script; the sync helper rejects scripts lacking explicit
    # FX-SCRIPT-TYPE / FX-SCRIPT-MATCH metadata.
    if [ -x "$MODDIR/scripts/jsruntime/sync-subs.sh" ]; then
      _sync_out=$(sh "$MODDIR/scripts/jsruntime/sync-subs.sh" 2>&1)
      _sync_rc=$?
      printf '%s\n' "$_sync_out" >>"$LOG"
      [ "$_sync_rc" -eq 0 ] || echo "script subscription sync failed; retaining valid cached hooks where possible" >>"$LOG"
    fi
    _p=$(cat "$PID" 2>/dev/null); case "$_p" in ''|*[!0-9]*) _p= ;; esac
    if [ -n "$_p" ] && is_engine_pid "$_p"; then
      if wait_for_listener "$_p"; then echo "already running pid=$_p; listener=ready"; exit 0; fi
      echo 'MITM engine process exists but 127.0.0.1:18443 is not listening; refusing to enable redirect' >&2
      exit 1
    fi
    rm -f "$PID"
    "$BIN" -mode init-ca -dir "$DIR" >/dev/null 2>&1 || exit 1
    FX_MODDIR="$MODDIR" PG="$PG" nohup "$BIN" -mode serve -dir "$DIR" -listen 127.0.0.1:18443 >>"$LOG" 2>&1 &
    _p=$!; echo "$_p" > "$PID"; chmod 600 "$PID" 2>/dev/null
    if wait_for_listener "$_p"; then echo "started pid=$_p; listener=127.0.0.1:18443 ready; firewall redirect is separately opt-in"; exit 0; fi
    # Do not leave a failed startup process running indefinitely. Signal only
    # when /proc still proves this PID's argv[0] is our exact engine binary.
    if is_engine_pid "$_p"; then
      kill "$_p" 2>/dev/null || :
      _stop_wait=0
      while [ "$_stop_wait" -lt 3 ] && is_engine_pid "$_p"; do sleep 1; _stop_wait=$((_stop_wait+1)); done
    fi
    if ! is_engine_pid "$_p"; then rm -f "$PID"; fi
    echo 'MITM engine failed listener readiness check; no redirect should be installed; inspect engine.log' >&2
    exit 1
    ;;
  stop)
    # The listener must never be stopped while an owned OUTPUT redirect can
    # still send TCP/443 into its loopback port. Remove the redirect first;
    # if firewall state cannot be inspected/cleaned, fail closed and keep the
    # listener alive so we do not strand device traffic.
    if [ -f "$MODDIR/scripts/mitm-redirect.sh" ]; then
      _stop_redirect_json=$(sh "$MODDIR/scripts/mitm-redirect.sh" status 2>/dev/null)
      case "$_stop_redirect_json" in
        *'"ipv4_redirect":"enabled"'*|*'"ipv4_redirect":"partial"'*|*'"ipv4_redirect":"orphaned-chain"'*)
          if ! sh "$MODDIR/scripts/mitm-redirect.sh" disable-rules >/dev/null 2>&1; then
            echo '{"ok":false,"error":"refusing to stop MITM listener: redirect cleanup failed; listener kept alive"}' >&2
            exit 1
          fi
          ;;
        *'"ipv4_redirect":"unknown"'*)
          echo '{"ok":false,"error":"refusing to stop MITM listener: firewall redirect state is unknown; inspect firewall before retrying"}' >&2
          exit 1
          ;;
      esac
    fi
    _p=$(cat "$PID" 2>/dev/null); case "$_p" in ''|*[!0-9]*) _p= ;; esac
    _owned=0
    if [ -n "$_p" ] && is_engine_pid "$_p"; then
      _owned=1
      kill "$_p" 2>/dev/null || :
      # Wait briefly for SIGTERM; only force-kill if cmdline still proves ownership.
      _wait=0
      while [ "$_wait" -lt 10 ]; do
        if ! is_engine_pid "$_p"; then
          _owned=0; break
        fi
        sleep 0.2 2>/dev/null || sleep 1
        _wait=$((_wait+1))
      done
      if [ "$_owned" = 1 ] && is_engine_pid "$_p"; then
        kill -9 "$_p" 2>/dev/null || :
        # SIGKILL delivery and /proc disappearance are asynchronous. Recheck
        # ownership for a bounded interval before deciding that shutdown failed.
        _kill_wait=0
        while [ "$_kill_wait" -lt 10 ]; do
          if ! is_engine_pid "$_p"; then
            _owned=0; break
          fi
          sleep 0.2 2>/dev/null || sleep 1
          _kill_wait=$((_kill_wait+1))
        done
      fi
    fi
    # Keep the PID file if the owned process is still alive. Removing it before
    # the final liveness check loses the only lifecycle handle and makes a later
    # retry harder after a failed shutdown.
    if [ -n "$_p" ] && is_engine_pid "$_p"; then
      echo '{"ok":false,"error":"owned engine process could not be stopped; PID file retained for retry"}' >&2; exit 1
    fi
    rm -f "$PID"
    _redirect=unknown
    if [ -f "$MODDIR/scripts/mitm-redirect.sh" ]; then
      _redirect_json=$(sh "$MODDIR/scripts/mitm-redirect.sh" status 2>/dev/null)
      case "$_redirect_json" in *'"ipv4_redirect":"enabled"'*) _redirect=enabled ;; *'"ipv4_redirect":"disabled"'*) _redirect=disabled ;; *'"ipv4_redirect":"partial"'*) _redirect=partial ;; esac
    fi
    printf '{"ok":true,"listener":"stopped","traffic_redirect":"%s"}\n' "$_redirect"
    ;;
  *) echo 'usage: mitm-engine.sh init-ca|rotate-ca|trust-ca|untrust-ca|status|start|stop' >&2; exit 2 ;;
esac
