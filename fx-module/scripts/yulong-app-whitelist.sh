#!/system/bin/sh
# Yulong 7.0.1 application whitelist migrated into FX.
# Selected packages bypass FX ad/DNS filtering through the existing single
# sing-box TUN (exclude_uid) or the external-VPN Root DNS Proxy UID allowlist.
# Independent from FX's proxy route list and the network-blocking firewall.
set -eu

MP=${MP:-}
if [ -z "$MP" ]; then
  for d in /data/adb/modules/privacyguard /data/adb/modules_update/privacyguard /data/adb/modules/privacy_guard /data/adb/modules/pg; do
    if [ -s "$d/module.prop" ] && grep -q '^id=privacyguard$' "$d/module.prop" 2>/dev/null; then MP="$d"; break; fi
  done
fi
[ -n "$MP" ] && [ -s "$MP/module.prop" ] || { echo "FX module is not installed" >&2; exit 20; }
PG=${PG:-/data/adb/privacyguard}
CONF=${CONF:-$PG/settings.conf}
LOCK=${LOCK:-$PG/yulong-app-whitelist.lock}
_YW_TEMP=
_YW_BACKUP=
_YW_RESTORE=
_YW_PID_TEMP=
_YW_PACKAGES=
umask 077

# Reject symlinked ancestors before creating or reading the private FX state.
# Configuration and lock paths are fixed direct children of PG.
_yw_validate_parent_chain() {
  _yw_candidate=$1
  case "$_yw_candidate" in /*) : ;; *) return 1 ;; esac
  case "$_yw_candidate" in /|*/|*//* ) return 1 ;; esac
  _yw_final=${_yw_candidate##*/}
  case "$_yw_final" in ''|.|..) return 1 ;; esac
  _yw_parent=${_yw_candidate%/*}
  [ -n "$_yw_parent" ] || _yw_parent=/
  _yw_rest=${_yw_parent#/}
  _yw_walk=
  while [ -n "$_yw_rest" ]; do
    case "$_yw_rest" in
      */*) _yw_component=${_yw_rest%%/*}; _yw_rest=${_yw_rest#*/} ;;
      *) _yw_component=$_yw_rest; _yw_rest= ;;
    esac
    case "$_yw_component" in ''|.|..) return 1 ;; esac
    _yw_walk="$_yw_walk/$_yw_component"
    [ -d "$_yw_walk" ] && [ ! -L "$_yw_walk" ] || return 1
  done
  return 0
}

_yw_validate_parent_chain "$PG" || {
  echo "FX whitelist state directory has a missing or unsafe parent" >&2
  exit 21
}
[ ! -L "$PG" ] || { echo "FX whitelist state directory is unsafe" >&2; exit 21; }
if [ ! -e "$PG" ]; then
  mkdir "$PG" || { echo "cannot create FX whitelist state directory" >&2; exit 21; }
fi
[ -d "$PG" ] && [ ! -L "$PG" ] || { echo "FX whitelist state directory is unsafe" >&2; exit 21; }
[ "$CONF" = "$PG/settings.conf" ] || { echo "FX whitelist settings path must be inside PG" >&2; exit 21; }
[ "$LOCK" = "$PG/yulong-app-whitelist.lock" ] || { echo "FX whitelist lock path must be inside PG" >&2; exit 21; }
[ -f "$CONF" ] && [ ! -L "$CONF" ] || { echo "FX settings.conf missing or unsafe" >&2; exit 21; }
[ ! -L "$LOCK" ] || { echo "FX whitelist lock path is unsafe" >&2; exit 21; }
[ ! -e "$LOCK" ] || [ -d "$LOCK" ] || { echo "FX whitelist lock path is not a directory" >&2; exit 21; }

valid_package() {
  case "$1" in ''|*[!A-Za-z0-9_.-]*) return 1 ;; esac
  printf '%s\n' "$1" | grep -Eq '^[A-Za-z0-9_]+([.][A-Za-z0-9_-]+)+$'
}
read_rows() {
  awk -F'|' '
    $0=="[list:yulong_app_whitelist]" {inlist=1; next}
    /^\[/ {inlist=0}
    inlist && NF>=3 &&
      $1 ~ /^[A-Za-z0-9_]+([.][A-Za-z0-9_-]+)+$/ &&
      ($3=="0" || $3=="1") {print $1 "|" $2 "|" $3}
  ' "$CONF"
}
write_item() {
  pkg="$1"; enabled="$2"
  tmp=$(mktemp "$CONF.yulong-white.XXXXXX") || return 1
  _YW_TEMP=$tmp
  awk -F'|' -v OFS='|' -v pkg="$pkg" -v enabled="$enabled" '
    BEGIN {inlist=0; seen=0; inserted=0}
    $0=="[list:yulong_app_whitelist]" {
      if(inlist && !inserted && enabled=="1"){print pkg,pkg,enabled;inserted=1}
      inlist=1;seen=1;print;next
    }
    /^\[/ {
      if(inlist && !inserted && enabled=="1"){print pkg,pkg,enabled;inserted=1}
      inlist=0;print;next
    }
    inlist && $1==pkg {
      if(enabled=="1" && !inserted){print pkg,pkg,enabled;inserted=1}
      next
    }
    {print}
    END {
      if(inlist && !inserted && enabled=="1"){print pkg,pkg,enabled;inserted=1}
      if(!seen && enabled=="1"){print "";print "[list:yulong_app_whitelist]";print pkg,pkg,enabled}
    }
  ' "$CONF" > "$tmp" || { rm -f "$tmp"; _YW_TEMP=; return 1; }
  if [ -s "$tmp" ] && [ -f "$tmp" ] && [ ! -L "$tmp" ] \
      && [ -f "$CONF" ] && [ ! -L "$CONF" ] \
      && chmod 600 "$tmp" && mv -f "$tmp" "$CONF"; then
    _YW_TEMP=
    return 0
  fi
  rm -f "$tmp"
  _YW_TEMP=
  return 1
}
with_lock() {
  tries=0
  [ ! -L "$LOCK" ] || { echo "FX whitelist lock path is unsafe" >&2; return 10; }
  while ! mkdir "$LOCK" 2>/dev/null; do
    [ ! -L "$LOCK" ] && [ -d "$LOCK" ] || { echo "FX whitelist lock path is unsafe" >&2; return 10; }
    [ ! -L "$LOCK/pid" ] || { echo "FX whitelist lock PID path is unsafe" >&2; return 10; }
    if [ -e "$LOCK/pid" ] && [ ! -f "$LOCK/pid" ]; then
      echo "FX whitelist lock PID file is unsafe" >&2
      return 10
    fi
    owner="$(cat "$LOCK/pid" 2>/dev/null || true)"
    case "$owner" in
      ''|*[!0-9]*)
        # A process may be between mkdir and writing its PID. Give that short
        # critical section time to finish before treating a PID-less lock stale.
        if [ ! -e "$LOCK/pid" ] && [ "$tries" -ge 3 ]; then
          rmdir "$LOCK" 2>/dev/null || :
        fi
        ;;
      *)
        if ! kill -0 "$owner" 2>/dev/null; then
          rm -f "$LOCK/pid" 2>/dev/null || :
          rmdir "$LOCK" 2>/dev/null || :
        fi
        ;;
    esac
    tries=$((tries+1))
    [ "$tries" -lt 20 ] || { echo "app whitelist update is busy" >&2; return 10; }
    sleep 1
  done
  if [ -L "$LOCK/pid" ]; then
    rmdir "$LOCK" 2>/dev/null || :
    echo "FX whitelist lock PID path is unsafe" >&2
    return 10
  fi
  _YW_PID_TEMP=$(mktemp "$LOCK/pid.XXXXXX") || {
    rmdir "$LOCK" 2>/dev/null || :
    echo "cannot create private whitelist lock owner file" >&2
    return 10
  }
  if ! printf '%s\n' "$$" > "$_YW_PID_TEMP" || ! chmod 600 "$_YW_PID_TEMP" \
      || [ -L "$LOCK/pid" ] || ! mv -f "$_YW_PID_TEMP" "$LOCK/pid"; then
    rm -f "$_YW_PID_TEMP"
    _YW_PID_TEMP=
    rmdir "$LOCK" 2>/dev/null || :
    echo "cannot record app whitelist lock owner" >&2
    return 10
  fi
  _YW_PID_TEMP=
  cleanup_lock() {
    [ -z "$_YW_TEMP" ] || rm -f "$_YW_TEMP" 2>/dev/null || :
    [ -z "$_YW_BACKUP" ] || rm -f "$_YW_BACKUP" 2>/dev/null || :
    [ -z "$_YW_RESTORE" ] || rm -f "$_YW_RESTORE" 2>/dev/null || :
    [ -z "$_YW_PID_TEMP" ] || rm -f "$_YW_PID_TEMP" 2>/dev/null || :
    [ -z "$_YW_PACKAGES" ] || rm -f "$_YW_PACKAGES" 2>/dev/null || :
    # The lock path may have been replaced while this transaction ran.
    # Release only the exact private lock directory whose owner is still us.
    if [ ! -L "$LOCK" ] && [ -d "$LOCK" ] &&
        [ ! -L "$LOCK/pid" ] && [ -f "$LOCK/pid" ] &&
        [ "$(cat "$LOCK/pid" 2>/dev/null || true)" = "$" ]; then
      rm -f "$LOCK/pid" 2>/dev/null || :
      rmdir "$LOCK" 2>/dev/null || :
    fi
  }
  # Keep the lock until the transaction shell has actually exited. A signal
  # must not run cleanup and then resume mutation without owning the lock.
  trap cleanup_lock EXIT
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM
  "$@"
}
mutate_transaction() {
  enabled="$1"; pkg="$2"
  [ -f "$CONF" ] && [ ! -L "$CONF" ] || { echo "FX settings.conf missing or unsafe" >&2; return 21; }
  _YW_BACKUP=$(mktemp "$CONF.yulong-white-rollback.XXXXXX") || return 1
  backup=$_YW_BACKUP
  if ! cat "$CONF" > "$backup" || ! chmod 600 "$backup"; then
    rm -f "$backup"; _YW_BACKUP=; return 1
  fi
  if ! write_item "$pkg" "$enabled"; then
    rm -f "$backup"; _YW_BACKUP=; return 1
  fi
  if sh "$MP/scripts/apply.sh" fast; then
    rm -f "$backup"; _YW_BACKUP=
    echo "applied=1"
    return 0
  fi
  _YW_RESTORE=$(mktemp "$CONF.restore.XXXXXX") || {
    rm -f "$backup"; _YW_BACKUP=
    echo "unable to create private whitelist rollback file" >&2
    return 11
  }
  if cat "$backup" > "$_YW_RESTORE" && chmod 600 "$_YW_RESTORE" \
      && [ -f "$CONF" ] && [ ! -L "$CONF" ] \
      && [ -f "$_YW_RESTORE" ] && [ ! -L "$_YW_RESTORE" ] \
      && mv -f "$_YW_RESTORE" "$CONF"; then
    _YW_RESTORE=
  else
    rm -f "$_YW_RESTORE" "$backup"
    _YW_RESTORE=; _YW_BACKUP=
    echo "whitelist config rollback failed" >&2
    return 11
  fi
  sh "$MP/scripts/apply.sh" fast >/dev/null 2>&1 || echo "previous config restored; runtime reconcile failed" >&2
  rm -f "$backup"; _YW_BACKUP=
  echo "apply failed; previous whitelist restored" >&2
  return 1
}
mutate_batch_transaction() {
  mode="$1"; shift
  case "$mode" in add|remove) ;; *) return 2 ;; esac
  [ "$#" -gt 0 ] || { echo "batch whitelist operation requires at least one package" >&2; return 2; }
  [ -f "$CONF" ] && [ ! -L "$CONF" ] || { echo "FX settings.conf missing or unsafe" >&2; return 21; }
  _YW_PACKAGES=$(mktemp "$PG/yulong-app-whitelist-batch.XXXXXX") || return 1
  for pkg in "$@"; do
    valid_package "$pkg" || {
      rm -f "$_YW_PACKAGES"; _YW_PACKAGES=
      echo "invalid package name in batch whitelist request" >&2
      return 2
    }
    if grep -F -x -q "$pkg" "$_YW_PACKAGES"; then
      rm -f "$_YW_PACKAGES"; _YW_PACKAGES=
      echo "duplicate package in batch whitelist request: $pkg" >&2
      return 2
    fi
    printf '%s\n' "$pkg" >> "$_YW_PACKAGES" || {
      rm -f "$_YW_PACKAGES"; _YW_PACKAGES=
      return 1
    }
  done
  chmod 600 "$_YW_PACKAGES" || {
    rm -f "$_YW_PACKAGES"; _YW_PACKAGES=
    return 1
  }
  _YW_BACKUP=$(mktemp "$CONF.yulong-white-rollback.XXXXXX") || {
    rm -f "$_YW_PACKAGES"; _YW_PACKAGES=; return 1;
  }
  if ! cat "$CONF" > "$_YW_BACKUP" || ! chmod 600 "$_YW_BACKUP"; then
    rm -f "$_YW_BACKUP" "$_YW_PACKAGES"
    _YW_BACKUP=; _YW_PACKAGES=
    return 1
  fi
  _YW_TEMP=$(mktemp "$CONF.yulong-white-batch.XXXXXX") || {
    rm -f "$_YW_BACKUP" "$_YW_PACKAGES"
    _YW_BACKUP=; _YW_PACKAGES=; return 1;
  }
  if ! awk -F'|' -v OFS='|' -v mode="$mode" '
    function emit_missing(pkg) {
      if(mode!="add") return
      for(pkg in wanted) if(!written[pkg]) {
        print pkg,pkg,1
        written[pkg]=1
      }
    }
    FNR==NR {
      if($1 ~ /^[A-Za-z0-9_]+([.][A-Za-z0-9_-]+)+$/) wanted[$1]=1
      next
    }
    $0=="[list:yulong_app_whitelist]" {
      if(inlist) emit_missing()
      inlist=1; seen=1; print; next
    }
    substr($0,1,1)=="[" {
      inlist=0; print; next
    }
    inlist && ($1 in wanted) {
      if(mode=="add" && !written[$1]) {
        print $1,$1,1
        written[$1]=1
      }
      next
    }
    {print}
    END {
      if(inlist) emit_missing()
      if(!seen && mode=="add") {
        print ""
        print "[list:yulong_app_whitelist]"
        emit_missing()
      }
    }
  ' "$_YW_PACKAGES" "$CONF" > "$_YW_TEMP"; then
    rm -f "$_YW_TEMP" "$_YW_BACKUP" "$_YW_PACKAGES"
    _YW_TEMP=; _YW_BACKUP=; _YW_PACKAGES=
    echo "unable to stage batch app whitelist update; configuration unchanged" >&2
    return 1
  fi
  if [ ! -s "$_YW_TEMP" ] || [ ! -f "$_YW_TEMP" ] || [ -L "$_YW_TEMP" ]; then
    rm -f "$_YW_TEMP" "$_YW_BACKUP" "$_YW_PACKAGES"
    _YW_TEMP=; _YW_BACKUP=; _YW_PACKAGES=
    echo "batch app whitelist output is invalid" >&2
    return 1
  fi
  if [ ! -L "$_YW_TEMP" ] && [ -f "$CONF" ] && [ ! -L "$CONF" ] \
      && chmod 600 "$_YW_TEMP" && mv -f "$_YW_TEMP" "$CONF"; then
    _YW_TEMP=
  else
    rm -f "$_YW_TEMP" "$_YW_BACKUP" "$_YW_PACKAGES"
    _YW_TEMP=; _YW_BACKUP=; _YW_PACKAGES=
    echo "atomic batch app whitelist update failed; configuration unchanged" >&2
    return 1
  fi
  rm -f "$_YW_PACKAGES"; _YW_PACKAGES=
  if sh "$MP/scripts/apply.sh" fast; then
    rm -f "$_YW_BACKUP"; _YW_BACKUP=
    echo "updated=$# applied=1"
    return 0
  fi
  _YW_RESTORE=$(mktemp "$CONF.restore.XXXXXX") || {
    rm -f "$_YW_BACKUP"; _YW_BACKUP=
    echo "unable to create batch whitelist rollback file" >&2
    return 11
  }
  if cat "$_YW_BACKUP" > "$_YW_RESTORE" && chmod 600 "$_YW_RESTORE" \
      && [ -f "$CONF" ] && [ ! -L "$CONF" ] \
      && [ -f "$_YW_RESTORE" ] && [ ! -L "$_YW_RESTORE" ] \
      && mv -f "$_YW_RESTORE" "$CONF"; then
    _YW_RESTORE=
  else
    rm -f "$_YW_RESTORE" "$_YW_BACKUP"
    _YW_RESTORE=; _YW_BACKUP=
    echo "batch whitelist rollback failed" >&2
    return 11
  fi
  sh "$MP/scripts/apply.sh" fast >/dev/null 2>&1 || echo "previous whitelist restored; runtime reconcile failed" >&2
  rm -f "$_YW_BACKUP"; _YW_BACKUP=
  echo "batch whitelist apply failed; previous selection restored" >&2
  return 1
}

prune_transaction() {
  [ -f "$CONF" ] && [ ! -L "$CONF" ] || { echo "FX settings.conf missing or unsafe" >&2; return 21; }
  _snapshot=$(cmd package list packages -U 2>/dev/null) || {
    echo "cannot read PackageManager snapshot; app whitelist unchanged" >&2; return 1;
  }
  [ -n "$_snapshot" ] || { echo "PackageManager returned an empty snapshot; app whitelist unchanged" >&2; return 1; }
  _YW_PACKAGES=$(mktemp "$PG/yulong-app-whitelist-packages.XXXXXX") || return 1
  if ! printf '%s\n' "$_snapshot" | awk '
    $1 ~ /^package:[A-Za-z0-9_.-]+$/ {
      pkg=substr($1,9); uid_ok=0
      for(i=2;i<=NF;i++) if($i ~ /^uid:[0-9]+$/) {uid_ok=1; break}
      if(uid_ok && pkg ~ /^[A-Za-z0-9_]+([.][A-Za-z0-9_-]+)+$/) {
        if(!seen[pkg]++) print pkg
        valid++
      }
    }
    END {exit !valid}
  ' > "$_YW_PACKAGES"; then
    rm -f "$_YW_PACKAGES"; _YW_PACKAGES=
    echo "PackageManager snapshot is malformed; app whitelist unchanged" >&2
    return 1
  fi
  [ -s "$_YW_PACKAGES" ] && chmod 600 "$_YW_PACKAGES" || {
    rm -f "$_YW_PACKAGES"; _YW_PACKAGES=
    echo "PackageManager snapshot has no usable package/UID rows; app whitelist unchanged" >&2
    return 1
  }
  _removed=$(awk -F'|' '
    FNR==NR {installed[$1]=1; next}
    $0=="[list:yulong_app_whitelist]" {inside=1; next}
    /^\[/ {inside=0}
    inside && NF>=3 && $1 ~ /^[A-Za-z0-9_]+([.][A-Za-z0-9_-]+)+$/
      && ($3=="0" || $3=="1") && !($1 in installed) {count++}
    END {print count+0}
  ' "$_YW_PACKAGES" "$CONF") || {
    rm -f "$_YW_PACKAGES"; _YW_PACKAGES=; return 1;
  }
  case "$_removed" in ''|*[!0-9]*)
    rm -f "$_YW_PACKAGES"; _YW_PACKAGES=
    echo "invalid stale whitelist count; configuration unchanged" >&2
    return 1
    ;;
  esac
  if [ "$_removed" -eq 0 ]; then
    rm -f "$_YW_PACKAGES"; _YW_PACKAGES=
    echo "removed=0 applied=0"
    return 0
  fi

  _YW_BACKUP=$(mktemp "$CONF.yulong-white-rollback.XXXXXX") || {
    rm -f "$_YW_PACKAGES"; _YW_PACKAGES=; return 1;
  }
  if ! cat "$CONF" > "$_YW_BACKUP" || ! chmod 600 "$_YW_BACKUP"; then
    rm -f "$_YW_BACKUP" "$_YW_PACKAGES"
    _YW_BACKUP=; _YW_PACKAGES=
    echo "unable to snapshot app whitelist before prune" >&2
    return 1
  fi
  _YW_TEMP=$(mktemp "$CONF.yulong-white-prune.XXXXXX") || {
    rm -f "$_YW_BACKUP" "$_YW_PACKAGES"
    _YW_BACKUP=; _YW_PACKAGES=; return 1;
  }
  if ! awk -F'|' '
    FNR==NR {installed[$1]=1; next}
    $0=="[list:yulong_app_whitelist]" {inside=1; print; next}
    /^\[/ {inside=0}
    inside && NF>=3 && $1 ~ /^[A-Za-z0-9_]+([.][A-Za-z0-9_-]+)+$/
      && ($3=="0" || $3=="1") && !($1 in installed) {next}
    {print}
  ' "$_YW_PACKAGES" "$CONF" > "$_YW_TEMP"; then
    rm -f "$_YW_TEMP" "$_YW_BACKUP" "$_YW_PACKAGES"
    _YW_TEMP=; _YW_BACKUP=; _YW_PACKAGES=
    echo "unable to stage app whitelist prune; configuration unchanged" >&2
    return 1
  fi
  if [ ! -s "$_YW_TEMP" ] || [ ! -f "$_YW_TEMP" ] || [ -L "$_YW_TEMP" ] \
      || [ ! -f "$CONF" ] || [ -L "$CONF" ] \
      || ! chmod 600 "$_YW_TEMP" || ! mv -f "$_YW_TEMP" "$CONF"; then
    rm -f "$_YW_TEMP" "$_YW_BACKUP" "$_YW_PACKAGES"
    _YW_TEMP=; _YW_BACKUP=; _YW_PACKAGES=
    echo "atomic app whitelist prune commit failed; configuration unchanged" >&2
    return 1
  fi
  _YW_TEMP=
  rm -f "$_YW_PACKAGES"; _YW_PACKAGES=
  if sh "$MP/scripts/apply.sh" fast; then
    rm -f "$_YW_BACKUP"; _YW_BACKUP=
    echo "removed=$_removed applied=1"
    return 0
  fi
  _YW_RESTORE=$(mktemp "$CONF.restore.XXXXXX") || {
    rm -f "$_YW_BACKUP"; _YW_BACKUP=
    echo "unable to create app whitelist prune rollback file" >&2
    return 11
  }
  if cat "$_YW_BACKUP" > "$_YW_RESTORE" && chmod 600 "$_YW_RESTORE" \
      && [ -f "$CONF" ] && [ ! -L "$CONF" ] \
      && [ -f "$_YW_RESTORE" ] && [ ! -L "$_YW_RESTORE" ] \
      && mv -f "$_YW_RESTORE" "$CONF"; then
    _YW_RESTORE=
  else
    rm -f "$_YW_RESTORE" "$_YW_BACKUP"
    _YW_RESTORE=; _YW_BACKUP=
    echo "app whitelist prune rollback failed" >&2
    return 11
  fi
  sh "$MP/scripts/apply.sh" fast >/dev/null 2>&1 || echo "previous whitelist restored; runtime reconcile failed" >&2
  rm -f "$_YW_BACKUP"; _YW_BACKUP=
  echo "app whitelist apply failed; previous selection restored" >&2
  return 1
}

cmd=${1:-list}
case "$cmd" in
  list)
    echo FXYULONGWHITE1
    read_rows
    ;;
  add)
    [ "$#" -eq 2 ] && valid_package "$2" || { echo "usage: $0 add PACKAGE" >&2; exit 2; }
    with_lock mutate_transaction 1 "$2"
    ;;
  remove)
    [ "$#" -eq 2 ] && valid_package "$2" || { echo "usage: $0 remove PACKAGE" >&2; exit 2; }
    with_lock mutate_transaction 0 "$2"
    ;;
  batch-add|batch-remove)
    [ "$#" -ge 2 ] || { echo "usage: $0 batch-add|batch-remove PACKAGE..." >&2; exit 2; }
    _batch_action="${cmd#batch-}"
    shift
    for _batch_pkg in "$@"; do
      valid_package "$_batch_pkg" || { echo "invalid package in batch whitelist request" >&2; exit 2; }
    done
    with_lock mutate_batch_transaction "$_batch_action" "$@"
    ;;
  prune)
    [ "$#" -eq 1 ] || { echo "usage: $0 prune" >&2; exit 2; }
    with_lock prune_transaction
    ;;
  apply)
    sh "$MP/scripts/apply.sh" fast
    ;;
  *)
    echo "usage: $0 list|add PACKAGE|remove PACKAGE|batch-add PACKAGE...|batch-remove PACKAGE...|prune|apply" >&2
    exit 2
    ;;
esac
