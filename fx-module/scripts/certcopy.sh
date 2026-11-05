#!/system/bin/sh
# Shared fail-closed helper for adding enabled CA submodule files to an overlay.
# Usage: ca_copy_submodule_certs <source-directory> <destination-directory> <label>
ca_cert_files_identical() {
  _cci_a="$1"; _cci_b="$2"
  [ -f "$_cci_a" ] && [ -f "$_cci_b" ] || return 1
  command -v cmp >/dev/null 2>&1 || return 2
  cmp -s "$_cci_a" "$_cci_b"
}

# Add only the exact certificate, never overwrite another certificate with the
# same subject hash. Android's hash-dir lookup supports collision slots .0.. .N.
ca_copy_submodule_certs() {
  _cc_srcdir="$1"; _cc_dest="$2"; _cc_label="$3"; _cc_count=0
  [ -d "$_cc_srcdir" ] && [ -d "$_cc_dest" ] || {
    echo "cert: ERROR $_cc_label source/destination missing" >&2; return 1;
  }
  for _cc_src in "$_cc_srcdir/"*.0; do
    [ -f "$_cc_src" ] || continue
    _cc_base=${_cc_src##*/}; _cc_base=${_cc_base%.0}
    case "$_cc_base" in ''|*[!0-9a-fA-F]*) echo "cert: ERROR invalid Android subject hash filename: $_cc_src" >&2; return 1 ;; esac
    _cc_first_free=''; _cc_duplicate=0; _cc_n=0
    while [ "$_cc_n" -le 99 ]; do
      _cc_slot="$_cc_dest/$_cc_base.$_cc_n"
      if [ -f "$_cc_slot" ]; then
        if ca_cert_files_identical "$_cc_src" "$_cc_slot"; then
          _cc_duplicate=1
        else
          _cc_cmp_rc=$?
          [ "$_cc_cmp_rc" -eq 1 ] || { echo "cert: ERROR cannot compare CA collision slot $_cc_slot" >&2; return 1; }
        fi
      elif [ ! -e "$_cc_slot" ] && [ -z "$_cc_first_free" ]; then
        _cc_first_free="$_cc_slot"
      fi
      _cc_n=$((_cc_n+1))
    done
    if [ "$_cc_duplicate" = 1 ]; then
      _cc_count=$((_cc_count+1)); continue
    fi
    [ -n "$_cc_first_free" ] || { echo "cert: ERROR Android CA collision chain exhausted for $_cc_base ($_cc_label)" >&2; return 1; }
    _cc_tmp="$_cc_first_free.tmp.$$"
    if ! cp -p "$_cc_src" "$_cc_tmp" 2>/dev/null || ! chmod 644 "$_cc_tmp" 2>/dev/null || ! mv -f "$_cc_tmp" "$_cc_first_free" 2>/dev/null; then
      rm -f "$_cc_tmp" 2>/dev/null
      echo "cert: ERROR unable to publish collision-safe CA slot $_cc_first_free ($_cc_label)" >&2
      return 1
    fi
    _cc_count=$((_cc_count+1))
  done
  if [ "$_cc_count" -lt 1 ]; then
    echo "cert: ERROR 启用的子模块在 $_cc_srcdir 中没有可复制的 .0 证书（$_cc_label）" >&2
    return 1
  fi
  return 0
}

# Remove only a byte-identical certificate from an overlay and compact its
# collision chain. Never rm hash.0 blindly: that slot may be a stock system CA.
ca_remove_submodule_certs() {
  _cr_srcdir="$1"; _cr_dest="$2"; _cr_label="$3"
  CA_REMOVED_CERT_COUNT=0
  [ -d "$_cr_srcdir" ] && [ -d "$_cr_dest" ] || return 0
  for _cr_src in "$_cr_srcdir/"*.0; do
    [ -f "$_cr_src" ] || continue
    _cr_base=${_cr_src##*/}; _cr_base=${_cr_base%.0}
    case "$_cr_base" in ''|*[!0-9a-fA-F]*) echo "cert: ERROR invalid Android subject hash filename: $_cr_src" >&2; return 1 ;; esac
    _cr_n=0; _cr_found=''
    while [ "$_cr_n" -le 99 ]; do
      _cr_slot="$_cr_dest/$_cr_base.$_cr_n"
      if [ -f "$_cr_slot" ]; then
        if ca_cert_files_identical "$_cr_src" "$_cr_slot"; then _cr_found="$_cr_n"; break; else
          _cr_cmp_rc=$?
          [ "$_cr_cmp_rc" -eq 1 ] || { echo "cert: ERROR cannot compare CA collision slot $_cr_slot ($_cr_label)" >&2; return 1; }
        fi
      fi
      _cr_n=$((_cr_n+1))
    done
    [ -n "$_cr_found" ] || continue
    _cr_n=$_cr_found
    _cr_slot="$_cr_dest/$_cr_base.$_cr_n"
    rm -f "$_cr_slot" 2>/dev/null || { echo "cert: ERROR unable to remove own CA slot $_cr_slot ($_cr_label)" >&2; return 1; }
    CA_REMOVED_CERT_COUNT=$((CA_REMOVED_CERT_COUNT+1))
    while [ "$_cr_n" -lt 99 ]; do
      _cr_next_n=$((_cr_n+1)); _cr_next="$_cr_dest/$_cr_base.$_cr_next_n"
      [ -f "$_cr_next" ] || break
      if [ -e "$_cr_slot" ] || ! mv "$_cr_next" "$_cr_slot" 2>/dev/null; then
        echo "cert: ERROR cannot compact CA collision chain $_cr_base ($_cr_label); sync aborted" >&2
        return 1
      fi
      _cr_n=$_cr_next_n
      _cr_slot="$_cr_dest/$_cr_base.$_cr_n"
    done
  done
  return 0
}
