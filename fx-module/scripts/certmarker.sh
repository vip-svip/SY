#!/system/bin/sh
# Commit a mount marker only after bind mount succeeded. If marker publication fails,
# attempt to detach; never remove the overlay source while the target remains mounted.
ca_commit_mount_marker() {
  _cmm_marker="$1"; _cmm_target="$2"; _cmm_overlay="$3"
  _cmm_tmp="${_cmm_marker}.tmp.$$"
  if printf '%s\n' "$_cmm_target" > "$_cmm_tmp" 2>/dev/null && mv -f "$_cmm_tmp" "$_cmm_marker" 2>/dev/null; then
    return 0
  fi
  rm -f "$_cmm_tmp" 2>/dev/null
  umount "$_cmm_target" 2>/dev/null
  if mount 2>/dev/null | grep -Fq " $_cmm_target "; then
    echo "cert: ERROR marker commit failed and mount remains live; preserving overlay $_cmm_overlay" >&2
    return 1
  fi
  rm -rf "$_cmm_overlay" 2>/dev/null
  echo "cert: ERROR marker commit failed; mount detached and temporary overlay removed" >&2
  return 1
}
