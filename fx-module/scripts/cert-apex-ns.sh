#!/system/bin/sh
# Namespace-aware Conscrypt APEX CA overlay helpers.
# These functions are sourced by certmgr.sh. We only unmount mounts recorded by
# per-mount-namespace ownership markers; on ambiguity/failure, preserve source data.

ca_apex_nsenter() {
  if command -v nsenter >/dev/null 2>&1; then
    nsenter "$@"
    return $?
  fi
  if command -v busybox >/dev/null 2>&1; then
    busybox nsenter "$@" 2>/dev/null
    return $?
  fi
  return 127
}

ca_apex_ns_id() {
  _cani_pid="$1"
  [ -r "/proc/$_cani_pid/ns/mnt" ] || return 1
  readlink "/proc/$_cani_pid/ns/mnt" 2>/dev/null | sed -n 's/^mnt:\[\([0-9][0-9]*\)\]$/\1/p'
}

ca_apex_ns_exec() {
  _cane_pid="$1"; shift
  _cane_target_id=$(ca_apex_ns_id "$_cane_pid") || return 1
  _cane_self_id=$(ca_apex_ns_id "$$") || return 1
  if [ "$_cane_target_id" = "$_cane_self_id" ]; then
    "$@"
  else
    ca_apex_nsenter --mount="/proc/$_cane_pid/ns/mnt" -- "$@"
  fi
}

ca_apex_ns_has_mount() {
  _canm_pid="$1"; _canm_target="$2"
  [ -r "/proc/$_canm_pid/mountinfo" ] || return 1
  awk -v target="$_canm_target" '$5 == target { found=1 } END { exit !found }' "/proc/$_canm_pid/mountinfo" 2>/dev/null
}

ca_apex_ns_marker() {
  printf '%s/cacerts-overlay-apex.ns.%s' "$1" "$2"
}

ca_apex_ns_add_candidate() {
  _canc_pid="$1"; _canc_required="$2"; _canc_list="$3"; _canc_seen="$4"
  case "$_canc_pid" in ''|*[!0-9]*) return 0 ;; esac
  [ -r "/proc/$_canc_pid/ns/mnt" ] || return 0
  _canc_id=$(ca_apex_ns_id "$_canc_pid") || return 0
  grep -Fqx "$_canc_id" "$_canc_seen" 2>/dev/null && return 0
  printf '%s\n' "$_canc_id" >> "$_canc_seen" || return 1
  printf '%s|%s|%s\n' "$_canc_id" "$_canc_pid" "$_canc_required" >> "$_canc_list" || return 1
  return 0
}

# Install the overlay into the shell, init, zygote/zygote64 and currently running
# app mount namespaces that expose both source and target. Zygote injection lets
# subsequently forked apps inherit the view; current app namespaces are best-effort.
# Return 1 only when a required namespace (shell/init/zygote) cannot be verified.
ca_apex_ns_mount_all() {
  _can_src="$1"; _can_target="$2"; _can_pg="$3"
  CA_APEX_NS_PARTIAL=0
  [ -d "$_can_src" ] && [ -d "$_can_target" ] || { echo 'cert: APEX namespace source/target missing' >&2; return 1; }
  mkdir -p "$_can_pg" 2>/dev/null || return 1
  _can_list="$_can_pg/.cert-apex-ns-list.$$"
  _can_seen="$_can_pg/.cert-apex-ns-seen.$$"
  (umask 077; : > "$_can_list" && : > "$_can_seen") || return 1
  _can_build_rc=0
  # Prioritize current shell, PID 1, then zygote namespaces so de-duplication
  # cannot accidentally classify a critical namespace as best-effort.
  ca_apex_ns_add_candidate "$$" 1 "$_can_list" "$_can_seen" || _can_build_rc=1
  ca_apex_ns_add_candidate 1 1 "$_can_list" "$_can_seen" || _can_build_rc=1
  for _can_pid in $(pidof zygote 2>/dev/null) $(pidof zygote64 2>/dev/null); do
    ca_apex_ns_add_candidate "$_can_pid" 1 "$_can_list" "$_can_seen" || _can_build_rc=1
  done
  for _can_proc in /proc/[0-9]*; do
    [ -d "$_can_proc" ] || continue
    _can_pid=${_can_proc##*/}
    ca_apex_ns_add_candidate "$_can_pid" 0 "$_can_list" "$_can_seen" || _can_build_rc=1
  done
  if [ "$_can_build_rc" -ne 0 ]; then
    rm -f "$_can_list" "$_can_seen" 2>/dev/null
    echo 'cert: unable to enumerate mount namespaces safely' >&2
    return 1
  fi
  _can_rc=0; _can_zygote_seen=0; _can_zygote_ready=0
  for _can_pid in $(pidof zygote 2>/dev/null) $(pidof zygote64 2>/dev/null); do
    [ -r "/proc/$_can_pid/ns/mnt" ] || continue
    _can_zygote_seen=1
  done
  while IFS='|' read -r _can_id _can_pid _can_required; do
    [ -n "$_can_id" ] && [ -n "$_can_pid" ] || continue
    _can_marker=$(ca_apex_ns_marker "$_can_pg" "$_can_id")
    _can_pid_name=$(tr '\000' '\n' < "/proc/$_can_pid/cmdline" 2>/dev/null | sed -n '1p')
    _can_is_zygote=0
    case "$_can_pid_name" in zygote|zygote64|*/zygote|*/zygote64) _can_is_zygote=1 ;; esac
    [ "$_can_is_zygote" = 1 ] && _can_zygote_seen=1
    # Skip namespaces without the APEX path, but never silently skip a live
    # zygote namespace: that is the primary trust view for app processes.
    if ! ca_apex_ns_exec "$_can_pid" test -d "$_can_target" >/dev/null 2>&1; then
      if [ "$_can_required" = 1 ] && { [ "$_can_pid" = "$$" ] || [ "$_can_pid" = 1 ] || [ "$_can_is_zygote" = 1 ]; }; then
        echo "cert: required namespace $_can_id cannot see $_can_target" >&2; _can_rc=1
      else
        CA_APEX_NS_PARTIAL=1
      fi
      continue
    fi
    if ! ca_apex_ns_exec "$_can_pid" test -d "$_can_src" >/dev/null 2>&1; then
      if [ "$_can_required" = 1 ]; then
        echo "cert: required namespace $_can_id cannot see overlay source $_can_src" >&2; _can_rc=1
      else
        CA_APEX_NS_PARTIAL=1
      fi
      continue
    fi
    if [ -f "$_can_marker" ]; then
      _can_old_src=$(sed -n '1p' "$_can_marker" 2>/dev/null)
      if [ "$_can_old_src" = "$_can_src" ] && ca_apex_ns_has_mount "$_can_pid" "$_can_target"; then
        continue
      fi
      echo "cert: stale namespace marker conflicts with current overlay: $_can_marker" >&2
      [ "$_can_required" = 1 ] && _can_rc=1 || CA_APEX_NS_PARTIAL=1
      continue
    fi
    if ca_apex_ns_has_mount "$_can_pid" "$_can_target"; then
      # Never stack over an unknown module/admin mount in another namespace.
      echo "cert: target already mounted in namespace $_can_id without FX ownership marker; preserving it" >&2
      [ "$_can_required" = 1 ] && _can_rc=1 || CA_APEX_NS_PARTIAL=1
      continue
    fi
    if ! ca_apex_ns_exec "$_can_pid" mount --bind "$_can_src" "$_can_target" 2>/dev/null; then
      echo "cert: bind mount failed in namespace $_can_id" >&2
      [ "$_can_required" = 1 ] && _can_rc=1 || CA_APEX_NS_PARTIAL=1
      continue
    fi
    if ! ca_apex_ns_has_mount "$_can_pid" "$_can_target"; then
      echo "cert: mount command returned success but namespace $_can_id did not expose the APEX bind mount" >&2
      ca_apex_ns_exec "$_can_pid" umount "$_can_target" 2>/dev/null || :
      [ "$_can_required" = 1 ] && _can_rc=1 || CA_APEX_NS_PARTIAL=1
      continue
    fi
    _can_tmp="$_can_marker.tmp.$$"
    if ! { printf '%s\n%s\n' "$_can_src" "$_can_target" > "$_can_tmp"; } 2>/dev/null || ! chmod 600 "$_can_tmp" 2>/dev/null || ! mv -f "$_can_tmp" "$_can_marker" 2>/dev/null; then
      rm -f "$_can_tmp" 2>/dev/null
      ca_apex_ns_exec "$_can_pid" umount "$_can_target" 2>/dev/null || :
      echo "cert: unable to commit namespace ownership marker $_can_marker" >&2
      [ "$_can_required" = 1 ] && _can_rc=1 || CA_APEX_NS_PARTIAL=1
      continue
    fi
  done < "$_can_list"
  # The candidate list is de-duplicated by mount namespace. If PID 1 or the
  # shell represented a namespace shared with zygote, the representative command
  # line is not named zygote and cannot set _can_zygote_ready inside the loop.
  # Verify by resolving every live zygote PID back to its namespace marker.
  _can_zygote_ready=0
  for _can_pid in $(pidof zygote 2>/dev/null) $(pidof zygote64 2>/dev/null); do
    [ -r "/proc/$_can_pid/ns/mnt" ] || continue
    _can_zid=$(ca_apex_ns_id "$_can_pid") || continue
    _can_zmarker=$(ca_apex_ns_marker "$_can_pg" "$_can_zid")
    if [ -f "$_can_zmarker" ] && ca_apex_ns_has_mount "$_can_pid" "$_can_target" && \
       ca_apex_ns_exec "$_can_pid" test -d "$_can_target" >/dev/null 2>&1; then
      _can_zygote_ready=1
      break
    fi
  done
  rm -f "$_can_list" "$_can_seen" 2>/dev/null
  if [ "$_can_zygote_seen" = 1 ] && [ "$_can_zygote_ready" != 1 ]; then
    echo 'cert: no verified Conscrypt overlay in any live zygote namespace' >&2
    _can_rc=1
  fi
  [ "$_can_rc" -eq 0 ] || return 1
  [ "$_can_zygote_seen" = 1 ] || { echo 'cert: zygote not running; cannot verify app certificate trust' >&2; return 1; }
  if [ "$CA_APEX_NS_PARTIAL" = 1 ]; then
    echo 'cert: WARN Conscrypt overlay verified for critical namespaces; one or more extra app namespaces could not be updated' >&2
  fi
  return 0
}

# Remove only namespace mounts created by this helper. A marker for a namespace
# that no longer has any process is stale because the namespace itself is gone.
ca_apex_ns_unmount_all() {
  _cau_target="$1"; _cau_pg="$2"; _cau_legacy_marker="$3"
  _cau_rc=0
  _cau_self_id=$(ca_apex_ns_id "$$" 2>/dev/null)
  for _cau_marker in "$_cau_pg"/cacerts-overlay-apex.ns.*; do
    [ -f "$_cau_marker" ] || continue
    _cau_id=${_cau_marker##*.ns.}
    case "$_cau_id" in ''|*[!0-9]*) echo "cert: invalid APEX namespace marker retained: $_cau_marker" >&2; _cau_rc=1; continue ;; esac
    _cau_pid=''
    for _cau_proc in /proc/[0-9]*; do
      [ -d "$_cau_proc" ] || continue
      _cau_try=${_cau_proc##*/}
      _cau_try_id=$(ca_apex_ns_id "$_cau_try" 2>/dev/null)
      if [ "$_cau_try_id" = "$_cau_id" ]; then _cau_pid=$_cau_try; break; fi
    done
    if [ -z "$_cau_pid" ]; then
      # No process can still reference this namespace; its mount died with it.
      rm -f "$_cau_marker" 2>/dev/null || _cau_rc=1
      continue
    fi
    if ! ca_apex_ns_has_mount "$_cau_pid" "$_cau_target"; then
      rm -f "$_cau_marker" 2>/dev/null || _cau_rc=1
      continue
    fi
    if ! ca_apex_ns_exec "$_cau_pid" umount "$_cau_target" 2>/dev/null; then
      echo "cert: ERROR unable to unmount FX-owned APEX view in namespace $_cau_id; source retained" >&2
      _cau_rc=1
      continue
    fi
    rm -f "$_cau_marker" 2>/dev/null || _cau_rc=1
  done
  # Migration path for pre-namespace-aware releases, whose single marker only
  # described the certmgr caller's namespace.
  if [ -f "$_cau_legacy_marker" ]; then
    if ca_apex_ns_has_mount "$$" "$_cau_target"; then
      if ! umount "$_cau_target" 2>/dev/null; then
        echo 'cert: ERROR legacy APEX mount could not be detached; source retained' >&2
        _cau_rc=1
      fi
    fi
  fi
  # If any live namespace still has the target mounted, its owner/source is now
  # ambiguous. Do not let the caller remove the shared overlay directory.
  if [ "$_cau_rc" -eq 0 ]; then
    for _cau_proc in /proc/[0-9]*; do
      [ -r "$_cau_proc/mountinfo" ] || continue
      _cau_pid=${_cau_proc##*/}
      if ca_apex_ns_has_mount "$_cau_pid" "$_cau_target"; then
        # Mount may belong to another module, but we cannot prove it is not the
        # old FX source without entering and checking that namespace's mount table.
        echo "cert: ERROR an APEX target mount remains in namespace for PID $_cau_pid; preserving overlay and marker" >&2
        _cau_rc=1
        break
      fi
    done
  fi
  [ "$_cau_rc" -eq 0 ] || return 1
  rm -f "$_cau_legacy_marker" 2>/dev/null || return 1
  return 0
}

ca_apex_ns_verify_zygote() {
  _cav_target="$1"; _cav_fp256=$(printf '%s' "$2" | tr 'A-F' 'a-f'); _cav_h1="$3"; _cav_h2="$4"
  case "$_cav_fp256" in ''|*[!0-9a-f]*) return 1 ;; esac
  [ "${#_cav_fp256}" -eq 64 ] || return 1
  _cav_count=0
  for _cav_pid in $(pidof zygote 2>/dev/null) $(pidof zygote64 2>/dev/null); do
    case "$_cav_pid" in ''|*[!0-9]*) continue ;; esac
    [ -r "/proc/$_cav_pid/ns/mnt" ] || continue
    _cav_has=0
    for _cav_hash in "$_cav_h1" "$_cav_h2"; do
      case "$_cav_hash" in ''|*[!0-9a-fA-F]*) continue ;; esac
      _cav_n=0
      while [ "$_cav_n" -le 99 ]; do
        if ca_file_matches256 "/proc/$_cav_pid/root$_cav_target/$_cav_hash.$_cav_n" "$_cav_fp256"; then
          _cav_has=1
          break
        fi
        _cav_n=$((_cav_n+1))
      done
      [ "$_cav_has" = 1 ] && break
    done
    [ "$_cav_has" = 1 ] && _cav_count=$((_cav_count+1))
  done
  [ "$_cav_count" -gt 0 ]
}
